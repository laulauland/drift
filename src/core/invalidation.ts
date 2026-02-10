import type { Cell } from "./schemas.ts";

export const markDependentsStale = (
  cells: ReadonlyArray<Cell>,
  changedCellIndex: number,
): ReadonlyArray<Cell> => {
  const affected = new Set<number>();
  const queue = [changedCellIndex];

  while (queue.length > 0) {
    const currentIndex = queue.shift();
    if (currentIndex === undefined) {
      continue;
    }

    for (const cell of cells) {
      if (!cell.dependencies.includes(currentIndex)) {
        continue;
      }

      if (affected.has(cell.index)) {
        continue;
      }

      affected.add(cell.index);
      queue.push(cell.index);
    }
  }

  return cells.map((cell) => {
    if (!affected.has(cell.index)) {
      return cell;
    }

    return {
      ...cell,
      state: "stale",
    };
  });
};
