#!/usr/bin/env bash
# Prints version identities only; never dumps container environment or configuration.
set -euo pipefail
printf 'RECORDED_AT=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
uname -srmo
if [[ -r /etc/os-release ]]; then
  python3 - <<'PY'
from pathlib import Path
for line in Path('/etc/os-release').read_text().splitlines():
    if line.startswith(('ID=', 'VERSION_ID=', 'PRETTY_NAME=')):
        print(line)
PY
fi
docker version --format 'DOCKER_CLIENT={{.Client.Version}} DOCKER_SERVER={{.Server.Version}}'
docker compose version
for image in "${BACKEND_IMAGE:-}" "${GATEWAY_IMAGE:-}" "${CADDY_IMAGE:-}" "${DM8_IMAGE:-}" "${REDIS_IMAGE:-}" "${MEDIA_IMAGE:-}"; do
  [[ -z $image ]] && continue
  docker image inspect "$image" --format 'IMAGE={{.RepoTags}} ID={{.Id}} DIGESTS={{.RepoDigests}} ARCH={{.Architecture}}'
done
if [[ -n ${BACKEND_IMAGE:-} ]]; then
  docker run --rm --network none --entrypoint java "$BACKEND_IMAGE" -version
fi
if [[ -n ${GATEWAY_IMAGE:-} ]]; then
  docker run --rm --network none --entrypoint node "$GATEWAY_IMAGE" --version
fi
echo 'Record DM8 SELECT * FROM V$VERSION, JDBC manifest/hash and external media versions separately.'
