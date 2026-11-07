// Cold-cache (provider) check for NFR-1.3 "a cache miss shall not exceed 3 s", kept apart from
// the sustained warm-cache load. One VU, COLD_CHECKS sequential requests (hard cap 10, so at most
// 20 live Open-Meteo/CAMS requests per run) for random Bangkok cells/hours that are not cached.
// Each miss is followed by one repeat that must be a cache hit.
import http from 'k6/http'
import { check, fail, sleep } from 'k6'
import { Counter, Trend } from 'k6/metrics'
import { BASE_URL, login, summarize, weatherUrl } from './lib.js'

const CHECKS = Math.min(Number(__ENV.COLD_CHECKS || 5), 10)
const missDuration = new Trend('weather_cache_miss_duration', true)
const alreadyCached = new Counter('weather_cold_skipped_already_cached')

export const options = {
  scenarios: { cold: { executor: 'per-vu-iterations', vus: 1, iterations: CHECKS, maxDuration: '3m' } },
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'max', 'count'],
  thresholds: {
    weather_cache_miss_duration: ['max<3000'],         // NFR-1.3 (both documents), confirmed misses only
    'http_req_duration{op:weather_cold}': ['max<3000'],  // same limit over every cold request
    'checks{op:weather_cold}': ['rate>0.99'],            // proposed correctness target
  },
}

export function setup() {
  const token = login(1)
  if (!token) fail('load-test accounts missing: run k8s/scripts/run-tool.sh python seed_loadtest.py')
  return { headers: { Authorization: `Bearer ${token}` } }
}

export default function (data) {
  // Random 0.01-degree cell (the cache key's resolution) and hour, 1-4 days ahead: the CAMS
  // air-quality forecast ends after about 4.5 days, and later slots are answered with 503.
  const hours = 24 + Math.floor(Math.random() * 72)
  const at = new Date(Math.floor(Date.now() / 3600000 + hours) * 3600000).toISOString()
  const slot = { latitude: (13.55 + Math.floor(Math.random() * 50) / 100).toFixed(2), longitude: (100.30 + Math.floor(Math.random() * 50) / 100).toFixed(2), at }
  const res = http.get(weatherUrl(slot), { headers: data.headers, tags: { op: 'weather_cold', name: 'GET /api/v1/conditions (cold)' } })
  const body = res.status === 200 ? res.json() : null
  if (body && body.cacheHit) { alreadyCached.add(1); return }
  if (!body) console.warn(`cold weather ${res.status} for ${JSON.stringify(slot)}: ${res.body}`)
  if (body) missDuration.add(res.timings.duration)
  const repeat = http.get(weatherUrl(slot), { headers: data.headers, tags: { op: 'weather_cached', name: 'GET /api/v1/conditions' } })
  check(res, {
    'cold weather 200 from provider': (r) => r.status === 200 && body.cacheHit === false && body.provider === 'Open-Meteo / CAMS',
    'repeat is a cache hit': () => repeat.status === 200 && repeat.json('cacheHit') === true,
  }, { op: 'weather_cold' })
  sleep(1)
}

export function handleSummary(data) {
  return summarize(data, { script: 'weather-cold.js', scenario: 'cold', checks: CHECKS, label: __ENV.LABEL || '' })
}
