# Scenarios

Nine situations, each in three parts: what a stock system does, what AWACS does with its log lines in order, and the knobs involved. Timestamps and names in the samples are illustrative. `HomeNet` and `OfficeNet` are stored networks, `PhoneHotspot` is an entry in `SAFETY_NET`, `FreeCafe` is an open network and `mydevice` is the device id. Samples show the wpa backend; on nm the rung lines read `recover L1: radio bounce`, `recover L2: re-kick NetworkManager on wlan0` and `recover L3: restart NetworkManager + reload WiFi firmware`. Samples omit repeated lines: the emergency and open attempts follow every rung, and the DEBUG evidence line is logged at every round with device-side evidence. Lines a recovery repeats within one outage are said once and counted; the counts follow `internet restored`.

## 1. Wrong password on the only reachable network

### Stock system behaviour

wpa_supplicant fails the handshake, marks the network `TEMP-DISABLED` for a growing interval and retries on its own timer. NetworkManager retries the profile a few times and leaves the device disconnected. Neither tries another network, and a watchdog that reboots on lost internet reboots without end.

### AWACS behaviour

The signs resemble a fault on the device (network on the air, cannot be joined, no gateway), but the credentials sign is present, so the reboot timer is set back to zero at every round. The ladder still runs, because a wedge can coincide with a stale password, and emergency and open networks follow each rung. With the correct password in place the next recovery succeeds.

```text
2026-01-01T10:00:30+03:00 [WARN] internet lost on HomeNet - router none (not associated), engaging
2026-01-01T10:00:31+03:00 [INFO] router not answering - waiting up to 25 s for wlan0 to reconnect
2026-01-01T10:01:19+03:00 [INFO] scan heard 3 networks: HomeNet -48, Cafe -70, Guest -74 | known on the air: HomeNet | stored, not heard: OfficeNet
2026-01-01T10:01:20+03:00 [ERROR] association refused by HomeNet - wrong password? (recovery continues, reboot stays off)
2026-01-01T10:01:21+03:00 [WARN] recover L1: radio bounce
2026-01-01T10:01:30+03:00 [INFO] trying emergency networks (1 listed)
2026-01-01T10:02:04+03:00 [WARN] emergency network PhoneHotspot refused: never associated - trying the next
2026-01-01T10:02:04+03:00 [INFO] no emergency network delivered (1 tried, 0 skipped)
2026-01-01T10:02:05+03:00 [INFO] trying open networks as last resort (0 open networks heard)
2026-01-01T10:02:05+03:00 [INFO] no open network delivered internet (0 heard, 0 tried, 0 linked without internet)
2026-01-01T10:03:12+03:00 [WARN] recover L2: restart dhcpcd (respawns the REAL per-interface supplicant)
2026-01-01T10:05:30+03:00 [WARN] recover L3: reload brcmfmac firmware (the 3-second cure a wedge needs)
2026-01-01T10:06:05+03:00 [OK] internet restored: HomeNet - down 5 min, 1 recovery run
2026-01-01T10:06:05+03:00 [INFO] repeated 2 more times during the outage (last at 10:05): association refused by HomeNet - wrong password? (recovery continues, reboot stays off)
```

On nm the credentials sign comes from the activation error text and holds for the whole recovery.

### Knobs involved

`NET_FAIL_TICKS`, `ASSOC_WAIT`, `SAFETY_NET`, `OPEN_NETWORKS`. `REBOOT_AFTER_MIN` plays no part while the credentials sign is seen.

## 2. Home access point down, then back

### Stock system behaviour

When the current link drops, wpa_supplicant selects another enabled network from its configuration and NetworkManager activates another autoconnect profile. Neither moves back to the higher-priority network while the current link holds, and neither measures throughput.

### AWACS behaviour

If the base layer roams within `NET_FAIL_TICKS` ticks nothing is logged. Otherwise recovery starts; its gentle opening may find the device already moved, in which case only `internet restored` follows. If not, every visible stored network is activated and measured and the best one kept. Afterwards, every `PREF_CHECK` seconds, the daemon looks for a visible stored network with a strictly higher priority; two consecutive sightings send the device home, with the upload measured on arrival.

