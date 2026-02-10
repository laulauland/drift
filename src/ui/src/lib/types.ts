export interface UiCell {
  readonly index: number;
  readonly title: string;
  readonly dependencies: ReadonlyArray<number>;
  readonly state: "clean" | "stale" | "running" | "error";
}

export interface NotebookViewModel {
  readonly cells: ReadonlyArray<UiCell>;
  readonly activeCell: number | null;
}
