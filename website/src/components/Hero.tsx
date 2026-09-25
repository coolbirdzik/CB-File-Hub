import * as React from "react";
import { motion, useReducedMotion, useScroll, useTransform, type MotionValue } from "motion/react";
import {
  AndroidLogo,
  ArrowRight,
  DownloadSimple,
  ShareNetwork,
  ShieldCheck,
  Sparkle,
  Tag,
  Translate,
  WindowsLogo,
} from "@phosphor-icons/react";
import { T, useCopy } from "./lang";
import { Rise, SplitText, easeOut } from "./motion";
import { download, liveDemo } from "./site";

/** Ambient colour behind the hero: three blurred blobs over a dot grid, all transform-animated. */
function Backdrop() {
  return (
    <div aria-hidden className="pointer-events-none absolute inset-0 -z-10 overflow-hidden">
      <div className="bg-dots absolute inset-0 [mask-image:radial-gradient(ellipse_70%_60%_at_50%_30%,#000_30%,transparent_75%)]" />
      <div className="animate-drift absolute -top-40 left-[8%] size-[38rem] rounded-full bg-[radial-gradient(closest-side,var(--c-aurora-1),transparent)] blur-2xl" />
      <div
        className="animate-drift absolute top-10 right-[-6%] size-[34rem] rounded-full bg-[radial-gradient(closest-side,var(--c-aurora-2),transparent)] blur-2xl"
        style={{ animationDelay: "-6s" }}
      />
      <div
        className="animate-drift absolute top-[45%] left-[30%] size-[44rem] rounded-full bg-[radial-gradient(closest-side,var(--c-aurora-3),transparent)] blur-3xl"
        style={{ animationDelay: "-11s" }}
      />
    </div>
  );
}

