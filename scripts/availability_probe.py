"""Fixed-rate request probe through the gateway, for pod-replacement and gRPC reconnection evidence.

Logs in once, then sends PROBE_RATE requests per second to PROBE_PATH for PROBE_DURATION seconds
and prints one line per second (sent/ok/failed, latency, status codes) plus a final JSON summary.
Every failure is listed with its timestamp so it can be lined up with pod events.

Env: PROBE_PATH (/api/v1/me/profile), PROBE_RATE (20), PROBE_DURATION (90), PROBE_EMAIL,
     PROBE_PASSWORD, GATEWAY_URL (http://gateway:8000).
"""
import json
import os
import threading
import time
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import httpx

BASE = os.getenv('GATEWAY_URL', 'http://gateway:8000')
PATH = os.getenv('PROBE_PATH', '/api/v1/me/profile')
RATE = int(os.getenv('PROBE_RATE', '20'))
DURATION = int(os.getenv('PROBE_DURATION', '90'))
lock = threading.Lock()
buckets = defaultdict(list)  # second -> [(status, ms)]
failures = []


def now(): return datetime.now(timezone.utc).isoformat(timespec='milliseconds')


def login():
    response = httpx.post(BASE + '/api/v1/auth/login', timeout=30,
                          json={'email': os.getenv('PROBE_EMAIL', 'ray@example.com'), 'password': os.getenv('PROBE_PASSWORD', 'runner123')})
    response.raise_for_status()
    return response.json()['accessToken']


def call(client, second):
    started = time.perf_counter()
    try:
        status = client.get(PATH).status_code
    except httpx.HTTPError as error:
        status = type(error).__name__
    elapsed = (time.perf_counter() - started) * 1000
    with lock:
        buckets[second].append((status, elapsed))
        if status != 200:
            failures.append({'at': now(), 'second': second, 'status': status, 'ms': round(elapsed)})


def report(second):
    rows = buckets.get(second, [])
    times = sorted(ms for _, ms in rows)
    codes = Counter(str(status) for status, _ in rows)
    ok = codes.get('200', 0)
    p50 = times[len(times) // 2] if times else 0
    print(f't+{second:03d}s {now()} sent={len(rows)} ok={ok} failed={len(rows) - ok} '
          f'p50={p50:.0f}ms max={(times[-1] if times else 0):.0f}ms codes={dict(codes)}', flush=True)


def main():
    token = login()
    client = httpx.Client(base_url=BASE, timeout=10, headers={'Authorization': 'Bearer ' + token},
                          limits=httpx.Limits(max_connections=64, max_keepalive_connections=64))
    print(f'probe start {now()} target={BASE}{PATH} rate={RATE}/s duration={DURATION}s', flush=True)
    start = time.monotonic()
    with ThreadPoolExecutor(max_workers=64) as pool:
        for tick in range(DURATION * RATE):
            delay = start + tick / RATE - time.monotonic()
            if delay > 0:
                time.sleep(delay)
            second = tick // RATE
            pool.submit(call, client, second)
            if tick % RATE == RATE - 1 and second >= 1:
                report(second - 1)  # previous second is complete apart from slow stragglers
    report(DURATION - 1)
    all_rows = [row for rows in buckets.values() for row in rows]
    times = sorted(ms for _, ms in all_rows)
    ok = sum(1 for status, _ in all_rows if status == 200)
    summary = {'target': BASE + PATH, 'rate': RATE, 'durationSeconds': DURATION, 'sent': len(all_rows), 'ok': ok,
               'failed': len(all_rows) - ok, 'successRate': round(ok / len(all_rows), 5) if all_rows else None,
               'p50Ms': round(times[len(times) // 2]) if times else None,
               'p95Ms': round(times[int(len(times) * .95)]) if times else None, 'maxMs': round(times[-1]) if times else None,
               'failures': failures}
    print('PROBE_SUMMARY ' + json.dumps(summary), flush=True)


if __name__ == '__main__':
    main()
