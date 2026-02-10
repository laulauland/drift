import type { Cell } from "./schemas.ts";

export type ResolverMode = "explicit" | "linear" | "inferred";

export const resolveDependencies = (
  mode: ResolverMode,
  cells: ReadonlyArray<Cell>,
): ReadonlyMap<number, ReadonlyArray<number>> => {
  switch (mode) {
    case "explicit":
      return resolveExplicit(cells);
    case "linear":
      return resolveLinear(cells);
    case "inferred":
      return resolveExplicit(cells);
  }
};

const resolveExplicit = (
  cells: ReadonlyArray<Cell>,
): ReadonlyMap<number, ReadonlyArray<number>> => {
  const map = new Map<number, ReadonlyArray<number>>();

  for (const cell of cells) {
    map.set(cell.index, cell.explicitDeps ?? []);
  }

  return map;
};

const resolveLinear = (cells: ReadonlyArray<Cell>): ReadonlyMap<number, ReadonlyArray<number>> => {
  const ordered = [...cells].sort((left, right) => left.index - right.index);
  const map = new Map<number, ReadonlyArray<number>>();

  for (let index = 0; index < ordered.length; index += 1) {
    const current = ordered[index];
    if (current === undefined || current.index === 0) {
      continue;
    }

    const previous = ordered[index - 1];
    if (previous === undefined) {
      map.set(current.index, []);
      continue;
    }

    map.set(current.index, [previous.index]);
  }

  return map;
};
