import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { checkFreeQuota, freeQuotaKey, recordFreeScan } from "../src/quota.ts";

const kv = (env as unknown as { QUOTA: KVNamespace }).QUOTA;
const DAY = 24 * 60 * 60;
const WINDOW = 30 * DAY;

describe("free quota (SPEC §9: 20 successful scans in any rolling 30 days)", () => {
  it("counts only successes recorded inside the window", async () => {
    const device = crypto.randomUUID();
    const t0 = new Date("2026-09-22T12:00:00Z");
    // Recorded in time order, as the Worker sees them: the first has left the window by t0 and is dropped on write.
    await recordFreeScan(kv, device, WINDOW, new Date(t0.getTime() - 31 * DAY * 1000));
    for (const daysAgo of [2, 1, 0]) await recordFreeScan(kv, device, WINDOW, new Date(t0.getTime() - daysAgo * DAY * 1000));

    const now = t0;
    expect(await checkFreeQuota(kv, device, 20, WINDOW, now)).toMatchObject({ allowed: true, used: 3 });
    const later = new Date(t0.getTime() + 29 * DAY * 1000);
    expect((await checkFreeQuota(kv, device, 20, WINDOW, later)).used).toBe(1);
  });

  it("refuses at the limit and says when the oldest scan frees a slot", async () => {
    const device = crypto.randomUUID();
    const t0 = new Date("2026-09-22T12:00:00Z");
    await recordFreeScan(kv, device, WINDOW, new Date(t0.getTime() - 10 * DAY * 1000));
    await recordFreeScan(kv, device, WINDOW, new Date(t0.getTime() - 1 * DAY * 1000));
    const result = await checkFreeQuota(kv, device, 2, WINDOW, t0);
    expect(result).toMatchObject({ allowed: false, used: 2, retryAfterSeconds: 20 * DAY });
    expect(await checkFreeQuota(kv, device, 3, WINDOW, t0)).toMatchObject({ allowed: true, used: 2, retryAfterSeconds: 0 });
  });

  it("keys per device and stores only in-window timestamps", async () => {
    const device = crypto.randomUUID();
    const now = new Date("2026-09-22T12:00:00Z");
    await recordFreeScan(kv, device, WINDOW, now);
    expect(JSON.parse((await kv.get(freeQuotaKey(device))) ?? "[]")).toEqual([now.getTime()]);
    expect((await checkFreeQuota(kv, crypto.randomUUID(), 20, WINDOW, now)).used).toBe(0);
  });
});
