import { beforeAll, describe, expect, it } from "vitest";
import { makeAssertionVerifier, makeAttestationVerifier, type AttestedKey } from "../src/attest.ts";
import { base64, concat, makeAssertion, makeAttestation, makeAuthority, type Authority } from "./appattest-fixtures.ts";

/**
 * Apple's nine attestation checks and the assertion's four, each proved to bite on its own. The chains are
 * generated here, so none of this needs a device, Apple, or a network — the same approach that made the
 * entitlement verifier testable in Phase 8a.
 */

const APP_ID = "F6VXT39M7H.com.leonparsons.RecipeBasket";
const CHALLENGE = new TextEncoder().encode("a-one-time-challenge");

let authority: Authority;
let other: Authority;

beforeAll(async () => {
  authority = await makeAuthority();
  other = await makeAuthority();
});

function verifier(overrides: Partial<Parameters<typeof makeAttestationVerifier>[0]> = {}) {
  return makeAttestationVerifier({
    appId: APP_ID,
    developmentEnv: true,
    rootCertificatePem: authority.rootPem,
    now: () => new Date("2026-09-25T12:00:00Z"),
    ...overrides,
  });
}

describe("attestation", () => {
  it("accepts one a device would produce, and keeps the receipt", async () => {
    const { keyId, attestation } = await makeAttestation(authority, { appId: APP_ID, challenge: CHALLENGE });
    const result = await verifier()(keyId, CHALLENGE, attestation);

    expect(typeof result).not.toBe("string");
    const key = result as AttestedKey;
    expect(key.keyId).toBe(keyId);
    expect(key.publicKeyPem).toContain("BEGIN PUBLIC KEY");
    expect(key.counter).toBe(0);
    // Unused today; stored so the risk-metric API can be added without re-attesting anybody.
    expect(key.receipt).toBe(base64(new Uint8Array([0xde, 0xad, 0xbe, 0xef])));
  });

  it("refuses a chain from another authority", async () => {
    const { keyId, attestation } = await makeAttestation(authority, {
      appId: APP_ID,
      challenge: CHALLENGE,
      signedBy: other,
    });
    expect(await verifier()(keyId, CHALLENGE, attestation)).toBe("chain");
  });

  it("refuses an attestation for a different challenge — the replay that matters most", async () => {
    const { keyId, attestation } = await makeAttestation(authority, { appId: APP_ID, challenge: CHALLENGE });
    const somebodyElsesChallenge = new TextEncoder().encode("a-different-challenge");
    expect(await verifier()(keyId, somebodyElsesChallenge, attestation)).toBe("nonce");
  });

  it("refuses a nonce that is not the hash it claims to be", async () => {
    const { keyId, attestation } = await makeAttestation(authority, {
      appId: APP_ID,
      challenge: CHALLENGE,
      nonce: new Uint8Array(32).fill(0x11),
    });
    expect(await verifier()(keyId, CHALLENGE, attestation)).toBe("nonce");
  });

  it("refuses a key id that is not the hash of the public key", async () => {
    const { attestation } = await makeAttestation(authority, { appId: APP_ID, challenge: CHALLENGE });
    expect(await verifier()(base64(new Uint8Array(32).fill(0x22)), CHALLENGE, attestation)).toBe("key_id");
  });

  it("refuses an attestation made for another app", async () => {
    const { keyId, attestation } = await makeAttestation(authority, {
      appId: APP_ID,
      challenge: CHALLENGE,
      rpId: "F6VXT39M7H.com.someone.else",
    });
    expect(await verifier()(keyId, CHALLENGE, attestation)).toBe("app_id");
  });

  it("refuses a key that has already signed something", async () => {
    const { keyId, attestation } = await makeAttestation(authority, {
      appId: APP_ID,
      challenge: CHALLENGE,
      signCount: 1,
    });
    expect(await verifier()(keyId, CHALLENGE, attestation)).toBe("counter");
  });

  it("refuses a development attestation once the server expects distributed builds", async () => {
    const { keyId, attestation } = await makeAttestation(authority, { appId: APP_ID, challenge: CHALLENGE });
    expect(await verifier({ developmentEnv: false })(keyId, CHALLENGE, attestation)).toBe("environment");
  });

  it("accepts a distributed attestation when it expects one", async () => {
    const { keyId, attestation } = await makeAttestation(authority, {
      appId: APP_ID,
      challenge: CHALLENGE,
      developmentEnv: false,
    });
    expect(typeof (await verifier({ developmentEnv: false })(keyId, CHALLENGE, attestation))).not.toBe("string");
  });

  it("refuses a credential id that disagrees with the key id", async () => {
    const { keyId, attestation } = await makeAttestation(authority, {
      appId: APP_ID,
      challenge: CHALLENGE,
      credentialId: new Uint8Array(32).fill(0x33),
    });
    expect(await verifier()(keyId, CHALLENGE, attestation)).toBe("credential_id");
  });

  it("refuses anything that is not an Apple attestation", async () => {
    const { keyId, attestation } = await makeAttestation(authority, {
      appId: APP_ID,
      challenge: CHALLENGE,
      format: "packed",
    });
    expect(await verifier()(keyId, CHALLENGE, attestation)).toBe("format");
    expect(await verifier()(keyId, CHALLENGE, new Uint8Array([1, 2, 3]))).toBe("malformed");
  });

  it("refuses a chain whose certificates have expired", async () => {
    const { keyId, attestation } = await makeAttestation(authority, { appId: APP_ID, challenge: CHALLENGE });
    const inTheFuture = verifier({ now: () => new Date("2045-01-01") });
    expect(await inTheFuture(keyId, CHALLENGE, attestation)).toBe("chain");
  });
});

