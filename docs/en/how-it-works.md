# How it works

The daemon in the order it runs. Text in backticks is the script's own: a knob, a command, or a log line quoted as printed. `N`, `X` and `ID` stand for a number, a network name and a network id; `IF` stands for the interface name. Story lines are quoted in English; with `LOG_LANG=ar` the local log carries the program's Arabic text instead, and `DEBUG` lines stay English.

## Start-up

`awacs.sh` with no argument is the daemon; `check` and `help` run without root, everything else needs root. `/etc/awacs.conf` is sourced when it is owned by root and neither group nor others can read or write it (mode `0600` is the script's own advice); every knob is validated and falls back to its default when malformed ([configuration.md](configuration.md)), and `LOG_TARGET` `both` or `remote` without `SITE_URL` is downgraded to `local`. The interface is `AWACS_IF`, else the best of `iw dev` (connected, then up, then present), else `wlan0`. `/run/awacs` holds the lock, the scan cache, the spool and the temporary-network marker; a second daemon fails the lock and exits.

The backend is `wpa` when NetworkManager is neither active nor enabled, `nm` when it is, and `nm_lame` when NetworkManager is present but `nmcli` is missing or the interface is unmanaged; a start waits up to 60 s for NetworkManager to become active first. Under `nm` any call into `wpa_cli` is logged as `BUG: wpa_cli reached under nm backend: ...`.

The first two log lines are `AWACS 1.0 starting on wlan0 (device mydevice)` and `reporting: both -> https://example.org | probe: https://example.org/mydevice/receiver.php | wifi cell: auto | lang: local <en|ar>, site <en|ar>` (`reporting: local | probe: none - signal mode | wifi cell: auto | lang: local <en|ar>, site <en|ar>` without a site). A missing interface logs `interface wlan0 not present - is the WiFi hardware alive?`, a missing tool `missing tools: ... - will try to install once online`, the nm backend `NetworkManager backend - AWACS supervises it (full capability)`. Then `rfkill unblock wifi` (on nm also `nmcli radio wifi on`), power save off, `stealth mode active (icmp hidden, avahi stopped)` when `STEALTH_MODE` is `yes`, removal of a temporary network left by a previous daemon, `enable_all` (every stored network re-enabled: `enable_network all` on wpa, `nmcli -w 5 device connect IF` on nm when the device is disconnected or failed) and on wpa `arm_hidden` (`scan_ssid 1` on every stored network in the live supplicant). With internet the spool is flushed; without it recovery starts before the first tick.

## The tick

Every `TICK` seconds the daemon applies the day or night profile (`night profile active (floor N kbps)` or `day profile active (floor N kbps)`, logged on a transition only) and runs the internet check; the first passing rung means online:

1. `ping -c 1 -W 2 8.8.8.8`
2. `ping -c 1 -W 2 1.1.1.1`
3. HTTP 204 from `http://connectivitycheck.gstatic.com/generate_204`, 3 s limit
4. HTTP 400 from `${SITE_URL}/${DEVICE_ID}/${SITE_API}` for a POST carrying `probe=1`, 3 s limit; only when `SITE_URL` is set

Both HTTP rungs compare the exact status code, so a captive portal's 200 or 302 reads as offline; a link where ping works but DNS does not reads as online.

The same four steps also run in a patient form, used only where a busy link would otherwise be misread: three pings per target 0.3 s apart with a 5 s wait each, and an 8 s limit on both HTTP steps. Every tick starts with the quick form above, and the toolbox words `check` and `status` use that form only.

A failed quick check is not a failure by itself. The daemon reads the interface's `tx_bytes` counter before and after the check: 16384 bytes or more sent while the check was failing means the device was busy sending (an upload, a live stream), and one patient check then decides the tick. A link that sent less than that counts as failed at once, so a dead link keeps its old timing. The patient check is paid at most once per outage: after one has failed, every following tick is decided by the quick check alone, and any passing quick check clears that state. With `DEBUG=yes` the two outcomes are `quick check timed out under load (sent ${sent} B during it) - patient check passed` and `sent ${sent} B during the failed quick check, the patient check failed too - counting it`.

A healthy tick clears the failure counter and the reboot timer, logs `internet restored: X` after a recovery, flushes the spool (third healthy tick in a row, then every thirtieth), runs the once-per-boot tool install, sends the WiFi cell every six ticks, removes a temporary network once the device sits on another network, and runs the passive upload meter and the preferred-network return. On the tick that reaches `NET_FAIL_TICKS` one more test comes first, on two conditions: the link itself is alive (the default gateway answers a ping, or the kernel's neighbour table lists it `REACHABLE`) and no patient check has failed in this outage yet. That test is a patient check. When it passes, the tick counts as healthy, no recovery starts, and the local file carries `internet answers late, not never - slow link, no recovery (${NET_FAIL_TICKS} quick checks timed out)`; that line is never sent to the site. Otherwise the daemon logs `internet lost on wlan0 - engaging` once and runs a recovery on this and every following tick until the internet is back. With the defaults, a link whose gateway has gone silent engages 40 to 63 s after the loss, and an upstream outage on a link whose router keeps answering engages about 72 to 83 s after it; the difference is that one patient check.

## Recovery

A recovery returns as soon as the internet is verified. It removes the daemon's own temporary network, runs `enable_all` and `arm_hidden`, then reads the link. With a gateway that answers, the first recovery of an outage keeps the association: it skips the reassociate, remembers the network the device is on as the one to come back to, and only waits; with `DEBUG=yes` the skip is logged as `gentle open skipped: the link is alive (gateway reachable) - the outage is upstream`. The second recovery of the same outage reassociates anyway, because a router that answers a ping yet forwards nothing for this device is cured by a fresh association. With a dead link it reassociates at once (`wpa_cli reassociate`; on nm `nmcli -w 5 device connect IF` when the device is disconnected or failed). Either way it waits up to `ASSOC_WAIT` seconds for an IPv4 lease. Asking for the network the device already rides with an address never re-activates it: that network is proven where it stands, so a live association is not bounced. If the internet check still fails, three rounds follow. In each:

1. nm only: wait for NetworkManager to settle; a passing internet check ends the recovery. A device in a connecting state (40 to 90) or deactivating (110) logs `NM is still trying - waiting it out`: no stored network is tried, the round takes the external branch and the reboot timer is cleared.
2. Every visible stored network is tried and measured (below); a working one ends the recovery. When the link was alive at the start of the recovery, the remembered network is left out of that list and is the one the device is put back on when no other network delivered.
3. The outage is classified as on the device or external (next section), before any temporary network is attached, because attaching and detaching one drops the route and the association and would make every external outage look like a fault on the device.
4. On the device: the rung of this round (L1, L2, L3), the internet check, then the emergency networks, then the open networks. External: `outage looks external (round N) — waiting, not rebooting`; the reboot timer is cleared, the emergency and open networks are tried, and the round ends with a 20 s pause. A failed emergency or open attempt is followed by re-enabling every stored network, and on the external branch by a return to the remembered network, so no round runs its pause with the device parked on a stranger or with its stored networks left disabled.

After three losing rounds the reboot condition is evaluated; if it is not met, `enable_all` runs, the recovery returns failure and the next tick starts another.

### Recovery rungs

| Rung | wpa backend | nm backend |
| --- | --- | --- |
| L1 | `recover L1: radio bounce`: `rfkill unblock wifi`, `ip link set IF down`, 2 s, `up`, 3 s | `recover L1: radio bounce`: block and unblock the interface's own rfkill index, or `nmcli radio wifi off` and `on` without one; wait up to 15 s for NetworkManager to settle |
| L2 | `recover L2: restart dhcpcd (respawns the REAL per-interface supplicant)`: `systemctl restart dhcpcd` (else `wpa_supplicant`), 8 s, `arm_hidden`, power save off | `recover L2: re-kick NetworkManager on wlan0`: `nmcli device reapply IF`, 3 s; if still offline `nmcli device disconnect IF`, 1 s, `nmcli -w 5 device connect IF`, 8 s; power save off |
| L3 | `recover L3: reload brcmfmac firmware (the 3-second cure a wedge needs)`: `modprobe -r brcmfmac`, 2 s, `modprobe brcmfmac`, 8 s, `arm_hidden`, power save off | `recover L3: restart NetworkManager + reload WiFi firmware`: `systemctl restart NetworkManager`, 8 s, the same `brcmfmac` reload, every `awacs-*` keyfile under `/run/NetworkManager/system-connections` removed, `nmcli connection reload` |

`brcmfmac` is the driver of the Raspberry Pi WiFi chip; on other hardware the reload does nothing. On nm the daemon never runs `ip link set down` or `up` and never restarts `dhcpcd`.

### Emergency and open networks

Emergency networks are the `SAFETY_NET` entries of the conf, names with passwords (an empty password lists an open hotspot). With a non-empty list the daemon logs `trying emergency networks (N listed)` and tries each entry whether or not the scan shows it, since a hotspot is often switched on a moment ago or hidden; success is `connected to EMERGENCY network: X`. On wpa an entry whose name contains a backslash or a double quote, or whose password contains a double quote, is skipped; on nm a non-empty password must be 8 to 63 characters or 64 hex digits.

Open networks come last and only when `OPEN_NETWORKS` is `yes`: `trying open networks as last resort`, then every open network the scan shows, skipping signals below -80 dBm (wpa) or 25 % (nm) and, on wpa, non-ASCII names; success is `connected to OPEN network: X`.

Both are temporary entries, on wpa in the live supplicant, on nm a keyfile under `/run/NetworkManager/system-connections` named `awacs-safety-*` or `awacs-crutch-*` with `autoconnect=false`; the id is recorded in `/run/awacs/open_id` so that a crashed daemon's successor removes it. The entry is removed at the next recovery start, on a healthy tick once the device sits on another network, by rung L3 on nm, and at every daemon start. Nothing is written to `wpa_supplicant.conf` or `/etc/NetworkManager`.

## On-device fault versus external outage

A round is a fault on the device only when all of these hold: NetworkManager is not in a connecting state this round (nm); no default gateway on the interface answers a ping; no association with an IPv4 lease succeeded this round; and at least one sign is present: a stored network is visible yet could not be joined, the scan shows nothing at all, or the stored network list is empty. Anything else is external: a gateway that answers means the link works and the fault is upstream.

Inside the on-device branch a wrong password takes precedence. Its sign is a `TEMP-DISABLED` entry in `list_networks` on wpa, or on nm an activation error mentioning secrets or authentication, remembered for the rest of the recovery. The line is `association refused - wrong password? (recovery continues, reboot stays off)`; the rungs still run, because a stale hotspot password can coincide with a real fault, and the reboot timer is set to zero every time the sign is seen. With `DEBUG=yes` each on-device round also writes `fight round N: ME evidence (LINK_OK=0, gw unreachable, auth_failing=N)`, the last `N` being 1 when the wrong-password sign was seen and 0 otherwise.

On nm one more read follows: the daemon waits for NetworkManager to settle and checks the internet again. A device back in a connecting state logs `NM is still trying - waiting it out` and the round ends after 20 s with no rung. A device in state 100 (connected) without internet means the fault is behind the router: `NetworkManager is connected, internet is not (round N) — router-side, no rung`; the timer is cleared, the emergency and open networks are tried, and the round ends after 20 s.

## The reboot condition

The reboot timer records the first on-device classification of the current streak. On wpa it is set directly. On nm it is set only when NetworkManager has given up: device state 30 or 120 on two consecutive classifications with no connecting state seen between them, or an unreadable state while `nmcli` itself fails (exit 8) after rung L3 has already restarted NetworkManager; state 20 (unavailable) never sets it. The timer is cleared by a healthy tick, any successful connect, an external classification, the wrong-password sign, and on nm by any connecting-state sighting or any readable state other than 30 or 120.

At the end of a losing recovery, when the timer has been set for `REBOOT_AFTER_MIN` minutes (and on nm NetworkManager is still given up), the daemon writes `wedged Nmin with networks visible — rebooting (repeats per streak until cured)` to the local log only (the network is down and `/run` is tmpfs, so no copy can reach the site), runs `sync`, waits 2 s and reboots. After the reboot the timer starts from zero. No reboot happens for a wrong password, for an external outage, while NetworkManager is still trying, or while any network delivers internet. `REBOOT_AFTER_MIN` cannot be 0; the validator falls back to 30.

## NetworkManager supervision

On nm the daemon intervenes only after `NET_FAIL_TICKS` failing ticks and only once the device has left its connecting and deactivating states, waiting up to `ASSOC_WAIT` seconds for that. Stored profiles are joined with `nmcli connection up` by uuid. It never runs `nmcli device wifi connect`, which writes a profile to `/etc`, never `nmcli connection modify`, and downs or deletes a profile only when its name matches `awacs-crutch-*` or `awacs-safety-*` and its file lies under `/run/NetworkManager/system-connections`; anything else is refused with `REFUSING delete: 'name' is not an awacs crutch` or `REFUSING delete: 'name' lives outside /run (owner file?)`.

In `nm_lame` the daemon logs `NetworkManager image but AWACS cannot drive it (unmanaged/no nmcli) - monitoring only`, checks the internet every 300 s, flushes the spool and lets the tool install run once. When a missing `nmcli` was the reason and the install brought it, the daemon logs `nmcli is now installed - restarting as a full NetworkManager supervisor` and exits so that systemd or the `rc.local` loop restarts it (a `-d` start has no launcher and stays).

## Upload measurement and the switch rule

One measurement is one upload of `PROBE_KB` KB to `PROBE_URL`, else the endpoint, with `curl --data-binary`, 15 s limit; when curl reports 0 and `wget` exists the same upload is timed with `wget --post-file`. The result is in kbps.

A comparison walks the visible stored networks except the current one: connect, measure, log `candidate [ID] X uploads at N kbps`, keep the fastest, stop early when a candidate reaches four times the profile floor. The winner is joined: `connected: X (upload N kbps)`. Inside a recovery the floor is 0, so any working network beats none. Inside an evaluation the floor is the current network's measured speed times `SWITCH_GAIN_PCT` (`NIGHT_GAIN_PCT` at night) divided by 100; when nobody beats it the daemon goes back: `no challenger beat the incumbent - staying on X`.

An evaluation is triggered by the passive meter: each healthy tick samples the interface's `tx_bytes` counter for 3 s. A flow between 20 kbps and the profile floor (`MIN_UP_KBPS` by day, `NIGHT_MIN_UP_KBPS` at night) is a strike; any sample outside that band, an idle one below 20 kbps included, resets the strikes to zero. After `UP_STRIKES` strikes and at least `DANCE_COOLDOWN` (`NIGHT_DANCE_COOLDOWN`) seconds since the last evaluation, the daemon logs `sustained slow upload (N kbps) - evaluating known networks`, measures the current network once, and starts the comparison only when that measurement is under the floor. While a live stream runs (`raspistill` with `live_raw`, `preview.jpg` or `capture.jpg` on its command line, or `curl` with `upfile=@`; other workloads are not detected) the band is 5 kbps to `STREAM_MIN_KBPS` and the line is `live stream starving (N kbps) - evaluating known networks`; a stream above `STREAM_MIN_KBPS` is never interrupted.

## Preferred-network return

Every `PREF_CHECK` seconds, unless a stream runs, the daemon looks for a visible stored network whose priority is strictly higher than the current one's (wpa `priority`, nm `connection.autoconnect-priority`); on wpa a supplicant-side scan runs first so that hidden networks are seen. After two consecutive sightings: `higher-priority network visible - trying to go home`, a connect, and a measurement on arrival. Under the floor means `preferred network too slow (N kbps) - benching it, going back`: the candidate is ignored for three cooldowns and the previous network is rejoined. Otherwise `returned to preferred network: X (upload N kbps)`.

## Signal mode

Without `SITE_URL` and without `PROBE_URL` there is nothing to upload to; the reporting line says `probe: none - signal mode`. A comparison then walks the visible stored networks strongest first and keeps the first one that delivers internet: `connected: X (signal mode - no upload probe target configured)`. The passive meter counts no strikes, so no evaluation starts, and the preferred-network return does not measure on arrival: `returned to preferred network: X (signal mode)`. `awacs.sh speed` reports that no probe target is configured. Everything else, the internet check's first three rungs included, is unchanged.

## The spool

Every reported event goes to `/var/log/awacs.log` in the language `LOG_LANG` selects (with `LOG_TARGET=remote` only `WARN` and `ERROR`). With `SITE_URL` set and `LOG_TARGET` `both` or `remote`, a site copy `[LEVEL] AWACS: message, dd/mm/yyyy hh:mm:ss AM/PM.` is built in the language `SITE_LANG` selects (a line with no Arabic text stays English) and POSTed in the background as `file=log/log.txt` with a 4 s limit; when the POST fails, or while offline, the copy is appended to `/run/awacs/spool`. Above `SPOOL_CAP` lines, line 1 is kept and the newest `SPOOL_CAP - 1` lines follow it: the first line of an outage carries the time it began, so the middle of the story is what is dropped. A flush sends line by line, stops at the first failure and keeps the remainder in front of any new lines.

## Scanning and the deaf-radio rule

A scan lists every visible network strongest first and is cached in `/run/awacs/scan` for `SCAN_TTL` seconds. Sources, in order: `iw dev IF scan` (up to 3 tries 3 s apart, 6 within the first 180 s of uptime; one wait on `Device or resource busy`, since the supplicant or NetworkManager is scanning and its own table holds the answer), then `iwlist IF scan`, then that table (`wpa_cli scan_results`, or NetworkManager's list with `--rescan no`).

When every source is empty the daemon logs `scan failed - using previous results (if any)`, serves the old cache and refreshes its timestamp, so a silent radio is asked once per `SCAN_TTL`. Three such scans in a row mean the radio hears nothing: `radio heard nothing on 3 scans in a row - previous results dropped`, logged once, and the cache becomes an empty answer; from then on the scan-shows-nothing sign holds for classification and the reboot condition can be met on a dead radio. Any scan that hears a beacon, even a hidden one, ends the streak. Scans run by the toolbox words log these warnings locally only.

## Network names

On wpa, matching uses the escaped text both `iw` and `wpa_cli` print (`\xNN` for non-ASCII bytes); on nm, the lowercase hex of the SSID bytes. Display decodes both; hex is never displayed. The two wpa-only name limits are listed in [faq.md](faq.md).
