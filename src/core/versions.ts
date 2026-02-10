export interface PlanVersion {
  readonly version: number;
  readonly content: string;
}

export const createNextVersion = (
  existing: ReadonlyArray<PlanVersion>,
  content: string,
): PlanVersion => ({
  version: existing.length + 1,
  content,
});
