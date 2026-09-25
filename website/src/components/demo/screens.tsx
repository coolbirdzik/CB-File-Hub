import * as React from "react";
import {
  ArrowSquareOut,
  Broom,
  CaretDown,
  CaretRight,
  Check,
  Cloud,
  DotsThree,
  DownloadSimple,
  FolderSimple,
  GearSix,
  GlobeSimple,
  HardDrive,
  House,
  Image as ImageIcon,
  ImagesSquare,
  Key,
  Lightbulb,
  LockKey,
  MagnifyingGlass,
  Camera,
  Plus,
  PlusCircle,
  PushPin,
  ShieldCheck,
  Tag,
  TerminalWindow,
  VideoCamera,
  WifiSlash,
  X,
  type Icon,
} from "@phosphor-icons/react";
import {
  accents,
  byId,
  childrenOf,
  entries,
  type Entry,
  folderSize,
  formatDate,
  formatSize,
  isMedia,
  tags,
  toneBackground,
} from "./data";
import { useDemo } from "./context";
import { FileGlyph, IconButton, SectionTitle, Thumb } from "./ui";

/* ------------------------------------------------------------------ Home */

export function HomeScreen() {
  const { t, navigate, openInNewTab, compact } = useDemo();
  const actions: Array<{ icon: Icon; title: string; desc: string; go: () => void }> = [
    { icon: PlusCircle, title: t("New Tab", "Tab mới"), desc: t("Open a new file browser tab", "Mở tab trình duyệt tệp mới"), go: () => openInNewTab("fs:demo") },
    { icon: FolderSimple, title: t("Browse Files", "Duyệt tệp"), desc: t("Explore your local files and folders", "Khám phá các tệp và thư mục cục bộ"), go: () => navigate("fs:demo") },
    { icon: ImageIcon, title: t("Image Gallery", "Thư viện ảnh"), desc: t("View images and videos in gallery", "Xem hình ảnh và video trong thư viện"), go: () => navigate("#gallery") },
    { icon: VideoCamera, title: t("Video Gallery", "Thư viện video"), desc: t("View images and videos in gallery", "Xem hình ảnh và video trong thư viện"), go: () => navigate("#videos") },
    { icon: Tag, title: t("Tags", "Thẻ"), desc: t("Organize with smart tags", "Tổ chức với thẻ thông minh"), go: () => navigate("#tags") },
  ];
  const pinned = ["pictures", "downloads"].map((id) => byId.get(id)!);

  return (
    <div className="h-full overflow-y-auto">
      <div className={`mx-auto max-w-[860px] ${compact ? "px-4 py-5" : "px-8 py-7"}`}>
        <section className="rounded-[22px] bg-[linear-gradient(135deg,var(--a-accent-soft),var(--a-accent-softer))] p-5 sm:p-6">
          <div className="flex items-start gap-4">
            <House size={30} weight="light" className="mt-1 shrink-0 text-app-accent-strong" />
            <div>
              <h2 className="text-[21px] leading-tight font-bold tracking-[-0.02em] text-app-accent-strong">
                {t("Welcome to CB File Hub", "Chào mừng đến với CB File Hub")}
              </h2>
              <p className="mt-1 text-[13px] text-app-accent-strong/75">
                {t("Your powerful file management companion", "Trợ lý quản lý tệp mạnh mẽ của bạn")}
              </p>
            </div>
          </div>
          <div className="mt-4 flex items-center gap-3 rounded-2xl bg-white/70 px-4 py-3 text-[12.5px]">
            <Lightbulb size={17} weight="light" className="shrink-0 text-app-accent-strong" />
            {t("Tip: Use quick actions below to get started quickly", "Mẹo: Sử dụng các hành động nhanh bên dưới để bắt đầu nhanh chóng")}
          </div>
        </section>

        <div className="mt-7">
          <SectionTitle title={t("Quick Actions", "Hành động nhanh")} pill={t("Start here", "Bắt đầu tại đây")} />
        </div>
        <div className={`mt-4 grid gap-3 ${compact ? "grid-cols-2" : "grid-cols-3"}`}>
          {actions.map((a) => (
            <button
              key={a.title}
              type="button"
              onClick={a.go}
              className="flex h-32 flex-col items-center justify-center gap-1.5 rounded-2xl bg-app-surface px-3 text-center shadow-[0_1px_2px_rgb(20_30_40/0.04)] ring-1 ring-app-line transition hover:-translate-y-0.5 hover:ring-app-accent/40 active:translate-y-0"
            >
              <a.icon size={24} weight="light" className="text-app-accent-strong" />
              <span className="mt-1 text-[13.5px] font-semibold">{a.title}</span>
              <span className="text-[11.5px] leading-snug text-app-muted">{a.desc}</span>
            </button>
          ))}
        </div>

        <section className="mt-7 rounded-2xl bg-app-surface p-5 ring-1 ring-app-line">
          <div className="flex items-center gap-2.5">
            <PushPin size={18} weight="light" className="text-app-accent-strong" />
            <h3 className="text-[15px] font-bold">{t("Pinned", "Đã ghim")}</h3>
          </div>
          <div className="mt-3 flex flex-wrap gap-2">
            {pinned.map((e) => (
              <button
                key={e.id}
                type="button"
                onClick={() => navigate(`fs:${e.id}`)}
                className="flex items-center gap-2 rounded-lg bg-app-bg px-3 py-2 text-[12.5px] ring-1 ring-app-line hover:bg-app-hover"
              >
                <FileGlyph entry={e} size={17} />
                {e.name}
              </button>
            ))}
          </div>
        </section>
      </div>
    </div>
  );
}

