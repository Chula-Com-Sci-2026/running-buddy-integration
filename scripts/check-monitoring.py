"""Verify actual viewer permissions, not merely pgweb's read-only UI switch."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
values = dict(line.split('=',1) for line in (root/'.env').read_text().splitlines() if '=' in line and not line.startswith('#'))

def query(database, sql):
    return subprocess.run(['docker','compose','exec','-T','-e','PGPASSWORD='+values['DEMO_VIEWER_PASSWORD'],'postgres','psql','-X','-h','127.0.0.1','-U','demo_viewer','-d',database,'-v','ON_ERROR_STOP=1','-tAc',sql],capture_output=True,text=True,cwd=root)

for database,table in [('identity_team','users'),('profile','profiles'),('discovery','buddy_requests'),('scheduling','runs'),('reputation','running_records'),('notification','notifications')]:
    result=query(database,f'SELECT count(*) FROM demo_monitor.{table}')
    assert result.returncode == 0, f'Cannot read approved view for {database}'
    permissions=query(database,f"SELECT has_table_privilege('demo_viewer','public.{table}','SELECT'),has_table_privilege('demo_viewer','demo_monitor.{table}','UPDATE')")
    assert permissions.returncode == 0 and permissions.stdout.strip() == 'f|f', f'Unexpected table permissions for {database}'
    blocked=query(database,f'SET transaction_read_only=off; UPDATE demo_monitor.{table} SET id=id WHERE false')
    assert blocked.returncode != 0, f'Viewer can write {database}'
secret=query('identity_team','SELECT password_hash FROM public.users LIMIT 1')
assert secret.returncode != 0, 'Viewer can read raw credential table'
print('PASS: six service views readable; direct table access and writes denied; credential hashes inaccessible.')
