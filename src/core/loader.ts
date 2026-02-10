import type { Cell, DriftConfig } from "./schemas.ts";

export interface LoadedProject {
  readonly config: DriftConfig;
  readonly cells: ReadonlyArray<Cell>;
}

export const createEmptyProject = (config: DriftConfig): LoadedProject => ({
  config,
  cells: [],
});
