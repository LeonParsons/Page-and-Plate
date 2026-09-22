/**
 * Per-device daily extraction counter in Workers KV (SPEC §9, default 30/day).
 * Eventually consistent by design: a burst can briefly exceed the limit. Counts attempts, not successes.
 */

const TWO_DAYS_SECONDS = 2 * 24 * 60 * 60;

export type QuotaResult = {
  allowed: boolean;
  /** Attempts already recorded today, including this one when allowed. */
  used: number;
  /** Seconds until the UTC day rolls over. */
  retryAfterSeconds: number;
};

export function quotaKey(deviceId: string, now: Date): string {
  return `quota:${deviceId}:${now.toISOString().slice(0, 10)}`;
}

export function secondsUntilUTCMidnight(now: Date): number {
  const next = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1);
  return Math.max(1, Math.ceil((next - now.getTime()) / 1000));
}

export async function consumeDailyQuota(kv: KVNamespace, deviceId: string, limit: number, now: Date): Promise<QuotaResult> {
  const key = quotaKey(deviceId, now);
  const used = Number.parseInt((await kv.get(key)) ?? "0", 10) || 0;
  const retryAfterSeconds = secondsUntilUTCMidnight(now);
  if (used >= limit) {
    return { allowed: false, used, retryAfterSeconds };
  }
  await kv.put(key, String(used + 1), { expirationTtl: TWO_DAYS_SECONDS });
  return { allowed: true, used: used + 1, retryAfterSeconds };
}

/**
 * The free tier (SPEC §9): successful scans in a rolling window, per device. Unlike the daily cap this counts
 * successes only — a failed extraction never costs a free scan — so it is checked before the model call and
 * recorded after it. The KV value is the in-window success times (ms); anything older is dropped on write.
 */

export type FreeQuotaResult = {
  allowed: boolean;
  /** Successful scans inside the window right now. */
  used: number;
  /** Seconds until the oldest in-window scan leaves it (0 when allowed). */
  retryAfterSeconds: number;
};

export function freeQuotaKey(deviceId: string): string {
  return `free:${deviceId}`;
}

async function readWindow(kv: KVNamespace, deviceId: string, windowSeconds: number, now: Date): Promise<number[]> {
  let times: unknown;
  try {
    times = JSON.parse((await kv.get(freeQuotaKey(deviceId))) ?? "[]");
  } catch {
    times = [];
  }
  const start = now.getTime() - windowSeconds * 1000;
  return (Array.isArray(times) ? times : [])
    .filter((t): t is number => typeof t === "number" && t > start && t <= now.getTime())
    .sort((a, b) => a - b);
}

export async function checkFreeQuota(kv: KVNamespace, deviceId: string, limit: number, windowSeconds: number, now: Date): Promise<FreeQuotaResult> {
  const times = await readWindow(kv, deviceId, windowSeconds, now);
  if (times.length >= limit) {
    const oldest = times[0]!;
    return { allowed: false, used: times.length, retryAfterSeconds: Math.max(1, Math.ceil((oldest + windowSeconds * 1000 - now.getTime()) / 1000)) };
  }
  return { allowed: true, used: times.length, retryAfterSeconds: 0 };
}

export async function recordFreeScan(kv: KVNamespace, deviceId: string, windowSeconds: number, now: Date): Promise<void> {
  const times = await readWindow(kv, deviceId, windowSeconds, now);
  times.push(now.getTime());
  await kv.put(freeQuotaKey(deviceId), JSON.stringify(times), { expirationTtl: windowSeconds });
}
