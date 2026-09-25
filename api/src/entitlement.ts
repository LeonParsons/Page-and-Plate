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
   * Overrides the pinned root. Xcode's local StoreKit configuration signs with a single self-signed
   * certificate it generates on the machine — `CN=StoreKit Testing in Xcode`, about a year's validity, and
   * its own leaf and root at once — so without this nothing bought in the simulator would verify and the
   * feature could only be tested against the real App Store. Export it with Xcode's
   * Editor ▸ Save Public Certificate on an open `.storekit` file; it is not the static
   * `StoreKitTestCertificate.cer` that ships inside the Xcode bundle, which signs nothing.
   */
  rootFingerprint?: string;
  /**
   * Accepts `environment: "Xcode"`, which is what a purchase through the local StoreKit configuration
   * carries. Only ever true alongside `rootFingerprint`: a transaction Apple signed is never in the Xcode
   * environment, so this cannot widen anything in production, where neither is set.
   */
  allowXcodeEnvironment?: boolean;
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

    // `Environment` only names Production and Sandbox; "Xcode" is real but absent from the enum, so the
    // comparison has to go through the string.
    const environment: string = payload.environment;
    const environmentAllowed =
      environment === "Production" ||
      (environment === "Sandbox" && options.allowSandbox) ||
      (environment === "Xcode" && options.allowXcodeEnvironment === true);
    if (!environmentAllowed) return reject("environment");

    return {
      productId: payload.productId,
      expiresAt: new Date(payload.expiresDate),
      environment: payload.environment,
    };
  };
}
