#!/usr/bin/env python3
"""Show recently observed OAI UE MAC statistics from Docker logs and probe UE IPs with ICMP ping."""
import argparse
from datetime import datetime, timedelta, timezone
import json
import ipaddress
import math
import re
import subprocess
import sys
import time

# Replaced with the git commit by scripts/install-ue-status.sh.
__version__ = 'dev'

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



def check_connectivity(data, container, enabled=True):
    """Send three ICMP requests to each matched address from the data network."""
    data['ping_container'] = container
    for ue in data['ues']:
        ue['connectivity'] = []
        if not enabled or not ue.get('ue_ip'):
            ue['connectivity'].append({
                'status': 'skipped',
                'detail': 'Disabled by --no-ping.' if not enabled else 'No matched UE IP.'})
            continue
        for address in ue['ue_ip'].split(','):
            result = {'address': address, 'checked_at': datetime.now(timezone.utc).isoformat()}
            try:
                address = str(ipaddress.ip_address(address))
                probe = subprocess.run(
                    ['docker', 'exec', container, 'ping', '-n', '-c', '3', '-W', '1', address],
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=8)
                result['output'] = probe.stdout.strip()
                if probe.returncode == 0:
                    result.update(status='reachable', detail='ICMP reply received.')
                elif probe.returncode == 1:
                    result.update(status='no-reply', detail='No ICMP reply received.')
                else:
                    result.update(status='error', detail=probe.stdout.strip() or f'Exit code {probe.returncode}.')
            except (OSError, ValueError, subprocess.TimeoutExpired) as error:
                result.update(status='error', detail=str(error))
            ue['connectivity'].append(result)


def format_kst(timestamp):
    """Render Docker/ISO timestamps in KST for human-readable output."""
    try:
        value = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
        if value.tzinfo is None:
            return timestamp
        return value.astimezone(timezone(timedelta(hours=9), 'KST')).isoformat(sep=' ') + ' KST'
    except ValueError:
        return timestamp


def display(data):
    def section(title):
        print(f"\n{title}")
        print('-' * 78)

    print('=' * 78)
    print('UE STATUS')
    print('=' * 78)
    print(f"Checked at : {format_kst(data['checked_at'])}")
    print(f"Container  : {data['container']}")
    print(f"Observed   : {len(data['ues'])} UE(s) in the last {data['window_seconds']}s")
    print(f"Observation window: the last {data['window_seconds']} seconds of gNB logs (set with --window SECONDS).")
    print('A UE is listed if its radio statistics appear in that time range.')
    print(f"After disconnection, it may remain listed for up to {data['window_seconds']} seconds after its last log entry.")
    print('It disappears on a subsequent refresh once that entry falls outside the window.')
    print('Being listed is not proof of a live connection; missing statistics do not prove disconnection.')
    if data.get('warnings'):
        section('WARNINGS')
    for warning in data.get('warnings', []):
        print(f'Warning: {warning}')
    if not data['ues']:
        section('UE STATISTICS')
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
    section('UE STATISTICS')
    print('  '.join(name.ljust(width) for (name, _), width in zip(columns, widths)))
    print('  '.join('-' * width for width in widths))
    for row in rows:
        print('  '.join(value.ljust(width) for value, width in zip(row, widths)))
    section('FIELD NOTES')
    print('TX/RX : cumulative bytes sent/received by the gNB')
    print('BLER  : reported value')
    print('-     : unavailable in the latest statistics')
    print('UE-IP: address from SMF allocation records, matched to this UE using AMF identity information.')
    print('       See IP CONNECTIVITY below for the ICMP ping results.')
    print('       - means no allocation record was found or matched to this UE.')
    section('IP CONNECTIVITY')
    print(f"Probe source: {data.get('ping_container', 'unavailable')} -> UE IP (3 ICMP requests, 1s reply timeout)")
    print('A reply confirms ICMP reachability only. No reply may also mean ICMP filtering;')
    print('it does not by itself prove that the UE is disconnected.')
    for ue in data['ues']:
        for probe in ue.get('connectivity', [{'status': 'skipped', 'detail': 'Not tested.'}]):
            print(f"\n  UE {ue['rnti']} | {probe.get('address', ue.get('ue_ip') or '-')} | {probe['status'].upper()}")
            output = probe.get('output')
            if output:
                lines = output.splitlines()
                print(f"    Ping: {lines[0]}")
                for line in lines[1:]:
                    print(f'    {line}')
            else:
                print(f"    {probe['detail']}")
    section('OBSERVATION TIMES (KST)')
    print('The IP record time is not the last traffic or disconnect time;')
    print('it may predate the radio statistics.')
    for ue in data['ues']:
        print(f"\n  UE {ue['rnti']} | IP: {ue.get('ue_ip') or '-'}")
        print(f"  Latest radio statistics: {format_kst(ue['last_seen'])} (gNB log)")
        if ue.get('ip_last_seen'):
            print(f"  IP allocation recorded: {format_kst(ue['ip_last_seen'])} (SMF log)")
        else:
            print('  IP allocation recorded: unavailable')


def positive(value):
    number = float(value)
    if not math.isfinite(number) or number <= 0:
        raise argparse.ArgumentTypeError('Enter a positive finite number.')
    return number


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', action='version', version=f'ue-status {__version__}')
    parser.add_argument('-c', '--container', default='oai-gnb', help='Container name (default: oai-gnb)')
    parser.add_argument('--window', type=positive, default=10, help='Recent log window in seconds (default: 10)')
    parser.add_argument('-w', '--watch', action='store_true', help='Refresh periodically (Ctrl+C to exit)')
    parser.add_argument('--interval', type=positive, default=2, help='Refresh interval in seconds (default: 2)')
    parser.add_argument('--json', action='store_true', help='Output JSON; watch mode emits one snapshot per line')
    parser.add_argument('--amf', default='oai-amf', help='AMF container (default: oai-amf)')
    parser.add_argument('--smf', default='oai-smf', help='SMF container (default: oai-smf)')
    parser.add_argument('--ping-container', default='oai-ext-dn', help='ICMP probe source container (default: oai-ext-dn)')
    parser.add_argument('--no-ping', action='store_true', help='Skip active ICMP probes; show log observations only')
    args = parser.parse_args()
    try:
        while True:
            data = snapshot(args.container, args.window, args.amf, args.smf)
            check_connectivity(data, args.ping_container, enabled=not args.no_ping)
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
