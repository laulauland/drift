import type { CellState } from "./schemas.ts";

type StatefulCell = {
  readonly index: number;
  readonly dependencies: readonly number[];
  readonly state: CellState;
};

export const markDependentsStale = <T extends StatefulCell>(
  cells: readonly T[],
  changedCellIndex: number,
): readonly T[] => {
  const descendants = collectDescendantIndexes(cells, changedCellIndex);
  return setCellStates(cells, descendants, "stale");
};

export const markCellEdited = <T extends StatefulCell>(
  cells: readonly T[],
  editedCellIndex: number,
): readonly T[] => {
  const staleIndexes = new Set<number>([editedCellIndex]);
  for (const descendant of collectDescendantIndexes(cells, editedCellIndex)) {
    staleIndexes.add(descendant);
  }

  return setCellStates(cells, staleIndexes, "stale");
};

export const markCellRunning = <T extends StatefulCell>(
  cells: readonly T[],
  cellIndex: number,
): readonly T[] => setSingleCellState(cells, cellIndex, "running");

export const markCellClean = <T extends StatefulCell>(
  cells: readonly T[],
  cellIndex: number,
): readonly T[] => setSingleCellState(cells, cellIndex, "clean");

export const markCellError = <T extends StatefulCell>(
  cells: readonly T[],
  cellIndex: number,
): readonly T[] => setSingleCellState(cells, cellIndex, "error");

const collectDescendantIndexes = <T extends StatefulCell>(
  cells: readonly T[],
  rootCellIndex: number,
): ReadonlySet<number> => {
  const dependentsByDependency = new Map<number, number[]>();

  for (const cell of cells) {
    for (const dependency of cell.dependencies) {
      const dependents = dependentsByDependency.get(dependency) ?? [];
      dependents.push(cell.index);
      dependentsByDependency.set(dependency, dependents);
    }
  }

  const descendants = new Set<number>();
  const queue = [...(dependentsByDependency.get(rootCellIndex) ?? [])];

  while (queue.length > 0) {
    const cellIndex = queue.shift();
    if (cellIndex === undefined || descendants.has(cellIndex)) {
      continue;
    }

    descendants.add(cellIndex);

    const dependents = dependentsByDependency.get(cellIndex) ?? [];
    for (const dependent of dependents) {
      queue.push(dependent);
    }
  }

  return descendants;
};

const setSingleCellState = <T extends StatefulCell>(
  cells: readonly T[],
  cellIndex: number,
  nextState: CellState,
): readonly T[] =>
  cells.map((cell) => {
    if (cell.index !== cellIndex || cell.state === nextState) {
      return cell;
    }

    return {
      ...cell,
      state: nextState,
    };
  });

const setCellStates = <T extends StatefulCell>(
  cells: readonly T[],
  indexes: ReadonlySet<number>,
  nextState: CellState,
): readonly T[] => {
  if (indexes.size === 0) {
    return cells;
  }

  return cells.map((cell) => {
    if (!indexes.has(cell.index) || cell.state === nextState) {
      return cell;
    }

    return {
      ...cell,
      state: nextState,
    };
  });
};
