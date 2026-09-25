import * as React from "react";
import { motion, useMotionTemplate, useMotionValue, useReducedMotion, useScroll, useTransform } from "motion/react";
import {
  ArrowsClockwise,
  Broom,
  Cloud,
  CloudArrowUp,
  Cpu,
  Desktop,
  DeviceMobile,
  DropboxLogo,
  GoogleDriveLogo,
  HardDrives,
  Keyboard,
  ShieldCheck,
  Sparkle,
  type Icon,
} from "@phosphor-icons/react";
import { T, type Copy, useCopy } from "./lang";
import { SplitText, easeOut } from "./motion";
import { Eyebrow } from "./Eyebrow";
import { Orbits } from "./Cosmos";

/** Panel with a cursor-following highlight. Pointer position lives in motion values, never React state. */
function Cell({
  className = "",
  delay = 0,
  children,
}: {
  className?: string;
  delay?: number;
  children: React.ReactNode;
}) {
  const x = useMotionValue(-400);
  const y = useMotionValue(-400);
  const spotlight = useMotionTemplate`radial-gradient(420px circle at ${x}px ${y}px, var(--c-spot), transparent 70%)`;

  return (
    <motion.article
      initial={{ opacity: 0, y: 36 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, amount: 0.2 }}
      transition={{ duration: 0.8, delay, ease: easeOut }}
      onPointerMove={(e) => {
        const r = e.currentTarget.getBoundingClientRect();
        x.set(e.clientX - r.left);
        y.set(e.clientY - r.top);
      }}
      onPointerLeave={() => {
        x.set(-400);
        y.set(-400);
      }}
      className={`group relative isolate overflow-hidden rounded-[14px] border border-line ${className}`}
    >
      <motion.div aria-hidden style={{ background: spotlight }} className="pointer-events-none absolute inset-0 z-10" />
      {children}
    </motion.article>
  );
}

function IconTile({ icon: Icon, className = "bg-surface text-accent" }: { icon: Icon; className?: string }) {
  return (
    <span className={`grid size-11 place-items-center rounded-xl border border-line shadow-sm ${className}`}>
      <Icon size={22} weight="duotone" />
    </span>
  );
}

/** Mock of the local runtime status: llama-server running a GGUF model on the GPU. */
function RuntimePanel() {
  return (
    <div aria-hidden className="rounded-2xl border border-white/10 bg-white/[0.04] p-4 font-mono text-[12px] text-[#7e92a8] backdrop-blur">
      <div className="flex items-center justify-between">
        <span className="text-[#e6f0fa]">llama.cpp · Vulkan</span>
        <span className="inline-flex items-center gap-1.5 rounded-full bg-[#38a9ff]/15 px-2 py-0.5 text-[11px] text-[#38a9ff]">
          <span className="relative flex size-1.5">
            <span className="animate-ping-soft absolute inset-0 rounded-full bg-[#38a9ff]" />
            <span className="relative size-1.5 rounded-full bg-[#38a9ff]" />
          </span>
          GPU
        </span>
      </div>
      <div className="mt-3 flex items-center justify-between border-t border-white/10 pt-3">
        <span>model.gguf</span>
        <span className="text-[#e6f0fa]">Q4_K_M</span>
      </div>
      <div className="mt-3 flex h-8 items-end gap-[3px]">
        {Array.from({ length: 28 }, (_, i) => (
          <span
            key={i}
            className="animate-bar w-full rounded-sm bg-gradient-to-t from-[#38a9ff]/30 to-[#38a9ff]"
            style={{ animationDelay: `${-((i * 137) % 1100)}ms`, height: `${40 + ((i * 53) % 60)}%` }}
          />
        ))}
      </div>
    </div>
  );
}

const providers: Array<{ icon: Icon; label: string }> = [
  { icon: HardDrives, label: "Local" },
  { icon: GoogleDriveLogo, label: "Google Drive" },
  { icon: DropboxLogo, label: "Dropbox" },
  { icon: Cloud, label: "OneDrive" },
];

