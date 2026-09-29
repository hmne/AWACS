# Troubleshooting

Each entry is a line the script prints, its level, what it means and what to do. The local log is `/var/log/awacs.log`; a local line reads `yyyy-mm-ddThh:mm:ss+hh:mm [LEVEL] message`. Daemon stderr reaches `journalctl -u awacs` under systemd and nowhere under the rc.local loop; the two conf refusals below are repeated in the log at start as WARN lines, and are best seen at once by running `sudo awacs.sh status` on a terminal, because every run as root sources the conf.

## Settings

### `awacs: IGNORING /etc/awacs.conf (not owned by root — chown root: it)`

Stderr, at every run as root. The conf is not owned by root, typically after a restore as another user; the daemon runs on defaults (no `SAFETY_NET`, no site). Fix: `sudo chown root:root /etc/awacs.conf`.

### `awacs: IGNORING /etc/awacs.conf (group/world can access it — chmod 600 it)`

Stderr, at every run as root. The mode has group or other bits (`0644`, `0640`); a conf that carries hotspot passwords is refused when anyone else can read or write it. Fix: `sudo chmod 600 /etc/awacs.conf`.

### `settings file /etc/awacs.conf ignored: mode 644, chmod 600 it - running on built-in defaults (no site, no emergency networks)`

WARN, once at start, after the `reporting:` line. The log repeats the stderr verdict above, so a refused conf is seen under a launcher that discards stderr; the mode is the octal mode found. Fix as above. The line reaches the site only when the environment supplies a `SITE_URL`, since the refused file is where that setting lives.

### `settings file /etc/awacs.conf ignored: not owned by root, chown root: it - running on built-in defaults (no site, no emergency networks)`

WARN, once at start: the log's form of the `not owned by root` refusal printed on stderr. Fix: `sudo chown root:root /etc/awacs.conf` and restart the daemon.

### `settings file /etc/awacs.conf not found - running on built-in defaults (no site, no emergency networks)`

WARN, once at start. The file named by `AWACS_CONF` does not exist: the daemon runs on defaults, local-only and in signal mode. Fix: create it (`sudo cp awacs.conf.example /etc/awacs.conf`, then owner and mode), or set `AWACS_CONF` to the right path.

### `settings file /etc/awacs.conf applied, but 2 values failed validation and use their defaults: TICK, SITE_TZ`

WARN, once at start, only when a value failed. The named knobs (names only, never values) were malformed and run on their defaults; the rule for each is in [configuration.md](configuration.md). For `SITE_URL`, `PROBE_URL` and `SITE_TZ` an empty value is a choice and is not named. Fix: correct the lines and restart the daemon.

### A knob you set is not applied, with no message

The validated knobs are named at start when they fall back (the line above). The four switches `OPEN_NETWORKS`, `NIGHT_MODE`, `STEALTH_MODE` and `DEBUG` are not validated: any spelling other than the lowercase word `yes` means off, with no line. `SAFETY_NET` entries need the exact form `SAFETY_NET["Name"]="password"`. Fix: correct the line and restart the daemon.

### `LOG_TARGET asked for the site but SITE_URL is empty - running local-only`

WARN, local log, once at start. `LOG_TARGET` was `both` or `remote` without a `SITE_URL`; the target was downgraded to `local`. Fix: set `SITE_URL`, or set `LOG_TARGET="local"`.

### `wifi cell asked for (REPORT_WIFI=yes) but SITE_URL is empty - nothing to publish to`

WARN, local log, once at start. `REPORT_WIFI` is `yes` but there is no site to post the cell to. Fix: set `SITE_URL`, or set `REPORT_WIFI` to `auto` or `no`.

### `time zone Asia/Kuwaitt is unknown on this device (no such zone) - stamps fall back to UTC`

WARN, once at start. `SITE_TZ` passed the shape check but `/usr/share/zoneinfo/<name>` is not a file, so the stamps on every line read UTC; `tzdata not installed` means the whole zoneinfo tree is missing. Only `Area/City` names are checked; a POSIX string such as `KST-3` needs no file. Fix: correct the name (`timedatectl list-timezones`), or install `tzdata`.

### `device id not usable (DEVICE_ID: my camera) - reporting as cam1`

WARN, once at start. The id found in `DEVICE_ID` (or `/tmp/device_id`) fails the rule `[A-Za-z0-9_-]{1,32}`, so the daemon reports under the short hostname (or `device`); the value is shown with control characters removed and cut to 40 characters. An absent id says nothing. Fix: set a plain id in the launcher's environment. A later change of the resolved id is `device id changed: cam1 -> cam2 - reporting under cam2 from now`.

### `reporting: local | probe: none - signal mode | wifi cell: auto`

INFO, local log, after the start line: the reporting knobs as applied. With a site the log target is followed by `->` and the site URL, and `probe:` names the probe target. `probe: none - signal mode` means neither `SITE_URL` nor `PROBE_URL` is set: no upload measurement and no switching by speed. If you set the knobs and still read `local`, the conf was not applied (the refusals above) or `SITE_URL` failed validation (named in the fallen-knobs line). The `running with:` line that follows is the next entry.

### `running with: measured mode, floor 400/200 kbps day/night (night 22:00-06:00), switch gain 150%, one evaluation per 20 min, reboot after 30 min wedged, wifi cell on, 3 stored networks, 0 emergency, open networks yes, stamps in the device zone`

INFO, once per start, the last of the start lines: the settings as they work after validation, the line every later line is read against. `measured mode` means a probe target exists (`SITE_URL` or `PROBE_URL`); without one the line reads `running with: signal mode (no probe target - networks chosen by signal), reboot after 30 min wedged, wifi cell off (no SITE_URL), 3 stored networks, 0 emergency, open networks yes, stamps in the device zone` and stays in the local file, since there is no site. With `NIGHT_MODE` other than `yes` the floor part reads `floor 400 kbps (night profile off)`. `one evaluation per` is `DANCE_COOLDOWN` in minutes, rounded up. `wifi cell` reads `on`, `off (REPORT_WIFI=no)`, `off (no SITE_URL)` or `off (auto with LOG_TARGET local)`. The stored count is read from the base layer at start, so `0 stored networks` with a sound setup means a mute `wpa_cli` or a missing `nmcli`. `emergency` is the number of `SAFETY_NET` entries, never their names. `stamps in` is `SITE_TZ` or `the device zone`. No address appears in the line. If it reads other than what you set, look at the `settings file` line before it.

## Start-up

### `AWACS 1.0 starting on wlan0 (device mydevice) - wpa backend, restart 3 of this boot`

INFO, every start. The tail names the backend (`wpa` or `NetworkManager`) and whether this is the first start since the device booted (`first start of this boot, up 1 min`, the uptime reading `45 s`, `3 min`, `2 h 15 min` or `3 d 4 h`) or a restart of the daemon (`restart N of this boot`). The counter is the file `/run/awacs/starts`, gone at reboot and raised only by the instance that won the lock. A `restart` hours after the boot means the daemon died and the launcher brought it back: look for an `AWACS exited unexpectedly` line before it and for the exit status in `journalctl -u awacs`. On a NetworkManager image without `nmcli` the tail reads `NetworkManager backend` and an `ERROR` line follows at once; the restart after `nmcli` arrives counts as a `restart` too.

### `missing tools: iw nmcli - will try to install once online`

ERROR, at start. The named tools are not in `PATH`; the inventory is `iw ip ping curl awk sed grep pgrep rfkill flock timeout stat date modprobe` plus `wpa_cli` (wpa) or `nmcli` (nm). At the third healthy tick one `apt-get install` runs in the background, once per boot (marker `/run/awacs/apt_tried`): `installing missing tools: <packages>`, then `tools installed: <packages>` or `tool install failed - still missing: <tools> - install manually`; without `apt-get`: `no apt-get on this system - install manually: <tools>`. Package names: `wpasupplicant`, `network-manager`, `iproute2`, `iputils-ping`, `mawk`, `procps`, `util-linux`, `coreutils`, `kmod`; other tools install under their own name. There is no knob to disable the attempt. Fix if it fails: install the packages by hand; the attempt repeats at the next boot.

