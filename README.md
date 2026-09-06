# Trust Atria

Public repo for collaboration, testing, issues and best practices.

## Using Trust Atria

[`agent.md`](agent.md) is the integration guide — get an API key, exchange
it for a short-lived certificate, present it (mTLS or a `TA-Authorization`
proof), route to a backend with `TA-Proxy-Pass`, renew and revoke. The
runnable version of the same flow is the sandbox below.

## Sandbox

The whole Atria boundary in one container — the real `atria-proxy` in mTLS
mode, pointed at the live TA sandbox (register + session + CA + CRL +
revoke, and the mock business logic) over the network; nothing is stood in
for inside the container. [`sandbox.md`](sandbox.md) is the walkthrough
spec (A: get an identity, B: calls through the proxy and a live rule
change, C: revoke and watch only the proxy react). [`sandbox/`](sandbox/)
is the image source and the scripts.

```
docker run -it --rm docker.io/trustatria/sandbox
./abc.sh -i
```

or run it once and take the exit status:

```
docker run --rm docker.io/trustatria/sandbox batch
```

`sandbox/demo.tape` records the walkthrough with
[VHS](https://github.com/charmbracelet/vhs).

![Sandbox walkthrough demo](sandbox/demo.gif)

Better [`quality`](https://www.youtube.com/watch?v=zyTGbVb33mU).
