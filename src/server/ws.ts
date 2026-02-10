export type ServerEventType = "cell:started" | "cell:progress" | "cell:complete" | "cell:error";

export interface ServerEvent {
  readonly type: ServerEventType;
  readonly cell: number;
  readonly payload: string;
}

export const toEventLogLine = (event: ServerEvent): string =>
  `${event.type} [cell ${event.cell}] ${event.payload}`;
