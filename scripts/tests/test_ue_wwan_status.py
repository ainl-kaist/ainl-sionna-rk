"""WWAN diagnostics without changing interfaces or sending packets."""
import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('wwan', Path(__file__).parents[1] / 'ue_wwan_status.py')
wwan = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wwan)


def address(flags=None, addresses=None):
    return json.dumps([{'flags': flags if flags is not None else ['UP'], 'operstate': 'UNKNOWN',
                        'addr_info': addresses if addresses is not None else [
                            {'local': '12.1.1.3', 'prefixlen': 24, 'scope': 'global'}]}])


class WwanTests(unittest.TestCase):
    def test_missing_interface(self):
        with patch.object(wwan, 'run', side_effect=RuntimeError('Device missing')):
            self.assertFalse(wwan.inspect('wwan0')['ok'])

    def test_unknown_operstate_and_no_default_can_be_valid(self):
        with patch.object(wwan, 'run', side_effect=[address(), '[]', '[]']):
            data = wwan.inspect('wwan0')
        self.assertTrue(data['ok'])
        self.assertEqual(data['checks'][-1]['status'], 'SKIP')

    def test_down_or_missing_address(self):
        for value in (address(flags=[]), address(addresses=[]), address(addresses=[
                {'local': '2001:db8::1', 'prefixlen': 64, 'scope': 'global', 'tentative': True}])):
            with patch.object(wwan, 'run', side_effect=[value, '[]', '[]']):
                self.assertFalse(wwan.inspect('wwan0')['ok'])

    def test_wrong_default_path_is_reported_even_when_bound_ping_succeeds(self):
        with patch.object(wwan.shutil, 'which', return_value='/usr/bin/ping'), patch.object(
                wwan, 'run', side_effect=[address(), '[]', '[]', '[{"dev":"eth0"}]', '3 received']) as run:
            data = wwan.inspect('wwan0', '192.168.72.135')
        self.assertFalse(data['ok'])
        self.assertIn('-I', run.call_args.args[0])
        self.assertIn('wwan0', run.call_args.args[0])
        self.assertEqual(data['checks'][-1]['status'], 'PASS')

    def test_ping_failure_is_reported(self):
        with patch.object(wwan.shutil, 'which', return_value='/usr/bin/ping'), patch.object(
                wwan, 'run', side_effect=[address(), '[]', '[]', '[{"dev":"wwan0"}]', RuntimeError('packet loss')]):
            data = wwan.inspect('wwan0', '192.168.72.135')
        self.assertFalse(data['ok'])
        self.assertIn('does not prove', data['checks'][-1]['detail'])


if __name__ == '__main__':
    unittest.main()
