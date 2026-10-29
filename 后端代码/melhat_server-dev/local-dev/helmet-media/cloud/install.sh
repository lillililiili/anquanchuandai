#!/bin/sh
# Called only on the explicitly authorized cloud after both package parts were uploaded.
set -eu
umask 077
MODE=preview
case "$#" in
  0) ;;
  1) if [ "$1" = --resume ]; then MODE=resume; else echo 'Usage: sh cloud/install.sh [--resume]' >&2; exit 2; fi ;;
  *) echo 'Usage: sh cloud/install.sh [--resume]' >&2; exit 2 ;;
esac
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
STATE=/var/lib/helmet-media-deploy/review-01
if [ -e "$STATE/deployment.json" ]; then
  echo 'Deployment transaction already exists; inspect it before retrying.' >&2
  exit 1
fi
python3 cloud/preflight.py
test -s .local/media.env
test -s .local/cloud-settings.json
test -s .local/freeswitch/freeswitch.xml
if [ "$MODE" = resume ]; then
  python3 cloud/deploy.py resume --state-dir "$STATE"
else
  mkdir -p .local/data/assets .local/models .local/srs-data .local/fs-logs .local/fs-db
  chmod 700 .local .local/data .local/data/assets .local/models .local/fs-logs .local/fs-db
  find .local -type f -exec chmod 600 {} +
  python3 cloud/deploy.py preview --state-dir "$STATE"
fi
# Build/download before touching active routes or SSH configuration.
docker compose config --quiet
docker compose build
docker compose pull srs turn
python3 cloud/download-model.py
docker compose up -d
if ! python3 cloud/check-ready.py; then
  docker compose stop
  echo 'New media services did not become ready. Existing routes were not changed; diagnostics retained.' >&2
  exit 1
fi
if ! python3 cloud/deploy.py apply --state-dir "$STATE" --settings .local/cloud-settings.json; then
  docker compose stop
  exit 1
fi
echo 'Media services and restricted routes are installed. Actual SIP registration, RTP and 4G business access still require external acceptance.'
echo 'Required cloud security-group inbound: TCP 1935,5060,3478; UDP 3478,8000,16384-16583,49160-49200. Existing HTTPS 443 remains in use.'
echo 'Do not expose 18190,18192,1985,8080,8021,5066,28088 or the local backend 18084.'
