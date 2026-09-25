import * as React from "react";
import type { Entry } from "./data";

/**
 * Routes mirror the app's tab paths: system screens are "#name" (the app shows these
 * raw in the tab strip, e.g. "#gallery"), folders are "fs:<id>", tagged files "tag:<id>".
 */
export type Route = string;

/** Tag Management preferences. They outlive the screen, like the app's saved view settings. */
export type TagPrefs = {
  view: "list" | "grid" | "tree" | null; // null: grid on wide windows, list on narrow ones (the app's default)
  zoom: number; // grid columns at the reference width, as the app's item-size slider
  sort: "name" | "popularity" | "recent";
  ascending: boolean;
};

export type DemoApi = {
  lang: "en" | "vi";
  t: (en: string, vi: string) => string;
  compact: boolean;
  route: Route;
  /** Push a route on the active tab's history; optionally select an entry once there. */
  navigate: (route: Route, selectId?: string) => void;
  canBack: boolean;
  canForward: boolean;
  back: () => void;
  forward: () => void;
  openInNewTab: (route: Route) => void;
  selected: string | null;
  select: (id: string | null) => void;
  open: (entry: Entry) => void;
  view: "grid" | "list";
  toast: (message: string) => void;
  showContextMenu: (entry: Entry, x: number, y: number) => void;
  accent: string;
  setAccent: (hex: string) => void;
  setLang: (lang: "en" | "vi") => void;
  openAgent: () => void;
  tagPrefs: TagPrefs;
  setTagPrefs: (patch: Partial<TagPrefs>) => void;
};

export const DemoContext = React.createContext<DemoApi | null>(null);

export function useDemo() {
  const api = React.useContext(DemoContext);
  if (!api) throw new Error("useDemo must be used inside <AppDemo>");
  return api;
}