```text
2026-01-01T12:00:30+03:00 [WARN] internet lost on HomeNet - router none (not associated), engaging
2026-01-01T12:00:31+03:00 [INFO] router not answering - waiting up to 25 s for wlan0 to reconnect
2026-01-01T12:00:44+03:00 [INFO] scan heard 5 networks: OfficeNet -61, Cafe -70, Guest -74, N5 -80, N6 -85 | known on the air: OfficeNet | stored, not heard: HomeNet
2026-01-01T12:00:45+03:00 [INFO] trying OfficeNet
2026-01-01T12:01:10+03:00 [INFO] candidate [1] OfficeNet uploads at 1484 kbps
2026-01-01T12:01:10+03:00 [INFO] switching to OfficeNet (1484 kbps, the fastest candidate)
2026-01-01T12:01:12+03:00 [OK] switched to OfficeNet (upload 1484 kbps)
2026-01-01T12:01:12+03:00 [OK] internet restored: OfficeNet - down 42 s, 1 recovery run
2026-01-01T12:21:30+03:00 [INFO] higher-priority network HomeNet visible twice - leaving OfficeNet to go home
2026-01-01T12:21:48+03:00 [INFO] measured 7445 kbps on HomeNet
2026-01-01T12:21:50+03:00 [OK] returned to preferred network: HomeNet (upload 7445 kbps)
```

Had `HomeNet` measured under the floor on arrival, the line would be `preferred network HomeNet too slow (120 kbps, floor 400) - benched for 60 min, going back to OfficeNet`, then `back on OfficeNet`, and `HomeNet` is left alone for those 60 minutes (three cooldowns). A `HomeNet` that shows at one check and is gone at the next is said once per stay, `preferred network HomeNet was visible at one check and gone at the next - staying on OfficeNet until it holds for two checks in a row`, and the attempt line then carries `(seen and lost N times before)`.

### Knobs involved

`PREF_CHECK`, `MIN_UP_KBPS` and `NIGHT_MIN_UP_KBPS`, `DANCE_COOLDOWN` (the veto lasts three of them), `PROBE_KB`, and the priorities in the network configuration (wpa `priority=`, nm `connection.autoconnect-priority`); the return needs the home priority strictly higher than the current one.

## 3. Every stored network gone

### Stock system behaviour

Nothing. Both stacks know only the stored networks.

### AWACS behaviour

No stored network is on the air, other networks are, and the gateway is silent: none of the three device-side signs applies, so the round is classified external and no rung runs. `SAFETY_NET` entries are tried whether or not the scan shows them, then open networks. The network joined is a temporary entry with priority 0. When a stored network with a higher priority reappears, the preferred-network check brings the device home and the entry is removed on the next healthy tick; no `awacs-*` profile remains on nm and no extra network id in the live supplicant on wpa.

```text
2026-01-01T14:00:30+03:00 [WARN] internet lost on HomeNet - router none (not associated), engaging
2026-01-01T14:00:31+03:00 [INFO] router not answering - waiting up to 25 s for wlan0 to reconnect
2026-01-01T14:01:54+03:00 [INFO] scan heard 4 networks: FreeCafe -55, Guest -70, N5 -80, N6 -85 | known on the air: none | stored, not heard: HomeNet, OfficeNet
2026-01-01T14:01:55+03:00 [INFO] outage looks external: none of your 2 stored networks is on the air, 4 others heard (round 1) — waiting, not rebooting
2026-01-01T14:02:02+03:00 [INFO] trying emergency networks (1 listed)
2026-01-01T14:02:37+03:00 [WARN] emergency network PhoneHotspot refused: never associated - trying the next
2026-01-01T14:02:37+03:00 [INFO] no emergency network delivered (1 tried, 0 skipped)
2026-01-01T14:02:38+03:00 [INFO] trying open networks as last resort (1 open networks heard)
2026-01-01T14:03:10+03:00 [OK] connected to OPEN network: FreeCafe (upload 620 kbps) - stored networks stay armed, home again when one returns
2026-01-01T14:03:11+03:00 [OK] internet restored: FreeCafe - down 2 min, 1 recovery run
2026-01-01T14:42:30+03:00 [INFO] higher-priority network HomeNet visible twice - leaving FreeCafe to go home
2026-01-01T14:43:06+03:00 [INFO] measured 2302 kbps on HomeNet
2026-01-01T14:43:08+03:00 [OK] returned to preferred network: HomeNet (upload 2302 kbps)
2026-01-01T14:43:21+03:00 [OK] back on a stored network: HomeNet - temporary network FreeCafe removed
```

