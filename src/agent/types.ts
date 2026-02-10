export type AgentBackendName = "claude" | "pi" | "codex";

export interface AgentInvocation {
  readonly cellIndex: number;
  readonly prompt: string;
  readonly model: string | null;
}

export interface AgentProvider {
  readonly backend: AgentBackendName;
  readonly stream: (invocation: AgentInvocation) => ReadonlyArray<string>;
}
