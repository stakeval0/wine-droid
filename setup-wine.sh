#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "setup-wine.sh must be run as root inside the proot Ubuntu rootfs." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WINE_VERSION="${WINE_DROID_WINE_VERSION:-9.0}"
WINE_ARCHIVE="wine-${WINE_VERSION}-amd64.tar.xz"
WINE_URL="https://github.com/Kron4ek/Wine-Builds/releases/download/${WINE_VERSION}/${WINE_ARCHIVE}"
INSTALL_DIR="/opt/wine${WINE_VERSION}"

apt-get update
apt-get install -y ca-certificates curl gcc libc6-dev tar xz-utils

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

curl -fL "$WINE_URL" -o "$tmpdir/$WINE_ARCHIVE"
tar -C "$tmpdir" -xf "$tmpdir/$WINE_ARCHIVE"

rm -rf "$INSTALL_DIR"
mv "$tmpdir/wine-${WINE_VERSION}-amd64" "$INSTALL_DIR"
ln -sfn "wine${WINE_VERSION}" /opt/wine

if [ -x "$INSTALL_DIR/bin/wineserver" ] && [ ! -e "$INSTALL_DIR/bin/wineserver.real" ]; then
  mv "$INSTALL_DIR/bin/wineserver" "$INSTALL_DIR/bin/wineserver.real"
fi
gcc "$SCRIPT_DIR/wineserver.c" -O2 -Wall -Wextra -o "$INSTALL_DIR/bin/wineserver"
chmod 755 "$INSTALL_DIR/bin/wineserver"

for exe in wine wine64 wineboot winecfg wineconsole winefile winepath wineserver regedit regsvr32; do
  if [ -e "/opt/wine/bin/$exe" ]; then
    ln -sfn "/opt/wine/bin/$exe" "/usr/local/bin/$exe"
  fi
done

# Kron4ek's /opt/wine/bin/wine is an i386 launcher. winetricks accepts WINE as
# a single executable path, so provide a stable wrapper for 32-bit prefixes.
cat >/usr/local/bin/wine-box86 <<'EOF'
#!/usr/bin/env sh
exec box86 /opt/wine/bin/wine "$@"
EOF
chmod 755 /usr/local/bin/wine-box86

echo "Installed Wine ${WINE_VERSION} at ${INSTALL_DIR}; /opt/wine now points to it."
