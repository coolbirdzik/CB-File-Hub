import * as React from "react";
import type { HeadFC } from "gatsby";
import { MotionConfig } from "motion/react";
import { ArrowLeft } from "@phosphor-icons/react";
import { Seo } from "../components/Layout";
import { LangProvider, T, useLang } from "../components/lang";
import { AppDemo } from "../components/demo/AppDemo";

function LangToggle() {
  const { lang, setLang } = useLang();
  return (
    <div role="group" aria-label="Language" className="flex rounded-full border border-line p-0.5 text-xs font-semibold">
      {(["en", "vi"] as const).map((code) => (
        <button
          key={code}
          type="button"
          aria-pressed={lang === code}
          onClick={() => setLang(code)}
          className={`h-7 rounded-full px-3 uppercase ${lang === code ? "bg-accent text-accent-ink" : "text-muted hover:text-ink"}`}
        >
          {code}
        </button>
      ))}
    </div>
  );
}

export default function DemoPage() {
  return (
    <LangProvider>
      <MotionConfig reducedMotion="user">
        <div className="flex h-[100dvh] flex-col">
          <header className="flex h-12 shrink-0 items-center gap-3 border-b border-line px-3 sm:px-4">
            <a href="/" className="inline-flex items-center gap-2 text-sm font-semibold">
              <ArrowLeft size={16} weight="bold" />
              <img src="/logo-badge.png?v=2" width={26} height={26} alt="" className="size-[26px] object-contain" />
              <span className="hidden sm:inline">CB File Hub</span>
            </a>
            <span className="truncate text-sm text-muted">
              <T en="Interactive demo with sample files" vi="Bản demo tương tác với tệp mẫu" />
            </span>
            <div className="ml-auto">
              <LangToggle />
            </div>
          </header>
          <main className="min-h-0 flex-1">
            <AppDemo />
          </main>
        </div>
      </MotionConfig>
    </LangProvider>
  );
}

export const Head: HeadFC = () => (
  <Seo
    title="Interactive demo - CB File Hub"
    description="Try CB File Hub in your browser with sample files: tabs, previews, tags, network places and CB Agent."
    path="/demo"
  />
);
