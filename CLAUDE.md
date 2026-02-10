# CLAUDE.md

@.fp/FP_CLAUDE.md

## Stack

- Runtime: Bun
- Language: TypeScript (strict, ESM only)
- Core: Effect ecosystem (`effect`, `@effect/schema`, `@effect/platform`)
- Frontend: SvelteKit with Svelte 5 runes
- No default exports except Svelte components

## Effect Patterns

### Always

- `Effect.gen(function*() { ... })` for effectful code (generator syntax, not pipe chains)
- `yield*` inside generators, never `await`
- Tagged errors via `Data.TaggedError` for failure cases (no string errors)
- `Schema.Struct`, `Schema.Literal`, etc. for data shapes (no handwritten interfaces for data payloads)
- `Schema.decode` / `Schema.encode` for parsing and serialization
- `Effect.tryPromise` to wrap unavoidable Promise-based APIs (e.g. `fetch`)
- Services via `Context.Tag` + `Layer` (no module-level singletons)
- `readonly` on arrays, records, and fields by default
- `Effect.acquireRelease` for resource/resource-lifecycle management

### Never

- `Promise` or `async/await` in application code (wrap in Effect)
- `try/catch` (use `Effect.catchTag` / `Effect.catchAll`)
- `throw` (use `Effect.fail(new SomeTaggedError({ ... }))`)
- `any` type (use `unknown` and decode through Schema)
- `as` assertions (decode/refine instead; `as const` is okay)
- `enum` (use `Schema.Literal` or `as const` unions)
- `namespace` or `require()`
- `console.log` (use `Effect.log` / `Effect.logDebug`)

## Svelte 5 Patterns

### Always

- `$state()` for reactive state
- `$derived()` for computed values
- `$effect()` for side effects
- `$props()` for component props
- `{#snippet}` blocks for reusable template fragments
- `<Component {prop}>` shorthand when prop name matches

### Never

- `writable` / `readable` / `derived` stores from `svelte/store`
- `$:` reactive statements (use `$derived()` / `$effect()`)
- `export let` for props (use `$props()`)
- `<slot>` (use `{#snippet}` + `{@render}`)
- `onMount` / `onDestroy` (use `$effect()` cleanup)
- `createEventDispatcher` (use callback props)

## General

- Named exports only (except `.svelte` components)
- `import type` for type-only imports
- Prefer `const` over `let`; never `var`
- Exhaustive `switch` via `never` in `default`
- File naming: `kebab-case.ts`, `PascalCase.svelte`
