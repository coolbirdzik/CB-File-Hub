// Persistent JSON-lines worker. stdout contains protocol messages only; model
// and decoder diagnostics go to stderr. Each request is bounded to 30 seconds.
#include "json.hpp"
#include "whisper.h"
#include "ggml-backend.h"
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <iostream>
#include <future>
#include <memory>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>
#ifdef _WIN32
#include <windows.h>
#include <fcntl.h>
#include <io.h>
#else
#include <sys/resource.h>
#endif
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/channel_layout.h>
#include <libswresample/swresample.h>
}
using json = nlohmann::json;
using Clock = std::chrono::steady_clock;
static constexpr int rate = 16000;
static double milliseconds(Clock::time_point start) {
    return std::chrono::duration<double, std::milli>(Clock::now() - start).count();
}

struct LanguageMemory {
    std::string source;
    int track = -1, id = -1, stable = 0;
    int64_t start = -1, end = -1, detected_at = -1;
    float confidence = 0;
};
static bool gpu_ready_to_take_over(void* flag) {
    return static_cast<std::atomic<bool>*>(flag)->load(std::memory_order_acquire);
}

struct Audio {
    AVFormatContext* format = nullptr;
    AVCodecContext* codec = nullptr;
    SwrContext* swr = nullptr;
    AVPacket* packet = av_packet_alloc();
    AVFrame* frame = av_frame_alloc();
    Clock::time_point deadline = Clock::now() + std::chrono::seconds(20);
    ~Audio() {
        av_frame_free(&frame); av_packet_free(&packet);
        swr_free(&swr); avcodec_free_context(&codec); avformat_close_input(&format);
    }
};
static void check(int status, const char* operation) {
    if (status < 0) throw std::runtime_error(operation);
}
static int interrupt(void* opaque) {
    return Clock::now() > static_cast<Audio*>(opaque)->deadline;
}

