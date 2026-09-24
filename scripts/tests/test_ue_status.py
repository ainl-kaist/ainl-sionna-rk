"""Regression checks for identity-based UE IP matching."""
import importlib.util
import io
from contextlib import redirect_stdout
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('ue_status', Path(__file__).parents[1] / 'ue_status.py')
status = importlib.util.module_from_spec(spec)
spec.loader.exec_module(status)


def amf_table(rows, gnbs=1):
    return "\n".join([
        "|gNBs' Information|", '|  Index | Status | Global Id | Name | PLMN |',
        *[f'| {i} | Connected | 0xe00 | gnb | 262,99 |' for i in range(gnbs)],
        '|-----|', "|UEs' Information|", '|  Index | 5GMM State | IMSI | GUTI | RAN | AMF | PLMN | Cell |',
        *[f'| {i} | 5GMM-REGISTERED | {imsi} | guti | {ran} | 0x15 | 262,99 | cell |'
          for i, (imsi, ran) in enumerate(rows)], '|-----|'])


def smf_context(imsi, ip=None):
    lines = ['SMF CONTEXT:', f'SUPI: imsi-{imsi}', 'PDU SESSION:']
    if ip:
        lines.append(f' PAA IPv4: {ip}')
    lines.append('[2026-09-24 09:00:00.000] [smf_app] [debug] end')
    return '\n'.join('2026-09-24T07:00:00Z ' + line for line in lines) + '\n'


class CoreLookupTests(unittest.TestCase):
    def test_multiple_ues_join_by_identity_not_order(self):
        amf = amf_table([('222', '0x02'), ('111', '0x01')])
        smf = smf_context('111', '12.1.1.2') + smf_context('222', '12.1.1.3')
        data = {'ues': [{'cu_ue_id': 1}, {'cu_ue_id': 2}, {'cu_ue_id': 3}]}
        with patch.object(status, 'docker', side_effect=[amf, smf]):
            status.add_core_info(data, 'amf', 'smf')
        self.assertEqual([ue['ue_ip'] for ue in data['ues']], ['12.1.1.2', '12.1.1.3', None])

    def test_release_clears_previous_allocation(self):
        log = smf_context('111', '12.1.1.2') + smf_context('111')
        self.assertEqual(status.parse_smf(log)['111']['addresses'], [])

    def test_latest_amf_table_replaces_old_rows(self):
        log = amf_table([('111', '0x01')]) + '\n' + amf_table([])
        self.assertEqual(status.parse_amf(log), {})

    def test_ambiguous_id_and_multiple_gnbs(self):
        self.assertIsNone(status.parse_amf(amf_table([('111', '0x01'), ('222', '0x01')]))[1])
        with self.assertRaises(RuntimeError):
            status.parse_amf(amf_table([], gnbs=2))

    def test_unavailable_core_keeps_radio_data(self):
        data = {'ues': [{'cu_ue_id': 1, 'rnti': 'abcd'}]}
        with patch.object(status, 'docker', side_effect=RuntimeError('unavailable')):
            status.add_core_info(data, 'amf', 'smf')
        self.assertEqual(data['ues'][0]['rnti'], 'abcd')
        self.assertIsNone(data['ues'][0]['ue_ip'])
        self.assertIn('warnings', data)

    def test_incomplete_and_invalid_context(self):
        self.assertEqual(status.parse_smf('2026-09-24T07:00:00Z SMF CONTEXT:\n'), {})
        self.assertEqual(status.parse_smf(smf_context('111', '999.1.1.1'))['111']['addresses'], [])


class ConnectivityTests(unittest.TestCase):
    def test_reply_no_reply_and_execution_error_are_distinct(self):
        for code, output, expected in (
            (0, '64 bytes: time=12.3 ms', 'reachable'),
            (1, '100% packet loss', 'no-reply'),
            (2, 'ping: operation not permitted', 'error'),
        ):
            with self.subTest(code=code):
                data = {'ues': [{'ue_ip': '12.1.1.3'}]}
                response = status.subprocess.CompletedProcess([], code, output)
                with patch.object(status.subprocess, 'run', return_value=response) as run:
                    status.check_connectivity(data, 'oai-ext-dn')
                probe = data['ues'][0]['connectivity'][0]
                self.assertEqual(probe['status'], expected)
                self.assertEqual(run.call_args.args[0],
                                 ['docker', 'exec', 'oai-ext-dn', 'ping', '-n', '-c', '3', '-W', '1', '12.1.1.3'])
                self.assertEqual(probe['output'], output)

    def test_full_ping_output_is_displayed(self):
        output = ('PING 12.1.1.3 (12.1.1.3) 56(84) bytes of data.\n'
                  '64 bytes from 12.1.1.3: icmp_seq=1 ttl=63 time=24.4 ms\n\n'
                  '--- 12.1.1.3 ping statistics ---\n'
                  '3 packets transmitted, 1 received, 66.6667% packet loss\n'
                  'rtt min/avg/max/mdev = 24.4/24.4/24.4/0.0 ms')
        data = {'checked_at': '2026-09-24T10:00:00Z', 'container': 'gnb',
                'window_seconds': 10, 'ues': [{'rnti': 'abcd', 'ue_ip': '12.1.1.3',
                                             'last_seen': '2026-09-24T10:00:00Z'}]}
        with patch.object(status.subprocess, 'run', return_value=
                          status.subprocess.CompletedProcess([], 0, output)):
            status.check_connectivity(data, 'source')
        rendered = io.StringIO()
        with redirect_stdout(rendered):
            status.display(data)
        for line in output.splitlines():
            self.assertIn(line, rendered.getvalue())
        self.assertIn('REACHABLE', rendered.getvalue())

    def test_disabled_or_missing_ip_never_runs_ping(self):
        for ip, enabled in [('12.1.1.3', False), (None, True)]:
            data = {'ues': [{'ue_ip': ip}]}
            with patch.object(status.subprocess, 'run') as run:
                status.check_connectivity(data, 'source', enabled)
            run.assert_not_called()
            self.assertEqual(data['ues'][0]['connectivity'][0]['status'], 'skipped')

    def test_timeout_does_not_prevent_next_address_probe(self):
        data = {'ues': [{'ue_ip': '12.1.1.3,2001:db8::3'}]}
        with patch.object(status.subprocess, 'run', side_effect=[
            status.subprocess.TimeoutExpired('docker', 5),
            status.subprocess.CompletedProcess([], 0, 'time<1 ms'),
        ]):
            status.check_connectivity(data, 'source')
        self.assertEqual([p['status'] for p in data['ues'][0]['connectivity']],
                         ['error', 'reachable'])

    def test_invalid_address_is_not_executed(self):
        data = {'ues': [{'ue_ip': '-bad-input'}]}
        with patch.object(status.subprocess, 'run') as run:
            status.check_connectivity(data, 'source')
        run.assert_not_called()
        self.assertEqual(data['ues'][0]['connectivity'][0]['status'], 'error')


if __name__ == '__main__':
    unittest.main()
