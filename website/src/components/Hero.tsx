import * as React from "react";
import {
  AndroidLogo,
  AppleLogo,
  ArrowRight,
  DownloadSimple,
  ShieldCheck,
  Sparkle,
  Translate,
  WindowsLogo,
} from "@phosphor-icons/react";
import { T, useCopy } from "./lang";
import { Rise, SplitText } from "./motion";
import { download } from "./site";
import { AppDemo } from "./demo/AppDemo";

/**
 * A planet's lit limb rising behind the demo: a huge dark disc whose rim catches the light,
 * with an atmosphere glow just outside it. Stars and nebula come from the site-wide Cosmos.
 * Both layers fade out well before the hero ends, so its clipped bottom edge never shows.
 */
function Horizon() {
  const fade = "[mask-image:linear-gradient(to_bottom,#000_0%,#000_5%,transparent_17%)]";
  return (
    <div aria-hidden className="pointer-events-none absolute inset-x-0 top-0 -z-10 flex justify-center sm:-top-10">
      <div className="relative aspect-square w-[max(260%,1400px)] shrink-0">
        {/* Atmosphere: a sharp bright band on the rim that falls off into space. */}
        <div
          className={`absolute -inset-[140px] rounded-full ${fade} bg-[radial-gradient(circle_closest-side,transparent_0_91.6%,rgb(150_210_255/0.55)_91.9%,rgb(56_169_255/0.2)_94%,transparent_100%)]`}
        />
        <div
          className={`absolute inset-0 rounded-full ${fade} bg-[radial-gradient(circle_at_50%_0%,#0c1f3d_0%,#050a14_14%,#03060c_32%)] shadow-[inset_0_1px_0_rgb(170_220_255/0.85),inset_0_22px_60px_-26px_rgb(56_169_255/0.75)]`}
        />
      </div>
    </div>
  );
}

export function Hero() {
  const copy = useCopy();
  return (
    <section aria-labelledby="hero-title" className="relative isolate overflow-hidden pt-28 sm:pt-32 lg:pt-36">
      <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <a
          href="#features"
          className="rise glass group inline-flex items-center gap-2.5 rounded-full py-1.5 pr-4 pl-1.5 text-sm font-medium transition-colors hover:border-accent/40"
        >
          <span className="inline-flex items-center gap-1.5 rounded-full bg-accent px-2.5 py-1 text-xs font-semibold text-accent-ink">
            <Sparkle size={12} weight="fill" />
            <T en="New" vi="Mới" />
          </span>
          <span className="text-muted transition-colors group-hover:text-ink">
            <T en="CB Agent now runs GGUF models on your GPU" vi="CB Agent chạy mô hình GGUF ngay trên GPU của bạn" />
          </span>
          <ArrowRight size={14} weight="bold" className="text-muted transition-transform duration-300 group-hover:translate-x-0.5" />
        </a>

        {/* Headline on the left, copy and actions bottom-aligned on the right. */}
        <div className="mt-10 grid gap-8 lg:grid-cols-12 lg:items-end lg:gap-12">
          <h1
            id="hero-title"
            className="text-[clamp(2.75rem,6vw,5.25rem)] leading-[1.0] font-extrabold tracking-[-0.02em] uppercase lg:col-span-7"
          >
            <SplitText copy={{ en: "Your files,\nin *flow.*", vi: "Mọi tệp tin,\ntrong *tầm* *tay.*" }} delay={0.1} />
          </h1>

          <Rise delay={0.35} className="lg:col-span-5 lg:pb-2">
            <p className="max-w-[46ch] text-lg leading-relaxed text-muted">
              <T
                en="Browse, tag, preview and play everything in one fast workspace for Windows and Android."
                vi="Duyệt, gắn thẻ, xem trước và phát mọi tệp trong một không gian làm việc nhanh, trên Windows và Android."
              />
            </p>
            <div className="mt-7 flex flex-wrap items-center gap-3">
              <a
                href="#download"
                className="group inline-flex h-12 items-center gap-2.5 rounded-full bg-accent pr-2 pl-6 font-semibold whitespace-nowrap text-accent-ink shadow-[0_10px_30px_-10px_var(--c-accent)] transition-[transform,box-shadow] duration-300 hover:-translate-y-0.5 hover:shadow-[0_16px_40px_-12px_var(--c-accent)] active:translate-y-0 active:scale-[0.98]"
              >
                <T {...download} />
                <span className="grid size-8 place-items-center rounded-full bg-accent-ink/15 transition-transform duration-300 group-hover:translate-y-0.5">
                  <DownloadSimple size={16} weight="bold" />
                </span>
              </a>
            </div>
            <ul className="mt-7 flex flex-wrap items-center gap-x-5 gap-y-2 text-sm text-muted">
              <li className="inline-flex items-center gap-1.5">
                <WindowsLogo size={16} weight="fill" className="text-accent" />
                <AppleLogo size={16} weight="fill" className="-ml-0.5 text-accent" />
                <AndroidLogo size={16} weight="fill" className="-ml-0.5 text-accent" />
                Windows · macOS · Android
              </li>
              <li className="inline-flex items-center gap-1.5">
                <ShieldCheck size={16} weight="fill" className="text-accent" />
                <T en="Local-first" vi="Dữ liệu tại máy" />
              </li>
              <li className="inline-flex items-center gap-1.5">
                <Translate size={16} weight="bold" className="text-accent" />
                English · Tiếng Việt
              </li>
            </ul>
          </Rise>
        </div>

        {/* The hero shot is the product itself: the interactive demo, live in the page. */}
        {/* Horizon sits outside the animated wrapper so it stays behind the hero copy, not above it. */}
        <div className="relative mt-20 sm:mt-16 lg:mt-20">
          <Horizon />
          <Rise delay={0.25} className="[--rise-y:64px] [animation-duration:1.2s]">
            <div
              id="live-demo"
              role="region"
              aria-label={copy({ en: "CB File Hub interactive demo", vi: "Bản demo tương tác CB File Hub" })}
              className="shadow-tinted relative h-[560px] scroll-mt-24 overflow-hidden rounded-[12px] border border-line bg-surface sm:h-[clamp(560px,58vw,700px)]"
            >
              <AppDemo />
            </div>
            <p className="mt-5 flex items-center justify-center gap-2 text-center text-sm text-muted">
              <ShieldCheck size={16} weight="fill" className="shrink-0 text-accent" />
              <T
                en="Live demo with sample files. Nothing on your device is read, changed or uploaded."
                vi="Demo trực tiếp với tệp mẫu. Không đọc, sửa hay tải lên bất cứ thứ gì trên máy bạn."
              />
            </p>
          </Rise>
        </div>
      </div>
    </section>
  );
}
