import * as React from "react";
import { AnimatePresence, motion, useInView, useScroll, useSpring } from "motion/react";
import { FolderOpen, Images, ShareNetwork, Tag, type Icon } from "@phosphor-icons/react";
import { T, type Copy, useCopy } from "./lang";
import { SplitText, easeOut } from "./motion";
import { Eyebrow } from "./Eyebrow";

type Step = {
  icon: Icon;
  title: Copy;
  body: Copy;
  image: { src: string; width: number; height: number; alt: Copy };
};

const steps: Step[] = [
  {
    icon: FolderOpen,
    title: { en: "See the whole picture.", vi: "Nhìn rõ mọi tệp tin." },
    body: {
      en: "Switch between list, grid and details. Preview images, video and PDFs without leaving the folder, and keep several folders open in tabs.",
      vi: "Đổi giữa danh sách, lưới và chi tiết. Xem trước ảnh, video, PDF ngay trong thư mục và giữ nhiều thư mục mở trong các tab.",
    },
    image: {
      src: "/media/hero-browser.webp",
      width: 1800,
      height: 967,
      alt: { en: "Folder in grid view with a preview pane", vi: "Thư mục dạng lưới với khung xem trước" },
    },
  },
  {
    icon: Images,
    title: { en: "Your library, alive.", vi: "Thư viện sống động hơn." },
    body: {
      en: "Browse albums and thumbnails, then play video and audio in the app. On desktop, picture-in-picture keeps a clip running while you work.",
      vi: "Duyệt album và ảnh thu nhỏ, xem video, nghe nhạc ngay trong app. Trên desktop, cửa sổ PiP giữ video chạy trong lúc bạn làm việc.",
    },
    image: {
      src: "/media/tour-gallery.webp",
      width: 1600,
      height: 860,
      alt: { en: "Album with photo and video thumbnails", vi: "Album với ảnh và video thu nhỏ" },
    },
  },
  {
    icon: Tag,
    title: { en: "Find it your way.", vi: "Tìm theo cách của bạn." },
    body: {
      en: "Tag files, nest tags into trees and pull up everything marked Travel or Movies without remembering a single folder path.",
      vi: "Gắn thẻ, lồng thẻ thành cây và mở mọi tệp có thẻ Du lịch hay Phim mà không cần nhớ đường dẫn thư mục.",
    },
    image: {
      src: "/media/tour-tags.webp",
      width: 1152,
      height: 720,
      alt: { en: "Tag tree with nested tags", vi: "Cây thẻ với các thẻ lồng nhau" },
    },
  },
  {
    icon: ShareNetwork,
    title: { en: "Remote folders, next to local ones.", vi: "Thư mục từ xa, ngay cạnh thư mục trong máy." },
    body: {
      en: "Open SMB shares and FTP, SFTP or WebDAV servers in a tab, or manage hosts and keys in the SSH workspace.",
      vi: "Mở thư mục chia sẻ SMB, máy chủ FTP, SFTP hoặc WebDAV trong một tab, hay quản lý host và khóa trong không gian SSH.",
    },
    image: {
      src: "/media/tour-network.webp",
      width: 1152,
      height: 720,
      alt: { en: "Network services list: SMB, FTP, SFTP, WebDAV and SSH", vi: "Danh sách dịch vụ mạng: SMB, FTP, SFTP, WebDAV và SSH" },
    },
  },
];

function Shot({ step, className = "" }: { step: Step; className?: string }) {
  const copy = useCopy();
  return (
    <img
      src={step.image.src}
      width={step.image.width}
      height={step.image.height}
      alt={copy(step.image.alt)}
      loading="lazy"
      decoding="async"
      className={`block h-full w-full object-cover object-left-top ${className}`}
    />
  );
}