/** Small frosted UI card that floats over the product shot. Desktop only; it repeats what the shot shows. */
function Floating({
  y,
  delay,
  className,
  children,
}: {
  y: MotionValue<number>;
  delay: number;
  className: string;
  children: React.ReactNode;
}) {
  return (
    <motion.div
      aria-hidden
      style={{ y }}
      initial={{ opacity: 0, scale: 0.9 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={{ duration: 0.9, delay, ease: easeOut }}
      className={`absolute z-10 hidden lg:block ${className}`}
    >
      <div className="glass animate-bob rounded-2xl p-3.5" style={{ animationDelay: `${-delay * 3}s` }}>
        {children}
      </div>
    </motion.div>
  );
}

const tags = [
  { en: "Travel", vi: "Du lịch", dot: "bg-emerald-500" },
  { en: "Beach", vi: "Biển", dot: "bg-amber-500" },
  { en: "Favorite", vi: "Yêu thích", dot: "bg-rose-500" },
];

export function Hero() {
  const ref = React.useRef<HTMLElement>(null);
  const reduce = useReducedMotion();
  const copy = useCopy();

  // The screenshot starts tilted back and lies flat as the visitor scrolls into it.
  const { scrollYProgress } = useScroll({ target: ref, offset: ["start start", "end start"] });
  const rotateX = useTransform(scrollYProgress, [0, 0.45], reduce ? [0, 0] : [16, 0]);
  const scale = useTransform(scrollYProgress, [0, 0.45], reduce ? [1, 1] : [0.92, 1]);
  const glowOpacity = useTransform(scrollYProgress, [0, 0.5], [1, 0.3]);
  // Floating cards drift at different rates than the shot for depth.
  const floatA = useTransform(scrollYProgress, [0, 1], reduce ? [0, 0] : [0, -140]);
  const floatB = useTransform(scrollYProgress, [0, 1], reduce ? [0, 0] : [0, -60]);
  const floatC = useTransform(scrollYProgress, [0, 1], reduce ? [0, 0] : [0, -220]);

  return (
    <section ref={ref} aria-labelledby="hero-title" className="relative isolate pt-28 sm:pt-32 lg:pt-36">
      <Backdrop />

      {/* Soft brand-navy wash behind the product shot. */}
      <motion.div
        aria-hidden
        style={{ opacity: glowOpacity }}
        className="pointer-events-none absolute inset-x-0 top-[38%] -z-10 mx-auto h-[70vh] max-w-6xl rounded-full bg-[radial-gradient(closest-side,var(--c-glow),transparent)] blur-3xl [mask-image:linear-gradient(to_bottom,#000_55%,transparent)]"
      />

      <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <a
          href="#features"
          className="rise glass group mb-8 inline-flex items-center gap-2.5 rounded-full py-1.5 pr-4 pl-1.5 text-sm font-medium transition-colors hover:border-accent/40"
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
      </div>

      <div className="mx-auto grid max-w-7xl gap-8 px-4 sm:px-6 lg:grid-cols-12 lg:items-end lg:gap-12 lg:px-8">
        <h1
          id="hero-title"
          className="text-[clamp(3rem,9vw,6.5rem)] leading-[1.02] font-semibold tracking-[-0.045em] lg:col-span-7"
        >
          <SplitText copy={{ en: "Your files,\nin *flow.*", vi: "Mọi tệp tin,\ntrong *tầm* *tay.*" }} delay={0.1} />
        </h1>

        <Rise delay={0.35} className="lg:col-span-5 lg:pb-3">
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
            <a
              href="#live-demo"
              className="glass group inline-flex h-12 items-center gap-2 rounded-full px-6 font-semibold whitespace-nowrap transition-colors hover:bg-surface"
            >
              <T {...liveDemo} />
              <ArrowRight size={16} weight="bold" className="transition-transform duration-300 group-hover:translate-x-0.5" />
            </a>
          </div>
          <ul className="mt-7 flex flex-wrap items-center gap-x-5 gap-y-2 text-sm text-muted">
            <li className="inline-flex items-center gap-1.5">
              <WindowsLogo size={16} weight="fill" className="text-accent" />
              <AndroidLogo size={16} weight="fill" className="-ml-0.5 text-accent" />
              Windows · Android
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

      <div className="relative mx-auto mt-14 max-w-7xl px-4 [perspective:1600px] sm:px-6 lg:mt-20 lg:px-8">
        <Floating y={floatA} delay={1.1} className="top-[14%] -left-2 w-64 xl:-left-8">
          <div className="flex items-center gap-2 text-xs font-semibold">
            <span className="grid size-6 place-items-center rounded-lg bg-accent text-accent-ink">
              <Sparkle size={13} weight="fill" />
            </span>
            CB Agent
          </div>
          <p className="mt-2 text-[13px] leading-snug text-muted">
            <T
              en="Found 2 duplicate videos in Photos. Highlight them?"
              vi="Tìm thấy 2 video trùng trong Photos. Đánh dấu chúng nhé?"
            />
          </p>
          <div className="mt-2.5 flex gap-1.5 text-[11px] font-semibold">
            <span className="rounded-full bg-accent px-2.5 py-1 text-accent-ink">
              <T en="Highlight" vi="Đánh dấu" />
            </span>
            <span className="rounded-full border border-line px-2.5 py-1 text-muted">
              <T en="Not now" vi="Để sau" />
            </span>
          </div>
        </Floating>

        <Floating y={floatB} delay={1.3} className="top-[38%] -right-2 w-56 xl:-right-10">
          <div className="flex items-center gap-2 text-xs font-semibold">
            <Tag size={15} weight="duotone" className="text-accent" />
            <T en="Tags" vi="Thẻ" />
          </div>
          <div className="mt-2.5 flex flex-wrap gap-1.5">
            {tags.map((t) => (
              <span key={t.en} className="inline-flex items-center gap-1.5 rounded-full border border-line bg-surface px-2.5 py-1 text-[11px] font-medium">
                <span className={`size-1.5 rounded-full ${t.dot}`} />
                <T en={t.en} vi={t.vi} />
              </span>
            ))}
          </div>
        </Floating>

        <Floating y={floatC} delay={1.5} className="bottom-[8%] left-[12%] w-60">
          <div className="flex items-center gap-3">
            <span className="grid size-9 place-items-center rounded-xl bg-accent-soft text-accent">
              <ShareNetwork size={18} weight="duotone" />
            </span>
            <div className="min-w-0">
              <div className="text-xs font-semibold">
                <T en="SMB share connected" vi="Đã kết nối SMB" />
              </div>
              <div className="truncate font-mono text-[11px] text-muted">\\nas\media</div>
            </div>
            <span className="relative ml-auto flex size-2.5">
              <span className="animate-ping-soft absolute inset-0 rounded-full bg-emerald-500" />
              <span className="relative size-2.5 rounded-full bg-emerald-500" />
            </span>
          </div>
        </Floating>

        <Rise delay={0.25} className="[--rise-y:64px] [animation-duration:1.2s]">
          <motion.div
            style={{ rotateX, scale, transformOrigin: "50% 0%" }}
            className="shadow-tinted relative rounded-[22px] border border-line bg-surface/70 p-1.5 backdrop-blur will-change-transform sm:p-2"
          >
            {/* Gradient rim: a 1px brand-tinted edge on top of the neutral border. */}
            <div
              aria-hidden
              className="pointer-events-none absolute inset-0 rounded-[22px] p-px [mask:linear-gradient(#000_0_0)_content-box_exclude,linear-gradient(#000_0_0)] [background:linear-gradient(160deg,var(--c-accent),transparent_35%,transparent_70%,var(--c-sky))] opacity-60"
            />
            {/* The capture's lower third is empty canvas, so crop it and fade the edge. */}
            <div className="relative aspect-[1800/800] overflow-hidden rounded-[15px]">
              <img
                src="/media/hero-browser.webp"
                width={1800}
                height={967}
                {...{ fetchpriority: "high" }}
                alt={copy({
                  en: "CB File Hub on Windows: a folder in grid view with image and video thumbnails and a preview pane",
                  vi: "CB File Hub trên Windows: thư mục dạng lưới với ảnh thu nhỏ, video và khung xem trước",
                })}
                className="block h-auto w-full"
              />
              <div aria-hidden className="absolute inset-x-0 bottom-0 h-1/4 bg-gradient-to-t from-surface to-transparent" />
            </div>
          </motion.div>
        </Rise>
      </div>
    </section>
  );
}
