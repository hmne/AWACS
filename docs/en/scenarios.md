# Scenarios

Nine situations, each in three parts: what a stock system does, what AWACS does with its log lines in order, and the knobs involved. Timestamps and names in the samples are illustrative. `HomeNet` and `OfficeNet` are stored networks, `PhoneHotspot` is an entry in `SAFETY_NET`, `FreeCafe` is an open network and `mydevice` is the device id. Samples show the wpa backend; on nm the rung lines read `recover L1: radio bounce`, `recover L2: re-kick NetworkManager on wlan0` and `recover L3: restart NetworkManager + reload WiFi firmware`. Samples omit repeated lines: the emergency and open attempts follow every rung, and the DEBUG evidence line is logged at every round with device-side evidence.

## 1. Wrong password on the only reachable network

### Stock system behaviour

wpa_supplicant fails the handshake, marks the network `TEMP-DISABLED` for a growing interval and retries on its own timer. NetworkManager retries the profile a few times and leaves the device disconnected. Neither tries another network, and a watchdog that reboots on lost internet reboots without end.

### AWACS behaviour

The signs resemble a fault on the device (network on the air, cannot be joined, no gateway), but the credentials sign is present, so the reboot timer is set back to zero at every round. The ladder still runs, because a wedge can coincide with a stale password, and emergency and open networks follow each rung. With the correct password in place the next recovery succeeds.

```text
[WARN][01/01 10:00:30] internet lost on wlan0 - engaging
[ERROR][01/01 10:01:20] association refused - wrong password? (recovery continues, reboot stays off)
[WARN][01/01 10:01:21] recover L1: radio bounce
[INFO][01/01 10:01:30] trying emergency networks (1 listed)
[INFO][01/01 10:02:05] trying open networks as last resort
[ERROR][01/01 10:03:10] association refused - wrong password? (recovery continues, reboot stays off)
[WARN][01/01 10:03:12] recover L2: restart dhcpcd (respawns the REAL per-interface supplicant)
[WARN][01/01 10:05:30] recover L3: reload brcmfmac firmware (the 3-second cure a wedge needs)
[OK][01/01 10:06:05] internet restored: HomeNet
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
[WARN][01/01 12:00:30] internet lost on wlan0 - engaging
[INFO][01/01 12:01:10] candidate [1] OfficeNet uploads at 1484 kbps
[OK][01/01 12:01:12] connected: OfficeNet (upload 1484 kbps)
[OK][01/01 12:01:12] internet restored: OfficeNet
[INFO][01/01 12:21:30] higher-priority network visible - trying to go home
[OK][01/01 12:21:50] returned to preferred network: HomeNet (upload 7445 kbps)
```

Had `HomeNet` measured under the floor on arrival, the line would be `preferred network too slow (N kbps) - benching it, going back`, and `HomeNet` is left alone for three cooldowns.

### Knobs involved

`PREF_CHECK`, `MIN_UP_KBPS` and `NIGHT_MIN_UP_KBPS`, `DANCE_COOLDOWN` (the veto lasts three of them), `PROBE_KB`, and the priorities in the network configuration (wpa `priority=`, nm `connection.autoconnect-priority`); the return needs the home priority strictly higher than the current one.

## 3. Every stored network gone

### Stock system behaviour

Nothing. Both stacks know only the stored networks.

### AWACS behaviour

No stored network is on the air, other networks are, and the gateway is silent: none of the three device-side signs applies, so the round is classified external and no rung runs. `SAFETY_NET` entries are tried whether or not the scan shows them, then open networks. The network joined is a temporary entry with priority 0. When a stored network with a higher priority reappears, the preferred-network check brings the device home and the entry is removed on the next healthy tick; no `awacs-*` profile remains on nm and no extra network id in the live supplicant on wpa.

```text
[WARN][01/01 14:00:30] internet lost on wlan0 - engaging
[INFO][01/01 14:01:55] outage looks external (round 1) — waiting, not rebooting
[INFO][01/01 14:02:02] trying emergency networks (1 listed)
[INFO][01/01 14:02:38] trying open networks as last resort
[OK][01/01 14:03:10] connected to OPEN network: FreeCafe
[OK][01/01 14:03:11] internet restored: FreeCafe
[INFO][01/01 14:42:30] higher-priority network visible - trying to go home
[OK][01/01 14:43:08] returned to preferred network: HomeNet (upload 2302 kbps)
```