function StepText({
  step,
  index,
  current,
  onActive,
}: {
  step: Step;
  index: number;
  current: boolean;
  onActive: (i: number) => void;
}) {
  const ref = React.useRef<HTMLDivElement>(null);
  // A step is "current" while it crosses the middle band of the viewport.
  const inView = useInView(ref, { margin: "-45% 0px -45% 0px" });
  React.useEffect(() => {
    if (inView) onActive(index);
  }, [inView, index, onActive]);
  const Icon = step.icon;

  return (
    <div
      ref={ref}
      className={`flex flex-col justify-center py-10 transition-opacity duration-500 lg:min-h-[78vh] lg:py-0 ${
        current ? "" : "lg:opacity-40"
      }`}
    >
      <motion.div
        initial={{ opacity: 0, y: 32 }}
        whileInView={{ opacity: 1, y: 0 }}
        viewport={{ once: true, amount: 0.5 }}
        transition={{ duration: 0.8, ease: easeOut }}
      >
        <div className="flex items-center gap-4">
          <span
            className={`grid size-12 place-items-center rounded-2xl transition-colors duration-500 ${
              current ? "bg-accent text-accent-ink shadow-[0_10px_24px_-10px_var(--c-accent)]" : "bg-accent-soft text-accent"
            }`}
          >
            <Icon size={22} weight="duotone" />
          </span>
          <span className="font-mono text-xs text-muted tabular-nums">
            {String(index + 1).padStart(2, "0")} / {String(steps.length).padStart(2, "0")}
          </span>
        </div>
        <h3 className="mt-6 text-3xl leading-tight font-semibold tracking-[-0.03em] sm:text-4xl">
          <T {...step.title} />
        </h3>
        <p className="mt-4 max-w-[46ch] text-lg leading-relaxed text-muted">
          <T {...step.body} />
        </p>
      </motion.div>
      {/* Below lg the sticky stage is hidden, so each step carries its own screenshot. */}
      <div className="shadow-tinted mt-8 aspect-[16/10] overflow-hidden rounded-[20px] border border-line bg-surface p-1.5 lg:hidden">
        <Shot step={step} className="rounded-[14px]" />
      </div>
    </div>
  );
}

export function Tour() {
  const [active, setActive] = React.useState(0);
  const list = React.useRef<HTMLDivElement>(null);
  const { scrollYProgress } = useScroll({ target: list, offset: ["start center", "end center"] });
  const progress = useSpring(scrollYProgress, { stiffness: 120, damping: 30 });
  const onActive = React.useCallback((i: number) => setActive(i), []);

  return (
    <section id="experience" aria-labelledby="experience-title" className="py-24 sm:py-32">
      <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <Eyebrow index="02" copy={{ en: "Experience", vi: "Trải nghiệm" }} />
        <h2
          id="experience-title"
          className="max-w-4xl text-4xl leading-[1.05] font-semibold tracking-[-0.035em] sm:text-5xl lg:text-6xl"
        >
          <SplitText
            copy={{
              en: "A file manager that *keeps* *up* with the way you work.",
              vi: "Trình quản lý tệp *theo* *kịp* cách bạn làm việc.",
            }}
            inView
          />
        </h2>

        <div className="mt-10 grid gap-x-16 lg:mt-4 lg:grid-cols-12">
          {/* Sticky stage: the screenshot swaps as each step reaches the middle of the viewport. */}
          <div className="hidden lg:col-span-7 lg:block">
            <div className="sticky top-[calc(50vh-16rem)]">
              <div
                aria-hidden
                className="pointer-events-none absolute -inset-10 -z-10 rounded-full bg-[radial-gradient(closest-side,var(--c-aurora-1),var(--c-aurora-2)_60%,transparent)] blur-2xl"
              />
              {/* Step switcher chips mirror the scroll position. */}
              <div aria-hidden className="mb-4 flex gap-2">
                {steps.map((s, i) => {
                  const StepIcon = s.icon;
                  return (
                    <span
                      key={s.image.src}
                      className={`inline-flex h-9 items-center gap-2 rounded-full border px-3.5 text-xs font-semibold transition-all duration-500 ${
                        i === active ? "border-accent/30 bg-accent-soft text-accent" : "border-line text-muted"
                      }`}
                    >
                      <StepIcon size={15} weight={i === active ? "fill" : "regular"} />
                      {String(i + 1).padStart(2, "0")}
                    </span>
                  );
                })}
              </div>
              <div className="shadow-tinted relative aspect-[16/10] overflow-hidden rounded-[24px] border border-line bg-surface p-2">
                <div className="relative h-full w-full overflow-hidden rounded-[16px] bg-canvas">
                  <AnimatePresence initial={false}>
                    <motion.div
                      key={active}
                      className="absolute inset-0"
                      initial={{ opacity: 0, scale: 1.04, filter: "blur(6px)" }}
                      animate={{ opacity: 1, scale: 1, filter: "blur(0px)" }}
                      exit={{ opacity: 0, scale: 0.98 }}
                      transition={{ duration: 0.7, ease: easeOut }}
                    >
                      <Shot step={steps[active]} />
                    </motion.div>
                  </AnimatePresence>
                </div>
              </div>
            </div>
          </div>

          <div ref={list} className="relative lg:col-span-5 lg:pl-10">
            {/* Progress rail through the four steps (desktop only). */}
            <div aria-hidden className="absolute top-0 bottom-0 left-0 hidden w-px bg-line lg:block">
              <motion.div style={{ scaleY: progress }} className="h-full w-full origin-top bg-accent" />
            </div>
            {steps.map((step, i) => (
              <StepText key={step.image.src} step={step} index={i} current={i === active} onActive={onActive} />
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
