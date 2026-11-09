import { afterEach, describe, expect, it, vi } from "vitest";
import { ApiRequestError, createOrderProcessingApiClient } from "@xydatalabs/orderprocessing-api-sdk";

afterEach(() => vi.restoreAllMocks());

describe("API error response parsing", () => {
  it.each([
    [403, "application/json", '{"error":"The authenticated tenant claim must match X-Tenant-Code."}', "The authenticated tenant claim must match X-Tenant-Code."],
    [403, "application/json", "", "Request failed with status 403."],
    [500, "application/json", "not-json", "not-json"],
    [500, "application/json", '{"unexpected":true}', '{"unexpected":true}'],
    [500, "application/json", '{"errors":[{}],"message":"Useful fallback"}', "Useful fallback"],
    [400, "application/problem+json", '{"detail":"Validation failed"}', "Validation failed"],
    [400, "application/json", '{"errors":["First","Second"]}', "First Second"],
    [503, "text/plain", "Service unavailable", "Service unavailable"]
  ])("preserves HTTP %s errors without consuming the response twice (%s, %s)", async (status, contentType, body, message) => {
    const response = new Response(body, { status, headers: { "Content-Type": contentType } });
    const read = vi.spyOn(response, "text");
    vi.spyOn(globalThis, "fetch").mockResolvedValue(response);
    const client = createOrderProcessingApiClient();
    await expect(client.getAllCustomers()).rejects.toMatchObject({
      name: "ApiRequestError", statusCode: status, message
    } satisfies Partial<ApiRequestError>);
    expect(read).toHaveBeenCalledTimes(1);
  });
});
