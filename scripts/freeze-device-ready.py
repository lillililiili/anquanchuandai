"""Freeze a local device-integration candidate without Git commits or tags.

Includes versionable project files (tracked and non-ignored new files), APK,
PC dist bundles and backend JAR. Excludes database contents and local credentials.
Run after all builds pass. The output directory must not already exist.
"""
import datetime
import hashlib
import json
import pathlib
import shutil
import subprocess
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
VERSION = 'device-ready-20261007'
OUTPUT = ROOT / 'output' / 'releases' / VERSION
PROJECTS = ('android代码/', 'pc前台项目/', 'pc后台项目/', '后端代码/', '新版安卓端开发/', 'scripts/')


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args])


def freeze():
    assert not OUTPUT.exists(), 'Refuse to overwrite a frozen candidate; use a new version identifier'
    apk = ROOT / 'android代码/melhat_android-main/build/app/outputs/flutter-apk/app-debug.apk'
    jar = ROOT / '后端代码/melhat_server-dev/ruoyi-admin/target/fdc-admin.jar'
    assert apk.is_file() and jar.is_file()
    for project in ('pc前台项目', 'pc后台项目'):
        assert (ROOT / project / 'dist/index.html').is_file()
    candidates = git('ls-files', '--cached', '--others', '--exclude-standard', '-z').decode('utf-8').split('\0')
    files = sorted(set(p for p in candidates if p and (p.startswith(PROJECTS) or p in ('README.md', '.gitignore')) and (ROOT / p).is_file()))
    assert files
    OUTPUT.mkdir(parents=True)
    records = []
    with zipfile.ZipFile(OUTPUT / 'source.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
        for name in files:
            source = ROOT / name
            records.append({'path': name, 'bytes': source.stat().st_size, 'sha256': digest(source)})
            archive.write(source, name)
    shutil.copy2(apk, OUTPUT / 'android-ldplayer-debug.apk')
    shutil.copy2(jar, OUTPUT / 'backend.jar')
    for project, name in [('pc前台项目', 'pc-portal'), ('pc后台项目', 'pc-admin')]:
        shutil.make_archive(str(OUTPUT / name), 'zip', ROOT / project / 'dist')
    artifacts = [{'file': p.name, 'bytes': p.stat().st_size, 'sha256': digest(p)} for p in sorted(OUTPUT.iterdir()) if p.is_file()]
    manifest = {
        'version': VERSION, 'status': '待真实设备联调版',
        'createdAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'gitBranch': git('branch', '--show-current').decode().strip(),
        'gitBase': git('rev-parse', 'HEAD').decode().strip(),
        'includesUncommittedWork': True, 'gitCommitOrTagCreated': False,
        'backendUrlInApk': 'http://127.0.0.1:18084', 'apkMode': 'debug, WEAR_MOCK=false, LDPlayer adb reverse required',
        'hardwareValidated': False, 'databaseIncluded': False,
        'sourceFileCount': len(records), 'sourceFiles': records, 'artifacts': artifacts,
    }
    (OUTPUT / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'version': VERSION, 'files': len(records), 'output': str(OUTPUT), 'artifacts': artifacts}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    freeze()
