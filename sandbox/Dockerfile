# The Atria sandbox walkthrough as one image: the real atria-proxy debian
# package, pointed at the TA sandbox (https://sandbox.trustatria.com), and
# the a/b/c scripts from trust-atria-project's sandbox.md. Nothing else runs
# here — register / session / CA / CRL / revoke and the mock business logic
# (/mock-*) are all the sandbox, over the network.
#
#   sandbox/register-key.sh          # register the shipped sandbox API key
#   curl -fsS https://sandbox.trustatria.com/ca -o sandbox/atria-ca.pem
#   docker build -t trustatria/sandbox sandbox/
#   docker run -it --rm trustatria/sandbox
#
# atria-proxy is pulled from the public apt repository. It must be a build
# where mtls mode also verifies the TA-Authorization proof when
# ATRIA_PUBLIC_URL is set (sandbox.md L12): the proxy requires the client
# certificate at the handshake AND a signed proof on every request.
ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}

ARG APT_URL=https://apt.trustatria.com
ARG APT_SUITE=atria
ARG APT_COMPONENT=main

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg adduser jq bash \
      python3 python3-cryptography \
 && curl -fsSL "${APT_URL}/trustatria.gpg.key" | gpg --dearmor -o /usr/share/keyrings/trustatria.gpg \
 && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/trustatria.gpg] ${APT_URL} ${APT_SUITE} ${APT_COMPONENT}" \
      > /etc/apt/sources.list.d/atria.list \
 && apt-get update && apt-get install -y --no-install-recommends atria-proxy \
 && rm -rf /var/lib/apt/lists/* \
 && dpkg -s atria-proxy | sed -n 's/^Version: /installed atria-proxy /p'

WORKDIR /opt/abc
# .dockerignore keeps Dockerfile/README.md/demo.tape/demo.webm out of the
# image entirely — excluded before the layer exists, not deleted after
# (a later `rm` still leaves a file recoverable from an earlier layer).
COPY . /opt/abc/
RUN chmod 0755 /opt/abc/entrypoint.sh /opt/abc/*.sh \
 && printf 'sandbox\n' > /opt/abc/API_VERSION

ENV ABC_SANDBOX=https://sandbox.trustatria.com \
    ABC_PROXY=https://127.0.0.1:8443 \
    ABC_ADMIN=http://127.0.0.1:8081 \
    ABC_PUBLIC_URL=https://127.0.0.1:8443 \
    ABC_STATE=/opt/abc/state

EXPOSE 8443
ENTRYPOINT ["/opt/abc/entrypoint.sh"]
CMD ["shell"]
