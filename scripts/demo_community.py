"""Operator-only demo community, seeded by seed.py after Ray and Mali. Never imported by a service.

Adds runners around Lumphini with avatars, so Discover and Who's nearby look lived-in, and a showcase
runner, Nok (nok@example.com / runner123), with buddies, shared past runs, a pending request, upcoming
runs her buddies organise, ratings and a running history.

The demo script still holds: within 2 km of Ray every new runner is Beginner or Advanced, so
"2 km + Intermediate" still leaves only Mali. Ray gets nothing here (his photo is for the live upload).
Mali gets an avatar and a few solo running records, but no buddies or ratings, so her rating stays
hidden after UC-04.
"""
import os
import random
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlsplit
from uuid import UUID, uuid5

import httpx
from psycopg.types.json import Jsonb

NAMESPACE = UUID('5d6c2a8e-6f1b-4c3e-9a7d-2b8e4f1c9a01')
NOK = '10101010-1010-4010-8010-101010101010'
AVATARS = Path(__file__).parent / 'demo-avatars'
ICT = timezone(timedelta(hours=7))
# Profile measures distance between 0.01° cells; Ray's cell. Offsets below are in cells from here.
RAY_CELL = (13.73, 100.54)


def ids(slug):
    return NOK if slug == 'nok' else str(uuid5(NAMESPACE, 'runner:' + slug))


# (slug, name, bio, pace from, pace to, experience, area, availability, cells north, cells east)
# Within 2 km (both offsets at most 1): Beginner or Advanced only. Intermediate starts at 2.2 km.
CROWD = [
    ('ploy', 'Ploy N.', 'Couch-to-5K graduate. Slow and chatty is my favourite pace.', 7, 8, 'Beginner', 'Lumphini Park', 'Evenings', 0, 0),
    ('praew', 'Praew M.', 'Weekend 5K with a coffee at the end. Looking for company!', 7, 8, 'Beginner', 'Lumphini Park', 'Weekends', 0, 0),
    ('arm', 'Arm T.', 'Marathon block for Bangkok Marathon. Intervals on Tuesdays, long runs on Sundays.', 4.5, 5.5, 'Advanced', 'Lumphini Park', 'Weekday mornings', 0, 1),
    ('june', 'June K.', 'Running my first 10K in December. Patient partners welcome.', 7, 8.5, 'Beginner', 'Silom', 'Weekends', -1, 0),
    ('kai', 'Kai L.', 'Trail runner stuck in the city. Early mornings before work.', 5, 5.5, 'Advanced', 'Sathorn', 'Early mornings', -1, 1),
    ('mint', 'Mint P.', 'Back to running after a knee injury, taking it easy.', 6.5, 7.5, 'Beginner', 'Lumphini Park', 'Evenings', 1, 0),
    ('tee', 'Tee W.', 'Sub-20 5K chaser. Happy to pace anyone going for a PB.', 4.5, 5, 'Advanced', 'Chit Lom', 'Weekday mornings', 1, 1),
    ('ice', 'Ice S.', 'Evening loops around Chula after class.', 7.5, 8.5, 'Beginner', 'Sam Yan', 'Evenings', 1, -1),
    ('bank', 'Bank R.', 'Half-marathon regular. Saturday long runs, steady pace.', 5, 6, 'Advanced', 'Ratchadamri', 'Weekends', 1, 0),
    ('nok', 'Nok T.', 'Benjakitti regular. Evening 8–10K, always up for a new running buddy.', 6, 6.5, 'Intermediate', 'Benjakitti Park', 'Evenings', 0, 2),
    ('oat', 'Oat C.', 'Runs to work twice a week, the long way round Benjakitti.', 6, 7, 'Intermediate', 'Benjakitti Park', 'Evenings', 0, 2),
    ('fern', 'Fern A.', 'After-work 5–8K near Asok. Music optional, chatting encouraged.', 5.5, 6.5, 'Intermediate', 'Asok', 'Weekday mornings', 1, 2),
    ('golf', 'Golf V.', 'Building up to a first half marathon.', 6, 6.5, 'Intermediate', 'Khlong Toei', 'Weekends', -2, 2),
    ('aom', 'Aom J.', 'Siam lunchtime runner. Short and sweet.', 6.5, 7, 'Intermediate', 'Siam', 'Evenings', 2, -1),
    ('bow', 'Bow K.', 'Thong Lo to Benjasiri and back, most evenings.', 6, 7, 'Intermediate', 'Thong Lo', 'Weekends', 0, 4),
    ('jay', 'Jay H.', 'Tempo runs and track sessions at Chula stadium.', 5.5, 6, 'Intermediate', 'Sam Yan', 'Weekday mornings', 1, -2),
]

