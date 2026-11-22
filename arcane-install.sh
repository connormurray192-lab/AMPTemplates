#!/bin/bash
# Installs the Arcane MP (HogwartsMP) dedicated server by pulling the project's
# public container image from ghcr and unpacking the server directory out of it.
# Arcane MP publishes no standalone server archive, so the image is the source.
# Usage: arcane-install.sh <datadir> <version> [installFoundation] [foundationVersion]
set -e
D="${1:?target dir}"; VER="${2:-1.11.1}"; FND="${3:-false}"; FVER="${4:-v0.12.0}"
REPO="arcane-mp/hogwartsmp-server"
mkdir -p "$D" && cd "$D"

if [ -f .server-version ] && [ "$(cat .server-version)" = "$VER" ] && [ -x HogwartsMPServer ]; then
  echo "Arcane MP server $VER already installed"
else
  echo "Fetching Arcane MP server $VER from ghcr.io/$REPO ..."
  TOK=$(curl -sf "https://ghcr.io/token?scope=repository:${REPO}:pull&service=ghcr.io" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
  [ -n "$TOK" ] || { echo "ERROR: could not get a registry token from ghcr.io"; exit 1; }
  ACCEPT='application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.docker.distribution.manifest.v2+json,application/vnd.oci.image.manifest.v1+json'
  MAN=$(curl -sf -H "Authorization: Bearer $TOK" -H "Accept: $ACCEPT" "https://ghcr.io/v2/${REPO}/manifests/${VER}") || true
  [ -n "$MAN" ] || { echo "ERROR: version '$VER' not found. Check the tag list at https://github.com/arcane-mp"; exit 1; }
  if printf '%s' "$MAN" | grep -q '"manifests"'; then
    SUB=$(printf '%s' "$MAN" | tr ',' '\n' | grep -B3 '"architecture":"amd64"' | sed -n 's/.*"digest":"\([^"]*\)".*/\1/p' | head -1)
    [ -n "$SUB" ] && MAN=$(curl -sf -H "Authorization: Bearer $TOK" -H "Accept: $ACCEPT" "https://ghcr.io/v2/${REPO}/manifests/${SUB}")
  fi
  LAYERS=$(printf '%s' "$MAN" | tr '{' '\n' | sed -n 's/.*"digest": *"\(sha256:[a-f0-9]*\)".*/\1/p' | sort -u)
  [ -n "$LAYERS" ] || { echo "ERROR: no layers found in the image manifest"; exit 1; }
  n=0
  for L in $LAYERS; do
    curl -sf -L -H "Authorization: Bearer $TOK" "https://ghcr.io/v2/${REPO}/blobs/${L}" -o .layer.tgz || continue
    # Only /opt/hogwartsmp is wanted, flattened into the data directory so that
    # 'resources' and '.packages' sit beside the binary as the server expects.
    if tar -tzf .layer.tgz 2>/dev/null | grep -q '^opt/hogwartsmp/'; then
      tar -xzf .layer.tgz --strip-components=2 opt/hogwartsmp 2>/dev/null || true
      n=$((n+1))
    fi
    rm -f .layer.tgz
  done
  [ "$n" -gt 0 ] || { echo "ERROR: the image contained no server files"; exit 1; }
  # The image ships these two as symlinks into /home/container; make them real.
  rm -f resources .packages 2>/dev/null || true
  chmod +x HogwartsMPServer crashpad_handler 2>/dev/null || true
  [ -x HogwartsMPServer ] || { echo "ERROR: HogwartsMPServer missing after extraction"; exit 1; }
  echo "$VER" > .server-version
  echo "Arcane MP server $VER installed"
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
