"""Side-by-side table of k6 result directories (run-k6.sh output), e.g. one vs two replicas.

Usage: python3 load-tests/compare.py <result-dir> <result-dir> [...] > comparison.md
Reads summary.json, environment.txt and pod-usage.txt from each directory.
"""
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

OPS = ['runner_search', 'nearby_runs', 'weather_cached']


def load(directory):
    path = Path(directory)
    summary = json.loads((path / 'summary.json').read_text())
    metrics, seconds = summary['metrics'], summary['state']['testRunDurationMs'] / 1000
    value = lambda name, stat: metrics.get(name, {}).get('values', {}).get(stat)
    replicas = dict(re.findall(r'^\s+(\S+)\s+\d+\s+(\d+)\s', (path / 'environment.txt').read_text(), re.M))
    peak = defaultdict(int)  # deployment -> peak summed millicores across its pods in one sample
    sample = defaultdict(int)
    for line in (path / 'pod-usage.txt').read_text().splitlines() + ['## end']:
        if line.startswith('##'):
            for name, cpu in sample.items():
                peak[name] = max(peak[name], cpu)
            sample = defaultdict(int)
        elif line.startswith('NODE '):
            parts = line.split()
            sample['node'] = int(parts[2].rstrip('m')); sample['node %'] = int(parts[3].rstrip('%'))
        elif line.strip():
            pod, cpu = line.split()[:2]
            sample[re.sub(r'-[a-z0-9]{8,10}-[a-z0-9]{5}$|-\d+$', '', pod)] += int(cpu.rstrip('m'))
    thresholds = {f'{name} {expr}': result['ok'] for name, metric in metrics.items()
                  for expr, result in (metric.get('thresholds') or {}).items()}
    return {'name': path.name, 'seconds': seconds, 'value': value, 'replicas': replicas, 'peak': peak, 'thresholds': thresholds}


def main(directories):
    runs = [load(d) for d in directories]
    fmt = lambda n, digits=0: '-' if n is None else f'{n:,.{digits}f}'
    print('| Metric | ' + ' | '.join(r['name'] for r in runs) + ' |')
    print('|---|' + '---|' * len(runs))
    row = lambda label, cells: print(f'| {label} | ' + ' | '.join(cells) + ' |')
    row('Replicas (gateway/profile/scheduling/conditions/discovery)',
        ['/'.join(r['replicas'].get(n, '?') for n in ('gateway', 'profile', 'scheduling', 'conditions', 'discovery')) for r in runs])
    row('Duration (s)', [fmt(r['seconds']) for r in runs])
    row('Peak VUs', [fmt(r['value']('vus_max', 'value') or r['value']('vus_max', 'max')) for r in runs])
    row('HTTP requests (total)', [fmt(r['value']('http_reqs', 'count')) for r in runs])
    row('Throughput (req/s, whole run)', [fmt(r['value']('http_reqs', 'rate'), 1) for r in runs])
    row('Iterations', [fmt(r['value']('iterations', 'count')) for r in runs])
    row('Dropped iterations', [fmt(r['value']('dropped_iterations', 'count') or 0) for r in runs])
    for op in OPS:
        d = f'http_req_duration{{op:{op}}}'
        row(f'{op} requests', [fmt(r['value'](d, 'count')) for r in runs])
        for stat in ('med', 'p(95)', 'p(99)', 'max'):
            row(f'{op} {stat} (ms)', [fmt(r['value'](d, stat)) for r in runs])
        row(f'{op} failed (%)', [fmt((r['value'](f'http_req_failed{{op:{op}}}', 'rate') or 0) * 100, 2) for r in runs])
        row(f'{op} checks passed (%)', [fmt((r['value'](f'checks{{op:{op}}}', 'rate') or 0) * 100, 2) for r in runs])
    row('Peak node CPU (millicores)', [fmt(r['peak'].get('node')) for r in runs])
    row('Peak node CPU (%)', [fmt(r['peak'].get('node %')) for r in runs])
    for name in ('gateway', 'profile', 'scheduling', 'conditions', 'discovery', 'identity', 'postgres', 'k6'):
        row(f'Peak CPU {name} (millicores, all pods)', [fmt(r['peak'].get(name)) for r in runs])
    names = sorted({name for r in runs for name in r['thresholds']})
    for name in names:
        row(f'Threshold {name}', ['PASS' if r['thresholds'].get(name) else 'FAIL' if name in r['thresholds'] else '-' for r in runs])


if __name__ == '__main__':
    main(sys.argv[1:])
