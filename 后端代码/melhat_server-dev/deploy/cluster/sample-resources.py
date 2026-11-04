#!/usr/bin/env python3
"""Read only selected isolated containers' metrics; no environment or payload capture."""
import argparse
import datetime
import json
from pathlib import Path
import re
import subprocess
import time

def command(args):
    return subprocess.run(args, check=True, capture_output=True, text=True, encoding='utf-8', timeout=15).stdout.strip()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--duration', type=int, required=True)
    parser.add_argument('--interval', type=int, default=5)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('containers', nargs='+')
    args = parser.parse_args()
    if not 10 <= args.duration <= 86400 or not 1 <= args.interval <= 60:
        parser.error('Use bounded duration 10..86400 seconds and interval 1..60 seconds.')
    if len(set(args.containers)) != len(args.containers) or any(not re.fullmatch(r'wearable-[a-z0-9-]+', name) for name in args.containers):
        parser.error('Explicit unique wearable-* isolated container names are required.')
    limits = []
    for name in args.containers:
        values = command(['docker', 'inspect', '--format', '{{.Id}}|{{.Image}}|{{.HostConfig.Memory}}|{{.HostConfig.NanoCpus}}|{{.HostConfig.CpuQuota}}|{{.HostConfig.CpuPeriod}}', name]).split('|')
        limits.append(dict(name=name, containerId=values[0], imageId=values[1], memoryBytes=int(values[2]),
                           nanoCpus=int(values[3]), cpuQuota=int(values[4]), cpuPeriod=int(values[5])))
    started = time.monotonic()
    errors = 0
    with args.output.open('x', encoding='utf-8') as evidence:
        evidence.write(json.dumps(dict(type='limits', containers=limits)) + '\n')
        while time.monotonic() - started < args.duration:
            stamp = datetime.datetime.now(datetime.timezone.utc).isoformat()
            try:
                rows = command(['docker', 'stats', '--no-stream', '--format', '{{json .}}', *args.containers]).splitlines()
                sample = dict(type='sample', utc=stamp, elapsedSeconds=time.monotonic() - started, rows=[json.loads(row) for row in rows])
                if len(sample['rows']) != len(args.containers):
                    raise ValueError('Incomplete sample')
            except (subprocess.SubprocessError, ValueError):
                errors += 1
                sample = dict(type='sample', utc=stamp, error=True)
            evidence.write(json.dumps(sample) + '\n')
            evidence.flush()
            time.sleep(max(0, min(args.interval, args.duration - (time.monotonic() - started))))
    print(f'Resource evidence written; failed samples: {errors}.')
    return 2 if errors else 0

if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.SubprocessError):
        print('Resource collection failed. No capacity claim was produced.')
        raise SystemExit(1)
