import { decodeTransaction } from "app-store-server-api";

/**
 * Proving the `x-entitlement` header is a subscription Apple actually sold (SPEC §6, Phase 8).
 *
 * The app sends `Transaction.jwsRepresentation` — the signed transaction StoreKit 2 holds for the current
 * entitlement. Its JWS header carries the certificate chain that signed it: a leaf, an intermediate, and
 * Apple Root CA - G3. `decodeTransaction` walks that chain — each certificate in date, each issued and
 * signed by the next — pins the root by SHA-256 fingerprint, and only then verifies the signature with the
 * leaf's key. Until this existed the Worker accepted anything shaped like `a.b.c`.
 *
 * What it deliberately does not do is ask Apple anything. Verification is offline, so a scan never waits on
 * the App Store, and the one thing we give up — OCSP revocation of Apple's own signing certificate — is
 * covered where it matters by `revocationDate` in the payload, which is how a refunded subscription
 * announces itself.
 */

export type Entitlement = {
  productId: string;
  expiresAt: Date;
  environment: string;
};

/** Null for every failure, so a forged header and an absent one lead to the same place: the free trial. */
export type EntitlementVerifier = (jws: string) => Promise<Entitlement | null>;

export type VerifierOptions = {
  bundleId: string;
  /** The subscription products we sell; mirrored from `Subscription/Products.swift`. */
  productIds: readonly string[];
  /**
   * Whether to accept a Sandbox transaction. True while the app is in development and TestFlight — every
   * purchase there is Sandbox — and **false before public release**, or a sandbox account is a free pass.
   */
  allowSandbox: boolean;
  /**
   * Overrides the pinned root. Xcode's local StoreKit configuration signs with a certificate authority it
   * generates per machine, so without this nothing bought in the simulator would verify and the feature
   * could only be tested against the real App Store.
   */
  rootFingerprint?: string;
  now?: () => Date;
  /** Called with the reason a header was refused, for the request log. Never called for an absent header. */
  onReject?: (reason: RejectionReason) => void;
};

export type RejectionReason =
  | "signature"
  | "bundle"
  | "product"
  | "expired"
  | "revoked"
  | "environment";

export function makeVerifier(options: VerifierOptions): EntitlementVerifier {
  const now = options.now ?? (() => new Date());
  const products = new Set(options.productIds);

  return async (jws: string): Promise<Entitlement | null> => {
    const reject = (reason: RejectionReason) => {
      options.onReject?.(reason);
      return null;
    };

    let payload: Awaited<ReturnType<typeof decodeTransaction>>;
    try {
      payload = await decodeTransaction(jws, options.rootFingerprint);
    } catch {
      // A malformed header, a chain that does not reach our root, a tampered payload — all the same answer.
      return reject("signature");
    }

    if (payload.bundleId !== options.bundleId) return reject("bundle");
    if (!products.has(payload.productId)) return reject("product");
    if (payload.revocationDate !== undefined) return reject("revoked");

    // A subscription transaction always carries an expiry; one without it is not a subscription.
    if (payload.expiresDate === undefined || payload.expiresDate <= now().getTime()) {
      return reject("expired");
    }

    if (payload.environment !== "Production" && !(payload.environment === "Sandbox" && options.allowSandbox)) {
      return reject("environment");
    }

    return {
      productId: payload.productId,
      expiresAt: new Date(payload.expiresDate),
      environment: payload.environment,
    };
  };
}
