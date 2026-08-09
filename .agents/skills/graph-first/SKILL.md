---
name: graph-first
description: Inspect and classify project graph impact before source-code changes, request approval for graph-changing work, update the canonical graph first, and reconcile graph, code, and verification. Use for every task that edits application, test, native, build, configuration, or script source in this repository. Do not use for analysis-only, review-only, diagnostics-only, or documentation-only requests.
---

# Graph-first coding loop

Use the agent graph as a compact plan and contract before changing source code.
`docs/agent/` is curated routing and ownership data, not an exhaustive inventory
and not a vector Graph-RAG store.

## Inspect

1. Read `docs/agent/index.md`.
2. Follow its routing to only the canonical maps relevant to the task.
3. Inspect the affected source paths read-only before proposing edits.
4. If the graph and source disagree, treat source as authoritative for current
   behavior and note the drift in the impact statement.

## Classify graph impact

Classify the task before editing any file:

- `none`: existing nodes, edges, ownership, contracts, scope, destructive
  behavior, and safety invariants remain unchanged.
- `changed`: any of those graph boundaries or guarantees must change.

### Heuristics for `changed`

Mark `changed` when the task will alter any of:

- feature entry points or ownership owners/lifetimes;
- edges that agents rely on (calls, data flow, process/plugin boundaries);
- MethodChannel methods or payloads;
- destructive-operation approval boundaries;
- persistence backends or lifecycle rules;
- focused verification required for a feature;
- safety invariants stated in the graph.

### Heuristics for `none`

Mark `none` when the task only:

- fixes or extends logic inside an existing node without changing its contract;
- refactors within the same ownership boundary;
- adds or tightens tests for existing behavior without changing required checks;
- changes comments, formatting, or non-behavioral wording.

### Ambiguity default

If it is unclear whether an invariant, ownership boundary, contract, or
destructive approval path moves, classify as `changed` and present the delta.

State the result in commentary:

```text
Graph impact: none — <one-sentence reason>
```

For `none`, proceed directly to implementation.

For `changed`, present this concise delta before editing:

```text
Graph impact: changed
Goal: <outcome>
Nodes: <added, removed, or changed components>
Edges: <changed calls, data flow, or ownership>
Invariants: <preserved or changed guarantees>
Drift: <none, or graph corrections required to match source>
Expected files: <graph and source paths>
Verification: <focused checks>
```

Wait for explicit user approval. Do not edit graph or source files before that
approval.

## Execute

After approval for a changed graph:

1. Update the canonical graph documents first.
2. Implement the source change within the approved boundary.
3. Run focused checks from `docs/agent/verification/test-impact-map.yaml`.
4. Iterate implementation and verification autonomously while the graph
   boundary stays unchanged.

If discovery changes the approved nodes, edges, ownership, contracts, scope,
destructive behavior, or safety invariants, stop and present a revised delta for
approval.

## Reconcile

Before finishing:

1. Compare actual behavior and paths with the canonical graph.
2. Reconcile drift inside the approved scope:
   - Prefer correcting the graph to match intentional source behavior.
   - Prefer correcting source only when the graph states a required invariant
     that the implementation violates and the task intends to restore.
3. Report implemented behavior, automated checks, manual gaps, and blockers
   separately.

Pure graph documentation fixes with no source-code edit remain
documentation-only and are exempt from this approval loop. Discovering such
drift during a source-code task should still be called out and fixed in the
same change set when practical.

The loop is complete only when graph, code, and verification agree.
