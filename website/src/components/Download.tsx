import * as React from "react";
import { motion } from "motion/react";
import { AppleLogo, ArrowUpRight, GooglePlayLogo, WindowsLogo, type Icon } from "@phosphor-icons/react";
import { T } from "./lang";
import { Reveal, SplitText, easeOut } from "./motion";
import { links } from "./site";

function StoreButton({ href, icon: Icon, small, name, primary }: { href: string; icon: Icon; small: { en: string; vi: string }; name: string; primary?: boolean }) {
  return (
    <motion.a
      href={href}
      target="_blank"
      rel="noopener noreferrer"
      whileHover={{ y: -3 }}
      whileTap={{ scale: 0.98 }}
      transition={{ type: "spring", stiffness: 380, damping: 26 }}
      className={`group inline-flex h-16 items-center gap-4 rounded-full pr-6 pl-5 whitespace-nowrap transition-colors ${
        primary
          ? "bg-[#34d1b0] text-[#04241d] shadow-[0_14px_40px_-12px_#34d1b0]"
          : "border border-white/15 bg-white/5 text-white backdrop-blur hover:bg-white/10"
      }`}
    >
      <Icon size={28} weight="fill" />
      <span className="flex flex-col text-left leading-tight">
        <span className={`text-xs ${primary ? "opacity-75" : "text-white/60"}`}>
          <T {...small} />
        </span>
        <span className="text-lg font-semibold">{name}</span>
      </span>
      <ArrowUpRight size={18} weight="bold" className="ml-2 transition-transform duration-300 group-hover:translate-x-0.5 group-hover:-translate-y-0.5" />
    </motion.a>
  );
}

export function Download() {
  return (
    <section id="download" aria-labelledby="download-title" className="px-4 pb-24 sm:px-6 sm:pb-32 lg:px-8">
      {/* Brand navy in both themes: the one deliberate dark moment, echoing the navy bento cell. */}
      <div className="relative isolate mx-auto max-w-7xl overflow-hidden rounded-[36px] bg-[linear-gradient(160deg,#14284a,#0a1628_60%,#071120)] px-6 py-20 text-center text-white shadow-tinted sm:px-12 sm:py-28">
        <div aria-hidden className="bg-grid-light absolute inset-0 -z-10 [mask-image:radial-gradient(ellipse_70%_70%_at_50%_0%,#000,transparent_75%)]" />
        <div
          aria-hidden
          className="animate-drift absolute -top-40 left-1/2 -z-10 size-[42rem] -translate-x-1/2 rounded-full bg-[radial-gradient(closest-side,rgb(52_209_176/0.35),transparent)] blur-2xl"
        />
        <div
          aria-hidden
          className="animate-drift absolute -right-40 -bottom-60 -z-10 size-[36rem] rounded-full bg-[radial-gradient(closest-side,rgb(70_140_255/0.25),transparent)] blur-3xl"
          style={{ animationDelay: "-8s" }}
        />
        <div aria-hidden className="absolute inset-x-0 top-0 -z-10 h-px bg-gradient-to-r from-transparent via-[#34d1b0]/60 to-transparent" />
        <motion.img
          src="/logo-badge.png?v=2"
          width={96}
          height={96}
          alt=""
          initial={{ opacity: 0, scale: 0.6, rotate: -8 }}
          whileInView={{ opacity: 1, scale: 1, rotate: 0 }}
          viewport={{ once: true, amount: 0.6 }}
          transition={{ type: "spring", stiffness: 180, damping: 16 }}
          className="relative mx-auto size-24 rounded-full object-contain shadow-[0_0_0_10px_rgb(255_255_255/0.04),0_0_0_22px_rgb(255_255_255/0.025),0_20px_60px_-10px_rgb(52_209_176/0.55)]"
        />
        <h2 id="download-title" className="mx-auto mt-10 max-w-3xl [--c-accent:#34d1b0] [--c-sky:#8cc4ff] text-4xl leading-[1.05] font-semibold tracking-[-0.035em] sm:text-5xl lg:text-6xl">
          <SplitText copy={{ en: "Make room for *better* *file* *days.*", vi: "Làm việc với tệp *nhẹ* *nhàng* *hơn.*" }} inView />
        </h2>
        <Reveal delay={0.15}>
          <p className="mx-auto mt-5 max-w-[48ch] text-lg leading-relaxed text-[#b4c4d6]">
            <T
              en="Bring your folders, media and connected places into one workspace."
              vi="Đưa thư mục, media và các kết nối vào cùng một không gian."
            />
          </p>
        </Reveal>
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, amount: 0.5 }}
          transition={{ duration: 0.8, delay: 0.25, ease: easeOut }}
          className="mt-10 flex flex-col flex-wrap items-center justify-center gap-3 sm:flex-row"
        >
          <StoreButton primary href={links.microsoftStore} icon={WindowsLogo} small={{ en: "Get it from", vi: "Tải trên" }} name="Microsoft Store" />
          <StoreButton href={links.googlePlay} icon={GooglePlayLogo} small={{ en: "Get it on", vi: "Tải trên" }} name="Google Play" />
          <StoreButton href={links.macos} icon={AppleLogo} small={{ en: "Download for", vi: "Tải cho" }} name="macOS" />
        </motion.div>
      </div>
    </section>
  );
}