### `interface wlan0 not present - is the WiFi hardware alive?`

ERROR, at start. No wireless interface in `iw dev`, no `wlan0` either, and the daemon proceeds against a name that has no device: a dead radio, an unplugged dongle, a missing driver, or `iw` itself missing (then `missing tools: iw` follows it). Fix: check `iw dev`, `rfkill list` and `dmesg | grep -i brcm`; set the environment variable `AWACS_IF` if the interface has an unusual name.

### `interface wlan0 has vanished - WiFi hardware or driver gone, rung L3 reloads the driver (a USB dongle needs replugging)`

ERROR, at a recovery start, once per outage. The interface answered `iw dev` earlier in this run and does not now: a dongle unplugged, or a netdev lost after a firmware crash. Rung L3 reloads `brcmfmac`, which brings a Pi's own chip back; a USB dongle needs replugging. An interface absent from the start gets the entry above instead. Check `iw dev`, `lsusb` and `dmesg`.

### `NetworkManager image but AWACS cannot drive it: nmcli is missing - will install it once online and restart - monitoring only`

ERROR, at start; the other forms are `NetworkManager image but AWACS cannot drive it: nmcli is missing - will install it once online, then restart AWACS by hand (started with -d) - monitoring only` and `NetworkManager image but AWACS cannot drive it: wlan0 is unmanaged by NetworkManager - fix unmanaged-devices in NetworkManager.conf and restart AWACS - monitoring only`. NetworkManager is active or enabled, and either `nmcli` is missing or the interface is unmanaged (device state 10). The daemon parks: it checks the internet every 300 s, flushes the spool and lets the tool install run once; no recovery runs. For a missing `nmcli`, wait for the install or run `apt-get install --reinstall network-manager` yourself: `nmcli is now installed - restarting as a full NetworkManager supervisor` follows, the daemon exits for the respawn loop, and the next start logs `NetworkManager backend - AWACS supervises it (full capability)`. For an unmanaged interface, look for `unmanaged-devices` in `/etc/NetworkManager/NetworkManager.conf` and `/etc/NetworkManager/conf.d/`, or run `nmcli device set wlan0 managed yes`, then restart the daemon; the parked daemon does not re-detect by itself.

### `internet lost on HomeNet - monitoring only, AWACS cannot recover here`

WARN, monitor-only mode, once per outage. The internet check that runs every 300 seconds failed after passing, or the first check after the start failed. No recovery runs; when the internet returns the spool is sent first and then `internet back on HomeNet - monitoring only` is written as OK, so the site reads the loss and the return in order. One pair per outage, nothing in the passes between. Fix: what the monitor-only entry above says.

### `wifi radio was soft-blocked at start - unblocked (a WLAN country not set, or a saved rfkill state)`

WARN, once at start. `rfkill list wifi` showed a soft block (`Soft blocked: yes`) before the daemon lifted it with `rfkill unblock wifi` (and `nmcli radio wifi on` on nm); the radio works from here on, but the block returns at the next boot until its cause is fixed. Fix: set the WLAN country (`raspi-config`, or `country=` in `wpa_supplicant.conf`), or clear a saved rfkill state (`sudo rfkill unblock wifi`, then remove the files under `/var/lib/systemd/rfkill/`).

### `wifi radio is hard-blocked - a hardware switch, AWACS cannot unblock it`

WARN, once at start. `rfkill list wifi` shows `Hard blocked: yes`: a physical switch or a firmware setting on the board. No command lifts it; the daemon runs against a dead radio until it is flipped.

### `stealth mode partly active: iptables missing - pings still answered`

WARN, once at start with `STEALTH_MODE="yes"`. One or two of the parts, comma-joined: `iptables missing - pings still answered` (install `iptables`), `ping rule could not be added - pings still answered` (both `iptables -C` and `iptables -I` failed: a kernel without netfilter, or nftables refusing the legacy tool), `avahi could not be stopped` (`systemctl stop avahi-daemon` left it active). An image without Avahi is not a failure. The full success keeps `stealth mode active (icmp hidden, avahi stopped)`.

### `removed the temporary network FreeCafe left by the previous run - the device was still on it, recovery follows`

WARN, once at start. The previous daemon died while the device rode a temporary open or emergency entry; this start removes it (the marker `/run/awacs/open_id`), which drops the link, and recovery begins at once. The INFO form without the tail means the device was already elsewhere. Not a fault of this start; look for what ended the previous daemon (an `AWACS exited unexpectedly` line, or the journal).

### `no internet at start on HomeNet - router still answers, engaging`

WARN, once at start. The first internet check failed; recovery starts at once, without the `NET_FAIL_TICKS` wait. The name is the network the device was on, or the interface (`wlan0`) when it was on none; the router word is the one of the loss line below. The win is said by `internet restored` on the first healthy tick.

### `starting after the reboot AWACS ordered at 2026-01-01 03:41 - wedged 30 min (HomeNet, OfficeNet on the air but this device cannot join), 7 recovery runs before it`

WARN, once, right after the start line of the first start after a reboot the daemon ordered. The marker `/var/log/awacs.log.reboot` named a different boot id, so the reboot happened; the saved outage story was put in front of this start's lines and reaches the site first. The sign and the count are those of the reboot line (the reboot entry below). Not an error in itself; read the story above it.

### `the reboot AWACS ordered at 2026-01-01 03:41 did not happen - the reboot command failed, check the device`

ERROR, once, 60 s into a run that finds the reboot marker with its own boot id: the `reboot` command did not end the boot (a missing `reboot`, a refused `systemctl`, a hung shutdown). The marker and the saved copy are dropped; the reboot count stays. Fix: run `sudo reboot` by hand and read `journalctl -b` for why it refused.

### `AWACS exited unexpectedly (status 1, last command in fight: echo "$UNBOUND_THING") - the launcher restarts it in 10 s`

ERROR, once, on an exit nobody ordered: an unbound variable under `set -u`, a failed `exec`, a stray `exit`. The status is the exit code, the command is the source text of the last command (never expanded, so no secret travels), and the function is named when the exit happened inside one. Under a launcher the daemon is back in 10 s; the tail reads `- no launcher under -d, start it again` when started with `-d`. Report it with the line; the successor's start line reads `restart N of this boot`.

### `another AWACS already holds the lock (pid 1234) - two launchers are running it, keep one (the rc.local line or the systemd unit)`

WARN, once per boot (marker `/run/awacs/lock_lost`). A second copy without a terminal lost the lock: the daemon runs both from `/etc/rc.local` and from `awacs.service`. The line lands in the shared spool and the running daemon's next flush delivers it. Fix: keep one launcher (`sudo systemctl disable awacs`, or remove the rc.local block).

### `aasw.sh is still running - two WiFi authorities will fight; remove its rc.local line`

WARN, at start. A process whose command line contains `/usr/local/bin/aasw` is running: an older WiFi watchdog that competes for the radio. Fix: remove its launch line from `/etc/rc.local` and the file.

## Outages and recovery

### `internet lost on HomeNet - router still answers, engaging`

WARN, once per outage. The line names the network the device was on when the internet went, or the interface (`wlan0`) when it was on none, and what the router did at that moment: `router still answers` (the gateway answers a ping, so the fault is upstream), `router silent too` (associated, gateway silent), `router none (not associated)`. `NET_FAIL_TICKS` consecutive internet checks failed; recovery starts and repeats every tick until `internet restored: <network> - down <duration>, <n> recovery runs` closes the outage. Not an error in itself; read the lines that follow.

### `internet answers late, not never - slow link, no recovery (${NET_FAIL_TICKS} quick checks timed out)`

