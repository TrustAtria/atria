# Trust Atria

Public repo for collaboration, testing, issues and best practices.

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

Better quality, downloadable: [`sandbox/demo.mp4`](sandbox/demo.mp4).
