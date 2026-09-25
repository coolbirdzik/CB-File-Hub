import * as React from "react";
import { AnimatePresence, motion } from "motion/react";
import {
  ArrowClockwise,
  ArrowLeft,
  ArrowRight,
  ArrowUp,
  Bell,
  Broom,
  CaretDown,
  CaretRight,
  CopySimple,
  CornersOut,
  DotsThree,
  DotsThreeVertical,
  Eye,
  FolderSimple,
  GearSix,
  GlobeSimple,
  HardDrive,
  House,
  Image as ImageIcon,
  List,
  ListBullets,
  MagnifyingGlass,
  Minus,
  Pause,
  Play,
  Plus,
  PushPin,
  SidebarSimple,
  SortAscending,
  SpeakerHigh,
  Sparkle,
  SquaresFour,
  Tag,
  TerminalWindow,
  Trash,
  VideoCamera,
  WifiHigh,
  X,
  type Icon,
} from "@phosphor-icons/react";
import { useLang } from "../lang";
import {
  accents,
  byId,
  childrenOf,
  entries,
  type Entry,
  filesWithTag,
  folderSize,
  formatSize,
  isMedia,
  pathOf,
  pathString,
  tagById,
  toneBackground,
} from "./data";
import { DemoContext, type DemoApi, type Route, type TagPrefs } from "./context";
import {
  BrowserScreen,
  CleanerScreen,
  GalleryHub,
  HomeScreen,
  NetworkScreen,
  PreviewPane,
  SettingsScreen,
  SshScreen,
  sortEntries,
  type SortKey,
} from "./screens";
import { AgentPanel } from "./AgentPanel";
import { TagsScreen } from "./TagsScreen";
import { IconButton, Toast } from "./ui";

type Tab = { id: number; history: Route[]; index: number };

