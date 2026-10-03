"""WWAN diagnostics without changing interfaces or sending packets."""
import importlib.util
import io
import json
from contextlib import redirect_stdout
from pathlib import Path
import subprocess
import sys
import tempfile
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


class VersionTests(unittest.TestCase):
    def test_source_reports_dev(self):
        out = io.StringIO()
        with patch.object(sys, 'argv', ['ue-wwan-status', '--version']), redirect_stdout(out), \
                self.assertRaises(SystemExit) as exit_:
            wwan.main()
        self.assertEqual(exit_.exception.code, 0)
        self.assertEqual(out.getvalue(), 'ue-wwan-status dev\n')

    def test_installer_stamps_git_describe(self):
        scripts = Path(__file__).parents[1]
        expected = subprocess.run(['git', '-C', str(scripts), 'describe', '--always', '--dirty'],
                                  capture_output=True, text=True).stdout.strip() or 'unknown'
        with tempfile.TemporaryDirectory() as prefix:
            subprocess.run([str(scripts / 'install-ue-wwan-status.sh'), '--prefix', prefix],
                           check=True, capture_output=True)
            installed = Path(prefix) / 'bin' / 'ue-wwan-status'
            self.assertEqual(installed.stat().st_mode & 0o777, 0o755)
            result = subprocess.run([sys.executable, str(installed), '--version'],
                                    check=True, capture_output=True, text=True)
        self.assertEqual(result.stdout, f'ue-wwan-status {expected}\n')
        self.assertIn("__version__ = 'dev'", (scripts / 'ue_wwan_status.py').read_text())


if __name__ == '__main__':
    unittest.main()
