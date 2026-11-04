#!/usr/bin/env python3
"""Explicitly mark an existing, mounted shared directory. Never overwrites a marker."""
import argparse
import os
from pathlib import Path
import uuid


def initialize(root: Path, store_id: str):
    if str(uuid.UUID(store_id)) != store_id:
        raise ValueError("store-id must be a canonical lowercase UUID")
    root = root.resolve(strict=True)
    if not root.is_dir() or root == Path(root.anchor):
        raise ValueError("Use an existing dedicated directory, not a filesystem root")
    marker = root / ".wearable-store-id"
    # O_EXCL also rejects existing symlinks. Never replace another store identity.
    try:
        fd = os.open(str(marker), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o640)
    except FileExistsError:
        if marker.is_symlink() or not marker.is_file() or marker.read_bytes() != (store_id + '\n').encode('ascii'):
            raise ValueError("Existing store marker differs; stop and verify the mount")
        return
    with os.fdopen(fd, "w", encoding="ascii", newline="\n") as handle:
        handle.write(store_id + "\n")
        handle.flush()
        os.fsync(handle.fileno())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("store_id", help="same UUID configured on both application nodes")
    args = parser.parse_args()
    initialize(args.directory, args.store_id)
    print("Shared-store identity prepared. Verify this same identity and cross-node file readback on both hosts.")
