# Demo day runbook

Follows the demo script slide: Auth, Home, UC-02, UC-03 and UC-04, then Nok's lived-in account.
Rehearsed against this stack on 14 Nov 2026.

## Before the demo

```sh
sh scripts/uat-tunnel.sh stop     # if it is open; a reset would point photo links back at localhost
sh scripts/reset-demo.sh          # wipes ALL local data, starts the stack, seeds it (a few minutes)
sh scripts/uat-tunnel.sh start    # builds the frontend and prints the public link
sh scripts/uat-tunnel.sh otp      # keep this terminal open for sign-up codes
```

Run the reset after the last rehearsal, so requests, runs, ratings and sign-ups from the rehearsal
are gone and the seeded runs move forward from today. Reset the evening before rather than the morning
of the demo: Mali's "Sunset social 5K" is seeded for 18:30 the next day. Then open the link in two
browser windows (one private). Run Conditions calls the live weather provider, so the laptop needs
internet. If the tunnel fails, the same build is at http://127.0.0.1:4173.

| Who | Email | Password | After a reset |
|---|---|---|---|
| Ray (window 1) | `ray@example.com` | `runner123` | No buddies, requests, ratings or records; no photo |
| Mali (window 2) | `mali@example.com` | `runner123` | Avatar and a few solo runs; no buddies or ratings |
| Nok (showcase) | `nok@example.com` | `runner123` | 5 buddies, a pending request from Aom, 3 finished runs, 9 logged runs, a rating |

Around them: 16 more runners with avatars, ratings and running totals (`scripts/demo_community.py`),
8 finished and 7 upcoming group runs.

## Auth: register and log in

1. Window 1, **Create account**: any new email (e.g. `demo@example.com`), a new phone
   (e.g. `+66812345678`), password of 8+ characters, consent.
2. The code appears in the OTP terminal as `[LOCAL CONSOLE OTP] phone=… code=123456 (not an SMS delivery)`.
   Say so: the console adapter stands in for SMS. The code expires after 5 minutes.
3. Verify, then set up the profile: drop the pin on the map, the running area fills in. **Set
   Experience to Beginner**: the form defaults to Intermediate at Lumphini, which would put this new
   runner next to Mali in Ray's "2 km + Intermediate" search. Discover already shows a dozen runners
   around Lumphini.
4. Sign out and **log in as Ray** for the rest of the demo.

Each email and phone registers once; use a new pair for each rehearsal or reset first.

## Home: Who's nearby

Ray's radar shows **4 runs within 1 km** around Lumphini Park (Mali's, Arm's, Ploy's and his own),
and his next run is "Weekend long run". Unjoined runs are placed to about 1 km, the same rule as
runner areas; the exact pin is for participants only. Tap the radar for Who's nearby: allow location,
or press **Use demo location** (near Lumphini) if the browser has none. Unjoined runs share one
rounded point, so their distances read the same; that is the privacy rule, not a bug.

## UC-02: find a buddy

Ray's Discover list depends on both filters, so the search visibly narrows:

| Within | All | Intermediate |
|---|---|---|
| 2 km | 12 runners | **Mali** |
| 5 km | 21 | Mali, Fah, Nok, Oat, Fern, Golf, Aom, Bow, Jay |
| 10 km | 22 | + Ton |

Distances are between ~1 km area cells (NFR-4.1), so several runners read "0 km".

1. Ray: Discover, set **2 km** and **Intermediate**, so only Mali remains. Open her profile (avatar,
   running totals, "Rating appears after 3 reviews"), send a request with a note.
2. Mali (window 2): the Activity tab shows a badge; she sees the notification and the note, and accepts.
3. Ray's Activity shows that Mali accepted.

## UC-03: schedule a run

1. Ray: **Create run** at Lumphini Park, any time in the next few days. The weather and PM2.5 card is
   the live forecast.
2. Mali opens the run: only the public meeting point ("Join this run to see the exact pin"). She
   **joins** and a map with the exact pin and an "Open in Google Maps" link appear.

## UC-04: after the run

No waiting for the new run: Ray and Mali are already in **"Lumphini evening 5K"** (yesterday, 18:00).

1. Both open Activity: **Confirm attendance**. After both confirm, the run is complete.
2. Rate each other, then **Save running record** (prefilled with 5000 m and 1800 s).
3. Ray's running history panel appears. Mali's rating stays hidden: one rating exists and three are
   needed before it is shown.

## Nok: a lived-in account

Sign in as Nok to show what the product looks like after a few weeks:

- **Home**: buddy activity (Oat's run she is going to, Arm's to join), radar around Benjakitti.
- **Activity**: Aom's pending request, five buddies, finished runs marked All done, running history.
- **A buddy's profile** (e.g. Oat): avatar, a rating out of 5 from verified runs, running totals.
  Individual runs stay private to the runner; others see totals only.
