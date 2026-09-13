# Troubleshooting

Each entry is a line the script itself prints, where it appears, what it means, and what to do. Local log: `/var/log/awacs.log`. Daemon stderr goes nowhere under the respawn loop, so the two conf refusals below are best seen by running `sudo awacs.sh status` on a terminal.

## `awacs: IGNORING /etc/awacs.conf (not owned by root — chown root: it)`

Where: stderr, at every start (daemon or toolbox word run as root).

Meaning: the conf exists but is not owned by root. It was probably restored from a backup as another user. The daemon runs on defaults: no `SAFETY_NET`, no site.

Fix: `sudo chown root:root /etc/awacs.conf`.

## `awacs: IGNORING /etc/awacs.conf (group/world can access it — chmod 600 it)`

Where: stderr, at every start.

Meaning: the mode has group or other bits (`0644`, `0640`, …). The conf carries hotspot passwords; a world-readable conf is as much a leak as a writable one, so it is refused.

Fix: `sudo chmod 600 /etc/awacs.conf`.

## A knob you set is not applied, with no message

Meaning: its value failed validation. Numbers must be non-zero integers of at most seven digits; `NIGHT_START`/`NIGHT_END` must be `HH:MM`; `RUN_DIR` must start with `/`. Failed values fall back to the defaults silently by design (a typo must not crash the daemon).

Fix: check the line in the conf. `SAFETY_NET` entries need the exact form `SAFETY_NET["Name"]="password"`.

## `missing tools: X Y - will try to install once online`

Where: `[ERROR]`, at start.

Meaning: `check_tools` did not find X and Y in `PATH`. The inventory is backend-aware: `wpa_cli` on legacy images, `nmcli` on NM images, plus `iw ip ping curl awk sed grep pgrep rfkill flock timeout stat date modprobe`.

What happens next: at the third healthy tick `install_tools` runs `apt-get install` once per boot in the background. Expect `installing missing tools: <packages>` and then either `tools installed: …` or `tool install failed - still missing: … - install manually`. If the box has no `apt-get`: `no apt-get on this system - install manually: …`.

Fix if it fails: install the named packages by hand, or wait for the next boot (the once-per-boot marker is `/run/awacs/apt_tried`).

## `interface wlan0 not present - is the WiFi hardware alive?`

Where: `[ERROR]`, at start.

Meaning: `detect_if` found no wireless interface in `iw dev` and fell back to `wlan0`, which does not exist either. Dead radio, unplugged dongle, missing driver, or `iw` itself missing (then a `missing tools: iw` line precedes it).

Fix: check `iw dev`, `rfkill list`, `dmesg | grep -i brcm`. Set `AWACS_IF` if the interface has an unusual name.

## `internet lost on wlan0 - engaging`

Where: `[WARN]`, once per outage.

Meaning: `NET_FAIL_TICKS` ticks without any `have_net` rung passing. The fight starts and repeats every tick until the internet is back. Not an error in itself; read the lines that follow.

## `outage looks external (round N) — waiting, not rebooting`

Where: `[INFO]`, up to three times per fight.

Meaning: the gateway answers (or NM is mid-transition), so the WiFi link works and the problem is upstream: ISP, router WAN, DNS at the router. AWACS still tries `SAFETY_NET` and open networks in case another network has a different upstream, then waits.

Fix: none on the device. Check the router.

## `association refused - wrong password? (recovery continues, reboot stays off)`

Where: `[ERROR]`, per fight round.

Meaning: on wpa a stored network is `TEMP-DISABLED` in `wpa_cli list_networks`; on NM an activation failed with a secrets/authentication error. The ladder still runs; the reboot clock is disarmed.

Fix: correct the password in your own network configuration (`wpa_supplicant.conf` or the NM profile). AWACS never edits it.

## `fight round N: ME evidence (LINK_OK=0, gw unreachable, auth_failing=0)`

Where: `[DEBUG]` (needs `DEBUG=yes`).

