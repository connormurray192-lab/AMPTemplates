#!/bin/bash
# Installs the Arcane MP dedicated server by pulling the project's public
# container image from ghcr and unpacking the server directory out of it.
# Arcane MP publishes no standalone server archive, so the image is the source.
#
# The project renamed at 1.12: releases up to 1.11.1 are published as
# hogwartsmp-server with a HogwartsMPServer binary under /opt/hogwartsmp, and
# 1.12.1+ as arcanemp-server with ArcaneMPServer under /opt/arcanemp. Both eras
# are supported, and whichever binary lands is exposed as ./arcane-server so the
# template has one stable thing to launch.
#
# Usage: arcane-install.sh <datadir> <version> [installFoundation] [foundationVersion]
set -e
D="${1:?target dir}"; VER="${2:-1.15.1}"; FND="${3:-false}"; FVER="${4:-v0.12.0}"
REPOS="arcane-mp/arcanemp-server arcane-mp/hogwartsmp-server"
ACCEPT='application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.docker.distribution.manifest.v2+json,application/vnd.oci.image.manifest.v1+json'
mkdir -p "$D" && cd "$D"

if [ -f .server-version ] && [ "$(cat .server-version)" = "$VER" ] && [ -x arcane-server ]; then
  echo "Arcane MP server $VER already installed"
else
  MAN=""; TOK=""; REPO=""
  for R in $REPOS; do
    T=$(curl -sf "https://ghcr.io/token?scope=repository:${R}:pull&service=ghcr.io" | tr ',' '\n' | sed -n 's/.*"token":"\([^"]*\)".*/\1/p' | head -1)
    [ -n "$T" ] || continue
    M=$(curl -sf -H "Authorization: Bearer $T" -H "Accept: $ACCEPT" "https://ghcr.io/v2/${R}/manifests/${VER}" 2>/dev/null) || true
    if [ -n "$M" ]; then MAN="$M"; TOK="$T"; REPO="$R"; break; fi
  done
  if [ -z "$MAN" ]; then
    echo "ERROR: version '$VER' was not found under ghcr.io/arcane-mp/arcanemp-server or ghcr.io/arcane-mp/hogwartsmp-server."
    echo "       Check the published tags at https://github.com/orgs/arcane-mp/packages"
    exit 1
  fi
  echo "Fetching Arcane MP server $VER from ghcr.io/${REPO} ..."

  # A multi-arch index points at per-platform manifests; follow the amd64 one.
  if printf '%s' "$MAN" | grep -q '"manifests"'; then
    SUB=$(printf '%s' "$MAN" | tr ',' '\n' | grep -B3 '"architecture":"amd64"' | sed -n 's/.*"digest":"\([^"]*\)".*/\1/p' | head -1)
    if [ -n "$SUB" ]; then
      MAN=$(curl -sf -H "Authorization: Bearer $TOK" -H "Accept: $ACCEPT" "https://ghcr.io/v2/${REPO}/manifests/${SUB}")
    fi
  fi

  LAYERS=$(printf '%s' "$MAN" | tr '{' '\n' | sed -n 's/.*"digest": *"\(sha256:[a-f0-9]*\)".*/\1/p' | sort -u)
  [ -n "$LAYERS" ] || { echo "ERROR: no layers found in the image manifest"; exit 1; }

  n=0
  for L in $LAYERS; do
    curl -sf -L -H "Authorization: Bearer $TOK" "https://ghcr.io/v2/${REPO}/blobs/${L}" -o .layer.tgz || continue
    # Only the server directory is wanted, flattened into the data directory so
    # that 'resources' and '.packages' sit beside the binary, as the server
    # expects (the image ships them as symlinks into its own data directory).
    SRC=$(tar -tzf .layer.tgz 2>/dev/null | grep -oE '^opt/(arcanemp|hogwartsmp)/' | head -1)
    if [ -n "$SRC" ]; then
      tar -xzf .layer.tgz --strip-components=2 "${SRC%/}" 2>/dev/null || true
      n=$((n + 1))
    fi
    rm -f .layer.tgz
  done
  [ "$n" -gt 0 ] || { echo "ERROR: the image contained no server files"; exit 1; }

  rm -f resources .packages 2>/dev/null || true
  chmod +x ArcaneMPServer HogwartsMPServer crashpad_handler 2>/dev/null || true
  BIN=""
  for B in ArcaneMPServer HogwartsMPServer; do
    if [ -x "$B" ]; then BIN="$B"; break; fi
  done
  [ -n "$BIN" ] || { echo "ERROR: no server binary found after extraction"; exit 1; }
  ln -sf "$BIN" arcane-server
  echo "$VER" > .server-version
  echo "Arcane MP server $VER installed (binary: $BIN)"
fi

mkdir -p resources logs .packages

# AMP edits server.json in place, so it has to exist before the first start.
if [ ! -f server.json ]; then
  cat > server.json <<'JSON'
{
    "download-url": "",
    "host": "0.0.0.0",
    "map": "",
    "maxplayers": 128,
    "mod": {
        "autoRespawn": true,
        "broomSpeedMultiplier": 1.0,
        "broomUpgradeTier": 0,
        "curseforge": {
            "mods": []
        },
        "gearStatMultiplier": 1.0,
        "gearTraits": true
    },
    "package-secret": "",
    "password": "",
    "port": 27015,
    "server-token": ""
}
JSON
  echo "Wrote a default server.json"
fi

case "$FND" in
  true|True)
    echo "Installing HMP Foundation resources $FVER ..."
    U="https://github.com/arcane-mp/foundations/releases/download/${FVER}/hmp-foundations-${FVER}.zip"
    if curl -sfL "$U" -o .foundation.zip; then
      unzip -oq .foundation.zip -d resources/ && rm -f .foundation.zip
      echo "Foundation resources installed into resources/ - they need a MySQL/MariaDB database, see https://github.com/arcane-mp/foundations/blob/main/DATABASE.md"
    else
      echo "WARNING: could not download Foundation $FVER ($U) - skipping"
      rm -f .foundation.zip
    fi
    ;;
esac
echo "Done."
