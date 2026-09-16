#!/usr/bin/env bash
set -euo pipefail
umask 022

# KNX Bridge Installer/Updater (eHive One / Debian arm64)
#
# Stable:
#   curl -fsSL https://raw.githubusercontent.com/ehive-dev/KNXBridge_releases/main/install.sh | sudo bash
# Bestimmte Version:
#   curl -fsSL https://raw.githubusercontent.com/ehive-dev/KNXBridge_releases/main/install.sh | sudo bash -s -- --tag v0.1.1

APP_NAME="knx-bridge"
UNIT="knx-bridge.service"
REPO="${REPO:-ehive-dev/KNXBridge_releases}"
TAG="${TAG:-}"
ARCH_REQ="arm64"
PORT="${PORT:-3032}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      [[ $# -ge 2 && -n "$2" ]] || { echo "--tag benötigt eine Version." >&2; exit 2; }
      TAG="$2"
      shift 2
      ;;
    --repo)
      [[ $# -ge 2 && -n "$2" ]] || { echo "--repo benötigt owner/repo." >&2; exit 2; }
      REPO="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: sudo $0 [--tag vX.Y.Z] [--repo owner/repo]"
      exit 0
      ;;
    *)
      echo "Unbekannter Parameter: $1" >&2
      exit 2
      ;;
  esac
done

info(){ printf '\033[1;34m[i]\033[0m %s\n' "$*"; }
ok(){ printf '\033[1;32m[✓]\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
fail(){ printf '\033[1;31m[✗]\033[0m %s\n' "$*" >&2; exit 1; }

[[ ${EUID:-$(id -u)} -eq 0 ]] || fail "Bitte als root ausführen (sudo)."
command -v apt-get >/dev/null || fail "apt-get wurde nicht gefunden."
command -v dpkg >/dev/null || fail "dpkg wurde nicht gefunden."
command -v dpkg-deb >/dev/null || fail "dpkg-deb wurde nicht gefunden."
command -v systemctl >/dev/null || fail "systemd wird benötigt."

missing=()
command -v curl >/dev/null || missing+=(curl)
command -v jq >/dev/null || missing+=(jq)
command -v node >/dev/null || missing+=(nodejs)
if (( ${#missing[@]} )); then
  info "Installiere benötigte Werkzeuge: ${missing[*]}"
  apt-get update
  apt-get install -y "${missing[@]}"
fi

node_major="$(node -p "Number(process.versions.node.split('.')[0])")"
(( node_major >= 18 )) || fail "KNX Bridge benötigt Node.js 18 oder neuer."

arch="$(dpkg --print-architecture)"
[[ "$arch" == "$ARCH_REQ" ]] || fail "KNX Bridge benötigt ${ARCH_REQ}; erkannt wurde ${arch}."

if [[ -n "$TAG" ]]; then
  api="https://api.github.com/repos/${REPO}/releases/tags/${TAG}"
else
  api="https://api.github.com/repos/${REPO}/releases/latest"
fi

info "Ermittle KNX-Bridge-Release aus ${REPO} ..."
release="$(curl -fsSL --retry 3 -H 'Accept: application/vnd.github+json' "$api")" \
  || fail "Das KNX-Bridge-Release konnte nicht geladen werden."
release_tag="$(printf '%s' "$release" | jq -r '.tag_name // empty')"
url="$(printf '%s' "$release" | jq -r --arg arch "$arch" '
  [.assets[]? | select(.name | test("^knx-bridge_[0-9].*_" + $arch + "\\.deb$"))]
  | .[0].browser_download_url // empty
')"
[[ -n "$release_tag" ]] || fail "Die Release-Antwort enthält keine Version."
[[ -n "$url" ]] || fail "Kein KNX-Bridge-Paket für ${arch} in ${release_tag} gefunden."

tmp_dir="$(mktemp -d -t knx-bridge-install.XXXXX)"
trap 'rm -rf "$tmp_dir"' EXIT
deb_file="${tmp_dir}/knx-bridge.deb"

info "Lade KNX Bridge ${release_tag} ..."
curl -fL --retry 3 --retry-delay 1 -o "$deb_file" "$url"
[[ "$(dpkg-deb -f "$deb_file" Package)" == "$APP_NAME" ]] || fail "Ungültiger Paketname im Release."
[[ "$(dpkg-deb -f "$deb_file" Architecture)" == "$arch" ]] || fail "Falsche Paketarchitektur im Release."

info "Installiere KNX Bridge ..."
if ! dpkg -i "$deb_file"; then
  warn "Paketabhängigkeiten werden repariert."
  apt-get -f install -y
  dpkg -i "$deb_file"
fi

systemctl enable --now "$UNIT"
for _ in {1..30}; do
  if curl -fsS "http://127.0.0.1:${PORT}/healthz" >/dev/null; then
    installed="$(dpkg-query -W -f='${Version}' "$APP_NAME")"
    ok "KNX Bridge ${installed} läuft auf Port ${PORT}."
    exit 0
  fi
  sleep 1
done

systemctl status "$UNIT" --no-pager >&2 || true
fail "KNX Bridge wurde installiert, der Health-Check ist jedoch fehlgeschlagen."
