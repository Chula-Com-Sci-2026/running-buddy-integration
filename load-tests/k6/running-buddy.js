// Runner search, nearby runs and warm-cache weather through the gateway.
//   SCENARIO=smoke     1 VU, a few iterations of every operation: correctness before load.
//   SCENARIO=baseline  open model: BASELINE_RATE iterations/s for BASELINE_DURATION (no think time).
//   SCENARIO=ramp      closed model: ramp to TARGET_VUS concurrent users with think time.
// VUs are concurrent simulated users, not requests per second: with 1-5 s think time a VU sends
// roughly one request every 3 s plus response time, so 500 VUs is about 150 req/s, not 500.
import http from 'k6/http'
import { check, fail, sleep } from 'k6'
import { Counter } from 'k6/metrics'
import { ACCOUNTS, BASE_URL, authHeaders, login, pick, summarize, thresholds, weatherSlots, weatherUrl } from './lib.js'

const SCENARIO = __ENV.SCENARIO || 'smoke'
const TARGET_VUS = Number(__ENV.TARGET_VUS || 500)
const THINK_MIN = Number(__ENV.THINK_MIN || 1)
const THINK_MAX = Number(__ENV.THINK_MAX || 5)
const MIN_RUNS = Number(__ENV.MIN_RUNS || 100)
// Operation mix in percent: runner search, nearby runs, cached weather.
const [SEARCH_PCT, RUNS_PCT] = (__ENV.MIX || '30,40,30').split(',').map(Number)
// Any cache miss during sustained load reaches the live provider, so a handful aborts the run.
const MAX_WEATHER_MISSES = Number(__ENV.MAX_WEATHER_MISSES || 10)
const WARM_MAX_AGE = Number(__ENV.WARM_MAX_AGE_SECONDS || 120)

const weatherMiss = new Counter('weather_cache_miss')
const weatherProviderCalls = new Counter('weather_warmup_provider_calls')

const stages = (__ENV.RAMP_STAGES || '1m:0.1,2m:0.5,2m:1,3m:1,1m:0').split(',').map((stage) => {
  const [duration, fraction] = stage.split(':')
  return { duration, target: Math.round(Number(fraction) * TARGET_VUS) }
})

const scenarios = {
  smoke: { executor: 'per-vu-iterations', vus: 1, iterations: Number(__ENV.SMOKE_ITERATIONS || 3), maxDuration: '2m' },
  baseline: {
    executor: 'constant-arrival-rate', rate: Number(__ENV.BASELINE_RATE || 10), timeUnit: '1s',
    duration: __ENV.BASELINE_DURATION || '5m', preAllocatedVUs: Number(__ENV.BASELINE_VUS || 50), maxVUs: Number(__ENV.BASELINE_MAX_VUS || 200),
  },
  ramp: { executor: 'ramping-vus', startVUs: 0, stages, gracefulRampDown: '30s' },
}

export const options = {
  scenarios: { [SCENARIO]: scenarios[SCENARIO] },
  setupTimeout: '3m',
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max', 'count'],
  thresholds: {
    ...thresholds(['runner_search', 'nearby_runs', 'weather_cached']),
    weather_cache_miss: [{ threshold: `count<=${MAX_WEATHER_MISSES}`, abortOnFail: true }],
  },
}

// Warm six weather slots, each freshly fetched (at most 6 provider fetches = 12 upstream requests),
// and refuse to
// start if the dataset is not seeded. Runs before any VU starts and is not part of the measurement.
export function setup() {
  if (!scenarios[SCENARIO]) fail(`unknown SCENARIO ${SCENARIO}`)
  const token = login(0)
  if (!token) fail('load-test accounts missing: run k8s/scripts/run-tool.sh python seed_loadtest.py')
  const headers = { Authorization: `Bearer ${token}` }
  const runs = http.get(`${BASE_URL}/runs`, { headers, tags: { op: 'setup' } })
  if (runs.status !== 200 || runs.json().length < MIN_RUNS) fail(`expected at least ${MIN_RUNS} upcoming runs; seed or --reschedule the dataset`)
  // A slot cached by an earlier run could expire mid-test (TTL 15 min). Use only entries fetched
  // within the last WARM_MAX_AGE seconds; otherwise move that slot one hour later and fetch it.
  const slots = []
  for (const base of weatherSlots()) {
    let chosen = null
    for (let shift = 0; shift < 12 && !chosen; shift++) {
      const slot = { ...base, at: new Date(Date.parse(base.at) + shift * 3600000).toISOString() }
      const res = http.get(weatherUrl(slot), { headers, tags: { op: 'setup' } })
      if (res.status !== 200) continue
      if (!res.json('cacheHit')) weatherProviderCalls.add(1)
      const ageSeconds = (Date.now() - Date.parse(res.json('updatedAt'))) / 1000
      if (!res.json('cacheHit') || ageSeconds < WARM_MAX_AGE) chosen = slot
    }
    if (!chosen) fail(`no fresh weather slot near ${JSON.stringify(base)}`)
    const check2 = http.get(weatherUrl(chosen), { headers, tags: { op: 'setup' } })
    if (check2.status !== 200 || !check2.json('cacheHit')) fail(`weather slot ${JSON.stringify(chosen)} was not cached: ${check2.status}`)
    slots.push(chosen)
  }
  return { slots, accounts: ACCOUNTS, upcomingRuns: runs.json().length }
}

