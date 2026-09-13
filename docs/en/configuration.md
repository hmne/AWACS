# Configuration

One file: `/etc/awacs.conf`. Everything not written there keeps the default compiled into `awacs.sh`. The template with every knob commented out is `awacs.conf.example` in the repository root.

## Rules the script enforces

- **Owner and mode.** The file must be owned by root and have no group/other bits (`0600` or stricter). Otherwise the daemon prints `awacs: IGNORING /etc/awacs.conf (not owned by root — chown root: it)` or `awacs: IGNORING /etc/awacs.conf (group/world can access it — chmod 600 it)` to stderr and runs on defaults. Refusal is never silent.
- **Plain assignments only.** `KEY=value`, `KEY="value"`, `SAFETY_NET["Name"]="password"`. No `readonly`, no `declare`, no commands. The file is sourced by bash as root; keep it to assignments.
- **Numeric validation.** Every numeric knob must match `^0*[1-9][0-9]{0,6}$`: a non-zero integer with at most seven significant digits. Leading zeros are normalised (`08` is read as 8, not octal). Anything else falls back to the default. Zero is rejected for all of them: `TICK=0` would hot-spin the loop and `SPOOL_CAP=0` would break the head pin.
- **Clock knobs.** `NIGHT_START` and `NIGHT_END` must be `HH:MM` (`0:00`–`23:59`); a malformed value falls back to the default.
- **Paths.** `RUN_DIR` must be absolute; a relative or empty value falls back to `/run/awacs`. All five runtime files move with it.
- The `check` and `help` words run without root and therefore on defaults.

Apply by installing the file once:

```sh
sudo cp awacs.conf.example /etc/awacs.conf
sudo chown root:root /etc/awacs.conf && sudo chmod 600 /etc/awacs.conf
sudo nano /etc/awacs.conf
```

