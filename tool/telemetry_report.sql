-- Verna VPN telemetry: the questions this system was built to answer.
--
--   ssh root@<vps> "sqlite3 -header -column /opt/verna-api/data/reports.db" < tool/telemetry_report.sql
--
-- Every query is read-only. They are written for the release review: run them
-- before deciding what the next version should fix, rather than guessing from
-- the loudest complaint.
--
-- One caveat that belongs on every number below: `install` is a random id per
-- installation, so it counts INSTALLS, not people. A user with two phones is
-- two installs, and a user who reinstalls or resets their id is a new one. It
-- is still far closer to a user count than the reports table's reporter hash,
-- which is derived from an IP and rotates daily.

.print ''
.print '=== 1. How many installs, and how much did they use it ==='
SELECT date(received_at)                       AS day,
       COUNT(DISTINCT install)                 AS installs,
       COUNT(*)                                AS sessions,
       ROUND(SUM(duration_s) / 3600.0, 1)      AS hours_total,
       ROUND(AVG(duration_s) / 60.0, 1)        AS avg_minutes,
       ROUND(SUM(bytes_down) / 1073741824.0, 2) AS gb_down
FROM sessions
GROUP BY 1 ORDER BY 1 DESC LIMIT 30;

.print ''
.print '=== 2. Did they come back? (installs by how many days they appear on) ==='
WITH days AS (
  SELECT install, COUNT(DISTINCT date(received_at)) AS active_days
  FROM sessions GROUP BY 1
)
SELECT active_days, COUNT(*) AS installs
FROM days GROUP BY 1 ORDER BY 1;

.print ''
.print '=== 3. Why the failures failed ==='
SELECT reason,
       COUNT(*)                        AS attempts,
       COUNT(DISTINCT install)         AS installs,
       ROUND(AVG(servers_live), 1)     AS avg_live_servers,
       ROUND(AVG(candidates_tried), 1) AS avg_tried,
       ROUND(AVG(gave_up_after_s), 0)  AS avg_seconds
FROM failures
GROUP BY 1 ORDER BY attempts DESC;

.print ''
.print '=== 4. Failures by operator and transport ==='
SELECT transport,
       COALESCE(operator, '-')  AS operator,
       COUNT(*)                 AS failures,
       COUNT(DISTINCT install)  AS installs,
       ROUND(AVG(servers_live), 1) AS avg_live_servers
FROM failures
GROUP BY 1, 2 ORDER BY failures DESC LIMIT 20;

.print ''
.print '=== 5. Success rate per install: connected at least once vs never ==='
WITH tried AS (
  SELECT install FROM sessions
  UNION
  SELECT install FROM failures
),
ok AS (SELECT DISTINCT install FROM sessions)
SELECT (SELECT COUNT(*) FROM tried)                    AS installs_that_tried,
       (SELECT COUNT(*) FROM ok)                       AS installs_that_connected,
       ROUND(100.0 * (SELECT COUNT(*) FROM ok)
                   / NULLIF((SELECT COUNT(*) FROM tried), 0), 0) AS pct;

.print ''
.print '=== 6. Hand-picked vs automatic ==='
SELECT picked,
       COUNT(*)                       AS sessions,
       ROUND(AVG(connect_ms) / 1000.0, 1) AS avg_connect_s,
       ROUND(AVG(attempts_before), 1) AS avg_servers_tried,
       ROUND(AVG(duration_s) / 60.0, 1) AS avg_minutes,
       ROUND(AVG(speed_kbps), 0)      AS avg_kbps
FROM sessions WHERE picked IS NOT NULL
GROUP BY 1;

.print ''
.print '=== 6b. ...and when they fail ==='
SELECT picked, reason, COUNT(*) AS failures
FROM failures WHERE picked IS NOT NULL
GROUP BY 1, 2 ORDER BY 1, failures DESC;

.print ''
.print '=== 7. Was the ping real? (what the app promised vs what it delivered) ==='
SELECT COUNT(*)                                   AS measured_both,
       ROUND(AVG(probe_ms), 0)                    AS avg_promised,
       ROUND(AVG(tunnel_ms), 0)                   AS avg_delivered,
       ROUND(AVG(tunnel_ms - probe_ms), 0)        AS avg_gap,
       SUM(tunnel_ms > probe_ms * 2)              AS more_than_double,
       ROUND(100.0 * SUM(tunnel_ms > probe_ms * 2) / COUNT(*), 0) AS pct_double
FROM sessions WHERE probe_ms IS NOT NULL AND tunnel_ms IS NOT NULL;

.print ''
.print '=== 8. Was it fast? (256 KB sample through the tunnel) ==='
SELECT COALESCE(protocol, '-')      AS protocol,
       COUNT(*)                     AS sessions,
       ROUND(AVG(speed_kbps), 0)    AS avg_kbps,
       MIN(speed_kbps)              AS worst,
       MAX(speed_kbps)              AS best,
       ROUND(AVG(tunnel_ms), 0)     AS avg_ping
FROM sessions WHERE speed_kbps IS NOT NULL
GROUP BY 1 ORDER BY avg_kbps DESC;

.print ''
.print '=== 9. Speed by exit country, where it was actually used ==='
SELECT COALESCE(exit_country, '-')  AS country,
       COUNT(*)                     AS sessions,
       COUNT(DISTINCT install)      AS installs,
       ROUND(AVG(speed_kbps), 0)    AS avg_kbps,
       ROUND(AVG(tunnel_ms), 0)     AS avg_ping,
       ROUND(AVG(duration_s) / 60.0, 1) AS avg_minutes
FROM sessions
GROUP BY 1 HAVING sessions >= 3 ORDER BY avg_kbps DESC;

.print ''
.print '=== 10. Short sessions: the closest thing to dissatisfaction ==='
-- Under two minutes, with what the session looked like. A short session on a
-- fast tunnel is someone who finished; a short session on a slow one, or one
-- that ended by itself, is someone who gave up.
SELECT CASE
         WHEN duration_s < 120 THEN 'under 2 min'
         WHEN duration_s < 600 THEN '2-10 min'
         WHEN duration_s < 3600 THEN '10-60 min'
         ELSE 'over an hour'
       END                          AS length,
       COUNT(*)                     AS sessions,
       ROUND(AVG(speed_kbps), 0)    AS avg_kbps,
       ROUND(AVG(tunnel_ms), 0)     AS avg_ping,
       SUM(ended_by = 'user')       AS ended_by_user,
       SUM(ended_by IN ('network', 'core_died', 'app_killed')) AS lost
FROM sessions WHERE duration_s IS NOT NULL
GROUP BY 1 ORDER BY MIN(duration_s);

.print ''
.print '=== 11. How sessions end ==='
SELECT COALESCE(ended_by, '-') AS ended_by,
       COUNT(*)                AS sessions,
       ROUND(AVG(duration_s) / 60.0, 1) AS avg_minutes
FROM sessions GROUP BY 1 ORDER BY sessions DESC;

.print ''
.print '=== 12. Which release each install is on ==='
SELECT COALESCE(app_version, '-') AS version,
       COUNT(DISTINCT install)    AS installs,
       COUNT(*)                   AS sessions,
       MAX(date(received_at))     AS last_seen
FROM sessions GROUP BY 1 ORDER BY installs DESC;