Here the hotspot was off; with it on, the lines would be `connected to EMERGENCY network: PhoneHotspot (upload 1100 kbps) - stored networks stay armed, home again when one returns` and `internet restored: PhoneHotspot - down 2 min, 1 recovery run`, and no open network is tried.

### Knobs involved

`SAFETY_NET`, `OPEN_NETWORKS`, `PREF_CHECK`, and a priority above 0 on the stored networks.

## 4. ISP outage with the router answering

### Stock system behaviour

Both stacks see an association and an address and do nothing. A watchdog that reboots on lost internet reboots every few minutes for the whole outage.

### AWACS behaviour

The loss is declared later here than on a dead link: the gateway keeps answering, so one patient check runs before the third failed quick check counts, and recovery starts about 72 to 83 seconds after the loss instead of 40 to 63. The first recovery keeps the association it has: the reassociate is skipped, the network the device is on is left out of the candidates, and failed attempts end back on it. After every other visible stored network has been activated and found without internet, the gateway ping passes, so the outage is external: no rung, and the reboot timer stays at zero. Each round still tries the emergency and open networks, because another network may have another upstream, then waits 20 seconds; a recovery has three rounds and a new one starts every tick while the outage lasts. Site lines spool meanwhile and are delivered in order once the link is back.

```text
2026-01-01T16:00:30+03:00 [WARN] internet lost on HomeNet - router still answers, engaging
2026-01-01T16:00:31+03:00 [INFO] router answers on HomeNet - keeping the link, trying the other stored networks first
2026-01-01T16:00:57+03:00 [INFO] scan heard 6 networks: HomeNet -48, OfficeNet -61, Cafe -70, Guest -74, N5 -80, N6 -85 | known on the air: HomeNet, OfficeNet | stored, not heard: none
2026-01-01T16:00:58+03:00 [INFO] trying OfficeNet
2026-01-01T16:01:39+03:00 [WARN] could not connect to OfficeNet: linked but no internet - trying the next
2026-01-01T16:01:40+03:00 [INFO] outage looks external: the router answers, the fault is upstream (round 1) — waiting, not rebooting
2026-01-01T16:01:50+03:00 [INFO] trying emergency networks (1 listed)
2026-01-01T16:02:24+03:00 [WARN] emergency network PhoneHotspot refused: never associated - trying the next
2026-01-01T16:02:24+03:00 [INFO] no emergency network delivered (1 tried, 0 skipped)
2026-01-01T16:02:25+03:00 [INFO] trying open networks as last resort (2 open networks heard)
2026-01-01T16:02:58+03:00 [WARN] open network Cafe linked but no internet (captive portal?) - trying the next
2026-01-01T16:03:30+03:00 [INFO] no open network delivered internet (2 heard, 2 tried, 1 linked without internet)
2026-01-01T16:48:10+03:00 [OK] internet restored: HomeNet - down 47 min, 12 recovery runs
2026-01-01T16:48:10+03:00 [INFO] repeated 35 more times during the outage (last at 16:47): outage looks external: the router answers, the fault is upstream — waiting, not rebooting
```

The emergency and open attempts repeat in every round until the upstream returns; the verdict, the refusals and the walk's closing lines are said once per outage and counted, and the counts follow `internet restored`. On nm, a device reported connected while the gateway is silent takes the same branch with `NetworkManager is connected, internet is not (round N) — router-side, no rung`.

### Knobs involved

`NET_FAIL_TICKS`, `SAFETY_NET`, `OPEN_NETWORKS`, `SPOOL_CAP`, `LOG_TARGET`.

## 5. Device-side wedge: deaf radio and the reboot

### Stock system behaviour

The radio stops hearing anything. wpa_supplicant scans and finds nothing, indefinitely; NetworkManager leaves the device disconnected or unavailable. Nothing reloads the firmware or reboots the device.

