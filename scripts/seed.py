"""Operator-only demo seed. Never imported by an application service."""
import os
from datetime import datetime,timedelta,timezone
from uuid import UUID
import httpx
import jwt
import psycopg
from psycopg.types.json import Jsonb
from argon2 import PasswordHasher

RUNNER_A='11111111-1111-4111-8111-111111111111'
RUNNER_B='22222222-2222-4222-8222-222222222222'
# Profiles only: their accounts come from the team Identity seed. Their pace ranges overlap Ray's, and
# neither is his buddy, so Home's strongest matches has someone to show.
RUNNER_C='44444444-4444-4444-8444-444444444444'
RUNNER_D='55555555-5555-4555-8555-555555555555'
PAST_RUN='33333333-3333-4333-8333-333333333333'

def database(name):
    user="identity" if name.startswith("identity_team") else name
    return psycopg.connect(f"postgresql://{user}:{os.environ['DB_PASSWORD']}@postgres:5432/{name}")

def main():
    if os.getenv('IDENTITY_BACKEND') != 'team':
        with database('identity') as connection:
            for subject,email,phone in [(RUNNER_A,'ray@example.com','+66811111111'),(RUNNER_B,'mali@example.com','+66822222222')]:
                connection.execute('INSERT INTO accounts(id,email,phone,password_hash,phone_verified) VALUES (%s,%s,%s,%s,true) ON CONFLICT(id) DO NOTHING',(subject,email,phone,PasswordHasher().hash('runner123')))
    # Profiles go through Profile's own API, so the service writes its outbox and publishes ProfileUpdated.
    profiles=[(RUNNER_A,{'name':'Ray Attajak','bio':'Evening runner','paceMin':6,'paceMax':7,'experience':'Intermediate','area':'Lumphini Park','availability':'Evenings','latitude':13.730,'longitude':100.541}),
              (RUNNER_B,{'name':'Mali S.','bio':'Evening runner','paceMin':6,'paceMax':7,'experience':'Intermediate','area':'Lumphini Park','availability':'Evenings','latitude':13.731,'longitude':100.541}),
              (RUNNER_C,{'name':'Narin K.','bio':'Easy miles on weekdays, longer runs when Bangkok is still quiet.','paceMin':5.5,'paceMax':6.5,'experience':'Advanced','area':'Benjakitti Park','availability':'Weekday mornings','latitude':13.729,'longitude':100.558}),
              (RUNNER_D,{'name':'Pim C.','bio':'Building a first 10K habit. Friendly pace and plenty of water breaks.','paceMin':6.5,'paceMax':7.5,'experience':'Beginner','area':'Chulalongkorn University','availability':'Weekends','latitude':13.738,'longitude':100.528})]
    for subject,profile in profiles:
        now=datetime.now(timezone.utc)
        token=jwt.encode({'sub':subject,'iss':'cant-run-alone-local','aud':'cant-run-alone-services','iat':now,'exp':now+timedelta(minutes=5)},os.environ['JWT_SECRET'],algorithm='HS256')
        headers={'Authorization':f'Bearer {token}'}
        profile_url=os.environ['PROFILE_URL']+'/api/v1/me/profile'
        if httpx.get(profile_url,headers=headers,timeout=10).status_code==404:
            httpx.put(profile_url,headers=headers,timeout=10,json=profile).raise_for_status()
    starts=datetime.now(timezone.utc)-timedelta(days=1)
    weather={'temperature':29,'humidity':65,'rainChance':20,'pm25':15,'level':'great','label':'Historical demo fixture','updatedAt':starts.isoformat(),'stale':True,'provider':'prepared past-run fixture'}
    with database('scheduling') as connection:
        connection.execute('INSERT INTO runs(id,organizer_id,title,meeting_point,latitude,longitude,starts_at,ends_at,distance_km,pace,participant_limit,weather) VALUES (%s,%s,%s,%s,13.730,100.541,%s,%s,5,%s,5,%s) ON CONFLICT(id) DO NOTHING',(PAST_RUN,RUNNER_A,'Prepared past run — attendance demo','Lumphini Park Gate 1',starts,starts+timedelta(hours=1),'6–7',Jsonb(weather)))
        for subject in (RUNNER_A,RUNNER_B):
            connection.execute('INSERT INTO participants(run_id,runner_id) VALUES (%s,%s) ON CONFLICT DO NOTHING',(PAST_RUN,subject))
    print('Seeded Ray and Mali (password: runner123), profiles for Ray, Mali, Narin and Pim, and a prepared past run. Existing data preserved.')

if __name__=='__main__':main()
