export type VcsBackendName = "git" | "jj";

export interface CommitRequest {
  readonly backend: VcsBackendName;
  readonly files: ReadonlyArray<string>;
  readonly message: string;
}

export const formatCommitSummary = (request: CommitRequest): string => {
  const fileCount = request.files.length;
  const noun = fileCount === 1 ? "file" : "files";

  return `${request.backend} commit (${fileCount} ${noun})`;
};