# Nok's buddies and how many days ago each friendship started; Aom's request is still waiting.
NOK_BUDDIES = [('oat', 2), ('fern', 5), ('golf', 9), ('arm', 13), ('ploy', 21)]
PENDING_TO_NOK = ('aom', 'Saw you run Benjakitti most evenings, mind if I join one?')

# Finished group runs: (slug, organizer, title, meeting point, lat, lng, days ago, ICT hour, km, pace, runners).
# Everyone attended and everyone rated everyone, so each runner here gets at least three ratings.
PAST_RUNS = [
    ('benjakitti-sunrise', 'oat', 'Benjakitti sunrise 10K', 'Benjakitti Park main entrance', 13.7290, 100.5580, 3, 6, 10, '6:00–6:30', ['oat', 'nok', 'fern', 'golf']),
    ('lumphini-loops', 'arm', 'Lumphini evening loops', 'Lumphini Park Gate 2', 13.7322, 100.5432, 6, 18, 8, '5:30–6:30', ['arm', 'nok', 'ploy', 'oat']),
    ('saturday-long', 'nok', 'Saturday long run', 'Benjakitti Park main entrance', 13.7290, 100.5580, 9, 6, 15, '6:00–6:30', ['nok', 'fern', 'golf', 'arm', 'ploy']),
    ('recovery-5k', 'ploy', 'Easy recovery 5K', 'Lumphini Park Clock Tower', 13.7317, 100.5415, 13, 18, 5, '7:00–8:00', ['ploy', 'mint', 'june', 'praew']),
    ('tempo-tuesday', 'tee', 'Tempo Tuesday', 'Lumphini Park Gate 4', 13.7295, 100.5380, 16, 6, 8, '4:45–5:30', ['tee', 'kai', 'bank', 'arm']),
    ('chula-night', 'ice', 'Chula night run', 'Chulalongkorn stadium gate', 13.7380, 100.5280, 20, 19, 6, '7:00–8:00', ['ice', 'pim', 'june', 'narin']),
    ('asok-after-work', 'fern', 'Asok after-work 5K', 'Benjasiri Park gate', 13.7305, 100.5677, 24, 18, 5, '6:00–7:00', ['fern', 'aom', 'bow', 'jay']),
    ('chatuchak-social', 'ton', 'Chatuchak park social', 'Chatuchak Park clock tower', 13.8030, 100.5530, 28, 7, 7, '6:00–7:00', ['ton', 'fah', 'beam', 'bow']),
]

# Upcoming runs: (slug, organizer, title, meeting point, lat, lng, days ahead, ICT hour, minute, km, pace, limit, runners).
# Arm's and Ploy's are within 1 km of Ray, so his Home radar and Who's nearby show them.
UPCOMING_RUNS = [
    ('benjakitti-8k', 'oat', 'Benjakitti evening 8K', 'Benjakitti Park main entrance', 13.7290, 100.5580, 1, 18, 0, 8, '6:00–6:30', 10, ['oat', 'nok', 'fern']),
    ('lumphini-intervals', 'arm', 'Lumphini tempo intervals', 'Lumphini Park Gate 2', 13.7322, 100.5432, 2, 6, 30, 6, '5:00–5:30', 8, ['arm', 'tee']),
    ('beginner-5k', 'ploy', 'Beginner-friendly 5K', 'Lumphini Park Gate 4', 13.7296, 100.5386, 3, 18, 30, 5, '7:00–8:00', 12, ['ploy', 'mint', 'praew', 'june']),
    ('sunday-long', 'golf', 'Sunday long run', 'Benjakitti Park main entrance', 13.7290, 100.5580, 5, 6, 0, 16, '6:00–6:30', 10, ['golf']),
]


