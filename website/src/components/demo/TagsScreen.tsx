import * as React from "react";
import {
  AppWindow,
  ArrowBendUpLeft,
  ArrowDown,
  ArrowLeft,
  ArrowRight,
  ArrowUp,
  ArrowsClockwise,
  CaretDown,
  CaretRight,
  ChartBar,
  Check,
  Checks,
  ClockCounterClockwise,
  DotsThreeOutline,
  DotsThreeVertical,
  Eye,
  Folder,
  Funnel,
  Image as ImageIcon,
  ImageBroken,
  List,
  MagnifyingGlass,
  Palette,
  PencilSimple,
  Plus,
  SortAscending,
  SquaresFour,
  Tag,
  Trash,
  TreeStructure,
  TreeView,
  X,
  type Icon,
} from "@phosphor-icons/react";
import { childTags, directTagCount, isParentTag, tagById, tagLastUsed, tags, toneBackground } from "./data";
import { useDemo, type TagPrefs } from "./context";

/*
 * Tag Management, rebuilt from the app's tag_management_screen.dart: the same header bar,
 * list / grid / tree views, drill-down into parent tags, filters, sort and context menu.
 * Editing actions (rename, colour, thumbnail, hierarchy, delete) only toast in the demo.
 */

type ViewMode = "list" | "grid" | "tree";
type HierarchyFilter = "all" | "parents" | "children" | "standalone";
type ThumbFilter = "all" | "with" | "without";
type Popover = { kind: "sort" | "view" | "zoom" | "more"; right: number; top: number };
type TagMenu = { id: string; x: number; y: number };

const ERROR = "#d13438";
const SELECTED_FILL = "color-mix(in srgb, var(--a-accent) 12%, transparent)";

/** `#rrggbb` plus an alpha byte: the app's `tagColor.withValues(alpha: a)`. */
const withAlpha = (hex: string, a: number) =>
  `${hex}${Math.round(a * 255)
    .toString(16)
    .padStart(2, "0")}`;

/** Grid item width for a zoom level: the app's GridZoomConstraints math, on a demo-scaled 960 px reference. */
const REFERENCE_WIDTH = 780;
const GRID_GAP = 12;
const itemWidthForZoom = (zoom: number) => Math.max(56, (REFERENCE_WIDTH - GRID_GAP * (zoom - 1)) / zoom);
const MIN_ZOOM = 2;
const MAX_ZOOM = 10;

function sortIds(ids: string[], prefs: TagPrefs, lang: "en" | "vi") {
  const name = (id: string) => tagById.get(id)!.name[lang];
  const cmp = (a: string, b: string) => {
    if (prefs.sort === "popularity") return directTagCount(a) - directTagCount(b);
    if (prefs.sort === "recent") return tagLastUsed(a).localeCompare(tagLastUsed(b));
    return name(a).localeCompare(name(b), lang, { sensitivity: "base" });
  };
  return [...ids].sort((a, b) => (prefs.ascending ? cmp(a, b) : -cmp(a, b)));
}

