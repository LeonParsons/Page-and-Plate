import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import {
  checkFreeQuota,
  checkWeeklyQuota,
  freeQuotaKey,
  recordFreeScan,
  recordWeeklyScan,
  weeklyQuotaKey,
} from "../src/quota.ts";

const kv = (env as unknown as { QUOTA: KVNamespace }).QUOTA;
const DAY = 24 * 60 * 60;
const WEEK = 7 * DAY;

describe("free trial (SPEC §9: 5 successful scans per device, ever)", () => {
  it("counts every success for the life of the device", async () => {
    const device = crypto.randomUUID();
    expect(await checkFreeQuota(kv, device, 5)).toMatchObject({ allowed: true, used: 0 });
    for (let i = 0; i < 4; i++) await recordFreeScan(kv, device);
    expect(await checkFreeQuota(kv, device, 5)).toMatchObject({ allowed: true, used: 4 });
    await recordFreeScan(kv, device);
    expect(await checkFreeQuota(kv, device, 5)).toMatchObject({ allowed: false, used: 5 });
  });

  it("keys per device, stores a bare count and never expires", async () => {
    const device = crypto.randomUUID();
    await recordFreeScan(kv, device);
    expect(await kv.get(freeQuotaKey(device))).toBe("1");
    expect((await checkFreeQuota(kv, crypto.randomUUID(), 5)).used).toBe(0);
  });

  it("reads a pre-2026-09-23 ledger of timestamps as that many scans", async () => {
    const device = crypto.randomUUID();
    await kv.put(freeQuotaKey(device), JSON.stringify([1_758_000_000_000, 1_758_100_000_000, 1_758_200_000_000]));
    expect(await checkFreeQuota(kv, device, 5)).toMatchObject({ allowed: true, used: 3 });
    await recordFreeScan(kv, device);
    expect(await kv.get(freeQuotaKey(device))).toBe("4");
  });

  it("unreadable storage reads as no scans — the app's own ledger is the other half of the gate", async () => {
    const device = crypto.randomUUID();
    await kv.put(freeQuotaKey(device), "not json");
    expect(await checkFreeQuota(kv, device, 5)).toMatchObject({ allowed: true, used: 0 });
  });
});

describe("weekly ceiling (SPEC §9: 25 successful scans in any rolling 7 days)", () => {
  it("counts only successes recorded inside the window", async () => {
    const device = crypto.randomUUID();
    const t0 = new Date("2026-09-22T12:00:00Z");
    // Recorded in time order, as the Worker sees them: the first has left the window by t0 and is dropped on write.
    await recordWeeklyScan(kv, device, WEEK, new Date(t0.getTime() - 8 * DAY * 1000));
    for (const daysAgo of [2, 1, 0]) await recordWeeklyScan(kv, device, WEEK, new Date(t0.getTime() - daysAgo * DAY * 1000));

    expect(await checkWeeklyQuota(kv, device, 25, WEEK, t0)).toMatchObject({ allowed: true, used: 3 });
    const later = new Date(t0.getTime() + 6 * DAY * 1000);
    expect((await checkWeeklyQuota(kv, device, 25, WEEK, later)).used).toBe(1);
  });

  it("refuses at the ceiling and says when the oldest scan frees a slot", async () => {
    const device = crypto.randomUUID();
    const t0 = new Date("2026-09-22T12:00:00Z");
    await recordWeeklyScan(kv, device, WEEK, new Date(t0.getTime() - 5 * DAY * 1000));
    await recordWeeklyScan(kv, device, WEEK, new Date(t0.getTime() - 1 * DAY * 1000));
    expect(await checkWeeklyQuota(kv, device, 2, WEEK, t0)).toMatchObject({ allowed: false, used: 2, retryAfterSeconds: 2 * DAY });
    expect(await checkWeeklyQuota(kv, device, 3, WEEK, t0)).toMatchObject({ allowed: true, used: 2, retryAfterSeconds: 0 });
  });

  it("keys per device and stores only in-window timestamps", async () => {
    const device = crypto.randomUUID();
    const now = new Date("2026-09-22T12:00:00Z");
    await recordWeeklyScan(kv, device, WEEK, now);
    expect(JSON.parse((await kv.get(weeklyQuotaKey(device))) ?? "[]")).toEqual([now.getTime()]);
    expect((await checkWeeklyQuota(kv, crypto.randomUUID(), 25, WEEK, now)).used).toBe(0);
  });
});
