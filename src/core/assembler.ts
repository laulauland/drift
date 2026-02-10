export const assembleCellsMarkdown = (cells: ReadonlyArray<string>): string =>
  cells.map((cell) => cell.trim()).join("\n\n---\n\n");