### AWACS behaviour

Three scans in a row with nothing from any source drop the stale picture; a radio that hears nothing is a device-side sign, so the reboot timer starts. The ladder runs L1, L2 and L3 with the emergency and open attempts after each rung, and the following recoveries repeat it. When the evidence has persisted for `REBOOT_AFTER_MIN` minutes without a healthy tick, the reboot line is written, the outage story is saved beside the log, and the device reboots. On nm the timer runs only once NetworkManager has settled in disconnected or failed on two consecutive rounds; state 20 (unavailable) never starts it.

```text
2026-01-01T18:00:30+03:00 [WARN] internet lost on HomeNet - router none (not associated), engaging
2026-01-01T18:00:31+03:00 [INFO] router not answering - waiting up to 25 s for wlan0 to reconnect
2026-01-01T18:01:05+03:00 [WARN] radio heard nothing on 3 scans in a row - previous results dropped
2026-01-01T18:01:05+03:00 [INFO] scan heard 0 networks | known on the air: none | stored, not heard: HomeNet, OfficeNet
2026-01-01T18:01:06+03:00 [DEBUG] fight round 1: ME evidence (LINK_OK=0, gw unreachable, auth_failing=0)
2026-01-01T18:01:06+03:00 [WARN] fault looks on the device: the radio hears no network at all - recovery follows
2026-01-01T18:01:06+03:00 [WARN] reboot clock armed - the device reboots after 18:31 unless the internet returns or the fault reads external
2026-01-01T18:01:07+03:00 [WARN] recover L1: radio bounce
2026-01-01T18:01:15+03:00 [INFO] trying emergency networks (1 listed)
2026-01-01T18:01:50+03:00 [INFO] trying open networks as last resort (0 open networks heard)
2026-01-01T18:02:40+03:00 [WARN] recover L2: restart dhcpcd (respawns the REAL per-interface supplicant)
2026-01-01T18:04:10+03:00 [WARN] recover L3: reload brcmfmac firmware (the 3-second cure a wedge needs)
2026-01-01T18:31:10+03:00 [ERROR] rebooting now: wedged 30 min (the radio hears no network at all) - reboot 1 for this fault, the story continues after the boot
2026-01-01T18:33:20+03:00 [INFO] AWACS 1.0 starting on wlan0 (device mydevice) - wpa backend, first start of this boot, up 45 s
2026-01-01T18:33:20+03:00 [WARN] starting after the reboot AWACS ordered at 2026-01-01 18:31 - wedged 30 min (the radio hears no network at all), 9 recovery runs before it
```

After the reboot the timer starts from zero; a wedge that survives the reboot earns the next one only after another full window, and the count in the reboot line climbs (`reboot 2 for this fault`) until a healthy tick clears it. The outage story, the reboot line and the two lines after it reach the site in that order once the device is back online: the spool was copied beside the log before the reboot and restored at this start.

### Knobs involved

`REBOOT_AFTER_MIN`, `NET_FAIL_TICKS`, `SCAN_TTL`.

## 6. Slow link with a faster stored network available

### Stock system behaviour

Nothing. A connected link is a connected link.

### AWACS behaviour

The passive meter reads the transmit counter every tick. A rate between 20 kbps and the floor for `UP_STRIKES` ticks in a row, with the cooldown elapsed, starts an evaluation with one upload probe of the current network. A probe above the floor ends it (`measured 800 kbps on HomeNet - above the 400 kbps floor, staying`): the meter saw a small feed, not a slow link. A probe under the floor, here 250 kbps, sets the bar for a challenger at `SWITCH_GAIN_PCT` percent of that, 375 kbps; every other visible stored network is activated and probed, and the best one above the bar is kept.

