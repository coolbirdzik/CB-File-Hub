import * as React from "react";
import { MotionConfig } from "motion/react";
import { LangProvider, T } from "./lang";
import { Nav } from "./Nav";
import { Footer } from "./Footer";
import { Cosmos } from "./Cosmos";

/** `current` is the nav href of this page, marked with aria-current. */
export function Layout({ children, current }: { children: React.ReactNode; current?: string }) {
  return (
    <LangProvider>
      {/* "user": honour prefers-reduced-motion for every transform animation on the site. */}
      <MotionConfig reducedMotion="user">
        <a
          href="#main"
          className="fixed top-3 left-4 z-50 -translate-y-20 rounded-full bg-accent px-4 py-2 text-sm font-semibold text-accent-ink focus:translate-y-0"
        >
          <T en="Skip to content" vi="Đến nội dung" />
        </a>
        <Cosmos />
        <Nav current={current} />
        <main id="main">{children}</main>
        <Footer />
      </MotionConfig>
    </LangProvider>
  );
}

export function Seo({ title, description, path = "/" }: { title: string; description: string; path?: string }) {
  const url = `https://cbfilehub.web.app${path}`;
  return (
    <>
      <title>{title}</title>
      <meta name="description" content={description} />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <meta name="theme-color" content="#05080d" />
      <meta property="og:type" content="website" />
      <meta property="og:title" content="CB File Hub" />
      <meta property="og:description" content="One place for your files, media and ideas." />
      <meta property="og:url" content={url} />
      <meta property="og:image" content="https://cbfilehub.web.app/media/hero-browser.webp" />
      <meta name="twitter:card" content="summary_large_image" />
      <link rel="canonical" href={url} />
      <link rel="icon" type="image/png" href="/logo-badge.png?v=2" />
    </>
  );
}
