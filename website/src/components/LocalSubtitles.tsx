import * as React from "react";
import { ArrowRight, Cpu, Translate, ArrowsClockwise } from "@phosphor-icons/react";
import { T, useCopy } from "./lang";
import { Rise } from "./motion";
import { Eyebrow } from "./Eyebrow";

export function LocalSubtitles() {
  const copy = useCopy();
  const [view, setView] = React.useState<"player" | "models">("player");
  const language = copy({ en: "en", vi: "vi" });
  return (
    <section id="local-subtitles" aria-labelledby="subtitle-title" className="relative scroll-mt-24 border-y border-line bg-surface/40 py-20 sm:py-28">
      <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <Eyebrow index="AI" copy={{ en: "Local subtitles · desktop preview", vi: "Phụ đề local · bản xem trước desktop" }} />
        <div className="grid gap-7 lg:grid-cols-12 lg:items-end lg:gap-12">
          <Rise className="lg:col-span-7">
            <h2 id="subtitle-title" className="max-w-[18ch] text-[clamp(2.25rem,4.8vw,4rem)] font-extrabold leading-[1.05] tracking-tight">
              <T en="Subtitles, generated on your desktop." vi="Phụ đề AI, tạo ngay trên máy bạn." />
            </h2>
          </Rise>
          <Rise delay={0.1} className="lg:col-span-5">
            <p className="max-w-[48ch] text-lg leading-relaxed text-muted">
              <T
                en="Recognize speech and translate subtitles while you watch. Choose your output language, download your models, and keep audio processing on your own computer."
                vi="Nhận diện lời nói và dịch phụ đề ngay khi xem. Chọn ngôn ngữ muốn đọc, tải model về máy và xử lý âm thanh ngay trên máy tính của bạn."
              />
            </p>
            <a href="#download" className="mt-5 inline-flex items-center gap-2 font-semibold text-accent transition-colors hover:text-ink">
              <T en="Explore desktop downloads" vi="Xem bản tải cho máy tính" />
              <ArrowRight size={17} aria-hidden />
            </a>
          </Rise>
        </div>

        <Rise delay={0.15} className="mt-10 sm:mt-14">
          <div role="group" aria-label={copy({ en: "Subtitle feature screenshots", vi: "Ảnh tính năng phụ đề" })} className="mb-4 flex gap-6 border-b border-line">
            {(["player", "models"] as const).map((id) => (
              <button key={id} id={`subtitles-tab-${id}`} type="button"
                aria-pressed={view === id} aria-controls="subtitles-preview"
                onClick={() => setView(id)}
                className={`border-b-2 pb-3 text-sm font-semibold transition-colors ${view === id ? "border-accent text-ink" : "border-transparent text-muted hover:text-ink"}`}>
                {id === "player" ? <T en="Watch & translate" vi="Xem và dịch phụ đề" /> : <T en="Models & languages" vi="Model và ngôn ngữ" />}
              </button>
            ))}
          </div>
          <figure id="subtitles-preview" aria-labelledby={`subtitles-tab-${view}`}>
            <img src={`/media/subtitles-${view}-${language}.webp`} width={1600} height={900} loading="lazy" decoding="async"
              className="w-full rounded-lg border border-line bg-black shadow-[0_24px_80px_-40px_rgb(0_0_0/0.8)]"
              alt={view === "player"
                ? copy({ en: "CB File Hub player with Japanese and English subtitles, one seek track and a CC control", vi: "Trình phát CB File Hub với phụ đề Nhật và Việt, một thanh seek và nút CC" })
                : copy({ en: "Local subtitle settings with Whisper, Hy-MT2, language choices and reusable subtitle cache", vi: "Cài đặt phụ đề local với Whisper, Hy-MT2, chọn ngôn ngữ và cache phụ đề" })} />
            <figcaption className="mt-3 text-xs leading-relaxed text-muted">
              <T en="App UI rendered with demo video and subtitle data. Desktop preview; model downloads are required. Older releases may not include this feature."
                vi="Giao diện app dựng với video và phụ đề mẫu. Bản xem trước desktop, cần tải model. Các bản phát hành cũ có thể chưa có tính năng này." />
            </figcaption>
          </figure>
        </Rise>
        <ul className="mt-7 flex flex-wrap gap-x-9 gap-y-4 text-sm text-muted">
          <li className="inline-flex items-center gap-2"><Cpu size={19} className="text-accent" /><T en="On-device recognition & translation" vi="Nhận diện và dịch ngay trên máy" /></li>
          <li className="inline-flex items-center gap-2"><Translate size={19} className="text-accent" /><T en="Japanese, Vietnamese, English and more" vi="Tiếng Nhật, Việt, Anh và nhiều ngôn ngữ khác" /></li>
          <li className="inline-flex items-center gap-2"><ArrowsClockwise size={19} className="text-accent" /><T en="Saved subtitles, ready next time" vi="Lưu phụ đề để dùng lại lần sau" /></li>
        </ul>
      </div>
    </section>
  );
}
