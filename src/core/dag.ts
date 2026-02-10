import type { Cell } from "./schemas.ts";

export const orderCellsByIndex = (cells: ReadonlyArray<Cell>): ReadonlyArray<Cell> =>
  [...cells].sort((left, right) => left.index - right.index);

export const getCellByIndex = (cells: ReadonlyArray<Cell>, index: number): Cell | null => {
  for (const cell of cells) {
    if (cell.index === index) {
      return cell;
    }
  }

  return null;
};