/* --------------------------------------------------------------- Browser */

export type SortKey = "name" | "size" | "date";

export function sortEntries(list: Entry[], key: SortKey) {
  const folders = list.filter((e) => e.kind === "folder" || e.kind === "drive");
  const files = list.filter((e) => e.kind !== "folder" && e.kind !== "drive");
  const cmp = (a: Entry, b: Entry) =>
    key === "size" ? (b.size ?? 0) - (a.size ?? 0) : key === "date" ? b.modified.localeCompare(a.modified) : a.name.localeCompare(b.name);
  return [...folders.sort((a, b) => a.name.localeCompare(b.name)), ...files.sort(cmp)];
}

export function BrowserScreen({ items, empty }: { items: Entry[]; empty: string }) {
  const { selected, select, open, view, compact, showContextMenu, t, lang } = useDemo();

  if (items.length === 0) {
    return (
      <div className="grid h-full place-items-center text-center text-[12.5px] text-app-muted">
        <div>
          <FolderSimple size={42} weight="thin" className="mx-auto mb-2 text-app-muted/70" />
          {empty}
        </div>
      </div>
    );
  }

  const handlers = (e: Entry) => ({
    onClick: (ev: React.MouseEvent) => {
      ev.stopPropagation();
      compact ? open(e) : select(e.id);
    },
    onDoubleClick: () => !compact && open(e),
    onContextMenu: (ev: React.MouseEvent) => {
      ev.preventDefault();
      ev.stopPropagation();
      select(e.id);
      showContextMenu(e, ev.clientX, ev.clientY);
    },
    onKeyDown: (ev: React.KeyboardEvent) => {
      if (ev.key === "Enter") open(e);
    },
  });

  if (view === "list" || compact) {
    return (
      <div className="h-full overflow-y-auto py-1" onClick={() => select(null)}>
        {!compact && (
          <div className="sticky top-0 z-10 grid grid-cols-[1fr_110px_120px] gap-4 border-b border-app-line bg-app-bg px-4 py-1.5 text-[11px] text-app-muted">
            <span>{t("Name", "Tên")}</span>
            <span className="text-right">{t("Size", "Kích thước")}</span>
            <span>{t("Modified", "Ngày sửa")}</span>
          </div>
        )}
        {items.map((e) => (
          <button
            key={e.id}
            type="button"
            {...handlers(e)}
            className={`w-full text-left ${
              compact ? "flex items-center gap-3.5 px-4 py-2.5" : "grid grid-cols-[1fr_110px_120px] items-center gap-4 px-4 py-[7px]"
            } ${selected === e.id ? "bg-app-accent-soft" : "hover:bg-app-hover"}`}
          >
            {compact ? (
              <>
                {e.tone ? (
                  <span className="size-10 shrink-0 rounded-xl" style={{ background: toneBackground[e.tone] }} />
                ) : (
                  <span className="grid size-10 shrink-0 place-items-center">
                    <FileGlyph entry={e} size={28} />
                  </span>
                )}
                <span className="min-w-0">
                  <span className="block truncate text-[14px]">{e.name}</span>
                  <span className="block text-[12px] text-app-muted">
                    {e.kind === "folder" ? `${childrenOf(e.id).length} ${t("items", "mục")}` : formatSize(e.size ?? 0)}
                  </span>
                </span>
              </>
            ) : (
              <>
                <span className="flex min-w-0 items-center gap-3 text-[13px]">
                  <FileGlyph entry={e} />
                  <span className="truncate">{e.name}</span>
                </span>
                <span className="text-right text-[12px] text-app-muted">
                  {e.kind === "folder" ? "" : formatSize(e.size ?? 0)}
                </span>
                <span className="text-[12px] text-app-muted">{formatDate(e.modified, lang)}</span>
              </>
            )}
          </button>
        ))}
      </div>
    );
  }

  return (
    <div className="h-full overflow-y-auto p-3" onClick={() => select(null)}>
      <div className="grid grid-cols-[repeat(auto-fill,minmax(118px,1fr))] gap-x-3 gap-y-4">
        {items.map((e) => (
          <button
            key={e.id}
            type="button"
            {...handlers(e)}
            className={`group flex flex-col items-stretch rounded-lg p-1.5 pt-2.5 text-center outline-offset-0 transition-colors ${
              selected === e.id ? "bg-app-accent-soft" : "hover:bg-app-hover"
            }`}
          >
            <Thumb entry={e} className="aspect-square w-full" />
            <span className="mt-1.5 line-clamp-2 px-0.5 text-[11.5px] leading-tight break-all">{e.name}</span>
          </button>
        ))}
      </div>
    </div>
  );
}

