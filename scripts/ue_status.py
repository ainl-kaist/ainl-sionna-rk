#!/usr/bin/env python3
"""Show recently observed OAI UE MAC statistics using read-only Docker logs."""
import argparse
from datetime import datetime, timezone
import json
import ipaddress
import math
import re
import subprocess
import sys
import time

ANSI = re.compile(r'\x1b\[[0-9;]*m')
HEADER = re.compile(r'UE RNTI ([0-9a-fA-F]+) CU-UE-ID (\d+) (\S+)')
DETAIL = re.compile(r'UE ([0-9a-fA-F]+): (.*)')


def parse_logs(log):
    """Keep each UE's newest block; never mix metrics across blocks."""
    ues = {}
    for raw in log.splitlines():
        line = ANSI.sub('', raw)
        timestamp, _, body = line.partition(' ')
        match = HEADER.search(body)
        if match:
            rnti, cu_id, sync = match.groups()
            ue = {'rnti': rnti.lower(), 'cu_ue_id': int(cu_id),
                  'sync': sync, 'last_seen': timestamp}
            for key, pattern in (
                ('rsrp_dbm', r'average RSRP (-?[\d.]+)'),
                ('ph_db', r'PH (-?[\d.]+) dB'),
                ('pcmax_dbm', r'PCMAX (-?[\d.]+) dBm'),
            ):
                value = re.search(pattern, body)
                if value:
                    ue[key] = float(value[1])
            ues[ue['rnti']] = ue
            continue
        match = DETAIL.search(body)
        if not match or match[1].lower() not in ues:
            continue
        ue = ues[match[1].lower()]
        detail = match[2]
        for direction, label in (('dl', 'dlsch'), ('ul', 'ulsch')):
            if detail.startswith(label + '_rounds'):
                for key, pattern, convert in (
                    ('bler', r'BLER ([\d.eE+-]+)', float),
                    ('mcs', r'MCS \(\d+\) (\d+)', int),
                    ('errors', label + r'_errors (\d+)', int),
                    ('rounds', label + r'_rounds ([\d/]+)', str),
                    ('snr_db', r'SNR (-?[\d.]+) dB', float),
                ):
                    value = re.search(pattern, detail)
                    if value:
                        ue[direction + '_' + key] = convert(value[1])
        match = re.search(r'MAC:\s+TX\s+(\d+) RX\s+(\d+) bytes', detail)
        if match:
            ue['mac_tx_bytes'], ue['mac_rx_bytes'] = map(int, match.groups())
    return sorted(ues.values(), key=lambda ue: ue['rnti'])


def docker(*args):
    result = subprocess.run(['docker', *args], stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, timeout=15)
    if result.returncode:
        raise RuntimeError(result.stdout.strip())
    return result.stdout


def parse_amf(log):
    """Read the latest complete AMF tables, with single-gNB scoping."""
    tables = {}
    kind = None
    rows = None
    for raw in log.splitlines():
        line = ANSI.sub('', raw)
        if "gNBs' Information" in line:
            kind, rows = 'gnbs', None
        elif "UEs' Information" in line:
            kind, rows = 'ues', None
        elif '|  Index' in line:
            rows = []
        elif kind and rows is not None and re.search(r'\|-+\|', line):
            tables[kind] = rows
            kind, rows = None, None
        elif kind and rows is not None and '|' in line:
            fields = [field.strip() for field in line.split('|')[1:-1]]
            if fields and fields[0].isdigit():
                rows.append(fields)
    gnbs = tables.get('gnbs', [])
    if len(gnbs) != 1 or gnbs[0][1] != 'Connected':
        raise RuntimeError('IP matching requires one connected gNB in the latest AMF table.')
    if 'ues' not in tables:
        raise RuntimeError('No complete recent AMF UE table found.')
    result = {}
    for row in tables['ues']:
        if len(row) != 8 or row[1] != '5GMM-REGISTERED':
            continue
        try:
            ran_id = int(row[4], 0)
        except ValueError:
            continue
        record = {'imsi': row[2], 'amf_ue_ngap_id': row[5]}
        # A duplicate RAN ID is ambiguous; do not guess which UE owns the IP.
        result[ran_id] = None if ran_id in result else record
    return result


def parse_smf(log):
    """Read explicit SUPI/PAA pairs from complete SMF context dumps only."""
    result = {}
    block = None
    for raw in log.splitlines():
        timestamp, _, body = ANSI.sub('', raw).partition(' ')
        if body.strip() == 'SMF CONTEXT:':
            block = {'last_seen': timestamp, 'addresses': []}
            continue
        if block is None:
            continue
        if re.match(r'\[\d{4}-\d{2}-\d{2} ', body):
            if 'imsi' in block:
                result[block['imsi']] = block
            block = None
            continue
        match = re.match(r'\s*SUPI:\s*imsi-(\d+)', body)
        if match:
            block['imsi'] = match[1]
        match = re.match(r'\s*PAA IPv[46]:\s*(\S+)', body)
        if match:
            try:
                address = str(ipaddress.ip_address(match[1]))
            except ValueError:
                continue
            if address not in block['addresses']:
                block['addresses'].append(address)
    return result


