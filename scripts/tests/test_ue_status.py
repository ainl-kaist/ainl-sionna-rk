"""Regression checks for identity-based UE IP matching."""
import importlib.util
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


if __name__ == '__main__':
    unittest.main()
