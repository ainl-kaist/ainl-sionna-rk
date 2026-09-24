#!/usr/bin/env python3
"""Check the UE host's WWAN interface, IP addresses, routes and optional reachability."""
import argparse
from datetime import datetime, timedelta, timezone
import ipaddress
import json
import math
import shutil
import subprocess
import sys
import time


def run(command):
    result = subprocess.run(command, capture_output=True, text=True, timeout=15)
    if result.returncode:
        raise RuntimeError((result.stderr or result.stdout).strip() or f'{command[0]} failed')
    return result.stdout


def inspect(interface, target=None):
    data = {'checked_at': datetime.now(timezone.utc).isoformat(),
            'interface': interface, 'target': target, 'checks': []}

    def check(name, state, detail):
        data['checks'].append({'name': name, 'status': state, 'detail': detail})

    try:
        links = json.loads(run(['ip', '-j', 'address', 'show', 'dev', interface]))
    except RuntimeError as error:
        check('interface', 'FAIL', str(error))
        data['ok'] = False
        return data
    if not links:
        check('interface', 'FAIL', 'Interface not found.')
        data['ok'] = False
        return data
    link = links[0]
    check('interface', 'PASS', 'Interface exists.')
    flags = link.get('flags', [])
    operstate = link.get('operstate', 'UNKNOWN')
    # Cellular raw-IP interfaces may report UNKNOWN while fully operational.
    up = 'UP' in flags and operstate not in ('DOWN', 'LOWERLAYERDOWN', 'NOTPRESENT')
    check('link', 'PASS' if up else 'FAIL', f"Flags: {','.join(flags)}; operstate: {operstate}")
    addresses = [a for a in link.get('addr_info', [])
                 if a.get('scope') == 'global' and a.get('valid_life_time') != 0
                 and not a.get('tentative') and not a.get('dadfailed')
                 and not {'tentative', 'dadfailed'}.intersection(a.get('flags', []))]
    data['addresses'] = [f"{a['local']}/{a['prefixlen']}" for a in addresses]
    check('ip_address', 'PASS' if addresses else 'FAIL',
          ', '.join(data['addresses']) or 'No usable global IP address assigned.')
    data['routes'] = []
    for family in ('-4', '-6'):
        data['routes'].extend(json.loads(run(['ip', '-j', family, 'route', 'show', 'table', 'all', 'dev', interface])))
    defaults = [r for r in data['routes'] if r.get('dst') == 'default']
    check('default_route', 'INFO', json.dumps(defaults) if defaults else
          'No default route on this interface; a destination-specific route may still work.')
    if target:
        family = '-4' if ipaddress.ip_address(target).version == 4 else '-6'
        try:
            route = json.loads(run(['ip', '-j', family, 'route', 'get', target]))
            selected = route[0].get('dev') if route else None
            data['selected_route'] = route
            check('normal_route', 'PASS' if selected == interface else 'FAIL',
                  f'Unbound traffic to {target} selects {selected or "no interface"}.')
        except RuntimeError as error:
            check('normal_route', 'FAIL', str(error))
        if not shutil.which('ping'):
            check('bound_ping', 'FAIL', 'ping is not installed.')
        else:
            command = ['ping', family, '-n', '-I', interface, '-c', '3', '-W', '2', '-w', '8', target]
            try:
                output = run(command)
                check('bound_ping', 'PASS', output.strip())
            except RuntimeError as error:
                check('bound_ping', 'FAIL', str(error) + '\nICMP failure alone does not prove the cellular session is disconnected.')
    else:
        check('reachability', 'SKIP', 'Use --target IP to check route selection and ping through this interface.')
    data['ok'] = all(c['status'] != 'FAIL' for c in data['checks'])
    return data


