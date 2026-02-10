import { describe, expect, test } from "bun:test";

import { resolveDependencies } from "./resolver.ts";
import type { Cell } from "./schemas.ts";

const createCell = (args: {
  readonly index: number;
  readonly explicitDeps?: ReadonlyArray<number> | null;
}): Cell => ({
  index: args.index,
  content: `Cell ${args.index}`,
  explicitDeps: args.explicitDeps ?? null,
  agent: null,
  imports: [],
  inlines: [],
  version: 1,
  dependencies: [],
  dependents: [],
  state: "stale",
  comments: [],
  artifact: null,
  lastInputHash: null,
});

describe("resolver", () => {
  test("explicit mode defaults undeclared cells to root cell and keeps explicit overrides", () => {
    const cells: readonly Cell[] = [
      createCell({ index: 0 }),
      createCell({ index: 1 }),
      createCell({ index: 2, explicitDeps: [1, 1, 2, 99] }),
      createCell({ index: 3 }),
    ];

    const dependencies = resolveDependencies("explicit", cells);

    expect([...dependencies.entries()]).toEqual([
      [0, []],
      [1, [0]],
      [2, [1]],
      [3, [0]],
    ]);
  });

  test("linear mode uses all previous cells unless explicit dependencies are declared", () => {
    const cells: readonly Cell[] = [
      createCell({ index: 0 }),
      createCell({ index: 1 }),
      createCell({ index: 2 }),
      createCell({ index: 3, explicitDeps: [1] }),
    ];

    const dependencies = resolveDependencies("linear", cells);

    expect([...dependencies.entries()]).toEqual([
      [0, []],
      [1, [0]],
      [2, [0, 1]],
      [3, [1]],
    ]);
  });

  test("inferred mode currently falls back to explicit defaults", () => {
    const cells: readonly Cell[] = [createCell({ index: 2 }), createCell({ index: 4 })];

    const dependencies = resolveDependencies("inferred", cells);

    expect([...dependencies.entries()]).toEqual([
      [2, []],
      [4, []],
    ]);
  });
});
