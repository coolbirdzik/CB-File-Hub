import * as React from "react";
import { AnimatePresence, motion, useMotionValueEvent, useScroll } from "motion/react";
import { List, X } from "@phosphor-icons/react";
import { T, useCopy, useLang, type Lang } from "./lang";
import { download, nav } from "./site";
import { easeOut } from "./motion";

function LangSwitch({ className = "" }: { className?: string }) {
  const { lang, setLang } = useLang();
  const copy = useCopy();
  return (
    <div
      role="group"
      aria-label={copy({ en: "Language", vi: "Ngôn ngữ" })}
      className={`relative flex h-9 items-center rounded-full border border-line p-0.5 text-xs font-semibold ${className}`}
    >
      {(["en", "vi"] as Lang[]).map((code) => (
        <button
          key={code}
          type="button"
          aria-pressed={lang === code}
          onClick={() => setLang(code)}
          className={`relative z-10 h-full rounded-full px-3 uppercase transition-colors duration-300 ${
            lang === code ? "text-accent-ink" : "text-muted hover:text-ink"
          }`}
        >
          {lang === code && (
            <motion.span
              layoutId="lang-pill"
              className="absolute inset-0 -z-10 rounded-full bg-accent"
              transition={{ type: "spring", stiffness: 420, damping: 34 }}
            />
          )}
          {code}
        </button>
      ))}
    </div>
  );
}

export function Nav({ current }: { current?: string }) {
  const { scrollY } = useScroll();
  const [scrolled, setScrolled] = React.useState(false);
  const [open, setOpen] = React.useState(false);
  const copy = useCopy();

  // Only flips a boolean at the threshold, so React re-renders twice per page, not per frame.
  useMotionValueEvent(scrollY, "change", (y) => {
    const next = y > 12;
    if (next !== scrolled) setScrolled(next);
  });

  React.useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && setOpen(false);
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [open]);

  return (
    <header className="fixed inset-x-0 top-0 z-40 px-3 sm:px-4">
      {/* At the top it is a plain bar; once scrolled it condenses into a floating frosted capsule. */}
      <div
        className={`mx-auto transition-[max-width,margin,border-radius,background-color,border-color,box-shadow] duration-500 ease-[cubic-bezier(0.16,1,0.3,1)] ${
          scrolled || open
            ? "glass mt-3 max-w-5xl rounded-[26px] bg-surface/85!"
            : "mt-0 max-w-7xl rounded-none border border-transparent"
        }`}
      >
        <nav
          aria-label={copy({ en: "Main navigation", vi: "Điều hướng chính" })}
          className={`flex items-center gap-6 transition-[height,padding] duration-500 ${
            scrolled || open ? "h-14 pr-2 pl-3 sm:pl-4" : "h-16 px-1 sm:px-2 lg:px-4"
          }`}
        >
          <a href="/" className="flex shrink-0 items-center gap-2.5" aria-label="CB File Hub">
            <img src="/logo-badge.png?v=2" width={36} height={36} alt="" className="size-9 object-contain" />
            <span className="text-[15px] font-semibold tracking-tight">CB File Hub</span>
          </a>

          <div className="ml-auto hidden items-center gap-1 lg:flex">
            {nav.map((item) => (
              <a
                key={item.href}
                href={item.href}
                aria-current={item.href === current ? "page" : undefined}
                className="rounded-full px-3.5 py-2 text-sm font-medium text-muted transition-colors hover:bg-surface-2/70 hover:text-ink aria-[current=page]:bg-accent-soft aria-[current=page]:text-accent"
              >
                <T en={item.en} vi={item.vi} />
              </a>
            ))}
          </div>

          <div className="ml-auto flex items-center gap-2 lg:ml-2">
            <LangSwitch />
            <a
              href="/#download"
              className="hidden h-9 items-center rounded-full bg-accent px-4 text-sm font-semibold whitespace-nowrap text-accent-ink shadow-[0_8px_20px_-10px_var(--c-accent)] transition-transform hover:-translate-y-px active:scale-[0.97] sm:inline-flex"
            >
              <T {...download} />
            </a>
            <button
              type="button"
              className="grid size-9 place-items-center rounded-full border border-line lg:hidden"
              aria-expanded={open}
              aria-controls="mobile-menu"
              aria-label={copy(open ? { en: "Close menu", vi: "Đóng menu" } : { en: "Open menu", vi: "Mở menu" })}
              onClick={() => setOpen((v) => !v)}
            >
              {open ? <X size={18} weight="bold" /> : <List size={18} weight="bold" />}
            </button>
          </div>
        </nav>

        <AnimatePresence>
          {open && (
            <motion.div
              id="mobile-menu"
              initial={{ height: 0, opacity: 0 }}
              animate={{ height: "auto", opacity: 1 }}
              exit={{ height: 0, opacity: 0 }}
              transition={{ duration: 0.4, ease: easeOut }}
              className="overflow-hidden lg:hidden"
            >
              <div className="flex flex-col px-4 pt-1 pb-5">
                {[...nav, { href: "/#download", ...download }].map((item, i) => (
                  <motion.a
                    key={item.href}
                    href={item.href}
                    onClick={() => setOpen(false)}
                    initial={{ opacity: 0, x: -12 }}
                    animate={{ opacity: 1, x: 0 }}
                    transition={{ delay: 0.05 + i * 0.04, duration: 0.4, ease: easeOut }}
                    className="border-b border-line py-4 text-2xl font-semibold tracking-tight last:border-b-0"
                  >
                    <T en={item.en} vi={item.vi} />
                  </motion.a>
                ))}
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </header>
  );
}
