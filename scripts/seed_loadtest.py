"""Operator-only load-test dataset (k6). Never imported by an application service.

Adds, without touching existing rows:
  * LOADTEST_PROFILES runner profiles (default 10,000; NFR-1.1 dataset size) around Bangkok,
  * LOADTEST_ACCOUNTS of them as verified team-Identity accounts (default 5,000; NFR-2.1),
  * LOADTEST_RUNS upcoming public runs (default 200) with load-test participants.

Every row has a deterministic UUIDv5 in a dedicated namespace plus a visible fixture marker, and
inserts use ON CONFLICT DO NOTHING, so re-running is a no-op and demo data (Ray, Mali, their runs)
is never overwritten. `--remove` deletes only rows carrying both the namespace ID and the marker.
`--reschedule` moves only the load-test runs forward again if they have started.

Usage (inside the cluster): k8s/scripts/run-tool.sh python seed_loadtest.py [--remove|--reschedule]
"""
import math
import os
import random
import sys
from datetime import datetime, timedelta, timezone
from uuid import NAMESPACE_URL, uuid5
import bcrypt
from psycopg.types.json import Jsonb
from seed import database

NAMESPACE = uuid5(NAMESPACE_URL, 'https://github.com/Chula-Com-Sci-2026/running-buddy/k6-load-test')
MARKER = 'k6 load-test fixture'
EMAIL_DOMAIN = 'loadtest.example.com'
PROFILES = int(os.getenv('LOADTEST_PROFILES', '10000'))
ACCOUNTS = int(os.getenv('LOADTEST_ACCOUNTS', '5000'))
RUNS = int(os.getenv('LOADTEST_RUNS', '200'))
PASSWORD = os.getenv('LOADTEST_PASSWORD', 'k6-runner-pass')  # local fixture credential only
CENTER = (13.7563, 100.5018)  # Bangkok
RADIUS_KM = 15
AREAS = ['Lumphini Park', 'Benchakitti Park', 'Chatuchak Park', 'Rot Fai Park', 'Suan Luang Rama IX',
         'Bang Krachao', 'Chulalongkorn Centenary Park', 'Benjasiri Park', 'Santiphap Park', 'Wachirabenchathat Park']
AVAILABILITY = ['Mornings', 'Evenings', 'Weekends', 'Weekday mornings', 'Weekend evenings', 'Evenings, weekends']
EXPERIENCE = ['Beginner'] * 4 + ['Intermediate'] * 4 + ['Advanced'] * 2


def profile_id(index): return uuid5(NAMESPACE, f'profile-{index}')
def run_id(index): return uuid5(NAMESPACE, f'run-{index}')
def email(index): return f'k6-runner-{index:05d}@{EMAIL_DOMAIN}'


def point(rng):
    # Uniform over a disc: realistic density falls off at the edge of the city, not at a square.
    distance = RADIUS_KM * math.sqrt(rng.random())
    bearing = rng.random() * 2 * math.pi
    lat = CENTER[0] + distance / 111.32 * math.cos(bearing)
    lon = CENTER[1] + distance / (111.32 * math.cos(math.radians(CENTER[0]))) * math.sin(bearing)
    return round(lat, 5), round(lon, 5)


def profiles(rng):
    for index in range(PROFILES):
        lat, lon = point(rng)
        pace_min = round(rng.uniform(4.5, 8.0) * 2) / 2
        yield (profile_id(index), f'Load Runner {index:05d}', MARKER, pace_min, pace_min + rng.choice([0.5, 1, 1.5]),
               rng.choice(EXPERIENCE), rng.choice(AREAS), rng.choice(AVAILABILITY), lat, lon)


def run_rows(rng, now):
    weather = {'temperature': 29, 'humidity': 70, 'rainChance': 20, 'pm25': 18, 'level': 'great',
               'label': 'Load-test fixture', 'updatedAt': now.isoformat(), 'stale': True, 'provider': MARKER}
    for index in range(RUNS):
        lat, lon = point(rng)
        starts = run_start(index, now)
        organizer = profile_id(rng.randrange(ACCOUNTS))
        others = {profile_id(rng.randrange(ACCOUNTS)) for _ in range(rng.randint(0, 4))} - {organizer}
        yield ((run_id(index), organizer, f'{MARKER} run {index:03d}', f'{rng.choice(AREAS)} meeting point', lat, lon,
                starts, starts + timedelta(hours=1), rng.choice([3, 5, 8, 10, 15]), '6–7', rng.choice([4, 6, 8, 10]), Jsonb(weather)),
               [organizer, *sorted(others)])


