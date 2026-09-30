# Verna VPN telemetry — design

**Date:** 2026-10-01
**Status:** agreed with Meysam, not yet implemented
**Ships in:** 1.0.3 (app) + verna-api

## Why

After the 1.0.2 release, 113 network vantage points pressed connect in one day
and 45 got a tunnel. We know *that* 68 failed. We cannot say **which of them
failed for which reason**, how long anyone stayed connected, whether the ping
the app promised matched the tunnel it delivered, or whether a user who picked
a country by hand had an easier time than one on automatic.

Everything we have today is per-server (`reports.db`: probe and tunnel outcomes
keyed by an IP-derived hash that rotates daily). Nothing is per-session and
nothing is per-install, so no question about a *user's experience* is
answerable.

This adds that layer, and nothing else.

## Decisions

| Decision | Chosen | Why |
|---|---|---|
| Identity | Random per-install UUID, resettable in Settings | The daily IP-derived hash merges users behind CGNAT and splits one phone whose mobile IP rotates. Retention and session length are unanswerable without a stable id. Not derived from IMEI, Android ID or any device identifier. |
| Consent | The existing "share results" switch, default on, with rewritten text | No OS permission is involved and no dialog is added. The switch already exists; only its description changes, to say what actually leaves the phone. |
| Shape | One row per session + one row per failed attempt | A full event stream costs several times the volume and is harder to query. Sessions and failures answer the questions asked. |
| Speed | 256 KB download from verna-api, once per session | Traffic counters measure what the user *did*, not what the line could do. One identical far end for everyone makes the numbers comparable; ~0.25 MB per connect, ~12 MB/day of egress at current volumes. |
| Geography | Country + mobile operator + ASN. Never the IP, never the city | Blocking differs per ISP and operator, not per city. "19 % on MCI" is actionable; "a user in Isfahan" is not, and install id + city + time + duration stops being statistics. |
| Output | Storage only | No dashboard, no scheduled digest. Analysis is run against the database when a release is being planned. |

## Data

### `sessions` — one row per connection that came up

| Column | Notes |
|---|---|
| `uid` | Client-generated, `UNIQUE`; makes re-sends idempotent |
| `install` | `HMAC(server_secret, install_id)`; fixed salt, unlike `reporter` |
| `started_at`, `duration_s` | |
| `picked` | `manual` \| `auto`, plus `asked_country` |
| `connect_ms`, `attempts_before` | How long it took and how many candidates were tried first |
| `probe_ms`, `tunnel_ms` | What the app predicted vs what it measured inside the tunnel |
| `speed_kbps` | The 256 KB test |
| `bytes_down`, `bytes_up`, `peak_kbps` | |
| `config_id`, `protocol`, `exit_country` | |
| `transport`, `operator`, `asn`, `country` | |
| `ended_by` | `user` \| `network` \| `core_died` \| `app_killed` \| `error` |
| `app_version` | |

### `failures` — one row per connect that ended with nothing

`reason` is taken from the app's own `TunnelFailure`, not invented for
telemetry: `no_internet`, `permission_denied`, `none_reachable`,
`no_traffic`, `cancelled`, `core_failed`. Plus `candidates_tried`,
`servers_live` (how many passed the device probe at that moment),
`gave_up_after_s`, `asked_country`, and the same transport / operator / asn /
country / app_version columns.

`servers_live` is the column that separates "the app is broken" from "this
network blocks everything": on 2026-09-30, the vantage points that connected
had 59.6 live servers on average, those that failed had 1.3.

## Transport

The existing `ReportQueue` pattern, which has survived flaky connections since
September: a disk-backed queue, one uid per row, batched POST, kept on the
phone when offline. A session row is written when the tunnel stops; a failure
row at the moment of failure. Flushed only while the app is not connecting, so
it never competes with the thing being measured.

New endpoint `POST /v1/telemetry`, separate from `/v1/reports`, because the
config bot reads the `reports` table for server ranking and that contract must
not move. New tables live in the same `reports.db`, so one file still holds
everything and backups do not change.

Server-side: row cap per request, `UNIQUE` on `uid`, unknown fields dropped,
180-day retention. No new process — verna-api carried six times its usual load
on release day at 125 MB with zero restarts.

## Sessions that never end

If Android kills the process, the session row is never written — and those are
exactly the sessions worth having (the tunnel died, the app was killed, the
user walked away). So an **open** session record is written to disk at connect
and closed by the next launch with `ended_by = app_killed` and the duration up
to the last traffic sample. Without this the data would be quietly biased
towards sessions that ended well.

## Never sent

- The user's own subscription links or their contents
- Any credential, key, password or UUID belonging to a server
- The user's IP address (the server does not store it today either)
- Anything about what the user did inside the tunnel — only whole-tunnel byte
  counters

This is enforced by a test over the outgoing JSON, not by a comment: a promise
in prose does not survive the next refactor.

## What becomes answerable

- Why a given group of users could not connect, split by operator and ISP
- Whether a hand-picked country connects more easily than automatic
- Whether the ping shown in the app matches the tunnel delivered
- Whether a connection was fast, independently of how much the user did
- Minutes used and bytes moved per install per day
- Whether short sessions correlate with slow speed and repeated drops —
  the closest thing to "were they unhappy" that this data can honestly support

## Not in scope

City-level geography. A dashboard. Any per-app or per-domain traffic
breakdown. Changing the existing `reports` table or the bot's ranking inputs.
