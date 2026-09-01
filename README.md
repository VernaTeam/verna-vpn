**English** · [فارسی](README.fa.md)

# Verna VPN

An Android client that runs a sing-box tunnel over free, public configs — and
tests every one of them on your phone before it offers you any.

---

## The problem it actually solves

There is no shortage of free VPN configs. Telegram channels post thousands a
day. The trouble is that almost none of them work *from where you are*, and you
find that out one at a time: paste, connect, wait, fail, repeat.

Server-side verification does not fix this. A config that a datacenter in
Germany can reach may be entirely unreachable from an Iranian mobile network,
because the thing blocking it sits between you and the server, not between the
server and the world.

So Verna measures from the device. It pulls a sample of the pool, runs it
through the sing-box core in proxy mode, and shows you the ones that carried
traffic — with the latency your phone measured, not one someone else did.

The difference is not marginal. On a Galaxy J7 on a home connection, of 313
candidate servers:

| | working |
|---|---|
| what the server had verified | 313 |
| what actually accepted a TCP connection here | 191 |
| what carried traffic through the tunnel here | **51** |

The list you see is the third row.

## The part that was harder than expected

The app's control channel is subject to exactly the blocking the app exists to
get around.

The config API sits behind Cloudflare. Cloudflare is anycast, so every edge
address serves the same site — but only some of those addresses are reachable
from a given Iranian connection, and which ones changes through the day.
Measured on 1 September 2026, the address DNS returned timed out while eight
other Cloudflare edges served the identical API in about a second. The server
had been healthy the whole time.

So there are three layers underneath the fetch:

1. **Edge rotation** — if the address DNS hands out is dead, connect straight to
   a known Cloudflare edge instead. TLS still carries the real hostname, so the
   certificate is validated exactly as before; only the socket's destination
   changes. The working edge is remembered so the next launch does not pay the
   timeouts again.
2. **On-device cache** — the last list that arrived, used only when the network
   fails.
3. **A bundled seed list** — a sample of the pool shipped inside the APK, for a
   first launch on a connection that blocks everything else. It goes stale
   within days, which is why it is last; every entry is re-tested on the device
   before it is offered.

   `assets/seed_configs.json` is empty in this repository. It holds a snapshot
   of other people's servers, and a git history is a permanent, indexed place
   to keep something that is stale in a week. Fill it before a release build:

   ```bash
   python tool/fetch_seed_configs.py
   ```

   The app treats an empty bundle as no fallback and behaves correctly without
   it.

None of these weaken certificate validation.

## What is in it

- **Protocols** — VLESS (incl. Reality), VMess, Shadowsocks, Trojan, Hysteria2,
  TUIC, via [sing-box](https://github.com/SagerNet/sing-box) 1.14.
- **On-device testing** — batched through the core's own urltest, twenty at a
  time so the measurement is of the server rather than of the queue behind it,
  and run twice so a server that lost the first race is not written off.
- **DNS over HTTPS on 443**, resolved inside the tunnel. Plain UDP does not
  survive here: most free configs are TCP-only, so a UDP resolver produced a
  tunnel that moved bytes and resolved no names.
- **Automatic reconnection** when the network changes, with a settle window so
  a Wi-Fi-to-mobile handover does not tear down a working session.
- **Usage history** — bytes per day for a fortnight, kept on the device and
  reported nowhere.
- **Persian and English**, light and dark, switchable live.

## Not built yet

Kill switch, split tunneling and local network access are shown in Settings as
pending rather than as switches. A toggle that flips and changes nothing is
worse than a missing feature — particularly a kill switch, whose entire purpose
is a promise about what happens when the tunnel drops.

## Build

Requires Flutter 3.44 or newer and the Android SDK.

```bash
flutter pub get
flutter run                       # debug, on a connected device
flutter build apk --release       # release
```

Release signing reads `android/key.properties`, which is not in this repository.
Without it the build falls back to the debug key and says so. To sign your own:

```bash
keytool -genkey -v -keystore verna.keystore -alias verna \
  -keyalg RSA -keysize 2048 -validity 10000
```

Then create `android/key.properties`:

```properties
storePassword=…
keyPassword=…
keyAlias=verna
storeFile=../verna.keystore
```

## Credits

- [sing-box](https://github.com/SagerNet/sing-box) — the tunnel core, via
  `flutter_singbox_client`.
- [Vazirmatn](https://github.com/rastikerdar/vazirmatn) and
  [JetBrains Mono](https://github.com/JetBrains/JetBrainsMono) — bundled fonts.
- Exit-IP geolocation from [ip-api.com](https://ip-api.com).

## Licence

MIT. See [LICENSE](LICENSE).
