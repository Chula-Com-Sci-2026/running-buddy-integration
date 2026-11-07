// Shared helpers for the Running Buddy k6 scripts. Every request goes through the API gateway,
// authenticated as a seeded load-test account (scripts/seed_loadtest.py).
import http from 'k6/http'
import { check } from 'k6'
import exec from 'k6/execution'
import { Rate, Trend } from 'k6/metrics'

export const BASE_URL = (__ENV.BASE_URL || 'http://gateway:8000') + '/api/v1'
export const ACCOUNTS = Number(__ENV.ACCOUNTS || 5000)
const PASSWORD = __ENV.LOADTEST_PASSWORD || 'k6-runner-pass'
// Access tokens live 15 minutes; renew a little earlier so long runs never send expired tokens.
const TOKEN_RENEW_MS = Number(__ENV.TOKEN_RENEW_SECONDS || 720) * 1000

export const loginDuration = new Trend('login_duration', true)
export const loginFailed = new Rate('login_failed')

// Original Deliverable 1 targets are the provisional baseline. running-buddy/docs/requirements.md
// states looser ones; TARGETS=requirements evaluates those instead. Neither document is changed.
const TARGET_SETS = {
  d1: { runner_search: 2000, nearby_runs: 1000, weather_cached: 300 },
  requirements: { runner_search: 3000, nearby_runs: 2000, weather_cached: 500 },
}
export const TARGET_SET = __ENV.TARGETS || 'd1'
export const P95_TARGETS = TARGET_SETS[TARGET_SET]
// Proposed (new, not in either requirements document): per-operation error and check rates.
export const MAX_ERROR_RATE = Number(__ENV.MAX_ERROR_RATE || 0.01)

export function thresholds(ops) {
  const result = {}
  for (const op of ops) {
    if (P95_TARGETS[op]) result[`http_req_duration{op:${op}}`] = [`p(95)<${P95_TARGETS[op]}`]
    result[`http_req_failed{op:${op}}`] = [`rate<${MAX_ERROR_RATE}`]
    result[`checks{op:${op}}`] = [`rate>${1 - MAX_ERROR_RATE}`]
  }
  return result
}

export function email(index) {
  return `k6-runner-${String(index).padStart(5, '0')}@loadtest.example.com`
}

export function login(index) {
  const res = http.post(`${BASE_URL}/auth/login`, JSON.stringify({ email: email(index), password: PASSWORD }), {
    headers: { 'Content-Type': 'application/json' }, tags: { op: 'login', name: 'POST /api/v1/auth/login' },
  })
  loginDuration.add(res.timings.duration)
  loginFailed.add(res.status !== 200)
  let token = null
  try { token = res.json('accessToken') } catch (_) { /* reported by the check below */ }
  check(res, { 'login 200 with access token': (r) => r.status === 200 && !!token }, { op: 'login' })
  return token
}

// One account per VU (VU n -> account n-1), so 500 VUs are 500 different runners. Returns null
// when login failed, so the caller skips its business request and the failure counts only once,
// as a login failure (login_failed), not as a 401 on search/runs/weather.
const session = { token: null, at: 0 }
export function authHeaders() {
  if (!session.token || Date.now() - session.at > TOKEN_RENEW_MS) {
    session.token = login((exec.vu.idInTest - 1) % ACCOUNTS)
    session.at = Date.now()
  }
  return session.token ? { Authorization: `Bearer ${session.token}` } : null
}

export function pick(items) {
  return items[Math.floor(Math.random() * items.length)]
}

