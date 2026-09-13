# How it works

This page follows the code. Function names are the ones in `awacs.sh`.

## Start-up

1. The conf `/etc/awacs.conf` is sourced if it is root-owned and mode `0600` (or stricter). Every numeric knob is validated; `NIGHT_START`/`NIGHT_END` must be `HH:MM`; `RUN_DIR` must be absolute. Then every knob is sealed `readonly`.
2. The interface is `AWACS_IF` or the best of `iw dev`: connected beats up beats present; `wlan0` if nothing is found (`detect_if`).
3. `/run/awacs` is created, mode `0700`.
4. `detect_backend` decides `wpa`, `nm` or `nm_lame` (see below). Under `nm`, the `wpa()` helper becomes a tripwire that logs `BUG: wpa_cli reached`.
5. The daemon takes `flock` on `/run/awacs/lock`. A second instance exits (with a box on a terminal, silently under the respawn loop).
6. `main` logs the start line and the reporting line (`reporting: <local|both|remote>[ -> SITE_URL] | probe: <url or 'none - signal mode'> | wifi cell: <auto|yes|no>`), checks tools, unblocks rfkill, disables WiFi power save, reaps a dead predecessor's temporary network, re-enables all stored networks, arms hidden-network probing, and rescues an orphaned spool snapshot.
7. No internet at start means `fight` immediately.

## The main loop (one tick = `TICK` seconds)

```text
apply_profile                  day/night switch, logs only on transition
if have_net:
    fails=0, ME clock cleared, NM evidence cleared
    "internet restored" if a fight was engaged
    flush_spool at the 3rd healthy tick, then every 30 ticks while lines remain
    install_tools at the 3rd healthy tick (once per boot)
    report_wifi every 6 ticks (background)
    retire the temporary network if a real one is current
    QA: passive upload meter -> strikes -> one probe -> evaluation
    preferred-network return every PREF_CHECK
else:
    fails++
    at fails == NET_FAIL_TICKS: "internet lost on IF - engaging"
    fight every tick from then on
sleep TICK
```

`have_net` is a ladder; any rung passing means online: `ping 8.8.8.8`, `ping 1.1.1.1`, HTTP 204 from `connectivitycheck.gstatic.com/generate_204`, HTTP 400 from the site's `device_api.php`. The two HTTP rungs are exact-code checks so a captive portal cannot pass.

## The fight

`fight` runs once per tick while the internet is down. Each call:

1. `drop_open`: yesterday's temporary network must not shadow today's real ones.
2. `enable_all`, `arm_hidden`. On NM: reset the per-fight activation evidence and `nm_wait_settled`.
3. `reassociate`, then `wait_ip && have_net`. Success ends the fight.
4. Three rounds. In each round:
   - NM only: `nm_wait_settled`; a heal is credited and the fight ends. If NM is busy (states 40–90 or 110) the round is marked `nm_working` and logs `NM is still trying - waiting it out`; no candidate is probed.
   - `best_by_upload`: connect to each visible stored network, measure, keep the fastest. Success ends the fight.
   - Classification (below) decides between the "my side" branch and the external branch.
   - "My side": log the evidence, optionally arm the reboot clock, run recovery rung `round` (L1, L2, L3), credit a heal, then `try_safety || try_open`.
   - External: clear the clock, log `outage looks external (round N) — waiting, not rebooting`, credit a heal, `try_safety || try_open`, sleep 20 s.
5. After three losing rounds: the reboot valve check, then `enable_all`, return failure.

Classification happens **before** the crutches are tried. Tearing down a temporary network drops the route and the association, and classifying after that framed every ISP outage as a local wedge (a proven ~35-minute reboot cycle).

### The recovery ladder

| Rung | `wpa` backend (`wpa_recover`) | `nm` backend (`nm_recover`) |
| --- | --- | --- |
| L1 | `rfkill unblock wifi`; `ip link set IF down`, 2 s, `up`, 3 s | block/unblock the interface's own rfkill index (`/sys/class/net/IF/phy80211/rfkill*`); `nmcli radio wifi off/on` only when no rfkill node exists; `nm_wait_settled 15` |
| L2 | `systemctl restart dhcpcd` (falls back to `wpa_supplicant`); 8 s; re-arm hidden; power save off | `nmcli device reapply IF`; if still offline, `nmcli device disconnect IF` then `nmcli -w 5 device connect IF`; power save off |
| L3 | `modprobe -r brcmfmac`, 2 s, `modprobe brcmfmac`, 8 s; re-arm hidden; power save off | `systemctl restart NetworkManager`; 8 s; `brcmfmac` reload; remove any `awacs-*` keyfile under `/run`; `nmcli connection reload`; mark L3 spent |

Log lines: `recover L1: radio bounce`, `recover L2: restart dhcpcd (...)` / `recover L2: re-kick NetworkManager on IF`, `recover L3: reload brcmfmac firmware (...)` / `recover L3: restart NetworkManager + reload WiFi firmware`.

`ip link down/up` and `dhcpcd` are never touched under NM: a second authority on a managed device is the disease the NM backend cures.