def seed_community(database, headers_for, existing):
    """`existing` maps the slugs seed.py already created (mali, narin, pim, beam, fah, ton) to ids."""
    rng = random.Random(2026)
    runner = {**{slug: ids(slug) for slug, *_ in CROWD}, **existing}
    paces = {slug: (pace_min, pace_max) for slug, _, _, pace_min, pace_max, *_ in CROWD}

    for slug, name, bio, pace_min, pace_max, experience, area, availability, north, east in CROWD:
        jitter = random.Random(slug)
        save_profile(headers_for(runner[slug]), {
            'name': name, 'bio': bio, 'paceMin': pace_min, 'paceMax': pace_max, 'experience': experience, 'area': area,
            'availability': availability,
            'latitude': round(RAY_CELL[0] + north * 0.01 + jitter.uniform(-0.003, 0.003), 4),
            'longitude': round(RAY_CELL[1] + east * 0.01 + jitter.uniform(-0.003, 0.003), 4)})
    for slug in runner:
        add_avatar(headers_for(runner[slug]), AVATARS / f'{slug}.png')

    now = datetime.now(timezone.utc)
    with database('scheduling') as scheduling, database('reputation') as reputation:
        for slug, organizer, title, place, lat, lng, days, hour, km, pace, runners in PAST_RUNS:
            run_id = str(uuid5(NAMESPACE, 'run:' + slug))
            starts = (datetime.now(ICT) - timedelta(days=days)).replace(hour=hour, minute=0, second=0, microsecond=0)
            weather = {'temperature': 28, 'humidity': 68, 'rainChance': 10, 'pm25': 18, 'level': 'great', 'label': 'Historical demo fixture',
                       'updatedAt': starts.isoformat(), 'stale': True, 'provider': 'prepared past-run fixture'}
            scheduling.execute('''INSERT INTO runs(id,organizer_id,title,meeting_point,latitude,longitude,starts_at,ends_at,distance_km,pace,participant_limit,weather,status)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,'completed') ON CONFLICT(id) DO NOTHING''',
                (run_id, runner[organizer], title, place, lat, lng, starts, starts + timedelta(hours=1), km, pace, 10, Jsonb(weather)))
            for slug_a in runners:
                scheduling.execute('INSERT INTO participants(run_id,runner_id,attendance_confirmed) VALUES (%s,%s,true) ON CONFLICT DO NOTHING', (run_id, runner[slug_a]))
                reputation.execute('INSERT INTO attendances(run_id,runner_id,created_at,updated_at) VALUES (%s,%s,%s,%s) ON CONFLICT DO NOTHING', (run_id, runner[slug_a], starts, starts))
                distance = int(km * 1000 * rng.uniform(0.98, 1.05))
                seconds_per_km = rng.uniform(*paces.get(slug_a, (6, 7))) * 60
                log_run(reputation, run_id, runner[slug_a], distance, int(distance / 1000 * seconds_per_km), starts + timedelta(hours=1))
                for slug_b in runners:
                    if slug_b != slug_a:
                        reputation.execute('''INSERT INTO participant_ratings(run_id,rater_id,ratee_id,punctuality,pace_accuracy,friendliness,created_at,updated_at)
                            VALUES (%s,%s,%s,%s,%s,%s,%s,%s) ON CONFLICT DO NOTHING''',
                            (run_id, runner[slug_a], runner[slug_b], rng.choice([4, 5, 5]), rng.choice([3, 4, 5]), rng.choice([4, 5, 5]), starts, starts))

        # Solo runs logged without a group run, so running totals differ from runner to runner.
        for slug in runner:
            for index in range(6 if slug == 'nok' else rng.randint(1, 4)):
                distance = rng.choice([3000, 5000, 5000, 7000, 8000, 10000, 12000])
                seconds_per_km = rng.uniform(*paces.get(slug, (6, 7))) * 60
                log_run(reputation, str(uuid5(NAMESPACE, f'solo:{slug}:{index}')), runner[slug], distance, int(distance / 1000 * seconds_per_km),
                        now - timedelta(days=rng.randint(1, 30), hours=rng.randint(0, 12)))

        today = datetime.now(ICT).replace(second=0, microsecond=0)
        for slug, organizer, title, place, lat, lng, days, hour, minute, km, pace, limit, runners in UPCOMING_RUNS:
            run_id = str(uuid5(NAMESPACE, 'run:' + slug))
            start = (today + timedelta(days=days)).replace(hour=hour, minute=minute)
            forecast = {'temperature': 29, 'humidity': 65, 'rainChance': 20, 'pm25': 15, 'level': 'great', 'label': 'Demo forecast',
                        'updatedAt': today.isoformat(), 'stale': True, 'provider': 'seed fixture'}
            scheduling.execute('''INSERT INTO runs(id,organizer_id,title,meeting_point,latitude,longitude,starts_at,ends_at,distance_km,pace,participant_limit,weather)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                ON CONFLICT(id) DO UPDATE SET starts_at=EXCLUDED.starts_at,ends_at=EXCLUDED.ends_at,weather=EXCLUDED.weather''',
                (run_id, runner[organizer], title, place, lat, lng, start, start + timedelta(hours=1), km, pace, limit, Jsonb(forecast)))
            for slug_a in runners:
                scheduling.execute('INSERT INTO participants(run_id,runner_id) VALUES (%s,%s) ON CONFLICT DO NOTHING', (run_id, runner[slug_a]))

    with database('discovery') as discovery:
        for index, (slug, days) in enumerate(NOK_BUDDIES):
            # Alternate who asked, so Nok's Activity shows requests she sent and ones she accepted.
            sender, recipient = (NOK, runner[slug]) if index % 2 == 0 else (runner[slug], NOK)
            asked = now - timedelta(days=days, hours=3)
            discovery.execute('''INSERT INTO buddy_requests(id,sender_id,recipient_id,status,note,created_at,updated_at)
                VALUES (%s,%s,%s,'accepted',%s,%s,%s) ON CONFLICT(id) DO NOTHING''',
                (str(uuid5(NAMESPACE, 'request:' + slug)), sender, recipient, 'Want to run together this week?', asked, asked + timedelta(hours=3)))
            pair = sorted([NOK, runner[slug]])
            discovery.execute('INSERT INTO buddy_relationships(runner_a,runner_b,created_at,updated_at) VALUES (%s,%s,%s,%s) ON CONFLICT DO NOTHING',
                              (pair[0], pair[1], asked + timedelta(hours=3), asked + timedelta(hours=3)))
        slug, note = PENDING_TO_NOK
        discovery.execute('''INSERT INTO buddy_requests(id,sender_id,recipient_id,status,note,created_at,updated_at)
            VALUES (%s,%s,%s,'pending',%s,%s,%s) ON CONFLICT DO NOTHING''',
            (str(uuid5(NAMESPACE, 'request:' + slug)), runner[slug], NOK, note, now - timedelta(hours=5), now - timedelta(hours=5)))

    print(f'Seeded the demo community: {len(CROWD)} runners with avatars, Nok (nok@example.com / runner123) with '
          f'{len(NOK_BUDDIES)} buddies, {len(PAST_RUNS)} finished and {len(UPCOMING_RUNS)} upcoming group runs, ratings and running records.')


