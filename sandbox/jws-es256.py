#!/usr/bin/env python3
"""Sign one `TA-Authorization` proof — a compact ES256 JWS that carries the
agent certificate in `x5c` and binds the method, URL and body of a single
request. `trust-atria-project/agent.md` is the field-by-field reference;
this is the client half of it, small enough to read in one sitting.

    jws-es256.py --cert agent-cert.pem --key agent-key.pem \
        --method POST --url https://proxy.example/api/v1/orders --body '{"x":1}'

Prints the compact JWS on stdout, nothing else, so it drops into a shell
variable. Needs the `cryptography` package (apt: python3-cryptography,
pip: cryptography)."""

import argparse
import base64
import hashlib
import json
import os
import sys
import time

try:
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec, utils
    from cryptography.x509 import load_pem_x509_certificate
except ImportError:
    sys.exit("this needs the `cryptography` package — `apt install python3-cryptography` "
             "or `pip install cryptography`")


def b64u(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cert", required=True)
    ap.add_argument("--key", required=True)
    ap.add_argument("--method", required=True)
    ap.add_argument("--url", required=True)
    ap.add_argument("--body", default="")
    ap.add_argument("--freshness-skew", type=int, default=0,
                    help="seconds to add to iat, for testing a stale proof")
    args = ap.parse_args()

    key = serialization.load_pem_private_key(open(args.key, "rb").read(), password=None)
    cert = load_pem_x509_certificate(open(args.cert, "rb").read())
    cert_der = cert.public_bytes(serialization.Encoding.DER)

    # x5c is base64 with padding (RFC 7515 4.1.6), the one field that is not
    # base64url — the leaf only; the proxy already pins the CA.
    header = {
        "alg": "ES256",
        "typ": "atria-proof+jws",
        "x5c": [base64.b64encode(cert_der).decode()],
    }
    body_bytes = args.body.encode()
    claims = {
        "htm": args.method,
        "htu": args.url,
        "iat": int(time.time()) + args.freshness_skew,
        "jti": os.urandom(16).hex(),
        "bh": b64u(hashlib.sha256(body_bytes).digest()),
    }

    signing_input = f"{b64u(json.dumps(header).encode())}.{b64u(json.dumps(claims).encode())}"
    der_sig = key.sign(signing_input.encode(), ec.ECDSA(hashes.SHA256()))
    # JWS wants the raw r‖s pair, 32 bytes each — not the DER SEQUENCE openssl
    # and `cryptography` hand back.
    r, s = utils.decode_dss_signature(der_sig)
    raw_sig = r.to_bytes(32, "big") + s.to_bytes(32, "big")

    print(f"{signing_input}.{b64u(raw_sig)}")


if __name__ == "__main__":
    main()