// Decode the selected audio stream at original media speed. Volume, mute and
// video playback rate do not alter recognition or the returned media times.
static std::vector<float> decode(const json& request) {
    Audio a;
    a.format = avformat_alloc_context();
    if (!a.format || !a.packet || !a.frame) throw std::bad_alloc();
    a.format->interrupt_callback = {interrupt, &a};
    const auto source = request.at("source").get<std::string>();
    AVDictionary* options = nullptr;
    av_dict_set(&options, "rw_timeout", "15000000", 0);
    const int opened = avformat_open_input(&a.format, source.c_str(), nullptr, &options);
    av_dict_free(&options);
    check(opened, "Cannot open media audio");
    check(avformat_find_stream_info(a.format, nullptr), "Cannot inspect audio streams");
    int stream = -1, ordinal = 0;
    for (unsigned i = 0; i < a.format->nb_streams; ++i) {
        if (a.format->streams[i]->codecpar->codec_type != AVMEDIA_TYPE_AUDIO) continue;
        if (ordinal++ == request.value("audio_track", 0)) { stream = static_cast<int>(i); break; }
    }
    if (stream < 0) throw std::runtime_error("Selected audio track is unavailable");
    auto* st = a.format->streams[stream];
    const AVCodec* decoder = avcodec_find_decoder(st->codecpar->codec_id);
    if (!decoder) throw std::runtime_error("Audio codec is unsupported");
    a.codec = avcodec_alloc_context3(decoder);
    if (!a.codec) throw std::bad_alloc();
    check(avcodec_parameters_to_context(a.codec, st->codecpar), "Cannot configure audio codec");
    a.codec->thread_count = 2;
    check(avcodec_open2(a.codec, decoder, nullptr), "Cannot initialize audio codec");
#if LIBAVUTIL_VERSION_MAJOR >= 57
    AVChannelLayout mono = AV_CHANNEL_LAYOUT_MONO;
    check(swr_alloc_set_opts2(&a.swr, &mono, AV_SAMPLE_FMT_FLT, rate,
          &a.codec->ch_layout, a.codec->sample_fmt, a.codec->sample_rate, 0, nullptr),
          "Cannot configure audio resampling");
#else
    a.swr = swr_alloc_set_opts(nullptr, AV_CH_LAYOUT_MONO, AV_SAMPLE_FMT_FLT, rate,
        a.codec->channel_layout ? a.codec->channel_layout : av_get_default_channel_layout(a.codec->channels),
        a.codec->sample_fmt, a.codec->sample_rate, 0, nullptr);
    if (!a.swr) throw std::runtime_error("Cannot configure audio resampling");
#endif
    check(swr_init(a.swr), "Cannot initialize audio resampling");
    const int64_t start_ms = std::max<int64_t>(0, request.value("start_ms", int64_t(0)));
    const int duration_ms = std::clamp(request.value("duration_ms", 8000), 1000, 30000);
    const int wanted = duration_ms * rate / 1000;
    const int64_t origin_us = a.format->start_time == AV_NOPTS_VALUE ? 0 : a.format->start_time;
    const int64_t seek_time = av_rescale_q(start_ms * 1000 + origin_us, AV_TIME_BASE_Q, st->time_base);
    if (start_ms > 0) {
        check(av_seek_frame(a.format, stream, seek_time, AVSEEK_FLAG_BACKWARD), "Media audio is not seekable");
        avcodec_flush_buffers(a.codec);
    }
    std::vector<float> pcm(static_cast<size_t>(wanted), 0.0f);
    int filled = 0;
    int64_t next_sample = start_ms * rate / 1000;
    bool done = false;
    auto receive = [&]() {
        while (!done) {
            const int result = avcodec_receive_frame(a.codec, a.frame);
            if (result == AVERROR(EAGAIN) || result == AVERROR_EOF) break;
            check(result, "Audio frame decoding failed");
            const int capacity = static_cast<int>(av_rescale_rnd(
                swr_get_delay(a.swr, a.codec->sample_rate) + a.frame->nb_samples,
                rate, a.codec->sample_rate, AV_ROUND_UP));
            std::vector<float> samples(static_cast<size_t>(capacity));
            uint8_t* out = reinterpret_cast<uint8_t*>(samples.data());
            const int64_t delay = swr_get_delay(a.swr, rate);
            const int n = swr_convert(a.swr, &out, capacity,
                const_cast<const uint8_t**>(a.frame->extended_data), a.frame->nb_samples);
            check(n, "Audio resampling failed");
            int64_t absolute = next_sample;
            if (a.frame->best_effort_timestamp != AV_NOPTS_VALUE) {
                const int64_t us = av_rescale_q(a.frame->best_effort_timestamp, st->time_base, AV_TIME_BASE_Q) - origin_us;
                absolute = av_rescale(us, rate, AV_TIME_BASE) - delay;
            }
            const int64_t offset = absolute - start_ms * rate / 1000;
            if (offset < wanted && offset + n > 0) {
                const int from = static_cast<int>(std::max<int64_t>(0, -offset));
                const int to = static_cast<int>(std::min<int64_t>(n, wanted - offset));
                if (to > from) {
                    // Add the offsets before forming the iterator. A negative
                    // intermediate iterator is UB even when +from restores it.
                    std::copy(samples.begin() + from, samples.begin() + to, pcm.begin() + (offset + from));
                    filled = std::max(filled, static_cast<int>(offset + to));
                }
            }
            next_sample = absolute + n;
            done = offset + n >= wanted;
            av_frame_unref(a.frame);
        }
    };
    int read_status = 0;
    while (!done && (read_status = av_read_frame(a.format, a.packet)) >= 0) {
        if (Clock::now() > a.deadline) throw std::runtime_error("Audio read timed out");
        if (a.packet->stream_index == stream) {
            int status = avcodec_send_packet(a.codec, a.packet);
            if (status == AVERROR(EAGAIN)) { receive(); status = avcodec_send_packet(a.codec, a.packet); }
            check(status, "Cannot feed audio decoder"); receive();
        }
        av_packet_unref(a.packet);
    }
    if (!done && read_status != AVERROR_EOF) check(read_status, "Audio read failed");
    if (!done) { avcodec_send_packet(a.codec, nullptr); receive(); }
    pcm.resize(static_cast<size_t>(filled));
    return pcm;
}

static whisper_context* load_model(const std::string& path, bool gpu) {
    FILE* file = nullptr;
#ifdef _WIN32
    const int len = MultiByteToWideChar(CP_UTF8, 0, path.data(), static_cast<int>(path.size()), nullptr, 0);
    std::wstring wide(static_cast<size_t>(len), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, path.data(), static_cast<int>(path.size()), wide.data(), len);
    file = _wfopen(wide.c_str(), L"rb");
#else
    file = std::fopen(path.c_str(), "rb");
#endif
    if (!file) throw std::runtime_error("Cannot read speech model");
    whisper_model_loader loader{};
    loader.context = file;
    loader.read = [](void* c, void* out, size_t n) { return std::fread(out, 1, n, static_cast<FILE*>(c)); };
    loader.eof = [](void* c) { return std::feof(static_cast<FILE*>(c)) != 0; };
    loader.close = [](void* c) { std::fclose(static_cast<FILE*>(c)); };
    auto params = whisper_context_default_params(); params.use_gpu = gpu;
    auto* ctx = whisper_init_with_params(&loader, params);
    if (!ctx) throw std::runtime_error("Speech model could not be loaded");
    return ctx;
}