export function TagsScreen() {
  const api = useDemo();
  const { t, lang, compact, navigate, openInNewTab, toast, tagPrefs, setTagPrefs } = api;
  const view: ViewMode = tagPrefs.view ?? (compact ? "list" : "grid");
  const root = React.useRef<HTMLDivElement>(null);

  const [drill, setDrill] = React.useState<string[]>([]);
  const [query, setQuery] = React.useState<string | null>(null);
  const [selected, setSelected] = React.useState<Set<string>>(new Set());
  const [focused, setFocused] = React.useState<string | null>(null);
  const [collapsed, setCollapsed] = React.useState<Set<string>>(new Set());
  const [hierarchy, setHierarchy] = React.useState<HierarchyFilter>("all");
  const [thumbs, setThumbs] = React.useState<ThumbFilter>("all");
  const [filterOpen, setFilterOpen] = React.useState(false);
  const [popover, setPopover] = React.useState<Popover | null>(null);
  const [menu, setMenu] = React.useState<TagMenu | null>(null);

  const name = (id: string) => tagById.get(id)!.name[lang];
  const searching = !!query?.trim();

  // Visible set, in the app's order: search (ignores drill scope) -> hierarchy filter -> thumbnail filter -> sort.
  // Unlike the app, a hierarchy filter also looks past the drill scope, so "Child tags" at the root isn't empty.
  let ids: string[];
  if (searching) {
    const q = query!.trim().toLowerCase();
    ids = tags.filter((x) => x.name.en.toLowerCase().includes(q) || x.name.vi.toLowerCase().includes(q)).map((x) => x.id);
  } else if (view === "tree" || hierarchy !== "all") {
    ids = tags.map((x) => x.id);
  } else {
    ids = (drill.length ? childTags(drill[drill.length - 1]) : tags.filter((x) => !x.parent)).map((x) => x.id);
  }
  if (hierarchy !== "all") {
    ids = ids.filter((id) => {
      const parent = isParentTag(id);
      const child = !!tagById.get(id)!.parent;
      return hierarchy === "parents" ? parent : hierarchy === "children" ? child : !parent && !child;
    });
  }
  if (thumbs !== "all") ids = ids.filter((id) => !!tagById.get(id)!.thumb === (thumbs === "with"));
  ids = sortIds(ids, tagPrefs, lang);

  const clearSelection = () => (setSelected(new Set()), setFocused(null));
  const openFiles = (id: string) => navigate(`tag:${id}`);
  const drillInto = (id: string) => {
    setDrill((d) => [...d, id]);
    clearSelection();
    setQuery(null);
  };
  /** Double-click / Enter / tap on touch: a parent drills in, a leaf opens its files. */
  const activate = (id: string) => (!searching && view !== "tree" && isParentTag(id) ? drillInto(id) : openFiles(id));

  const select = (id: string, e: React.MouseEvent | React.KeyboardEvent) => {
    if (e.ctrlKey || e.metaKey) {
      setSelected((prev) => {
        const next = new Set(prev);
        next.has(id) ? next.delete(id) : next.add(id);
        return next;
      });
    } else if (e.shiftKey && focused && ids.includes(focused)) {
      const [a, b] = [ids.indexOf(focused), ids.indexOf(id)].sort((x, y) => x - y);
      setSelected(new Set(ids.slice(a, b + 1)));
      return;
    } else {
      setSelected(new Set([id]));
    }
    setFocused(id);
  };

  // Back unwinds in-screen state first (search, then drill level), then the tab history.
  const canBack = drill.length > 0 || api.canBack;
  const back = () => (drill.length ? setDrill((d) => d.slice(0, -1)) : api.back());

  const anchor = (el: HTMLElement): { right: number; top: number } => {
    const box = root.current!.getBoundingClientRect();
    const r = el.getBoundingClientRect();
    return { right: Math.max(8, box.right - r.right), top: r.bottom - box.top + 4 };
  };
  const togglePopover = (kind: Popover["kind"], el: HTMLElement) =>
    setPopover((p) => (p?.kind === kind ? null : { kind, ...anchor(el) }));

  const showMenu = (id: string, x: number, y: number) => {
    const box = root.current!.getBoundingClientRect();
    if (!selected.has(id)) setSelected(new Set([id]));
    setFocused(id);
    setPopover(null);
    setMenu({ id, x: Math.min(x - box.left, box.width - 236), y: Math.min(y - box.top, box.height - 300) });
  };

  const off = (en: string, vi: string) => () => toast(t(`${en} is off in the demo`, `Bản demo không ${vi}`));

  const itemProps = (id: string) => ({
    tabIndex: 0,
    onClick: (e: React.MouseEvent) => {
      e.stopPropagation();
      if (compact) return activate(id);
      select(id, e);
    },
    onDoubleClick: () => !compact && activate(id),
    onAuxClick: (e: React.MouseEvent) => e.button === 1 && openInNewTab(`tag:${id}`),
    onMouseDown: (e: React.MouseEvent) => e.button === 1 && e.preventDefault(),
    onContextMenu: (e: React.MouseEvent) => {
      e.preventDefault();
      e.stopPropagation();
      showMenu(id, e.clientX, e.clientY);
    },
    onKeyDown: (e: React.KeyboardEvent) => {
      if (e.key === "Enter") activate(id);
      else if (e.key === " ") (e.preventDefault(), select(id, e));
      else if (e.key === "F2") (e.preventDefault(), off("Rename", "đổi tên thẻ")());
      else if (e.key === "Delete") off("Deleting tags", "xóa thẻ")();
    },
  });

  const actions: TagActions = {
    openFiles,
    rename: off("Rename", "đổi tên thẻ"),
    color: off("Changing colours", "đổi màu thẻ"),
    thumbnail: off("Setting a thumbnail", "đặt ảnh thu nhỏ"),
    hierarchy: off("Editing the hierarchy", "sửa phân cấp thẻ"),
    remove: off("Deleting tags", "xóa thẻ"),
    menu: (id, el) => {
      const r = el.getBoundingClientRect();
      showMenu(id, r.left, r.bottom + 4);
    },
  };

  const filterCount = (hierarchy !== "all" ? 1 : 0) + (thumbs !== "all" ? 1 : 0);

  return (
    <div
      ref={root}
      className="relative flex h-full flex-col"
      onKeyDown={(e) => e.key === "Escape" && (setMenu(null), setPopover(null), clearSelection())}
    >
      {/* Header bar: address bar with breadcrumb, then the tag toolbar actions. */}
      <div className="flex h-11 shrink-0 items-center gap-0.5 px-2">
        {selected.size > 0 && <HeaderButton icon={X} label={t("Deselect all", "Bỏ chọn tất cả")} onClick={clearSelection} />}
        <HeaderButton icon={ArrowLeft} label={t("Back", "Quay lại")} onClick={back} disabled={!canBack} />
        {!compact && <HeaderButton icon={ArrowRight} label={t("Forward", "Tiến")} onClick={api.forward} disabled={!api.canForward} />}
        {drill.length > 0 && <HeaderButton icon={ArrowUp} label={t("Up one level", "Lên một cấp")} onClick={back} />}

        <div className="mx-1 flex min-w-0 flex-1">
          {query !== null ? (
            <div className="flex h-8 min-w-0 flex-1 items-center gap-2 rounded-md bg-app-surface px-3 ring-1 ring-app-accent/50">
              <MagnifyingGlass size={14} className="shrink-0 text-app-muted" />
              <input
                autoFocus
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                onKeyDown={(e) => e.key === "Escape" && (e.stopPropagation(), setQuery(null))}
                placeholder={t("Search tags...", "Tìm kiếm thẻ...")}
                aria-label={t("Search tags", "Tìm kiếm thẻ")}
                className="min-w-0 flex-1 bg-transparent text-[12.5px] outline-none placeholder:text-app-muted"
              />
            </div>
          ) : (
            <nav aria-label={t("Path", "Đường dẫn")} className="flex h-8 min-w-0 flex-1 items-center gap-0.5 overflow-hidden rounded-md bg-app-field/80 px-2 text-[12.5px]">
              <Tag size={13} weight="light" className="mr-1 shrink-0 text-app-muted" />
              {drill.length === 0 ? (
                <span className="truncate px-0.5">{t("Tag Management", "Quản lý Tags")}</span>
              ) : (
                <button type="button" onClick={() => setDrill([])} className="shrink-0 rounded px-1 py-0.5 text-app-muted hover:bg-app-hover hover:text-app-text">
                  {t("Tag Management", "Quản lý Tags")}
                </button>
              )}
              {drill.map((id, i) => (
                <React.Fragment key={id}>
                  <CaretRight size={10} className="shrink-0 text-app-muted" />
                  {i < drill.length - 1 ? (
                    <button type="button" onClick={() => setDrill(drill.slice(0, i + 1))} className="shrink-0 rounded px-1 py-0.5 text-app-muted hover:bg-app-hover hover:text-app-text">
                      {name(id)}
                    </button>
                  ) : (
                    <span className="truncate px-1">{name(id)}</span>
                  )}
                </React.Fragment>
              ))}
            </nav>
          )}
        </div>

        <span className="relative">
          <HeaderButton icon={Funnel} label={t("Filter tags", "Lọc thẻ")} onClick={() => setFilterOpen(true)} tone={filterCount ? "accent" : undefined} />
          {filterCount > 0 && (
            <span className="pointer-events-none absolute -top-0.5 -right-0.5 grid h-3.5 min-w-3.5 place-items-center rounded-full bg-app-accent px-1 text-[9px] font-bold text-white">
              {filterCount}
            </span>
          )}
        </span>
        <HeaderButton icon={SortAscending} label={t("Sort Tags", "Sắp xếp thẻ")} onClick={(e) => togglePopover("sort", e.currentTarget)} active={popover?.kind === "sort"} />
        <HeaderButton icon={Eye} label={t("View mode", "Chế độ xem")} onClick={(e) => togglePopover("view", e.currentTarget)} active={popover?.kind === "view"} />
        {view === "grid" && (
          <HeaderButton icon={SquaresFour} label={t("Adjust item size", "Điều chỉnh kích thước item")} onClick={(e) => togglePopover("zoom", e.currentTarget)} active={popover?.kind === "zoom"} />
        )}
        {!compact && <HeaderButton icon={ArrowsClockwise} label={t("Refresh", "Làm mới")} onClick={() => toast(t("Refreshed", "Đã làm mới"))} />}
        <HeaderButton
          icon={query !== null ? X : MagnifyingGlass}
          label={t("Search", "Tìm kiếm")}
          onClick={() => setQuery((q) => (q === null ? "" : null))}
        />
        <HeaderButton icon={DotsThreeVertical} label={t("More options", "Thêm tùy chọn")} onClick={(e) => togglePopover("more", e.currentTarget)} active={popover?.kind === "more"} />
      </div>

      {/* "N tags created" */}
      <div className="flex shrink-0 items-center gap-2 px-5 pt-3 pb-2 text-[13px] font-semibold text-app-muted">
        <Tag size={18} weight="light" className="text-app-accent" />
        {ids.length} {t("tags created", "thẻ đã tạo")}
      </div>

      {filterCount > 0 && (
        <div className="flex shrink-0 items-center gap-1.5 px-3 pb-2">
          <Funnel size={13} className="shrink-0 text-app-accent/70" />
          <div className="flex min-w-0 flex-1 gap-1.5 overflow-x-auto">
            {hierarchy !== "all" && (
              <FilterChip
                icon={hierarchy === "parents" ? TreeStructure : hierarchy === "children" ? ArrowBendUpLeft : Tag}
                label={hierarchyLabel(hierarchy, t)}
                onRemove={() => setHierarchy("all")}
                removeLabel={t("Remove filter", "Bỏ bộ lọc")}
              />
            )}
            {thumbs !== "all" && (
              <FilterChip
                icon={ImageIcon}
                label={thumbs === "with" ? t("Has thumbnail", "Có ảnh thu nhỏ") : t("No thumbnail", "Không có ảnh thu nhỏ")}
                onRemove={() => setThumbs("all")}
                removeLabel={t("Remove filter", "Bỏ bộ lọc")}
              />
            )}
          </div>
          <button type="button" onClick={() => (setHierarchy("all"), setThumbs("all"))} className="shrink-0 rounded-md px-2 py-1 text-[11.5px] text-app-accent-strong hover:bg-app-hover">
            {t("Clear all", "Xóa tất cả")}
          </button>
        </div>
      )}

      <div className="min-h-0 flex-1" onClick={clearSelection}>
        {ids.length === 0 ? (
          <div className="grid h-full place-items-center px-6 text-center">
            <div>
              <MagnifyingGlass size={40} weight="light" className="mx-auto text-app-muted/50" />
              <p className="mt-4 text-[15px] font-semibold">
                {searching ? t(`No tags match "${query!.trim()}"`, `Không có thẻ nào phù hợp với "${query!.trim()}"`) : t("No tags found", "Không tìm thấy thẻ")}
              </p>
              <button
                type="button"
                onClick={(e) => (e.stopPropagation(), searching ? setQuery("") : (setHierarchy("all"), setThumbs("all")))}
                className="mt-4 inline-flex items-center gap-2 rounded-full px-5 py-2 text-[12.5px] text-app-accent-strong ring-1 ring-app-line hover:bg-app-hover"
              >
                <X size={14} />
                {searching ? t("Clear Search", "Xóa tìm kiếm") : t("Clear all", "Xóa tất cả")}
              </button>
            </div>
          </div>
        ) : view === "tree" ? (
          <TreeView_
            ids={ids}
            collapsed={collapsed}
            onToggle={(id) =>
              setCollapsed((prev) => {
                const next = new Set(prev);
                next.has(id) ? next.delete(id) : next.add(id);
                return next;
              })
            }
            selected={selected}
            itemProps={itemProps}
          />
        ) : view === "grid" ? (
          <GridView ids={ids} zoom={tagPrefs.zoom} selected={selected} itemProps={itemProps} actions={actions} />
        ) : (
          <ListView ids={ids} selected={selected} itemProps={itemProps} actions={actions} />
        )}
      </div>

      <button
        type="button"
        aria-label={t("Create new tag", "Tạo thẻ mới")}
        title={t("Create new tag", "Tạo thẻ mới")}
        onClick={off("Creating tags", "tạo thẻ mới")}
        className="absolute right-4 bottom-4 z-10 grid size-12 place-items-center rounded-xl bg-app-accent text-white shadow-md transition hover:brightness-105 active:scale-95"
      >
        <Plus size={22} weight="light" />
      </button>

      {/* Overlays */}
      {(popover || menu) && (
        <div
          className="absolute inset-0 z-20"
          onClick={() => (setPopover(null), setMenu(null))}
          onContextMenu={(e) => (e.preventDefault(), setPopover(null), setMenu(null))}
        />
      )}
      {popover && (
        <div
          role="menu"
          className="absolute z-30 min-w-[210px] overflow-hidden rounded-lg bg-app-surface py-1 text-[12.5px] shadow-[0_10px_30px_rgb(15_25_35/0.18)] ring-1 ring-app-line"
          style={{ right: popover.right, top: popover.top }}
        >
          {popover.kind === "sort" &&
            (
              [
                ["name", SortAscending, t("By Alphabet", "Theo bảng chữ cái")],
                ["popularity", ChartBar, t("By Popular", "Theo phổ biến")],
                ["recent", ClockCounterClockwise, t("Sort by recent", "Sắp xếp theo gần đây")],
              ] as const
            ).map(([key, G, label]) => {
              const active = tagPrefs.sort === key;
              return (
                <MenuItem
                  key={key}
                  icon={G}
                  label={label}
                  active={active}
                  trailing={active ? tagPrefs.ascending ? <ArrowUp size={14} /> : <ArrowDown size={14} /> : null}
                  onClick={() => (setTagPrefs(active ? { ascending: !tagPrefs.ascending } : { sort: key, ascending: true }), setPopover(null))}
                />
              );
            })}
          {popover.kind === "view" &&
            (
              [
                ["list", List, t("List", "Danh sách")],
                ["grid", SquaresFour, t("Grid", "Lưới")],
                ["tree", TreeView, t("Tree", "Cây")],
              ] as const
            ).map(([mode, G, label]) => (
              <MenuItem
                key={mode}
                icon={G}
                label={label}
                active={view === mode}
                trailing={view === mode ? <Check size={14} /> : null}
                onClick={() => (setTagPrefs({ view: mode }), setPopover(null))}
              />
            ))}
          {popover.kind === "zoom" && (
            <div className="px-4 py-3">
              <div className="flex items-center justify-between text-[12px]">
                <span className="font-medium">{t("Grid size", "Kích thước lưới")}</span>
                <span className="rounded-md bg-app-accent-soft px-2 py-0.5 text-[11px] font-semibold text-app-accent-strong">{tagPrefs.zoom}</span>
              </div>
              <input
                type="range"
                min={MIN_ZOOM}
                max={MAX_ZOOM}
                value={tagPrefs.zoom}
                onChange={(e) => setTagPrefs({ zoom: Number(e.target.value) })}
                aria-label={t("Grid size", "Kích thước lưới")}
                className="mt-3 w-full accent-[var(--a-accent)]"
              />
              <div className="mt-1 flex justify-between text-[10.5px] text-app-muted">
                <span>{t("Larger", "Lớn hơn")}</span>
                <span>{t("Smaller", "Nhỏ hơn")}</span>
              </div>
            </div>
          )}
          {popover.kind === "more" && (
            <>
              <MenuItem icon={Checks} label={t("Select all", "Chọn tất cả")} onClick={() => (setSelected(new Set(ids)), setPopover(null))} />
              <div className="my-1 h-px bg-app-line" />
              <MenuItem icon={Plus} label={t("Create New Tag", "Tạo thẻ mới")} onClick={() => (off("Creating tags", "tạo thẻ mới")(), setPopover(null))} />
            </>
          )}
        </div>
      )}
      {menu && (
        <div
          role="menu"
          className="absolute z-30 w-[228px] overflow-hidden rounded-lg bg-app-surface py-1 text-[12.5px] shadow-[0_10px_30px_rgb(15_25_35/0.18)] ring-1 ring-app-line"
          style={{ left: Math.max(4, menu.x), top: Math.max(4, menu.y) }}
        >
          <div className="flex items-center gap-2 px-3 pt-1.5 pb-2 font-semibold">
            <Tag size={15} weight="light" style={{ color: tagById.get(menu.id)!.color }} />
            <span className="truncate">{name(menu.id)}</span>
          </div>
          <div className="mb-1 h-px bg-app-line" />
          {(
            [
              [Folder, t("View Files with Tag", "Xem tệp với thẻ"), () => openFiles(menu.id)],
              [AppWindow, t("Open in New Tab", "Mở trong tab mới"), () => openInNewTab(`tag:${menu.id}`)],
              [PencilSimple, t("Rename Tag", "Đổi tên thẻ"), actions.rename],
              [Palette, t("Change Tag Color", "Thay đổi màu sắc"), actions.color],
              [ImageIcon, t("Set Thumbnail", "Đặt ảnh thu nhỏ"), actions.thumbnail],
              [TreeStructure, t("Manage Hierarchy", "Quản lý phân cấp"), actions.hierarchy],
            ] as Array<[Icon, string, () => void]>
          ).map(([G, label, run]) => (
            <MenuItem key={label} icon={G} label={label} onClick={() => (setMenu(null), run())} />
          ))}
          <div className="my-1 h-px bg-app-line" />
          <MenuItem icon={Trash} label={t("Delete this tag from all files", "Xóa thẻ này khỏi tất cả tệp")} danger onClick={() => (setMenu(null), actions.remove())} />
        </div>
      )}
      {filterOpen && (
        <FilterDialog
          hierarchy={hierarchy}
          thumbs={thumbs}
          onApply={(h, th) => (setHierarchy(h), setThumbs(th), setFilterOpen(false))}
          onClose={() => setFilterOpen(false)}
        />
      )}
    </div>
  );
}

