# Using Trust Atria — an agent integration guide

How an AI agent authenticates to a Trust Atria proxy and calls a backend
through it. Written to be read by the agent's author, human or AI.

Trust Atria is a policy proxy in front of a backend API. Your agent gets a
short-lived certificate, presents it on every request, and the proxy
decides — **certificate → revocation → policy**, first failure wins —
whether to forward the call. Nothing about your backend changes; the
enforcement is entirely in the proxy.

- A runnable end-to-end example: [`sandbox.md`](sandbox.md) and
  [`sandbox/`](sandbox/) — see *Try it: the sandbox* at the end.
- Product and architecture detail: <https://trustatria.com>.

---

## 1. What you need

| | |
|---|---|
| **An API key** | `atria_<id>_<secret>` — long-lived, opaque, issued to an account at <https://register.trustatria.com/>. An operator creates it and hands it to you; only its hash is stored. **It never goes to the proxy** — it is used once per session, against the registration API, to get a certificate. |
| **The registration API base URL** | `https://register.trustatria.com/api` for Trust Atria's own service; a customer running their own CA has their own. |
| **The proxy URL** | the host your agent actually calls — the customer's domain, or `https://sandbox.trustatria.com` for the sandbox. |

That is all. In proof mode the CA is pinned on the proxy side, so you
distribute no secret and no CA material.

## 2. Get a session certificate

Exchange the API key for a certificate. Do this once per session, and again
before the certificate expires.

```
POST {register}/session
Authorization: Bearer atria_<id>_<secret>
Content-Type: application/json

{ "csr": "<PEM PKCS#10 CSR>" }        # optional — omit to have a keypair minted for you
```

Response (`201`):

```json
{
  "agent_id": "billing-bot",
  "serial": "5f3a…",
  "certificate_pem": "-----BEGIN CERTIFICATE-----\n…",
  "private_key_pem": "-----BEGIN PRIVATE KEY-----\n…",   // only when you sent no CSR
  "not_after": "2026-01-01T12:15:00Z"
}
```

- **Send a CSR** so the private key never leaves your process. Omitting it
  is a convenience for demos only.
- **Lifetime**: 15 minutes by default, 24 hours maximum. Renew by calling
  `/session` again before `not_after`; there is no refresh token.
- The certificate's subject carries three things, all set by the issuer,
  none of which you can change:
  - `CN=<agent_id>` — your identity, the key the policy is written against;
  - `atria-key:<id>` — which API key minted it, so a request traces back to
    an account;
  - `atria-scope:<set>` — the **destination scope set**: the host matchers
    this credential may be routed to (see §4). Absent means "anywhere".

Every credential failure here — unknown key, deactivated key, malformed key
— answers with the **same** `401`. The endpoint will not tell you whether a
key id is real.

## 3. Call through the proxy

There are two ways to present the certificate. **Which one a deployment
uses is the operator's choice, not yours** — ask, or try mTLS first.

### mTLS (the proxy terminates TLS)

Present the certificate at the TLS handshake, exactly as any client-cert
TLS. Nothing Atria-specific in the request itself.

```
curl --cert client.pem --key client.key \
     https://proxy.example.com/api/v1/orders -d '{"amount": 250}'
```

### Proof (something terminates TLS in front of the proxy)

A CDN, tunnel, load balancer or nginx has already terminated TLS, so the
handshake never reaches the proxy. Instead, sign a **proof** per request
with the certificate's private key and send it in one header:

```
TA-Authorization: <compact JWS>
```

