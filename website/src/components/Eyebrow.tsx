import * as React from "react";
import { T, type Copy } from "./lang";
import { Reveal, Rise } from "./motion";

/**
 * Numbered section label above a headline: "01 — Live demo".
 * `immediate` for labels visible on load: CSS entrance on first paint instead of waiting for hydration.
 */
export function Eyebrow({
  index,
  copy,
  className = "",
  immediate = false,
}: {
  index: string;
  copy: Copy;
  className?: string;
  immediate?: boolean;
}) {
  const Wrap = immediate ? Rise : Reveal;
  return (
    <Wrap y={12} className={`mb-6 flex items-center gap-3 text-sm font-medium text-muted ${className}`}>
      <span className="font-mono text-xs tabular-nums text-accent">{index}</span>
      <span aria-hidden className="h-px w-8 bg-gradient-to-r from-accent to-transparent" />
      <span>
        <T {...copy} />
      </span>
    </Wrap>
  );
}
