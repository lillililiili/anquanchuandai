import importlib.util,unittest
from pathlib import Path
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('release',Path(__file__).with_name('database_release.py'))
release=importlib.util.module_from_spec(spec);spec.loader.exec_module(release)

def info(role='staging',project=None):
    return {'Config':{'Labels':{'com.docker.compose.project':project or release.PROJECTS[role],'com.docker.compose.service':'mysql','com.wearables.deployment-role':role}}}

class ReleaseGuardTest(unittest.TestCase):
    def test_rejects_daily_legacy_or_arbitrary_mysql_before_any_write(self):
        for project in ('local-dev','fuda-wearables','another-project'):
            with self.subTest(project=project),patch.object(release,'identity',return_value=info(project=project)),patch.object(release,'mysql') as mysql:
                with self.assertRaises(ValueError):release.target_guard('mysql-target')
                mysql.assert_not_called()
    def test_rejects_populated_target_for_both_roles(self):
        for role in release.PROJECTS:
            with self.subTest(role=role),patch.object(release,'identity',return_value=info(role)),patch.object(release,'run',return_value=b''),patch.object(release,'mysql',return_value=b'1'):
                with self.assertRaisesRegex(ValueError,'not empty'):release.target_guard('mysql-target',role)
    def test_rejects_running_target_backend_for_both_roles(self):
        for role in release.PROJECTS:
            with self.subTest(role=role),patch.object(release,'identity',return_value=info(role)),patch.object(release,'run',return_value=b'backend-id'),patch.object(release,'mysql') as mysql:
                with self.assertRaisesRegex(ValueError,'Stop'):release.target_guard('mysql-target',role)
                mysql.assert_not_called()
    def test_empty_stopped_targets_use_their_own_project_filter(self):
        for role,project in release.PROJECTS.items():
            with self.subTest(role=role),patch.object(release,'identity',return_value=info(role)),patch.object(release,'run',return_value=b'') as run,patch.object(release,'mysql',return_value=b'0'):
                release.target_guard('mysql-target',role)
                self.assertIn('label=com.docker.compose.project='+project,run.call_args.args[0])
    def test_role_mismatch_and_production_without_explicit_role_rejected(self):
        with patch.object(release,'identity',return_value=info('production')),patch.object(release,'mysql') as mysql:
            with self.assertRaises(ValueError):release.target_guard('production-mysql')
            mysql.assert_not_called()
        broken=info('production');broken['Config']['Labels']['com.wearables.deployment-role']='staging'
        with patch.object(release,'identity',return_value=broken):
            with self.assertRaises(ValueError):release.target_guard('production-mysql','production')
    def test_unknown_role_and_unsafe_container_names_rejected(self):
        with self.assertRaises(ValueError):release.target_guard('mysql','unknown')
        for bad in ['--all','$(pwd)','mysql; rm','x/y']:
            with self.assertRaises(ValueError):release.identity(bad)
if __name__=='__main__':unittest.main()
