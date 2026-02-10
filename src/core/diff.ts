export interface DiffSummary {
  readonly additions: number;
  readonly deletions: number;
}

export const summarizeUnifiedDiff = (patch: string): DiffSummary => {
  const lines = patch.split("\n");
  let additions = 0;
  let deletions = 0;

  for (const line of lines) {
    if (line.startsWith("+++") || line.startsWith("---")) {
      continue;
    }

    if (line.startsWith("+")) {
      additions += 1;
      continue;
    }

    if (line.startsWith("-")) {
      deletions += 1;
    }
  }

  return { additions, deletions };
};