Meaning: the round classified the outage as the device's own: a stored network is visible but cannot be ridden, or the radio sees nothing, or the stored list is empty; no gateway; no credentials signature. The ladder runs and the reboot clock is armed (on NM only once `nm_me_settled` agrees).

## `recover L1: radio bounce` / `recover L2: …` / `recover L3: …`

Where: `[WARN]`.

Meaning: the recovery ladder is running, one rung per round: radio, network service (`dhcpcd` or NetworkManager), WiFi firmware (`brcmfmac`). A ladder that repeats every fight for many minutes with no `internet restored` is a genuine local wedge and leads to the valve below.

## `wedged Nmin with networks visible — rebooting (repeats per streak until cured)`

Where: `[ERROR]`, local log only, immediately before a reboot.

Meaning: continuous ME evidence for `REBOOT_AFTER_MIN` minutes, every rung tried, no wrong-password signature, no gateway. The reboot is the last cure. After the reboot the streak starts again from zero; if the wedge survives the reboot, the next one comes after another full streak.

If this repeats: the fault is below AWACS — driver, power supply, SD card, a router that beacons but never leases. `journalctl -b -1` and `dmesg` from the previous boot are the next places to look. Raising `REBOOT_AFTER_MIN` spaces the reboots out; it does not fix the cause.

## `NetworkManager image but AWACS cannot drive it (unmanaged/no nmcli) - monitoring only`

Where: `[ERROR]`, at start.

Meaning: NetworkManager is active or enabled, but either `nmcli` is missing or the interface is unmanaged (device state 10). AWACS parks: it checks the internet every 300 s, flushes the spool, and lets `install_tools` run once. Fighting an unmanaged device would be inert.

Fix for a missing `nmcli`: wait for the install (`nmcli is now installed - restarting as a full NetworkManager supervisor` follows, then a fresh start line), or `apt-get install --reinstall network-manager`.

Fix for an unmanaged interface: look in `/etc/NetworkManager/conf.d/` and `/etc/NetworkManager/NetworkManager.conf` for `unmanaged-devices`, or `nmcli device set wlan0 managed yes`. The next respawn re-detects and logs `NetworkManager backend - AWACS supervises it (full capability)`.

## `NM is still trying - waiting it out`

Where: `[INFO]`, per fight round on NM, and at a rung boundary.

Meaning: the device is in NetworkManager's connecting band — at the round's start, or again when NM is re-read after the evidence was gathered. AWACS defers: no candidate probing, no rung, the ME clock cleared. Normal on NM during an outage.

## `NetworkManager is connected, internet is not (round N) — router-side, no rung`

Where: `[INFO]`, NM only.

Meaning: at a rung boundary NM reported state 100 (connected, with an address) but `have_net` fails. That is the router's problem, not the device's; no rung runs and the clock is cleared.

## `BUG: wpa_cli reached under nm backend: …`

Where: `[ERROR]`.

Meaning: a code path called the `wpa()` helper while the backend is NetworkManager. This is a tripwire and should never fire. The call returns failure and nothing is sent to `wpa_cli`.

Fix: report it with the log line; it names the arguments.

## `scan failed - using previous results (if any)`

Where: `[WARN]`.

Meaning: `iw`, `iwlist` and the backend's own scan table all returned nothing after every retry. Right after boot the radio answers slowly (AWACS already allows six tries in the first three minutes). If it persists while the box is online, the radio or driver is unwell; `iw dev wlan0 scan` by hand shows the error. A single `Device or resource busy` no longer produces this line: AWACS reads the supplicant's or NM's table instead. The old picture is served and its timestamp refreshed (one retry per `SCAN_TTL`); the third empty scan in a row drops it — see the next entry.

## `radio heard nothing on N scans in a row - previous results dropped`

Where: `[WARN]`, once per silence.

