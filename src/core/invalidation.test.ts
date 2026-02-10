import { describe, expect, test } from "bun:test";

import {
  markCellClean,
  markCellEdited,
  markCellError,
  markCellRunning,
  markDependentsStale,
} from "./invalidation.ts";

type TestCell = {
  readonly index: number;
  readonly dependencies: readonly number[];
  readonly state: "clean" | "stale" | "running" | "error";
};

const createCell = (args: {
  readonly index: number;
  readonly dependencies?: readonly number[];
  readonly state: TestCell["state"];
}): TestCell => ({
  index: args.index,
  dependencies: args.dependencies ?? [],
  state: args.state,
});

const toStateMap = (cells: readonly TestCell[]): Map<number, TestCell["state"]> =>
  new Map(cells.map((cell) => [cell.index, cell.state]));

describe("invalidation", () => {
  test("markCellEdited marks the edited cell and transitive descendants as stale", () => {
    const cells: readonly TestCell[] = [
      createCell({ index: 0, state: "clean" }),
      createCell({ index: 1, dependencies: [0], state: "clean" }),
      createCell({ index: 2, dependencies: [1], state: "clean" }),
      createCell({ index: 3, dependencies: [1], state: "clean" }),
      createCell({ index: 4, dependencies: [3], state: "clean" }),
      createCell({ index: 5, dependencies: [0], state: "clean" }),
      createCell({ index: 6, dependencies: [5], state: "error" }),
    ];

    const updated = markCellEdited(cells, 1);
    const states = toStateMap(updated);

    expect(states.get(0)).toBe("clean");
    expect(states.get(1)).toBe("stale");
    expect(states.get(2)).toBe("stale");
    expect(states.get(3)).toBe("stale");
    expect(states.get(4)).toBe("stale");
    expect(states.get(5)).toBe("clean");
    expect(states.get(6)).toBe("error");
  });

  test("markDependentsStale only marks descendants and leaves edited cell unchanged", () => {
    const cells: readonly TestCell[] = [
      createCell({ index: 0, state: "clean" }),
      createCell({ index: 1, dependencies: [0], state: "clean" }),
      createCell({ index: 2, dependencies: [1], state: "clean" }),
    ];

    const updated = markDependentsStale(cells, 1);
    const states = toStateMap(updated);

    expect(states.get(1)).toBe("clean");
    expect(states.get(2)).toBe("stale");
  });

  test("run success flow transitions stale -> running -> clean", () => {
    const cells: readonly TestCell[] = [
      createCell({ index: 0, state: "clean" }),
      createCell({ index: 1, dependencies: [0], state: "stale" }),
    ];

    const running = markCellRunning(cells, 1);
    expect(toStateMap(running).get(1)).toBe("running");

    const clean = markCellClean(running, 1);
    expect(toStateMap(clean).get(1)).toBe("clean");
  });

  test("run error flow transitions stale -> running -> error", () => {
    const cells: readonly TestCell[] = [
      createCell({ index: 0, state: "clean" }),
      createCell({ index: 1, dependencies: [0], state: "stale" }),
    ];

    const running = markCellRunning(cells, 1);
    expect(toStateMap(running).get(1)).toBe("running");

    const errored = markCellError(running, 1);
    expect(toStateMap(errored).get(1)).toBe("error");
  });
});
