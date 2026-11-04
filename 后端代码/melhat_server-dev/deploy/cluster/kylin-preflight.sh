#!/usr/bin/env bash
# Run as the same host user that owns the application shared directory.
set -euo pipefail
mode=kylin
if [[ ${1:-} == --lab ]]; then mode=lab; shift; fi
if [[ ${1:-} == --help ]]; then
  echo 'SHARED_FILES_DIR=/mnt/wearable/files MELHAT_FILES_STORE_ID=<UUID> ./kylin-preflight.sh [--lab]'
  echo 'Default requires Kylin V10 x86_64 and an NFS mount. --lab never certifies Kylin/NFS.'
  exit 0
fi
[[ $# == 0 ]] || { echo 'Unexpected arguments' >&2; exit 2; }
fail() { echo "FAIL: $*" >&2; exit 1; }
for cmd in uname docker findmnt python3; do command -v "$cmd" >/dev/null || fail "Missing executable: $cmd"; done
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' || fail 'Python 3.9 or newer is required'
[[ $(uname -m) == x86_64 ]] || fail 'An x86_64 host is required'
[[ -r /etc/os-release ]] || fail '/etc/os-release is unavailable'
# /etc/os-release is installed by the host OS, never sourced from the delivery bundle.
. /etc/os-release
if [[ $mode == kylin ]]; then
  [[ ${ID,,} == *kylin* || ${NAME,,} == *kylin* ]] || fail 'Target OS is not Kylin'
  [[ ${VERSION_ID:-} == 10* || ${VERSION:-} == *V10* ]] || fail 'Target is not Kylin V10'
fi
printf 'OS=%s\nARCH=%s\nKERNEL=%s\nMODE=%s\n' "${PRETTY_NAME:-unknown}" "$(uname -m)" "$(uname -r)" "$mode"
docker version --format 'DOCKER_CLIENT={{.Client.Version}} DOCKER_SERVER={{.Server.Version}}'
docker compose version
docker info --format 'DOCKER_ARCH={{.Architecture}} CGROUP={{.CgroupVersion}}'
root=${SHARED_FILES_DIR:?Set SHARED_FILES_DIR to the mounted shared file directory}
[[ $root == /* && $root != / && -d $root ]] || fail 'Shared file directory must be an existing absolute directory, not /'
fs=$(findmnt -n -T "$root" -o FSTYPE)
options=$(findmnt -n -T "$root" -o OPTIONS)
printf 'SHARED_FSTYPE=%s\n' "$fs"
if [[ $mode == kylin ]]; then
  [[ $fs == nfs || $fs == nfs4 ]] || fail 'Production shared files must use the reviewed NFS mount'
  [[ ,$options, != *,soft,* && ,$options, != *,softerr,* ]] || fail 'Use a hard NFS mount; soft failures can corrupt writes'
fi
python3 - "$root" "${MELHAT_FILES_STORE_ID:?Set the expected shared-store UUID}" <<'PY'
import hashlib, os, pathlib, sys, tempfile, uuid
root = pathlib.Path(sys.argv[1]).resolve(strict=True)
marker = root / '.wearable-store-id'
if marker.is_symlink() or not marker.is_file() or marker.read_text().strip() != sys.argv[2]:
    raise RuntimeError('Shared store identity is missing or does not match; do not write to the backing local directory')
source = target = None
try:
    fd, source = tempfile.mkstemp(prefix='.wearable-preflight-', dir=root)
    payload = os.urandom(4096)
    with os.fdopen(fd, 'wb') as f:
        f.write(payload)
        f.flush()
        os.fsync(f.fileno())
    target = root / ('.wearable-preflight-' + uuid.uuid4().hex)
    os.replace(source, target)
    if hashlib.sha256(target.read_bytes()).digest() != hashlib.sha256(payload).digest():
        raise RuntimeError('Shared file readback differs from the write')
    print('FILE_CREATE_FLUSH_RENAME_READBACK=PASS')
finally:
    for p in (source, target):
        if p is not None:
            pathlib.Path(p).unlink(missing_ok=True)
PY
if [[ $mode == lab ]]; then
  echo 'PASS: local preflight only; Kylin, NFS and real-device acceptance remain pending.'
else
  echo 'PASS: host prerequisites only. Both application UIDs, cross-host visibility and business acceptance must still be verified.'
fi
