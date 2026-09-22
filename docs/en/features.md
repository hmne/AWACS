# Features

What `awacs.sh` does, grouped by area. Defaults in parentheses are the script's; `/etc/awacs.conf` overrides them ([configuration.md](configuration.md)). Log lines are quoted as printed; `N`, `NAME` and `ID` stand for the values the script fills in, and `wlan0` for the interface name.

## Connectivity and recovery

Internet check. Every `TICK` seconds (10): a ping to 8.8.8.8, a ping to 1.1.1.1, an HTTP request to `connectivitycheck.gstatic.com/generate_204` that must answer 204 and, when `SITE_URL` is set, a POST to the site endpoint that must answer 400. A captive portal answers 200 or 302 and counts as offline. The same four steps also run in a patient form where a busy link would otherwise be misread: three pings per target 0.3 s apart with a 5 s wait each, and 8 s limits on the HTTP steps. A failed quick check earns one patient check only when the interface sent 16384 bytes or more while it was failing, and only once per outage.

Recovery start. After `NET_FAIL_TICKS` (3) failed checks in a row the daemon logs `internet lost on wlan0 - engaging` once and starts recovery, repeated every tick until `internet restored: NAME`. On that tick, while the gateway still answers and no patient check has failed in this outage, one patient check runs first: when it passes, nothing is torn down and the local file records `internet answers late, not never - slow link, no recovery (${NET_FAIL_TICKS} quick checks timed out)`. Recovery starts 40 to 63 seconds after a loss on a link whose gateway has gone silent, and about 72 to 83 seconds after one on a link whose router keeps answering. A daemon that starts offline begins recovery at once.

Gentle opening. Each recovery re-enables every stored network, re-arms hidden-network probing, asks the base layer to reassociate and waits up to `ASSOC_WAIT` seconds (25) for an association and an IPv4 address before anything is torn down. While the gateway answers, the first recovery of an outage skips the reassociate and keeps the live association: the network the device is on is left out of the candidates and is the one it returns to. The second recovery of the same outage reassociates anyway. A network the device already rides with an address is proven where it stands, never re-activated.

Measured choice. Every stored network on the air is activated in turn and probed with a `PROBE_KB` (200) kilobyte upload to `PROBE_URL` or, when that is empty, the site endpoint, until one uploads at four times the floor: `candidate [ID] NAME uploads at N kbps`. The best one is kept: `connected: NAME (upload N kbps)`. Signal strength alone never decides.