/* --------------------------------------------------------------- Preview */

export function PreviewPane({ entry, onClose }: { entry: Entry | null; onClose: () => void }) {
  const { t, lang, toast } = useDemo();
  return (
    <aside className="flex h-full w-full flex-col bg-app-bg">
      <div className="flex h-9 items-center gap-1 px-3 text-[11.5px] text-app-muted">
        <span className="min-w-0 flex-1 truncate">{entry ? entry.name : t("Preview", "Xem trước")}</span>
        {entry && (
          <IconButton icon={ArrowSquareOut} size={14} label={t("Open", "Mở")} onClick={() => toast(t("Opens with the default app on your PC", "Mở bằng ứng dụng mặc định trên máy"))} className="size-6" />
        )}
        <IconButton icon={X} size={14} label={t("Close preview", "Đóng xem trước")} onClick={onClose} className="size-6" />
      </div>
      {!entry ? (
        <div className="grid flex-1 place-items-center text-center text-[11.5px] text-app-muted">
          <div>
            <ImageIcon size={26} weight="light" className="mx-auto mb-2" />
            {t("Select a file to preview", "Chọn tệp để xem trước")}
          </div>
        </div>
      ) : (
        <div className="flex-1 overflow-y-auto px-3 pb-4">
          <div className="overflow-hidden rounded-lg bg-app-surface ring-1 ring-app-line">
            <Thumb entry={entry} className="aspect-[4/3] w-full !rounded-none" />
          </div>
          <dl className="mt-4 space-y-2.5 text-[12px]">
            {[
              [t("Type", "Loại"), entry.kind === "folder" ? t("Folder", "Thư mục") : entry.name.split(".").pop()!.toUpperCase()],
              [t("Size", "Kích thước"), formatSize(entry.kind === "folder" ? folderSize(entry.id) : entry.size ?? 0)],
              [t("Modified", "Ngày sửa"), formatDate(entry.modified, lang)],
            ].map(([k, v]) => (
              <div key={k} className="flex justify-between gap-3">
                <dt className="text-app-muted">{k}</dt>
                <dd className="truncate font-medium">{v}</dd>
              </div>
            ))}
          </dl>
          {entry.tags && entry.tags.length > 0 && (
            <div className="mt-4 flex flex-wrap gap-1.5">
              {entry.tags.map((id) => {
                const tag = tags.find((x) => x.id === id)!;
                return (
                  <span key={id} className="inline-flex items-center gap-1.5 rounded-full bg-app-surface px-2.5 py-1 text-[11px] ring-1 ring-app-line">
                    <span className="size-2 rounded-full" style={{ background: tag.color }} />
                    {tag.name[lang]}
                  </span>
                );
              })}
            </div>
          )}
        </div>
      )}
    </aside>
  );
}

/* ----------------------------------------------------------- Gallery Hub */

