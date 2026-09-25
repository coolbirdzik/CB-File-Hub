import * as React from "react";
import { T } from "./lang";
import { download, links, nav } from "./site";

export function Footer() {
  const explore = nav.filter((n) => n.href !== "/#experience");
  return (
    <footer className="border-t border-line">
      <div className="mx-auto grid max-w-7xl gap-12 px-4 py-16 sm:px-6 md:grid-cols-[1.4fr_1fr_1fr_1fr] lg:px-8">
        <div>
          <a href="/" className="inline-flex items-center gap-2.5">
            <img src="/logo-badge.png?v=2" width={36} height={36} alt="" className="size-9 object-contain" />
            <span className="text-[15px] font-semibold tracking-tight">CB File Hub</span>
          </a>
          <p className="mt-4 max-w-[34ch] text-sm leading-relaxed text-muted">
            <T
              en="A better place for the files, media and ideas you keep close."
              vi="Một nơi gọn gàng hơn cho tệp, media và những ý tưởng của bạn."
            />
          </p>
        </div>

        <FooterColumn title={{ en: "Explore", vi: "Khám phá" }}>
          {explore.map((item) => (
            <a key={item.href} href={item.href}>
              <T en={item.en} vi={item.vi} />
            </a>
          ))}
        </FooterColumn>

        <FooterColumn title={download}>
          <a href={links.microsoftStore} target="_blank" rel="noopener noreferrer">
            Microsoft Store
          </a>
          <a href={links.googlePlay} target="_blank" rel="noopener noreferrer">
            Google Play
          </a>
        </FooterColumn>

        <FooterColumn title={{ en: "Legal", vi: "Pháp lý" }}>
          <a href={links.privacy}>
            <T en="Privacy" vi="Quyền riêng tư" />
          </a>
          <a href={links.terms}>
            <T en="Terms" vi="Điều khoản" />
          </a>
        </FooterColumn>
      </div>
      <div className="mx-auto flex max-w-7xl flex-wrap items-center justify-between gap-3 border-t border-line px-4 py-6 text-sm text-muted sm:px-6 lg:px-8">
        <span>© 2026 CB File Hub</span>
        <span className="inline-flex items-center gap-2">
          <span className="size-1.5 rounded-full bg-accent" />
          <T en="Made for Windows and Android" vi="Dành cho Windows và Android" />
        </span>
      </div>
      <div aria-hidden className="overflow-hidden">
        <p className="mx-auto -mb-[0.2em] max-w-7xl bg-gradient-to-b from-ink/[0.09] to-transparent bg-clip-text px-4 text-center text-[clamp(4rem,17vw,15rem)] leading-none font-bold tracking-[-0.06em] whitespace-nowrap text-transparent select-none sm:px-6 lg:px-8">
          CB File Hub
        </p>
      </div>
    </footer>
  );
}

function FooterColumn({ title, children }: { title: { en: string; vi: string }; children: React.ReactNode }) {
  return (
    <div>
      <h2 className="text-sm font-semibold">
        <T {...title} />
      </h2>
      <div className="mt-4 flex flex-col items-start gap-3 text-sm text-muted [&>a]:transition-colors [&>a:hover]:text-ink">
        {children}
      </div>
    </div>
  );
}
