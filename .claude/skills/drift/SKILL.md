---
name: drift
description: Drift spec-to-code binding conventions. Use when editing code that is bound by drift specs, updating specs, working with drift frontmatter, or when drift lint reports stale bindings.
---

# Drift: Spec-to-Code Bindings

drift binds markdown specs to code. When bound code changes, `drift lint` flags the spec as stale. Agents that change code must update the specs they affect.

## When you change code

1. Run `drift lint` to check if any specs are stale
2. If a spec is stale because of your change, update the spec content to reflect the new code
3. Run `drift link <spec-path> <file>` to refresh provenance (auto-appends current change ID)

## When you change a spec

If you add references to new code, add bindings:

```bash
drift link docs/my-spec.md src/new-file.ts
```

If you remove references to code, remove bindings:

```bash
drift unlink docs/my-spec.md src/old-file.ts
```

## Binding syntax

In YAML frontmatter:
```yaml
drift:
  files:
    - src/auth/login.ts              # file-level
    - src/auth/provider.ts#AuthConfig # symbol-level
    - src/auth/login.ts@abc123       # with provenance
```

In spec body (inline references):
```markdown
The auth flow uses @./src/auth/provider.ts#AuthConfig for token validation.
```

## Staleness reasons

`drift lint` exits 1 if any binding is stale:
- **changed after spec** — bound file/symbol modified after the spec
- **file not found** — bound file no longer exists
- **symbol not found** — bound symbol no longer exists in the file

## Workflow

```bash
drift lint                    # check what's stale
# update the affected spec(s)
drift link <spec> <file>      # refresh provenance
drift lint                    # verify all ok
```
