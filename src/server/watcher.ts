export interface FileChange {
  readonly path: string;
  readonly kind: "created" | "updated" | "deleted";
}

export const createWatcherSummary = (changes: ReadonlyArray<FileChange>): string => {
  if (changes.length === 0) {
    return "no changes";
  }

  return `${changes.length} file changes detected`;
};