def run_start(index, now):
    # Two to fourteen days ahead, at the NFR-2.2 peak hours: 05:00-07:00 and 17:00-20:00 Bangkok
    # time, i.e. 22:00-23:00 and 10:00-12:00 UTC.
    day = now.replace(hour=0, minute=0, second=0, microsecond=0) + timedelta(days=2 + index % 13)
    return day + timedelta(hours=[22, 23, 10, 11, 12][index % 5])


def seed():
    if ACCOUNTS > PROFILES:
        sys.exit('LOADTEST_ACCOUNTS cannot exceed LOADTEST_PROFILES')
    rng = random.Random(20261031)  # fixed seed: the same dataset every time
    now = datetime.now(timezone.utc)
    password_hash = bcrypt.hashpw(PASSWORD.encode(), bcrypt.gensalt(12)).decode()
    with database('identity_team') as connection, connection.cursor() as cursor:
        cursor.executemany('INSERT INTO users(id,email,phone_number,password_hash,is_phone_verified) VALUES (%s,%s,%s,%s,true) ON CONFLICT DO NOTHING',
                           [(profile_id(i), email(i), f'+669{i:08d}', password_hash) for i in range(ACCOUNTS)])
    with database('profile') as connection, connection.cursor() as cursor:
        # Team Profile schema: revision 1 for a fresh row. Fixtures bypass Profile's outbox on purpose,
        # so 10,000 ProfileUpdated events are not queued.
        cursor.executemany('INSERT INTO profiles(id,name,bio,pace_min,pace_max,experience,area,availability,latitude,longitude,revision) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,1) ON CONFLICT DO NOTHING',
                           list(profiles(rng)))
    with database('scheduling') as connection, connection.cursor() as cursor:
        for run, participants in run_rows(rng, now):
            cursor.execute('INSERT INTO runs(id,organizer_id,title,meeting_point,latitude,longitude,starts_at,ends_at,distance_km,pace,participant_limit,weather) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) ON CONFLICT DO NOTHING', run)
            cursor.executemany('INSERT INTO participants(run_id,runner_id) VALUES (%s,%s) ON CONFLICT DO NOTHING', [(run[0], p) for p in participants])
    report()


def reschedule():
    now = datetime.now(timezone.utc)
    with database('scheduling') as connection:
        moved = 0
        for index in range(RUNS):
            starts = run_start(index, now)
            moved += connection.execute('UPDATE runs SET starts_at=%s, ends_at=%s WHERE id=%s AND title LIKE %s AND starts_at<%s',
                                        (starts, starts + timedelta(hours=1), run_id(index), MARKER + '%', now + timedelta(days=1))).rowcount
    print(f'Rescheduled {moved} load-test runs; demo runs untouched.')
    report()


def remove():
    profile_ids = [profile_id(i) for i in range(max(PROFILES, ACCOUNTS))]
    run_ids = [run_id(i) for i in range(RUNS)]
    with database('scheduling') as connection:
        connection.execute('DELETE FROM participants WHERE run_id IN (SELECT id FROM runs WHERE id = ANY(%s) AND title LIKE %s)', (run_ids, MARKER + '%'))
        runs = connection.execute('DELETE FROM runs WHERE id = ANY(%s) AND title LIKE %s', (run_ids, MARKER + '%')).rowcount
    with database('profile') as connection:
        profiles_removed = connection.execute('DELETE FROM profiles WHERE id = ANY(%s) AND bio = %s', (profile_ids, MARKER)).rowcount
    with database('identity_team') as connection:
        users = connection.execute('DELETE FROM users WHERE id = ANY(%s) AND email LIKE %s', (profile_ids, '%@' + EMAIL_DOMAIN)).rowcount
    print(f'Removed {users} load-test accounts, {profiles_removed} profiles and {runs} runs; other rows untouched.')
    report()


def report():
    with database('profile') as connection:
        total, fixtures = connection.execute('SELECT count(*), count(*) FILTER (WHERE bio=%s) FROM profiles', (MARKER,)).fetchone()
    with database('identity_team') as connection:
        users, load_users = connection.execute('SELECT count(*), count(*) FILTER (WHERE email LIKE %s) FROM users', ('%@' + EMAIL_DOMAIN,)).fetchone()
    with database('scheduling') as connection:
        upcoming, load_runs = connection.execute('SELECT count(*) FILTER (WHERE starts_at>now()), count(*) FILTER (WHERE title LIKE %s AND starts_at>now()) FROM runs', (MARKER + '%',)).fetchone()
    print(f'dataset profiles_total={total} profiles_loadtest={fixtures} users_total={users} users_loadtest={load_users} '
          f'upcoming_runs_total={upcoming} upcoming_runs_loadtest={load_runs}')


if __name__ == '__main__':
    {'--remove': remove, '--reschedule': reschedule, '--report': report}.get(sys.argv[1] if len(sys.argv) > 1 else '', seed)()
