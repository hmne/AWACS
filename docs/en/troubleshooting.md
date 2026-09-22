# Troubleshooting

Each entry is a line the script prints, its level, what it means and what to do. The local log is `/var/log/awacs.log`; a local line reads `[LEVEL][dd/mm HH:MM:SS] message`. Daemon stderr reaches `journalctl -u awacs` under systemd and nowhere under the rc.local loop; the two conf refusals below are best seen by running `sudo awacs.sh status` on a terminal, because every run as root sources the conf.

## Settings

### `awacs: IGNORING /etc/awacs.conf (not owned by root — chown root: it)`

Stderr, at every run as root. The conf is not owned by root, typically after a restore as another user; the daemon runs on defaults (no `SAFETY_NET`, no site). Fix: `sudo chown root:root /etc/awacs.conf`.

### `awacs: IGNORING /etc/awacs.conf (group/world can access it — chmod 600 it)`

Stderr, at every run as root. The mode has group or other bits (`0644`, `0640`); a conf that carries hotspot passwords is refused when anyone else can read or write it. Fix: `sudo chmod 600 /etc/awacs.conf`.

### A knob you set is not applied, with no message

The value failed validation and the default is in use; the silent fallback is deliberate, a typo must not stop the daemon. The rule for each knob is in [configuration.md](configuration.md). `SAFETY_NET` entries need the exact form `SAFETY_NET["Name"]="password"`. Fix: correct the line and restart the daemon.

### `LOG_TARGET asked for the site but SITE_URL is empty - running local-only`

WARN, local log, once at start. `LOG_TARGET` was `both` or `remote` without a `SITE_URL`; the target was downgraded to `local`. Fix: set `SITE_URL`, or set `LOG_TARGET="local"`.

### `reporting: local | probe: none - signal mode | wifi cell: auto`

INFO, local log, after the start line: the reporting knobs as applied. With a site the log target is followed by `->` and the site URL, and `probe:` names the probe target. `probe: none - signal mode` means neither `SITE_URL` nor `PROBE_URL` is set: no upload measurement and no switching by speed. If you set the knobs and still read `local`, the conf was not applied (the two refusals above) or `SITE_URL` failed validation.

## Start-up

### `missing tools: iw nmcli - will try to install once online`

ERROR, at start. The named tools are not in `PATH`; the inventory is `iw ip ping curl awk sed grep pgrep rfkill flock timeout stat date modprobe` plus `wpa_cli` (wpa) or `nmcli` (nm). At the third healthy tick one `apt-get install` runs in the background, once per boot (marker `/run/awacs/apt_tried`): `installing missing tools: <packages>`, then `tools installed: <packages>` or `tool install failed - still missing: <tools> - install manually`; without `apt-get`: `no apt-get on this system - install manually: <tools>`. Package names: `wpasupplicant`, `network-manager`, `iproute2`, `iputils-ping`, `mawk`, `procps`, `util-linux`, `coreutils`, `kmod`; other tools install under their own name. There is no knob to disable the attempt. Fix if it fails: install the packages by hand; the attempt repeats at the next boot.

### `interface wlan0 not present - is the WiFi hardware alive?`

ERROR, at start. No wireless interface in `iw dev`, no `wlan0` either, and the daemon proceeds against a name that has no device: a dead radio, an unplugged dongle, a missing driver, or `iw` itself missing (then `missing tools: iw` follows it). Fix: check `iw dev`, `rfkill list` and `dmesg | grep -i brcm`; set the environment variable `AWACS_IF` if the interface has an unusual name.

### `NetworkManager image but AWACS cannot drive it (unmanaged/no nmcli) - monitoring only`