## "My side" versus external

The "my side" (ME) branch needs **all** of:

- not `nm_working` (NM is not mid-transition this round),
- `gw_ok` false: no default gateway on the interface, or it does not answer a ping,
- `LINK_OK` false: no association-plus-lease succeeded this round,
- and at least one tell: a stored network is visible yet could not be ridden, **or** the scan shows nothing at all (healthy radios see neighbours), **or** the stored list is empty (a mute supplicant).

Anything else is external. `gw_ok` passing means the link works and the outage is upstream.

Inside the ME branch, `auth_failing` (wpa: a `TEMP-DISABLED` network in `list_networks`; NM: an activation error mentioning secrets/authentication, sticky for the fight) logs `association refused - wrong password? (recovery continues, reboot stays off)` and sets the clock to zero. The ladder still runs, because a real wedge can coincide with one stale hotspot password.

On NM there is one more step at the rung boundary: `nm_wait_settled`, credit `have_net`, and if the device state is 100 (connected) the round takes a router-side path: `NetworkManager is connected, internet is not (round N) — router-side, no rung`, crutches, sleep 20 s. This came from the lab's live NM journal: L1 once bounced the radio five seconds after NM's own autoconnect had succeeded.

## The reboot valve

- `ME_SINCE` is the epoch of the first ME classification in the current streak. It is set on the wpa backend directly, and on NM only when `nm_me_settled` is true.
- It is cleared by: any healthy tick, any successful `connect_id`, any external classification, any wrong-password signature, and on NM by any busy sighting or any readable non-settled state.
- At the end of a losing fight, if `ME_SINCE > 0` and `now - ME_SINCE >= REBOOT_AFTER_MIN * 60` (and on NM `nm_me_settled` still holds), the daemon logs `wedged Nmin with networks visible — rebooting (repeats per streak until cured)` to the local file only, runs `sync`, sleeps 2 s, and reboots.
- The line is local-only by physics: the network is down and a spooled copy would die with the reboot (`/run` is tmpfs). The site learns of the reboot from the boot story.
- After a reboot the clock starts from zero; a surviving wedge earns another reboot only after a full new streak. With the default 30 minutes, reboots are at least ~40 minutes apart.

`nm_me_settled` returns true only when the NM device state has read 30 (disconnected) or 120 (failed) on two consecutive classifications with no busy sighting between them, or when the state is unreadable, `nmcli` itself exits 8 and L3's NM restart is already spent. State 20 (unavailable) never arms the valve on NM; it also covers rfkill and no-radio states a reboot would not cure.

## NetworkManager deference

From NM-SPEC section 6, as implemented:

AWACS does nothing while:

- `have_net` passes;
- the device is in the connecting band (40 prepare, 50 config, 60 need-auth, 70 ip-config, 80 ip-check, 90 secondaries) or 110 deactivating — every intervening primitive first calls `nm_wait_settled`;
- the outage is younger than `NET_FAIL_TICKS`;
- the device cycled through connecting states during a fight round: read as "NM still trying", the ME clock stays disarmed, no rung runs.
- the device is back in the connecting band at the rung boundary (NM is read once more after the ~12 s of evidence gathering): the same `NM is still trying - waiting it out` line, the round ends with no rung; state 100 without internet at that boundary takes the router-side branch instead.

AWACS intervenes only when all of these hold: `have_net` failed for `NET_FAIL_TICKS` ticks; the device state is settled (30, 120, or 100 without internet); and, for the ME/reboot path, NM has given up (30/120), a tell fired, `auth_failing` is false, and AWACS's own `connection up` attempts failed too.

The intervention order is cooperative: `nmcli -w 5 device connect IF` (let NM re-pick), `connection up uuid` per visible stored profile (the measured probing NM cannot do), temporary networks, `nm_recover` L1–L3, the valve. At every exit — win, loss, shutdown — `enable_all` hands the device back with a settled-gated `nmcli -w 5 device connect IF`. Forbidden on NM: `wpa_cli`, `ip link set down/up` on the managed device, restarting `dhcpcd`, and any owner-profile write.

The backend verdicts: `wpa` (NetworkManager neither active nor enabled), `nm` (full capability), `nm_lame` (NM is present but `nmcli` is missing or the interface is unmanaged, state 10). In `nm_lame` the daemon parks: it checks the internet every 300 s, flushes the spool, lets `install_tools` try once, and exits so the respawn loop can re-detect — but only when the reason was a missing `nmcli` and the launch was the respawn loop.

## Choosing by upload

`best_by_upload FLOOR HOME` walks `visible_known_ids`, skipping the incumbent (it was measured moments ago). For each candidate: `connect_id`, then `up_kbps` (a `PROBE_KB` upload to the probe target, `curl --data-binary`, speed read from `%{speed_upload}`; `wget` fallback with timing). The loop stops early when a candidate exceeds four times the current floor. If nobody beat the floor (or the best is 0), the incumbent is reconnected and the log says `no challenger beat the incumbent - staying on X`. Otherwise the winner is connected, `enable_all` runs, and `connected: X (upload N kbps)` is logged.

