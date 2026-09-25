#!/usr/bin/env bash
#
# Generates the certificate chains `test/entitlement.test.ts` signs its fixtures with.
#
# Apple signs a StoreKit transaction with a leaf certificate, and puts the leaf, its intermediate and the
# Apple Root CA - G3 in the JWS header's `x5c`. Verifying means walking that chain and pinning the root by
# SHA-256 fingerprint. To test our half of that we need a chain of our own: a root to pin, a leaf to sign
# with, and enough wrong chains to prove each check actually bites.
#
# Run from api/:  bash scripts/make-test-pki.sh
# The output is committed — this is only for regenerating it, in 2046 or if a case is added.

set -euo pipefail

out="test/fixtures/pki"
rm -rf "$out"
mkdir -p "$out"

days=7300   # 20 years; these expire in 2046

ec_key() {
  openssl ecparam -name prime256v1 -genkey -noout -out "$out/$1.sec1.pem" 2>/dev/null
  openssl pkcs8 -topk8 -nocrypt -in "$out/$1.sec1.pem" -out "$out/$1.key.pem"
  rm "$out/$1.sec1.pem"
}

# A self-signed root.
root() {
  ec_key "$1"
  openssl req -x509 -new -key "$out/$1.key.pem" -sha256 -days $days \
    -subj "/CN=Page and Plate Test Root $2" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -out "$out/$1.crt.pem" 2>/dev/null
}

# A certificate signed by another. `ca` is TRUE for an intermediate, FALSE for a leaf.
signed() {
  local name=$1 issuer=$2 cn=$3 ca=$4
  shift 4
  ec_key "$name"
  openssl req -new -key "$out/$name.key.pem" -subj "/CN=$cn" -out "$out/$name.csr" 2>/dev/null
  if [ "$ca" = "TRUE" ]; then
    printf 'basicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\n' > "$out/$name.ext"
  else
    printf 'basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\n' > "$out/$name.ext"
  fi
  openssl x509 -req -in "$out/$name.csr" -CA "$out/$issuer.crt.pem" -CAkey "$out/$issuer.key.pem" \
    -CAcreateserial -sha256 -extfile "$out/$name.ext" "$@" -out "$out/$name.crt.pem" 2>/dev/null
  rm "$out/$name.csr" "$out/$name.ext"
}

# The chain the tests treat as Apple's.
root root A
signed intermediate root "Page and Plate Test Intermediate" TRUE -days $days
signed leaf intermediate "Page and Plate Test Leaf" FALSE -days $days

# Signed by the right intermediate but already out of date, for the validity-window check.
signed expired-leaf intermediate "Page and Plate Expired Leaf" FALSE \
  -not_before 20200101000000Z -not_after 20210101000000Z

# A second, unrelated chain. Its leaf dropped into the first chain proves the issuer check bites, and its
# root's fingerprint proves the pin does.
root other-root B
signed other-intermediate other-root "Page and Plate Other Intermediate" TRUE -days $days
signed other-leaf other-intermediate "Page and Plate Other Leaf" FALSE -days $days

rm -f "$out"/*.srl

echo "--- fingerprints (SHA-256) ---"
for c in root other-root; do
  printf '%-12s %s\n' "$c" "$(openssl x509 -in "$out/$c.crt.pem" -noout -fingerprint -sha256 | cut -d= -f2)"
done
ls "$out"