def add_core_info(data, amf, smf):
    for ue in data['ues']:
        ue['imsi'] = None
        ue['ue_ip'] = None
        ue['ip_source'] = None
        ue['ip_last_seen'] = None
    if not data['ues']:
        return
    try:
        identities = parse_amf(docker('logs', '--timestamps', '--since', '60s', amf))
        # Assignments can predate the radio observation window by hours.
        # Re-read retained context dumps so releases and SMF restarts clear old IPs.
        sessions = parse_smf(docker('logs', '--timestamps', smf))
        for ue in data['ues']:
            identity = identities.get(ue['cu_ue_id'])
            if not identity:
                continue
            ue.update(identity)
            session = sessions.get(identity['imsi'])
            if session and session['addresses']:
                ue['ue_ip'] = ','.join(session['addresses'])
                ue['ip_source'] = f'{smf}: SMF context log via {amf} RAN UE NGAP ID/IMSI'
                ue['ip_last_seen'] = session['last_seen']
    except (OSError, subprocess.TimeoutExpired, RuntimeError) as error:
        data.setdefault('warnings', []).append(f'Core IP lookup unavailable: {error}')


def snapshot(container, window, amf='oai-amf', smf='oai-smf'):
    if docker('inspect', '-f', '{{.State.Running}}', container).strip() != 'true':
        raise RuntimeError(f'Container {container} is not running.')
    log = docker('logs', '--timestamps', '--since', f'{window}s', container)
    data = {'container': container, 'checked_at': datetime.now(timezone.utc).isoformat(),
            'window_seconds': window, 'ues': parse_logs(log)}
    add_core_info(data, amf, smf)
    return data


def display(data):
    print(f"[{data['checked_at']}] {data['container']} | UEs observed in the last {data['window_seconds']}s: {len(data['ues'])}")
    print('Log-based observations. Disconnected UEs disappear after the observation window expires.')
    for warning in data.get('warnings', []):
        print(f'Warning: {warning}')
    if not data['ues']:
        print('No recent UE statistics. Check UE connectivity and whether MAC statistics logging is enabled.')
        return
    columns = [('RNTI', 'rnti'), ('CU-ID', 'cu_ue_id'), ('IMSI', 'imsi'),
               ('UE-IP', 'ue_ip'), ('SYNC', 'sync'),
               ('RSRP(dBm)', 'rsrp_dbm'), ('UL-SNR(dB)', 'ul_snr_db'),
               ('DL-MCS', 'dl_mcs'), ('UL-MCS', 'ul_mcs'),
               ('DL-BLER', 'dl_bler'), ('UL-BLER', 'ul_bler'),
               ('TX(bytes)', 'mac_tx_bytes'), ('RX(bytes)', 'mac_rx_bytes')]
    rows = [[str(ue[key]) if ue.get(key) is not None else '-' for _, key in columns] for ue in data['ues']]
    widths = [max(len(name), *(len(row[i]) for row in rows)) for i, (name, _) in enumerate(columns)]
    for row in [[name for name, _ in columns], *rows]:
        print('  '.join(value.ljust(width) for value, width in zip(row, widths)))
    print('TX/RX: cumulative bytes at the gNB; BLER: reported value; -: unavailable in the latest block.')
    print('UE-IP: last recorded SMF allocation matched through AMF; -: unavailable or unmatched.')
    for ue in data['ues']:
        if ue.get('ip_last_seen'):
            print(f"  {ue['rnti']} IP allocation last seen: {ue['ip_last_seen']}")
        print(f"  {ue['rnti']} last seen: {ue['last_seen']}")


def positive(value):
    number = float(value)
    if not math.isfinite(number) or number <= 0:
        raise argparse.ArgumentTypeError('Enter a positive finite number.')
    return number


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('-c', '--container', default='oai-gnb', help='Container name (default: oai-gnb)')
    parser.add_argument('--window', type=positive, default=10, help='Recent log window in seconds (default: 10)')
    parser.add_argument('-w', '--watch', action='store_true', help='Refresh periodically (Ctrl+C to exit)')
    parser.add_argument('--interval', type=positive, default=2, help='Refresh interval in seconds (default: 2)')
    parser.add_argument('--json', action='store_true', help='Output JSON; watch mode emits one snapshot per line')
    parser.add_argument('--amf', default='oai-amf', help='AMF container (default: oai-amf)')
    parser.add_argument('--smf', default='oai-smf', help='SMF container (default: oai-smf)')
    args = parser.parse_args()
    try:
        while True:
            data = snapshot(args.container, args.window, args.amf, args.smf)
            if args.json:
                print(json.dumps(data, ensure_ascii=False), flush=True)
            else:
                if args.watch and sys.stdout.isatty():
                    print('\033[2J\033[H', end='')
                display(data)
                sys.stdout.flush()
            if not args.watch:
                return 0
            time.sleep(args.interval)
    except KeyboardInterrupt:
        return 0
    except (OSError, subprocess.TimeoutExpired, RuntimeError) as error:
        print(f'UE status query failed: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
