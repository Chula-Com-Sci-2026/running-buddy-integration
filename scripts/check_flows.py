"""End-to-end test against running services and real local data stores."""
import json
import os
import time
from datetime import datetime,timedelta,timezone
from uuid import uuid4
import httpx
import redis
from psycopg.rows import dict_row
from seed import database,RUNNER_A,RUNNER_B,PAST_RUN

BASE='http://gateway:8000/api/v1'

def expect(response,status=200):
    assert response.status_code==status,(response.status_code,response.text)
    return response.json() if response.content else None

def login(email):
    client=httpx.Client(base_url=BASE,timeout=35)
    result=expect(client.post('/auth/login',json={'email':email,'password':'runner123'}))
    client.headers['Authorization']='Bearer '+result['accessToken']
    return client

def main():
    alice,bob=login('ray@example.com'),login('mali@example.com')
    assert httpx.get(BASE+'/runs').status_code==401
    assert expect(alice.get('/me/profile'))['id']==RUNNER_A
    assert any(row['id']==RUNNER_B for row in expect(alice.get('/runners?radiusKm=5')))
    # Unique request pair per run, real verified accounts and API-created profiles.
    from argon2 import PasswordHasher
    subjects=[str(uuid4()),str(uuid4())]
    clients=[]
    with database('identity') as connection:
        for subject in subjects:
            connection.execute('INSERT INTO accounts(id,email,phone,password_hash,phone_verified) VALUES (%s,%s,%s,%s,true)',(subject,subject+'@example.com','+66'+str(int(uuid4().hex[:12],16))[-9:],PasswordHasher().hash('runner123')))
    for index,subject in enumerate(subjects):
        client=login(subject+'@example.com')
        expect(client.put('/me/profile',json={'name':f'Integration Runner {index}','bio':'Integration check','paceMin':6,'paceMax':7,'experience':'Intermediate','area':'Lumphini','availability':'Evenings','latitude':13.73,'longitude':100.541}))
        clients.append(client)
    sender,recipient=clients
    request=expect(sender.post('/buddy-requests',json={'runnerId':subjects[1]}),201)
    duplicate=sender.post('/buddy-requests',json={'runnerId':subjects[1]})
    assert duplicate.status_code in (409,422)
    assert sender.patch('/buddy-requests/'+request['id'],json={'decision':'accepted'}).status_code==403
    deadline=time.monotonic()+25
    while time.monotonic()<deadline:
        notifications=expect(recipient.get('/notifications'))
        if any(row['payload']['requestId']==request['id'] for row in notifications):break
        time.sleep(.5)
    else:raise AssertionError('Broker notification was not delivered')
    expect(recipient.patch('/buddy-requests/'+request['id'],json={'decision':'accepted'}))
    assert subjects[1] in expect(sender.get('/buddies'))
    with database('discovery') as connection:
        assert connection.execute('SELECT status FROM buddy_requests WHERE id=%s',(request['id'],)).fetchone()[0]=='accepted'
    # Live provider -> Redis miss/hit -> persisted future run and real join.
    at=(datetime.now(timezone.utc)+timedelta(days=1)).replace(hour=11,minute=0,second=0,microsecond=0)
    params={'latitude':13.73,'longitude':100.541,'at':at.isoformat()}
    forecast=expect(alice.get('/conditions',params=params))
    cached=expect(alice.get('/conditions',params=params))
    assert cached['cacheHit'] and forecast['provider']=='Open-Meteo / CAMS'
    cache=redis.Redis(host='redis',decode_responses=True)
    assert cache.get(cached['cacheKey']) and 0<cache.ttl(cached['cacheKey'])<=900
    bangkok=at+timedelta(hours=7)
    run=expect(alice.post('/runs',json={'title':'Integration live weather run','meetingPoint':'Lumphini Park Gate 1','latitude':13.73,'longitude':100.541,'date':bangkok.strftime('%Y-%m-%d'),'time':bangkok.strftime('%H:%M'),'distanceKm':5,'pace':'6–7','participantLimit':2,'visibility':'Public'}),201)
    expect(bob.put('/runs/'+run['id']+'/participants/me'))
    assert expect(bob.get('/runs/'+run['id']))['participants']==2
    # Prepared past-run flow. Repeatable confirmations, unique new completed run for rating/record assertions.
    with database('scheduling') as connection:
        past=str(uuid4())
        connection.execute('INSERT INTO runs SELECT %s,organizer_id,title,meeting_point,latitude,longitude,starts_at,ends_at,distance_km,pace,participant_limit,\'scheduled\',weather,now() FROM runs WHERE id=%s',(past,PAST_RUN))
        for subject in (RUNNER_A,RUNNER_B):connection.execute('INSERT INTO participants(run_id,runner_id) VALUES (%s,%s)',(past,subject))
    assert alice.post('/runs/'+past+'/ratings',json={'rateeId':RUNNER_B,'punctuality':5,'paceAccuracy':5,'friendliness':5}).status_code==403
    assert expect(alice.post('/runs/'+past+'/attendance'))['status']=='attendance_open'
    assert expect(bob.post('/runs/'+past+'/attendance'))['status']=='completed'
    expect(alice.post('/runs/'+past+'/ratings',json={'rateeId':RUNNER_B,'punctuality':5,'paceAccuracy':4,'friendliness':5}),201)
    assert alice.post('/runs/'+past+'/ratings',json={'rateeId':RUNNER_B,'punctuality':5,'paceAccuracy':4,'friendliness':5}).status_code in (409,422)
    record=expect(alice.post('/running_records',json={'running_record':{'run_id':past,'runner_id':RUNNER_B,'distance_meters':5000,'duration_seconds':1800,'occurred_at':datetime.now(timezone.utc).isoformat()}}),201)
    assert record['runner_id']==RUNNER_A
    assert bob.get('/running_records/'+record['id']).status_code==404
    history=expect(alice.get('/me/history'))
    assert any(row['id']==record['id'] for row in history['records'])
    print(json.dumps({'result':'PASS','flows':['authentication','gRPC search/request/accept','RabbitMQ notification','live forecast and Redis hit','schedule/join','attendance/rating/record/history'],'requestId':request['id'],'runId':run['id'],'recordId':record['id'],'redisKey':cached['cacheKey']},indent=2))

if __name__=='__main__':main()