Here the hotspot was off; with it on, the lines would be `connected to EMERGENCY network: PhoneHotspot` and `internet restored: PhoneHotspot`, and no open network is tried.

### Knobs involved

`SAFETY_NET`, `OPEN_NETWORKS`, `PREF_CHECK`, and a priority above 0 on the stored networks.

## 4. ISP outage with the router answering

### Stock system behaviour

Both stacks see an association and an address and do nothing. A watchdog that reboots on lost internet reboots every few minutes for the whole outage.

### AWACS behaviour

The loss is declared later here than on a dead link: the gateway keeps answering, so one patient check runs before the third failed quick check counts, and recovery starts about 72 to 83 seconds after the loss instead of 40 to 63. The first recovery keeps the association it has: the reassociate is skipped, the network the device is on is left out of the candidates, and failed attempts end back on it. After every other visible stored network has been activated and found without internet, the gateway ping passes, so the outage is external: no rung, and the reboot timer stays at zero. Each round still tries the emergency and open networks, because another network may have another upstream, then waits 20 seconds; a recovery has three rounds and a new one starts every tick while the outage lasts. Site lines spool meanwhile and are delivered in order once the link is back.

```text
[WARN][01/01 16:00:30] internet lost on wlan0 - engaging
[INFO][01/01 16:01:40] outage looks external (round 1) — waiting, not rebooting
[INFO][01/01 16:01:50] trying emergency networks (1 listed)
[INFO][01/01 16:02:25] trying open networks as last resort
[INFO][01/01 16:03:00] outage looks external (round 2) — waiting, not rebooting
[OK][01/01 16:48:10] internet restored: HomeNet
```

The three-line group repeats for every round until the upstream returns. On nm, a device reported connected while the gateway is silent takes the same branch with `NetworkManager is connected, internet is not (round N) — router-side, no rung`.

### Knobs involved

`NET_FAIL_TICKS`, `SAFETY_NET`, `OPEN_NETWORKS`, `SPOOL_CAP`, `LOG_TARGET`.

## 5. Device-side wedge: deaf radio and the reboot

### Stock system behaviour

The radio stops hearing anything. wpa_supplicant scans and finds nothing, indefinitely; NetworkManager leaves the device disconnected or unavailable. Nothing reloads the firmware or reboots the device.

### AWACS behaviour

Three scans in a row with nothing from any source drop the stale picture; a radio that hears nothing is a device-side sign, so the reboot timer starts. The ladder runs L1, L2 and L3 with the emergency and open attempts after each rung, and the following recoveries repeat it. When the evidence has persisted for `REBOOT_AFTER_MIN` minutes without a healthy tick, the reboot line is written to the local log and the device reboots. On nm the timer runs only once NetworkManager has settled in disconnected or failed on two consecutive rounds; state 20 (unavailable) never starts it.

```text
[WARN][01/01 18:00:30] internet lost on wlan0 - engaging
[WARN][01/01 18:01:05] radio heard nothing on 3 scans in a row - previous results dropped
[DEBUG][01/01 18:01:06] fight round 1: ME evidence (LINK_OK=0, gw unreachable, auth_failing=0)
[WARN][01/01 18:01:07] recover L1: radio bounce
[INFO][01/01 18:01:15] trying emergency networks (1 listed)
[INFO][01/01 18:01:50] trying open networks as last resort
[WARN][01/01 18:02:40] recover L2: restart dhcpcd (respawns the REAL per-interface supplicant)
[WARN][01/01 18:04:10] recover L3: reload brcmfmac firmware (the 3-second cure a wedge needs)
[ERROR][01/01 18:31:10] wedged 30min with networks visible — rebooting (repeats per streak until cured)
[INFO][01/01 18:33:20] AWACS 1.0 starting on wlan0 (device mydevice)
```

After the reboot the timer starts from zero; a wedge that survives the reboot earns the next one only after another full window.

### Knobs involved

`REBOOT_AFTER_MIN`, `NET_FAIL_TICKS`, `SCAN_TTL`.

## 6. Slow link with a faster stored network available

### Stock system behaviour

Nothing. A connected link is a connected link.

### AWACS behaviour