describe("assertion", () => {
  const assertions = makeAssertionVerifier({ appId: APP_ID });

  async function attestedKey(): Promise<{ key: AttestedKey; keys: CryptoKeyPair }> {
    const { keyId, attestation, credentialKeys } = await makeAttestation(authority, { appId: APP_ID, challenge: CHALLENGE });
    const key = (await verifier()(keyId, CHALLENGE, attestation)) as AttestedKey;
    return { key, keys: credentialKeys };
  }

  it("accepts one signed by the attested key and advances the counter", async () => {
    const { key, keys } = await attestedKey();
    const clientDataHash = new Uint8Array(32).fill(0x44);
    const assertion = await makeAssertion({ appId: APP_ID, clientDataHash, keys, counter: 1 });

    expect(await assertions(assertion, clientDataHash, key)).toEqual({ counter: 1 });
  });

  it("refuses one signed over a different request", async () => {
    const { key, keys } = await attestedKey();
    const assertion = await makeAssertion({
      appId: APP_ID,
      clientDataHash: new Uint8Array(32).fill(0x44),
      keys,
      counter: 1,
    });
    // Same assertion, a different body: this is what binds a signature to one request.
    expect(await assertions(assertion, new Uint8Array(32).fill(0x55), key)).toBe("signature");
  });

  it("refuses one signed by a key we never attested", async () => {
    const { key } = await attestedKey();
    const impostor = await makeAttestation(authority, { appId: APP_ID, challenge: CHALLENGE });
    const clientDataHash = new Uint8Array(32).fill(0x44);
    const assertion = await makeAssertion({ appId: APP_ID, clientDataHash, keys: impostor.credentialKeys, counter: 1 });

    expect(await assertions(assertion, clientDataHash, key)).toBe("signature");
  });

  it("refuses a replay: the counter never goes backwards or stands still", async () => {
    const { key, keys } = await attestedKey();
    const clientDataHash = new Uint8Array(32).fill(0x44);
    const assertion = await makeAssertion({ appId: APP_ID, clientDataHash, keys, counter: 5 });

    expect(await assertions(assertion, clientDataHash, { ...key, counter: 4 })).toEqual({ counter: 5 });
    // Captured and sent again once the counter has been recorded.
    expect(await assertions(assertion, clientDataHash, { ...key, counter: 5 })).toBe("replay");
    expect(await assertions(assertion, clientDataHash, { ...key, counter: 9 })).toBe("replay");
  });

  it("refuses one made for another app", async () => {
    const { key, keys } = await attestedKey();
    const clientDataHash = new Uint8Array(32).fill(0x44);
    const assertion = await makeAssertion({
      appId: APP_ID,
      rpId: "F6VXT39M7H.com.someone.else",
      clientDataHash,
      keys,
      counter: 1,
    });
    expect(await assertions(assertion, clientDataHash, key)).toBe("app_id");
  });

  it("refuses rubbish", async () => {
    const { key } = await attestedKey();
    expect(await assertions(new Uint8Array([1, 2, 3]), new Uint8Array(32), key)).toBe("malformed");
  });
});

describe("the client data hash binds a challenge to a body", () => {
  it("changes when either does", async () => {
    const hash = async (challenge: string, body: string) =>
      base64(
        new Uint8Array(
          await crypto.subtle.digest(
            "SHA-256",
            concat(new TextEncoder().encode(challenge), new TextEncoder().encode(body)) as BufferSource,
          ),
        ),
      );
    const baseline = await hash("c1", "b1");
    expect(await hash("c2", "b1")).not.toBe(baseline);
    expect(await hash("c1", "b2")).not.toBe(baseline);
    expect(await hash("c1", "b1")).toBe(baseline);
  });
});