Meaning: three consecutive fresh scans (`iw`, `iwlist`, the backend's table) heard no beacon at all. The stale scan picture was dropped so the fight, the toolbox and the WiFi cell stop showing networks that are not there. A healthy radio always hears neighbours; if this line appears while the box is not moving, the radio or its driver is wedged — the fight will classify it as the device's own fault and, after `REBOOT_AFTER_MIN` minutes of that, the reboot valve fires. The line is not repeated; the first beacon heard again ends the streak silently.

## `reporting: local | probe: none - signal mode | wifi cell: auto`

Where: `[INFO]`, right after the start line.

Meaning: the reporting knobs as applied: log target (and site), upload-probe target, WiFi-cell mode. `probe: none - signal mode` says there is no `SITE_URL` and no `PROBE_URL`: no upload QA, no dance, network choice by signal when the internet is lost. If you set the knobs in `/etc/awacs.conf` and still see `local`, the conf was not applied (owner/mode entries above) or `SITE_URL` failed validation (plain `http://` or `https://` URL, no spaces).

## `LOG_TARGET asked for the site but SITE_URL is empty - running local-only`

Where: `[WARN]`, once at start.

Meaning: `LOG_TARGET` was `both` or `remote` without a `SITE_URL`. The target was downgraded to `local`. Set `SITE_URL` or set `LOG_TARGET="local"` to silence it.

## `connected: X (signal mode - no upload probe target configured)` / `returned to preferred network: X (signal mode)`

Where: `[OK]`.

Meaning: signal mode (no probe target). The fight kept the strongest visible stored network that delivered internet; the preferred-network return went home without measuring. Neither line quotes a speed because none was measured. `awacs.sh speed` in this mode prints `no probe target (signal mode)`: set `SITE_URL` or `PROBE_URL` for measured choice.

## `aasw.sh is still running - two WiFi authorities will fight; remove its rc.local line`

Where: `[WARN]`, at start.

Meaning: the predecessor script is still launched somewhere. Remove its `rc.local` line and its file.

## `REFUSING delete: 'name' is not an awacs crutch` / `… lives outside /run (owner file?)`

Where: `[ERROR]`, NM only.

Meaning: a delete was requested for a profile that is not named `awacs-crutch-*`/`awacs-safety-*` or does not live under `/run/NetworkManager/system-connections/`. The delete did not happen. This is the no-block law's last guard; it should never fire.

## `no challenger beat the incumbent - staying on X`

Where: `[OK]`.

Meaning: an evaluation probed the other stored networks and none beat the current one by the required gain. The box went back to where it was. Not an error.

## `preferred network too slow (N kbps) - benching it, going back`

Where: `[WARN]`.

Meaning: the higher-priority network came back, AWACS moved to it and measured under the floor, so it returned to the previous network and will not try that one again for three cooldowns.

## The toolbox prints the ROOT ACCESS REQUIRED box

Meaning: `status`, `networks`, `evaluate`, `scan` and `speed` need root (they read the supplicant or NM and the private state dir). Only `check` and `help` run unprivileged.

## `awacs.sh: usage: …` and exit 1

Meaning: the word is misspelled. The check runs before the root gate so a typo and a missing `sudo` stay distinguishable.

## Another instance is already running (INSTANCE ERROR box)

Meaning: you launched the daemon by hand while the service already runs it. The lock is `flock` on `/run/awacs/lock`; the box shows the running pid. Use the toolbox words instead; they run beside the daemon.

## Site log shows nothing although `LOG_TARGET` is `both`

Check in order: `SITE_URL` set and reachable from the device (`curl -s -o /dev/null -w '%{http_code}\n' --data-urlencode probe=1 "$SITE_URL/$DEVICE_ID/device_api.php"` must print `400`); the conf actually applied (owner/mode above); the spool `/run/awacs/spool` — lines waiting there are delivered ~30 s after the internet is proven healthy and retried every ~5 min.

## The WiFi cell shows no speed

Normal. The speed is measured at decision moments only (a fight's candidate probe, an evaluation after slow upload, arrival on a preferred network), and it is shown only while the device is still on the network it was measured on. `0` in the first field means "no measurement for this network yet".
