// This translation unit shares the existing FFmpeg reader but is linked to
// NeMo's own ggml runtime instead of whisper.cpp. Never load both GPU runtimes
// into the Flutter process (or the same worker).
#include <nemo_speech/asr.h>
#include <map>

static const std::map<std::string, std::string> nemo_languages = {
    {"auto", "auto"}, {"en", "en-US"}, {"es", "es-ES"}, {"fr", "fr-FR"},
    {"it", "it-IT"}, {"pt", "pt-PT"}, {"nl", "nl-NL"}, {"de", "de-DE"},
    {"tr", "tr-TR"}, {"ru", "ru-RU"}, {"ar", "ar-AR"}, {"hi", "hi-IN"},
    {"ja", "ja-JP"}, {"ko", "ko-KR"}, {"vi", "vi-VN"}, {"uk", "uk-UA"},
    {"pl", "pl-PL"}, {"sv", "sv-SE"}, {"cs", "cs-CZ"}, {"no", "nb-NO"},
    {"da", "da-DK"}, {"bg", "bg-BG"}, {"fi", "fi-FI"}, {"hr", "hr-HR"},
    {"sk", "sk-SK"}, {"zh", "zh-CN"}, {"hu", "hu-HU"}, {"ro", "ro-RO"}, {"et", "et-EE"}
};

static std::string language_code(const char* value) {
    if (!value || !*value) return {};
    std::string code(value);
    const auto separator = code.find('-');
    if (separator != std::string::npos) code.resize(separator);
    return code == "nb" ? "no" : code;
}

// Some quantized SDK outputs omit the language tag in auto mode. Kana and
// Hangul are unambiguous; don't guess the language of Latin/Han-only text.
static std::string script_language(const std::string& text) {
    for (size_t i = 0; i < text.size();) {
        const auto first = static_cast<unsigned char>(text[i++]);
        unsigned code = first;
        int continuation = 0;
        if ((first & 0xe0) == 0xc0) { code = first & 0x1f; continuation = 1; }
        else if ((first & 0xf0) == 0xe0) { code = first & 0x0f; continuation = 2; }
        else if ((first & 0xf8) == 0xf0) { code = first & 7; continuation = 3; }
        while (continuation-- > 0 && i < text.size()) code = (code << 6) | (static_cast<unsigned char>(text[i++]) & 0x3f);
        if ((code >= 0x3040 && code <= 0x30ff) || (code >= 0xff66 && code <= 0xff9d)) return "ja";
        if ((code >= 0xac00 && code <= 0xd7af) || (code >= 0x1100 && code <= 0x11ff)) return "ko";
    }
    return "auto";
}

static void nemo_check(nemo_speech_asr_status status, const char* operation) {
    if (status != NEMO_SPEECH_ASR_OK) {
        const auto* detail = nemo_speech_asr_last_error();
        throw std::runtime_error(std::string(operation) + " (NeMo " + std::to_string(status) + "): " + (detail ? detail : "unknown error"));
    }
}

using NemoRecognizer = std::unique_ptr<nemo_speech_asr_recognizer, decltype(&nemo_speech_asr_destroy)>;
using NemoResult = std::unique_ptr<nemo_speech_asr_result, decltype(&nemo_speech_asr_result_destroy)>;

static NemoRecognizer nemo_load(const std::string& path, bool gpu) {
    nemo_speech_asr_model_config model{};
    model.size = sizeof(model); model.path = path.c_str();
    nemo_speech_asr_backend_config backend{};
    backend.size = sizeof(backend); backend.gpu = gpu ? 0 : -1;
    nemo_speech_asr_recognizer_config config{};
    config.size = sizeof(config); config.model = &model; config.backend = &backend;
    nemo_speech_asr_streaming_config streaming{};
    streaming.size = sizeof(streaming);
    streaming.chunk_size = 1.12f; // required even for RNNT geometry validation
    streaming.rnnt_right_context = 13; // quality mode, 1.12 s model context
    config.streaming = &streaming;
    nemo_speech_asr_recognizer* raw = nullptr;
    nemo_check(nemo_speech_asr_create(&config, &raw), "Speech model could not be loaded");
    return NemoRecognizer(raw, nemo_speech_asr_destroy);
}

