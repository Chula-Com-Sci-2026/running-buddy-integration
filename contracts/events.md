# Buddy notification events, version 1

Exchange `cra.events`, type `topic`, durable. Routing key equals `eventType`.

```json
{
  "eventId": "UUID",
  "eventType": "BuddyRequestSent",
  "version": 1,
  "occurredAt": "ISO-8601 UTC timestamp",
  "correlationId": "UUID",
  "payload": {
    "requestId": "UUID",
    "senderId": "UUID",
    "recipientId": "UUID",
    "status": "pending"
  }
}
```

`BuddyRequestAnswered` has the same shape and `status` is `accepted` or `rejected`. Notification targets `recipientId` for sent events and `senderId` for answered events. Delivery is at least once. Notification's unique `(event_id, recipient_id)` constraint deduplicates after retries. Acknowledgement occurs only after database commit. Invalid messages are rejected to exchange `cra.dead` / queue `notifications.dead`; database failures close/reconnect the channel with a three-second retry delay so unacknowledged messages requeue.

Discovery writes outbox events atomically with request creation/response and retries publishing every two seconds. Failed or unrouted publishes leave `published_at` null. The local publisher uses RabbitMQ's management publish API, persistent messages and positive routing acknowledgement. Consumers must be provisioned before events can leave the outbox.
