import { describe, expect, it } from "vitest";
import { CompactSign, importPKCS8 } from "jose";
import { makeVerifier, type RejectionReason } from "../src/entitlement.ts";
import leafKeyPem from "./fixtures/pki/leaf.key.pem?raw";
import leafPem from "./fixtures/pki/leaf.crt.pem?raw";
import expiredLeafKeyPem from "./fixtures/pki/expired-leaf.key.pem?raw";
import expiredLeafPem from "./fixtures/pki/expired-leaf.crt.pem?raw";
import otherLeafKeyPem from "./fixtures/pki/other-leaf.key.pem?raw";
import otherLeafPem from "./fixtures/pki/other-leaf.crt.pem?raw";
import intermediatePem from "./fixtures/pki/intermediate.crt.pem?raw";
import rootPem from "./fixtures/pki/root.crt.pem?raw";

/**
 * These sign their own certificate chains (`scripts/make-test-pki.sh`), so nothing here needs Apple, a
 * network, or a real purchase. What is being proved is that each check actually bites — before this, the
 * Worker's whole test for a subscription was a regex that `a.b.c` passed.
 */

const ROOT = "C1:ED:A3:E3:C9:AF:AF:40:4D:B3:6D:B6:24:36:81:E2:E8:AF:F9:66:7C:7B:00:C3:2F:DF:F7:04:81:E2:AB:D0";
const OTHER_ROOT = "C4:84:2F:70:FE:C3:60:8E:F2:08:26:00:67:28:AF:73:00:A2:A7:B5:FD:49:3E:CC:E8:88:5E:08:56:1B:03:88";

const BUNDLE = "com.leonparsons.RecipeBasket";
const MONTHLY = "com.leonparsons.RecipeBasket.unlimited.monthly";
const YEARLY = "com.leonparsons.RecipeBasket.unlimited.yearly";
const NOW = new Date("2026-09-25T12:00:00Z");
const NEXT_MONTH = new Date("2026-10-25T12:00:00Z").getTime();

function der(pem: string): string {
  return pem.replace(/-----(BEGIN|END) CERTIFICATE-----/g, "").replace(/\s+/g, "");
}

type Payload = Record<string, unknown>;

/** A transaction as Apple would sign it: the payload, and the chain in the header. */
async function sign(payload: Payload, keyPem = leafKeyPem, chain = [leafPem, intermediatePem, rootPem]) {
  const key = await importPKCS8(keyPem, "ES256");
  return new CompactSign(new TextEncoder().encode(JSON.stringify(payload)))
    .setProtectedHeader({ alg: "ES256", x5c: chain.map(der) })
    .sign(key);
}

function valid(overrides: Payload = {}): Payload {
  return {
    bundleId: BUNDLE,
    productId: MONTHLY,
    expiresDate: NEXT_MONTH,
    environment: "Production",
    transactionId: "2000000000000001",
    ...overrides,
  };
}

function verifier(overrides: Partial<Parameters<typeof makeVerifier>[0]> = {}) {
  const rejections: RejectionReason[] = [];
  const verify = makeVerifier({
    bundleId: BUNDLE,
    productIds: [MONTHLY, YEARLY],
    allowSandbox: false,
    rootFingerprint: ROOT,
    now: () => NOW,
    onReject: (reason) => rejections.push(reason),
    ...overrides,
  });
  return { verify, rejections };
}

