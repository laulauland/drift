import type { Cell, DependencyResolver } from "./schemas.ts";

export type ResolverMode = DependencyResolver;

const ROOT_CELL_INDEX = 0;

export const resolveDependencies = (
  mode: ResolverMode,
  cells: ReadonlyArray<Cell>,
): ReadonlyMap<number, ReadonlyArray<number>> => {
  const orderedCells = [...cells].sort((left, right) => left.index - right.index);
  const availableIndexes = new Set<number>(orderedCells.map((cell) => cell.index));
  const resolvedDependencies = new Map<number, ReadonlyArray<number>>();

  for (const cell of orderedCells) {
    if (cell.index === ROOT_CELL_INDEX) {
      resolvedDependencies.set(cell.index, []);
      continue;
    }

    const sourceDependencies =
      cell.explicitDeps !== null
        ? cell.explicitDeps
        : resolveFallbackDependencies({
            mode,
            cell,
            orderedCells,
            availableIndexes,
          });

    resolvedDependencies.set(
      cell.index,
      normalizeDependencies({
        dependencies: sourceDependencies,
        cellIndex: cell.index,
        availableIndexes,
      }),
    );
  }

  return resolvedDependencies;
};

const resolveFallbackDependencies = (args: {
  readonly mode: ResolverMode;
  readonly cell: Cell;
  readonly orderedCells: ReadonlyArray<Cell>;
  readonly availableIndexes: ReadonlySet<number>;
}): ReadonlyArray<number> => {
  switch (args.mode) {
    case "explicit":
    case "inferred":
      return defaultExplicitDependencies(args.cell.index, args.availableIndexes);
    case "linear":
      return defaultLinearDependencies(args.cell, args.orderedCells);
  }
};

const defaultExplicitDependencies = (
  cellIndex: number,
  availableIndexes: ReadonlySet<number>,
): ReadonlyArray<number> => {
  if (cellIndex === ROOT_CELL_INDEX) {
    return [];
  }

  return availableIndexes.has(ROOT_CELL_INDEX) ? [ROOT_CELL_INDEX] : [];
};

const defaultLinearDependencies = (
  cell: Cell,
  orderedCells: ReadonlyArray<Cell>,
): ReadonlyArray<number> => {
  const dependencies: number[] = [];

  for (const candidate of orderedCells) {
    if (candidate.index < cell.index) {
      dependencies.push(candidate.index);
    }
  }

  return dependencies;
};

const normalizeDependencies = (args: {
  readonly dependencies: ReadonlyArray<number>;
  readonly cellIndex: number;
  readonly availableIndexes: ReadonlySet<number>;
}): ReadonlyArray<number> => {
  const deduped = new Set<number>();

  for (const dependency of args.dependencies) {
    if (dependency === args.cellIndex) {
      continue;
    }

    if (!args.availableIndexes.has(dependency)) {
      continue;
    }

    deduped.add(dependency);
  }

  return [...deduped].sort((left, right) => left - right);
};