/* ------------------------------------------------------------------ Views */

type ItemProps = (id: string) => React.HTMLAttributes<HTMLDivElement> & { tabIndex: number };
type TagActions = {
  openFiles: (id: string) => void;
  rename: () => void;
  color: () => void;
  thumbnail: () => void;
  hierarchy: () => void;
  remove: () => void;
  menu: (id: string, anchor: HTMLElement) => void;
};

/** List view: rounded tiles washed in the tag colour, with the app's six trailing actions. */
function ListView({ ids, selected, itemProps, actions }: { ids: string[]; selected: Set<string>; itemProps: ItemProps; actions: TagActions }) {
  const { t, lang, compact } = useDemo();
  return (
    <div role="listbox" aria-multiselectable className="h-full space-y-2 overflow-y-auto px-4 pt-2 pb-20">
      {ids.map((id) => {
        const tag = tagById.get(id)!;
        const isSel = selected.has(id);
        const inHierarchy = isParentTag(id) || !!tag.parent;
        return (
          <div
            key={id}
            role="option"
            aria-selected={isSel}
            {...itemProps(id)}
            className="flex min-h-14 cursor-default items-center gap-3.5 rounded-2xl py-2 pr-2 pl-4 outline-none focus-visible:ring-2 focus-visible:ring-app-accent/50"
            style={{ background: isSel ? SELECTED_FILL : withAlpha(tag.color, 0.08) }}
          >
            {isSel && <SoftCheckbox />}
            <ThumbOrDot id={id} size={compact ? 36 : 40} />
            <div className="min-w-0 flex-1">
              <div className="flex min-w-0 items-center gap-1">
                <span className="truncate text-[13.5px] font-medium">{tag.name[lang]}</span>
                {!compact && (
                  <span title={t("Double-click to rename", "Nhấn đúp để đổi tên")} className="shrink-0 text-app-muted/50">
                    <PencilSimple size={13} />
                  </span>
                )}
              </div>
              <HierarchyContext id={id} />
            </div>
            <div className="flex shrink-0 items-center" onClick={(e) => e.stopPropagation()} onDoubleClick={(e) => e.stopPropagation()}>
              {compact ? (
                <>
                  <ActionButton icon={Folder} label={t("View Files with Tag", "Xem tệp với thẻ")} color="var(--a-accent)" onClick={() => actions.openFiles(id)} />
                  <ActionButton icon={DotsThreeOutline} label={t("More options", "Thêm tùy chọn")} onClick={(e) => actions.menu(id, e.currentTarget)} />
                </>
              ) : (
                <>
                  <ActionButton icon={PencilSimple} label={t("Rename Tag", "Đổi tên thẻ")} onClick={actions.rename} />
                  <ActionButton icon={Folder} label={t("View Files with Tag", "Xem tệp với thẻ")} color="var(--a-accent)" onClick={() => actions.openFiles(id)} />
                  <ActionButton icon={Palette} label={t("Change Tag Color", "Thay đổi màu sắc")} onClick={actions.color} />
                  <ActionButton icon={ImageIcon} label={t("Set Thumbnail", "Đặt ảnh thu nhỏ")} onClick={actions.thumbnail} />
                  <ActionButton
                    icon={TreeStructure}
                    label={t("Manage hierarchy (parent/child)", "Quản lý phân cấp (cha/con)")}
                    color={inHierarchy ? "var(--a-accent-strong)" : undefined}
                    onClick={actions.hierarchy}
                  />
                  <ActionButton icon={Trash} label={t("Delete this tag from all files", "Xóa thẻ này khỏi tất cả tệp")} color={withAlpha(ERROR, 0.7)} onClick={actions.remove} />
                </>
              )}
            </div>
          </div>
        );
      })}
    </div>
  );
}

