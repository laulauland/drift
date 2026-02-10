export type ServerAction = "plan" | "build" | "commit";

export interface ActionRequest {
  readonly action: ServerAction;
  readonly cell: number;
}

export interface ActionResponse {
  readonly accepted: boolean;
  readonly message: string;
}

export const acknowledgeAction = (request: ActionRequest): ActionResponse => ({
  accepted: true,
  message: `${request.action} scheduled for cell ${request.cell}`,
});