INFO, local file only, at most once per outage. `NET_FAIL_TICKS` quick internet checks in a row timed out, but the link itself was alive (the default gateway answered, or the kernel's neighbour table reported it reachable) and one patient check, with three pings per target and 8-second HTTP limits, got an answer. The uplink is slow or saturated, not down: no loss line is written, no recovery runs and the tick counts as healthy. Fix: none. Seeing it often means an uplink whose answers regularly arrive after the quick check's 2 to 3 seconds, usually under a saturated upload; raise `TICK` or `NET_FAIL_TICKS` to give such a link more time before the daemon engages at all. The site gets the episode instead (next entry).

### `uplink answering late on HomeNet - 3 quick checks timed out, the patient check passed, no recovery`

INFO, sent to the site, once at the start of each late episode: the event of the local line above, said once to the site instead of every 40 to 60 seconds under a steady load. Later late passes in the episode are counted, not said; at most hourly, when new ones exist, `internet answered late 4 more times in the last hour on HomeNet - slow link, no recovery` is written. The episode closes after 30 consecutive ticks whose quick check passed (about 5 minutes) with `uplink answers normally again on HomeNet - answered late 6 times over 26 min`; no new episode opens within 30 minutes of the close, and late passes in that window fold into the next episode's count and span. When a loss ends the episode the daemon writes `internet answered late 2 more times before this loss on HomeNet - slow link` and then the loss line. Two lines an hour at most on the worst link. Fix: as for the local entry above.

### `outage looks external (round 1) — waiting, not rebooting`

INFO, once per outage; every later round that reaches the same verdict is counted, and the count follows `internet restored` as `repeated N more times during the outage (last at HH:MM): outage looks external: the router answers, the fault is upstream — waiting, not rebooting`. The fault is not on the device, and the verdict names the sign that decided: `outage looks external: the router answers, the fault is upstream (round N) — waiting, not rebooting` (the gateway answers), `outage looks external: OfficeNet linked but no internet, the fault is behind that network (round N) — waiting, not rebooting` (a network associated and obtained a lease in this round), `outage looks external: none of your 2 stored networks is on the air, 4 others heard (round N) — waiting, not rebooting` (the radio hears networks but none of the stored ones), or the plain form above on nm when NetworkManager was still working the device at the start of the round (the previous `NM is still trying` line). The problem is upstream (ISP, the router's WAN side, DNS at the router) or the stored networks are out of range. The reboot timer is reset; emergency and open networks are still tried, then the round waits 20 s. Fix: none on the device. Check the router; if none of your networks is visible, check placement.

### `association refused by HomeNet - wrong password? (recovery continues, reboot stays off)`

ERROR, once per outage per set of names; identical rounds are counted, and `association refused - wrong password? (recovery continues, reboot stays off)` is the form when no name is known. On wpa the named networks are `TEMP-DISABLED` in `wpa_cli list_networks`; on nm an activation failed with an error naming secrets, authentication, 802-1X, key management or a pre-shared key. The recovery ladder still runs; the reboot timer is reset every time this sign is seen. Fix: correct the password in your own configuration (`wpa_supplicant.conf` or the NetworkManager profile); the daemon never edits it.

### `fight round 1: ME evidence (LINK_OK=0, gw unreachable, auth_failing=0)`

DEBUG, local log only, written only with `DEBUG="yes"` in the conf or `AWACS_DEBUG=yes` in the environment. The round classified the outage as the device's own: the gateway does not answer, no network associated and obtained a lease this round, and a stored network is visible but cannot be used, or the scan is empty, or the stored list is empty. The ladder runs and the reboot timer starts (on nm only once NetworkManager has given up; see the reboot entry).

### `fault looks on the device: HomeNet, OfficeNet on the air but this device cannot join - recovery follows`

WARN, the first on-device round of an outage that runs a rung; a changed sign speaks again, identical rounds are counted. The sign is one of `<names> on the air but this device cannot join` (stored networks visible, none joinable; at most ten names), `the radio hears no network at all` (the deaf-radio verdict), `the stored network list cannot be read` (nm: `nmcli` exits 8) and `the stored network list reads empty` (a mute supplicant). The rung of the round follows; the reboot timer runs from the first such round (on nm once NetworkManager has given up). When the wrong-password sign is present its own line takes this one's place. Fix: none in itself; the rungs are the cure, and the reboot the last one.

### `reboot clock armed - the device reboots after 03:41 unless the internet returns or the fault reads external`

WARN, the first arming of an outage; later armings are counted. On-device evidence started the `REBOOT_AFTER_MIN` clock; the hour is the deadline in `SITE_TZ`, and the reboot lands at the end of the first losing recovery after it. Any healthy tick, external verdict or wrong-password sign clears it; on nm a pick-up by NetworkManager says `reboot clock cleared - NetworkManager picked the device up again`. A router that beacons but never leases, or a radio that hears nothing, is what usually arms it; check the router and `dmesg`.

### `recover L1: radio bounce`

WARN, round 1 of a recovery classified as on the device; one rung per round. Round 2 logs `recover L2: restart dhcpcd (respawns the REAL per-interface supplicant)` (wpa) or `recover L2: re-kick NetworkManager on wlan0` (nm); round 3 logs `recover L3: reload brcmfmac firmware (the 3-second cure a wedge needs)` or `recover L3: restart NetworkManager + reload WiFi firmware`. On wpa the rungs are an interface down and up, a `dhcpcd` (or `wpa_supplicant`) restart, and a `brcmfmac` module reload; on nm an rfkill (or `nmcli radio wifi`) bounce, `nmcli device reapply` followed by a disconnect and connect, and a NetworkManager restart with the module reload. [how-it-works.md](how-it-works.md) lists each command. The module reload does nothing on hardware without that driver. A ladder that repeats for many minutes without `internet restored` meets the reboot condition below. A rung whose command failed says so once per outage, in the `did not complete` entries below.

### `recover L1 did not complete: wlan0 would not come back up - radio not bounced`

WARN, wpa, once per outage. `ip link set wlan0 up` failed after the interface was taken down. An interface that will not come up is a lost driver or lost hardware; the next two rungs follow, and rung L3 reloads the driver. Fix: `dmesg | tail` and `ip link show wlan0`.

### `recover L2 did not complete: dhcpcd and wpa_supplicant both refused to restart - supplicant not respawned`

WARN, wpa, once per outage. `systemctl restart dhcpcd` failed and `systemctl restart wpa_supplicant` after it. Without a fresh network daemon an empty stored list cannot heal. Fix: `systemctl status dhcpcd wpa_supplicant` and `journalctl -u dhcpcd`.

### `recover L3 did not complete: brcmfmac would not unload - firmware not reloaded`

WARN, both backends, once per outage. The `brcmfmac` driver was loaded (`/sys/module/brcmfmac` exists) and `modprobe -r brcmfmac` refused to remove it; hardware that does not use this driver never raises the line. Most often a driver stuck under a frozen radio; when the signs persist, the reboot is the next cure. Fix: `lsmod | grep brcm` and `dmesg`.

### `recover L3 did not complete: NetworkManager refused to restart - firmware reload follows`

WARN, nm, once per outage. `systemctl restart NetworkManager` failed; said before the driver step, which runs anyway. Fix: `systemctl status NetworkManager` and `journalctl -u NetworkManager`.

### `rebooting now: wedged 30 min (HomeNet, OfficeNet on the air but this device cannot join) - reboot 1 for this fault, the story continues after the boot`

ERROR, immediately before the reboot. On-device evidence was continuous for `REBOOT_AFTER_MIN` minutes (default 30); the sign in parentheses is the one holding at that moment (`the radio hears no network at all`, `the stored network list reads empty` are the others), and the count numbers the reboots of this fault (`/var/log/awacs.log.reboots`, removed by the first healthy tick). The network is down, so the line waits in the spool; the daemon copies the spool beside the log with a marker, and the next start delivers the whole story and says `starting after the reboot AWACS ordered at ...`. Any healthy tick, external classification or wrong-password sign resets the timer, and on nm so does any sighting of NetworkManager still working; on nm the reboot also requires NetworkManager to have given up: state 30 (disconnected) or 120 (failed) on two consecutive classifications, or `nmcli` unreachable after the L3 restart. The reboot cannot be switched off; `REBOOT_AFTER_MIN` only delays it. If the count climbs, the fault is below the daemon: driver, power supply, SD card, or a router that beacons but never leases. Read `journalctl -b -1` and `dmesg` from the previous boot.

### `NM is still trying - waiting it out`

INFO, nm backend, at the start of a round and again after the evidence was gathered; said once per outage, the later sightings are counted and follow `internet restored`. The device is in NetworkManager's connecting states (40 to 90, or 110): stored networks are not tried, no rung runs and the reboot timer is reset. At the start of a round the round takes the external path (`outage looks external` follows, emergency and open networks are still tried, the round waits 20 s); after the evidence the round only waits 20 s. Normal on nm during an outage.

### `NetworkManager is connected, internet is not (round 1) — router-side, no rung`

INFO, nm backend, after the evidence was gathered: NetworkManager reports state 100 (connected, with an address) while the internet check fails, the router's problem. No rung runs, the reboot timer is reset, emergency and open networks are still tried.

### `NetworkManager is not answering nmcli (exit 8) - stored networks cannot be tried until it is restarted (recover L3)`

ERROR, nm backend, the first exit 8 of a streak (a later 8 after a good read is counted). `nmcli` cannot reach NetworkManager: the service is down or its bus is gone. No stored network can be activated; candidates fail with `NetworkManager not answering` and the on-device sign reads `the stored network list cannot be read`. Rung L3 restarts NetworkManager; if it repeats, `systemctl status NetworkManager` and `journalctl -u NetworkManager`.

### `trying emergency networks (2 listed)`

INFO, after the stored networks failed; absent when `SAFETY_NET` is empty. Each entry is tried in turn, visible or not, for about `ASSOC_WAIT` seconds per attempt on wpa (default 25) and up to three times that on nm; success logs `connected to EMERGENCY network: <name> (upload N kbps) - stored networks stay armed, home again when one returns`. Each entry's fate is said once per outage per entry, in the four entries below; a losing walk closes with `no emergency network delivered (N tried, M skipped)`. On wpa a name containing a backslash or a double quote, or a password containing a double quote, is skipped; on nm a password must be 8 to 63 characters or 64 hex digits.

### `emergency network MyPhone skipped: password must be 8-63 characters or 64 hex digits`

ERROR, nm backend, once per outage per entry. The `SAFETY_NET` password is not a valid WPA passphrase or key; the entry is never tried. Fix: correct the entry in `/etc/awacs.conf` (a passphrase of 8 to 63 characters works on both backends) and restart the daemon.

### `emergency network MyPhone skipped: name or password carries a quote or backslash the supplicant cannot take`

ERROR, wpa, once per outage per entry. The name carries a backslash or a double quote, or the password a double quote, and neither passes through the quoted `wpa_cli` argument. Fix: change the hotspot's name or password.

### `could not create the temporary entry for MyPhone - skipping it`

WARN, once per outage per entry. The base layer refused to create the temporary entry (`add_network` or `set_network` on wpa, writing and loading the keyfile on nm). A mute `wpa_cli` fails every entry this way, as many times as the list is long; rung L2 treats it. Fix: `wpa_cli status` by hand; on nm, `journalctl -u NetworkManager`.

### `emergency network MyPhone refused: never associated - trying the next`

WARN, once per outage per entry and reason. The hotspot is off, out of range, or refused the device; the reason is one of those listed under `could not connect` below. Not a settings fault unless the reason is `refused - wrong password?`.

### `trying open networks as last resort (3 open networks heard)`

INFO, once per outage, after the emergency networks failed; absent unless `OPEN_NETWORKS` is `yes`. Networks without encryption are tried strongest first, skipping signals below -80 dBm (wpa) or 25 % (nm); on wpa a name with non-ASCII characters is skipped. Success logs `connected to OPEN network: <name> (upload N kbps) - stored networks stay armed, home again when one returns`; a walk without a win closes with `no open network delivered internet (N heard, M tried, K linked without internet)`. A stranger that refuses the association is counted, not said. The temporary entry lives in the live supplicant or under `/run/NetworkManager/system-connections/` and is removed when the device is back on a stored network, at the next recovery, or at the next daemon start.

### `open network FreeCafe linked but no internet (captive portal?) - trying the next`

WARN, once per outage per network. The open network gave an association and an address but the internet check failed: a splash page intercepts traffic, or the network has no upstream. The entry is removed and the next open network tried. Nothing to fix on the device.

### `could not return to HomeNet: never associated - stored networks re-enabled, waiting 20 s`

WARN, once per outage. An external round tried the emergency and open networks and could not get back to the network the recovery started on; every stored network is re-enabled and the round waits 20 s for the base layer. Not said when the way back linked without internet, which is the external outage itself.

## Radio and scans

### `scan failed - using previous results (if any)`

WARN. `iw dev wlan0 scan` returned nothing after every try (three tries 3 s apart, six in the first three minutes after boot), and `iwlist` and the backend's own table (`wpa_cli scan_results` or `nmcli device wifi list`) returned nothing either. The previous picture is kept and its timestamp refreshed, so the radio is asked again once per `SCAN_TTL`. A `Device or resource busy` answer is not retried: after 3 s `iwlist` and the backend's table are read instead, and the line appears only when they are empty as well. A hand-run `awacs.sh scan` logs the line locally only. Fix if it persists while online: `iw dev wlan0 scan` by hand shows the driver's error.

### `radio heard nothing on 3 scans in a row - previous results dropped`

WARN, once, when the picture is dropped. Three consecutive scans, each with every source, heard no network; the cache is emptied so that recovery, the toolbox and the WiFi cell stop showing networks that are not there. An empty scan is evidence that the fault is on the device (a working radio hears its neighbours); after `REBOOT_AFTER_MIN` minutes of it the reboot condition is met. The first scan that hears anything ends the streak silently. Fix: `rfkill list`, `iw dev wlan0 scan` by hand, `dmesg`. If the box has not moved and neighbours exist, the radio or its driver is stuck.

## Network choice

### `connected: HomeNet (signal mode - no upload probe target configured)`

OK; the preferred-network return logs `returned to preferred network: HomeNet (signal mode)`. No probe target: recovery kept the strongest stored network that delivered internet, and the return to the preferred network went ahead without a measurement. `awacs.sh speed` prints `no probe target (signal mode)`. For measured choice set `SITE_URL` or `PROBE_URL`.

### `sustained slow upload on HomeNet (150 kbps for 3 samples, floor 400) - evaluating known networks`

WARN; with a live stream running the line is `live stream starving on HomeNet (12 kbps for 3 samples, floor 50) - evaluating known networks`. The passive 3 s kernel-counter sample stayed between 20 kbps and the current floor (`MIN_UP_KBPS` by day, `NIGHT_MIN_UP_KBPS` at night) for `UP_STRIKES` consecutive ticks and the cooldown since the last evaluation has passed; the stream variant needs a running `raspistill` serving `live_raw`, `preview.jpg` or `capture.jpg`, or a `curl` upload with `upfile=@`, and a flow between 5 kbps and `STREAM_MIN_KBPS`. One probe of the current network follows, `measured <n> kbps on <name> - under the <floor> kbps floor, a challenger must beat <bar> kbps` (or the `upload probe failed` entry below); if it measures under the floor the other visible stored networks are tried (`trying <name>`, then `candidate [<id>] <name> uploads at <n> kbps`, or `could not connect to <name>: <reason> - trying the next`) and the outcome is `switching to <name> (<n> kbps against <m> kbps here)` followed by `switched to <name> (upload <n> kbps)`, or the next entry. A probe above the floor ends the evaluation with `measured <n> kbps on <name> - above the <floor> kbps floor, staying`. Ripe strikes while the cooldown still runs are `upload still slow on <name> (<n> kbps, floor <floor>) - evaluation on cooldown, next look in <m> min` (INFO, once per window; `live stream still starving on <name> (<n> kbps, floor <floor>) - evaluation on cooldown, next look in <m> min` under a stream). Fix if it repeats every cooldown: the network is slow for the floor you set; adjust `MIN_UP_KBPS` or the night floor, or accept the switching.

### `no challenger beat the incumbent - staying on HomeNet (best was OfficeNet at 300 kbps, needed 375)`

OK. An evaluation measured the other stored networks and none beat the current one by the required gain (`SWITCH_GAIN_PCT` by day, `NIGHT_GAIN_PCT` at night); the device went back to where it was. The parenthesis names the closest candidate and the bar; inside a recovery the line ends at the name. When no candidate was measured the line is `the only candidate did not deliver internet - staying on HomeNet at 250 kbps` or `none of the 2 candidates delivered internet - staying on HomeNet at 250 kbps`, and `no other known network on the air - staying on HomeNet at 250 kbps` when there was nothing to try. Not an error.

### `could not connect to OfficeNet: linked but no internet - trying the next`

WARN, once per candidate that fails inside a comparison or a recovery; `trying OfficeNet` precedes it. The reason is one of `never associated` (no association within `ASSOC_WAIT`), `associated but got no address` (no IPv4 lease within `ASSOC_WAIT`), `refused - wrong password?` (the supplicant marked it `TEMP-DISABLED`, or NetworkManager named the credentials), `not found on the air` (nm), `timed out after 25 s` (nm's own wait), `NetworkManager not answering` (`nmcli` exit 8), `NetworkManager: <its own message>` (any other nm failure) and `linked but no internet` (the link came up and the internet check failed); `no association or no address` is the fallback. The next candidate is tried. Fix if the same network fails every time: check its password and its router; a wrong password also produces `association refused by OfficeNet - wrong password? (recovery continues, reboot stays off)`.

### `switching to OfficeNet failed: never associated - going back to HomeNet`

WARN. The comparison chose OfficeNet (`switching to OfficeNet (...)` precedes it), but the second connection to it failed; the daemon returns to the network it left and logs `back on HomeNet`, or `back on HomeNet - linked but still no internet` when the way back linked without internet, or `could not return to HomeNet: never associated` when it failed. Inside a recovery, with no network to go back to, the line ends at the reason. A network that worked a moment ago stopped answering; not a fault of the daemon.

### `could not return to HomeNet: never associated`

WARN, once per outage per network and reason. The way back to the previous network failed for the reason given (one of the connect reasons above, other than `linked but no internet`): after a lost comparison (the best candidate is then joined anyway, `switching to OfficeNet (300 kbps, below the 375 kbps bar) - the best left, HomeNet: never associated`), after a failed switch, or after a preferred-network return that measured too slow or failed (then `the way back to HomeNet failed - on <network> now, the next check decides` follows). A way back that linked without internet is INFO instead, `back on HomeNet - linked but still no internet` (`, recovery continues` appended inside a recovery): the device is home, the internet is not. Read the lines that follow: the next internet check decides, and a recovery starts if the internet is gone.

### `upload probe failed on HomeNet - the probe target accepted nothing (site or endpoint down?), counting it as 0 kbps`

WARN, at a decision moment (the evaluation's baseline, a candidate, a preferred-network arrival), in place of the `measured` or `candidate` line. Neither curl nor the wget fallback got the probe body accepted within the limits; the decision counts the network as 0 kbps, so a live incumbent is never displaced by it, and a preferred network measured this way is benched. Check the probe target with the `400` test in [integration.md](integration.md); `awacs.sh speed` runs the same probe by hand.

### `evaluation ended with no working network - on nothing now, the next check decides and recovery follows if the internet is gone`

WARN, once per such evaluation. The comparison chose a candidate that then failed and the way home failed too, or there was no candidate and the way home failed; every stored network is re-enabled and the line names where the device sits (`nothing` when on no network). The next internet check decides; a loss starts recovery. Usually the home network went down during the evaluation.

### `could not reach the preferred network HomeNet: never associated - going back to Hotspot`

WARN. A higher-priority network was visible on two consecutive checks but could not be joined for the reason given; the daemon goes back to the network it left (`back on Hotspot`, or the failed-return lines) and tries again after the next two sightings. With no known network to go back to the tail reads `- no stored network to go back to, the next check decides`. Fix if it repeats: the preferred network is visible but refuses this device; check its password and look for `association refused by HomeNet - wrong password?`.

### `preferred network HomeNet too slow (120 kbps, floor 400) - benched for 60 min, going back to Hotspot`

WARN. A stored network with a higher priority was visible on two consecutive checks (`PREF_CHECK` apart), the daemon moved to it (`higher-priority network HomeNet visible twice - leaving Hotspot to go home` precedes this), measured it under the floor and goes back. That network is not tried again for the minutes given, three cooldowns (60 by day, 120 at night with the defaults); `- benched for 60 min, staying on it` when there is no network to go back to, and `, ends the bench on OfficeNet` is appended when another network's bench was still running. A probe the target refused speaks `upload probe failed` first and benches the network at 0 kbps.

### `the way back to Hotspot failed - on no network now, the next check decides`

WARN, after a preferred-network attempt whose way back failed (its `could not return to Hotspot: <reason>` precedes it). The line names where the device sits now; on wpa the supplicant may sit on nothing until the re-enable takes effect, on nm NetworkManager roams by itself. Not written when the way back linked without internet, since the device is then back. The next check decides.

## Site commands

The lines of the site's WiFi menu: a scan on demand, a manual trial of a stored network (`switch`) and a trial of a new network with a password typed on the site (`join`). The channel, the answer states and the key are described in [integration.md](integration.md). Every line here names networks and numbers only; no password, key or ciphertext ever reaches a log.

The page wording quoted below is the reference dashboard's; a site of your own words the reason tokens itself.

### `site command scan expired - it waited 2 min behind a recovery, tap again`

INFO. The command reached the device more than 60 s ago by the device's uptime clock (a recovery was running and the command is read only at the top of the main loop). The site's page shows `Command expired`. Fix: tap again once the internet is back.

### `site command switch refused - a recovery is running, tap again when the internet is back`

INFO. The command arrived while a recovery was engaged; nothing about a command runs inside a recovery. The page shows `AWACS is busy`. Fix: wait for `internet restored`, then tap again.

### `scan asked from the site while offline - the list cannot be published until the internet is back`

INFO. The radio could be scanned but the list has nowhere to go while the internet is down; the answer is `failed` with `offline` and the page says the camera has no internet. The same line exists for `switch` and `join` (`... recovery decides the network until the internet is back`).

### `scan asked from the site under a live stream - a few seconds of stutter`

INFO. A scan takes the radio off its channel; the owner asked for the scan, so it runs once, and the live viewer stutters while it does. `manual trial under a live stream - the viewer stutters while the network changes` is the same warning for a switch or join.

### `scan from the site heard 7 networks - list published`

INFO. The scan ran past the `SCAN_TTL` cache and the once-a-minute gate, the list was posted in the foreground and the answer `done` followed with the count. A page that still shows the old rows did not poll yet.

### `switch asked from the site to OfficeNet - not a stored network, nothing to try`

WARN. The key the site sent matches no stored network (the network was removed from the supplicant or NetworkManager after the list was published, or the page is stale). The answer is `failed` with `out_of_reach`. Fix: scan again from the menu; an unknown network is joined, not switched to.

### `switch asked from the site to HomeNet - already on it`

INFO. The chosen network is the current one; nothing moves and the answer is `switched` with the last measured speed (0 when none).

### `switch asked from the site to HomeNet - already on it, holding it`

INFO. The same, with a hold asked (`hold=<seconds>` in the command's fifth field): no trial, the hold starts now and the answer is `switched NAME KBPS hold=<seconds>`; the `hold on HomeNet for 30 min ...` line follows.

### `manual trial: OfficeNet for 15 s, leaving HomeNet (1200 kbps) - it stays only at 1800 kbps or more`

INFO, the opening line of every trial. The daemon names where it leaves from, the origin's upload (its last measurement when fresher than 120 s, else one probe now) and the bar the trial must reach: the origin's upload times `SWITCH_GAIN_PCT` (or the night gain) divided by 100, the same bar every challenger meets. Then the connect: a link that forms and delivers internet is answered `trying`.

### `manual trial: OfficeNet upload 2000 kbps, the 1800 kbps bar met - staying on it`

OK. The one probe, run inside the 15 s on the trial network, measured it at or above the bar; the network stays and the answer is `switched` (or `joined`). In signal mode the line reads `signal mode` in place of the upload and any network that delivers internet stays.

### `manual trial: OfficeNet uploads at 700 kbps, under the 1800 kbps bar (HomeNet 1200 kbps at 150%) - going back`

INFO. The trial network was slower than the bar; the daemon returns to the origin and answers `returned` with both pairs of numbers, and the page says `Back on HomeNet`. This is the owner's design: a manual choice is a trial, never a takeover.

### `manual trial: OfficeNet uploads at 700 kbps, under the 1800 kbps bar (HomeNet 1200 kbps at 150%) - staying anyway, held from the menu`

INFO. The switch asked for a hold and the trial network has internet (the probe carried bytes, or the quick check passed at the verdict), so the slower network is kept as asked; the answer is `switched NAME KBPS hold=<seconds>` and the next line is the hold's. A held switch whose trial meets the bar logs the ordinary `bar met - staying on it` line, then the hold's.

### `hold on OfficeNet for 30 min - no preferred-network return and no evaluation leaves it; an internet loss or a new command ends it`

INFO. The hold has started: for that long (the device's uptime clock) the preferred-network look and the slow-upload evaluation do not run. The recovery is untouched. The trial's opening line named it as well: `... - the bar is 1800 kbps, and it stays for 30 min either way while it has internet`.

### `hold on OfficeNet ended - back to its own judgement`

INFO. The hold's time is up; the next preferred-network look and the next evaluation behave as always. The other two endings: `hold on OfficeNet ended - internet lost` (a real outage: the recovery chooses the network from here) and `hold on OfficeNet ended - a new command from the site` (any command the daemon served; a new held switch starts its own hold).

### `manual trial: OfficeNet measured 0 kbps and fails the internet check - the hold is not taken, going back to HomeNet`

INFO. The switch asked for a hold, but at the verdict the trial network carried no bytes and the quick internet check failed: reachability comes first, the hold is refused and the way back runs as for any slower trial (`back on HomeNet`, the answer `returned`).

### `upload slow on OfficeNet (120 kbps, floor 400) - held from the menu, no evaluation until the hold ends in 25 min`

INFO, once per hold. The slow-upload strikes ripened under a hold; the evaluation that would run now could leave the held network, so it does not run. The strikes count again and the first evaluation after the hold comes as soon as they ripen.

### `hold on OfficeNet ends with this stop - the next start judges on its own`

INFO, in the graceful stop's lines. The hold lives in memory only; the restarted daemon knows nothing of it and returns to a preferred network or evaluates as always.

### `manual trial: OfficeNet never associated - going back to HomeNet`

WARN. The connect to the trial network failed; the reason is the connect verdict (`never associated`, `not found on the air`, `associated but got no address`, `refused - wrong password?`, `linked but no internet`, `timed out after 45 s` on NetworkManager) and the answer's reason token follows it: `wrong_password` for the refusal, `no_internet` for a link without internet, `out_of_reach` for everything else. The daemon goes back to the origin at once. The trial's connect waits `TRIAL_ASSOC_WAIT` (45 s, or `ASSOC_WAIT` when larger) where the recovery waits `ASSOC_WAIT`: a new or far network can scan 7 to 23 s before it authenticates, and the wrong-password mark is read for the whole budget, so neither a reachable network nor a wrong password is answered `out_of_reach`. For a join the line starts `join: NAME ... - removing it, going back to HomeNet` and the entry is removed.

### `back on HomeNet`

OK. The way back after a trial formed a link and delivered internet. A way back that links without internet says nothing more here (the outage is upstream; the device is home) and still counts as `returned`.

### `the way back to HomeNet failed - on no network now, the next check decides and recovery follows if the internet is gone`

WARN. The origin did not take the device back after a trial (`on OfficeNet now` when the device sits on some network). The answer is `failed` with `return_failed`; the next tick decides and the ordinary recovery takes over if the internet is gone. Nothing was disabled: every stored network is re-enabled on every exit of a trial.

### `join asked from the site: CafeNet - adding it at runtime and trying it for 15 s`

INFO. The password was opened and passes the shape rule (8 to 63 characters or 64 hex digits, no tab or newline); the network is added at run time only (`add_network` on wpa, a keyfile `awacs-join-<epoch>-<pid>` in `/run` on nm) and the trial above follows. On wpa a password carrying a double quote or a backslash cannot be passed to the supplicant and is refused before this line: `join: the supplicant cannot take a quote or backslash in a password - CafeNet not added` (WARN, answer `wrong_password`). A password outside the shape rule is `join asked from the site for CafeNet - the password must be 8 to 63 characters or 64 hex digits`.

### `join asked from the site for CafeNet - the password could not be opened with this device's key; the site holds another key? open admin/wifi.php?reset_key=1 once and try again`

WARN. The blob's MAC did not verify or the decryption failed: the site encrypted with a key that is not this device's (the card was reflashed and the site still holds the old key, or the key file is damaged). The daemon offers its key to the site again (taken only with proof) and answers `failed` with `key_changed`; the page names the reset step. Fix: open the site's `admin/wifi.php?reset_key=1` once under the admin token, wait for `device key registered with the site` (within the next healthy minute), then join again.

### `joined CafeNet - password kept in /etc/awacs.networks, re-added at every start`

OK. The trial network linked and delivered internet, so the password is right; it was written to `/etc/awacs.networks` (root 0600) before anything else, and on nm the persistent profile `awacs-joined-<hexssid>` took over from the trial entry. The 15 s trial still decides whether the device stays (`joined`) or goes back to a faster origin (`returned`); the password is kept either way. `joined CafeNet but /etc/awacs.networks could not be written - the network lasts until the next start` (WARN) means the SD card refused the write: the network works until the next start and is not re-added. On nm, `join: the stored entry for CafeNet could not take over - riding the trial entry until the next start` (WARN) means the persistent profile could not be activated; the trial entry carries the device until the next start re-adds the network from the file.

### `re-added 1 networks joined from the site: CafeNet`

INFO, at start and after the recovery rungs that restart the supplicant (wpa L2 and L3) or NetworkManager (nm L3). Every line of `/etc/awacs.networks` whose SSID has no profile yet was added again. A network that could not be re-added has its own WARN: `joined network CafeNet could not be re-added to the supplicant` (or `... to NetworkManager`, or `joined network CafeNet refused by the supplicant - not re-added`).

### `removed an unfinished join of CafeNet left by the previous run`

INFO, at start. The previous daemon died between adding a network from the site and proving its password (`/run/awacs/join_id` was still there); the entry is removed so nothing the daemon created outlives it. On wpa the entry goes only while its id still carries that SSID. Fix: none; join again from the menu.

### `device key made for passwords typed on the site (/etc/awacs.key)`

INFO, once. The first start that found `openssl` made the device key (64 hex, root 0600). `could not write /etc/awacs.key - join from the menu is off` and `could not make the device key (openssl rand failed) - join from the menu is off` (both WARN) mean the file could not be made; scan and switch still work.

### `device key registered with the site - a password typed there can be opened here`

INFO, once per boot. The site answered 2xx to `file=wifi_key`, at start, at the third healthy tick and then once a healthy minute until it is accepted. Until this line has appeared in a boot the site may still hold no key, and its join alert answers `the camera has not registered a key yet (AWACS start pending)`.

### `the site holds another key for this camera (a reflash?) - open admin/wifi.php?reset_key=1 once from your phone, then join from the menu works again`

WARN, once per boot. The site answered 403 to the registration: it holds a different key and this device cannot prove a rotation (no `/etc/awacs.key.prev` with the key the site knew), which is the case after a reflash. A receiver that does not know `wifi_key` at all also answers 403 (`Error: forbidden file`) and earns this line; update the receiver or ignore it. Scan and switch keep working; join fails with `key_changed` until the site forgets the old key. Fix: the reset step in the line, once, under the admin token. With the shipped receivers, delete `private/wifi.key` in the device folder.

### `openssl is missing - a password typed on the site cannot be opened here, join from the menu is off`

WARN, at start. `openssl` is not installed, so no key can be made and no password opened; `openssl` is part of every Raspberry Pi OS image, so this points at a trimmed image. Fix: `apt-get install openssl`, then restart the daemon.

### Local lines of the command channel

Five INFO lines stay in the local log and never reach the site, because they describe a line the site could not have meant or already handled: `site command dropped - unreadable line` (the relayed line failed the shape check), `site command scan delivered twice (epoch N) - already handled` (the relay signalled twice for one command; `/run/awacs/cmd.last` caught it), `site switch dropped - no network key` and `site join dropped - no network key or no password` (the command named no network; the site answers those cases itself before sending), and `site switch: the fifth field is not a hold - switching without one` (a switch whose fifth field is neither empty nor `hold=<1 to 86400>`). The relay's own local lines (`wifi command relayed to awacs`, `wifi command dropped ... awacs is not running`, `... an older build without the command trap`) belong to the reference dashboard's capture script and its local log, not to this daemon.

## Reporting channels

### `site did not take the log line (http 500) - holding lines, delivery retried about every 5 min`

WARN, once per episode. A story line's POST got a reply outside 2xx and 3xx (`no reply in 4 s` for a timeout) while the internet was up; the refused line and this one wait in the spool and a flush tries again about every 30 ticks. Later refusals are silent until a flush delivers everything held, which closes with `site reachable again - delivered N held lines stamped HH:MM to HH:MM, they stand above this line with their own times`. The code is the endpoint's: 500 is the receiver failing, 403 or 404 a wrong `SITE_URL`, `SITE_API` or device folder, no reply a host that does not answer. Check the endpoint with the `400` test in [integration.md](integration.md).

### `outage story trimmed - 14 lines dropped from its middle (the spool keeps 60)`

WARN, once per outage, after the delivery line of the flush that sent everything held. More lines were held than `SPOOL_CAP` allows; the first line and the newest were kept, the middle dropped, and the count is the total across the outage. Raise `SPOOL_CAP` if the whole story matters; the count is kept in `/run/awacs/spool.dropped`.

### `stop drain reached its budget - the remaining held lines wait for the next start`

INFO, local file only, at most once per stop. The stop's own flush (on SIGTERM, SIGINT, SIGHUP or the exit trap) sends the held lines in the foreground, bounded to 6 lines or 20 s so it ends inside the unit's `TimeoutStopSec=40`; what lies past the budget stays in the spool and the successor's start flush delivers it, and the stop's flush writes no `delivered` line. Fix: none; the story arrives with the next start.

### `wifi cell not accepted by the site (http 403) - the page drops the cell when it goes stale`

WARN, once per episode. The WiFi cell's POST got a reply outside 2xx and 3xx (or `no reply in 4 s`); the site's WiFi widget will go stale. Story lines and the cell go to the same endpoint, so a site down for everything says this and the entry above once each. `wifi cell accepted again` (OK) closes the episode. Check the receiver's handling of `file=tmp/wifi.tmp`.

### `wifi scan list not accepted by the site (http 500) - the list behind the WiFi box will not show`

WARN, once per episode. The scan list's POST (`file=tmp/wifi_scan.tmp`) got a reply outside 2xx and 3xx (or `no reply in 4 s`); the site's list of heard networks stays as it was. The post is retried every minute, silently, until it is taken, which `wifi scan list accepted again` (OK) says. The list follows the cell's knob, `REPORT_WIFI`, so `no` turns both off. Fix: as for the cell; a `403` means the receiver does not know the file, since the shipped receivers accept a fixed set of file names (see [integration.md](integration.md)).

### `local log /var/log/awacs.log not writable - SD card read-only? the site keeps the story`

WARN, on the first healthy tick after an append to the local log failed; once per failure streak (marker `/run/awacs/log.down`). The directory is missing, or the filesystem is read-only or full (an SD card that went read-only after an error is the usual case). The daemon keeps running and the site keeps the story; `local log /var/log/awacs.log writable again` (OK) follows when appends succeed. Check `mount | grep ' / '`, `df -h` and `dmesg | grep -i mmc`.

## Guards that should never fire

### `BUG: wpa_cli reached under nm backend: ...`

ERROR, local log only. A code path called the wpa helper while the backend is NetworkManager; the call returns failure and nothing reaches `wpa_cli`. Report it with the log line; it names the arguments.

### `REFUSING delete: 'name' is not an awacs profile`

ERROR, local log only, nm backend; the second form is `REFUSING delete: 'name' lives outside /run (owner file?)`. A delete was requested for a profile not named `awacs-crutch-*`, `awacs-safety-*`, `awacs-join-*` or `awacs-joined-*`, or whose file is not under `/run/NetworkManager/system-connections/`; the delete did not happen. This is the last guard in front of your own profiles. Report it with the log line.

## The toolbox

### The ROOT ACCESS REQUIRED box

`status`, `networks`, `evaluate`, `scan` and `speed` need root: they read the supplicant or NetworkManager and the private state directory. Only `check` and `help` run unprivileged.

### `usage: awacs.sh [status|networks|evaluate|scan|speed|check|help|-d]   (no argument = daemon)` and exit 1

The word is misspelled. The check runs before the root gate, so a typo and a missing `sudo` stay distinguishable.

### The INSTANCE ERROR box

You launched the daemon by hand while another copy holds the lock (`flock` on `/run/awacs/lock`); the box shows that copy's pid. Without a terminal the losing copy says `another AWACS already holds the lock (pid N) - two launchers are running it, keep one (the rc.local line or the systemd unit)` once per boot and exits 0. Use the toolbox words instead; they run beside the daemon without taking the lock.

### `awacs.sh speed` prints `0 kbps — probe failed`

The probe target did not accept the upload within the time limit, with curl and with the wget fallback. Check the target with the `400` test in [integration.md](integration.md). `no probe target (signal mode)` instead means neither `SITE_URL` nor `PROBE_URL` is set.

## Symptoms without a line of their own

### `awacs.sh status` reports the daemon `NOT running`

The `daemon` row reads `running (pid N)` when the pid written in `/run/awacs/lock` is alive and its command line names awacs, and `NOT running` otherwise. Check the launcher: `systemctl status awacs`, or the `/etc/rc.local` line and `pgrep -af awacs.sh`; then `journalctl -u awacs` for the exit status and the local log for how far the last start got.

### The site log shows nothing although `LOG_TARGET` is `both`

Check in order. The endpoint answers from the device: `curl -s -o /dev/null -w '%{http_code}\n' --data-urlencode probe=1 "$SITE_URL/$DEVICE_ID/receiver.php"` (or the `SITE_API` name) must print `400`. The conf was applied: no refusal on stderr, and the `reporting:` line names the site. Lines waiting in the spool `/run/awacs/spool` are delivered about 30 s after the internet is verified healthy and retried about every 5 min. Then read the receiver's `log/log.txt` on the server. A site that answers but refuses is said in the local log: `site did not take the log line (http 500) - holding lines, delivery retried about every 5 min` (entry above).

### The site log lines are in the wrong language

`SITE_LANG` picks the language of the site copy and `LOG_LANG` that of the local file, each `en` (the default) or `ar`; a line with no Arabic text stays English. Set the knob in `/etc/awacs.conf` and restart the daemon. DEBUG lines are English either way.

### The start line repeats every 10 seconds

The daemon exits shortly after `AWACS 1.0 starting on wlan0 (device mydevice) - wpa backend, restart 7 of this boot` and the respawn loop (rc.local or `Restart=always`) starts it again after 10 s; the restart count climbs with every start. `journalctl -u awacs` shows the exit status; the local lines between two start lines show how far it got, and an `AWACS exited unexpectedly (status N, last command ...: ...)` line names the command that ended the previous one. A second launcher does not produce this picture: the copy that loses the lock says `another AWACS already holds the lock` once per boot and nothing else.

### Two launchers

The daemon runs both from `/etc/rc.local` and from `awacs.service`. The second copy loses the lock, says `another AWACS already holds the lock (pid N) - two launchers are running it, keep one (the rc.local line or the systemd unit)` once per boot, exits 0 and is started again every 10 s: `journalctl -u awacs` shows a start and a clean exit every 10 s, or `pgrep -af awacs.sh` shows a copy that is not the unit's main process. Fix: keep one launcher.

### The WiFi cell shows no speed

Normal. The speed is measured at decision moments only (a candidate during recovery, an evaluation after slow upload, arrival on a preferred network) and shown only while the device is still on the network it was measured on; `0` in the first field means no measurement for this network yet. The visible count never reads below 1 while the device is associated to a stored network; before the first scan of a boot it comes from the supplicant's own table.

## Other lines

Lines without an entry above, with sample values. Site lines carry the same event in the `SITE_LANG` language.

| Line | Level | When |
| --- | --- | --- |
| `AWACS 1.0 starting on wlan0 (device mydevice) - wpa backend, first start of this boot, up 1 min` | INFO | Every daemon start; `NetworkManager backend` on nm, `restart N of this boot` after a respawn in the same boot. |
| `running with: measured mode, floor 400/200 kbps day/night (night 22:00-06:00), switch gain 150%, one evaluation per 20 min, reboot after 30 min wedged, wifi cell on, 3 stored networks, 0 emergency, open networks yes, stamps in the device zone` | INFO | Every start, after the `reporting:` line; `running with: signal mode (no probe target - networks chosen by signal), ...` without a probe target. |
| `online at start via HomeNet` | OK | A start that finds the internet up. |
| `removed the temporary network FreeCafe left by the previous run` | INFO | A start that finds a temporary entry the previous daemon left; the WARN form ends `- the device was still on it, recovery follows`. |
| `stealth mode active (icmp hidden, avahi stopped)` | INFO | Start with `STEALTH_MODE="yes"`, both legs succeeded. |
| `NetworkManager backend - AWACS supervises it (full capability)` | INFO | A start on nm. |
| `day profile active until 22:00 - floor 400 kbps, a challenger must reach 150% of the incumbent, evaluations 20 min apart` | INFO | First tick by day, then at `NIGHT_END` (`NIGHT_MODE="yes"`). |
| `night profile active until 06:00 - floor 200 kbps, a challenger must reach 300% of the incumbent, evaluations 40 min apart` | INFO | First tick at night, then at `NIGHT_START`. |
| `clock set forward 7 h 0 min by time sync - the lines above carry the old time` | INFO | The device clock moved by more than 60 s between two ticks; `back` for the other direction. |
| `device id changed: cam1 -> cam2 - reporting under cam2 from now` | INFO | The resolved device id differs from the one the start reported under. |
| `router answers on HomeNet - keeping the link, trying the other stored networks first` | INFO | A recovery's opening while the gateway answers; `router answers on HomeNet but forwards nothing - reassociating anyway this time` (wpa, the second recovery), `router not answering - waiting up to 25 s for wlan0 to reconnect` with a silent gateway. Once per outage each. |
| `scan heard 6 networks: HomeNet -48, OfficeNet -61, Cafe -70 \| known on the air: HomeNet, OfficeNet \| stored, not heard: Guest` | INFO | What the radio heard when an evaluation began, strongest first; inside a recovery once per distinct picture per outage. |
| `measured 250 kbps on HomeNet - under the 400 kbps floor, a challenger must beat 375 kbps` | INFO | The evaluation's baseline under the floor; `measured 250 kbps on HomeNet` alone on a preferred-network arrival; `measured 800 kbps on HomeNet - above the 400 kbps floor, staying` when no comparison follows. |
| `upload still slow on HomeNet (150 kbps, floor 400) - evaluation on cooldown, next look in 12 min` | INFO | Ripe slow samples while the cooldown runs, once per window; `live stream still starving on HomeNet (12 kbps, floor 50) - evaluation on cooldown, next look in 12 min` under a stream. |
| `trying OfficeNet` | INFO | A candidate is being connected. |
| `candidate [3] OfficeNet uploads at 850 kbps` | INFO | Each measured candidate. |
| `switching to OfficeNet (850 kbps against 250 kbps here)` | INFO | The winner, before the move; `(850 kbps, the fastest candidate)` inside a recovery; ` - plainly fast, over 4x the 400 kbps floor, probing stopped at it` appended when a candidate at four times the floor ended the probing. |
| `switching to OfficeNet (300 kbps, below the 375 kbps bar) - the best left, HomeNet: never associated` | INFO | A losing candidate taken because the way home failed; `switching to OfficeNet (0 kbps) - it delivered internet, HomeNet: never associated` inside a recovery. |
| `switched to OfficeNet (upload 850 kbps)` | OK | The best measured candidate was taken. |
| `no other known network on the air - staying on HomeNet at 250 kbps` | OK | A comparison with nobody to try; `the only candidate did not deliver internet - staying on HomeNet at 250 kbps` and `none of the 2 candidates delivered internet - staying on HomeNet at 250 kbps` when candidates were walked and none measured. |
| `back on HomeNet` | OK | The way back after a failed switch or a too-slow preferred network. |
| `back on HomeNet - linked but still no internet` | INFO | The way back linked without internet; `, recovery continues` appended inside a recovery. |
| `higher-priority network HomeNet visible twice - leaving OfficeNet to go home` | INFO | Two consecutive preferred-network sightings; ` (seen and lost 3 times before)` appended after flickers. |
| `preferred network HomeNet was visible at one check and gone at the next - staying on OfficeNet until it holds for two checks in a row` | INFO | A flicker, once per stay on the current network. |
| `returned to preferred network: HomeNet (upload 900 kbps)` | OK | The preferred network passed the measurement. |
| `internet restored: HomeNet - down 5 min, 3 recovery runs` | OK | The internet is back after a loss; `1 recovery run` for one. |
| `repeated 12 more times during the outage (last at 03:41): outage looks external: the router answers, the fault is upstream — waiting, not rebooting` | INFO | After `internet restored`, one per step the recovery repeated, with the hour of the last repeat. |
| `uplink answering late on HomeNet - 3 quick checks timed out, the patient check passed, no recovery` | INFO | The first late pass of an episode; `internet answered late N more times in the last hour on HomeNet - slow link, no recovery` hourly, `uplink answers normally again on HomeNet - answered late N times over 26 min` closes it, `internet answered late N more times before this loss on HomeNet - slow link` when a loss ends it. |
| `reboot clock cleared - NetworkManager picked the device up again` | INFO | nm: NetworkManager showed a connecting or readable state after an announced arming. |
| `dropping temporary network FreeCafe - it stopped delivering` | INFO | A recovery starts while the device is on a temporary entry; once per outage. |
| `back on a stored network: HomeNet - temporary network FreeCafe removed` | OK | The healthy tick that finds the device home again. |
| `no emergency network delivered (1 tried, 0 skipped)` | INFO | The emergency walk ended without a win; once per outage. |
| `trying open networks as last resort (3 open networks heard)` and `no open network delivered internet (3 heard, 2 tried, 1 linked without internet)` | INFO | The open-network walk's opener and closer; once per outage each. |
| `connected to EMERGENCY network: MyPhone (upload 620 kbps) - stored networks stay armed, home again when one returns` | OK | An emergency network delivered internet; `(signal mode)` without a probe target. |
| `connected to OPEN network: FreeCafe (upload 620 kbps) - stored networks stay armed, home again when one returns` | OK | An open network delivered internet. |
| `internet back on HomeNet - monitoring only` | OK | Monitor-only mode: the internet returned. |
| `delivered 9 held lines stamped 03:10 to 03:41 - they stand above this line with their own times` | INFO | After every delivery of held lines; `delivered 1 held line stamped 03:10 - it stands above this line with its own time` for one; `site reachable again - delivered 9 held lines stamped 03:10 to 03:41, they stand above this line with their own times` (OK) when the delivery closes a refusal episode. |
| `wifi cell accepted again` | OK | The site took the WiFi cell after refusing it. |
| `wifi scan list accepted again` | OK | The site took the WiFi scan list after refusing it. |
| `local log /var/log/awacs.log writable again` | OK | Appends to the local log succeed again. |
| `AWACS stopping on SIGTERM (systemctl stop or shutdown) - stored networks re-enabled, the network layer runs on its own until the next start` | INFO | A graceful stop; `SIGINT (Ctrl+C)`, `SIGHUP (terminal closed)` or `SIGQUIT` name the other signals. |

Further `DEBUG` lines (`scan: 1/3 tries used`, `connect_id: activating ...`, `QA: flow=...`, `best_pref_id: ...`, `quick check timed out under load (sent ${sent} B during it) - patient check passed`, `sent ${sent} B during the failed quick check, the patient check failed too - counting it`, `gentle open skipped: the link is alive (gateway reachable) - the outage is upstream`) trace decisions in the local file and are silenced with `DEBUG="no"`.
