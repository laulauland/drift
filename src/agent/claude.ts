import type { AgentProvider } from "./types.ts";

export const claudeAgentProvider: AgentProvider = {
  backend: "claude",
  stream: (invocation) => [`[claude] scaffold response for cell ${invocation.cellIndex}`],
};