Recovery ladder. One rung per round, each aimed at a different layer. wpa: `recover L1: radio bounce` (interface down and up), `recover L2: restart dhcpcd (respawns the REAL per-interface supplicant)`, `recover L3: reload brcmfmac firmware (the 3-second cure a wedge needs)`. nm: `recover L1: radio bounce` (the interface's own rfkill switch), `recover L2: re-kick NetworkManager on wlan0` (`nmcli device reapply`, then disconnect and connect), `recover L3: restart NetworkManager + reload WiFi firmware`.

Emergency networks. `SAFETY_NET` entries (name and password, in `/etc/awacs.conf`) are tried after the stored networks and before any open network, whether or not the scan shows them: `trying emergency networks (N listed)`, then `connected to EMERGENCY network: NAME`.

Open networks. With `OPEN_NETWORKS="yes"` (the default) open networks come last, one attempt per name, skipping signals under -80 dBm (wpa) or 25 % (nm): `trying open networks as last resort`, then `connected to OPEN network: NAME`.

Temporary entries. An emergency or open network is a temporary entry: on wpa a network id in the live supplicant, never saved; on nm a keyfile under `/run/NetworkManager/system-connections/` named `awacs-crutch-*` or `awacs-safety-*`, `autoconnect=false`, mode 0600. Its id is written to `/run/awacs/open_id` before the attempt, so the next daemon removes it if this one dies; it is removed as soon as a stored network is current again.

Hidden networks. On wpa the daemon sets `scan_ssid 1` on every stored network at start, at every recovery and after rungs L2 and L3, at run time only. On nm the profile must carry `802-11-wireless.hidden yes`; the daemon does not write it.

## Outage classification and the reboot condition

Gateway test. Before any rung, after every visible stored network has been activated and found without internet, the daemon pings the default gateway. An answer means the link works and the fault is upstream: `outage looks external (round N) — waiting, not rebooting`. No rung runs, the reboot timer stays at zero, emergency and open networks are still tried, and the round waits 20 seconds.

Three signs that the fault is on the device. With the gateway silent and no address this round, any one of these starts the reboot timer: a stored network is on the air and cannot be joined; the radio hears nothing; the stored list is empty. Logged at DEBUG level as `fight round N: ME evidence (LINK_OK=0, gw unreachable, auth_failing=N)`; the last `N` is 1 when the credentials sign is present, otherwise 0.

Wrong password. wpa marks the network `TEMP-DISABLED`; on nm the activation fails with a credentials message. The daemon logs `association refused - wrong password? (recovery continues, reboot stays off)`, resets the timer and keeps the ladder running.

Reboot condition. A reboot needs `REBOOT_AFTER_MIN` minutes (30) of uninterrupted on-device evidence with no healthy tick and no credentials sign; on nm NetworkManager must also have settled in disconnected or failed on two consecutive rounds, or `nmcli` must be exiting 8 after rung L3. `wedged 30min with networks visible — rebooting (repeats per streak until cured)` goes to the local log only, then `sync` and `reboot`; the timer then restarts from zero. The knob rejects 0: the reboot can be delayed, not disabled.

## NetworkManager supervision

Backend detection. NetworkManager active or enabled makes the backend `nm`, after up to 60 seconds waiting for the service: `NetworkManager backend - AWACS supervises it (full capability)`. Otherwise the backend is `wpa`.

Waiting NetworkManager out. While the device state is in the connecting band (40 to 90, or 110) no override is issued, `NM is still trying - waiting it out`, and the reboot timer resets. Every rung boundary re-checks; a device reported connected without internet takes the gateway branch: `NetworkManager is connected, internet is not (round N) — router-side, no rung`.

Deletion guard. `connection down` and `connection delete` run only through one function that refuses any profile not named `awacs-(crutch|safety)-<epoch>-<pid>` or stored outside `/run/NetworkManager/system-connections/`, logging `REFUSING delete: 'NAME' is not an awacs crutch` or `REFUSING delete: 'NAME' lives outside /run (owner file?)`.

Names in hex. Every name comparison on nm uses lowercase hex bytes, so non-ASCII characters, colons and backslashes match exactly, and any call reaching `wpa_cli` under nm is logged as `BUG: wpa_cli reached under nm backend:` and fails.

Monitor-only mode. An unmanaged interface or a missing `nmcli` parks the daemon: `NetworkManager image but AWACS cannot drive it (unmanaged/no nmcli) - monitoring only`. It still flushes the spool and attempts the tool install; once `nmcli` appears, `nmcli is now installed - restarting as a full NetworkManager supervisor` and an exit so the launcher restarts it.

## Link quality and switching

Slow-link evaluation. Each healthy tick reads the interface's transmit counter over 3 seconds. A rate between 20 kbps and the floor (`MIN_UP_KBPS`, 400) for `UP_STRIKES` (3) ticks in a row, `DANCE_COOLDOWN` seconds (1200) after the last evaluation: `sustained slow upload (N kbps) - evaluating known networks`. One probe of the current network follows; only a probe under the floor starts a comparison, and a challenger must reach `SWITCH_GAIN_PCT` (150) percent of that probe or the daemon returns: `no challenger beat the incumbent - staying on NAME`.

Live stream. While a process matching `raspistill` with `live_raw`, `preview.jpg` or `capture.jpg`, or `curl` with `upfile=@`, is running, its rate is the meter: between 5 kbps and `STREAM_MIN_KBPS` (50) for `UP_STRIKES` ticks gives `live stream starving (N kbps) - evaluating known networks`. A healthy stream is never interrupted by a probe, a switch or the preferred-network check.

Preferred-network return. Every `PREF_CHECK` seconds (600) the daemon looks for a visible stored network with a strictly higher priority (wpa `priority`, nm `connection.autoconnect-priority`). Two consecutive sightings: `higher-priority network visible - trying to go home`. Under the floor on arrival, `preferred network too slow (N kbps) - benching it, going back` and a veto for three cooldowns; otherwise `returned to preferred network: NAME (upload N kbps)`.

Signal mode. With neither `SITE_URL` nor `PROBE_URL`, recovery joins the strongest visible stored network that delivers internet, `connected: NAME (signal mode - no upload probe target configured)`; evaluation, comparison and arrival measurement are off.

## Scanning

Results are cached for `SCAN_TTL` seconds (30). A scan makes up to 3 attempts (6 in the first three minutes after boot); on `Device or resource busy` it waits 3 seconds once, then reads `iwlist` or the backend's own table (`wpa_cli scan_results`, `nmcli device wifi list --rescan no`). When every source returns nothing the previous picture is kept, `scan failed - using previous results (if any)`; three such scans in a row drop it, `radio heard nothing on 3 scans in a row - previous results dropped`. A scan that succeeds but names no network keeps the previous picture.

## Logging and reporting

Local log. `/var/log/awacs.log`, `[LEVEL][dd/mm HH:MM:SS] message`; past `LOG_CAP` (1500) plus 200 lines the file is cut back to `LOG_CAP`. `DEBUG="yes"` (the default; `AWACS_DEBUG` in the environment overrides it) adds decision-trace lines.

Site log. With `SITE_URL` set and `LOG_TARGET` `both` or `remote`, every event is also posted to `SITE_URL/DEVICE_ID/SITE_API` as `file=log/log.txt`, formatted `[LEVEL] AWACS: message, dd/mm/yyyy hh:mm:ss AM.` in the `SITE_TZ` zone; the site receives the Arabic text where the program has one. `remote` keeps only WARN and ERROR lines locally. The start-up line `reporting:` states the log target, the probe target and the WiFi cell setting.

Spool. Lines that cannot be sent go to `/run/awacs/spool`, at most `SPOOL_CAP` (60), the first line pinned so the outage's opening line survives. It drains in order after three healthy ticks, then every 30 ticks while lines remain.

WiFi cell. Every six healthy ticks the daemon posts `file=tmp/wifi.tmp` with `kbps,visible,total,band,SSID`; the speed is sent only when measured on the current network, otherwise 0. `REPORT_WIFI` is `auto` (on with the site log), `yes` or `no`.

Tools. At start: `missing tools: iw - will try to install once online`. At the third healthy tick one background `apt-get install` per boot with the Debian package names: `installing missing tools:`, then `tools installed:` or `tool install failed - still missing:`; without apt, `no apt-get on this system - install manually:`.

## Safety and hygiene

No writes to stored configuration. No `save_config`, no `disable_network`, no `nmcli connection modify`, no `nmcli device wifi connect`; `connection down` and `delete` only through the deletion guard. Every stored network is re-enabled at start, at every recovery start, after every success, on every failed recovery's exit and at shutdown.

Settings file. `/etc/awacs.conf` is read only when owned by root and neither readable nor writable by group or others; otherwise `awacs: IGNORING /etc/awacs.conf (group/world can access it — chmod 600 it)` or `awacs: IGNORING /etc/awacs.conf (not owned by root — chown root: it)` goes to stderr and the defaults apply. Numeric knobs must be non-zero numbers of at most seven digits, `NIGHT_START` and `NIGHT_END` must be `HH:MM`; anything else falls back to the default.

Runtime files. Everything under `RUN_DIR` (`/run/awacs`, mode 0700) is created with `umask 077`. Passwords go to the supplicant over stdin and to NetworkManager in a 0600 keyfile, never on a command line. `DEVICE_ID` must match `[A-Za-z0-9_-]{1,32}`; otherwise the short hostname, then `device`. `flock` on `/run/awacs/lock` keeps a single instance.

Stealth. `STEALTH_MODE="yes"` adds one `iptables` rule dropping ICMP echo requests on the interface and stops `avahi-daemon`: `stealth mode active (icmp hidden, avahi stopped)`. It is not access control.

Shutdown. On SIGINT, SIGTERM, SIGQUIT or SIGHUP the daemon re-enables all networks and exits 0.

## Toolbox

The toolbox words are `status`, `networks`, `evaluate`, `scan`, `speed`, `check` and `help`; `check` and `help` run without root on the built-in defaults, not `/etc/awacs.conf`, and [README.md](../../README.md) describes the output of each word. Any other word prints `usage: awacs.sh [status|networks|evaluate|scan|speed|check|help|-d]   (no argument = daemon)`; `-d` starts the daemon in the background and `-q` is ignored.

## Day and night profile

With `NIGHT_MODE="yes"` (the default) the floor, the gain and the cooldown switch from `MIN_UP_KBPS`, `SWITCH_GAIN_PCT` and `DANCE_COOLDOWN` to `NIGHT_MIN_UP_KBPS` (200), `NIGHT_GAIN_PCT` (300) and `NIGHT_DANCE_COOLDOWN` (2400) between `NIGHT_START` (22:00) and `NIGHT_END` (06:00); the window may cross midnight. Each transition is logged once: `night profile active (floor 200 kbps)` or `day profile active (floor 400 kbps)`.

## Installer, unit, receivers, dashboard

`install.sh`, the systemd unit and the terminal dashboard `tools/awacs-tui.sh` are described in [install.md](install.md). The two receivers, `server/receiver.php` and `server/receiver.py`, and the endpoint contract are described in [integration.md](integration.md).

## Limitations

- WiFi only: one wireless interface, no Ethernet fallback; a connection needs an IPv4 address.
- Live-stream detection is hard-wired to the two process patterns above; rung L3 reloads `brcmfmac` unconditionally, which does nothing on another chip.
- The reboot cannot be switched off, only delayed; the once-per-boot package install has no off switch.
- Site log lines carry the Arabic text where the program has one; open networks are joined by default; a network where ping answers but DNS is dead reads as online.
- wpa: open networks with non-ASCII names are skipped, and stored names or `SAFETY_NET` entries containing a backslash, a double quote, a tab, a line break, an escape character or an edge space never match or are skipped.
- nm: a hidden profile must carry `hidden=yes` itself; device state 20 (unavailable) never starts the reboot timer.

[scenarios.md](scenarios.md) shows nine situations in order; [how-it-works.md](how-it-works.md) describes the main loop; [troubleshooting.md](troubleshooting.md) explains each log line.