describe("verifying a signed transaction", () => {
  it("accepts one Apple signed, and reports what was bought", async () => {
    const { verify } = verifier();
    const entitlement = await verify(await sign(valid()));

    expect(entitlement).not.toBeNull();
    expect(entitlement?.productId).toBe(MONTHLY);
    expect(entitlement?.expiresAt.toISOString()).toBe("2026-10-25T12:00:00.000Z");
    expect(entitlement?.environment).toBe("Production");
  });

  it("accepts the yearly plan too", async () => {
    const { verify } = verifier();
    expect(await verify(await sign(valid({ productId: YEARLY })))).not.toBeNull();
  });

  it("refuses the string that used to be enough", async () => {
    const { verify, rejections } = verifier();
    // The old gate was a regex for three base64url segments, so this was a subscription.
    expect(await verify("a.b.c")).toBeNull();
    expect(rejections).toEqual(["signature"]);
  });

  it("refuses a chain that does not reach the root we pin", async () => {
    const { verify, rejections } = verifier({ rootFingerprint: OTHER_ROOT });
    expect(await verify(await sign(valid()))).toBeNull();
    expect(rejections).toEqual(["signature"]);
  });

  it("refuses a leaf the intermediate never issued", async () => {
    const { verify } = verifier();
    // A real leaf and a real chain — from two different certificate authorities.
    const jws = await sign(valid(), otherLeafKeyPem, [otherLeafPem, intermediatePem, rootPem]);
    expect(await verify(jws)).toBeNull();
  });

  it("refuses a certificate outside its validity window", async () => {
    const { verify } = verifier();
    const jws = await sign(valid(), expiredLeafKeyPem, [expiredLeafPem, intermediatePem, rootPem]);
    expect(await verify(jws)).toBeNull();
  });

  it("refuses a payload edited after signing", async () => {
    const { verify } = verifier();
    const [header, payload, signature] = (await sign(valid())).split(".") as [string, string, string];
    const forged = JSON.parse(atob(payload.replace(/-/g, "+").replace(/_/g, "/")));
    forged.expiresDate = new Date("2099-01-01").getTime();
    const reencoded = btoa(JSON.stringify(forged)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

    expect(await verify(`${header}.${reencoded}.${signature}`)).toBeNull();
  });
});

describe("what the payload has to say", () => {
  it("refuses another app's subscription", async () => {
    const { verify, rejections } = verifier();
    expect(await verify(await sign(valid({ bundleId: "com.someone.else" })))).toBeNull();
    expect(rejections).toEqual(["bundle"]);
  });

  it("refuses a product we do not sell", async () => {
    const { verify, rejections } = verifier();
    expect(await verify(await sign(valid({ productId: "com.leonparsons.RecipeBasket.something" })))).toBeNull();
    expect(rejections).toEqual(["product"]);
  });

  it("refuses one that has run out", async () => {
    const { verify, rejections } = verifier();
    const yesterday = new Date("2026-09-24T12:00:00Z").getTime();
    expect(await verify(await sign(valid({ expiresDate: yesterday })))).toBeNull();
    expect(rejections).toEqual(["expired"]);
  });

  it("refuses one with no expiry at all", async () => {
    const { verify, rejections } = verifier();
    expect(await verify(await sign(valid({ expiresDate: undefined })))).toBeNull();
    expect(rejections).toEqual(["expired"]);
  });

  it("refuses a refunded subscription", async () => {
    const { verify, rejections } = verifier();
    const jws = await sign(valid({ revocationDate: new Date("2026-09-20").getTime() }));
    expect(await verify(jws)).toBeNull();
    expect(rejections).toEqual(["revoked"]);
  });
});

describe("Sandbox", () => {
  it("is refused when the release switch is off", async () => {
    const { verify, rejections } = verifier({ allowSandbox: false });
    expect(await verify(await sign(valid({ environment: "Sandbox" })))).toBeNull();
    expect(rejections).toEqual(["environment"]);
  });

  it("is accepted while it is on, because TestFlight has nothing else", async () => {
    const { verify } = verifier({ allowSandbox: true });
    expect(await verify(await sign(valid({ environment: "Sandbox" })))).not.toBeNull();
  });

  it("does not let anything else through, even when it is on", async () => {
    const { verify, rejections } = verifier({ allowSandbox: true });
    expect(await verify(await sign(valid({ environment: "Xcode" })))).toBeNull();
    expect(rejections).toEqual(["environment"]);
  });
});