Without a probe target (no `SITE_URL` and no `PROBE_URL`: **signal mode**) there is nothing to upload to, so `best_by_upload` walks the visible stored networks strongest-first and keeps the first one that delivers internet: `connected: X (signal mode - no upload probe target configured)`. The QA path below is switched off entirely in that mode — a slow kernel-counter flow cannot be told from a small feed without the probe that clears the false alarm, so no strikes, no evaluation, no dance.

The QA path in the main loop: `tx_kbps` samples the interface's `tx_bytes` for 3 s. A flow between 20 kbps and `CUR_MIN_UP` is a strike; below 20 the device is idle and nothing is learned. After `UP_STRIKES` strikes and `CUR_COOLDOWN` since the last evaluation: `sustained slow upload (N kbps) - evaluating known networks`, one honest probe of the incumbent; if it is under the floor, `best_by_upload` with floor `here * CUR_GAIN / 100`.

While `streaming` is true (the camera stack's own processes), the band is 5–`STREAM_MIN_KBPS` and the line is `live stream starving (N kbps) - evaluating known networks`. A healthy stream is never interrupted.

## Preferred-network return

Every `PREF_CHECK` seconds, when not streaming: `pref_prescan` (wpa: a supplicant-side scan so armed `scan_ssid` surfaces hidden networks), then `best_pref_id` looks for a visible stored network with a priority strictly above the current one's (wpa: `priority`; NM: `connection.autoconnect-priority`, signed). Two consecutive sightings are required. On arrival `up_kbps` decides: under the floor means `preferred network too slow (N kbps) - benching it, going back`, a veto for three cooldowns, and a return to the previous network; otherwise `returned to preferred network: X (upload N kbps)`. Without a probe target nothing is measured on arrival: `returned to preferred network: X (signal mode)`, and no veto.

## The spool and the head pin

`site_log` writes the English line to the local log and builds the site line `[LEVEL] AWACS: <Arabic or English>, dd/mm/yyyy hh:mm:ss AM/PM.` While `net_up` is set it is sent in the background (`curl --max-time 4`) and self-spools on failure; while offline it is appended to `/run/awacs/spool`.

When the spool exceeds `SPOOL_CAP` lines, line 1 is kept and the newest `SPOOL_CAP - 1` follow it: the outage's opening banner carries the "when it began" stamp, so the middle chatter is what rolls off. `head -n 1` plus `tail -n (CAP-1)` can never duplicate a line.

`flush_spool` renames the spool to a snapshot (atomic; async appenders start a fresh file), sends line by line, stops at the first failure, and merges the unsent remainder in front of any new lines, capped with the same head pin. An appender landing in the final merge instant can lose one line; a lock there would let a hung flush block the fight, and reachability outranks logs.

## Scan sources

`scan` returns TSV `ssid<TAB>signal_dBm<TAB>open|sec`, strongest first, cached in `/run/awacs/scan` for `SCAN_TTL` seconds.

1. `iw dev IF scan`, up to 3 tries (6 within the first 180 s of uptime), 3 s apart. On `Device or resource busy` it waits once and stops trying: the supplicant or NM is scanning right now and its table will hold the answer.
2. `scan_iwlist`: `iwlist IF scan`, same TSV; a relative "Signal level=65/100" falls through to a -70 estimate instead of reading as +65 dBm.
3. `scan_backend`: wpa `scan_results` (already escaped like `iw`), or NM's `device wifi list --rescan no` with percent converted back to dBm (`percent / 2 - 100`) and hex converted to `iw`'s escaped text (`hex2iw`).

If all three are empty the log says `scan failed - using previous results (if any)`, the old cache is served and its timestamp is refreshed, so a silent radio is asked again once per `SCAN_TTL` rather than once per caller. Three such fresh scans in a row (`SCAN_DEAF`, a constant) mean the radio hears nothing: the log says `radio heard nothing on 3 scans in a row - previous results dropped` once, the cache becomes an empty answer served for `SCAN_TTL`, and every reader — the fight's "radio sees nothing" tell, the toolbox words, the WiFi cell — sees the truth; the reboot valve can now arm on a dead radio. Any scan that heard a beacon, even a hidden one, ends the streak. A scan that succeeded but named nothing keeps the previous cache.

In the lab, `iw` answered busy on 77 of 107 daemon scans on the legacy image while associated; step 3 is what made `evaluate`, `scan` and `speed` work from the first try.

## Names

- wpa backend: matching is on the raw escaped text both `iw` and `wpa_cli` print (`\xNN` for non-ASCII). `awk` receives it via `ENVIRON`, never `-v`, because `-v` decodes escapes and made every Arabic network invisible.
- NM backend: matching is on lowercase hex of the SSID bytes. A `0x…` value from `nmcli` that decodes as valid UTF-8 is a network literally named `0x…`; one that does not decode is NM's byte form. The ambiguous case emits both keys and the air picks the real one.
- Display: `pssid` decodes `\xNN` and strips control bytes; `disp_ssid` reads NM's UTF-8 property. Hex never reaches a human surface.
