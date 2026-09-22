import type { Context } from "hono";
import type { ContentfulStatusCode } from "hono/utils/http-status";

/** Every non-2xx body is `{ error, ...extra }` with one of these codes (SPEC §6 plus bad_request / upstream_unavailable). */
export type ErrorCode =
  | "bad_request"
  | "unauthorized"
  | "payload_too_large"
  | "no_recipe_found"
  | "unreadable"
  | "rate_limited"
  | "free_quota_exhausted"
  | "model_invalid_output"
  | "upstream_unavailable"
  | "server_misconfigured"
  | "internal";

export const ERROR_STATUS: Record<ErrorCode, ContentfulStatusCode> = {
  bad_request: 400,
  unauthorized: 401,
  payload_too_large: 413,
  no_recipe_found: 422,
  unreadable: 422,
  rate_limited: 429,
  free_quota_exhausted: 402,
  model_invalid_output: 502,
  upstream_unavailable: 503,
  server_misconfigured: 500,
  internal: 500,
};

export function errorResponse(c: Context, code: ErrorCode, extra: Record<string, unknown> = {}) {
  return c.json({ error: code, ...extra }, ERROR_STATUS[code]);
}
