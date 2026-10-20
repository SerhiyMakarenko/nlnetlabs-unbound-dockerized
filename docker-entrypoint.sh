#!/bin/sh
# Keeps the root trust anchor valid before Unbound starts, at whatever path
# the mounted config names, so both config layouts work:
#
#   current: chroot: "" + auto-trust-anchor-file: "/var/lib/unbound/root.key"
#            with /var/lib/unbound on a volume (survives container recreation)
#   legacy:  default chroot + auto-trust-anchor-file:
#            "/usr/local/etc/unbound/root.key" (configs written for the
#            2019-2021 image keep working unchanged)
set -eu

SBIN=/usr/local/sbin

# Config file: the argument after -c, else the default used in CMD.
CONF=/usr/local/etc/unbound/unbound.conf
prev=
for arg in "$@"; do
    if [ "$prev" = "-c" ]; then CONF=$arg; fi
    prev=$arg
done

anchor=$("$SBIN/unbound-checkconf" -o auto-trust-anchor-file "$CONF" 2>/dev/null || true)

if [ -z "$anchor" ]; then
    echo "entrypoint: no auto-trust-anchor-file in $CONF, not managing a trust anchor" >&2
else
    case $anchor in
        /*) ;;
        *) anchor="$("$SBIN/unbound-checkconf" -o directory "$CONF")/$anchor" ;;
    esac
    dir=$(dirname "$anchor")
    mkdir -p "$dir"

    # Bootstrap a missing anchor, or repair one that missed a root KSK
    # rollover: unbound-anchor tries RFC 5011 over DNS first and, if the
    # stored anchor can no longer validate the root, rebuilds it from IANA's
    # root-anchors.xml verified against ICANN's certificate. Exit code 1
    # means "anchor was rebuilt" and is expected, so it is ignored.
    "$SBIN/unbound-anchor" -a "$anchor" || true

    if [ ! -s "$anchor" ]; then
        echo "entrypoint: FATAL: no root trust anchor at $anchor" >&2
        exit 1
    fi

    # The daemon drops to user unbound and rewrites the anchor through a temp
    # file + rename in the same directory, so it needs to own both.
    chown unbound:unbound "$dir" "$anchor" 2>/dev/null ||
        echo "entrypoint: WARNING: cannot give $anchor to user unbound; RFC 5011 updates will fail" >&2
    echo "entrypoint: trust anchor ready at $anchor" >&2
fi

exec "$SBIN/unbound" "$@"
