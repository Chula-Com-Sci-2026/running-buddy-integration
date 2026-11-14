# Demo day runbook

Follows the demo script slide: Auth, then UC-02, UC-03 and UC-04. Every step was rehearsed against
this stack on 14 Nov 2026.

## Before the demo

```sh
sh scripts/reset-demo.sh          # wipes ALL local data, starts the stack, seeds it (a few minutes)
cd ../cant-run-alone-frontend && npm run dev
```

Run the reset after the last rehearsal, so requests, runs, ratings and sign-ups from the rehearsal
are gone. Re-seeding also moves the upcoming runs forward from today. Then open two browser
windows (one private) and keep a terminal on the OTP log:

```sh
docker compose -f compose.yaml -f compose.team-identity.yaml logs -f identity | grep "CONSOLE OTP"
```

Run Conditions calls the live weather provider, so the laptop needs internet.

| Who | Email | Password |
|---|---|---|
| Ray (window 1) | `ray@example.com` | `runner123` |
| Mali (window 2) | `mali@example.com` | `runner123` |

After a reset, Ray and Mali are not buddies, have no requests, no ratings and no running records.

## Auth: register and log in

1. Window 1, **Create account**: any new email (e.g. `demo@example.com`), a new phone
   (e.g. `+66812345678`), password of 8+ characters, consent.
2. The code appears in the OTP log as `[LOCAL CONSOLE OTP] phone=… code=123456 (not an SMS delivery)`.
   Say so: the console adapter stands in for SMS. The code expires after 5 minutes.
3. Verify, then sign out and **log in as Ray** for the rest of the demo.

Each email and phone registers once; use a new pair for each rehearsal or reset first.

## UC-02: find a buddy

Ray's Discover list depends on both filters, so the search visibly narrows:

| Within | All | Intermediate |
|---|---|---|
| 2 km | Mali, Beam, Pim | **Mali** |
| 5 km | + Narin, Fah | Mali, Fah |
| 10 km | + Ton | Mali, Fah, Ton |

1. Ray: Discover, set **2 km** and **Intermediate**, so only Mali remains. Open her profile, send a
   request with a note.
2. Mali (window 2): the Activity tab shows a badge; she sees the notification and the note, and accepts.
3. Ray's Activity shows that Mali accepted.

## UC-03: schedule a run

1. Ray: **Create run** at Lumphini Park, with the start time **3–5 minutes from now**. The weather and
   PM2.5 card is the live forecast. (A run must start in the future; the short lead time lets UC-04
   continue with the same run.)
2. Mali opens the run: only the public meeting point. She **joins** and now sees the exact pin.
   Joining closes when the run starts, so join before that.

## UC-04: after the run

1. Once the start time passes, Ray's run page shows **Your run is underway** and **Finish run**.
   Finishing ends the run now instead of after the default hour.
2. Both open Activity: **Confirm attendance**. After both confirm, the run is complete.
3. Rate each other, then **Save running record**.
4. Mali's rating stays hidden: one rating exists and three are needed before it is shown.

**Backup** if the new run has not started yet or something stalls: Ray and Mali are already in
"Prepared past run — attendance demo" (ended yesterday), so Activity offers the same three steps
straight away.
