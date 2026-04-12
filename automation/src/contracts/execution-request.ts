export interface ExecutionRequest {
  runtimeTarget: string;
  tenantCodes: string[];
  allowPartialExecution: boolean;
}
