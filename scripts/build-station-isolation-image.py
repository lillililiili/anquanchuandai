"""Build the reviewed station-isolation JAR on its unchanged local baseline image.

Only inspect, JAR hashing, image tagging and an offline Docker build are performed.
The daily container is never created, stopped, restarted or reconfigured.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import tempfile
import unittest
from unittest.mock import patch as mock_patch

ROOT = Path(__file__).resolve().parents[1]
BACKEND = ROOT / '后端代码/melhat_server-dev'
spec = importlib.util.spec_from_file_location('container_patch', BACKEND / 'local-dev/wearable-container-patch.py')
patch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patch)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require_baseline(manifest):
    expected = manifest.get('live')
    if not expected or not expected.get('containerId') or not re.fullmatch(r'sha256:[a-f0-9]{64}', expected.get('imageId', '')):
        raise RuntimeError('Candidate must record its live container and image identity')
    live = patch.inspect('melhat-backend')
    if not live['State']['Running'] or live['Id'] != expected['containerId'] or live['Image'] != expected['imageId']:
        raise RuntimeError('Daily backend identity changed; rebase the candidate first')
    running = patch.docker('exec', 'melhat-backend', 'sha256sum', '/app/fdc-admin.jar').decode().split()[0]
    if running != manifest['baselineJarSha256']:
        raise RuntimeError('Daily JAR changed; rebase the candidate first')
    return live


def build(directory):
    directory = Path(directory).resolve()
    if not any(directory.is_relative_to(parent.resolve()) and directory != parent.resolve()
               for parent in (ROOT / 'output', BACKEND / 'build')):
        raise RuntimeError('Candidate directory must be below workspace output or backend/build')
    manifest = patch.read_json(directory / 'release.json')
    jar = directory / 'fdc-admin.jar'
    if manifest.get('state') != 'candidate-only-not-deployed' or manifest.get('unchangedNonTaskEntriesVerified') is not True:
        raise RuntimeError('A verified, undeployed allowlisted candidate is required')
    if not re.fullmatch(r'[a-f0-9]{64}', manifest.get('jarSha256', '')) or sha(jar) != manifest['jarSha256']:
        raise RuntimeError('Candidate JAR differs from its reviewed hash')
    if sha(directory / 'baseline-fdc-admin.jar') != manifest['baselineJarSha256']:
        raise RuntimeError('Recorded baseline JAR hash does not match')
    live = require_baseline(manifest)
    image = 'melhat-backend:station-isolation-' + manifest['jarSha256'][:16]
    base = image + '-base'
    # A fixed local tag avoids registry resolution of a bare image digest in FROM.
    patch.docker('tag', live['Image'], base)
    (directory / 'Dockerfile').write_text('FROM ' + base + '\nCOPY fdc-admin.jar /app/fdc-admin.jar\n', encoding='utf-8')
    (directory / '.dockerignore').write_text('*\n!fdc-admin.jar\n!Dockerfile\n', encoding='utf-8')
    with (directory / 'image-build.log').open('wb') as output:
        patch.docker('build', '--network', 'none', '--pull=false', '-t', image, str(directory), output=output, timeout=300)
    candidate = patch.inspect(image)
    if candidate['Config']['Entrypoint'] != live['Config']['Entrypoint']:
        raise RuntimeError('Candidate image changed the baseline entrypoint')
    if sha(jar) != manifest['jarSha256']:
        raise RuntimeError('Candidate JAR changed during image build')
    require_baseline(manifest)
    manifest.update(image=image, candidateImageId=candidate['Id'], containerBuildPerformed=True,
                    imageBuiltAtUtc=patch.now(), dailyContainerUnchanged=True)
    patch.write_json(directory / 'release.json', manifest)
    return dict(image=image, candidateImageId=candidate['Id'], jarSha256=manifest['jarSha256'], dailyContainerChanged=False)


class ImageBuildTests(unittest.TestCase):
    def fixture(self, root):
        directory = root / 'output/candidate'
        directory.mkdir(parents=True)
        (directory / 'fdc-admin.jar').write_bytes(b'candidate')
        (directory / 'baseline-fdc-admin.jar').write_bytes(b'baseline')
        manifest = dict(state='candidate-only-not-deployed', unchangedNonTaskEntriesVerified=True,
                        live=dict(containerId='container-original', imageId='sha256:' + 'a' * 64),
                        jarSha256=sha(directory / 'fdc-admin.jar'), baselineJarSha256=sha(directory / 'baseline-fdc-admin.jar'))
        patch.write_json(directory / 'release.json', manifest)
        live = dict(Id='container-original', Image=manifest['live']['imageId'], State=dict(Running=True), Config=dict(Entrypoint=['java']))
        return directory, manifest, live

    def test_only_baseline_tag_and_offline_build_with_exact_copy(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); directory, manifest, live = self.fixture(root)
            with mock_patch(__name__ + '.ROOT', root), mock_patch(__name__ + '.BACKEND', root / 'backend'), \
                 mock_patch.object(patch, 'inspect', side_effect=[live, dict(Id='candidate-image', Config=live['Config']), live]), \
                 mock_patch.object(patch, 'docker', return_value=(manifest['baselineJarSha256'] + '  /app/fdc-admin.jar').encode()) as docker:
                result = build(directory)
            calls = [call.args for call in docker.call_args_list]
            self.assertEqual([call[0] for call in calls], ['exec', 'tag', 'build', 'exec'])
            self.assertEqual(calls[1][1], live['Image'])
            self.assertEqual(calls[2][1:4], ('--network', 'none', '--pull=false'))
            self.assertEqual((directory / 'Dockerfile').read_text(), 'FROM ' + result['image'] + '-base\nCOPY fdc-admin.jar /app/fdc-admin.jar\n')
            self.assertEqual((directory / '.dockerignore').read_text(), '*\n!fdc-admin.jar\n!Dockerfile\n')
            self.assertEqual(patch.read_json(directory / 'release.json')['candidateImageId'], 'candidate-image')

    def test_changed_daily_identity_fails_before_mutation(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); directory, _, live = self.fixture(root)
            live['Id'] = 'changed'
            with mock_patch(__name__ + '.ROOT', root), mock_patch(__name__ + '.BACKEND', root / 'backend'), \
                 mock_patch.object(patch, 'inspect', return_value=live), mock_patch.object(patch, 'docker') as docker:
                with self.assertRaisesRegex(RuntimeError, 'identity changed'):
                    build(directory)
                docker.assert_not_called()

    def test_changed_candidate_fails_before_docker(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); directory, _, _ = self.fixture(root)
            (directory / 'fdc-admin.jar').write_bytes(b'changed')
            with mock_patch(__name__ + '.ROOT', root), mock_patch(__name__ + '.BACKEND', root / 'backend'), \
                 mock_patch.object(patch, 'inspect') as inspect, mock_patch.object(patch, 'docker') as docker:
                with self.assertRaisesRegex(RuntimeError, 'reviewed hash'):
                    build(directory)
                inspect.assert_not_called(); docker.assert_not_called()

    def test_live_jar_drift_fails_before_tag(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); directory, _, live = self.fixture(root)
            with mock_patch(__name__ + '.ROOT', root), mock_patch(__name__ + '.BACKEND', root / 'backend'), \
                 mock_patch.object(patch, 'inspect', return_value=live), mock_patch.object(patch, 'docker', return_value=b'changed  /app/fdc-admin.jar') as docker:
                with self.assertRaisesRegex(RuntimeError, 'Daily JAR changed'):
                    build(directory)
                self.assertEqual([call.args[0] for call in docker.call_args_list], ['exec'])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory')
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        unittest.main(argv=['build-station-isolation-image'], exit=True)
    elif args.directory:
        print(json.dumps(build(args.directory)))
    else:
        parser.error('--directory or --self-test is required')