/** Concentric rings around the shield: your devices and servers, nothing in between. */
function Orbit() {
  const nodes: Array<{ icon: Icon; className: string }> = [
    { icon: Desktop, className: "top-[6%] left-1/2 -translate-x-1/2" },
    { icon: DeviceMobile, className: "bottom-[16%] left-[4%]" },
    { icon: HardDrives, className: "right-[4%] bottom-[16%]" },
  ];
  return (
    <div aria-hidden className="relative mx-auto size-52 shrink-0 md:order-2 md:mx-0 lg:size-56">
      <div className="absolute inset-0 rounded-full border border-line" />
      <div className="animate-spin-slow absolute inset-5 rounded-full border border-dashed border-accent/40" />
      <div className="absolute inset-12 rounded-full border border-line bg-[radial-gradient(closest-side,var(--c-accent-soft),transparent)]" />
      <span className="absolute inset-0 m-auto grid size-16 place-items-center rounded-2xl bg-accent text-accent-ink shadow-[0_14px_30px_-12px_var(--c-accent)]">
        <ShieldCheck size={30} weight="fill" />
      </span>
      {nodes.map(({ icon: NodeIcon, className }, i) => (
        <span
          key={i}
          className={`absolute grid size-10 place-items-center rounded-xl border border-line bg-surface text-accent shadow-sm ${className}`}
        >
          <NodeIcon size={18} weight="duotone" />
        </span>
      ))}
    </div>
  );
}

function Heading({ icon: Icon, title, body }: { icon: Icon; title: Copy; body: Copy }) {
  return (
    <div className="relative z-20">
      <IconTile icon={Icon} />
      <h3 className="mt-5 text-2xl leading-tight font-semibold tracking-[-0.025em]">
        <T {...title} />
      </h3>
      <p className="mt-3 max-w-[42ch] leading-relaxed text-muted">
        <T {...body} />
      </p>
    </div>
  );
}

function Kbd({ children }: { children: React.ReactNode }) {
  return (
    <kbd className="inline-flex h-9 min-w-9 items-center justify-center rounded-lg border border-line border-b-[3px] bg-surface px-2.5 font-sans text-sm font-semibold text-ink">
      {children}
    </kbd>
  );
}

const shortcuts: Array<{ keys: string[]; label: Copy }> = [
  { keys: ["Ctrl", "T"], label: { en: "New tab", vi: "Tab mới" } },
  { keys: ["Ctrl", "F"], label: { en: "Search", vi: "Tìm kiếm" } },
  { keys: ["F2"], label: { en: "Rename", vi: "Đổi tên" } },
  { keys: ["Backspace"], label: { en: "Up a folder", vi: "Lên thư mục cha" } },
];