The passive meter reads the transmit counter every tick. A rate between 20 kbps and the floor for `UP_STRIKES` ticks in a row, with the cooldown elapsed, starts an evaluation with one upload probe of the current network. A probe above the floor ends it: the meter saw a small feed, not a slow link. A probe under the floor, here 250 kbps, sets the bar for a challenger at `SWITCH_GAIN_PCT` percent of that, 375 kbps; every other visible stored network is activated and probed, and the best one above the bar is kept.

```text
[WARN][01/01 20:01:27] sustained slow upload (107 kbps) - evaluating known networks
[INFO][01/01 20:01:58] candidate [1] OfficeNet uploads at 1620 kbps
[OK][01/01 20:02:20] connected: OfficeNet (upload 1620 kbps)
```

When no candidate clears the bar the daemon goes back: `no challenger beat the incumbent - staying on HomeNet`. Under a live stream the evaluation starts from `live stream starving (N kbps) - evaluating known networks`, and only when the stream itself runs below `STREAM_MIN_KBPS`.

### Knobs involved

`MIN_UP_KBPS`, `UP_STRIKES`, `SWITCH_GAIN_PCT`, `DANCE_COOLDOWN`, `PROBE_KB`, `PROBE_URL`, the night variants `NIGHT_MIN_UP_KBPS`, `NIGHT_GAIN_PCT` and `NIGHT_DANCE_COOLDOWN`, and `STREAM_MIN_KBPS`.

## 7. The daemon dies while on a temporary network

### Stock system behaviour

Not applicable. A profile created with `nmcli device wifi connect` would persist under `/etc` and nothing would remove it.

### AWACS behaviour

The entry's id was written to `/run/awacs/open_id` before the attempt. The launcher (the rc.local loop or the systemd unit, 10 seconds later) starts a new daemon, which removes the entry at start: on wpa `remove_network` for the recorded id; on nm a guarded delete of the recorded profile, then a sweep of every `awacs-*` profile and `/run` keyfile. Removing the entry drops the link, so the new daemon is offline and starts recovery at once, without the `NET_FAIL_TICKS` wait and without an `internet lost` line.

```text
[INFO][01/01 22:00:00] AWACS 1.0 starting on wlan0 (device mydevice)
[INFO][01/01 22:01:25] outage looks external (round 1) — waiting, not rebooting
[INFO][01/01 22:01:32] trying emergency networks (1 listed)
[INFO][01/01 22:02:08] trying open networks as last resort
[OK][01/01 22:02:40] connected to OPEN network: FreeCafe
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
[WARN][01/01 07:00:30] internet lost on wlan0 - engaging
[OK][01/01 07:01:05] internet restored: HomeNet
```

### Knobs involved

`PREF_CHECK`; the network configuration (`scan_ssid=1` optional on wpa, `hidden=yes` required on nm).

## 9. Running without a reporting site (signal mode)

### Stock system behaviour

Not applicable.

### AWACS behaviour

With `SITE_URL` and `PROBE_URL` empty there is nothing to upload to. The internet check has three rungs instead of four. Recovery joins the strongest visible stored network that delivers internet, in signal order, without measuring; the slow-link evaluation, the comparison and the arrival veto are off, and the preferred-network return still works. Nothing is posted and the spool is unused; a `LOG_TARGET` other than `local` is downgraded with `LOG_TARGET asked for the site but SITE_URL is empty - running local-only`. `speed` reports that there is no probe target. Setting `PROBE_URL` alone (any URL that accepts a POST body) restores measured choice without a site log.

```text
[INFO][01/01 08:00:00] AWACS 1.0 starting on wlan0 (device mydevice)
[INFO][01/01 08:00:00] reporting: local | probe: none - signal mode | wifi cell: auto
[WARN][01/01 09:10:30] internet lost on wlan0 - engaging
[OK][01/01 09:11:20] connected: OfficeNet (signal mode - no upload probe target configured)
[OK][01/01 09:11:20] internet restored: OfficeNet
[INFO][01/01 09:31:30] higher-priority network visible - trying to go home
[OK][01/01 09:31:50] returned to preferred network: HomeNet (signal mode)
```

### Knobs involved

`SITE_URL`, `PROBE_URL`, `LOG_TARGET`, `REPORT_WIFI`.

[features.md](features.md) lists every capability; [troubleshooting.md](troubleshooting.md) explains each log line; [configuration.md](configuration.md) has the knob table.
