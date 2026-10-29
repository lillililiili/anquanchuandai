"""Replace an already migrated backend with a compatible image; never rerun data cleanup."""
import argparse
import importlib.util
import pathlib
import sys

spec = importlib.util.spec_from_file_location('release', pathlib.Path(__file__).with_name('wearable-business-release.py'))
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)


def patch(folder, image, token_file):
    folder = r.safe_folder(folder)
    receipt = r.read_json(folder / 'release.json')
    if receipt['status'] != 'released':
        raise RuntimeError('Complete the original release before a compatible patch')
    live, target = r.inspect(r.LIVE), r.inspect(image)
    if not live['State']['Running'] or live['Image'] != receipt['newImageId']:
        raise RuntimeError('Daily backend differs from the recorded SQL release')
    if live['Image'] == target['Id']:
        return {'status': 'already-current', 'imageId': target['Id']}
    token = r.admin_token(token_file)
    if r.maintenance(token)['mode'] != 'ACTIVE':
        raise RuntimeError('Resolve maintenance before replacing a running backend')
    if not r.business_initialized():
        raise RuntimeError('The current backend is not using initialized SQL business storage')
    key = r.read_json(folder / 'baseline/business-keys.private.json')['MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY']
    env = dict(value.split('=', 1) for value in live['Config']['Env'] if '=' in value)
    if env.get('MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY') != key:
        raise RuntimeError('Current encryption key differs from the retained recovery key')
    stamp = r.dt.datetime.now(r.dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ').lower()
    directory = folder / ('compatible-patch-' + stamp)
    directory.mkdir()
    old_name, failed_name = 'melhat-before-patch-' + stamp, 'melhat-failed-patch-' + stamp
    result = {'startedAt': r.now(), 'status': 'preparing', 'oldImageId': live['Image'], 'imageId': target['Id'],
              'oldContainerId': live['Id'], 'retainedContainer': old_name, 'cleanupPerformed': False}
    r.write_json(directory / 'previous-container.private.json', live)
    r.write_json(directory / 'result.json', result)
    renamed = started = False
    r.run('stop', '--time', '30', r.LIVE)
    try:
        (directory / 'database.sql').write_bytes(r.dump())
        r.copy_current_state(r.LIVE, directory / 'compatibility-files')
        exported = r.business_cli(live['Image'], live, key, directory / 'current-sql-export', 'Export', require_drained=False)
        if not exported.get('guardianInitialized') or not exported.get('mediaInitialized'):
            raise RuntimeError('Both business namespaces must be initialized before patching')
        r.run('rename', r.LIVE, old_name)
        renamed = True
        r.run(*r.recreate_args(live, target['Id'], key))
        started = True
        r.healthy(18084)
        status = r.maintenance(token)
        if status['mode'] != 'ACTIVE':
            raise RuntimeError('Compatible image did not retain ACTIVE maintenance state')
        r.wait_replayed(exported['reportWatermark'])
        result.update(status='patched', completedAt=r.now(), reportWatermark=exported['reportWatermark'],
                      currentContainerId=r.inspect(r.LIVE)['Id'])
        receipt.update(newImageId=target['Id'], newContainerId=result['currentContainerId'], compatiblePatch=directory.name)
        r.write_json(folder / 'release.json', receipt)
    except Exception:
        # Both images use the same current SQL schema/key. No earlier dump or JSON is imported.
        if started:
            r.run('stop', '--time', '30', r.LIVE)
            r.run('rename', r.LIVE, failed_name)
        if renamed:
            r.run('rename', old_name, r.LIVE)
        r.run('start', r.LIVE)
        r.healthy(18084)
        result.update(status='compatible-predecessor-restored', completedAt=r.now())
        r.write_json(directory / 'result.json', result)
        raise RuntimeError('Patch failed; the prior SQL-compatible backend is running against all current data') from None
    r.write_json(directory / 'result.json', result)
    return result


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('folder')
    parser.add_argument('--image', required=True)
    parser.add_argument('--admin-token-file', required=True)
    args = parser.parse_args()
    try:
        print(r.encode(patch(args.folder, args.image, args.admin_token_file)))
    except (RuntimeError, ValueError, OSError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