/** Grid view: thumbnail (or colour gradient with a tag glyph) over a name strip; actions float up on hover. */
function GridView({ ids, zoom, selected, itemProps, actions }: { ids: string[]; zoom: number; selected: Set<string>; itemProps: ItemProps; actions: TagActions }) {
  const { t, lang, compact } = useDemo();
  return (
    <div className={`h-full overflow-y-auto pb-20 ${compact ? "px-3 pt-1" : "px-4 pt-2"}`}>
      <div
        role="listbox"
        aria-multiselectable
        className="grid"
        style={{
          // Phones get narrower items so the default zoom still shows two columns.
          gridTemplateColumns: `repeat(auto-fill, minmax(${Math.round(itemWidthForZoom(zoom) * (compact ? 0.75 : 1))}px, 1fr))`,
          gap: compact ? 8 : GRID_GAP,
        }}
      >
        {ids.map((id) => {
          const tag = tagById.get(id)!;
          const isSel = selected.has(id);
          return (
            <div
              key={id}
              role="option"
              aria-selected={isSel}
              title={isParentTag(id) ? t("Double click to open child tags", "Nhấp đúp để mở thẻ con") : t("Double click to open files", "Nhấp đúp để mở tệp")}
              {...itemProps(id)}
              className={`group flex cursor-default flex-col overflow-hidden rounded-2xl outline-none focus-visible:ring-2 focus-visible:ring-app-accent/50 ${isSel ? "ring-1 ring-app-accent/45" : ""}`}
              style={{ aspectRatio: compact ? "1.15" : "1.25", background: isSel ? "var(--a-accent-soft)" : withAlpha(tag.color, 0.1) }}
            >
              <div className="relative min-h-0 flex-1">
                {tag.thumb ? (
                  <span className="absolute inset-0" style={{ background: toneBackground[tag.thumb] }} />
                ) : (
                  <span
                    className="absolute inset-0 grid place-items-center"
                    style={{ background: `linear-gradient(135deg, ${withAlpha(tag.color, 0.55)}, ${withAlpha(tag.color, 0.22)})` }}
                  >
                    <Tag size={compact ? 30 : 36} weight="light" className="text-white/85" />
                  </span>
                )}
                {compact ? (
                  <button
                    type="button"
                    aria-label={t("More options", "Thêm tùy chọn")}
                    onClick={(e) => (e.stopPropagation(), actions.menu(id, e.currentTarget))}
                    className="absolute top-1 right-1 grid size-7 place-items-center rounded-full bg-app-surface/70 text-app-muted"
                  >
                    <DotsThreeOutline size={16} />
                  </button>
                ) : (
                  <div
                    className="absolute inset-x-0 bottom-1.5 flex translate-y-2 justify-center opacity-0 transition duration-150 ease-out group-focus-within:translate-y-0 group-focus-within:opacity-100 group-hover:translate-y-0 group-hover:opacity-100"
                    onClick={(e) => e.stopPropagation()}
                    onDoubleClick={(e) => e.stopPropagation()}
                  >
                    <div className="flex items-center rounded-full bg-app-surface px-0.5 shadow-[0_4px_14px_rgb(15_25_35/0.16)] ring-1 ring-app-line">
                      <ToolbarButton icon={Folder} label={t("View Files with Tag", "Xem tệp với thẻ")} color="var(--a-accent)" onClick={() => actions.openFiles(id)} />
                      <ToolbarButton icon={PencilSimple} label={t("Rename Tag", "Đổi tên thẻ")} onClick={actions.rename} />
                      <ToolbarButton icon={Trash} label={t("Delete this tag from all files", "Xóa thẻ này khỏi tất cả tệp")} color={withAlpha(ERROR, 0.85)} onClick={actions.remove} />
                      <ToolbarButton icon={DotsThreeOutline} label={t("More options", "Thêm tùy chọn")} onClick={(e) => actions.menu(id, e.currentTarget)} />
                    </div>
                  </div>
                )}
              </div>
              <div className="mt-px bg-[rgb(11_13_16/0.04)] px-2 pt-1.5 pb-2 text-center">
                <div className="line-clamp-2 text-[12.5px] leading-tight font-semibold break-words">{tag.name[lang]}</div>
                <HierarchyContext id={id} centered />
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

/** Tree view: every tag nested under its parent. Click selects and folds, double-click opens the files. */
function TreeView_({
  ids,
  collapsed,
  onToggle,
  selected,
  itemProps,
}: {
  ids: string[];
  collapsed: Set<string>;
  onToggle: (id: string) => void;
  selected: Set<string>;
  itemProps: ItemProps;
}) {
  const { t, lang } = useDemo();
  const visible = new Set(ids);
  // Keep a node when it or any descendant survives the filters, so matches keep their ancestors.
  const keep = (id: string): boolean => visible.has(id) || childTags(id).some((c) => keep(c.id));
  const byName = (a: { name: { en: string; vi: string } }, b: { name: { en: string; vi: string } }) =>
    a.name[lang].localeCompare(b.name[lang], lang, { sensitivity: "base" });

  const rows: Array<{ id: string; depth: number; kids: boolean }> = [];
  const walk = (parent: string | undefined, depth: number) => {
    for (const tag of tags.filter((x) => x.parent === parent && keep(x.id)).sort(byName)) {
      const kids = childTags(tag.id).some((c) => keep(c.id));
      rows.push({ id: tag.id, depth, kids });
      if (kids && !collapsed.has(tag.id)) walk(tag.id, depth + 1);
    }
  };
  walk(undefined, 0);

  return (
    <div role="tree" aria-label={t("Tags", "Thẻ")} aria-multiselectable className="h-full overflow-y-auto pb-20">
      {rows.map(({ id, depth, kids }) => {
        const tag = tagById.get(id)!;
        const isSel = selected.has(id);
        const props = itemProps(id);
        return (
          <div
            key={id}
            role="treeitem"
            aria-selected={isSel}
            aria-expanded={kids ? !collapsed.has(id) : undefined}
            aria-level={depth + 1}
            {...props}
            onClick={(e) => {
              props.onClick?.(e);
              if (kids) onToggle(id);
            }}
            onKeyDown={(e) => {
              if (kids && e.key === "ArrowRight" && collapsed.has(id)) onToggle(id);
              else if (kids && e.key === "ArrowLeft" && !collapsed.has(id)) onToggle(id);
              else props.onKeyDown?.(e);
            }}
            className={`flex h-9 cursor-default items-center gap-2 pr-4 text-[13px] outline-none focus-visible:bg-app-hover ${isSel ? "" : "hover:bg-app-hover"}`}
            style={{ paddingLeft: 12 + depth * 16, background: isSel ? SELECTED_FILL : undefined }}
          >
            <span className="grid size-4 shrink-0 place-items-center text-app-muted">
              {kids && (collapsed.has(id) ? <CaretRight size={11} /> : <CaretDown size={11} />)}
            </span>
            <ThumbOrDot id={id} size={24} />
            <span className="truncate font-medium">{tag.name[lang]}</span>
          </div>
        );
      })}
    </div>
  );
}

/* ------------------------------------------------------------ Pieces */

/** The tag's picked thumbnail, or its colour dot (12 px in rows, 32 px on large tiles), as in the app. */
function ThumbOrDot({ id, size }: { id: string; size: number }) {
  const tag = tagById.get(id)!;
  if (tag.thumb) {
    return <span className={`shrink-0 ${size > 40 ? "rounded-xl" : "rounded-lg"}`} style={{ width: size, height: size, background: toneBackground[tag.thumb] }} />;
  }
  const dot = size > 40 ? 32 : 12;
  return (
    <span className="grid shrink-0 place-items-center" style={{ width: size <= 24 ? dot : size, height: size <= 24 ? dot : size }}>
      <span className="rounded-full" style={{ width: dot, height: dot, background: tag.color }} />
    </span>
  );
}

/** Small parent / children hint under a tag name. */
function HierarchyContext({ id, centered = false }: { id: string; centered?: boolean }) {
  const { lang } = useDemo();
  const parent = tagById.get(id)!.parent;
  const kids = childTags(id);
  if (!parent && kids.length === 0) return null;
  const row = `flex min-w-0 items-center gap-1 ${centered ? "justify-center" : ""}`;
  return (
    <div className="mt-0.5 space-y-px text-[10.5px] leading-tight">
      {parent && (
        <div className={`${row} text-app-accent/70`}>
          <ArrowBendUpLeft size={11} className="shrink-0" />
          <span className="truncate">{tagById.get(parent)!.name[lang]}</span>
        </div>
      )}
      {kids.length > 0 && (
        <div className={`${row} text-app-accent-strong/80`}>
          <TreeStructure size={11} className="shrink-0" />
          <span className="truncate">
            {kids.length}: {kids.slice(0, 3).map((k) => k.name[lang]).join(", ")}
            {kids.length > 3 ? "..." : ""}
          </span>
        </div>
      )}
    </div>
  );
}

function SoftCheckbox() {
  return (
    <span aria-hidden className="grid size-[18px] shrink-0 place-items-center rounded-[5px] bg-app-accent text-white">
      <Check size={12} weight="bold" />
    </span>
  );
}

function HeaderButton({
  icon: G,
  label,
  onClick,
  disabled = false,
  active = false,
  tone,
}: {
  icon: Icon;
  label: string;
  onClick: (e: React.MouseEvent<HTMLButtonElement>) => void;
  disabled?: boolean;
  active?: boolean;
  tone?: "accent";
}) {
  return (
    <button
      type="button"
      title={label}
      aria-label={label}
      disabled={disabled}
      onClick={(e) => (e.stopPropagation(), onClick(e))}
      className={`grid size-8 shrink-0 place-items-center rounded-md transition-colors disabled:opacity-35 ${
        active ? "bg-app-hover text-app-text" : tone === "accent" ? "text-app-accent hover:bg-app-hover" : "text-app-muted hover:bg-app-hover hover:text-app-text"
      }`}
    >
      <G size={17} weight="light" />
    </button>
  );
}

function ActionButton({ icon: G, label, onClick, color }: { icon: Icon; label: string; onClick: (e: React.MouseEvent<HTMLButtonElement>) => void; color?: string }) {
  return (
    <button
      type="button"
      title={label}
      aria-label={label}
      onClick={onClick}
      className="grid size-8 place-items-center rounded-full text-app-muted transition-colors hover:bg-black/5"
      style={color ? { color } : undefined}
    >
      <G size={17} weight="light" />
    </button>
  );
}

function ToolbarButton({ icon: G, label, onClick, color }: { icon: Icon; label: string; onClick: (e: React.MouseEvent<HTMLButtonElement>) => void; color?: string }) {
  return (
    <button
      type="button"
      title={label}
      aria-label={label}
      onClick={onClick}
      className="grid size-7 place-items-center rounded-full text-app-muted transition-colors hover:bg-app-hover"
      style={color ? { color } : undefined}
    >
      <G size={16} weight="light" />
    </button>
  );
}

function MenuItem({
  icon: G,
  label,
  onClick,
  active = false,
  danger = false,
  trailing = null,
}: {
  icon: Icon;
  label: string;
  onClick: () => void;
  active?: boolean;
  danger?: boolean;
  trailing?: React.ReactNode;
}) {
  return (
    <button
      type="button"
      role="menuitem"
      onClick={onClick}
      className={`flex w-full items-center gap-3 px-3 py-1.5 text-left hover:bg-app-hover ${active ? "font-semibold text-app-accent-strong" : ""}`}
      style={danger ? { color: ERROR } : undefined}
    >
      <G size={16} weight="light" className="shrink-0" />
      <span className="min-w-0 flex-1 truncate">{label}</span>
      {trailing}
    </button>
  );
}

function FilterChip({ icon: G, label, onRemove, removeLabel }: { icon: Icon; label: string; onRemove: () => void; removeLabel: string }) {
  return (
    <span className="inline-flex shrink-0 items-center gap-1.5 rounded-lg bg-app-accent-soft py-1 pr-1 pl-2 text-[11.5px]">
      <G size={12} className="text-app-accent" />
      {label}
      <button type="button" aria-label={removeLabel} onClick={onRemove} className="grid size-4 place-items-center rounded text-app-muted hover:bg-black/5">
        <X size={11} />
      </button>
    </span>
  );
}

function hierarchyLabel(h: HierarchyFilter, t: (en: string, vi: string) => string) {
  if (h === "parents") return t("Parent tags", "Thẻ cha");
  if (h === "children") return t("Child tags", "Thẻ con");
  if (h === "standalone") return t("Standalone", "Độc lập");
  return t("All", "Tất cả");
}

/** The app's "Filter tags" dialog: hierarchy and thumbnail choices, applied together. */
function FilterDialog({
  hierarchy,
  thumbs,
  onApply,
  onClose,
}: {
  hierarchy: HierarchyFilter;
  thumbs: ThumbFilter;
  onApply: (h: HierarchyFilter, th: ThumbFilter) => void;
  onClose: () => void;
}) {
  const { t } = useDemo();
  const [h, setH] = React.useState(hierarchy);
  const [th, setTh] = React.useState(thumbs);

  const Option = ({ label, icon: G, selected, onClick }: { label: string; icon?: Icon; selected: boolean; onClick: () => void }) => (
    <button
      type="button"
      aria-pressed={selected}
      onClick={onClick}
      className={`inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 text-[12px] ring-1 transition-colors ${
        selected ? "bg-app-accent-soft text-app-accent-strong ring-app-accent/50" : "ring-app-line hover:bg-app-hover"
      }`}
    >
      {G && <G size={14} className={selected ? "text-app-accent" : "text-app-muted"} />}
      {label}
    </button>
  );

  return (
    <div className="absolute inset-0 z-40 grid place-items-center bg-black/25 p-4" onClick={onClose} onKeyDown={(e) => e.key === "Escape" && (e.stopPropagation(), onClose())}>
      <div role="dialog" aria-modal aria-label={t("Filter tags", "Lọc thẻ")} className="w-full max-w-[360px] rounded-xl bg-app-surface p-5 shadow-2xl" onClick={(e) => e.stopPropagation()}>
        <h3 className="flex items-center gap-2 text-[15px] font-semibold">
          <Funnel size={18} className="text-app-accent" />
          {t("Filter tags", "Lọc thẻ")}
        </h3>
        <p className="mt-4 text-[12.5px] font-semibold text-app-accent-strong">{t("Hierarchy", "Phân cấp")}</p>
        <div className="mt-2 flex flex-wrap gap-2">
          <Option label={t("All", "Tất cả")} selected={h === "all"} onClick={() => setH("all")} />
          <Option label={t("Parent tags", "Thẻ cha")} icon={TreeStructure} selected={h === "parents"} onClick={() => setH("parents")} />
          <Option label={t("Child tags", "Thẻ con")} icon={ArrowBendUpLeft} selected={h === "children"} onClick={() => setH("children")} />
          <Option label={t("Standalone", "Độc lập")} icon={Tag} selected={h === "standalone"} onClick={() => setH("standalone")} />
        </div>
        <p className="mt-5 text-[12.5px] font-semibold text-app-accent-strong">{t("Thumbnail", "Ảnh thu nhỏ")}</p>
        <div className="mt-2 flex flex-wrap gap-2">
          <Option label={t("All", "Tất cả")} selected={th === "all"} onClick={() => setTh("all")} />
          <Option label={t("Has thumbnail", "Có ảnh thu nhỏ")} icon={ImageIcon} selected={th === "with"} onClick={() => setTh("with")} />
          <Option label={t("No thumbnail", "Không có ảnh thu nhỏ")} icon={ImageBroken} selected={th === "without"} onClick={() => setTh("without")} />
        </div>
        <div className="mt-6 flex justify-end gap-2">
          <button type="button" onClick={() => (setH("all"), setTh("all"))} className="rounded-md px-3 py-1.5 text-[12.5px] text-app-accent-strong hover:bg-app-hover">
            {t("Reset", "Đặt lại")}
          </button>
          <button type="button" onClick={() => onApply(h, th)} className="rounded-md bg-app-accent px-4 py-1.5 text-[12.5px] font-medium text-white hover:brightness-105">
            {t("Apply", "Áp dụng")}
          </button>
        </div>
      </div>
    </div>
  );
}
