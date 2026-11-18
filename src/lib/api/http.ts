import { NextResponse } from "next/server";
import { randomUUID } from "node:crypto";

export const API_BODY_LIMIT = 1_000_000;
export const API_HEADERS = { "cache-control": "private, no-store", "x-content-type-options": "nosniff" };

export function requestId(): string {
  return randomUUID();
}

export function apiResponse<T>(data: T, status = 200, id: string = requestId()) {
  return NextResponse.json({ data, request_id: id }, { status, headers: { ...API_HEADERS, "x-request-id": id } });
}

export function apiError(message: string, status: number, id: string = requestId(), details?: unknown) {
  return NextResponse.json({ error: message, ...(details === undefined ? {} : { details }), request_id: id }, { status, headers: { ...API_HEADERS, "x-request-id": id } });
}

export async function readJson(request: Request): Promise<{ ok: true; value: unknown } | { ok: false; status: 400 | 413; error: string }> {
  const length = Number(request.headers.get("content-length") ?? 0);
  if (Number.isFinite(length) && length > API_BODY_LIMIT) return { ok: false, status: 413, error: "Request body is too large." };
  try {
    const text = await request.text();
    if (new TextEncoder().encode(text).byteLength > API_BODY_LIMIT) return { ok: false, status: 413, error: "Request body is too large." };
    return { ok: true, value: JSON.parse(text) as unknown };
  } catch {
    return { ok: false, status: 400, error: "Request body must be valid JSON." };
  }
}

export function rpcUnavailable(error: { code?: string; message?: string } | null | undefined) {
  if (!error) return false;
  return error.code === "PGRST202" || /function .* does not exist|could not find the function/i.test(error.message ?? "");
}

export function safeString(value: unknown, max = 500) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}
