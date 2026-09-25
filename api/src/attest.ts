import "reflect-metadata";   // @peculiar/x509 v2 uses tsyringe, which needs this before it loads
import { X509Certificate } from "@peculiar/x509";
import { decodeCBOR } from "@levischuck/tiny-cbor";

/**
 * App Attest: proving a request came from an unmodified build of this app on genuine Apple hardware
 * (SPEC §6, Phase 8b).
 *
 * 8a stopped a forged subscription. This stops a forged *device*: `x-device-id` is a UUID the client makes
 * up, so a patched app rotated it for a fresh trial every time. The Secure Enclave signs instead, and the
 * quota hangs off a key identity that cannot be invented.
 *
 * Two things it deliberately does not do. It does not limit how many keys one device may create — someone
 * with a real iPhone can still attest a fresh key per trial, and Apple's answer to that is the receipt and
 * the risk-metric API, which is why the receipt is kept. And it does not check certificate revocation.
 *
 * The checks below are Apple's, in Apple's order, from "Validating apps that connect to your server".
 */

export type AttestedKey = {
  keyId: string;
  publicKeyPem: string;
  /** Kept unused, so the risk-metric API can be added later without re-attesting anybody. */
  receipt: string;
  counter: number;
};

export type AttestationFailure =
  | "malformed"
  | "format"
  | "chain"
  | "nonce"
  | "key_id"
  | "app_id"
  | "counter"
  | "environment"
  | "credential_id";

export type AssertionFailure = "malformed" | "app_id" | "signature" | "replay";

/** Apple's nonce lives in this extension of the leaf certificate. */
const NONCE_OID = "1.2.840.113635.100.8.2";
/** Where the attested credential data begins, after rpIdHash (32), flags (1) and signCount (4). */
const AAGUID_OFFSET = 37;
const CREDENTIAL_ID_LENGTH_OFFSET = 53;
const CREDENTIAL_ID_OFFSET = 55;
/** A key id, and therefore a credential id, is always a SHA-256. */
const KEY_ID_BYTES = 32;

export type AttestationVerifierOptions = {
  /** "<teamId>.<bundleId>" — what Apple hashes into `rpIdHash`. */
  appId: string;
  /**
   * A development build attests with the aaguid `appattestdevelop`; a distributed one uses `appattest`
   * padded with zeros. Getting this backwards accepts the wrong builds, so it is explicit rather than
   * inferred.
   */
  developmentEnv: boolean;
  /** Apple's App Attest root, PEM. Overridable so the tests can sign their own chains. */
  rootCertificatePem: string;
  now?: () => Date;
};

export type AttestationVerifier = (
  keyId: string,
  challenge: Uint8Array,
  attestation: Uint8Array,
) => Promise<AttestedKey | AttestationFailure>;