function runnerSearch(headers) {
  const radius = pick([5, 10])
  const experience = pick(['All', 'All', 'Beginner', 'Intermediate', 'Advanced'])
  const res = http.get(`${BASE_URL}/runners?radiusKm=${radius}&experience=${experience}`, {
    headers, tags: { op: 'runner_search', name: 'GET /api/v1/runners' },
  })
  let body = null
  try { body = res.json() } catch (_) { /* counted as a failed check */ }
  check(res, {
    'search 200': (r) => r.status === 200,
    'search returns compatible runners': () => Array.isArray(body) && body.length > 0 && body.every((p) => p.id && typeof p.match === 'number'),
    'search filters experience': () => Array.isArray(body) && (experience === 'All' || body.every((p) => p.experience === experience)),
    'search hides coordinates': () => Array.isArray(body) && body.every((p) => !('latitude' in p) && !('longitude' in p)),
  }, { op: 'runner_search' })
}

function nearbyRuns(headers) {
  const res = http.get(`${BASE_URL}/runs`, { headers, tags: { op: 'nearby_runs', name: 'GET /api/v1/runs' } })
  let body = null
  try { body = res.json() } catch (_) { /* counted as a failed check */ }
  check(res, {
    'runs 200': (r) => r.status === 200,
    'runs lists upcoming runs': () => Array.isArray(body) && body.length >= MIN_RUNS,
    'unjoined runs show approximate pins only': () => Array.isArray(body) &&
      body.filter((run) => !run.joined).every((run) => Math.abs(run.latitude * 10 - Math.round(run.latitude * 10)) < 1e-9),
  }, { op: 'nearby_runs' })
}

function cachedWeather(headers, slots) {
  const res = http.get(weatherUrl(pick(slots)), { headers, tags: { op: 'weather_cached', name: 'GET /api/v1/conditions' } })
  let body = null
  try { body = res.json() } catch (_) { /* counted as a failed check */ }
  if (body && body.cacheHit === false) weatherMiss.add(1)
  check(res, {
    'weather 200': (r) => r.status === 200,
    'weather served from cache': () => !!body && body.cacheHit === true,
    'weather has live provider data': () => !!body && body.provider === 'Open-Meteo / CAMS' && typeof body.temperature === 'number',
  }, { op: 'weather_cached' })
}

export default function (data) {
  const headers = authHeaders()
  if (!headers) { sleep(1); return }
  if (SCENARIO === 'smoke') {
    runnerSearch(headers)
    nearbyRuns(headers)
    cachedWeather(headers, data.slots)
    return
  }
  const roll = Math.random() * 100
  if (roll < SEARCH_PCT) runnerSearch(headers)
  else if (roll < SEARCH_PCT + RUNS_PCT) nearbyRuns(headers)
  else cachedWeather(headers, data.slots)
  if (SCENARIO === 'ramp') sleep(THINK_MIN + Math.random() * (THINK_MAX - THINK_MIN))
}

export function handleSummary(data) {
  return summarize(data, {
    script: 'running-buddy.js', scenario: SCENARIO, config: scenarios[SCENARIO], mix: { SEARCH_PCT, RUNS_PCT },
    thinkSeconds: SCENARIO === 'ramp' ? [THINK_MIN, THINK_MAX] : null, accounts: ACCOUNTS, label: __ENV.LABEL || '',
  })
}
