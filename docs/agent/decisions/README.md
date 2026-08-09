# Architecture Decision Records

Use this directory for decisions whose rationale is not recoverable from the
current code alone. Examples include process boundaries, persistence migrations,
cross-target cache rules, and safety constraints.

Name records `NNNN-short-title.md` and use this template:

```markdown
# ADR NNNN: Title

- Status: proposed | accepted | superseded
- Date: YYYY-MM-DD
- Owners: team or subsystem

## Context

What forces the decision?

## Decision

What boundary or approach is chosen?

## Consequences

What becomes easier, harder, or forbidden?

## Source anchors

- `path/to/entrypoint`
- `path/to/verification`
```

Do not use ADRs as file indexes. Update `feature-map.yaml` when files move.