export function makeAttestationVerifier(options: AttestationVerifierOptions): AttestationVerifier {
  const now = options.now ?? (() => new Date());

  return async (keyId, challenge, attestation) => {
    const parsed = parseAttestation(attestation);
    if (typeof parsed === "string") return parsed;
    const { credCert, intermediateCert, authData, receipt } = parsed;

    // 1. The chain: leaf issued by the intermediate, intermediate by Apple's root, all three in date.
    const root = new X509Certificate(options.rootCertificatePem);
    if (!(await verifyChain([credCert, intermediateCert], root, now()))) return "chain";

    // 2–4. nonce = SHA-256(authData ‖ clientDataHash), carried in the leaf's Apple extension.
    const clientDataHash = await sha256(challenge);
    const expectedNonce = await sha256(concat(authData, clientDataHash));
    const actualNonce = nonceFromCertificate(credCert);
    if (!actualNonce || !equalBytes(actualNonce, expectedNonce)) return "nonce";

    // 5. The key id is the SHA-256 of the public key's uncompressed point.
    const point = new Uint8Array(credCert.publicKey.rawData).slice(-65);
    if (point[0] !== 0x04) return "key_id";
    if (base64(await sha256(point)) !== keyId) return "key_id";

    // 6. The app this attestation was made for.
    const rpIdHash = authData.slice(0, 32);
    if (!equalBytes(rpIdHash, await sha256(new TextEncoder().encode(options.appId)))) return "app_id";

    // 7. A fresh key has never signed anything.
    if (readCounter(authData) !== 0) return "counter";

    // 8. Development builds and distributed builds are not interchangeable.
    const aaguid = authData.slice(AAGUID_OFFSET, AAGUID_OFFSET + 16);
    if (!equalBytes(aaguid, expectedAaguid(options.developmentEnv))) return "environment";

    // 9. The credential the attestation describes is the key we were told about.
    const credentialIdLength = (authData[CREDENTIAL_ID_LENGTH_OFFSET]! << 8) | authData[CREDENTIAL_ID_LENGTH_OFFSET + 1]!;
    if (credentialIdLength !== KEY_ID_BYTES) return "credential_id";
    const credentialId = authData.slice(CREDENTIAL_ID_OFFSET, CREDENTIAL_ID_OFFSET + KEY_ID_BYTES);
    if (base64(credentialId) !== keyId) return "credential_id";

    return {
      keyId,
      publicKeyPem: credCert.publicKey.toString("pem"),
      receipt: base64(receipt),
      counter: 0,
    };
  };
}

export type AssertionVerifier = (
  assertion: Uint8Array,
  clientDataHash: Uint8Array,
  key: AttestedKey,
) => Promise<{ counter: number } | AssertionFailure>;

export function makeAssertionVerifier(options: { appId: string }): AssertionVerifier {
  return async (assertion, clientDataHash, key) => {
    const parsed = parseAssertion(assertion);
    if (typeof parsed === "string") return parsed;
    const { signature, authData } = parsed;

    if (!equalBytes(authData.slice(0, 32), await sha256(new TextEncoder().encode(options.appId)))) {
      return "app_id";
    }

    const signed = await sha256(concat(authData, clientDataHash));
    if (!(await verifyECDSA(key.publicKeyPem, signature, signed))) return "signature";

    // The Secure Enclave counts its own signatures, so a captured assertion replayed later arrives with a
    // counter it has already used. This is the only thing standing between a sniffed request and a replay.
    const counter = readCounter(authData);
    if (counter <= key.counter) return "replay";

    return { counter };
  };
}

// MARK: Parsing

type ParsedAttestation = {
  credCert: X509Certificate;
  intermediateCert: X509Certificate;
  authData: Uint8Array;
  receipt: Uint8Array;
};

function parseAttestation(attestation: Uint8Array): ParsedAttestation | AttestationFailure {
  try {
    const object = decodeCBOR(attestation);
    if (!(object instanceof Map)) return "malformed";
    if (object.get("fmt") !== "apple-appattest") return "format";

    const statement = object.get("attStmt");
    const authData = object.get("authData");
    if (!(statement instanceof Map) || !(authData instanceof Uint8Array)) return "malformed";
    if (authData.length < CREDENTIAL_ID_OFFSET + KEY_ID_BYTES) return "malformed";

    const chain = statement.get("x5c");
    const receipt = statement.get("receipt");
    if (!Array.isArray(chain) || chain.length < 2) return "malformed";
    if (!(chain[0] instanceof Uint8Array) || !(chain[1] instanceof Uint8Array)) return "malformed";

    return {
      credCert: new X509Certificate(chain[0]),
      intermediateCert: new X509Certificate(chain[1]),
      authData,
      receipt: receipt instanceof Uint8Array ? receipt : new Uint8Array(),
    };
  } catch {
    return "malformed";
  }
}

function parseAssertion(assertion: Uint8Array): { signature: Uint8Array; authData: Uint8Array } | AssertionFailure {
  try {
    const object = decodeCBOR(assertion);
    if (!(object instanceof Map)) return "malformed";
    const signature = object.get("signature");
    const authData = object.get("authenticatorData");
    if (!(signature instanceof Uint8Array) || !(authData instanceof Uint8Array)) return "malformed";
    if (authData.length < 37) return "malformed";
    return { signature, authData };
  } catch {
    return "malformed";
  }
}

