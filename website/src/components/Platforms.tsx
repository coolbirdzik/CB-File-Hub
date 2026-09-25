import * as React from "react";
import { motion, useReducedMotion, useScroll, useTransform } from "motion/react";
import { AndroidLogo, WindowsLogo } from "@phosphor-icons/react";
import { T, useCopy } from "./lang";
import { Reveal, SplitText } from "./motion";
import { Eyebrow } from "./Eyebrow";

export function Platforms() {
  const ref = React.useRef<HTMLElement>(null);
  const reduce = useReducedMotion();
  const copy = useCopy();

  // Desktop and phone move at different speeds: one workspace, two screens.
  const { scrollYProgress } = useScroll({ target: ref, offset: ["start end", "end start"] });
  const desktopY = useTransform(scrollYProgress, [0, 1], reduce ? [0, 0] : [60, -60]);
  const phoneY = useTransform(scrollYProgress, [0, 1], reduce ? [0, 0] : [180, -140]);
  const phoneRotate = useTransform(scrollYProgress, [0, 1], reduce ? [0, 0] : [6, -3]);

  return (
    <section id="platforms" ref={ref} aria-labelledby="platforms-title" className="relative isolate overflow-hidden py-24 sm:py-32">
      <div
        aria-hidden
        className="pointer-events-none absolute right-[-10%] bottom-0 -z-10 size-[48rem] rounded-full bg-[radial-gradient(closest-side,var(--c-aurora-2),transparent)] blur-3xl"
      />
      <div
        aria-hidden
        className="pointer-events-none absolute bottom-[10%] left-[-8%] -z-10 size-[30rem] rounded-full bg-[radial-gradient(closest-side,var(--c-aurora-1),transparent)] blur-3xl"
      />
      <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <div className="max-w-2xl">
          <Eyebrow index="04" copy={{ en: "Platforms", vi: "Nền tảng" }} />
          <h2 id="platforms-title" className="text-4xl leading-[1.05] font-semibold tracking-[-0.035em] sm:text-5xl lg:text-6xl">
            <SplitText copy={{ en: "Your files go *where* *you* *do.*", vi: "Tệp đi cùng bạn *mọi* *nơi.*" }} inView />
          </h2>
          <Reveal delay={0.15}>
            <p className="mt-5 max-w-[52ch] text-lg leading-relaxed text-muted">
              <T
                en="A roomy workspace on Windows and a touch-first app on Android, with the same tabs, tags and previews."
                vi="Không gian rộng rãi trên Windows và ứng dụng tối ưu cảm ứng trên Android, cùng tab, thẻ và xem trước quen thuộc."
              />
            </p>
            <ul className="mt-7 flex flex-wrap gap-3 text-sm font-semibold">
              <li className="glass inline-flex h-10 items-center gap-2 rounded-full px-4">
                <WindowsLogo size={18} weight="fill" className="text-accent" />
                Windows
              </li>
              <li className="glass inline-flex h-10 items-center gap-2 rounded-full px-4">
                <AndroidLogo size={18} weight="fill" className="text-accent" />
                Android
              </li>
            </ul>
          </Reveal>
        </div>

        {/* Composition: wide desktop shot, phone overlapping its lower-left corner. */}
        <div className="relative mt-16 pb-10 sm:mt-20 lg:pb-24">
          <motion.div style={{ y: desktopY }} className="ml-auto w-full md:w-[82%]">
            <div className="shadow-tinted rounded-[24px] border border-line bg-surface p-1.5 sm:p-2">
              <img
                src="/media/tour-gallery.webp"
                width={1600}
                height={860}
                loading="lazy"
                decoding="async"
                alt={copy({ en: "CB File Hub album view on Windows", vi: "Chế độ xem album của CB File Hub trên Windows" })}
                className="block h-auto w-full rounded-[16px]"
              />
            </div>
          </motion.div>

          <motion.div
            style={{ y: phoneY, rotate: phoneRotate }}
            className="relative mx-auto -mt-24 w-[58%] max-w-[300px] md:absolute md:bottom-0 md:left-[3%] md:mt-0 md:w-[27%] md:max-w-[330px]"
          >
            <div className="shadow-tinted rounded-[36px] border border-line bg-[#0b1422] p-2.5">
              <img
                src="/media/phone-files.webp"
                width={720}
                height={1606}
                loading="lazy"
                decoding="async"
                alt={copy({ en: "CB File Hub file list on Android", vi: "Danh sách tệp của CB File Hub trên Android" })}
                className="block h-auto w-full rounded-[28px]"
              />
            </div>
          </motion.div>
        </div>
      </div>
    </section>
  );
}
