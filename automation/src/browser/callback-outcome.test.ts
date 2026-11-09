import assert from "node:assert/strict";
import test from "node:test";
import { classifyCallback, type CallbackSnapshot } from "./callback-outcome.js";

const empty: CallbackSnapshot = { loading: false, errorMessage: "", successMessage: "", infoMessage: "" };

test("a callback with no loading panel and no result is not complete", () => {
  assert.equal(classifyCallback(empty).state, "pending");
});

test("the observed resource-not-found callback fails, never completes", () => {
  const result = classifyCallback({ ...empty, errorMessage: "The requested resource was not found." });
  assert.equal(result.state, "failed");
  assert.equal(result.message, "The requested resource was not found.");
});

test("errors override stale success content", () => {
  assert.equal(classifyCallback({ ...empty, successMessage: "Completed", errorMessage: "Declined" }).state, "failed");
});

test("pending information never counts as payment success", () => {
  assert.equal(classifyCallback({ ...empty, infoMessage: "Waiting for confirmation" }).state, "pending");
});

test("a success banner while reconciliation is loading remains pending", () => {
  assert.equal(classifyCallback({ ...empty, loading: true, successMessage: "Completed" }).state, "pending");
});

test("only a settled explicit success completes the journey", () => {
  const result = classifyCallback({ ...empty, successMessage: " Payment completed successfully. " });
  assert.equal(result.state, "completed");
  assert.equal(result.message, "Payment completed successfully.");
});
