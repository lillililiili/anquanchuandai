import importlib.util,unittest,errno
from pathlib import Path
from unittest.mock import patch,MagicMock
spec=importlib.util.spec_from_file_location('preflight',Path(__file__).with_name('preflight.py'))
p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
class PreflightTest(unittest.TestCase):
    def test_staging_checks_only_its_gateway_and_never_daily_ports(self):
        self.assertEqual([('127.0.0.1',18089)],p.endpoints(False))
    def test_production_checks_all_eight_real_listener_endpoints(self):
        self.assertEqual({18084,18086,18087,18088,28086,28087,28088,28089},{port for host,port in p.endpoints(True)})
        self.assertEqual({p.BRIDGE},{host for host,port in p.endpoints(True) if port>=28000})
    def test_bridge_requires_the_exact_host_address(self):
        with patch.object(p.subprocess,'run',return_value=MagicMock(stdout=b'[{"addr_info":[{"local":"10.255.1.1"}]}]')):self.assertTrue(p.bridge_present())
        with patch.object(p.subprocess,'run',return_value=MagicMock(stdout=b'[{"addr_info":[{"local":"10.255.1.2"}]}]')):self.assertFalse(p.bridge_present())
        with patch.object(p.subprocess,'run',side_effect=OSError()):self.assertFalse(p.bridge_present())
    def test_address_missing_and_occupied_ports_are_distinguished(self):
        with patch.object(p.socket,'socket') as factory:
            sock=factory.return_value.__enter__.return_value
            sock.bind.side_effect=OSError(errno.EADDRINUSE,'busy');self.assertEqual('occupied',p.probe('127.0.0.1',1)['status'])
            sock.bind.side_effect=OSError(errno.EADDRNOTAVAIL,'missing');self.assertEqual('unavailable',p.probe(p.BRIDGE,1)['status'])
            sock.bind.side_effect=None;self.assertEqual('free',p.probe('127.0.0.1',1)['status'])
if __name__=='__main__':unittest.main()
