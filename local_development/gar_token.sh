#!/bin/sh

# Prints a Google Artifact Registry access token on stdout.
#
# .npmrc expands this into _authToken for the pkg.dev registries, so something
# has to produce one before pnpm can install. Calling gcloud directly is the
# obvious way and is what mise used to do - but gcloud is a Python program and
# spawning it costs around 400ms, paid on every new shell in a repo that
# declares NPM_TOKEN. That is why opening a tmux window there was slow.
#
# gcloud caches the credential itself, so that 400ms buys nothing but process
# startup: the token handed back is almost always the one handed back last
# time. Caching the result moves the spawn from once a shell to once an hour.
#
# Access tokens live one hour. Refreshing at 45 minutes leaves margin, so a
# token handed out just before the cutoff is still valid well after it is used.

set -eu

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/gar"
CACHE="$CACHE_DIR/token"
MAX_AGE_MINUTES=45

# Age is the only freshness test. The cache cannot know that a token was
# revoked, or that `gcloud auth login` switched accounts, and finding out
# would cost a network round trip - more than the spawn being avoided. So a
# stale token is answered with --refresh rather than detected.
force_refresh=false
[ "${1:-}" = "--refresh" ] && force_refresh=true

if [ "$force_refresh" = false ] &&
   [ -n "$(find "$CACHE" -mmin "-$MAX_AGE_MINUTES" 2>/dev/null)" ]; then
    cat "$CACHE"
    exit 0
fi

mkdir -p "$CACHE_DIR"
chmod 700 "$CACHE_DIR"

# Write through a temporary file so a failing gcloud cannot truncate a cache
# that still holds a working token: npm answers an empty token with a 401,
# which reads as an auth problem rather than a missing one.
umask 077
tmp="$CACHE.$$"
trap 'rm -f "$tmp"' EXIT INT TERM

gcloud auth print-access-token > "$tmp"
[ -s "$tmp" ] || { echo "gar_token: gcloud returned an empty token" >&2; exit 1; }
mv "$tmp" "$CACHE"
cat "$CACHE"
