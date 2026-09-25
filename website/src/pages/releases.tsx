import * as React from "react";
import type { HeadFC } from "gatsby";
import {
  AndroidLogo,
  ArrowRight,
  ArrowUpRight,
  Bug,
  CaretDown,
  DownloadSimple,
  GithubLogo,
  Lightning,
  Sparkle,
  Wrench,
  WindowsLogo,
  type Icon,
} from "@phosphor-icons/react";
import { Layout, Seo } from "../components/Layout";
import { Eyebrow } from "../components/Eyebrow";
import { T, type Copy } from "../components/lang";
import { Reveal, Rise, SplitText } from "../components/motion";
import { links } from "../components/site";
// Snapshot of the GitHub releases, refreshed by `npm run releases` (scripts/fetch-releases.mjs).
import data from "../data/releases.json";

type Release = (typeof data.releases)[number];
type Change = Release["items"][number];
type GroupKey = "new" | "fixes" | "improvements" | "maintenance";

const groups: Array<{ key: GroupKey; icon: Icon; title: Copy; tone: string }> = [
  { key: "new", icon: Sparkle, title: { en: "New", vi: "Tính năng mới" }, tone: "bg-accent text-accent-ink" },
  { key: "fixes", icon: Bug, title: { en: "Fixes", vi: "Sửa lỗi" }, tone: "bg-rose-500/12 text-rose-600 dark:text-rose-400" },
  { key: "improvements", icon: Lightning, title: { en: "Improvements", vi: "Cải thiện" }, tone: "bg-sky/12 text-sky" },
];

const releases = data.releases;
const commitUrl = (hash: string) => `https://github.com/${data.repo}/commit/${hash}`;
const anchor = (r: Release) => r.tag;

function count(r: Release, key: GroupKey) {
  return r.items.filter((i) => i.group === key).length;
}