ERROR, at start. NetworkManager is active or enabled, and either `nmcli` is missing or the interface is unmanaged (device state 10). The daemon parks: it checks the internet every 300 s, flushes the spool and lets the tool install run once; no recovery runs. For a missing `nmcli`, wait for the install or run `apt-get install --reinstall network-manager` yourself: `nmcli is now installed - restarting as a full NetworkManager supervisor` follows, the daemon exits for the respawn loop, and the next start logs `NetworkManager backend - AWACS supervises it (full capability)`. For an unmanaged interface, look for `unmanaged-devices` in `/etc/NetworkManager/NetworkManager.conf` and `/etc/NetworkManager/conf.d/`, or run `nmcli device set wlan0 managed yes`, then restart the daemon; the parked daemon does not re-detect by itself.

### `aasw.sh is still running - two WiFi authorities will fight; remove its rc.local line`

WARN, at start. A process whose command line contains `/usr/local/bin/aasw` is running: an older WiFi watchdog that competes for the radio. Fix: remove its launch line from `/etc/rc.local` and the file.

## Outages and recovery

### `internet lost on wlan0 - engaging`

WARN, once per outage. `NET_FAIL_TICKS` consecutive internet checks failed; recovery starts and repeats every tick until `internet restored: <network>` closes the outage. Not an error in itself; read the lines that follow.

### `internet answers late, not never - slow link, no recovery (${NET_FAIL_TICKS} quick checks timed out)`

