# A recording of the sandbox walkthrough (Output below: both an mp4 and a
# gif from the one run — the gif is what actually embeds inline in
# README.md; GitHub does not render a <video> tag against a plain
# repo-committed file, only its own upload-CDN URLs, so a <video src=
# "sandbox/demo.mp4"> silently shows nothing. The mp4 is still worth
# keeping — better quality, downloadable, linked from the README next to
# the gif).
#
# VHS (https://github.com/charmbracelet/vhs) drives a real terminal and
# records what actually happens, so this is the output, not a mock-up of
# it. The tape runs `docker` itself, so whatever renders it needs a docker
# CLI plus the daemon socket.
#
#   # native vhs on a host with docker:
#   vhs demo.tape
#
#   # or the vhs container - it has vhs+chromium+ffmpeg but no docker, so
#   # pass the client and the socket in:
#   docker run --rm \
#     -v /var/run/docker.sock:/var/run/docker.sock \
#     -v /usr/bin/docker:/usr/bin/docker:ro \
#     -v "$PWD":/vhs \
#     ghcr.io/charmbracelet/vhs demo.tape
#
# Either way it pulls docker.io/trustatria/sandbox (or `docker tag` a local
# build to that name first) and writes demo.mp4 + demo.gif.
#
# The run uses ABC_BRIEF=1 - step headers and results only, about a fifth
# of the full transcript, paced with a beat of its own since there is no
# narration left to give a reader time to read a result (briefpause in
# lib.sh, plus a longer one between b.sh's five steps) - see the Sleep
# right after it starts, sized from a measured real run, not guessed.

Output demo.mp4
Output demo.webm
Output demo.gif

Set Shell bash
Set FontSize 15
Set Width 1300
Set Height 940
Set Padding 22
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms

Type "# The whole Atria boundary, on your machine. Get the image:"
Enter
Sleep 1500ms

Type "docker pull docker.io/trustatria/sandbox"
Enter
Sleep 4s

Type "# Start it, interactive. The entrypoint brings up the one service"
Enter
Type "# here - the real atria-proxy in mTLS mode - pointed at the TA"
Enter
Type "# sandbox (sandbox.trustatria.com); register / CA / CRL / revoke and"
Enter
Type "# the mock business logic are all that host, over the network."
Enter
Sleep 1500ms

Type "docker run -it --rm docker.io/trustatria/sandbox"
Enter
Sleep 8s

Type "# A: get an identity.  B: calls through the proxy, by method and by"
Enter
Type "# payload, then a live rule change.  C: revoke, and watch only the"
Enter
Type "# proxy react."
Enter
Sleep 2s

Type "ABC_BRIEF=1 ./abc.sh"
Enter
# Measured 71.5s end to end against the real sandbox (run-local.sh,
# 2026-09-05, briefpause + b.sh's inter-step beat included) — 60s was
# cutting it off mid-B4. 100s for real-network variance on top.
Sleep 80s

Type "# Every call is plain curl against a real proxy. Read a.sh, b1.sh .."
Enter
Type "# b5.sh, c.sh and change any line. exit tears the container down."
Enter
Sleep 2s

Type "exit"
Enter
Sleep 3s