The JWS binds the request's method, URL and body, so it cannot be replayed
against a different call. Field-by-field reference and an integration
sketch are in [§6](#6-the-proof-field-by-field); [`sandbox/jws-es256.py`](sandbox/jws-es256.py)
is a ~90-line Python reference. Some deployments require **both** — the
client certificate at the handshake *and* a matching proof on every
request.

### What comes back

- On success: whatever the backend returned.
- On a block: a bare `403` (or `429` for a rate limit) and a **stable
  reason code** in the body — `ENDPOINT_NOT_ALLOWED`,
  `TRANSACTION_VALUE_EXCEEDS_LIMIT`, `CERTIFICATE_REVOKED`,
  `CERTIFICATE_EXPIRED`, `CERTIFICATE_WRONG_DEPLOYMENT`,
  `DESTINATION_NOT_ALLOWED`, `RATE_LIMIT_EXCEEDED`, `INVALID_PROOF`, …
- **Which rule matched is never in the response** — it is in the operator's
  audit log. A `403` tells you *that* you crossed a boundary, not where it
  sits.

The proxy forwards your verified `agent_id` to the backend as
`x-atria-agent-id`; any such header you send yourself is dropped.

## 4. Route to a specific backend (optional)

One proxy can front several backends. Name your target with a header:

```
TA-Proxy-Pass: api.internal.example.com
```

With no header, the request goes to the proxy's **default route**. With
one, the host must pass **both** gates or the request is `403`:

1. a matcher in your certificate's `atria-scope:` set —
   `CERTIFICATE_WRONG_DEPLOYMENT` if not;
2. the proxy operator's own allow-list —
   `DESTINATION_NOT_ALLOWED` if not.

Matchers are an exact host (`api.example.com`), a suffix wildcard
(`*.example.com` — one or more labels under the suffix, never the bare
suffix and never a substring), or `*` (any). **The set is fixed on the API
key** (or an RBAC role it belongs to) at issuance — no request field,
header or claim can widen it. If you need a different destination, you need
a differently scoped key.

## 5. Renew and revoke

- **Renew**: `POST {register}/session` again before `not_after`. Do it
  ahead of expiry — the proxy re-checks validity on *every* request, not
  just at connect, so a long-lived connection does not outlive its
  certificate.
- **Self-revoke one certificate**:

  ```
  POST {register}/session/revoke
  TA-Authorization: <proof signed with the certificate being revoked>
  ```

  Proof of possession of the certificate's key is the authority to revoke
  *that certificate* — only that serial goes on the revocation list; the
  API key stays live and the agent is not suspended. (On the sandbox, only
  a `sandbox`-scoped certificate may self-revoke.)

Revocation is eventually consistent: the proxy pulls the list on an
interval, so a revoked certificate keeps working until the next pull.

## 6. The proof, field by field

A compact JWS (RFC 7515), one per request, never reused or cached.

**Protected header:**

```json
{
  "alg": "ES256",
  "typ": "atria-proof+jws",
  "x5c": ["<base64 DER of the leaf certificate>"]
}
```

`ES256` because the CA issues P-256 certificates. `x5c` carries only the
leaf — the proxy already has the CA pinned.

**Claims:**

| claim | value |
|---|---|
| `htm` | the HTTP method |
| `htu` | the full request URL, **no query string or fragment** |
| `iat` | issued-at, unix seconds — must be within a short freshness window (~30s) |
| `jti` | a random nonce; the proxy rejects a repeat within the window |
| `bh`  | base64url SHA-256 of the request body (the hash of the empty string when there is no body) |

`htu` is the full URL, not just the path, so a proof minted for one
hostname cannot be replayed against another that presents the same
certificate.

**The proxy verifies**, in this order, collapsing every failure to one
`401` shape: parse the header → take the leaf from `x5c[0]` → chain it to
the pinned CA → check revocation → verify the signature against the leaf's
key → `iat` fresh → `jti` unseen → `htm`/`htu` match the request exactly
(never normalised) → `bh` matches the body → `agent_id` is the leaf
subject. Policy evaluation then proceeds identically to mTLS mode.

**Integration sketch** — any JOSE library with `ES256` and an `x5c` header
does this shape:

```
cert_pem, private_key = <from POST /session>

def sign_request(method, url, body: bytes | None) -> str:
    claims = {
        "htm": method,
        "htu": url,                                  # full URL, no query
        "iat": now_unix(),
        "jti": random_hex(16),
        "bh":  base64url(sha256(body or b"")),
    }
    header = {"alg": "ES256", "typ": "atria-proof+jws",
              "x5c": [der_base64(cert_pem)]}
    return jws_sign_compact(header, claims, private_key)

headers["TA-Authorization"] = sign_request(method, url, body)
```

[`sandbox/jws-es256.py`](sandbox/jws-es256.py) is a ~90-line reference in
Python, for use inside `curl -H "TA-Authorization: $(…)"`. Trust Atria's own
`atria-ca sign-proof` CLI wraps the same function.

## 7. Behind nginx, a CDN or an ALB (proof mode)

If the terminator in front is only there to share port 443 or route by
hostname, forward TCP (`ssl_preread`) and mTLS reaches the proxy untouched
— proof mode is not needed. Where something *must* terminate (a WAF, a CDN,
an nginx serving other paths), it has three rules, all defaults:

1. **Do not rewrite the path** — `proxy_pass http://…:8443;` with no
   trailing slash, no `rewrite`. A stripped prefix changes `htu`.
2. **Do not normalise the path** — `merge_slashes off;`. The proxy rejects
   ambiguous paths rather than guessing; folding `//` ahead of it hides the
   case it exists to catch.
3. **Do not touch `TA-Authorization` or the body** — both pass through
   unchanged by default. A dedicated header, so a front that rewrites
   `Authorization` for its own auth leaves the proof alone.

A working `server` block is at
[trustatria.com/install](https://trustatria.com/install) under
*Behind nginx*, and ships beside the `atria-proxy` package.

## Try it: the sandbox

The whole boundary in one container — the real `atria-proxy` pointed at
`https://sandbox.trustatria.com`, nothing stubbed:

```
docker run -it --rm docker.io/trustatria/sandbox
./abc.sh            # A, then B, then C, straight through
```

Every call is plain `curl` you can read and change.
[`sandbox.md`](sandbox.md) is the walkthrough spec; mapped onto this guide:

| sandbox | this guide |
|---|---|
| **A** — register, get a certificate, sign the first proof | §2, §3, §6 |
| **B** — calls through the proxy: by method, by payload value, then a live rule change | §3, §4 |
| **C** — self-revoke, pull the CRL, watch only the proxy react | §5 |
