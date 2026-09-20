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
