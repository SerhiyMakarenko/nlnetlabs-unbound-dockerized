# General
[![Build image](https://github.com/SerhiyMakarenko/nlnetlabs-unbound-dockerized/actions/workflows/build.yml/badge.svg?branch=stable)](https://github.com/SerhiyMakarenko/nlnetlabs-unbound-dockerized/actions/workflows/build.yml)
[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg?style=flat)](https://github.com/SerhiyMakarenko/nlnetlabs-unbound-dockerized/blob/stable/LICENSE)

Unbound is a validating, recursive, caching DNS resolver. It is designed to be fast and lean and incorporates modern features based on open standards.

This image builds Unbound from NLnet Labs' signed source releases on Debian 13 (trixie) for `linux/amd64`, `linux/arm64` and `linux/arm/v7`.

# Tags
| Tag | Meaning |
|---|---|
| `latest` | Newest Unbound release, rebuilt monthly with current Debian security fixes |
| `1.26`, `1.26.0` | Newest build of that Unbound minor / patch version |
| `1.26.0-YYYYMMDD` | One specific build that never changes; pin this to roll back |

# Building the Image Yourself
Every Unbound version that gets published also gets a git tag (`v1.26.1`, ...) and a [GitHub Release](https://github.com/SerhiyMakarenko/nlnetlabs-unbound-dockerized/releases), created after the images are on Docker Hub:
```
git clone --branch v1.26.1 https://github.com/SerhiyMakarenko/nlnetlabs-unbound-dockerized.git
cd nlnetlabs-unbound-dockerized
docker build -t nlnetlabs-unbound-resolver .
```
The Dockerfile pins the source tarball by SHA-256, so a build from a tag uses exactly the verified source. The build needs BuildKit, which is the default since Docker 23. A tag marks the first release of each Unbound version; `stable` also carries later image changes and is what the monthly Docker Hub rebuilds use.

# Usage
```
docker run -d --name nlnetlabs-unbound-resolver --net=host \
    -v /path/to/unbound.conf:/usr/local/etc/unbound/unbound.conf:ro \
    -v unbound-anchor:/var/lib/unbound \
    serhiymakarenko/nlnetlabs-unbound-resolver:latest
```

Or with Docker Compose:
```yaml
services:
  unbound:
    image: serhiymakarenko/nlnetlabs-unbound-resolver:latest
    container_name: nlnetlabs-unbound-resolver
    network_mode: host
    restart: unless-stopped
    volumes:
      - ./unbound.conf:/usr/local/etc/unbound/unbound.conf:ro
      - unbound-anchor:/var/lib/unbound

volumes:
  unbound-anchor:
```

For DNSSEC validation, `unbound.conf` needs:
```
server:
    chroot: ""
    auto-trust-anchor-file: "/var/lib/unbound/root.key"
```

On every start, the entrypoint reads `auto-trust-anchor-file` from your config, then creates or repairs that trust anchor with `unbound-anchor` before starting Unbound. Keeping `/var/lib/unbound` on a volume lets Unbound follow DNS root key rollovers (RFC 5011) across container restarts and recreation.

# Upgrading from the 2019-2021 Image (Unbound 1.13.1 and older)
The old image baked a root trust anchor into the image at build time, so it was reset to a 2021 copy every time the container was recreated. That copy only has the root key KSK-2017. Since the root zone switched to KSK-2024 on 11 October 2026, that copy can no longer validate anything, so DNSSEC-validating setups on the old image fail every lookup with SERVFAIL.

Existing configs keep working unchanged: if yours keeps `root.key` at `/usr/local/etc/unbound/root.key` inside the default chroot, the entrypoint repairs the anchor there on every start. Moving to the layout above is still recommended, because it keeps the anchor across container recreation.

Other changes: Debian 10 → 13, OpenSSL 1.1.1 → 3.x, no `LD_LIBRARY_PATH`, no pidfile in the default command (`-p`). The `unbound` user is still UID/GID 88.

# How the Image is Maintained
- **Every build is tested before it is published.** CI starts the image with both config layouts and requires that a signed zone validates (AD flag), that a deliberately broken zone is rejected (SERVFAIL), and that the broken zone resolves with checking disabled (`+cd`), so the rejection is shown to come from validation.
- **New Unbound releases are picked up weekly.** A workflow checks for new releases and verifies the tarball's OpenPGP signature against NLnet Labs' pinned release key. It then opens a PR against `develop` with the new version and SHA-256.
- **Merging `develop` into `stable` publishes.** `stable` is also rebuilt without cache on the 1st of every month.