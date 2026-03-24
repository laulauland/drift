<!-- drift:
  files:
    - src/main.zig@982ee91




-->
<img width="276" height="84" alt="Drift Logo" src="https://github.com/user-attachments/assets/19618b90-d43e-4e92-8497-9674a87693e2" />

Bind specs to code. Lint for drift.

Any markdown file in your repo can declare anchors to code — specific files or AST symbols. When bound code changes, `drift check` flags the spec as stale. Agents that change code must update the specs they affect.

## Install

```bash
curl -fsSL https://drift.fp.dev/install.sh | sh
```

To install a specific version:

```bash
curl -fsSL https://drift.fp.dev/install.sh | sh -s -- --version v0.1.0
```

Or build from source:

```bash
zig build -Doptimize=ReleaseSafe --prefix ~/.local
```

### Coding agent skill (Claude Code, Codex)

```bash
curl -fsSL https://drift.fp.dev/install.sh | sh
npx skills add fiberplane/drift
```

The skill teaches coding agents how to maintain drift anchors. Once installed, the agent will run `drift link` to stamp provenance and keep specs in sync as it makes code changes. When `drift check` is in CI, stale specs block merges — so the agent can't silently break documentation.

## Usage

Write a markdown spec, then bind it to code:

```
drift link docs/auth.md src/auth/login.ts
drift link docs/auth.md src/auth/provider.ts#AuthConfig
```

`drift link` adds the anchor to the spec's YAML frontmatter and auto-appends provenance (current git HEAD). You can also reference code inline — `@./src/auth/provider.ts#AuthConfig` in the spec body — and `drift link` will stamp those with provenance too.

Check if specs are fresh:

```
drift check
```

Refresh all anchors in a spec after updating it:

```
drift link docs/auth.md
```

### What a spec looks like

After linking, your spec has frontmatter anchors and (optionally) inline references:

```markdown
---
drift:
  files:
    - src/auth/login.ts@a1b2c3d4
    - src/auth/provider.ts#AuthConfig@a1b2c3d4
---

# Auth Architecture

Users authenticate via OAuth2. The validation flow uses @./src/auth/provider.ts#AuthConfig@a1b2c3d4 ...
```

Each anchor carries provenance via an `@<git-sha>` suffix — recording which commit you last reviewed that code at. Provenance is per-anchor, so different files track independently.

If you don't want frontmatter visible on GitHub, use an HTML comment instead:

```markdown
<!-- drift:
  files:
    - src/auth/login.ts@a1b2c3d4
    - src/auth/provider.ts#AuthConfig@a1b2c3d4
-->
```

## Commands

```
drift check         Check all specs for staleness (exits 1 if stale)
drift status        Show all specs and their anchors
drift link          Add an anchor to a spec (auto-appends provenance)
drift unlink        Remove an anchor from a spec
```

`drift lint` is an alias for `drift check`.

## How staleness works

For each anchor, drift compares the bound code at the provenance revision against its current state. For supported languages (TypeScript, Python, Rust, Go, Zig, Java), comparison is syntax-aware — drift parses with tree-sitter and hashes a normalized AST fingerprint (node kinds + token text, no whitespace or position data). Reformatting won't trigger false positives. Symbol-level anchors (`#AuthConfig`) narrow this to just that declaration's subtree. Unsupported languages fall back to raw content comparison.

```
$ drift check

docs/auth.md
  STALE   src/auth/provider.ts#AuthConfig (changed after spec)
          changed by mike in e4f8a2c (Mar 15)
          "refactor: split auth config into separate concerns"
  STALE   src/core/old-module.ts (file not found)
  ok      src/auth/login.ts

docs/payments.md
  ok

1 spec stale, 1 ok
```

## CI

`drift check` exits 1 when any spec is stale, so it works as a CI gate:

```yaml
# .github/workflows/drift.yml
name: Drift
on: [push, pull_request]
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: fiberplane/drift@main
      - run: drift check
```

`fetch-depth: 0` is required — drift needs VCS history to compare content at provenance revisions. The setup action auto-detects platform, downloads the right binary from GitHub releases, and verifies its checksum before installing.

## VCS support

git. jj support is planned for when jj-native forges exist — until then, colocated jj repos use git provenance, which works in both local and CI environments.

## Development

Requires Zig 0.15.2. The repo includes a `.tool-versions` file for [mise](https://mise.jdx.dev/) (or asdf). If you haven't already, [activate mise](https://mise.jdx.dev/getting-started.html#activate-mise) in your shell, then:

```bash
mise install        # installs zig 0.15.2
zig build test      # run tests
zig build -Doptimize=ReleaseSafe  # build release binary
```

Enable the pre-push hook to run build, lint, and tests before every push:

```bash
git config core.hooksPath hooks
```
