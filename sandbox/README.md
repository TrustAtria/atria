# Atria sandbox

**This is a generated copy.** The primary source is `trust-atria-srv/eval/abc/`
(private repo) — `sb.sh` mirrors its runtime scripts here one direction. A
hand-edit here is overwritten by the next mirror run; send changes to the
source instead. `Dockerfile`, `README.md` and `.dockerignore` are the
exceptions, kept hand-maintained on this side because the two build
contexts genuinely differ (this one is self-contained; the source one
reaches a sibling `packages/`).

One container running the real `atria-proxy` debian package, pointed at
the TA sandbox (`https://sandbox.trustatria.com`), walked the way
[`../sandbox.md`](../sandbox.md) describes it — get an identity, run
business calls through the proxy and change its rules, revoke and watch
only the proxy react.

`register`, `session`, the CA, the CRL, `admin/revoke`, and the mock
business logic (`/mock-login`, `/mock-bl`, `/mock-logout`) are all that
sandbox, over the network. The container ships the proxy, a
**sandbox-scoped API key** (`register-key.sh`), the sandbox **CA cert**
(public), the YAML rules, and the scripts — no key is minted here, and no
CA private key exists here.

`demo.tape` records the walkthrough as `demo.webm`
([VHS](https://github.com/charmbracelet/vhs)): `vhs demo.tape`.

## Run

```
docker run -it --rm docker.io/trustatria/sandbox
```

You land in a shell with the proxy up and pointed at the sandbox (needs
network to `sandbox.trustatria.com`):

```
./abc.sh          # A, then B, then C, straight through
./abc.sh -i       # the same, pausing before each call so you can read it
./a.sh ./b.sh ./c.sh   # one part at a time
./b1.sh … ./b5.sh      # one B step at a time — repeat any of them by hand
```

Or run it once and take its exit status:

```
docker run --rm docker.io/trustatria/sandbox batch
```

## What the three parts do

- **`a.sh` — Workflow A.** Register for an API key, exchange it for a
  short-lived certificate, then sign a `TA-Authorization` proof. The proxy
  requires the proof on every request; the mock backend never checks for
  it — a real customer backend does not.
- **`b.sh` — Workflow B**, five steps, each its own script (`b1.sh` …
  `b5.sh`) so you can repeat one by hand; `b.sh` runs them in order.
  **B1** `POST /mock-login` for the backend's own session token.
  **B2 — by method:** `GET` is granted, `DELETE` is not
  (`403 ENDPOINT_NOT_ALLOWED` — nothing denies it, it is just absent from
  the policy). **B3 — by payload:** `PUT`/`POST` carry a payment, and
  `max_transaction_value` bounds its `transaction_value` at any depth —
  250 usd passes, 5000 is `TRANSACTION_VALUE_EXCEEDS_LIMIT`, a string is
  `TRANSACTION_VALUE_NOT_NUMERIC`. **B4** raise the ceiling in
  `policies.yaml`, reload with no restart, the 5000 call goes through while
  `DELETE` stays blocked. **B5** add `value_guard` and reload: it matches
  any field whose name contains `value`/`amount`/`sum`/`total`, coerces
  numeric strings, and reads the currency from the body to convert it
  (`ATRIA_RATES_FILE`) — 900 EUR passes, 950 EUR is `VALUE_LIMIT_EXCEEDED`,
  and a matched field it cannot parse is skipped, not refused.
- **`c.sh` — Workflow C.** The backend answers a call reached directly on
  its own token. Self-revoke the certificate at `register.trustatria.com` —
  authenticated by a `TA-Authorization` proof signed with the certificate's
  own key, not by the API key, so only this certificate dies and the key
  stays live. Force the proxy to pull the new revocation list; now the same
  call through the proxy is refused (`403 CERTIFICATE_REVOKED`) while the
  direct call still works — the proxy is what enforces revocation, and the
  backend never knew.

## Options

| variable | default | |
|---|---|---|
| `ABC_PROXY` / `ABC_CLOUD` / `ABC_BACKEND` / `ABC_ADMIN` | loopback | point the same scripts at your own deployment |
| `ABC_PUBLIC_URL` | `ABC_PROXY` | the origin a proof is bound to — must equal the proxy's `ATRIA_PUBLIC_URL` |

To call from **outside** the container, publish the port
(`-p 8443:8443`) and set both `ABC_PUBLIC_URL` and the proxy's
`ATRIA_PUBLIC_URL` (in `env`) to the address you actually use, or every
proof is rejected on its URL binding.

## Build it yourself

```
docker build -t trustatria/sandbox sandbox/
docker run -it --rm trustatria/sandbox
```

`atria-proxy` is pulled from `apt.trustatria.com`; it must be a build where
mtls mode also verifies the `TA-Authorization` proof when `ATRIA_PUBLIC_URL`
is set — the proxy requires the client certificate at the handshake **and** a
signed proof on every request (`sandbox.md` L12).
