#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
python3 cloud/deploy.py rollback --state-dir /var/lib/helmet-media-deploy/review-01
# Only this compose project's containers are stopped; recordings and configuration remain.
docker compose stop