const BROWSER_ROUTES = /^(fs:|tag:|#videos$|#all-images$)/;

function routeItems(route: Route): Entry[] {
  if (route.startsWith("fs:")) return childrenOf(route.slice(3));
  if (route.startsWith("tag:")) return filesWithTag(route.slice(4));
  if (route === "#videos") return entries.filter((e) => e.kind === "video");
  if (route === "#all-images") return entries.filter((e) => e.kind === "image");
  return [];
}

/** Tab strip label. Like the app, system screens show their raw "#route". */
function routeLabel(route: Route, lang: "en" | "vi") {
  if (route.startsWith("fs:")) return pathString(route.slice(3));
  // The app names a tag-search tab "Tag: <name>".
  if (route.startsWith("tag:")) return `Tag: ${tagById.get(route.slice(4))?.name[lang] ?? route.slice(4)}`;
  return route;
}

function routeIcon(route: Route): Icon {
  if (route.startsWith("tag:") || route === "#tags") return Tag;
  if (route === "#videos") return VideoCamera;
  if (route === "#all-images" || route === "#gallery") return ImageIcon;
  if (route === "#network" || route === "#ssh") return GlobeSimple;
  return FolderSimple;
}

export function AppDemo({ className = "" }: { className?: string }) {
  const { lang, setLang } = useLang();
  const t = React.useCallback((en: string, vi: string) => (lang === "vi" ? vi : en), [lang]);

  const root = React.useRef<HTMLDivElement>(null);
  const [compact, setCompact] = React.useState(false);
  React.useEffect(() => {
    const el = root.current;
    if (!el) return;
    const ro = new ResizeObserver(([entry]) => setCompact(entry.contentRect.width < 700));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  const tabSeq = React.useRef(3);
  const [tabs, setTabs] = React.useState<Tab[]>([
    { id: 1, history: ["#home"], index: 0 },
    { id: 2, history: ["fs:demo", "fs:pictures"], index: 1 },
    { id: 3, history: ["#tags"], index: 0 },
  ]);
  const [activeId, setActiveId] = React.useState(2);
  const [selected, setSelected] = React.useState<string | null>("p3");
  const [view, setView] = React.useState<"grid" | "list">("grid");
  const [sort, setSort] = React.useState<SortKey>("name");
  const [previewOpen, setPreviewOpen] = React.useState(true);
  const [search, setSearch] = React.useState<string | null>(null);
  const [drawer, setDrawer] = React.useState(false);
  const [agentOpen, setAgentOpen] = React.useState(false);
  const [tabManager, setTabManager] = React.useState(false);
  const [viewer, setViewer] = React.useState<Entry | null>(null);
  const [sheet, setSheet] = React.useState<Entry | null>(null);
  const [menu, setMenu] = React.useState<{ entry: Entry; x: number; y: number } | null>(null);
  const [accent, setAccent] = React.useState(accents[0].hex);
  const [tagPrefs, setTagPrefs] = React.useState<TagPrefs>({ view: null, zoom: 5, sort: "name", ascending: true });
  const [toastMsg, setToastMsg] = React.useState<string | null>(null);
  const toastTimer = React.useRef<number>();

  const tab = tabs.find((x) => x.id === activeId) ?? tabs[0];
  const route = tab.history[tab.index];
  const isBrowser = BROWSER_ROUTES.test(route);
  const folderId = route.startsWith("fs:") ? route.slice(3) : null;

  const toast = React.useCallback((message: string) => {
    setToastMsg(message);
    window.clearTimeout(toastTimer.current);
    toastTimer.current = window.setTimeout(() => setToastMsg(null), 2400);
  }, []);

  const updateTab = (fn: (tab: Tab) => Tab) => setTabs((all) => all.map((x) => (x.id === activeId ? fn(x) : x)));

  const navigate = React.useCallback(
    (next: Route, selectId?: string) => {
      setTabs((all) =>
        all.map((x) => {
          if (x.id !== activeId) return x;
          if (x.history[x.index] === next) return x;
          const history = [...x.history.slice(0, x.index + 1), next];
          return { ...x, history, index: history.length - 1 };
        }),
      );
      setSelected(selectId ?? null);
      setSearch(null);
      setDrawer(false);
      setMenu(null);
      if (selectId && !compact) setPreviewOpen(true);
    },
    [activeId, compact],
  );

  const openInNewTab = React.useCallback((next: Route) => {
    const id = ++tabSeq.current;
    setTabs((all) => [...all, { id, history: [next], index: 0 }]);
    setActiveId(id);
    setSelected(null);
    setSearch(null);
    setDrawer(false);
    setMenu(null);
    setTabManager(false);
  }, []);

  const closeTab = (id: number) => {
    if (tabs.length === 1) {
      // Like the app: closing the last tab leaves a fresh Home tab.
      const fresh = ++tabSeq.current;
      setTabs([{ id: fresh, history: ["#home"], index: 0 }]);
      setActiveId(fresh);
    } else {
      const i = tabs.findIndex((x) => x.id === id);
      const rest = tabs.filter((x) => x.id !== id);
      setTabs(rest);
      if (id === activeId) setActiveId(rest[Math.max(0, i - 1)].id);
    }
    setSelected(null);
  };

  const go = (delta: -1 | 1) => {
    updateTab((x) => ({ ...x, index: Math.min(x.history.length - 1, Math.max(0, x.index + delta)) }));
    setSelected(null);
    setSearch(null);
  };
  const upTarget = folderId ? byId.get(folderId)?.parent ?? null : null;
  const goUp = () => upTarget && navigate(`fs:${upTarget}`, folderId ?? undefined);

  const open = React.useCallback(
    (e: Entry) => {
      setMenu(null);
      if (e.kind === "folder" || e.kind === "drive") return navigate(`fs:${e.id}`);
      setSelected(e.id);
      if (isMedia(e)) return setViewer(e);
      if (compact) return setSheet(e);
      toast(t(`${e.name} opens with its default app`, `${e.name} sẽ mở bằng ứng dụng mặc định`));
    },
    [navigate, compact, toast, t],
  );

  let items = sortEntries(routeItems(route), sort);
  if (search) items = items.filter((e) => e.name.toLowerCase().includes(search.toLowerCase()));
  const selectedEntry = selected ? byId.get(selected) ?? null : null;

  const api: DemoApi = {
    lang,
    t,
    compact,
    route,
    navigate,
    canBack: tab.index > 0,
    canForward: tab.index < tab.history.length - 1,
    back: () => go(-1),
    forward: () => go(1),
    openInNewTab,
    selected,
    select: setSelected,
    open,
    view,
    toast,
    showContextMenu: (entry, x, y) => {
      const box = root.current!.getBoundingClientRect();
      setMenu({ entry, x: Math.min(x - box.left, box.width - 200), y: Math.min(y - box.top, box.height - 220) });
    },
    accent,
    setAccent,
    setLang,
    openAgent: () => setAgentOpen(true),
    tagPrefs,
    setTagPrefs: (patch) => setTagPrefs((prev) => ({ ...prev, ...patch })),
  };

  // Shortcuts only fire while focus is inside the demo, so the landing page keeps its own keys.
  const onKeyDown = (e: React.KeyboardEvent) => {
    const typing = (e.target as HTMLElement).closest("input, textarea");
    if (e.key === "Escape") {
      setMenu(null);
      setViewer(null);
      setSheet(null);
      setDrawer(false);
      setTabManager(false);
      if (search !== null) setSearch(null);
      return;
    }
    if (typing) return;
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "f" && isBrowser) {
      e.preventDefault();
      setSearch("");
    } else if (e.key === "Backspace" && isBrowser) {
      e.preventDefault();
      upTarget ? goUp() : go(-1);
    } else if (e.key === "Delete" && selectedEntry) {
      toast(t("Demo only: nothing was deleted", "Chỉ là demo: không có gì bị xóa"));
    } else if (e.key === "F2" && selectedEntry) {
      e.preventDefault();
      toast(t("Rename is off in the demo", "Bản demo không cho đổi tên"));
    }
  };

  const statusText = selectedEntry
    ? `1 ${t("items selected", "mục đã chọn")}  |  ${formatSize(selectedEntry.kind === "folder" ? folderSize(selectedEntry.id) : selectedEntry.size ?? 0)}`
    : `${items.length} ${t("items", "mục")}`;

  return (
    <DemoContext.Provider value={api}>
      <div
        ref={root}
        onKeyDown={onKeyDown}
        onClick={() => menu && setMenu(null)}
        style={{ "--a-accent": accent } as React.CSSProperties}
        className={`cbfh-app relative isolate flex h-full w-full flex-col overflow-hidden bg-app-bg text-[13px] select-none ${className}`}
      >
        {compact ? (
          <MobileHeader
            label={routeLabel(route, lang)}
            tabCount={tabs.length}
            onMenu={() => setDrawer(true)}
            onNewTab={() => openInNewTab("#home")}
            onTabs={() => setTabManager(true)}
            onSearch={() => isBrowser && setSearch("")}
          />
        ) : (
          <TitleBar
            tabs={tabs}
            activeId={tab.id}
            lang={lang}
            agentOpen={agentOpen}
            onMenu={() => setDrawer(true)}
            onSelect={(id) => {
              setActiveId(id);
              setSelected(null);
              setSearch(null);
            }}
            onClose={closeTab}
            onNew={() => openInNewTab("#home")}
            onAgent={() => setAgentOpen((v) => !v)}
          />
        )}

        <div className="relative flex min-h-0 flex-1">
          <div className="flex min-w-0 flex-1 flex-col">
            {/* Tag Management draws its own header bar, as it does in the app. */}
            {(isBrowser || ["#network", "#ssh", "#trash"].includes(route)) && (
              <Toolbar
                route={route}
                canBack={tab.index > 0}
                canForward={tab.index < tab.history.length - 1}
                canUp={!!upTarget}
                onBack={() => go(-1)}
                onForward={() => go(1)}
                onUp={goUp}
                search={search}
                setSearch={setSearch}
                isBrowser={isBrowser}
                sort={sort}
                onSort={() => {
                  const next: SortKey = sort === "name" ? "size" : sort === "size" ? "date" : "name";
                  setSort(next);
                  toast(t(`Sorted by ${next}`, `Sắp xếp theo ${next === "name" ? "tên" : next === "size" ? "kích thước" : "ngày"}`));
                }}
                view={view}
                onView={() => setView((v) => (v === "grid" ? "list" : "grid"))}
                previewOpen={previewOpen}
                onPreview={() => setPreviewOpen((v) => !v)}
                onAgent={() => setAgentOpen((v) => !v)}
              />
            )}
            <div className="flex min-h-0 flex-1">
              <main className="min-w-0 flex-1">
                <Screen route={route} items={items} search={search} />
              </main>
              {isBrowser && previewOpen && !compact && (
                <div className="w-[260px] shrink-0 border-l border-app-line xl:w-[300px]">
                  <PreviewPane entry={selectedEntry} onClose={() => setPreviewOpen(false)} />
                </div>
              )}
            </div>
            {isBrowser && !compact && (
              <div className="flex h-7 shrink-0 items-center border-t border-app-line bg-app-chrome px-3 text-[11px] whitespace-pre text-app-muted">
                {statusText}
              </div>
            )}
          </div>

          {!compact && agentOpen && (
            <div className="w-[min(380px,42%)] shrink-0 border-l border-app-line">
              <AgentPanel onClose={() => setAgentOpen(false)} folderId={folderId} />
            </div>
          )}
        </div>

        {/* Overlays */}
        <AnimatePresence>
          {compact && agentOpen && (
            <motion.div
              key="agent"
              initial={{ y: "100%" }}
              animate={{ y: 0 }}
              exit={{ y: "100%" }}
              transition={{ type: "spring", stiffness: 320, damping: 34 }}
              className="absolute inset-0 z-20"
            >
              <AgentPanel onClose={() => setAgentOpen(false)} folderId={folderId} />
            </motion.div>
          )}
          {drawer && <Drawer key="drawer" onClose={() => setDrawer(false)} onAgent={() => (setDrawer(false), setAgentOpen(true))} />}
          {tabManager && (
            <TabManager
              key="tabs"
              tabs={tabs}
              activeId={tab.id}
              lang={lang}
              onClose={() => setTabManager(false)}
              onSelect={(id) => (setActiveId(id), setTabManager(false), setSelected(null))}
              onCloseTab={closeTab}
            />
          )}
          {viewer && <Viewer key="viewer" entry={viewer} onClose={() => setViewer(null)} />}
          {sheet && (
            <motion.div key="sheet" className="absolute inset-0 z-20 flex flex-col justify-end bg-black/30" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} onClick={() => setSheet(null)}>
              <motion.div
                initial={{ y: 40 }}
                animate={{ y: 0 }}
                className="h-[65%] overflow-hidden rounded-t-2xl bg-app-bg"
                onClick={(e) => e.stopPropagation()}
              >
                <PreviewPane entry={sheet} onClose={() => setSheet(null)} />
              </motion.div>
            </motion.div>
          )}
        </AnimatePresence>

        {menu && <ContextMenu {...menu} onClose={() => setMenu(null)} />}
        <Toast message={toastMsg} />
      </div>
    </DemoContext.Provider>
  );
}

/* --------------------------------------------------------------- Screens */

function Screen({ route, items, search }: { route: Route; items: Entry[]; search: string | null }) {
  const { t } = useDemoApi();
  if (route === "#home") return <HomeScreen />;
  if (route === "#gallery") return <GalleryHub />;
  if (route === "#tags") return <TagsScreen />;
  if (route === "#network") return <NetworkScreen />;
  if (route === "#ssh") return <SshScreen />;
  if (route === "#cb-agent-cleaner") return <CleanerScreen />;
  if (route === "#settings") return <SettingsScreen />;
  if (route === "#trash") {
    return (
      <div className="grid h-full place-items-center text-center text-[12.5px] text-app-muted">
        <div>
          <Trash size={40} weight="thin" className="mx-auto mb-2" />
          {t("Trash Bin is empty", "Thùng rác trống")}
        </div>
      </div>
    );
  }
  return <BrowserScreen items={items} empty={search ? t("No files match your search", "Không có tệp nào khớp") : t("This folder is empty", "Thư mục này trống")} />;
}

function useDemoApi() {
  const api = React.useContext(DemoContext);
  if (!api) throw new Error("outside AppDemo");
  return api;
}

/* ------------------------------------------------------------- Title bar */

function TitleBar({
  tabs,
  activeId,
  lang,
  agentOpen,
  onMenu,
  onSelect,
  onClose,
  onNew,
  onAgent,
}: {
  tabs: Tab[];
  activeId: number;
  lang: "en" | "vi";
  agentOpen: boolean;
  onMenu: () => void;
  onSelect: (id: number) => void;
  onClose: (id: number) => void;
  onNew: () => void;
  onAgent: () => void;
}) {
  const { t } = useDemoApi();
  return (
    <div className="flex h-11 shrink-0 items-center gap-1.5 bg-app-chrome pr-2 pl-2">
      <IconButton icon={List} label={t("Open navigation menu", "Mở menu điều hướng")} onClick={onMenu} className="!h-7 !w-9 bg-app-field/70" size={17} />
      <div role="tablist" aria-label={t("Tabs", "Tab")} className="ml-3 flex min-w-0 items-end self-stretch">
        {tabs.map((tab) => {
          const route = tab.history[tab.index];
          const active = tab.id === activeId;
          const RouteIcon = routeIcon(route);
          return (
            <div
              key={tab.id}
              role="tab"
              aria-selected={active}
              tabIndex={0}
              onClick={() => onSelect(tab.id)}
              onKeyDown={(e) => e.key === "Enter" && onSelect(tab.id)}
              onAuxClick={(e) => e.button === 1 && onClose(tab.id)}
              className={`group relative flex h-9 w-[190px] min-w-[96px] shrink cursor-default items-center gap-2 rounded-t-md px-3 text-[12px] ${
                active ? "bg-app-bg" : "text-app-muted hover:bg-app-hover/70"
              }`}
            >
              {active && <span className="absolute inset-x-0 top-0 h-[2px] rounded-full bg-app-accent" />}
              <RouteIcon size={14} weight="light" className="shrink-0" />
              <span className="min-w-0 flex-1 truncate">{routeLabel(route, lang)}</span>
              <button
                type="button"
                aria-label={t("Close tab", "Đóng tab")}
                onClick={(e) => {
                  e.stopPropagation();
                  onClose(tab.id);
                }}
                className="grid size-5 shrink-0 place-items-center rounded text-app-muted hover:bg-app-field"
              >
                <X size={12} weight="light" />
              </button>
            </div>
          );
        })}
      </div>
      <button
        type="button"
        aria-label={t("New tab", "Tab mới")}
        onClick={onNew}
        className="ml-1 grid size-7 shrink-0 place-items-center rounded-full bg-app-accent-soft text-app-accent-strong hover:brightness-95"
      >
        <Plus size={14} weight="light" />
      </button>
      <div className="flex-1" />
      <span className="grid size-7 place-items-center rounded-full bg-app-accent-soft text-app-accent-strong" aria-hidden>
        <Bell size={14} weight="light" />
      </span>
      <button
        type="button"
        aria-label="CB Agent"
        aria-pressed={agentOpen}
        onClick={onAgent}
        className={`grid size-8 place-items-center rounded-md ${agentOpen ? "bg-app-accent-soft text-app-accent-strong" : "text-app-muted hover:bg-app-hover"}`}
      >
        <Sparkle size={17} weight="light" />
      </button>
      {/* Window controls are decoration: the demo is not a real window. */}
      <div className="ml-1 flex gap-1" aria-hidden>
        {[Minus, CornersOut, X].map((G, i) => (
          <span key={i} className="grid h-7 w-8 place-items-center rounded-md bg-app-accent-softer text-app-accent-strong">
            <G size={13} weight="light" />
          </span>
        ))}
        <span className="grid h-7 w-8 place-items-center rounded-md bg-app-accent-softer text-app-accent-strong">
          <DotsThree size={15} weight="bold" />
        </span>
      </div>
    </div>
  );
}

/* --------------------------------------------------------------- Toolbar */

function Toolbar(props: {
  route: Route;
  canBack: boolean;
  canForward: boolean;
  canUp: boolean;
  onBack: () => void;
  onForward: () => void;
  onUp: () => void;
  search: string | null;
  setSearch: (s: string | null) => void;
  isBrowser: boolean;
  sort: SortKey;
  onSort: () => void;
  view: "grid" | "list";
  onView: () => void;
  previewOpen: boolean;
  onPreview: () => void;
  onAgent: () => void;
}) {
  const { t, lang, navigate, compact, toast } = useDemoApi();
  const { route, search, setSearch, isBrowser } = props;

  const crumbs: Array<{ label: string; route?: Route }> = route.startsWith("fs:")
    ? pathOf(route.slice(3)).map((e) => ({ label: e.name, route: `fs:${e.id}` }))
    : route.startsWith("tag:")
      ? [{ label: t("Tag Management", "Quản lý Tags"), route: "#tags" }, { label: tagById.get(route.slice(4))!.name[lang] }]
      : route === "#network"
        ? [{ label: t("Network", "Mạng") }]
        : route === "#ssh"
          ? [{ label: t("Network", "Mạng"), route: "#network" }, { label: "SSH" }]
          : route === "#videos"
            ? [{ label: t("Video Gallery", "Thư viện video") }]
            : route === "#trash"
              ? [{ label: t("Trash Bin", "Thùng rác") }]
              : [{ label: t("All Pictures", "Tất cả ảnh"), route: "#gallery" }];
  const LeadIcon = route.startsWith("fs:") ? HardDrive : routeIcon(route);

  const pathBar =
    search !== null ? (
      <div className="flex h-8 min-w-0 flex-1 items-center gap-2 rounded-md bg-app-surface px-3 ring-1 ring-app-accent/50">
        <MagnifyingGlass size={14} className="text-app-muted" />
        <input
          autoFocus
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder={t("Search in this folder", "Tìm trong thư mục này")}
          aria-label={t("Search in this folder", "Tìm trong thư mục này")}
          className="min-w-0 flex-1 bg-transparent text-[12.5px] outline-none placeholder:text-app-muted"
        />
        <button type="button" aria-label={t("Close search", "Đóng tìm kiếm")} onClick={() => setSearch(null)} className="text-app-muted">
          <X size={13} />
        </button>
      </div>
    ) : (
      <nav aria-label={t("Path", "Đường dẫn")} className="flex h-8 min-w-0 flex-1 items-center gap-1 overflow-hidden rounded-md bg-app-field/80 px-2.5 text-[12.5px]">
        <LeadIcon size={13} weight="light" className="mr-1 shrink-0 text-app-muted" />
        {crumbs.map((c, i) => (
          <React.Fragment key={i}>
            {i > 0 && <CaretRight size={10} className="shrink-0 text-app-muted" />}
            {c.route && i < crumbs.length - 1 ? (
              <button type="button" onClick={() => navigate(c.route!)} className="shrink-0 rounded px-1 py-0.5 text-app-muted hover:bg-app-hover hover:text-app-text">
                {c.label}
              </button>
            ) : (
              <span className="truncate px-1">{c.label}</span>
            )}
          </React.Fragment>
        ))}
      </nav>
    );

  if (compact) {
    return (
      <div className="shrink-0 bg-app-chrome">
        {search !== null && <div className="px-3 pb-2">{pathBar}</div>}
        <div className="flex h-11 items-center justify-around px-2">
          <IconButton icon={ArrowLeft} label={t("Back", "Quay lại")} onClick={props.onBack} disabled={!props.canBack} size={20} />
          <IconButton icon={ArrowUp} label={t("Up", "Lên")} onClick={props.onUp} disabled={!props.canUp} size={20} />
          {isBrowser && <IconButton icon={MagnifyingGlass} label={t("Search", "Tìm kiếm")} onClick={() => setSearch("")} size={20} />}
          {isBrowser && <IconButton icon={SortAscending} label={t("Sort", "Sắp xếp")} onClick={props.onSort} size={20} />}
          <IconButton icon={Sparkle} label="CB Agent" onClick={props.onAgent} size={20} />
          <IconButton icon={ArrowClockwise} label={t("Refresh", "Làm mới")} onClick={() => toast(t("Refreshed", "Đã làm mới"))} size={20} />
        </div>
      </div>
    );
  }

  return (
    <div className="flex h-11 shrink-0 items-center gap-1 bg-app-bg px-2">
      <IconButton icon={ArrowLeft} label={t("Back", "Quay lại")} onClick={props.onBack} disabled={!props.canBack} />
      <IconButton icon={ArrowRight} label={t("Forward", "Tiến")} onClick={props.onForward} disabled={!props.canForward} />
      <IconButton icon={ArrowUp} label={t("Up one level", "Lên thư mục cha")} onClick={props.onUp} disabled={!props.canUp} />
      <div className="mx-1 flex min-w-0 flex-1">{pathBar}</div>
      {isBrowser ? (
        <>
          <IconButton icon={MagnifyingGlass} label={t("Search (Ctrl+F)", "Tìm kiếm (Ctrl+F)")} onClick={() => setSearch(search === null ? "" : null)} active={search !== null} />
          <IconButton icon={SortAscending} label={t(`Sort: ${props.sort}`, "Sắp xếp")} onClick={props.onSort} />
          <IconButton icon={props.view === "grid" ? ListBullets : SquaresFour} label={props.view === "grid" ? t("List view", "Dạng danh sách") : t("Grid view", "Dạng lưới")} onClick={props.onView} />
          <IconButton icon={SidebarSimple} label={t("Preview pane", "Khung xem trước")} onClick={props.onPreview} active={props.previewOpen} />
          <IconButton icon={Eye} label={t("Show hidden files", "Hiện tệp ẩn")} onClick={() => toast(t("No hidden files in the sample library", "Thư viện mẫu không có tệp ẩn"))} />
          <IconButton icon={ArrowClockwise} label={t("Refresh", "Làm mới")} onClick={() => toast(t("Refreshed", "Đã làm mới"))} />
          <IconButton icon={DotsThreeVertical} label={t("More", "Thêm")} onClick={() => toast(t("More options live in the full app", "Các tùy chọn khác có trong bản đầy đủ"))} />
        </>
      ) : (
        <IconButton icon={ArrowClockwise} label={t("Refresh", "Làm mới")} onClick={() => toast(t("Refreshed", "Đã làm mới"))} />
      )}
    </div>
  );
}

/* ---------------------------------------------------------- Mobile header */

function MobileHeader({
  label,
  tabCount,
  onMenu,
  onNewTab,
  onTabs,
  onSearch,
}: {
  label: string;
  tabCount: number;
  onMenu: () => void;
  onNewTab: () => void;
  onTabs: () => void;
  onSearch: () => void;
}) {
  const { t } = useDemoApi();
  return (
    <div className="flex h-14 shrink-0 items-center gap-2 bg-app-chrome px-2">
      <IconButton icon={List} label={t("Open navigation menu", "Mở menu điều hướng")} onClick={onMenu} size={20} className="!size-10" />
      <button type="button" onClick={onSearch} className="flex h-10 min-w-0 flex-1 items-center gap-2 rounded-full bg-app-surface px-3.5 text-[14px]">
        <MagnifyingGlass size={17} className="shrink-0 text-app-muted" />
        <span className="min-w-0 flex-1 truncate text-left">{label}</span>
        <CaretDown size={13} className="shrink-0 text-app-muted" />
      </button>
      <IconButton icon={Plus} label={t("New tab", "Tab mới")} onClick={onNewTab} size={20} className="!size-10" />
      <button type="button" onClick={onTabs} aria-label={t("Tab manager", "Quản lý tab")} className="flex h-10 items-center gap-1 rounded-full bg-app-surface px-3 text-[14px] font-semibold">
        {tabCount}
        <CopySimple size={15} weight="light" />
      </button>
    </div>
  );
}

/* ------------------------------------------------------------------ Drawer */

function Drawer({ onClose, onAgent }: { onClose: () => void; onAgent: () => void }) {
  const { t, navigate } = useDemoApi();
  const [pinnedOpen, setPinnedOpen] = React.useState(true);
  const [drivesOpen, setDrivesOpen] = React.useState(true);

  const Item = ({ icon: G, label, onClick, indent = false }: { icon: Icon; label: string; onClick: () => void; indent?: boolean }) => (
    <button type="button" onClick={onClick} className={`flex w-full items-center gap-3 rounded-lg py-2 pr-2 text-left text-[13px] hover:bg-app-hover ${indent ? "pl-9" : "pl-3"}`}>
      <G size={17} weight="light" className="shrink-0 text-app-muted" />
      <span className="truncate">{label}</span>
    </button>
  );
  const Section = ({ icon: G, label, open, toggle, children }: { icon: Icon; label: string; open: boolean; toggle: () => void; children: React.ReactNode }) => (
    <div>
      <button type="button" aria-expanded={open} onClick={toggle} className="flex w-full items-center gap-3 rounded-lg py-2 pr-2 pl-3 text-left text-[13px] hover:bg-app-hover">
        <G size={17} weight="light" className="shrink-0 text-app-muted" />
        <span className="flex-1">{label}</span>
        {open ? <CaretDown size={11} className="text-app-muted" /> : <CaretRight size={11} className="text-app-muted" />}
      </button>
      {open && children}
    </div>
  );

  return (
    <motion.div className="absolute inset-0 z-30" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
      <button type="button" aria-label={t("Close menu", "Đóng menu")} onClick={onClose} className="absolute inset-0 bg-[#10151c]/25" />
      <motion.nav
        aria-label={t("Navigation", "Điều hướng")}
        initial={{ x: -290 }}
        animate={{ x: 0 }}
        exit={{ x: -290 }}
        transition={{ type: "spring", stiffness: 360, damping: 36 }}
        className="absolute inset-y-0 left-0 flex w-[272px] flex-col bg-app-chrome shadow-[8px_0_30px_rgb(15_25_35/0.12)]"
      >
        <div className="flex items-center gap-3 px-4 pt-4 pb-3">
          <img src="/logo.png" alt="" width={34} height={34} className="size-[34px]" />
          <div className="flex-1">
            <div className="text-[14px] font-semibold">CB File Hub</div>
            <div className="text-[11px] text-app-muted">{t("Your files, in flow", "Mọi tệp tin, trong tầm tay")}</div>
          </div>
          <PushPin size={16} weight="light" className="text-app-muted" />
        </div>
        <div className="min-h-0 flex-1 space-y-0.5 overflow-y-auto px-3 pb-4">
          <Item icon={House} label={t("Home", "Trang chủ")} onClick={() => navigate("#home")} />
          <Section icon={PushPin} label={t("Pinned", "Đã ghim")} open={pinnedOpen} toggle={() => setPinnedOpen((v) => !v)}>
            <Item indent icon={FolderSimple} label="Pictures" onClick={() => navigate("fs:pictures")} />
            <Item indent icon={FolderSimple} label="Downloads" onClick={() => navigate("fs:downloads")} />
          </Section>
          <Section icon={HardDrive} label={t("Drives", "Ổ đĩa")} open={drivesOpen} toggle={() => setDrivesOpen((v) => !v)}>
            <Item indent icon={HardDrive} label={`${t("Local Disk", "Ổ đĩa cục bộ")} (C:)`} onClick={() => navigate("fs:c")} />
            <Item indent icon={HardDrive} label={`${t("Local Disk", "Ổ đĩa cục bộ")} (D:)`} onClick={() => navigate("fs:d")} />
            <Item indent icon={Trash} label={t("Trash Bin", "Thùng rác")} onClick={() => navigate("#trash")} />
          </Section>
          <div className="my-2 border-t border-app-line" />
          <Item icon={ImageIcon} label={t("Image Gallery", "Thư viện ảnh")} onClick={() => navigate("#gallery")} />
          <Item icon={VideoCamera} label={t("Video Gallery", "Thư viện video")} onClick={() => navigate("#videos")} />
          <Item icon={Tag} label={t("Tags", "Thẻ")} onClick={() => navigate("#tags")} />
          <Item icon={WifiHigh} label={t("Networks", "Mạng")} onClick={() => navigate("#network")} />
          <Item icon={TerminalWindow} label={t("SSH workspace", "Không gian SSH")} onClick={() => navigate("#ssh")} />
          <Item icon={Sparkle} label="CB Agent" onClick={onAgent} />
          <Item indent icon={Broom} label={t("Disk Cleaner (CB Agent)", "Dọn rác (CB Agent)")} onClick={() => navigate("#cb-agent-cleaner")} />
          <div className="my-2 border-t border-app-line" />
          <Item icon={GearSix} label={t("Settings", "Cài đặt")} onClick={() => navigate("#settings")} />
        </div>
      </motion.nav>
    </motion.div>
  );
}

/* ------------------------------------------------------------ Tab manager */

function TabManager({
  tabs,
  activeId,
  lang,
  onClose,
  onSelect,
  onCloseTab,
}: {
  tabs: Tab[];
  activeId: number;
  lang: "en" | "vi";
  onClose: () => void;
  onSelect: (id: number) => void;
  onCloseTab: (id: number) => void;
}) {
  const { t } = useDemoApi();
  return (
    <motion.div className="absolute inset-0 z-20 flex flex-col bg-app-bg" initial={{ opacity: 0, scale: 0.98 }} animate={{ opacity: 1, scale: 1 }} exit={{ opacity: 0, scale: 0.98 }}>
      <div className="flex h-14 items-center gap-3 px-3">
        <IconButton icon={X} label={t("Close", "Đóng")} onClick={onClose} size={20} className="!size-10" />
        <h2 className="text-[19px] font-semibold">{t("Tab Manager", "Quản lý tab")}</h2>
      </div>
      <div className="grid flex-1 auto-rows-[170px] grid-cols-2 gap-3 overflow-y-auto p-3">
        {tabs.map((tab) => {
          const route = tab.history[tab.index];
          const G = routeIcon(route);
          const active = tab.id === activeId;
          return (
            <div key={tab.id} role="button" tabIndex={0} onClick={() => onSelect(tab.id)} className={`flex flex-col rounded-2xl p-3 ${active ? "bg-app-accent-softer ring-1 ring-app-accent/40" : "bg-app-surface ring-1 ring-app-line"}`}>
              <div className="flex items-center gap-2">
                <FolderSimple size={17} weight="light" className={active ? "text-app-accent-strong" : ""} />
                <span className={`min-w-0 flex-1 truncate text-[13.5px] font-semibold ${active ? "text-app-accent-strong" : ""}`}>{routeLabel(route, lang)}</span>
                <button type="button" aria-label={t("Close tab", "Đóng tab")} onClick={(e) => (e.stopPropagation(), onCloseTab(tab.id))} className="text-app-muted">
                  <X size={15} />
                </button>
              </div>
              <div className="grid flex-1 place-items-center">
                <G size={36} weight="thin" className="text-app-muted" />
              </div>
            </div>
          );
        })}
      </div>
    </motion.div>
  );
}

/* ---------------------------------------------------------------- Viewer */

function Viewer({ entry, onClose }: { entry: Entry; onClose: () => void }) {
  const { t, toast } = useDemoApi();
  const [playing, setPlaying] = React.useState(true);
  return (
    <motion.div className="absolute inset-0 z-20 flex flex-col bg-[#0b0d10]/95 text-white" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
      <div className="flex h-11 shrink-0 items-center gap-3 px-3 text-[12.5px]">
        <span className="min-w-0 flex-1 truncate">{entry.name}</span>
        <span className="text-white/60">{formatSize(entry.size ?? 0)}</span>
        <button type="button" aria-label={t("Close", "Đóng")} onClick={onClose} className="grid size-8 place-items-center rounded-md hover:bg-white/10">
          <X size={16} />
        </button>
      </div>
      <div className="grid min-h-0 flex-1 place-items-center p-4">
        <motion.div
          initial={{ scale: 0.92, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ type: "spring", stiffness: 260, damping: 28 }}
          className="aspect-video max-h-full w-full max-w-[720px] rounded-md"
          style={{ background: toneBackground[entry.tone ?? "earth"] }}
        />
      </div>
      {entry.kind === "video" && (
        <div className="flex h-12 shrink-0 items-center gap-3 px-4 text-[11.5px] text-white/80">
          <button type="button" aria-label={playing ? t("Pause", "Tạm dừng") : t("Play", "Phát")} onClick={() => setPlaying((v) => !v)} className="grid size-8 place-items-center rounded-full bg-white/10">
            {playing ? <Pause size={14} weight="fill" /> : <Play size={14} weight="fill" />}
          </button>
          <span>00:12</span>
          <span className="relative h-1 flex-1 rounded-full bg-white/20">
            <motion.span className="absolute inset-y-0 left-0 rounded-full bg-[var(--a-accent)]" initial={{ width: "8%" }} animate={{ width: playing ? "60%" : "8%" }} transition={{ duration: playing ? 30 : 0.2, ease: "linear" }} />
          </span>
          <span>02:04</span>
          <SpeakerHigh size={16} />
          <button type="button" onClick={() => toast(t("On desktop the app pops the video into a floating window", "Trên desktop, app đưa video ra cửa sổ nổi"))} aria-label={t("Picture-in-picture", "Cửa sổ PiP")} className="rounded px-2 py-1 hover:bg-white/10">
            PiP
          </button>
        </div>
      )}
    </motion.div>
  );
}

/* ---------------------------------------------------------- Context menu */

function ContextMenu({ entry, x, y, onClose }: { entry: Entry; x: number; y: number; onClose: () => void }) {
  const { t, open, openInNewTab, toast } = useDemoApi();
  const isFolder = entry.kind === "folder" || entry.kind === "drive";
  const items: Array<{ label: string; run: () => void; danger?: boolean }> = [
    { label: t("Open", "Mở"), run: () => open(entry) },
    ...(isFolder ? [{ label: t("Open in new tab", "Mở trong tab mới"), run: () => openInNewTab(`fs:${entry.id}`) }] : []),
    { label: t("Add tag", "Thêm thẻ"), run: () => toast(t("Tag editing is off in the demo", "Bản demo không sửa thẻ")) },
    { label: t("Rename", "Đổi tên"), run: () => toast(t("Rename is off in the demo", "Bản demo không cho đổi tên")) },
    { label: t("Copy path", "Sao chép đường dẫn"), run: () => toast(pathString(entry.id)) },
    { label: t("Delete", "Xóa"), run: () => toast(t("Demo only: nothing was deleted", "Chỉ là demo: không có gì bị xóa")), danger: true },
  ];
  return (
    <div
      role="menu"
      className="absolute z-30 w-48 overflow-hidden rounded-lg bg-app-surface py-1 text-[12.5px] shadow-[0_10px_30px_rgb(15_25_35/0.18)] ring-1 ring-app-line"
      style={{ left: x, top: y }}
      onClick={(e) => e.stopPropagation()}
    >
      {items.map((it) => (
        <button
          key={it.label}
          role="menuitem"
          type="button"
          onClick={() => (it.run(), onClose())}
          className={`block w-full px-3 py-1.5 text-left hover:bg-app-hover ${it.danger ? "text-[#d13438]" : ""}`}
        >
          {it.label}
        </button>
      ))}
    </div>
  );
}
