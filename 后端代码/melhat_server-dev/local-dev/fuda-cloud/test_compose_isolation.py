"""Compose config is a parser-only operation: these tests never contact a Docker daemon or start containers."""
import json,os,subprocess,unittest
from pathlib import Path
HERE=Path(__file__).resolve().parent

def config(production=False):
    args=['docker','compose','--env-file','.env.example','-f','compose.yml']
    if production:args+=['-f','compose.production.yml','--profile','production-device-cutover']
    args+=['config','--no-env-resolution','--format','json']
    env=dict(os.environ)
    for key in ('COMPOSE_PROJECT_NAME','COMPOSE_FILE','COMPOSE_PROFILES'):env.pop(key,None)
    result=subprocess.run(args,cwd=HERE,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=True)
    return json.loads(result.stdout)

class ComposeIsolationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.stage=config();cls.prod=config(True)
    def test_staging_backend_has_no_egress_or_published_port(self):
        b=self.stage['services']['backend'];self.assertEqual({'private'},set(b['networks']));self.assertFalse(b.get('ports'))
        self.assertTrue(self.stage['networks']['private']['internal']);self.assertNotIn('egress',self.stage['networks'])
        for flag in ('--melhat.direct.enabled=false','--melhat.belt.enabled=false','--melhat.helmet-media.enabled=false','--fuda.gb.internal-enabled=false'):
            self.assertIn(flag,b['command'])
        runtime=next(v for v in b['volumes'] if v['target']=='/run/secrets/device-runtime.yml')
        self.assertEqual('safe-runtime.yml',Path(runtime['source']).name);self.assertTrue(runtime['read_only'])
        self.assertFalse({'helmet-gateway','belt-gateway','phone-gateway','private-relays'}&set(self.stage['services']))
    def test_projects_networks_and_all_data_volumes_are_distinct(self):
        self.assertEqual('fuda-wearables-staging',self.stage['name']);self.assertEqual('fuda-wearables-production',self.prod['name'])
        for name in ('mysql-data','redis-data','backend-data'):self.assertNotEqual(self.stage['volumes'][name]['name'],self.prod['volumes'][name]['name'])
        self.assertNotEqual(self.stage['networks']['private']['name'],self.prod['networks']['private']['name'])
    def test_production_is_explicit_and_uses_correct_backend_and_query_ports(self):
        b=self.prod['services']['backend'];self.assertEqual({'private','egress'},set(b['networks']));self.assertEqual([],b['command'])
        self.assertEqual([('127.0.0.1','18084',18084)],[(p['host_ip'],p['published'],p['target']) for p in b['ports']])
        q=self.prod['services']['query-gateway'];self.assertEqual([('10.255.1.1','28089',8080)],[(p['host_ip'],p['published'],p['target']) for p in q['ports']])
        runtime=next(v for v in b['volumes'] if v['target']=='/run/secrets/device-runtime.yml');self.assertIn('/production/',runtime['source'].replace('\\','/'))
        self.assertIn('private-relays',self.prod['services'])
    def test_only_query_gateway_spans_private_and_frontend(self):
        for cfg in (self.stage,self.prod):
            self.assertEqual({'private','frontend'},set(cfg['services']['query-gateway']['networks']))
            for service in ('mysql','redis'):self.assertEqual({'private'},set(cfg['services'][service]['networks']));self.assertFalse(cfg['services'][service].get('ports'))
            self.assertFalse(cfg['networks']['frontend'].get('internal',False))
if __name__=='__main__':unittest.main()
