#!/usr/bin/env bash
# End-to-end check that the image resolves AND validates DNSSEC:
# a signed zone must come back with the AD flag, a deliberately broken
# zone must be SERVFAIL, and the same broken zone must resolve with +cd
# (which proves the SERVFAIL comes from validation, not from the network).
#
# usage: smoke-test.sh IMAGE CONFIG [PLATFORM]
set -euo pipefail

IMAGE=${1:?usage: smoke-test.sh IMAGE CONFIG [PLATFORM]}
CONFIG=$(realpath "${2:?usage: smoke-test.sh IMAGE CONFIG [PLATFORM]}")
PLATFORM=${3:-}
NAME="unbound-smoke-$$"
PORT=5053

if ! command -v dig >/dev/null; then
  sudo apt-get update -qq && sudo apt-get install -y -qq bind9-dnsutils >/dev/null
fi

cleanup() {
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "--- unbound log ---"
    docker logs "$NAME" 2>&1 | tail -n 100 || true
  fi
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  exit "$rc"
}
trap cleanup EXIT

run_args=(-d --name "$NAME"
  -p "127.0.0.1:${PORT}:53/udp" -p "127.0.0.1:${PORT}:53/tcp"
  -v "${CONFIG}:/usr/local/etc/unbound/unbound.conf:ro")
[ -n "$PLATFORM" ] && run_args+=(--platform "$PLATFORM")
docker run "${run_args[@]}" "$IMAGE" >/dev/null

q()      { dig @127.0.0.1 -p "$PORT" +time=5 +tries=2 "$@" 2>&1 || true; }
status() { q "$@" | sed -n 's/.*status: \([A-Z]*\),.*/\1/p'; }
has_ad() { local out; out=$(q +dnssec "$@"); grep -Eq '^;; flags:[a-z ]* ad[ ;]' <<<"$out"; }
fail()   { echo "FAIL: $*" >&2; exit 1; }

echo "Testing $(basename "$CONFIG")${PLATFORM:+ on $PLATFORM}; waiting for the trust anchor to prime..."
for _ in $(seq 1 60); do   # generous: the arm/v7 run is emulated
  has_ad . SOA && break
  sleep 2
done

has_ad . SOA                                     || fail "root not validated: trust anchor did not prime"
has_ad nlnetlabs.nl A                            || fail "signed zone returned without the AD flag"
[ "$(status dnssec-failed.org A)" = SERVFAIL ]    || fail "deliberately broken zone was not rejected"
[ "$(status +cd dnssec-failed.org A)" = NOERROR ] || fail "broken zone unreachable even with +cd (network?)"

echo "PASS: resolution and DNSSEC validation work"
docker logs "$NAME" 2>&1 | grep -E -m2 'entrypoint: trust anchor|keytag query' || true
