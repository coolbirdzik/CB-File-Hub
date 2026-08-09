# Agent Graph — Index

This directory is the routing layer for coding agents and maintainers. It maps
features and runtime contracts to the source files that implement them. Source
code remains authoritative when a graph and the implementation disagree.

This is curated agent routing, not vector Graph RAG. There is no embedding index
here; agents follow these documents by path and then read the cited source.

Source-code tasks use the repo-scoped `graph-first` skill under
`.agents/skills/graph-first/`. `AGENTS.md` keeps only the mandatory routing rule;
the skill owns the reusable inspect, impact, approval, implementation, and
reconciliation loop.

## How to use this documentation

1. Start with [system-map.md](system-map.md) for workspace and runtime
   boundaries.
2. Find the feature in [feature-map.yaml](feature-map.yaml).
3. Read [flows/core-flows.md](flows/core-flows.md) before changing a cross-layer
   path.
4. Check [state/state-ownership.md](state/state-ownership.md) before introducing
   state, providers, caches, or singletons.
5. For Windows changes, check
   [native/method-channels.yaml](native/method-channels.yaml) and update both
   sides of the contract.
6. Use [verification/test-impact-map.yaml](verification/test-impact-map.yaml) to
   select focused checks, then follow the repository CI order when risk warrants
   it.

For every source-code task, classify the graph impact before editing:

- `none`: the implementation stays inside existing nodes, edges, ownership,
  contracts, scope, and invariants; proceed without a graph approval pause.
- `changed`: present a concise graph delta and wait for explicit approval, then
  update the canonical graph before source code.

## Coverage policy

- Prefer high-risk ownership, safety, native, process, and persistence
  boundaries over exhaustive file indexes.
- A missing feature stub does not mean the area is free of constraints; source
  remains the authority. Expand or deepen a stub when that area is actively
  changed.
- Keep entry points short. Prefer the first reads that unlock ownership and
  contracts, not every related file.
- Verification keys in
  [verification/test-impact-map.yaml](verification/test-impact-map.yaml) should
  use the same feature ids as [feature-map.yaml](feature-map.yaml) when both
  exist.

## Graph conventions

- Paths are relative to the workspace root.
- `entrypoints` are good first reads, not an exhaustive dependency list.
- `edges` describe important runtime or ownership relationships.
- `invariants` are constraints that a change must preserve.
- Generated dependency data must never replace manually reviewed invariants.
- Do not use durable line numbers in graph data; prefer files and symbols.

## Anti-patterns

- Do not treat `docs/agent/` as a complete inventory of the app.
- Do not invent edges, owners, or invariants from package or folder names alone.
- Do not skip reading cited source for hot paths, destructive flows, or native
  contracts.
- Do not mark ordinary bugfixes inside an existing node as `changed` unless a
  published boundary or invariant moves.
- Do not let drifted graph text override observed source behavior.
- Do not add ADRs as file indexes; keep mappings in the graph documents.

## Maintenance contract

Update these graph documents when a change does any of the following:

- moves a feature entry point or ownership boundary;
- adds or changes a MethodChannel method or payload;
- changes a destructive-operation approval boundary;
- changes persistence backends or lifecycle rules;
- adds a new runtime process, isolate, or native plugin;
- changes the focused verification required for a feature.

For major architectural decisions, add an ADR under
[decisions/](decisions/README.md). Keep an ADR focused on the decision and its
tradeoffs; keep file mappings in the graph documents.

_Verified against repository baseline `7f40c2a` plus the working tree on
2026-08-09._