/** Same day on server and client: formatted in UTC, both languages rendered, CSS shows one. */
function DateText({ iso }: { iso: string }) {
  const d = new Date(iso);
  const opts: Intl.DateTimeFormatOptions = { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" };
  return (
    <time dateTime={iso}>
      <T en={d.toLocaleDateString("en-US", opts)} vi={d.toLocaleDateString("vi-VN", opts)} />
    </time>
  );
}

function size(bytes: number) {
  const mb = bytes / 1024 / 1024;
  return `${mb < 10 ? mb.toFixed(1) : Math.round(mb)} MB`;
}

function ChangeRow({ item }: { item: Change }) {
  return (
    <li className="group/row flex gap-3 py-2.5">
      <span aria-hidden className="mt-[0.6em] size-1.5 shrink-0 rounded-full bg-line group-hover/row:bg-accent" />
      <div className="min-w-0 flex-1 leading-relaxed">
        {item.scope && (
          <span className="mr-2 inline-flex translate-y-[-1px] items-center rounded-md border border-line bg-surface-2 px-1.5 py-px font-mono text-[11px] text-muted">
            {item.scope}
          </span>
        )}
        {item.breaking && (
          <span className="mr-2 inline-flex rounded-md bg-amber-500/15 px-1.5 py-px text-[11px] font-semibold text-amber-700 dark:text-amber-400">
            <T en="Breaking" vi="Thay đổi lớn" />
          </span>
        )}
        <span className="text-ink/90">{item.subject}</span>
      </div>
      <a
        href={commitUrl(item.hash)}
        target="_blank"
        rel="noopener noreferrer"
        className="mt-0.5 hidden h-fit shrink-0 rounded-md px-1.5 py-0.5 font-mono text-xs text-muted sm:block transition-colors hover:bg-accent-soft hover:text-accent"
      >
        {item.hash}
      </a>
    </li>
  );
}

function Downloads({ release }: { release: Release }) {
  if (!release.assets.length) return null;
  return (
    <div className="mt-8 border-t border-line pt-6">
      <h4 className="flex items-center gap-2 text-sm font-semibold">
        <DownloadSimple size={16} weight="bold" className="text-accent" />
        <T en="Downloads" vi="Tải về" />
      </h4>
      <ul className="mt-3 flex flex-wrap gap-2">
        {release.assets.map((a) => {
          const PlatformIcon = a.platform === "windows" ? WindowsLogo : AndroidLogo;
          return (
            <li key={a.name}>
              <a
                href={a.url}
                title={a.name}
                className="group inline-flex h-10 items-center gap-2 rounded-xl border border-line bg-canvas/60 pr-3 pl-2.5 text-sm font-medium transition-colors hover:border-accent/40 hover:bg-accent-soft"
              >
                <PlatformIcon size={16} weight="fill" className="text-accent" />
                {a.label}
                <span className="font-mono text-xs text-muted tabular-nums">{size(a.size)}</span>
              </a>
            </li>
          );
        })}
      </ul>
    </div>
  );
}

function ReleaseCard({ release, latest }: { release: Release; latest: boolean }) {
  const maintenance = release.items.filter((i) => i.group === "maintenance");
  const visible = groups.filter((g) => count(release, g.key) > 0);

  return (
    <Reveal y={24}>
      <article
        id={anchor(release)}
        aria-labelledby={`${anchor(release)}-title`}
        className={`relative scroll-mt-28 rounded-[24px] border bg-surface p-6 sm:p-8 ${
          latest ? "border-accent/30 shadow-tinted" : "border-line"
        }`}
      >
        {/* Timeline node on the rail to the left of the card (lg only). */}
        <span
          aria-hidden
          className={`absolute top-10 -left-[calc(2.5rem+5px)] hidden size-2.5 rounded-full ring-4 ring-canvas lg:block ${
            latest ? "bg-accent" : "bg-muted/50"
          }`}
        >
          {latest && <span className="animate-ping-soft absolute inset-0 rounded-full bg-accent" />}
        </span>

        <header className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <div className="flex flex-wrap items-center gap-2.5">
              <h2 id={`${anchor(release)}-title`} className="text-3xl font-semibold tracking-[-0.03em] sm:text-4xl">
                <span className="text-muted">v</span>
                {release.version}
              </h2>
              {latest && (
                <span className="inline-flex items-center gap-1.5 rounded-full bg-accent px-2.5 py-1 text-xs font-semibold text-accent-ink">
                  <Sparkle size={12} weight="fill" />
                  <T en="Latest" vi="Mới nhất" />
                </span>
              )}
              {release.prerelease && (
                <span className="rounded-full border border-line px-2.5 py-1 text-xs font-semibold text-muted">
                  <T en="Pre-release" vi="Thử nghiệm" />
                </span>
              )}
            </div>
            <p className="mt-2 text-sm text-muted">
              <DateText iso={release.date} />
            </p>
          </div>
          <a
            href={release.url}
            target="_blank"
            rel="noopener noreferrer"
            className="group inline-flex h-9 items-center gap-1.5 rounded-full border border-line px-3.5 text-sm font-medium text-muted transition-colors hover:bg-surface-2 hover:text-ink"
          >
            <GithubLogo size={16} weight="fill" />
            GitHub
            <ArrowUpRight size={13} weight="bold" className="transition-transform group-hover:translate-x-0.5 group-hover:-translate-y-0.5" />
          </a>
        </header>

        {visible.length > 0 && (
          <ul aria-label="Summary" className="mt-5 flex flex-wrap gap-2">
            {visible.map((g) => (
              <li key={g.key} className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-semibold ${g.tone}`}>
                <g.icon size={13} weight="bold" />
                {count(release, g.key)} <T {...g.title} />
              </li>
            ))}
          </ul>
        )}

        {visible.length === 0 && (
          <p className="mt-6 rounded-2xl bg-surface-2 px-5 py-4 text-muted">
            <T
              en="Maintenance release: build and packaging updates, no user-facing changes."
              vi="Bản bảo trì: cập nhật quy trình build và đóng gói, không có thay đổi về tính năng."
            />
          </p>
        )}

        <div className="mt-6 grid gap-7">
          {visible.map((g) => (
            <section key={g.key} aria-label={g.title.en}>
              <h3 className="flex items-center gap-2.5 text-base font-semibold">
                <span className={`grid size-7 place-items-center rounded-lg ${g.tone}`}>
                  <g.icon size={15} weight="bold" />
                </span>
                <T {...g.title} />
              </h3>
              <ul className="mt-2 divide-y divide-line/60 pl-1">
                {release.items
                  .filter((i) => i.group === g.key)
                  .map((item, i) => (
                    <ChangeRow key={`${item.hash}-${i}`} item={item} />
                  ))}
              </ul>
            </section>
          ))}

          {maintenance.length > 0 && (
            <details className="group/details rounded-2xl border border-line bg-canvas/50">
              <summary className="flex cursor-pointer list-none items-center gap-2.5 px-4 py-3 text-sm font-semibold text-muted transition-colors hover:text-ink [&::-webkit-details-marker]:hidden">
                <Wrench size={16} weight="duotone" className="text-accent" />
                <T en="Under the hood" vi="Hậu trường" />
                <span className="rounded-full bg-surface-2 px-2 py-px font-mono text-xs tabular-nums">{maintenance.length}</span>
                <CaretDown size={14} weight="bold" className="ml-auto transition-transform duration-300 group-open/details:rotate-180" />
              </summary>
              <ul className="divide-y divide-line/60 px-4 pb-2 text-sm">
                {maintenance.map((item, i) => (
                  <ChangeRow key={`${item.hash}-${i}`} item={item} />
                ))}
              </ul>
            </details>
          )}
        </div>

        <Downloads release={release} />
      </article>
    </Reveal>
  );
}

/** Tag of the release card crossing the upper third of the viewport, for the version index. */
function useCurrentRelease() {
  const [current, setCurrent] = React.useState(releases[0]?.tag);
  React.useEffect(() => {
    const observer = new IntersectionObserver(
      (entries) => {
        const hit = entries.find((e) => e.isIntersecting);
        if (hit) setCurrent(hit.target.id);
      },
      { rootMargin: "-30% 0px -65% 0px" },
    );
    releases.forEach((r) => {
      const el = document.getElementById(anchor(r));
      if (el) observer.observe(el);
    });
    return () => observer.disconnect();
  }, []);
  return current;
}

export default function ReleasesPage() {
  const latest = releases[0];
  const current = useCurrentRelease();
  const total = (key: GroupKey) => releases.reduce((n, r) => n + count(r, key), 0);
  const stats: Array<{ value: number; label: Copy }> = [
    { value: releases.length, label: { en: "releases", vi: "bản phát hành" } },
    { value: total("new"), label: { en: "new features", vi: "tính năng mới" } },
    { value: total("fixes"), label: { en: "fixes", vi: "lỗi đã sửa" } },
    { value: total("improvements"), label: { en: "improvements", vi: "cải thiện" } },
  ];

  return (
    <Layout current={links.releases}>
      <section aria-labelledby="releases-title" className="relative isolate overflow-hidden pt-32 pb-16 sm:pt-40">
        <div aria-hidden className="pointer-events-none absolute inset-0 -z-10">
          <div className="bg-dots absolute inset-0 [mask-image:radial-gradient(ellipse_60%_70%_at_30%_20%,#000_20%,transparent_75%)]" />
          <div className="animate-drift absolute -top-40 left-[4%] size-[34rem] rounded-full bg-[radial-gradient(closest-side,var(--c-aurora-1),transparent)] blur-2xl" />
          <div
            className="animate-drift absolute -top-20 right-[-4%] size-[30rem] rounded-full bg-[radial-gradient(closest-side,var(--c-aurora-2),transparent)] blur-2xl"
            style={{ animationDelay: "-7s" }}
          />
        </div>

        <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
          <Eyebrow immediate index={latest ? `v${latest.version}` : "—"} copy={{ en: "Changelog", vi: "Nhật ký thay đổi" }} />
          <h1
            id="releases-title"
            className="max-w-4xl text-[clamp(2.75rem,7vw,5.5rem)] leading-[1.02] font-semibold tracking-[-0.045em]"
          >
            <SplitText copy={{ en: "Release *notes.*", vi: "Bản *phát* *hành.*" }} delay={0.05} />
          </h1>
          <Rise delay={0.3}>
            <p className="mt-6 max-w-[56ch] text-lg leading-relaxed text-muted">
              <T
                en="Everything that changed in CB File Hub, release by release. Build and CI housekeeping is left out."
                vi="Mọi thay đổi của CB File Hub qua từng phiên bản. Các thay đổi build và CI nội bộ đã được lược bỏ."
              />
            </p>
            <div className="mt-8 flex flex-wrap items-center gap-3">
              <a
                href="/#download"
                className="group inline-flex h-12 items-center gap-2.5 rounded-full bg-accent pr-2 pl-6 font-semibold whitespace-nowrap text-accent-ink shadow-[0_10px_30px_-10px_var(--c-accent)] transition-transform duration-300 hover:-translate-y-0.5 active:scale-[0.98]"
              >
                <T en="Get the latest" vi="Tải bản mới nhất" />
                <span className="grid size-8 place-items-center rounded-full bg-accent-ink/15">
                  <DownloadSimple size={16} weight="bold" />
                </span>
              </a>
              <a
                href={`${links.github}/releases`}
                target="_blank"
                rel="noopener noreferrer"
                className="glass group inline-flex h-12 items-center gap-2 rounded-full px-6 font-semibold whitespace-nowrap transition-colors hover:bg-surface"
              >
                <GithubLogo size={18} weight="fill" />
                <T en="View on GitHub" vi="Xem trên GitHub" />
                <ArrowUpRight size={15} weight="bold" className="transition-transform group-hover:translate-x-0.5 group-hover:-translate-y-0.5" />
              </a>
            </div>
          </Rise>

          <Rise delay={0.4}>
            <dl className="mt-14 grid grid-cols-2 gap-px overflow-hidden rounded-[20px] border border-line bg-line sm:grid-cols-4">
              {stats.map((s) => (
                <div key={s.label.en} className="bg-surface/80 px-5 py-5 backdrop-blur sm:px-6">
                  <dt className="text-sm text-muted">
                    <T {...s.label} />
                  </dt>
                  <dd className="mt-1 text-3xl font-semibold tracking-[-0.03em] tabular-nums">{s.value}</dd>
                </div>
              ))}
            </dl>
          </Rise>
        </div>
      </section>

      <div className="mx-auto grid max-w-7xl grid-cols-[minmax(0,1fr)] gap-10 px-4 pb-24 sm:px-6 sm:pb-32 lg:grid-cols-[13rem_minmax(0,1fr)] lg:gap-16 lg:px-8">
        {/* Version index: sticky on desktop, a horizontal scroller on small screens. */}
        <nav aria-label="Versions" className="min-w-0 lg:sticky lg:top-28 lg:self-start">
          <p className="mb-3 text-xs font-semibold tracking-wide text-muted uppercase">
            <T en="Versions" vi="Phiên bản" />
          </p>
          <ol className="-mx-4 flex gap-2 overflow-x-auto px-4 pb-2 lg:mx-0 lg:flex-col lg:gap-0.5 lg:overflow-visible lg:px-0">
            {releases.map((r, i) => (
              <li key={r.tag} className="shrink-0">
                <a
                  href={`#${anchor(r)}`}
                  aria-current={current === r.tag ? "location" : undefined}
                  className="flex items-baseline justify-between gap-3 rounded-xl border border-line px-3 py-2 text-sm transition-colors hover:bg-surface aria-[current=location]:border-accent/30 aria-[current=location]:bg-accent-soft aria-[current=location]:text-accent lg:border-transparent"
                >
                  <span className="font-semibold tabular-nums">
                    v{r.version}
                    {i === 0 && <span className="ml-1.5 inline-block size-1.5 -translate-y-0.5 rounded-full bg-accent" />}
                  </span>
                  <span className="text-xs text-muted">
                    <DateText iso={r.date} />
                  </span>
                </a>
              </li>
            ))}
          </ol>
          <a
            href="#top"
            onClick={(e) => {
              e.preventDefault();
              window.scrollTo({ top: 0, behavior: "smooth" });
            }}
            className="mt-4 hidden items-center gap-1.5 px-3 text-xs font-medium text-muted transition-colors hover:text-ink lg:inline-flex"
          >
            <ArrowRight size={12} weight="bold" className="-rotate-90" />
            <T en="Back to top" vi="Lên đầu trang" />
          </a>
        </nav>

        <div className="relative grid gap-8 lg:pl-10">
          <div aria-hidden className="absolute top-2 bottom-2 left-0 hidden w-px bg-gradient-to-b from-accent via-line to-transparent lg:block" />
          {releases.map((r, i) => (
            <ReleaseCard key={r.tag} release={r} latest={i === 0} />
          ))}
        </div>
      </div>
    </Layout>
  );
}

export const Head: HeadFC = () => (
  <Seo
    title="Release notes - CB File Hub"
    description="What changed in each CB File Hub release for Windows and Android: new features, fixes, improvements and downloads."
    path="/releases"
  />
);