// Weather slots for the warm-cache test: three Bangkok parks x two peak hours (NFR-2.2), two days
// ahead so the slot stays inside the provider's forecast horizon for the whole run.
export function weatherSlots() {
  const day = new Date(Date.now() + 2 * 86400000)
  const at = (utcHour) => new Date(Date.UTC(day.getUTCFullYear(), day.getUTCMonth(), day.getUTCDate(), utcHour)).toISOString()
  const places = [[13.73, 100.54], [13.72, 100.56], [13.80, 100.55]]
  // 06:00 and 18:00 Bangkok time = 23:00 (previous UTC day) and 11:00 UTC.
  return places.flatMap(([latitude, longitude]) => [at(-1), at(11)].map((time) => ({ latitude, longitude, at: time })))
}

export function weatherUrl(slot) {
  return `${BASE_URL}/conditions?latitude=${slot.latitude}&longitude=${slot.longitude}&at=${encodeURIComponent(slot.at)}`
}

// handleSummary helpers: compact per-operation table plus the full JSON between markers, so the
// result can be extracted from `kubectl logs` of the in-cluster k6 Job.
export function summarize(data, meta) {
  const ops = ['runner_search', 'nearby_runs', 'weather_cached', 'weather_cold', 'login']
  const seconds = data.state.testRunDurationMs / 1000
  const value = (name, stat) => (data.metrics[name] && data.metrics[name].values[stat])
  const verdict = (name) => {
    const t = data.metrics[name] && data.metrics[name].thresholds
    if (!t) return ''
    return Object.entries(t).map(([expr, r]) => `${expr} ${r.ok ? 'PASS' : 'FAIL'}`).join('; ')
  }
  const int = (n) => (n === undefined || n === null ? '-' : String(Math.round(n)))
  const fmt = (n) => (n === undefined || n === null || Number.isNaN(n) ? '-' : Number(n).toFixed(n < 10 ? 2 : 0))
  const lines = [
    `scenario=${meta.scenario} targets=${TARGET_SET} duration=${seconds.toFixed(0)}s vus_max=${int(value('vus_max', 'value'))} ` +
      `iterations=${int(value('iterations', 'count'))} http_reqs=${int(value('http_reqs', 'count'))} (${fmt(value('http_reqs', 'rate'))}/s) ` +
      `dropped_iterations=${int(value('dropped_iterations', 'count') || 0)}`,
    'op              count    req/s   avg ms   p50 ms   p90 ms   p95 ms   p99 ms   max ms  failed%  checks%  thresholds',
  ]
  for (const op of ops) {
    const d = `http_req_duration{op:${op}}`
    // Per-operation submetrics exist only where a threshold names them; login uses its own Trend.
    const dur = data.metrics[d] ? d : op === 'login' && data.metrics.login_duration ? 'login_duration' : null
    if (!dur) continue
    const count = value(dur, 'count')
    const row = [op.padEnd(14), int(count).padStart(7), fmt(count / seconds).padStart(8)]
    for (const stat of ['avg', 'med', 'p(90)', 'p(95)', 'p(99)', 'max']) row.push(fmt(dur && value(dur, stat)).padStart(8))
    const failed = op === 'login' ? value('login_failed', 'rate') : value(`http_req_failed{op:${op}}`, 'rate')
    const checks = value(`checks{op:${op}}`, 'rate')
    row.push((failed === undefined ? '-' : (failed * 100).toFixed(2)).padStart(8), (checks === undefined ? '-' : (checks * 100).toFixed(2)).padStart(8))
    row.push(' ' + [verdict(d), verdict(`http_req_failed{op:${op}}`), verdict(`checks{op:${op}}`)].filter(Boolean).join('; '))
    lines.push(row.join(' '))
  }
  for (const name of Object.keys(data.metrics).filter((n) => n.startsWith('weather_') && !n.includes('{'))) {
    lines.push(`${name}: ${JSON.stringify(data.metrics[name].values)} ${verdict(name)}`)
  }
  const json = JSON.stringify({ meta, state: data.state, metrics: data.metrics, root_group: data.root_group }, null, 1)
  return { stdout: lines.join('\n') + '\n===K6_SUMMARY_JSON_BEGIN===\n' + json + '\n===K6_SUMMARY_JSON_END===\n' }
}