def save_profile(headers, profile):
    url = os.environ['PROFILE_URL'] + '/api/v1/me/profile'
    if httpx.get(url, headers=headers, timeout=10).status_code == 404:
        httpx.put(url, headers=headers, timeout=10, json=profile).raise_for_status()


def add_avatar(headers, image):
    """Uploads through Profile's own photo flow, once: request a signed URL, store the file, attach it."""
    base = os.environ['PROFILE_URL'] + '/api/v1/me/profile'
    profile = httpx.get(base, headers=headers, timeout=10)
    if profile.status_code != 200 or profile.json().get('photoUrl') or not image.exists():
        return
    upload = httpx.post(base + '/photo-uploads', headers=headers, timeout=10)
    upload.raise_for_status()
    # The URL is signed for the public storage host, which this container may not reach. The signature
    # covers the Host header, not the address, so send it to the storage service under that host name.
    signed = urlsplit(upload.json()['uploadUrl'])
    storage = os.environ.get('PROFILE_STORAGE_URL', 'http://profile-storage:9000')
    stored = httpx.put(f'{storage}{signed.path}?{signed.query}', content=image.read_bytes(), timeout=30,
                       headers={'Host': signed.netloc, 'Content-Type': 'image/png'})
    stored.raise_for_status()
    httpx.put(base + '/photo', headers=headers, timeout=10, json={'photoRef': upload.json()['photoRef']}).raise_for_status()


def log_run(reputation, run_id, runner_id, distance, duration, at):
    reputation.execute('''INSERT INTO running_records(run_id,runner_id,distance_meters,duration_seconds,occurred_at,created_at,updated_at)
        VALUES (%s,%s,%s,%s,%s,%s,%s) ON CONFLICT DO NOTHING''', (run_id, runner_id, distance, duration, at, at, at))