static void warm_gpu(whisper_context* ctx) {
    auto params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.n_threads = std::clamp(static_cast<int>(std::thread::hardware_concurrency()) / 2, 1, 6);
    params.language = "en"; params.no_context = true; params.single_segment = true;
    params.print_progress = params.print_realtime = params.print_timestamps = false;
    params.duration_ms = 1000; params.max_tokens = 1;
    std::vector<float> silence(rate, 0.0f);
    check(whisper_full(ctx, params, silence.data(), static_cast<int>(silence.size())),
        "Speech recognition failed during GPU warm-up");
}

struct LanguagePlan {
    std::string language, hint;
    bool reuse, valid_hint, detect;
    int duration_ms;
    int64_t position;
};
static LanguagePlan language_plan(const json& request, LanguageMemory& memory) {
    const auto source = request.at("source").get<std::string>();
    const int track = request.value("audio_track", 0);
    const int64_t position = request.value("start_ms", int64_t(0));
    if (memory.source != source || memory.track != track || position < memory.start ||
        std::abs(position - memory.end) > 1600) {
        memory = {}; memory.source = source; memory.track = track;
    }
    const auto language = request.value("language", std::string("auto"));
    const auto hint = request.value("language_hint", std::string());
    const bool reuse = language == "auto" && memory.stable >= 2 && memory.confidence >= 0.75f &&
        position - memory.detected_at < 30000;
    const bool valid_hint = language == "auto" && !hint.empty() && whisper_lang_id(hint.c_str()) >= 0;
    return {language, hint, reuse, valid_hint, language == "auto" && !valid_hint && !reuse,
        std::clamp(request.value("duration_ms", 8000), 1000, 30000), position};
}
struct Transcription {
    json response;
    LanguageMemory memory;
};
static Transcription transcribe(whisper_context* context, const LanguagePlan& plan,
        LanguageMemory memory, const std::vector<float>& pcm, std::atomic<bool>* cancel = nullptr) {
    json response = {{"segments", json::array()}, {"language", plan.language},
        {"audio_ms", std::min<int64_t>(pcm.size() * 1000 / rate, plan.duration_ms)},
        {"language_reused", plan.reuse && !plan.valid_hint},
        {"timings", {{"detect_ms", 0}, {"asr_ms", 0}}}};
    const auto audible = std::min<size_t>(pcm.size(), plan.duration_ms * rate / 1000);
    double energy = 0;
    for (size_t i = 0; i < audible; ++i) energy += pcm[i] * pcm[i];
    if (audible > 0 && std::sqrt(energy / audible) > 0.0005) {
        if (plan.language != "auto" && whisper_lang_id(plan.language.c_str()) < 0)
            throw std::runtime_error("Unsupported audio language");
        auto params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
        params.n_threads = std::clamp(static_cast<int>(std::thread::hardware_concurrency()) / 2, 1, 6);
        params.language = plan.language.c_str(); params.translate = false; params.no_context = true;
        params.print_progress = params.print_realtime = params.print_timestamps = false;
        params.suppress_nst = true; params.temperature = 0; params.temperature_inc = 0;
        if (cancel) {
            params.abort_callback = gpu_ready_to_take_over;
            params.abort_callback_user_data = cancel;
        }
        if (plan.valid_hint) params.language = plan.hint.c_str();
        else if (plan.reuse) params.language = whisper_lang_str(memory.id);
        if (plan.detect) {
            const auto started = Clock::now();
            int detected = -1;
            float confidence = 0;
            if (cancel) {
                // The CPU bridge is cancellable. Its low-level public language
                // detector has no abort callback, so use detect-only inference.
                auto detector = params; detector.detect_language = true;
                check(whisper_full(context, detector, pcm.data(), static_cast<int>(pcm.size())),
                    "Cannot detect audio language");
                detected = whisper_full_lang_id(context);
            } else {
                check(whisper_pcm_to_mel(context, pcm.data(), static_cast<int>(pcm.size()), params.n_threads),
                    "Cannot prepare language detection");
                std::vector<float> probabilities(whisper_lang_max_id() + 1, 0.0f);
                detected = whisper_lang_auto_detect(context, 0, params.n_threads, probabilities.data());
                if (detected >= 0) confidence = probabilities[detected];
            }
            check(detected, "Cannot detect audio language");
            params.language = whisper_lang_str(detected);
            memory.stable = confidence >= 0.75f ? (memory.id == detected ? memory.stable + 1 : 1) : 0;
            memory.id = detected; memory.confidence = confidence; memory.detected_at = plan.position;
            response["timings"]["detect_ms"] = milliseconds(started);
        }
        // Look-ahead informs language only; recognition cannot see future words.
        std::vector<float> speech(pcm.begin(), pcm.begin() + audible);
        if (speech.size() < rate) speech.resize(rate, 0);
        params.duration_ms = plan.duration_ms;
        const auto started = Clock::now();
        check(whisper_full(context, params, speech.data(), static_cast<int>(speech.size())),
            "Speech recognition failed");
        response["timings"]["asr_ms"] = milliseconds(started);
        response["language"] = whisper_lang_str(whisper_full_lang_id(context));
        response["language_confidence"] = plan.valid_hint ? 1.0f : memory.confidence;
        for (int i = 0; i < whisper_full_n_segments(context); ++i) {
            const auto from = std::clamp<int64_t>(whisper_full_get_segment_t0(context, i) * 10, 0, plan.duration_ms);
            const auto to = std::clamp<int64_t>(whisper_full_get_segment_t1(context, i) * 10, from, plan.duration_ms);
            if (to > from) response["segments"].push_back({{"start_ms", plan.position + from},
                {"end_ms", plan.position + to}, {"text", whisper_full_get_segment_text(context, i)}});
        }
    }
    memory.start = plan.position; memory.end = plan.position + plan.duration_ms;
    return {std::move(response), std::move(memory)};
}