```text
2026-01-01T20:01:27+03:00 [WARN] sustained slow upload on HomeNet (107 kbps for 3 samples, floor 400) - evaluating known networks
2026-01-01T20:01:28+03:00 [INFO] scan heard 6 networks: HomeNet -48, OfficeNet -61, Cafe -70, Guest -74, N5 -80, N6 -85 | known on the air: HomeNet, OfficeNet | stored, not heard: none
2026-01-01T20:01:40+03:00 [INFO] measured 250 kbps on HomeNet - under the 400 kbps floor, a challenger must beat 375 kbps
2026-01-01T20:01:41+03:00 [INFO] trying OfficeNet
2026-01-01T20:01:58+03:00 [INFO] candidate [1] OfficeNet uploads at 1620 kbps
2026-01-01T20:01:58+03:00 [INFO] switching to OfficeNet (1620 kbps against 250 kbps here) - plainly fast, over 4x the 400 kbps floor, probing stopped at it
2026-01-01T20:02:20+03:00 [OK] switched to OfficeNet (upload 1620 kbps)
```

When no candidate clears the bar the daemon goes back: `no challenger beat the incumbent - staying on HomeNet (best was OfficeNet at 300 kbps, needed 375)`. Slow samples that ripen again inside the cooldown are said once per window, `upload still slow on HomeNet (107 kbps, floor 400) - evaluation on cooldown, next look in 12 min`. Under a live stream the evaluation starts from `live stream starving on HomeNet (N kbps for 3 samples, floor 50) - evaluating known networks`, and only when the stream itself runs below `STREAM_MIN_KBPS`.

### Knobs involved

`MIN_UP_KBPS`, `UP_STRIKES`, `SWITCH_GAIN_PCT`, `DANCE_COOLDOWN`, `PROBE_KB`, `PROBE_URL`, the night variants `NIGHT_MIN_UP_KBPS`, `NIGHT_GAIN_PCT` and `NIGHT_DANCE_COOLDOWN`, and `STREAM_MIN_KBPS`.

## 7. The daemon dies while on a temporary network

### Stock system behaviour

Not applicable. A profile created with `nmcli device wifi connect` would persist under `/etc` and nothing would remove it.

### AWACS behaviour

The entry's id was written to `/run/awacs/open_id` before the attempt. The launcher (the rc.local loop or the systemd unit, 10 seconds later) starts a new daemon, which removes the entry at start: on wpa `remove_network` for the recorded id; on nm a guarded delete of the recorded profile, then a sweep of every `awacs-*` profile and `/run` keyfile. Removing the entry drops the link, so the new daemon is offline and starts recovery at once, without the `NET_FAIL_TICKS` wait; the removal and the boot-time loss have their own lines, and the win is announced on the first healthy tick. If the previous daemon ended by an error rather than a kill, its `AWACS exited unexpectedly (status N, last command ...: ...) - the launcher restarts it in 10 s` line stands above the start line once the spool is delivered.

```text
2026-01-01T22:00:00+03:00 [INFO] AWACS 1.0 starting on wlan0 (device mydevice) - wpa backend, restart 1 of this boot
2026-01-01T22:00:01+03:00 [WARN] removed the temporary network FreeCafe left by the previous run - the device was still on it, recovery follows
2026-01-01T22:00:05+03:00 [WARN] no internet at start on wlan0 - router none (not associated), engaging
2026-01-01T22:00:06+03:00 [INFO] router not answering - waiting up to 25 s for wlan0 to reconnect
2026-01-01T22:01:24+03:00 [INFO] scan heard 4 networks: FreeCafe -55, Guest -70, N5 -80, N6 -85 | known on the air: none | stored, not heard: HomeNet, OfficeNet
2026-01-01T22:01:25+03:00 [INFO] outage looks external: none of your 2 stored networks is on the air, 4 others heard (round 1) — waiting, not rebooting
2026-01-01T22:01:32+03:00 [INFO] trying emergency networks (1 listed)
2026-01-01T22:02:08+03:00 [INFO] trying open networks as last resort (1 open networks heard)
2026-01-01T22:02:40+03:00 [OK] connected to OPEN network: FreeCafe (upload 640 kbps) - stored networks stay armed, home again when one returns
2026-01-01T22:02:53+03:00 [OK] internet restored: FreeCafe - down 2 min, 1 recovery run
```

If a stored network has come back meanwhile, the recovery joins it instead.

### Knobs involved

