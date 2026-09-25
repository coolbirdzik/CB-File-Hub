import * as React from "react";
import { motion, type HTMLMotionProps, type Variants } from "motion/react";
import type { Copy } from "./lang";

// Reduced motion is handled once by <MotionConfig reducedMotion="user"> in Layout:
// transform animations become instant, opacity fades stay. Keeping `initial` identical
// on server and client avoids hydration mismatches.
//
// Above the fold, entrance animations are plain CSS (`.rise`, global.css) instead of motion:
// motion's `initial` ships as opacity:0 in the static HTML and only animates after hydration,
// which held the hero headline (the LCP element) back by 1-2.5s. CSS starts on first paint.

export const easeOut = [0.16, 1, 0.3, 1] as const;

/** Fades a block up on first paint, no JS needed. For content that is visible when the page opens. */
export function Rise({
  delay = 0,
  y,
  className = "",
  style,
  children,
  ...rest
}: React.HTMLAttributes<HTMLDivElement> & { delay?: number; y?: number }) {
  const rise = { animationDelay: `${delay}s`, ...(y === undefined ? null : { "--rise-y": `${y}px` }) };
  return (
    <div className={`rise ${className}`} style={{ ...rise, ...style } as React.CSSProperties} {...rest}>
      {children}
    </div>
  );
}

/** Fades a block up once as it enters the viewport. Used for section headings and grid cells. */
export function Reveal({
  delay = 0,
  y = 28,
  children,
  ...rest
}: HTMLMotionProps<"div"> & { delay?: number; y?: number }) {
  return (
    <motion.div
      initial={{ opacity: 0, y }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, amount: 0.2 }}
      transition={{ duration: 0.8, delay, ease: easeOut }}
      {...rest}
    >
      {children}
    </motion.div>
  );
}

const word: Variants = {
  hidden: { y: "105%", opacity: 0 },
  shown: (delay: number) => ({ y: "0%", opacity: 1, transition: { duration: 0.9, delay, ease: easeOut } }),
};

// "*word*" in headline copy paints that word with the brand gradient.
const isMarked = (w: string) => w.length > 2 && w.startsWith("*") && w.endsWith("*");

function Words({ text, lang, delay, css }: { text: string; lang: string; delay: number; css: boolean }) {
  let index = 0;
  return (
    <span data-l={lang} lang={lang}>
      {text.split("\n").map((line, li) => {
        const words = line.split(" ");
        return (
          <span key={li} className="block">
            {words.map((w, wi) => (
              // Padding + negative margin reserve room inside the mask for descenders (g, y, p)
              // and stacked Vietnamese diacritics (ể, ỗ) without changing the line height.
              <span key={wi} className="-my-[0.22em] inline-block overflow-hidden py-[0.22em] align-top">
                {css ? (
                  <span
                    className={`rise rise-word inline-block ${isMarked(w) ? "text-brand pr-[0.04em]" : ""}`}
                    style={{ animationDelay: `${delay + index++ * 0.07}s` }}
                  >
                    {isMarked(w) ? w.slice(1, -1) : w}
                  </span>
                ) : (
                  <motion.span
                    className={`inline-block ${isMarked(w) ? "text-brand pr-[0.04em]" : ""}`}
                    variants={word}
                    custom={delay + index++ * 0.07}
                  >
                    {isMarked(w) ? w.slice(1, -1) : w}
                  </motion.span>
                )}
                {wi < words.length - 1 ? " " : null}
              </span>
            ))}
          </span>
        );
      })}
    </span>
  );
}

/**
 * Headline that rises word by word. "\n" in the copy forces a line break.
 * The trigger sits on the wrapper: the words start clipped by their masks, so they
 * can never be "in view" themselves.
 */
export function SplitText({ copy, delay = 0, inView = false }: { copy: Copy; delay?: number; inView?: boolean }) {
  // Page headlines (no inView) are visible on load: CSS plays them on first paint, before hydration.
  if (!inView) {
    return (
      <span className="block">
        <Words text={copy.en} lang="en" delay={delay} css />
        <Words text={copy.vi} lang="vi" delay={delay} css />
      </span>
    );
  }
  return (
    <motion.span className="block" initial="hidden" whileInView="shown" viewport={{ once: true, amount: 0.5 }}>
      <Words text={copy.en} lang="en" delay={delay} css={false} />
      <Words text={copy.vi} lang="vi" delay={delay} css={false} />
    </motion.span>
  );
}