def display(data):
    def section(title):
        print(f"\n{title}")
        print('-' * 78)

    checks = {item['name']: item for item in data['checks']}

    def show(name, label):
        item = checks.get(name)
        if item is None:
            print(f'  [SKIP] {label}: interface unavailable.')
            return
        lines = item['detail'].splitlines() or ['']
        print(f"  [{item['status']}] {label}: {lines[0]}")
        for line in lines[1:]:
            print(f'    {line}')

    checked_at = datetime.fromisoformat(data['checked_at'].replace('Z', '+00:00'))
    checked_at = checked_at.astimezone(timezone(timedelta(hours=9), 'KST'))
    print('=' * 78)
    print('UE WWAN STATUS')
    print('=' * 78)
    print(f"Checked at : {checked_at.isoformat(sep=' ')} KST")
    print(f"Interface  : {data['interface']}")
    print(f"Target     : {data['target'] or 'none (local configuration only)'}")

    section('INTERFACE AND IP ADDRESS')
    show('interface', 'Interface')
    show('link', 'Link state')
    show('ip_address', 'IP addresses')
    print('Note: operstate UNKNOWN can be normal for WWAN interfaces.')

    section('ROUTING')
    show('default_route', 'Default routes')
    if data['target'] is not None:
        show('normal_route', 'Ordinary traffic')
    else:
        print('  [SKIP] Target route lookup: local-only mode.')

    section('IP CONNECTIVITY')
    if data['target'] is not None:
        print(f"Probe: {data['interface']} -> {data['target']} (3 ICMP requests, 2s timeout, 8s deadline)")
        show('bound_ping', 'Ping')
        # Failed ping details already include the ICMP interpretation note.
        if checks.get('bound_ping', {}).get('status') != 'FAIL':
            print('Note: ICMP reachability does not confirm application service availability.')
    else:
        print('  [SKIP] Local-only mode; IP connectivity was not tested.')

    section('RESULT SUMMARY')
    failed = [item['name'] for item in data['checks'] if item['status'] == 'FAIL']
    print('Result: ' + ('PASS' if data['ok'] else 'FAIL'))
    if failed:
        print('Failed checks: ' + ', '.join(failed))
    if checks.get('normal_route', {}).get('status') == 'FAIL' and checks.get('bound_ping', {}).get('status') == 'PASS':
        print('Ping used WWAN explicitly, but ordinary traffic selects a different route or has no usable route.')
    print('PASS: check passed | FAIL: check failed | INFO: informational | SKIP: not tested')


def positive(value):
    number = float(value)
    if not math.isfinite(number) or number <= 0:
        raise argparse.ArgumentTypeError('Enter a positive finite number.')
    return number


def target_ip(value):
    try:
        return str(ipaddress.ip_address(value))
    except ValueError as error:
        raise argparse.ArgumentTypeError('Use a numeric IPv4 or IPv6 destination address.') from error


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('-i', '--interface', default='wwan0', help='UE interface (default: wwan0)')
    destination = parser.add_mutually_exclusive_group()
    destination.add_argument('--target', type=target_ip, default='192.168.72.135',
                             help='Destination IP for route selection and interface-bound ping (default: 192.168.72.135)')
    destination.add_argument('--local-only', dest='target', action='store_const', const=None,
                             help='Check local interface configuration without route probing or ping')
    parser.add_argument('-w', '--watch', action='store_true', help='Refresh until Ctrl+C')
    parser.add_argument('--interval', type=positive, default=2, help='Delay between checks in seconds (default: 2)')
    parser.add_argument('--json', action='store_true', help='Output JSON; one snapshot per line in watch mode')
    args = parser.parse_args()
    if not shutil.which('ip'):
        print('UE interface check failed: iproute2 (ip command) is required.', file=sys.stderr)
        return 2
    try:
        while True:
            data = inspect(args.interface, args.target)
            if args.json:
                print(json.dumps(data), flush=True)
            else:
                if args.watch and sys.stdout.isatty():
                    print('\033[2J\033[H', end='')
                display(data)
                sys.stdout.flush()
            if not args.watch:
                return 0 if data['ok'] else 1
            time.sleep(args.interval)
    except KeyboardInterrupt:
        return 0
    except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as error:
        print(f'UE interface check failed: {error}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