`RUN_DIR` (the marker's location), `SAFETY_NET`, `OPEN_NETWORKS`.

## 8. A hidden home network

### Stock system behaviour

wpa_supplicant joins a hidden network only when its network block carries `scan_ssid=1`; NetworkManager only when the profile carries `hidden=yes`. A broadcast scan lists the access point without a name.

### AWACS behaviour

On wpa the daemon sets `scan_ssid 1` on every stored network at start, at every recovery and after rungs L2 and L3, at run time only, so a home block without the line still works while the daemon runs. The preferred-network check first asks the supplicant for its own scan and takes the union of the `iw` picture and `wpa_cli scan_results`, which names the hidden network. During recovery, when the `iw` scan succeeds it does not name the network, so it is not a measured candidate, and the supplicant itself associates to it after the gentle opening or a rung, with the daemon crediting the result; when the scan falls back to the supplicant's table the network is named and becomes a candidate. An air of only hidden networks keeps the previous scan picture and is not a deaf radio. On nm the profile must carry `hidden=yes`; NetworkManager probes for it and lists it, and the daemon never writes the property. `evaluate` lists a hidden network among the stored networks not on the air, because the broadcast scan carries no name for it.

```text
2026-01-01T07:00:30+03:00 [WARN] internet lost on HomeNet - router silent too, engaging
2026-01-01T07:00:31+03:00 [INFO] router not answering - waiting up to 25 s for wlan0 to reconnect
2026-01-01T07:01:05+03:00 [OK] internet restored: HomeNet - down 35 s, 1 recovery run
```

### Knobs involved

`PREF_CHECK`; the network configuration (`scan_ssid=1` optional on wpa, `hidden=yes` required on nm).

## 9. Running without a reporting site (signal mode)

### Stock system behaviour

Not applicable.

### AWACS behaviour

With `SITE_URL` and `PROBE_URL` empty there is nothing to upload to. The internet check has three rungs instead of four. Recovery joins the strongest visible stored network that delivers internet, in signal order, without measuring; the slow-link evaluation, the comparison and the arrival veto are off, and the preferred-network return still works. Nothing is posted and the spool is unused; a `LOG_TARGET` other than `local` is downgraded with `LOG_TARGET asked for the site but SITE_URL is empty - running local-only`. `speed` reports that there is no probe target. Setting `PROBE_URL` alone (any URL that accepts a POST body) restores measured choice without a site log.

```text
2026-01-01T08:00:00+03:00 [INFO] AWACS 1.0 starting on wlan0 (device mydevice) - wpa backend, first start of this boot, up 38 s
2026-01-01T08:00:00+03:00 [INFO] reporting: local | probe: none - signal mode | wifi cell: auto
2026-01-01T08:00:01+03:00 [INFO] running with: signal mode (no probe target - networks chosen by signal), reboot after 30 min wedged, wifi cell off (no SITE_URL), 2 stored networks, 1 emergency, open networks yes, stamps in the device zone
2026-01-01T08:00:04+03:00 [OK] online at start via HomeNet
2026-01-01T09:10:30+03:00 [WARN] internet lost on HomeNet - router silent too, engaging
2026-01-01T09:10:31+03:00 [INFO] router not answering - waiting up to 25 s for wlan0 to reconnect
2026-01-01T09:10:54+03:00 [INFO] scan heard 5 networks: OfficeNet -61, Cafe -70, Guest -74, N5 -80, N6 -85 | known on the air: OfficeNet | stored, not heard: HomeNet
2026-01-01T09:10:55+03:00 [INFO] trying OfficeNet
2026-01-01T09:11:20+03:00 [OK] connected: OfficeNet (signal mode - no upload probe target configured)
2026-01-01T09:11:20+03:00 [OK] internet restored: OfficeNet - down 50 s, 1 recovery run
2026-01-01T09:31:30+03:00 [INFO] higher-priority network HomeNet visible twice - leaving OfficeNet to go home
2026-01-01T09:31:50+03:00 [OK] returned to preferred network: HomeNet (signal mode)
```

### Knobs involved

`SITE_URL`, `PROBE_URL`, `LOG_TARGET`, `REPORT_WIFI`.

[features.md](features.md) lists every capability; [troubleshooting.md](troubleshooting.md) explains each log line; [configuration.md](configuration.md) has the knob table.
