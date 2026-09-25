import * as React from "react";
import { motion } from "motion/react";
import { ArrowUpRight, ShieldCheck } from "@phosphor-icons/react";
import { T, useCopy } from "./lang";
import { Reveal, SplitText, easeOut } from "./motion";
import { links } from "./site";
import { AppDemo } from "./demo/AppDemo";
import { Eyebrow } from "./Eyebrow";

export function LiveDemo() {
  const copy = useCopy();

  return (
    <section id="live-demo" aria-labelledby="live-demo-title" className="relative isolate py-24 sm:py-32">
      <div
        aria-hidden
        className="bg-dots pointer-events-none absolute inset-0 -z-10 [mask-image:radial-gradient(ellipse_60%_50%_at_50%_65%,#000,transparent_75%)]"
      />
      <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <Eyebrow index="01" copy={{ en: "Live demo", vi: "Dùng thử" }} />
        <h2 id="live-demo-title" className="text-4xl leading-[1.05] font-semibold tracking-[-0.035em] sm:text-5xl lg:text-6xl">
          <SplitText copy={{ en: "Go ahead. *Click* *around.*", vi: "Cứ thử *khám* *phá* đi." }} inView />
        </h2>
        <Reveal delay={0.15} className="mt-5 flex flex-col gap-5 sm:flex-row sm:items-end sm:justify-between">
          <p className="max-w-[60ch] text-lg leading-relaxed text-muted">
            <T
              en="The real CB File Hub layout, running on sample files. Open the menu, switch tabs, right-click a file or ask CB Agent."
              vi="Giao diện CB File Hub thật, chạy với tệp mẫu. Mở menu, đổi tab, nhấp chuột phải vào tệp hoặc hỏi CB Agent."
            />
          </p>
          <a
            href={links.demo}
            target="_blank"
            rel="noopener noreferrer"
            className="glass group inline-flex h-11 shrink-0 items-center gap-2 self-start rounded-full px-5 text-sm font-semibold whitespace-nowrap transition-colors hover:bg-surface sm:self-auto"
          >
            <T en="Open full screen" vi="Mở toàn màn hình" />
            <ArrowUpRight size={16} weight="bold" className="transition-transform duration-300 group-hover:translate-x-0.5 group-hover:-translate-y-0.5" />
          </a>
        </Reveal>
      </div>

      <div className="relative mx-auto mt-12 max-w-[1400px] px-4 sm:px-6 lg:px-8">
        {/* Brand glow that spills out from under the demo window. */}
        <div
          aria-hidden
          className="pointer-events-none absolute inset-x-[10%] top-[8%] bottom-[4%] -z-10 rounded-full bg-[radial-gradient(closest-side,var(--c-aurora-1),var(--c-aurora-2)_55%,transparent)] blur-3xl"
        />
        {/* Opens once like an app window, then stays still so clicks land where the cursor is. */}
        <motion.div
          role="region"
          aria-label={copy({ en: "CB File Hub interactive demo", vi: "Bản demo tương tác CB File Hub" })}
          initial={{ opacity: 0, scale: 0.94, y: 48 }}
          whileInView={{ opacity: 1, scale: 1, y: 0 }}
          viewport={{ once: true, amount: 0.15 }}
          transition={{ duration: 1, ease: easeOut }}
          style={{ transformOrigin: "50% 0%" }}
          className="shadow-tinted h-[640px] overflow-hidden rounded-[20px] border border-line bg-surface sm:h-[clamp(600px,62vw,780px)]"
        >
          <AppDemo />
        </motion.div>
        <p className="mt-5 flex items-center justify-center gap-2 text-center text-sm text-muted">
          <ShieldCheck size={16} weight="fill" className="shrink-0 text-accent" />
          <T
            en="Sample files only. Nothing on your device is read, changed or uploaded."
            vi="Chỉ dùng tệp mẫu. Không đọc, sửa hay tải lên bất cứ thứ gì trên máy bạn."
          />
        </p>
      </div>
    </section>
  );
}