INFO, local file only, at most once per outage. `NET_FAIL_TICKS` quick internet checks in a row timed out, but the link itself was alive (the default gateway answered, or the kernel's neighbour table reported it reachable) and one patient check, with three pings per target and 8-second HTTP limits, got an answer. The uplink is slow or saturated, not down: no loss line is written, no recovery runs and the tick counts as healthy. Fix: none. Seeing it often means an uplink whose answers regularly arrive after the quick check's 2 to 3 seconds, usually under a saturated upload; raise `TICK` or `NET_FAIL_TICKS` to give such a link more time before the daemon engages at all.

### `outage looks external (round 1) — waiting, not rebooting`

INFO, up to three times per recovery. The fault is not on the device: the gateway answers, or a network associated and obtained a lease in this round, or the radio hears networks but none of the stored ones, or on nm NetworkManager was still working the device at the start of the round (the previous `NM is still trying` line). The problem is upstream (ISP, the router's WAN side, DNS at the router) or the stored networks are out of range. The reboot timer is reset; emergency and open networks are still tried, then the round waits 20 s. Fix: none on the device. Check the router; if none of your networks is visible, check placement.

### `association refused - wrong password? (recovery continues, reboot stays off)`

ERROR, per recovery round. On wpa a stored network is `TEMP-DISABLED` in `wpa_cli list_networks`; on nm an activation failed with an error naming secrets, authentication, 802-1X, key management or a pre-shared key. The recovery ladder still runs; the reboot timer is reset every time this sign is seen. Fix: correct the password in your own configuration (`wpa_supplicant.conf` or the NetworkManager profile); the daemon never edits it.

### `fight round 1: ME evidence (LINK_OK=0, gw unreachable, auth_failing=0)`

DEBUG, local log only, unless `DEBUG="no"` is set in the conf or `AWACS_DEBUG=no` in the environment. The round classified the outage as the device's own: the gateway does not answer, no network associated and obtained a lease this round, and a stored network is visible but cannot be used, or the scan is empty, or the stored list is empty. The ladder runs and the reboot timer starts (on nm only once NetworkManager has given up; see the reboot entry).

### `recover L1: radio bounce`

WARN, round 1 of a recovery classified as on the device; one rung per round. Round 2 logs `recover L2: restart dhcpcd (respawns the REAL per-interface supplicant)` (wpa) or `recover L2: re-kick NetworkManager on wlan0` (nm); round 3 logs `recover L3: reload brcmfmac firmware (the 3-second cure a wedge needs)` or `recover L3: restart NetworkManager + reload WiFi firmware`. On wpa the rungs are an interface down and up, a `dhcpcd` (or `wpa_supplicant`) restart, and a `brcmfmac` module reload; on nm an rfkill (or `nmcli radio wifi`) bounce, `nmcli device reapply` followed by a disconnect and connect, and a NetworkManager restart with the module reload. [how-it-works.md](how-it-works.md) lists each command. The module reload does nothing on hardware without that driver. A ladder that repeats for many minutes without `internet restored` meets the reboot condition below.

### `wedged 30min with networks visible — rebooting (repeats per streak until cured)`

ERROR, local log only, immediately before the reboot; the line never reaches the site because the network is down and a spooled copy would die with the reboot (`/run` is tmpfs). On-device evidence was continuous for `REBOOT_AFTER_MIN` minutes (default 30). Any healthy tick, external classification or wrong-password sign resets the timer, and on nm so does any sighting of NetworkManager still working; on nm the reboot also requires NetworkManager to have given up: state 30 (disconnected) or 120 (failed) on two consecutive classifications, or `nmcli` unreachable after the L3 restart. The reboot cannot be switched off; `REBOOT_AFTER_MIN` only delays it. If it repeats, the fault is below the daemon: driver, power supply, SD card, or a router that beacons but never leases. Read `journalctl -b -1` and `dmesg` from the previous boot.

### `NM is still trying - waiting it out`

INFO, nm backend, at the start of a round and again after the evidence was gathered. The device is in NetworkManager's connecting states (40 to 90, or 110): stored networks are not tried, no rung runs and the reboot timer is reset. At the start of a round the round takes the external path (`outage looks external` follows, emergency and open networks are still tried, the round waits 20 s); after the evidence the round only waits 20 s. Normal on nm during an outage.

### `NetworkManager is connected, internet is not (round 1) — router-side, no rung`

INFO, nm backend, after the evidence was gathered: NetworkManager reports state 100 (connected, with an address) while the internet check fails, the router's problem. No rung runs, the reboot timer is reset, emergency and open networks are still tried.

### `trying emergency networks (2 listed)`

INFO, after the stored networks failed; absent when `SAFETY_NET` is empty. Each entry is tried in turn, visible or not, for about `ASSOC_WAIT` seconds per attempt on wpa (default 25) and up to three times that on nm; success logs `connected to EMERGENCY network: <name>`. On wpa a name containing a backslash or a double quote, or a password containing a double quote, is skipped; on nm a password must be 8 to 63 characters or 64 hex digits.

### `trying open networks as last resort`

INFO, after the emergency networks failed; absent unless `OPEN_NETWORKS` is `yes`. Networks without encryption are tried strongest first, skipping signals below -80 dBm (wpa) or 25 % (nm); on wpa a name with non-ASCII characters is skipped. Success logs `connected to OPEN network: <name>`. The temporary entry lives in the live supplicant or under `/run/NetworkManager/system-connections/` and is removed when the device is back on a stored network, at the next recovery, or at the next daemon start.

## Radio and scans

### `scan failed - using previous results (if any)`

WARN. `iw dev wlan0 scan` returned nothing after every try (three tries 3 s apart, six in the first three minutes after boot), and `iwlist` and the backend's own table (`wpa_cli scan_results` or `nmcli device wifi list`) returned nothing either. The previous picture is kept and its timestamp refreshed, so the radio is asked again once per `SCAN_TTL`. A `Device or resource busy` answer is not retried: after 3 s `iwlist` and the backend's table are read instead, and the line appears only when they are empty as well. A hand-run `awacs.sh scan` logs the line locally only. Fix if it persists while online: `iw dev wlan0 scan` by hand shows the driver's error.

### `radio heard nothing on 3 scans in a row - previous results dropped`

WARN, once, when the picture is dropped. Three consecutive scans, each with every source, heard no network; the cache is emptied so that recovery, the toolbox and the WiFi cell stop showing networks that are not there. An empty scan is evidence that the fault is on the device (a working radio hears its neighbours); after `REBOOT_AFTER_MIN` minutes of it the reboot condition is met. The first scan that hears anything ends the streak silently. Fix: `rfkill list`, `iw dev wlan0 scan` by hand, `dmesg`. If the box has not moved and neighbours exist, the radio or its driver is stuck.

## Network choice

### `connected: HomeNet (signal mode - no upload probe target configured)`

OK; the preferred-network return logs `returned to preferred network: HomeNet (signal mode)`. No probe target: recovery kept the strongest stored network that delivered internet, and the return to the preferred network went ahead without a measurement. `awacs.sh speed` prints `no probe target (signal mode)`. For measured choice set `SITE_URL` or `PROBE_URL`.

### `sustained slow upload (150 kbps) - evaluating known networks`

WARN; with a live stream running the line is `live stream starving (12 kbps) - evaluating known networks`. The passive 3 s kernel-counter sample stayed between 20 kbps and the current floor (`MIN_UP_KBPS` by day, `NIGHT_MIN_UP_KBPS` at night) for `UP_STRIKES` consecutive ticks and the cooldown since the last evaluation has passed; the stream variant needs a running `raspistill` serving `live_raw`, `preview.jpg` or `capture.jpg`, or a `curl` upload with `upfile=@`, and a flow between 5 kbps and `STREAM_MIN_KBPS`. One probe of the current network follows; if it measures under the floor the other visible stored networks are measured (`candidate [<id>] <name> uploads at <n> kbps` each) and the outcome is `connected: <name> (upload <n> kbps)` or the next entry. Fix if it repeats every cooldown: the network is slow for the floor you set; adjust `MIN_UP_KBPS` or the night floor, or accept the switching.

### `no challenger beat the incumbent - staying on HomeNet`

OK. An evaluation measured the other stored networks and none beat the current one by the required gain (`SWITCH_GAIN_PCT` by day, `NIGHT_GAIN_PCT` at night); the device went back to where it was. Not an error.

### `preferred network too slow (120 kbps) - benching it, going back`

WARN. A stored network with a higher priority was visible on two consecutive checks (`PREF_CHECK` apart), the daemon moved to it (`higher-priority network visible - trying to go home` precedes this), measured it under the floor and returned. That network is not tried again for three cooldowns.

## Guards that should never fire

### `BUG: wpa_cli reached under nm backend: ...`

ERROR, local log only. A code path called the wpa helper while the backend is NetworkManager; the call returns failure and nothing reaches `wpa_cli`. Report it with the log line; it names the arguments.

### `REFUSING delete: 'name' is not an awacs crutch`

ERROR, local log only, nm backend; the second form is `REFUSING delete: 'name' lives outside /run (owner file?)`. A delete was requested for a profile not named `awacs-crutch-*` or `awacs-safety-*`, or whose file is not under `/run/NetworkManager/system-connections/`; the delete did not happen. This is the last guard in front of your own profiles. Report it with the log line.

## The toolbox

### The ROOT ACCESS REQUIRED box

`status`, `networks`, `evaluate`, `scan` and `speed` need root: they read the supplicant or NetworkManager and the private state directory. Only `check` and `help` run unprivileged.

### `usage: awacs.sh [status|networks|evaluate|scan|speed|check|help|-d]   (no argument = daemon)` and exit 1

The word is misspelled. The check runs before the root gate, so a typo and a missing `sudo` stay distinguishable.

### The INSTANCE ERROR box

You launched the daemon by hand while another copy holds the lock (`flock` on `/run/awacs/lock`); the box shows that copy's pid. Without a terminal the losing copy exits 0 silently. Use the toolbox words instead; they run beside the daemon without taking the lock.

### `awacs.sh speed` prints `0 kbps — probe failed`

The probe target did not accept the upload within the time limit, with curl and with the wget fallback. Check the target with the `400` test in [integration.md](integration.md). `no probe target (signal mode)` instead means neither `SITE_URL` nor `PROBE_URL` is set.

## Symptoms without a line of their own

### `awacs.sh status` reports the daemon `NOT running`

The `daemon` row reads `running (pid N)` when the pid written in `/run/awacs/lock` is alive and its command line names awacs, and `NOT running` otherwise. Check the launcher: `systemctl status awacs`, or the `/etc/rc.local` line and `pgrep -af awacs.sh`; then `journalctl -u awacs` for the exit status and the local log for how far the last start got.

### The site log shows nothing although `LOG_TARGET` is `both`

Check in order. The endpoint answers from the device: `curl -s -o /dev/null -w '%{http_code}\n' --data-urlencode probe=1 "$SITE_URL/$DEVICE_ID/receiver.php"` (or the `SITE_API` name) must print `400`. The conf was applied: no refusal on stderr, and the `reporting:` line names the site. Lines waiting in the spool `/run/awacs/spool` are delivered about 30 s after the internet is verified healthy and retried about every 5 min. Then read the receiver's `log/log.txt` on the server.

### The site log lines are in Arabic

By design: the site line carries the event's Arabic text when the program has one; the local file carries the English line. There is no knob.

### The start line repeats every 10 seconds

The daemon exits shortly after `AWACS 1.0 starting on wlan0 (device mydevice)` and the respawn loop (rc.local or `Restart=always`) starts it again after 10 s. `journalctl -u awacs` shows the exit status; the local lines between two start lines show how far it got. A second launcher does not produce this picture: the copy that loses the lock exits before it logs anything.

### Two launchers

The daemon runs both from `/etc/rc.local` and from `awacs.service`. The second copy loses the lock, exits 0 without a log line and is started again every 10 s: `journalctl -u awacs` shows a start and a clean exit every 10 s, or `pgrep -af awacs.sh` shows a copy that is not the unit's main process. Fix: keep one launcher.

### The WiFi cell shows no speed

Normal. The speed is measured at decision moments only (a candidate during recovery, an evaluation after slow upload, arrival on a preferred network) and shown only while the device is still on the network it was measured on; `0` in the first field means no measurement for this network yet.

## Other lines

Lines without an entry above, with sample values. Site lines carry the Arabic text of the same event.

| Line | Level | When |
| --- | --- | --- |
| `AWACS 1.0 starting on wlan0 (device mydevice)` | INFO | Every daemon start. |
| `stealth mode active (icmp hidden, avahi stopped)` | INFO | Start with `STEALTH_MODE="yes"`. |
| `day profile active (floor 400 kbps)` | INFO | First tick by day, then at `NIGHT_END` (`NIGHT_MODE="yes"`). |
| `night profile active (floor 200 kbps)` | INFO | First tick at night, then at `NIGHT_START`. |
| `internet restored: HomeNet` | OK | The internet is back after a loss. |
| `connected to EMERGENCY network: MyPhone` | OK | An emergency network delivered internet. |
| `connected to OPEN network: CafeFree` | OK | An open network delivered internet. |
| `candidate [3] OfficeNet uploads at 850 kbps` | INFO | Each measured candidate. |
| `connected: OfficeNet (upload 850 kbps)` | OK | The best measured candidate was taken. |
| `higher-priority network visible - trying to go home` | INFO | Two consecutive preferred-network sightings. |
| `returned to preferred network: HomeNet (upload 900 kbps)` | OK | The preferred network passed the measurement. |

Further `DEBUG` lines (`scan: 1/3 tries used`, `connect_id: activating ...`, `QA: flow=...`, `best_pref_id: ...`, `quick check timed out under load (sent ${sent} B during it) - patient check passed`, `sent ${sent} B during the failed quick check, the patient check failed too - counting it`, `gentle open skipped: the link is alive (gateway reachable) - the outage is upstream`) trace decisions in the local file and are silenced with `DEBUG="no"`.
