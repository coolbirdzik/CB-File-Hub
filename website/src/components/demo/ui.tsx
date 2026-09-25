import * as React from "react";
import {
  FileCode,
  FilePdf,
  FileText,
  FileXls,
  FileZip,
  Folder,
  FolderSimple,
  HardDrive,
  Image as ImageIcon,
  MusicNotes,
  Play,
  VideoCamera,
  type Icon,
} from "@phosphor-icons/react";
import { type Entry, toneBackground } from "./data";

/** Square toolbar button in the app's style: light Phosphor glyph, soft hover plate. */
export function IconButton({
  icon: Glyph,
  label,
  onClick,
  active = false,
  disabled = false,
  size = 18,
  className = "",
}: {
  icon: Icon;
  label: string;
  onClick?: () => void;
  active?: boolean;
  disabled?: boolean;
  size?: number;
  className?: string;
}) {
  return (
    <button
      type="button"
      title={label}
      aria-label={label}
      aria-pressed={active || undefined}
      disabled={disabled}
      onClick={onClick}
      className={`grid size-8 shrink-0 place-items-center rounded-md transition-colors disabled:opacity-35 ${
        active ? "bg-app-accent-soft text-app-accent-strong" : "text-app-muted hover:bg-app-hover hover:text-app-text"
      } ${className}`}
    >
      <Glyph size={size} weight="light" />
    </button>
  );
}

const glyphs: Record<Entry["kind"], { icon: Icon; color: string }> = {
  drive: { icon: HardDrive, color: "var(--a-accent-strong)" },
  folder: { icon: Folder, color: "var(--a-accent)" },
  image: { icon: ImageIcon, color: "#2f8fd8" },
  video: { icon: VideoCamera, color: "#e5534b" },
  audio: { icon: MusicNotes, color: "#8b5cf6" },
  pdf: { icon: FilePdf, color: "#e0413a" },
  text: { icon: FileText, color: "#2f8fd8" },
  code: { icon: FileCode, color: "#0a7acc" },
  sheet: { icon: FileXls, color: "#1d8f4e" },
  archive: { icon: FileZip, color: "#d99a21" },
};

/** Small icon used in list rows, breadcrumbs and chat chips. Folders use the filled glyph, like the app's list view. */
export function FileGlyph({ entry, size = 20 }: { entry: Entry; size?: number }) {
  const g = glyphs[entry.kind];
  const Glyph = g.icon;
  return <Glyph size={size} weight={entry.kind === "folder" ? "fill" : "light"} color={g.color} className="shrink-0" />;
}

/** Square grid thumbnail. Images and videos show their picture; folders get the tinted card with a tab. */
export function Thumb({ entry, className = "" }: { entry: Entry; className?: string }) {
  if (entry.kind === "folder" || entry.kind === "drive") {
    return (
      <div className={`relative ${className}`}>
        <span className="absolute -top-1.5 left-0 h-2 w-7 rounded-t-[4px] bg-app-accent-soft" />
        <div className="grid h-full w-full place-items-center rounded-lg bg-app-accent-softer ring-1 ring-app-accent-soft">
          {entry.kind === "drive" ? (
            <HardDrive size={40} weight="light" className="text-app-accent" />
          ) : (
            <FolderSimple size={40} weight="light" className="text-app-accent" />
          )}
        </div>
      </div>
    );
  }
  if (entry.tone && (entry.kind === "image" || entry.kind === "video")) {
    return (
      <div className={`relative overflow-hidden rounded-lg ${className}`} style={{ background: toneBackground[entry.tone] }}>
        {entry.kind === "video" && (
          <span className="absolute inset-0 grid place-items-center">
            <span className="grid size-9 place-items-center rounded-full border-[1.5px] border-white/85 text-white/90">
              <Play size={14} weight="fill" />
            </span>
          </span>
        )}
      </div>
    );
  }
  const g = glyphs[entry.kind];
  const Glyph = g.icon;
  return (
    <div className={`grid place-items-center ${className}`}>
      <Glyph size={46} weight="light" color={g.color} />
    </div>
  );
}

/** Transient message at the bottom of the window. */
export function Toast({ message }: { message: string | null }) {
  return (
    <div
      role="status"
      aria-live="polite"
      className={`pointer-events-none absolute bottom-10 left-1/2 z-40 -translate-x-1/2 rounded-lg bg-[#2b2f36] px-4 py-2.5 text-[12.5px] text-white shadow-lg transition-all duration-300 ${
        message ? "translate-y-0 opacity-100" : "translate-y-2 opacity-0"
      }`}
    >
      {message}
    </div>
  );
}

/** "Section title" pattern from the app: accent bar, bold title, optional pill. */
export function SectionTitle({ title, pill, muted = false }: { title: string; pill?: string; muted?: boolean }) {
  return (
    <div className="flex items-center gap-3">
      <span className={`h-6 w-1 rounded-full ${muted ? "bg-app-muted/60" : "bg-app-accent"}`} />
      <h3 className="text-[15px] font-semibold tracking-[-0.01em]">{title}</h3>
      {pill && (
        <span
          className={`rounded-full px-2.5 py-0.5 text-[10.5px] font-semibold ${
            muted ? "bg-app-field text-app-muted" : "border border-app-accent/25 bg-app-accent-soft text-app-accent-strong"
          }`}
        >
          {pill}
        </span>
      )}
    </div>
  );
}
