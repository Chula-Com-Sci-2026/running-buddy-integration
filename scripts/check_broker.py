"""Publish real duplicate deliveries and a poison event; verify dedup and dead-letter routing."""
import json,os,time
from uuid import uuid4
import pika
from seed import database,RUNNER_A,RUNNER_B
connection=pika.BlockingConnection(pika.URLParameters(os.environ['AMQP_URL']))
channel=connection.channel()
channel.confirm_delivery()
event={'eventId':str(uuid4()),'eventType':'BuddyRequestSent','version':1,'occurredAt':'2026-10-16T00:00:00Z','correlationId':str(uuid4()),'payload':{'recipientId':RUNNER_B,'senderId':RUNNER_A,'requestId':str(uuid4()),'status':'pending'}}
for _ in range(2):
 channel.basic_publish(exchange='cra.events',routing_key='BuddyRequestSent',body=json.dumps(event),mandatory=True,properties=pika.BasicProperties(delivery_mode=2))
channel.basic_publish(exchange='cra.events',routing_key='BuddyRequestSent',body='invalid-json',mandatory=True,properties=pika.BasicProperties(delivery_mode=2))
deadline=time.monotonic()+15
while time.monotonic()<deadline:
 with database('notification') as database_connection:
  count=database_connection.execute('SELECT count(*) FROM notifications WHERE event_id=%s',(event['eventId'],)).fetchone()[0]
 dead=channel.queue_declare(queue='notifications.dead',passive=True).method.message_count
 if count==1 and dead>=1:
  time.sleep(.5)
  with database('notification') as database_connection:
   assert database_connection.execute('SELECT count(*) FROM notifications WHERE event_id=%s',(event['eventId'],)).fetchone()[0]==1
  print('PASS: two real broker deliveries produce one notification; invalid JSON is dead-lettered.')
  break
 time.sleep(.25)
else:raise AssertionError('Broker dedup/dead-letter verification failed')
connection.close()