/**
 * The nonce sits in a `SEQUENCE { [1] { OCTET STRING } }`. Read the octet string's declared length rather
 * than taking the last 32 bytes: a certificate can carry a malformed extension whose length disagrees with
 * its contents, and slicing from the end would quietly accept it.
 */
function nonceFromCertificate(certificate: X509Certificate): Uint8Array | null {
  const extension = certificate.getExtension(NONCE_OID);
  if (!extension) return null;
  const value = new Uint8Array(extension.value);
  // 30 <len> A1 <len> 04 <len> <nonce>
  if (value.length < 6 || value[0] !== 0x30 || value[2] !== 0xa1 || value[4] !== 0x04) return null;
  const length = value[5]!;
  if (length !== KEY_ID_BYTES || value.length < 6 + length) return null;
  return value.slice(6, 6 + length);
}

// MARK: Primitives

async function verifyChain(chain: X509Certificate[], root: X509Certificate, at: Date): Promise<boolean> {
  const all = [...chain, root];
  for (const certificate of all) {
    if (certificate.notBefore > at || certificate.notAfter < at) return false;
  }
  for (let i = 0; i < all.length - 1; i++) {
    if (!(await all[i]!.verify({ publicKey: all[i + 1]!.publicKey, signatureOnly: true }))) return false;
  }
  return true;
}

async function verifyECDSA(publicKeyPem: string, signature: Uint8Array, data: Uint8Array): Promise<boolean> {
  const raw = derToRawSignature(signature);
  if (!raw) return false;
  const key = await crypto.subtle.importKey(
    "spki",
    pemToDer(publicKeyPem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"],
  );
  return crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key, raw, data);
}

/**
 * Apple signs with a DER `SEQUENCE { INTEGER r, INTEGER s }`; WebCrypto wants the two integers as fixed
 * 32-byte halves. The DER integers are signed, so they carry a leading zero when the high bit is set and
 * are short when the value is.
 */
function derToRawSignature(der: Uint8Array): Uint8Array | null {
  if (der.length < 8 || der[0] !== 0x30) return null;
  let offset = 2;
  const read = (): Uint8Array | null => {
    if (der[offset] !== 0x02) return null;
    const length = der[offset + 1]!;
    const start = offset + 2;
    if (start + length > der.length) return null;
    offset = start + length;
    let value = der.slice(start, start + length);
    while (value.length > 32 && value[0] === 0x00) value = value.slice(1);
    if (value.length > 32) return null;
    const padded = new Uint8Array(32);
    padded.set(value, 32 - value.length);
    return padded;
  };
  const r = read();
  const s = read();
  return r && s ? concat(r, s) : null;
}

function pemToDer(pem: string): Uint8Array {
  const base64Body = pem.replace(/-----(BEGIN|END) PUBLIC KEY-----/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(base64Body), (c) => c.charCodeAt(0));
}

function expectedAaguid(developmentEnv: boolean): Uint8Array {
  const aaguid = new Uint8Array(16);
  aaguid.set(new TextEncoder().encode(developmentEnv ? "appattestdevelop" : "appattest"));
  return aaguid;
}

function readCounter(authData: Uint8Array): number {
  const view = new DataView(authData.buffer, authData.byteOffset + 33, 4);
  return view.getUint32(0, false);
}

async function sha256(data: Uint8Array): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", data as BufferSource));
}

function concat(a: Uint8Array, b: Uint8Array): Uint8Array {
  const out = new Uint8Array(a.length + b.length);
  out.set(a);
  out.set(b, a.length);
  return out;
}

function equalBytes(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let difference = 0;
  for (let i = 0; i < a.length; i++) difference |= a[i]! ^ b[i]!;
  return difference === 0;
}

export function base64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}