export function GalleryHub() {
  const { t, navigate, compact } = useDemo();
  const imageCount = entries.filter((e) => e.kind === "image").length;
  const cards: Array<{ icon: Icon; title: string; desc: string; route: string }> = [
    { icon: ImageIcon, title: t("All Pictures", "Tất cả ảnh"), desc: t("Browse all your pictures", "Duyệt tất cả hình ảnh của bạn"), route: "#all-images" },
    { icon: FolderSimple, title: t("Albums", "Album"), desc: t("Organize in albums", "Tổ chức trong album"), route: "fs:albums" },
    { icon: Camera, title: t("Pictures", "Ảnh"), desc: t("Pictures folder", "Thư mục Ảnh"), route: "fs:pictures" },
    { icon: DownloadSimple, title: t("Downloads", "Tải xuống"), desc: t("Downloaded files", "Tệp đã tải xuống"), route: "fs:downloads" },
  ];
  const album = childrenOf("weekend").filter(isMedia).slice(0, 4);

  return (
    <div className="h-full overflow-y-auto">
      <div className={compact ? "p-4" : "p-6"}>
        <section className="flex items-center gap-4 rounded-[20px] bg-app-accent-soft px-5 py-5">
          <ImagesSquare size={26} weight="light" className="shrink-0 text-app-accent-strong" />
          <div className="min-w-0 flex-1">
            <h2 className="text-[17px] font-semibold text-app-accent-strong">{t("Gallery Hub", "Thư viện ảnh")}</h2>
            <p className="text-[12.5px] text-app-accent-strong/75">{t("Manage your photos and albums", "Quản lý ảnh và album của bạn")}</p>
          </div>
          <div className="rounded-xl bg-app-surface px-4 py-2 text-center">
            <div className="text-[16px] font-semibold text-app-accent-strong">{imageCount}</div>
            <div className="text-[11px] text-app-muted">{t("Images", "Ảnh")}</div>
          </div>
        </section>

        <div className="mt-6">
          <SectionTitle title={t("Gallery Actions", "Thao tác thư viện")} pill={t("Quick Access", "Truy cập nhanh")} />
        </div>
        <div className={`mt-4 grid gap-3 ${compact ? "grid-cols-2" : "grid-cols-4"}`}>
          {cards.map((c) => (
            <button
              key={c.route}
              type="button"
              onClick={() => navigate(c.route)}
              className="flex h-36 flex-col items-center justify-center gap-1 rounded-2xl bg-app-surface/70 px-3 text-center ring-1 ring-app-line transition hover:bg-app-surface hover:ring-app-accent/40"
            >
              <c.icon size={24} weight="light" className="text-app-accent-strong" />
              <span className="mt-1.5 text-[13px] font-medium">{c.title}</span>
              <span className="text-[11.5px] text-app-muted">{c.desc}</span>
            </button>
          ))}
        </div>

        <div className="mt-7 flex items-center justify-between">
          <SectionTitle title={t("Featured Albums", "Album nổi bật")} pill={t("Personalized", "Cá nhân hóa")} muted />
          <GearSix size={16} weight="light" className="text-app-muted" />
        </div>
        <button
          type="button"
          onClick={() => navigate("fs:weekend")}
          className="mt-4 w-full max-w-[300px] overflow-hidden rounded-2xl bg-app-surface text-left ring-1 ring-app-line transition hover:ring-app-accent/40"
        >
          <div className="grid aspect-[16/9] grid-cols-2 grid-rows-2 gap-0.5">
            {album.map((e) => (
              <span key={e.id} style={{ background: toneBackground[e.tone!] }} />
            ))}
          </div>
          <div className="px-4 py-3">
            <div className="text-[13px] font-medium">Weekend Picks</div>
            <div className="text-[11.5px] text-app-muted">
              {childrenOf("weekend").length} {t("items", "mục")}
            </div>
          </div>
        </button>
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ Tags */

export function TagsScreen() {
  const { t, lang, navigate, toast, compact } = useDemo();
  const [collapsed, setCollapsed] = React.useState<Set<string>>(new Set());
  const [selected, setSelected] = React.useState<string | null>("beach");

  const rows: Array<{ id: string; depth: number }> = [];
  const walk = (parent: string | undefined, depth: number) => {
    for (const tag of tags.filter((x) => x.parent === parent)) {
      rows.push({ id: tag.id, depth });
      if (!collapsed.has(tag.id)) walk(tag.id, depth + 1);
    }
  };
  walk(undefined, 0);

  return (
    <div className="relative h-full overflow-y-auto">
      <div className="flex items-center gap-2 px-5 pt-4 pb-2 text-[13px] font-medium text-app-muted">
        <Tag size={17} weight="light" className="text-app-accent" />
        {tags.length} {t("tags created", "thẻ đã tạo")}
      </div>
      <div role="tree" aria-label={t("Tags", "Thẻ")} className="pb-20">
        {rows.map(({ id, depth }) => {
          const tag = tags.find((x) => x.id === id)!;
          const hasKids = tags.some((x) => x.parent === id);
          return (
            <div
              key={id}
              role="treeitem"
              aria-selected={selected === id}
              aria-expanded={hasKids ? !collapsed.has(id) : undefined}
              tabIndex={0}
              onClick={() => (compact ? navigate(`tag:${id}`) : setSelected(id))}
              onDoubleClick={() => navigate(`tag:${id}`)}
              onKeyDown={(e) => e.key === "Enter" && navigate(`tag:${id}`)}
              className={`flex h-9 cursor-default items-center gap-2 pr-4 text-[13px] ${
                selected === id ? "bg-app-accent-soft" : "hover:bg-app-hover"
              }`}
              style={{ paddingLeft: 12 + depth * 16 }}
            >
              {hasKids ? (
                <button
                  type="button"
                  aria-label={collapsed.has(id) ? t("Expand", "Mở rộng") : t("Collapse", "Thu gọn")}
                  onClick={(e) => {
                    e.stopPropagation();
                    setCollapsed((prev) => {
                      const next = new Set(prev);
                      next.has(id) ? next.delete(id) : next.add(id);
                      return next;
                    });
                  }}
                  className="grid size-4 place-items-center text-app-muted"
                >
                  {collapsed.has(id) ? <CaretRight size={11} /> : <CaretDown size={11} />}
                </button>
              ) : (
                <span className="size-4" />
              )}
              <span className="size-2.5 rounded-full" style={{ background: tag.color }} />
              <span className="flex-1">{tag.name[lang]}</span>
            </div>
          );
        })}
      </div>
      <p className="px-5 pb-6 text-[11.5px] text-app-muted">
        {compact
          ? t("Tap a tag to see its files.", "Chạm vào thẻ để xem các tệp.")
          : t("Double-click a tag to see its files.", "Nhấp đúp vào thẻ để xem các tệp.")}
      </p>
      <button
        type="button"
        aria-label={t("New tag", "Thẻ mới")}
        onClick={() => toast(t("Creating tags is off in the demo", "Bản demo không tạo thẻ mới"))}
        className="absolute right-4 bottom-4 grid size-12 place-items-center rounded-xl bg-app-accent text-white shadow-md transition hover:brightness-105 active:scale-95"
      >
        <Plus size={20} weight="light" />
      </button>
    </div>
  );
}

/* --------------------------------------------------------------- Network */

export function NetworkScreen() {
  const { t, toast, navigate } = useDemo();
  const services: Array<{ icon: Icon; name: string; desc: string; go?: () => void }> = [
    { icon: FolderSimple, name: "SMB", desc: t("Windows Shared Folders (SMB via Win32)", "Thư mục chia sẻ Windows (SMB qua Win32)") },
    { icon: Cloud, name: "FTP", desc: "File Transfer Protocol (FTP)" },
    { icon: LockKey, name: "SFTP", desc: "SSH File Transfer Protocol" },
    { icon: GlobeSimple, name: "WebDAV", desc: "Web Distributed Authoring and Versioning" },
    { icon: TerminalWindow, name: t("SSH workspace", "Không gian SSH"), desc: "Hosts · SSH keys · Terminal", go: () => navigate("#ssh") },
  ];
  return (
    <div className="h-full overflow-y-auto">
      <h3 className="px-5 pt-5 text-[14px] font-semibold">{t("Active Connections", "Kết nối đang hoạt động")}</h3>
      <div className="flex flex-col items-center py-8 text-center">
        <WifiSlash size={34} weight="light" className="text-app-muted" />
        <p className="mt-3 text-[13px] text-app-muted">{t("No active network connections", "Không có kết nối mạng đang hoạt động")}</p>
        <p className="mt-1 text-[11.5px] text-app-muted">{t("Use the (+) button to add a new connection", "Dùng nút (+) để thêm kết nối mới")}</p>
      </div>
      <div className="border-t border-app-line" />
      <h3 className="px-5 pt-5 pb-2 text-[14px] font-semibold">{t("Available Services", "Dịch vụ có sẵn")}</h3>
      {services.map((s) => (
        <button
          key={s.name}
          type="button"
          onClick={s.go ?? (() => toast(t(`Demo only: no ${s.name} connection is made`, `Chỉ là demo: không kết nối ${s.name} thật`)))}
          className="flex w-full items-center gap-3.5 px-5 py-2.5 text-left hover:bg-app-hover"
        >
          <s.icon size={18} weight="light" className="text-app-accent" />
          <span>
            <span className="block text-[13px]">{s.name}</span>
            <span className="block text-[11.5px] text-app-muted">{s.desc}</span>
          </span>
        </button>
      ))}
    </div>
  );
}

export function SshScreen() {
  const { t, toast } = useDemo();
  const [tab, setTab] = React.useState<"hosts" | "keys" | "known">("hosts");
  const chips = [
    { id: "hosts" as const, label: "Hosts" },
    { id: "keys" as const, label: t("SSH keys", "SSH key") },
    { id: "known" as const, label: t("Trusted hosts", "Máy chủ đã tin cậy") },
  ];
  return (
    <div className="h-full overflow-y-auto p-4">
      <div className="flex flex-wrap items-center gap-2">
        {chips.map((c) => (
          <button
            key={c.id}
            type="button"
            onClick={() => setTab(c.id)}
            className={`inline-flex h-8 items-center gap-1.5 rounded-full px-3.5 text-[12px] ${
              tab === c.id ? "bg-app-accent-soft text-app-accent-strong" : "bg-app-field text-app-text"
            }`}
          >
            {tab === c.id && <Check size={13} weight="bold" />}
            {c.label}
          </button>
        ))}
        <button type="button" onClick={() => toast(t("Adding hosts is off in the demo", "Bản demo không thêm máy chủ"))} className="inline-flex h-8 items-center gap-1.5 rounded-md bg-app-field px-3 text-[12px]">
          <Plus size={13} /> {t("Add host", "Thêm máy chủ")}
        </button>
        <button type="button" onClick={() => toast(t("Keys never leave your device in the app", "Trong app, khóa không bao giờ rời khỏi máy"))} className="inline-flex h-8 items-center gap-1.5 rounded-md bg-app-field px-3 text-[12px]">
          <Key size={13} /> {t("Import private key", "Nhập private key")}
        </button>
      </div>
      <div className="mt-3 flex h-9 items-center gap-2 rounded-md bg-app-field px-3 text-[12.5px] text-app-muted">
        <MagnifyingGlass size={15} /> {t("Search", "Tìm kiếm")}
      </div>
      {tab === "hosts" ? (
        <button
          type="button"
          onClick={() => toast(t("Demo only: the terminal is not connected", "Chỉ là demo: terminal không kết nối thật"))}
          className="mt-3 w-full max-w-[300px] overflow-hidden rounded-lg bg-app-field/60 text-left ring-1 ring-app-line hover:ring-app-accent/40"
        >
          <div className="flex gap-3 p-3">
            <span className="grid size-9 place-items-center rounded-md bg-app-surface text-app-accent">
              <TerminalWindow size={18} weight="light" />
            </span>
            <span className="min-w-0 flex-1">
              <span className="block text-[13px] font-semibold">Demo staging server</span>
              <span className="block truncate font-mono text-[11px] text-app-muted">deploy@staging.example.com:22</span>
              <span className="block text-[11px] text-app-muted">Password</span>
            </span>
            <DotsThree size={16} className="text-app-muted" />
          </div>
          <div className="flex gap-3 bg-app-field px-3 py-2 text-app-muted">
            <TerminalWindow size={14} />
            <FolderSimple size={14} />
          </div>
        </button>
      ) : (
        <p className="mt-8 text-center text-[12.5px] text-app-muted">{t("Nothing here yet", "Chưa có gì ở đây")}</p>
      )}
    </div>
  );
}

/* --------------------------------------------------------- Disk cleaner */

const usage = [
  { name: "Users", size: 54, pct: 42, files: 84210, depth: 0, kind: "" },
  { name: "Demo", size: 37, pct: 69, files: 51240, depth: 1, kind: "" },
  { name: "AppData", size: 14, pct: 38, files: 26100, depth: 2, kind: "" },
  { name: "Temp", size: 6, pct: 43, files: 14820, depth: 3, kind: "TEMP" },
  { name: "GPUCache", size: 1.17, pct: 8, files: 3420, depth: 3, kind: "BROWSER" },
  { name: "Downloads", size: 8, pct: 22, files: 2740, depth: 2, kind: "" },
  { name: "Windows", size: 29, pct: 23, files: 62100, depth: 0, kind: "" },
  { name: "SoftwareDistribution", size: 4.1, pct: 14, files: 940, depth: 1, kind: "WIN UPDATE" },
  { name: "$Recycle.Bin", size: 3.03, pct: 2, files: 126, depth: 0, kind: "RECYCLE" },
];

export function CleanerScreen() {
  const { t, compact, toast, openAgent } = useDemo();
  const [checked, setChecked] = React.useState<Set<string>>(new Set());
  const cleanable = usage.filter((u) => u.kind);
  const selectedGb = cleanable.filter((u) => checked.has(u.name)).reduce((s, u) => s + u.size, 0);

  return (
    <div className="flex h-full">
      {!compact && (
        <aside className="w-[210px] shrink-0 border-r border-app-line p-3">
          <div className="flex gap-2.5 p-2">
            <Broom size={20} weight="light" className="mt-0.5 shrink-0 text-app-accent" />
            <div>
              <div className="text-[13px] font-semibold">CB Agent Cleaner</div>
              <div className="text-[11px] leading-snug text-app-muted">
                {t("Utilities that help keep this PC fast and organized", "Các tiện ích giúp máy tính gọn gàng và hoạt động tốt hơn")}
              </div>
            </div>
          </div>
          <div className="mt-3 px-2 text-[10.5px] font-semibold tracking-wide text-app-muted">STORAGE</div>
          <div className="mt-1.5 rounded-lg bg-app-field/80 p-2.5">
            <div className="text-[12.5px] font-medium">{t("Disk usage", "Dung lượng ổ đĩa")}</div>
            <div className="text-[11px] text-app-muted">{t("Inspect folders and safely clean confirmed junk", "Kiểm tra thư mục và dọn rác đã xác nhận")}</div>
          </div>
        </aside>
      )}
      <div className="flex min-w-0 flex-1 flex-col">
        <div className="flex flex-wrap items-center gap-2 border-b border-app-line px-4 py-2.5 text-[12px]">
          <HardDrive size={15} weight="light" className="text-app-accent" />
          <span className="font-medium">C:\ 128.00 GB</span>
          <span className="ml-auto rounded-md bg-[#fff1dc] px-2 py-1 font-medium text-[#b25e00]">Junk: 14.30 GB</span>
          <button type="button" onClick={() => setChecked(new Set(cleanable.map((u) => u.name)))} className="px-1.5 font-medium text-app-accent-strong">
            {t("Check all cleanable", "Chọn tất cả có thể dọn")}
          </button>
          <button type="button" onClick={openAgent} className="rounded-full bg-app-accent px-3 py-1.5 font-medium text-white">
            {t("Ask CB Agent", "Hỏi CB Agent")}
          </button>
        </div>
        <div className="min-h-0 flex-1 overflow-y-auto">
          <div className="grid grid-cols-[22px_1fr_70px_90px] gap-2 border-b border-app-line px-4 py-1.5 text-[11px] text-app-muted sm:grid-cols-[22px_1fr_70px_120px_70px]">
            <span />
            <span>{t("Name", "Tên")}</span>
            <span className="text-right">{t("Size", "Kích thước")}</span>
            <span>% {t("of Parent", "thư mục cha")}</span>
            <span className="hidden text-right sm:block">{t("Files", "Tệp")}</span>
          </div>
          {usage.map((u) => (
            <label
              key={u.name}
              className={`grid cursor-default grid-cols-[22px_1fr_70px_90px] items-center gap-2 px-4 py-1.5 text-[12px] sm:grid-cols-[22px_1fr_70px_120px_70px] ${u.kind ? "bg-[#fffaf2]" : ""}`}
            >
              {u.kind ? (
                <input
                  type="checkbox"
                  checked={checked.has(u.name)}
                  onChange={() =>
                    setChecked((prev) => {
                      const next = new Set(prev);
                      next.has(u.name) ? next.delete(u.name) : next.add(u.name);
                      return next;
                    })
                  }
                  className="size-3.5 accent-[var(--a-accent)]"
                />
              ) : (
                <span />
              )}
              <span className={`flex min-w-0 items-center gap-1.5 ${u.kind ? "text-[#c46a00]" : ""}`} style={{ paddingLeft: u.depth * 14 }}>
                <FolderSimple size={14} weight="light" className="shrink-0" />
                <span className="truncate">{u.name}</span>
                {u.kind && <span className="ml-1 rounded bg-[#fff1dc] px-1 text-[9px] font-semibold">{u.kind}</span>}
              </span>
              <span className="text-right">{u.size >= 10 ? u.size.toFixed(2) : u.size.toFixed(2)} GB</span>
              <span className="flex items-center gap-2">
                <span className="h-2 flex-1 overflow-hidden rounded-sm bg-app-field">
                  <span className="block h-full" style={{ width: `${u.pct}%`, background: u.kind ? "#f59e0b" : "#5cb85c" }} />
                </span>
                <span className="w-8 text-right text-app-muted">{u.pct}%</span>
              </span>
              <span className="hidden text-right text-app-muted sm:block">{u.files.toLocaleString("en-US")}</span>
            </label>
          ))}
        </div>
        <div className="flex items-center gap-3 border-t border-app-line px-4 py-2 text-[12px]">
          <Broom size={15} weight="light" className="text-[#c46a00]" />
          {t("Selected", "Đã chọn")}: {selectedGb.toFixed(2)} GB / 14.30 GB
          <button
            type="button"
            disabled={!checked.size}
            onClick={() => toast(t("Demo only: nothing was deleted", "Chỉ là demo: không có gì bị xóa"))}
            className="ml-auto rounded-full bg-app-accent px-3.5 py-1.5 font-medium text-white disabled:bg-app-field disabled:text-app-muted"
          >
            {t("Review & clean", "Xem lại & dọn")}
          </button>
        </div>
      </div>
    </div>
  );
}

/* -------------------------------------------------------------- Settings */

export function SettingsScreen() {
  const { t, lang, setLang, accent, setAccent } = useDemo();
  return (
    <div className="h-full overflow-y-auto">
      <div className="mx-auto max-w-[640px] space-y-4 p-6">
        <h2 className="text-[20px] font-bold tracking-[-0.02em]">{t("Settings", "Cài đặt")}</h2>
        <section className="rounded-2xl bg-app-surface p-5 ring-1 ring-app-line">
          <div className="text-[13.5px] font-semibold">{t("Language", "Ngôn ngữ")}</div>
          <div className="text-[12px] text-app-muted">{t("Select the language you want to use", "Chọn ngôn ngữ bạn muốn sử dụng")}</div>
          <div className="mt-3 flex gap-2">
            {(["en", "vi"] as const).map((code) => (
              <button
                key={code}
                type="button"
                aria-pressed={lang === code}
                onClick={() => setLang(code)}
                className={`rounded-lg px-4 py-2 text-[12.5px] ring-1 ${
                  lang === code ? "bg-app-accent-soft font-semibold text-app-accent-strong ring-app-accent/40" : "ring-app-line hover:bg-app-hover"
                }`}
              >
                {code === "en" ? "English" : "Tiếng Việt"}
              </button>
            ))}
          </div>
        </section>
        <section className="rounded-2xl bg-app-surface p-5 ring-1 ring-app-line">
          <div className="text-[13.5px] font-semibold">{t("Accent color", "Màu nhấn")}</div>
          <div className="text-[12px] text-app-muted">
            {t("Current accent", "Màu nhấn hiện tại")}: {accents.find((a) => a.hex === accent)?.name[lang]}
          </div>
          <div className="mt-3 flex flex-wrap gap-2.5">
            {accents.map((a) => (
              <button
                key={a.id}
                type="button"
                aria-label={a.name[lang]}
                aria-pressed={accent === a.hex}
                onClick={() => setAccent(a.hex)}
                className="grid size-9 place-items-center rounded-full ring-offset-2 transition hover:scale-105"
                style={{ background: a.hex, boxShadow: accent === a.hex ? `0 0 0 2px #fff, 0 0 0 4px ${a.hex}` : undefined }}
              >
                {accent === a.hex && <Check size={15} weight="bold" color="#fff" />}
              </button>
            ))}
          </div>
        </section>
        <section className="flex items-start gap-3 rounded-2xl bg-app-surface p-5 ring-1 ring-app-line">
          <ShieldCheck size={20} weight="light" className="mt-0.5 shrink-0 text-app-accent-strong" />
          <p className="text-[12.5px] leading-relaxed text-app-muted">
            {t(
              "The full app also has themes, fonts, thumbnail and cache options, backup & sync and more.",
              "Bản đầy đủ còn có giao diện, phông chữ, tùy chọn ảnh thu nhỏ và bộ nhớ đệm, sao lưu & đồng bộ và nhiều hơn nữa.",
            )}
          </p>
        </section>
      </div>
    </div>
  );
}
