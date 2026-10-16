"""Operator probe used before/after normal postgres and redis container restarts."""
import json
from pathlib import Path
import sys
import redis
from seed import database,RUNNER_A

cache=redis.Redis(host='redis',decode_responses=True)
key='delivery4:persistence-proof'
state=Path('/contracts/persistence-proof.json')
if sys.argv[1]=='before':
    cache.setex(key,1800,'real Redis AOF persistence')
    with database('identity') as connection:
        count=connection.execute('SELECT count(*) FROM accounts WHERE id=%s',(RUNNER_A,)).fetchone()[0]
    assert count==1
    state.write_text(json.dumps({'accountId':RUNNER_A,'redisKey':key}))
    print('Prepared persisted PostgreSQL account and Redis key; restart databases normally without deleting volumes.')
else:
    proof=json.loads(state.read_text())
    with database('identity') as connection:
        assert connection.execute('SELECT count(*) FROM accounts WHERE id=%s',(proof['accountId'],)).fetchone()[0]==1
    assert cache.get(proof['redisKey'])=='real Redis AOF persistence'
    print('PASS: PostgreSQL account and Redis AOF key survived container restarts.')
