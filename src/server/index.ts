import { acknowledgeAction, type ActionRequest } from "./api.ts";
import { createWatcherSummary, type FileChange } from "./watcher.ts";

export * from "./api.ts";
export * from "./watcher.ts";
export * from "./ws.ts";

export interface DriftServer {
  readonly runAction: (request: ActionRequest) => string;
  readonly summarizeChanges: (changes: ReadonlyArray<FileChange>) => string;
}

export const createServerScaffold = (): DriftServer => ({
  runAction: (request) => acknowledgeAction(request).message,
  summarizeChanges: (changes) => createWatcherSummary(changes),
});
