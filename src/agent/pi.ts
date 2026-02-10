import type { AgentProvider } from "./types.ts";

export const piAgentProvider: AgentProvider = {
  backend: "pi",
  stream: (invocation) => [`[pi] scaffold response for cell ${invocation.cellIndex}`],
};
