import type { AgentProvider } from "./types.ts";

export const codexAgentProvider: AgentProvider = {
  backend: "codex",
  stream: (invocation) => [`[codex] scaffold response for cell ${invocation.cellIndex}`],
};