The daemon reads the conf at start. After an edit, restart it (see [install.md](install.md#upgrading)).

## Public-edition knobs (site and logging)

| Knob | Default | Values | Effect |
| --- | --- | --- | --- |
| `SITE_URL` | `""` | base URL, no trailing slash | Empty means local-only operation: no site lines, no WiFi cell, no probes unless `PROBE_URL` is set. When set, the script talks to `${SITE_URL}/${DEVICE_ID}/device_api.php`: log lines, the WiFi cell, the upload probe and the last rung of the internet check. |
| `LOG_TARGET` | `"local"` | `local` / `both` / `remote` | `local`: the file only. `both`: the file and the site. `remote`: the site, with only `WARN` and `ERROR` kept in the local file. `both` and `remote` require `SITE_URL`; asked for without it, the target is downgraded to `local` and one `WARN` line says so. |
| `PROBE_URL` | `""` | URL | Where the upload probe POSTs its body. Defaults to `${SITE_URL}/${DEVICE_ID}/device_api.php` when `SITE_URL` is set. Empty with no site means no probes: network choice falls back to signal order ("signal mode"). |
| `REPORT_WIFI` | `"auto"` | `auto` / `yes` / `no` | Publish `tmp/wifi.tmp` (`kbps,visible,total,band,SSID`) every ~60 s. `auto` is on when `SITE_URL` is set and `LOG_TARGET` is not `local`; `yes` needs `SITE_URL`. |
| `SITE_TZ` | `""` | an IANA zone name, e.g. `Europe/Berlin` | Time zone of the stamp on site log lines (`dd/mm/yyyy hh:mm:ss AM/PM`). Empty means the device's own zone. Letters, digits, `/`, `_`, `+`, `-` only; anything else is treated as empty. |
| `DEVICE_ID` | — | `[A-Za-z0-9_-]{1,32}` | Not a conf knob: comes from the environment (`export DEVICE_ID=` in `rc.local`, `Environment=DEVICE_ID=` in systemd). If unset, the first non-blank line of `/tmp/device_id` is read; anything that is not a plain slug falls back to the short hostname, then to `device`. |

### Three deployment shapes

1. **Local-only.** `SITE_URL=""`. The log is `/var/log/awacs.log`. The internet check uses the two pings and `generate_204`. No upload probes, so the daemon runs in **signal mode**: when the internet is lost the fight rides the strongest visible stored network that delivers (`connected: X (signal mode - no upload probe target configured)`); the slow-upload evaluation has nothing to measure and stays off (no strikes, no dance); the preferred-network return goes home without measuring (`returned to preferred network: X (signal mode)`, never a `too slow` veto); `awacs.sh speed` answers `no probe target (signal mode)`. The start line reads `reporting: local | probe: none - signal mode | wifi cell: auto`. Everything else — fight, ladder, classification, valve, safety net, open networks, day/night — is unchanged. To keep measured choice without a site, set `PROBE_URL` to any URL that accepts a POST body.
2. **Self-hosted receiver.** `SITE_URL="https://example.com/cams"` pointing at the receiver shipped in this repository, `LOG_TARGET="both"`. The receiver appends `log/log.txt`, overwrites `tmp/wifi.tmp`, answers the probe with `400`, and that `400` becomes the fourth rung of the internet check. Network choice is by measured upload. See [integration.md](integration.md).
3. **Full site.** The same URL pointing at a dashboard that also renders the log and the WiFi cell. Same contract; the dashboard decides what to show.

## Rhythm

| Knob | Default | Unit | What moving it changes | Suggested range |
| --- | --- | --- | --- | --- |
| `TICK` | `10` | seconds | Main-loop cadence. Each tick is two pings at most (plus HTTP rungs when they fail). Smaller reacts faster and pings more; larger delays every detection proportionally. | 5–30 |
| `NET_FAIL_TICKS` | `3` | ticks | Ticks without internet before `internet lost … engaging`. With `TICK=10`, 3 is ~30 s. Smaller fights on blips; larger waits through real outages. | 2–6 |
| `ASSOC_WAIT` | `25` | seconds | How long `wait_ip` waits for association plus an IPv4 lease after each connect attempt, and the `-w` for `nmcli connection up`. Too small fails slow routers; too large stretches every candidate probe. | 15–60 |
| `PREF_CHECK` | `600` | seconds | Interval of the preferred-network look. The return needs two consecutive sightings, so the effective stability window is twice this. One cache read, zero radio traffic. | 300–1800 |
| `REBOOT_AFTER_MIN` | `30` | minutes | Continuous "my side" evidence required before the valve fires. Reboots are never closer than this plus a full new streak. | 15–120 |

## Upload doctrine

| Knob | Default | Unit | What moving it changes | Suggested range |
| --- | --- | --- | --- | --- |
| `PROBE_KB` | `200` | KB | Size of each upload probe. Larger is more accurate and costs more data per decision; smaller is noisier. Each `best_by_upload` candidate and each QA check sends one. | 100–1000 |
| `MIN_UP_KBPS` | `400` | kbps | Day floor. A sustained measured flow below it (and above 20) is a strike; an incumbent probed below it triggers an evaluation; a preferred network arriving below it is benched. | 100–2000 |
| `UP_STRIKES` | `3` | samples | Consecutive slow samples before an evaluation is even considered. Hysteresis against one bad sample. | 2–5 |
| `SWITCH_GAIN_PCT` | `150` | percent | The floor a challenger must beat: `incumbent_kbps × GAIN / 100`. 150 means 1.5× faster. Lower switches more often. | 120–300 |
| `DANCE_COOLDOWN` | `1200` | seconds | Minimum gap between evaluations. Every evaluation interrupts real traffic. | 600–3600 |
| `STREAM_MIN_KBPS` | `50` | kbps | While a live stream runs, a flow below this (and above 5) is "starving" and allows an evaluation. Above it the stream is never touched. | 20–200 |

## Night profile

| Knob | Default | Unit | What moving it changes | Suggested range |
| --- | --- | --- | --- | --- |
| `NIGHT_MODE` | `"yes"` | yes/no | Anything but `yes` disables the profile switch. | — |
| `NIGHT_START` | `"22:00"` | HH:MM | Start of the night window. A window that wraps midnight is handled. | — |
| `NIGHT_END` | `"06:00"` | HH:MM | End of the night window. | — |
| `NIGHT_MIN_UP_KBPS` | `200` | kbps | Night floor, replaces `MIN_UP_KBPS`. | 50–1000 |
| `NIGHT_GAIN_PCT` | `300` | percent | Night gain, replaces `SWITCH_GAIN_PCT`. | 150–500 |
| `NIGHT_DANCE_COOLDOWN` | `2400` | seconds | Night cooldown, replaces `DANCE_COOLDOWN`. | 1200–7200 |

Transitions log `night profile active (floor N kbps)` and `day profile active (floor N kbps)` once each. `TICK` does not change at night; the loop is already cheap.

## Last resorts and behaviour

| Knob | Default | Values | Effect |
| --- | --- | --- | --- |
| `OPEN_NETWORKS` | `"yes"` | yes/no | Anything but `yes` disables the open-network last resort. Open networks are tried only after stored networks and `SAFETY_NET` have failed; strangers under -80 dBm (wpa) or 25 % (NM) are skipped. |
| `SAFETY_NET[...]` | empty | see below | Emergency networks with passwords, tried before open networks. |
| `STEALTH_MODE` | `"no"` | yes/no | `yes` inserts an `iptables` INPUT rule dropping ICMP echo on the interface and stops `avahi-daemon`. Runtime only; gone at reboot. Needs `iptables` present. |
| `DEBUG` | `"yes"` | yes/no | Decision-trace `[DEBUG]` lines in the local log only. The environment variable `AWACS_DEBUG` sets the default. |

### `SAFETY_NET` syntax

One line per network, inside the conf only:

```sh
SAFETY_NET["MyPhoneHotspot"]="hotspot-password"
SAFETY_NET["NeighbourGuest"]="another-password"
SAFETY_NET["OpenHotspotIDeliberatelyTrust"]=""     # empty password = open network, tried before strangers
```

Rules:

- Tried in the order bash iterates the array (not guaranteed), each attempt bounded by `ASSOC_WAIT`, even when the network is not in the scan (hotspots are often just switched on or hidden).
- wpa backend: a name or password containing a backslash or a double quote is skipped (the supplicant's quoted parser cannot carry it). The password is passed over stdin, never argv.
- NM backend: any name and password bytes are accepted; the password must be 8–63 characters or exactly 64 hex digits, otherwise the entry is skipped. The profile is a `/run` keyfile, mode 0600, `autoconnect=false`, named `awacs-safety-<epoch>-<pid>`.
- The connected emergency network is a temporary entry and is retired like an open network once a stored network is current again.

## Files

| Knob | Default | Effect |
| --- | --- | --- |
| `LOG_FILE` | `/var/log/awacs.log` | The local log. Format `[LEVEL][dd/mm HH:MM:SS] message`. |
| `LOG_CAP` | `1500` | Rotation keeps this many lines; rotation runs when the file exceeds `LOG_CAP + 200`. Suggested 500–10000. |
| `RUN_DIR` | `/run/awacs` | Private root-only state: `lock` (flock + daemon pid), `scan` (cache), `spool`, `open_id` (temporary-network marker), `probe` (wget body), `apt_tried` (once-per-boot marker). tmpfs: recreated at boot. |
| `SCAN_TTL` | `30` | Seconds a scan result is served from cache. Scans go off-channel. Suggested 15–120. |
| `SPOOL_CAP` | `60` | Lines kept for the site while offline, first line pinned. Suggested 20–500. |

## Environment variables

| Variable | Effect |
| --- | --- |
| `DEVICE_ID` | Device identity (see above). |
| `AWACS_IF` | Interface override; skips `detect_if`. |
| `AWACS_CONF` | Conf path override (default `/etc/awacs.conf`). |
| `AWACS_DEBUG` | Default for `DEBUG`. |
| `AWACS_TEST_KBPS`, `AWACS_TEST_SCAN` | Test hooks: fixed upload reading; serve the scan cache without touching the radio. |

## Cross-checking against the code

`tools/gen-config-table.sh` reads `awacs.sh` and `awacs.conf.example` and prints a table of every knob: the default in the script, the default in the example, how it is validated, and the functions that use it. Run it after any change to either file so this page cannot drift from the code. Its output is committed as [config-reference.md](config-reference.md).

## Suggested ranges

The "suggested range" columns are operating guidance, not lab-measured limits. The hard limit the script enforces is the validator: 1 to 9 999 999 for every numeric knob. The lab ran with `PREF_CHECK=60`, `REBOOT_AFTER_MIN=4`, `DANCE_COOLDOWN=120`, `SPOOL_CAP=15` to shorten waits; production values are the defaults.