int main() {
#ifdef _WIN32
    SetPriorityClass(GetCurrentProcess(), BELOW_NORMAL_PRIORITY_CLASS);
#else
    setpriority(PRIO_PROCESS, 0, 5);
#endif
#ifdef _WIN32
    _setmode(_fileno(stdin), _O_BINARY); _setmode(_fileno(stdout), _O_BINARY);
#endif
    av_log_set_level(AV_LOG_ERROR);
    avformat_network_init();
    std::unique_ptr<whisper_context, decltype(&whisper_free)> ctx(nullptr, whisper_free);
    std::shared_ptr<whisper_context> startup_cpu;
    std::atomic<bool> gpu_ready{true};
    std::atomic<int64_t> gpu_warmup_us{0};
    // Destruction joins the warm-up before releasing either captured object.
    std::future<void> gpu_warmup;
    std::string model_path;
    bool accelerated = false;
    LanguageMemory remembered;
    std::shared_ptr<std::atomic<bool>> startup_cancel;
    std::future<Transcription> startup_task;
    std::string line;
    while (std::getline(std::cin, line)) {
        json response; int id = 0;
        try {
            if (line.size() > 1024 * 1024) throw std::runtime_error("Request too large");
            const auto request = json::parse(line); id = request.at("id").get<int>();
            const auto command = request.at("command").get<std::string>();
            if (command == "init") {
                const auto started = Clock::now();
                if (startup_task.valid()) {
                    if (startup_cancel) startup_cancel->store(true);
                    try { startup_task.get(); } catch (...) {}
                }
                if (gpu_warmup.valid()) gpu_warmup.get();
                std::atomic_store(&startup_cpu, std::shared_ptr<whisper_context>());
                model_path = request.at("model").get<std::string>();
                const bool use_gpu = request.value("gpu", true);
                ctx.reset(load_model(model_path, use_gpu));
                accelerated = use_gpu && (ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_GPU) ||
                    ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_IGPU));
                if (accelerated) {
                    // Context creation can take a backend-global lock. Prepare
                    // the bounded CPU bridge BEFORE GPU shader compilation;
                    // creating it concurrently can block behind the driver.
                    if (whisper_model_n_audio_layer(ctx.get()) <= 12) {
                        std::atomic_store(&startup_cpu,
                            std::shared_ptr<whisper_context>(load_model(model_path, false), whisper_free));
                    }
                    gpu_ready.store(false, std::memory_order_release);
                    gpu_warmup_us.store(0);
                    const auto warmup_started = Clock::now();
                    int warmup_delay = 0;
#ifdef CB_SUBTITLE_TEST_HOOKS
                    warmup_delay = std::clamp(request.value("test_warmup_delay_ms", 0), 0, 10000);
#endif
                    gpu_warmup = std::async(std::launch::async, [context = ctx.get(), &startup_cpu, &gpu_ready, &gpu_warmup_us, warmup_started, warmup_delay]() {
                        try {
                            if (warmup_delay > 0) std::this_thread::sleep_for(std::chrono::milliseconds(warmup_delay));
                            warm_gpu(context);
                            std::atomic_store(&startup_cpu, std::shared_ptr<whisper_context>());
                        } catch (...) {
                            gpu_ready.store(true, std::memory_order_release);
                            throw;
                        }
                        gpu_warmup_us.store(std::chrono::duration_cast<std::chrono::microseconds>(Clock::now() - warmup_started).count());
                        gpu_ready.store(true, std::memory_order_release);
                    });
                }
                remembered = {};
                response = {{"protocol", 1}, {"ready", true}, {"load_ms", milliseconds(started)},
                    {"accelerated", accelerated}, {"warming", gpu_warmup.valid()}};
#ifdef CB_SUBTITLE_TEST_HOOKS
                response["test_hooks"] = true;
#endif
            } else if (command == "decode") {
                // Also available without a model for decoder/timeline validation.
                const auto pcm = decode(request);
                double energy = 0; for (const float sample : pcm) energy += sample * sample;
                response = {{"samples", pcm.size()}, {"rms", pcm.empty() ? 0 : std::sqrt(energy / pcm.size())}};
            } else if (command == "transcribe") {
                if (!ctx) throw std::runtime_error("Speech model is not initialized");
                if (startup_task.valid() && startup_task.wait_for(std::chrono::milliseconds(0)) == std::future_status::ready) {
                    try { startup_task.get(); } catch (...) {} // Discard a cancelled CPU loser.
                }
                auto normalized = remembered;
                const auto plan = language_plan(request, normalized);
                auto decode_request = request;
                if (plan.detect) decode_request["duration_ms"] = 30000;
                const auto decode_started = Clock::now();
                auto pcm = std::make_shared<const std::vector<float>>(decode(decode_request));
                const double decode_ms = milliseconds(decode_started);
                Transcription result;
                bool cpu_won = false;
                if (gpu_warmup.valid() &&
                    gpu_warmup.wait_for(std::chrono::milliseconds(100)) != std::future_status::ready &&
                    whisper_model_n_audio_layer(ctx.get()) <= 12) {
                    auto cpu = std::atomic_load(&startup_cpu);
                    if (cpu) {
                        startup_cancel = std::make_shared<std::atomic<bool>>(false);
                        startup_task = std::async(std::launch::async,
                            [held = std::move(cpu), pcm, plan, normalized, cancel = startup_cancel]() mutable {
                                // Drop the captured model when work ends, even if
                                // nobody polls this losing future while paused.
                                auto context = std::move(held);
                                return transcribe(context.get(), plan, normalized, *pcm, cancel.get());
                            });
                        while (true) {
                            if (startup_task.wait_for(std::chrono::milliseconds(0)) == std::future_status::ready) {
                                result = startup_task.get(); cpu_won = true; break;
                            }
                            if (gpu_warmup.wait_for(std::chrono::milliseconds(0)) == std::future_status::ready) {
                                gpu_warmup.get(); startup_cancel->store(true);
                                // Do not wait for an uninterruptible CPU kernel
                                // before showing the already-ready GPU result.
                                result = transcribe(ctx.get(), plan, normalized, *pcm); break;
                            }
                            std::this_thread::sleep_for(std::chrono::milliseconds(2));
                        }
                    } else {
                        gpu_warmup.get(); result = transcribe(ctx.get(), plan, normalized, *pcm);
                    }
                } else {
                    if (gpu_warmup.valid()) gpu_warmup.get();
                    result = transcribe(ctx.get(), plan, normalized, *pcm);
                }
                remembered = std::move(result.memory);
                response = std::move(result.response);
                response["timings"]["decode_ms"] = decode_ms;
                response["backend"] = cpu_won ? "cpu-startup" : accelerated ? "gpu" : "cpu";
                response["gpu_warmup_ms"] = gpu_warmup_us.load() / 1000.0;
            } else throw std::runtime_error("Unknown command");
            response["id"] = id;
        } catch (const std::exception& e) { response = {{"id", id}, {"error", e.what()}}; }
        std::cout << response.dump(-1, ' ', false, json::error_handler_t::replace) << std::endl;
    }
    return 0;
}
