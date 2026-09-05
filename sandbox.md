# Sandbox workflow

The whole Atria boundary, walked on your own machine: get an agent
identity, run business calls through the proxy and change its rules, then
revoke the identity and watch only the proxy react. Everything runs on
loopback in one container — the real `atria-proxy` package plus openssl and
Python stand-ins for Atria Cloud and a customer backend.

**NOTE:** *usually* below marks the production workflow; where it is
written, the sandbox takes a shortcut for the sake of a self-contained
test.

## Run it

```
docker run -it --rm docker.io/trustatria/sandbox
```

drops you into a shell with everything already up:

```
./abc.sh          # A, then B, then C, straight through
./abc.sh -i       # the same, pausing before each call so you can read it
./a.sh ./b.sh ./c.sh    # one part at a time — state carries between them
```

Run it once and take its exit status instead of getting a shell:

```
docker run --rm docker.io/trustatria/sandbox batch
```

`ABC_BRIEF=1` drops the narration and keeps only each step and its result.
`TA_DELAY` (seconds, default 1.5) is the wait before each call so a run
stays under the shared rate limit.

## Environment and context

1. A Docker image with the `atria-proxy` Debian package, and:
2. the sandbox ships with an API key — *usually* the key is issued from
   <https://register.trustatria.com/>.
3. The API key is only good for minting a short-lived certificate —
   *usually* the agent does this itself.
4. That certificate establishes mTLS **and** signs a per-request proof
   sent in the `TA-Authorization` header. The proxy verifies the proof
   against the Atria CA's public key — no shared secret.
5. A second image runs the `atria-proxy` pointed at a mock business-logic
   backend, and also carries:
   - the proxy's own server certificate — *usually* the customer's own,
     for their hostname;
   - the proxy's rules, in YAML;
   - scripts that mimic an agent calling the backend — the customer API
     being protected.

## The execution workflow — A

*(get an identity and learn to present it)*

1. Register for an API key, then exchange it for a certificate
   (*usually* against <https://register.trustatria.com/>).
2. Build and sign a `TA-Authorization` proof for the request.
3. Call the running proxy. The mock backend does not require the proof —
   a real customer backend never does — **but the proxy does.**

## The execution workflow — B

*(the regular loop)*

Call the proxy, which forwards to the backend:

- `POST /mock-login` for the backend's own session token — any login and
  password (each at least six characters, valid JSON).
- `GET`/`POST`/`PUT`/`DELETE` `/mock-bl` and watch the rules decide each
  one — this is why the endpoint takes every method.
  - By **method**: a verb the policy grants reaches the backend; one it
    withholds stops at the proxy (`403 ENDPOINT_NOT_ALLOWED`).
  - By **payload**: a payment amount over the policy's ceiling is refused
    (`TRANSACTION_VALUE_EXCEEDS_LIMIT` for the exact field, or
    `VALUE_LIMIT_EXCEEDED` for the heuristic `value_guard` — which also
    matches money-ish field names, coerces numeric strings, and converts
    the currency).
- Change a rule in the YAML, reload the proxy with no restart, and re-run —
  a `403` becomes a `200`.

## The execution workflow — C

*(wrap-up)*

1. Call `/mock-bl` **directly**, on the mock session token — it works.
   That is the control for everything below.
2. Revoke the certificate at the cloud. *Usually* an agent revokes only
   its own, and only a sandbox-issued one.
3. Tell the proxy to pull `/crl`.
4. Now the same call **through the proxy** is refused
   (`403 CERTIFICATE_REVOKED`) while the **direct** call is unchanged — the
   proxy is what enforces revocation, and the backend never knew.
5. `POST /mock-logout` — it needs the token too; there is no server-side
   session to end, so it just answers `200`.
