"""Fetch and fully validate the public offline Chinese model before activation."""
import hashlib
import json
import os
import tarfile
import time
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / '.local' / 'models'
NAME = 'vits-melo-tts-zh_en'
URL = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/' + NAME + '.tar.bz2'
REQUIRED = ['model.onnx', 'tokens.txt', 'lexicon.txt', 'date.fst', 'number.fst', 'phone.fst']


def archive_members(filename):
    # Traversing all members decompresses to EOF, detecting truncated downloads.
    with tarfile.open(filename) as package:
        members = package.getmembers()
        for member in members:
            parts = Path(member.name).parts
            if (not parts or parts[0] != NAME or '..' in parts
                    or Path(member.name).is_absolute() or member.issym() or member.islnk()
                    or not (member.isfile() or member.isdir())):
                raise RuntimeError('Unsafe model archive member')
        for name in REQUIRED:
            if not any(m.name == NAME + '/' + name and m.isfile() and m.size > 0 for m in members):
                raise RuntimeError('Incomplete model archive: ' + name)
        if not any(m.name.startswith(NAME + '/dict/') and m.isfile() for m in members):
            raise RuntimeError('Model dictionary missing')
        return members


def download():
    ROOT.mkdir(parents=True, exist_ok=True)
    model, archive, manifest = ROOT / NAME, ROOT / (NAME + '.tar.bz2'), ROOT / 'model-source.json'
    if manifest.exists() and all((model / f).is_file() for f in REQUIRED) and (model / 'dict').is_dir():
        print('Previously validated TTS model retained', flush=True)
        return
    if archive.exists():
        try:
            archive_members(archive)
        except (EOFError, OSError, tarfile.TarError, RuntimeError):
            archive.rename(ROOT / (archive.name + '.invalid-' + uuid.uuid4().hex))
            print('Incomplete prior download quarantined; retrying official release', flush=True)
    if not archive.exists():
        temporary = ROOT / (NAME + '.download')
        for attempt in range(3):
            try:
                offset = temporary.stat().st_size if temporary.exists() else 0
                headers = {'User-Agent': 'helmet-media-installer/1.0'}
                if offset:
                    headers['Range'] = 'bytes=%d-' % offset
                request = urllib.request.Request(URL, headers=headers)
                with urllib.request.urlopen(request, timeout=60) as source:
                    if source.status == 206:
                        if not source.headers.get('Content-Range', '').startswith('bytes %d-' % offset):
                            raise RuntimeError('Unexpected resume range')
                    else:
                        offset = 0  # A server may ignore Range; restart, never append a whole archive.
                    expected = int(source.headers.get('Content-Length', '0'))
                    received = 0
                    with temporary.open('ab' if offset else 'wb') as out:
                        while True:
                            chunk = source.read(64 * 1024)
                            if not chunk:
                                break
                            received += len(chunk)
                            if offset + received > 600 * 1024 * 1024:
                                raise RuntimeError('Unexpected model archive size')
                            out.write(chunk)
                        out.flush()
                        os.fsync(out.fileno())
                    if expected and received != expected:
                        raise RuntimeError('Incomplete HTTP download')
                archive_members(temporary)
                os.replace(temporary, archive)
                print('Complete model archive validated (%d bytes)' % archive.stat().st_size, flush=True)
                break
            except Exception as error:
                if attempt == 2:
                    raise RuntimeError('Official model download failed after three attempts') from error
                print('Download incomplete; resuming official release', flush=True)
                time.sleep(2)
    stage = ROOT / ('.extract-' + uuid.uuid4().hex)
    stage.mkdir(mode=0o700)
    with tarfile.open(archive) as package:
        package.extractall(stage, members=archive_members(archive))
    prepared = stage / NAME
    if not all((prepared / f).is_file() for f in REQUIRED) or not (prepared / 'dict').is_dir():
        raise RuntimeError('Extracted model incomplete')
    if model.exists():
        model.rename(ROOT / (NAME + '.incomplete-' + uuid.uuid4().hex))
    prepared.rename(model)
    stage.rmdir()
    digest = hashlib.sha256()
    with archive.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(chunk)
    manifest.write_text(json.dumps({'url': URL, 'sha256': digest.hexdigest()}, indent=2) + '\n')
    print('Offline Chinese model activated after complete archive verification', flush=True)


if __name__ == '__main__':
    download()
