import type { NotebookViewModel } from "../types.ts";

export const createInitialNotebook = (): NotebookViewModel => ({
  cells: [],
  activeCell: null,
});