export function Bento() {
  const ref = React.useRef<HTMLElement>(null);
  const reduce = useReducedMotion();
  const copy = useCopy();
  // Screenshots inside the bento drift a little slower than the page for depth.
  const { scrollYProgress } = useScroll({ target: ref, offset: ["start end", "end start"] });
  const drift = useTransform(scrollYProgress, [0, 1], reduce ? [0, 0] : [40, -40]);

  return (
    <section id="features" ref={ref} aria-labelledby="features-title" className="py-24 sm:py-32">
      <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <Eyebrow index="02" copy={{ en: "Features", vi: "Tính năng" }} />
        <h2
          id="features-title"
          className="max-w-3xl text-4xl leading-[1.05] font-extrabold tracking-[-0.015em] uppercase sm:text-5xl lg:text-6xl"
        >
          <SplitText copy={{ en: "Everything you need to stay *in* *motion.*", vi: "Đủ công cụ để công việc *liền* *mạch.*" }} inView />
        </h2>

        {/* 6 cells with no gaps. lg (4 cols): 2x2, 2x1, 2x1, 1x1, 1x1, 2x1. md (2 cols): 2, 1+1, 1+1, 2. Stacked below md. */}
        <div className="mt-14 grid auto-rows-[minmax(18rem,auto)] gap-4 md:grid-cols-2 lg:grid-cols-4">
          {/* Assistant, the largest cell, with the real chat panel. */}
          <Cell className="bg-accent-soft md:col-span-2 lg:row-span-2">
            <div className="flex h-full flex-col p-7 sm:p-9">
              <Heading
                icon={Sparkle}
                title={{ en: "Ask for a file in plain words.", vi: "Hỏi tìm tệp bằng lời thường." }}
                body={{
                  en: "CB Agent searches and inspects your files, and waits for your approval before it moves or deletes anything.",
                  vi: "CB Agent tìm và xem thông tin tệp, và chờ bạn duyệt trước khi di chuyển hay xóa bất cứ thứ gì.",
                }}
              />
              <div className="relative mt-8 -mb-9 min-h-[300px] flex-1 sm:-mr-9">
                <motion.img
                  style={{ y: drift }}
                  src="/media/bento-assistant.webp"
                  width={759}
                  height={975}
                  loading="lazy"
                  decoding="async"
                  alt={copy({
                    en: "CB Agent chat: finding duplicate videos and highlighting them in the file browser",
                    vi: "Trò chuyện với CB Agent: tìm video trùng và đánh dấu trong trình duyệt tệp",
                  })}
                  className="shadow-tinted absolute top-0 right-0 w-[min(100%,440px)] rounded-tl-[16px] border border-line"
                />
              </div>
            </div>
          </Cell>

          {/* Local model runtime: brand-navy panel. */}
          <Cell delay={0.08} className="bg-[linear-gradient(140deg,var(--c-navy),#03060f)] text-[#e6f0fa] lg:col-span-2">
            <Orbits className="-top-40 -right-40 w-[520px]" rings={[0.34, 0.6, 1]} />
            <div className="relative z-20 grid h-full gap-8 p-7 sm:p-9 xl:grid-cols-2 xl:items-end">
              <div className="flex h-full flex-col justify-between gap-8">
                <IconTile icon={Cpu} className="border-white/10 bg-white/5 text-[#38a9ff]" />
                <div>
                  <h3 className="text-2xl leading-tight font-semibold tracking-[-0.025em]">
                    <T en="Run the model on your own PC." vi="Chạy mô hình ngay trên máy của bạn." />
                  </h3>
                  <p className="mt-3 max-w-[48ch] leading-relaxed text-[#7e92a8]">
                    <T
                      en="On Windows, load a GGUF model and CB Agent runs it on your GPU. Or connect the cloud provider you already use."
                      vi="Trên Windows, nạp mô hình GGUF để CB Agent chạy bằng GPU của bạn. Hoặc kết nối nhà cung cấp đám mây bạn đang dùng."
                    />
                  </p>
                </div>
              </div>
              <RuntimePanel />
            </div>
          </Cell>

          {/* Disk cleanup with the real usage table. */}
          <Cell delay={0.16} className="bg-surface lg:col-span-2">
            <div className="grid h-full gap-6 p-7 sm:p-9 xl:grid-cols-[1fr_1.1fr]">
              <Heading
                icon={Broom}
                title={{ en: "See what fills your disk.", vi: "Biết ổ đĩa đầy vì đâu." }}
                body={{
                  en: "Explore usage folder by folder, spot caches and temp files, and review everything before it is cleaned.",
                  vi: "Xem dung lượng theo từng thư mục, nhận ra bộ nhớ đệm, tệp tạm và kiểm tra kỹ trước khi dọn.",
                }}
              />
              <div className="relative min-h-[180px] xl:-mr-9 xl:-mb-9">
                <img
                  src="/media/bento-cleaner.webp"
                  width={1400}
                  height={511}
                  loading="lazy"
                  decoding="async"
                  alt={copy({
                    en: "Disk cleaner showing folder sizes and cleanable caches",
                    vi: "Trình dọn ổ đĩa hiển thị dung lượng thư mục và bộ nhớ đệm có thể dọn",
                  })}
                  className="absolute top-0 left-0 h-full w-auto max-w-none rounded-tl-[14px] border border-line"
                />
              </div>
            </div>
          </Cell>

          {/* Keyboard shortcuts, rendered as real keys. */}
          <Cell delay={0.08} className="bg-surface">
            <div className="relative z-20 flex h-full flex-col p-7">
              <IconTile icon={Keyboard} />
              <h3 className="mt-5 text-xl font-semibold tracking-[-0.02em]">
                <T en="Keyboard first." vi="Ưu tiên bàn phím." />
              </h3>
              <ul className="mt-auto space-y-2.5 pt-6">
                {shortcuts.map((s) => (
                  <li key={s.keys.join("+")} className="flex items-center justify-between gap-3 text-sm text-muted">
                    <T {...s.label} />
                    <span className="flex gap-1">
                      {s.keys.map((k) => (
                        <Kbd key={k}>{k}</Kbd>
                      ))}
                    </span>
                  </li>
                ))}
              </ul>
            </div>
          </Cell>

          {/* Backup targets. */}
          <Cell delay={0.16} className="bg-[radial-gradient(120%_90%_at_100%_0%,var(--c-accent-soft),var(--c-surface))]">
            <div className="relative z-20 flex h-full flex-col justify-between gap-8 p-7">
              <IconTile icon={CloudArrowUp} />
              <div aria-hidden className="flex items-center">
                <div className="flex -space-x-2.5">
                  {providers.map(({ icon: P, label }) => (
                    <span
                      key={label}
                      title={label}
                      className="grid size-11 place-items-center rounded-full border-2 border-surface bg-surface-2 text-ink/80 shadow-sm"
                    >
                      <P size={20} weight="fill" />
                    </span>
                  ))}
                </div>
                <span className="ml-3 inline-flex items-center gap-1.5 rounded-full bg-accent-soft px-2.5 py-1 text-xs font-semibold text-accent">
                  <ArrowsClockwise size={13} weight="bold" />
                  Sync
                </span>
              </div>
              <div>
                <h3 className="text-xl font-semibold tracking-[-0.02em]">
                  <T en="Back up to your own cloud." vi="Sao lưu lên đám mây của bạn." />
                </h3>
                <p className="mt-2 leading-relaxed text-muted">
                  <T
                    en="Settings and tags go to a local folder, Google Drive, Dropbox or OneDrive."
                    vi="Cài đặt và thẻ được lưu vào thư mục trong máy, Google Drive, Dropbox hoặc OneDrive."
                  />
                </p>
              </div>
            </div>
          </Cell>

          {/* Local-first promise. */}
          <Cell delay={0.24} className="bg-surface-2 md:col-span-2">
            <div className="relative z-20 flex h-full flex-col justify-between gap-8 p-7 sm:p-9 md:flex-row md:items-center">
              <Orbit />
              <div>
                <IconTile icon={ShieldCheck} />
                <h3 className="mt-5 text-2xl leading-tight font-semibold tracking-[-0.025em]">
                  <T en="Your files stay yours." vi="Tệp của bạn vẫn là của bạn." />
                </h3>
                <p className="mt-3 max-w-[46ch] leading-relaxed text-muted">
                  <T
                    en="Local first. Your library lives on your device and on the servers you choose to connect."
                    vi="Ưu tiên dữ liệu tại máy. Thư viện nằm trên thiết bị của bạn và những máy chủ bạn chọn kết nối."
                  />
                </p>
              </div>
            </div>
          </Cell>
        </div>
      </div>
    </section>
  );
}
