import "reflect-metadata";
import { Extension, X509Certificate, X509CertificateGenerator, cryptoProvider } from "@peculiar/x509";
import { encodeCBOR } from "@levischuck/tiny-cbor";

/**
 * Builds App Attest payloads the way a device would, so `attest.test.ts` can prove each of Apple's checks
 * bites without a device, without Apple, and without a network.
 *
 * The trust anchor is a root we generate here and hand to the verifier — the same trick that made Phase 8a
 * testable. A leaf has to be minted per attestation rather than committed as a fixture, because the nonce
 * inside it is a hash of that attestation's own `authData` and challenge.
 */

cryptoProvider.set(crypto as unknown as Crypto);

const NONCE_OID = "1.2.840.113635.100.8.2";
const ES256 = { name: "ECDSA", hash: "SHA-256", namedCurve: "P-256" } as const;

export type Authority = {
  rootPem: string;
  rootKeys: CryptoKeyPair;
  intermediate: X509Certificate;
  intermediateKeys: CryptoKeyPair;
};

export async function makeAuthority(): Promise<Authority> {
  const rootKeys = await generateKeys();
  const root = await X509CertificateGenerator.createSelfSigned({
    serialNumber: "01",
    name: "CN=Test App Attest Root",
    notBefore: new Date("2020-01-01"),
    notAfter: new Date("2040-01-01"),
    signingAlgorithm: ES256,
    keys: rootKeys,
    extensions: [],
  });

  const intermediateKeys = await generateKeys();
  const intermediate = await X509CertificateGenerator.create({
    serialNumber: "02",
    subject: "CN=Test App Attest Intermediate",
    issuer: root.subject,
    notBefore: new Date("2020-01-01"),
    notAfter: new Date("2040-01-01"),
    signingAlgorithm: ES256,
    publicKey: intermediateKeys.publicKey,
    signingKey: rootKeys.privateKey,
  });

  return { rootPem: root.toString("pem"), rootKeys, intermediate, intermediateKeys };
}

export type AttestationOptions = {
  appId: string;
  challenge: Uint8Array;
  developmentEnv?: boolean;
  /** Overrides, one per check, so each test breaks exactly one thing. */
  aaguid?: string;
  signCount?: number;
  credentialId?: Uint8Array;
  nonce?: Uint8Array;
  rpId?: string;
  signedBy?: Authority;
  format?: string;
};

export type Attestation = {
  keyId: string;
  attestation: Uint8Array;
  credentialKeys: CryptoKeyPair;
  authData: Uint8Array;
};

export async function makeAttestation(authority: Authority, options: AttestationOptions): Promise<Attestation> {
  const credentialKeys = await generateKeys();
  const point = new Uint8Array((await crypto.subtle.exportKey("raw", credentialKeys.publicKey)) as ArrayBuffer);
  const keyId = base64(await sha256(point));
  const credentialId = options.credentialId ?? (await sha256(point));

  const authData = await buildAuthData({
    rpId: options.rpId ?? options.appId,
    signCount: options.signCount ?? 0,
    aaguid: options.aaguid ?? (options.developmentEnv === false ? "appattest" : "appattestdevelop"),
    credentialId,
  });

  const nonce = options.nonce ?? (await sha256(concat(authData, await sha256(options.challenge))));
  const signer = options.signedBy ?? authority;
  const leaf = await X509CertificateGenerator.create({
    serialNumber: "03",
    subject: "CN=Test Credential",
    issuer: signer.intermediate.subject,
    notBefore: new Date("2020-01-01"),
    notAfter: new Date("2040-01-01"),
    signingAlgorithm: ES256,
    publicKey: credentialKeys.publicKey,
    signingKey: signer.intermediateKeys.privateKey,
    extensions: [new Extension(NONCE_OID, false, nonceExtension(nonce))],
  });

  const attestation = encodeCBOR(
    new Map<string, unknown>([
      ["fmt", options.format ?? "apple-appattest"],
      [
        "attStmt",
        new Map<string, unknown>([
          ["x5c", [new Uint8Array(leaf.rawData), new Uint8Array(signer.intermediate.rawData)]],
          ["receipt", new Uint8Array([0xde, 0xad, 0xbe, 0xef])],
        ]),
      ],
      ["authData", authData],
    ]) as never,
  );

  return { keyId, attestation: new Uint8Array(attestation), credentialKeys, authData };
}

export async function makeAssertion(options: {
  appId: string;
  clientDataHash: Uint8Array;
  keys: CryptoKeyPair;
  counter: number;
  rpId?: string;
}): Promise<Uint8Array> {
  const authData = concat(await sha256(new TextEncoder().encode(options.rpId ?? options.appId)), header(options.counter));
  const signed = await sha256(concat(authData, options.clientDataHash));
  const raw = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, options.keys.privateKey, signed as BufferSource));

  const encoded = encodeCBOR(
    new Map<string, unknown>([
      ["signature", rawToDerSignature(raw)],
      ["authenticatorData", authData],
    ]) as never,
  );
  return new Uint8Array(encoded);
}

// MARK: Bytes

async function buildAuthData(options: {
  rpId: string;
  signCount: number;
  aaguid: string;
  credentialId: Uint8Array;
}): Promise<Uint8Array> {
  const aaguid = new Uint8Array(16);
  aaguid.set(new TextEncoder().encode(options.aaguid).slice(0, 16));

  const rpIdHash = await sha256(new TextEncoder().encode(options.rpId));
  const credentialIdLength = new Uint8Array([options.credentialId.length >> 8, options.credentialId.length & 0xff]);
  // A COSE public key would follow; nothing we verify reads it, so a marker keeps the shape honest.
  const cosePlaceholder = new Uint8Array([0xa1, 0x01, 0x02]);

  return concat(
    concat(concat(rpIdHash, header(options.signCount)), concat(aaguid, credentialIdLength)),
    concat(options.credentialId, cosePlaceholder),
  );
}

/** flags (attested credential data present) and the four-byte big-endian counter. */
function header(counter: number): Uint8Array {
  const bytes = new Uint8Array(5);
  bytes[0] = 0x40;
  new DataView(bytes.buffer).setUint32(1, counter, false);
  return bytes;
}

function nonceExtension(nonce: Uint8Array): ArrayBuffer {
  // SEQUENCE { [1] { OCTET STRING nonce } }
  const der = new Uint8Array(6 + nonce.length);
  der.set([0x30, 4 + nonce.length, 0xa1, 2 + nonce.length, 0x04, nonce.length]);
  der.set(nonce, 6);
  return der.buffer as ArrayBuffer;
}

/** The inverse of the verifier's DER reader: WebCrypto signs raw r‖s, Apple's devices emit DER. */
function rawToDerSignature(raw: Uint8Array): Uint8Array {
  const integer = (value: Uint8Array): number[] => {
    let start = 0;
    while (start < value.length - 1 && value[start] === 0x00) start++;
    const trimmed = [...value.slice(start)];
    if (trimmed[0]! & 0x80) trimmed.unshift(0x00);
    return [0x02, trimmed.length, ...trimmed];
  };
  const body = [...integer(raw.slice(0, 32)), ...integer(raw.slice(32))];
  return new Uint8Array([0x30, body.length, ...body]);
}

async function generateKeys(): Promise<CryptoKeyPair> {
  return crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]) as Promise<CryptoKeyPair>;
}

async function sha256(data: Uint8Array): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", data as BufferSource));
}

export function concat(a: Uint8Array, b: Uint8Array): Uint8Array {
  const out = new Uint8Array(a.length + b.length);
  out.set(a);
  out.set(b, a.length);
  return out;
}

export function base64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}