static json nemo_transcribe(nemo_speech_asr_recognizer* recognizer, const json& request) {
    const auto started = Clock::now();
    bool reused = false;
    auto pcm = decode(request, &reused);
    const double decode_ms = milliseconds(started);
    const int64_t base = std::max<int64_t>(0, request.value("start_ms", int64_t(0)));
    const int64_t audio_ms = pcm.size() * 1000 / rate;
    const auto selected = request.value("language", std::string("auto"));
    const auto hint = request.value("language_hint", std::string());
    const auto language = selected == "auto" && nemo_languages.count(hint) ? hint : selected;
    const auto locale = nemo_languages.find(language);
    if (locale == nemo_languages.end()) throw std::runtime_error("Unsupported audio language");
    json response = {{"segments", json::array()}, {"language", language}, {"audio_ms", audio_ms},
        {"reused_input", reused}, {"timings", {{"decode_ms", decode_ms}, {"detect_ms", 0}, {"asr_ms", 0}}}};
    double energy = 0;
    for (const float sample : pcm) energy += sample * sample;
    if (pcm.empty() || std::sqrt(energy / pcm.size()) <= 0.0005) return response;
    auto options = nemo_speech_asr_recognition_options_default();
    options.language_code = locale->second.c_str();
    options.enable_word_time_offsets = true;
    options.enable_automatic_punctuation = true;
    const auto asr_started = Clock::now();
    nemo_speech_asr_result* raw = nullptr;
    nemo_check(nemo_speech_asr_recognize_f32(recognizer, &options, pcm.data(), pcm.size(), rate, &raw), "Speech recognition failed");
    NemoResult result(raw, nemo_speech_asr_result_destroy);
    response["timings"]["asr_ms"] = milliseconds(asr_started);
    if (!result || !nemo_speech_asr_result_alternative_count(result.get())) return response;
    const char* text = nemo_speech_asr_result_transcript(result.get(), 0);
    if (!text || !*text) return response;
    std::string detected = language;
    if (language == "auto" && nemo_speech_asr_result_language_count(result.get(), 0))
        detected = language_code(nemo_speech_asr_result_language_code(result.get(), 0, 0));
    if (!nemo_languages.count(detected) || detected == "auto") detected = script_language(text);
    response["language"] = detected;
    // Preserve the entire punctuated transcript. Use the actual word span;
    // the Dart scheduler already groups chunks and trims recognition overlap.
    const auto words = nemo_speech_asr_result_word_count(result.get(), 0);
    int64_t from = audio_ms, to = 0;
    for (size_t i = 0; i < words; ++i) {
        from = std::min<int64_t>(from, nemo_speech_asr_result_word_start_time(result.get(), 0, i));
        to = std::max<int64_t>(to, nemo_speech_asr_result_word_end_time(result.get(), 0, i));
    }
    from = std::clamp<int64_t>(from, 0, audio_ms);
    to = std::clamp<int64_t>(to, from, audio_ms);
    if (to <= from) { from = 0; to = audio_ms; }
    if (to > from) response["segments"].push_back({{"start_ms", base + from}, {"end_ms", base + to}, {"text", text}});
    return response;
}

int main() {
    SetPriorityClass(GetCurrentProcess(), BELOW_NORMAL_PRIORITY_CLASS);
    _setmode(_fileno(stdin), _O_BINARY); _setmode(_fileno(stdout), _O_BINARY);
    av_log_set_level(AV_LOG_ERROR);
    avformat_network_init();
    NemoRecognizer recognizer(nullptr, nemo_speech_asr_destroy);
    bool gpu = false;
    std::string line;
    while (std::getline(std::cin, line)) {
        json response; int id = 0;
        try {
            const auto request = json::parse(line);
            id = request.value("id", 0);
            const auto command = request.value("command", std::string());
            if (command == "init") {
                const auto started = Clock::now();
                gpu = request.value("gpu", true);
                recognizer = nemo_load(request.at("model").get<std::string>(), gpu);
                response = {{"protocol", 1}, {"ready", true}, {"accelerated", gpu}, {"load_ms", milliseconds(started)}, {"engine", "nemo-speech"}};
            } else if (command == "transcribe") {
                if (!recognizer) throw std::runtime_error("Speech model is not initialized");
                response = nemo_transcribe(recognizer.get(), request);
                response["backend"] = gpu ? "gpu" : "cpu";
            } else if (command == "decode") {
                bool reused = false;
                const auto pcm = decode(request, &reused);
                double energy = 0; for (const float sample : pcm) energy += sample * sample;
                response = {{"samples", pcm.size()}, {"rms", pcm.empty() ? 0 : std::sqrt(energy / pcm.size())}, {"reused_input", reused}};
            } else throw std::runtime_error("Unknown command");
            response["id"] = id;
        } catch (const std::exception& e) { response = {{"id", id}, {"error", e.what()}}; }
        std::cout << response.dump(-1, ' ', false, json::error_handler_t::replace) << std::endl;
    }
    return 0;
}
