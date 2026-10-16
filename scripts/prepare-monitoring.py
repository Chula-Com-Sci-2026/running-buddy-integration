"""Provision narrow live database views for recording; never grant application-role privileges."""
from pathlib import Path
import os
import re
import secrets
import subprocess

root = Path(__file__).resolve().parents[1]
env_path = root / '.env'
values = dict(line.split('=', 1) for line in env_path.read_text().splitlines() if '=' in line and not line.startswith('#'))
if 'DEMO_VIEWER_PASSWORD' not in values:
    values['DEMO_VIEWER_PASSWORD'] = secrets.token_hex(32)
    env_path.write_text(env_path.read_text().rstrip() + '\nDEMO_VIEWER_PASSWORD=' + values['DEMO_VIEWER_PASSWORD'] + '\n')
    env_path.chmod(0o600)
password = values['DEMO_VIEWER_PASSWORD']
if not re.fullmatch(r'[0-9a-f]{64}', password):
    raise SystemExit('DEMO_VIEWER_PASSWORD must be 64 hexadecimal characters')

views = {
    'identity_team': {'users': 'id,email,is_email_verified,is_phone_verified,is_locked,created_at'},
    'identity': {'accounts': 'id,email,phone_verified,created_at'},
    'profile': {'profiles': 'id,name,pace_min,pace_max,experience,area,availability,updated_at'},
    'discovery': {
        'buddy_requests': 'id,sender_id,recipient_id,status,created_at,updated_at',
        'buddy_relationships': 'id,runner_a,runner_b,created_at',
        'outbox_events': 'id,event_type,published_at,created_at',
    },
    'scheduling': {
        'runs': 'id,organizer_id,title,meeting_point,starts_at,ends_at,distance_km,pace,participant_limit,status,created_at',
        'participants': 'run_id,runner_id,attendance_confirmed',
    },
    'reputation': {
        'attendances': 'id,run_id,runner_id,created_at',
        'participant_ratings': 'id,run_id,rater_id,ratee_id,punctuality,pace_accuracy,friendliness,created_at',
        'running_records': 'id,run_id,runner_id,distance_meters,duration_seconds,occurred_at,created_at',
    },
    'notification': {'notifications': 'id,event_id,recipient_id,type,is_read,created_at'},
}

def psql(database, sql, password_var=False):
    command = ['docker','compose','exec','-T','postgres','psql','-X','-U','postgres','-d',database,'-v','ON_ERROR_STOP=1']
    if password_var:
        command += ['-v', 'viewer_password=' + password]
    result = subprocess.run(command, input=sql, text=True, capture_output=True, cwd=root)
    if result.returncode:
        # Never print potentially sensitive SQL/connection configuration from failed provisioning.
        raise SystemExit(f'Monitoring setup failed for {database}; check the database exists and migrations have run')

psql('postgres', """
DO $$ BEGIN
 IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='demo_viewer') THEN
  CREATE ROLE demo_viewer LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION;
 END IF;
END $$;
ALTER ROLE demo_viewer PASSWORD :'viewer_password';
ALTER ROLE demo_viewer SET default_transaction_read_only=on;
ALTER ROLE demo_viewer SET statement_timeout='10s';
""", password_var=True)
for database, tables in views.items():
    # Fallback and optional team database may not both exist in a brand-new workspace.
    query = subprocess.run(['docker','compose','exec','-T','postgres','psql','-X','-U','postgres','-d','postgres','-tAc',f"SELECT 1 FROM pg_database WHERE datname='{database}'"],capture_output=True,text=True,cwd=root,check=True)
    if query.stdout.strip() != '1':
        continue
    statements = ['CREATE SCHEMA IF NOT EXISTS demo_monitor;', 'REVOKE ALL ON SCHEMA demo_monitor FROM PUBLIC;', 'GRANT USAGE ON SCHEMA demo_monitor TO demo_viewer;', f'ALTER ROLE demo_viewer IN DATABASE {database} SET search_path=demo_monitor,pg_catalog;']
    for table, columns in tables.items():
        statements += [f'CREATE OR REPLACE VIEW demo_monitor.{table} AS SELECT {columns} FROM public.{table};', f'GRANT SELECT ON demo_monitor.{table} TO demo_viewer;']
    psql(database, '\n'.join(statements))
print('Prepared read-only live views. Credential hashes, tokens, OTPs and private profile coordinates are excluded.')
