import type { AttestedKey } from "./attest.ts";

/**
 * One-time challenges, and the keys that have been attested (SPEC §6, Phase 8b).
 *
 * A challenge is what stops an attestation or an assertion being captured and sent again: the server says
 * which random value to sign, remembers it for five minutes, and forgets it the moment it is used. An
 * assertion the server never asked for is worth nothing.
 *
 * Eventually consistent like the quota, and for the same reason it does not matter: a challenge raced
 * across two edges buys one extra scan, not an unlimited supply, and the Secure Enclave's counter closes
 * that anyway.
 */

const CHALLENGE_TTL_SECONDS = 5 * 60;
const CHALLENGE_BYTES = 32;

export function challengeKey(challenge: string): string {
  return `challenge:${challenge}`;
}

export function attestedKeyKey(keyId: string): string {
  return `attest:${keyId}`;
}

/** A fresh challenge, remembered until it is used or five minutes pass. */
export async function issueChallenge(kv: KVNamespace): Promise<string> {
  const bytes = crypto.getRandomValues(new Uint8Array(CHALLENGE_BYTES));
  const challenge = base64url(bytes);
  await kv.put(challengeKey(challenge), "1", { expirationTtl: CHALLENGE_TTL_SECONDS });
  return challenge;
}

/** True once, and only for a challenge this server issued. */
export async function consumeChallenge(kv: KVNamespace, challenge: string): Promise<boolean> {
  if (!challenge) return false;
  const key = challengeKey(challenge);
  if ((await kv.get(key)) === null) return false;
  await kv.delete(key);
  return true;
}

export async function readAttestedKey(kv: KVNamespace, keyId: string): Promise<AttestedKey | null> {
  const stored = await kv.get(attestedKeyKey(keyId));
  if (stored === null) return null;
  try {
    const parsed = JSON.parse(stored) as AttestedKey;
    return typeof parsed.publicKeyPem === "string" && typeof parsed.counter === "number" ? parsed : null;
  } catch {
    return null;
  }
}

/** No TTL: an attested key is the device's identity, and the trial it spends must not come back. */
export async function writeAttestedKey(kv: KVNamespace, key: AttestedKey): Promise<void> {
  await kv.put(attestedKeyKey(key.keyId), JSON.stringify(key));
}

export function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function fromBase64(value: string): Uint8Array | null {
  try {
    const padded = value.replace(/-/g, "+").replace(/_/g, "/");
    return Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
  } catch {
    return null;
  }
}
