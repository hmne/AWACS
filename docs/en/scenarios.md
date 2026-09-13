# Scenarios

Concrete situations, each as: the situation, what a stock system does, what AWACS does, what the log shows. The log lines are real ones from the lab (`lab/evidence/*/RESULT.txt` and the captured `awacs.log` files). The lab used `REBOOT_AFTER_MIN=4`, `PREF_CHECK=60` and `DANCE_COOLDOWN=120` to shorten waits; timings inside the VMs are 3–5× slower than a real board.

## 1. Wrong password on the only reachable network

**Situation.** The router's password changed, or the stored one is wrong. No other stored network is on the air.

**Stock system.** wpa_supplicant marks the network `TEMP-DISABLED` and retries on its own schedule; NetworkManager tries, fails, and leaves the device disconnected. Nothing is written down, nothing else is tried, and a watchdog script that "reboots when the internet is gone" reboots forever.

**AWACS.** The fight starts. The evidence signature looks like a local wedge (network visible, cannot be ridden, no gateway), but `auth_failing` fires, so the reboot clock is set to zero every time it is seen. The ladder still runs (a real wedge can coincide with one stale password), emergency and open networks are tried, and the moment the right password is back the box heals.

**Log (legacy image, 2026-09-12).**

```text
[WARN][12/09 17:54:36] internet lost on wlan0 - engaging
[ERROR][12/09 17:56:21] association refused - wrong password? (recovery continues, reboot stays off)
[WARN][12/09 17:56:22] recover L1: radio bounce
[INFO][12/09 17:56:31] trying emergency networks (1 listed)
[INFO][12/09 17:57:06] trying open networks as last resort
[ERROR][12/09 17:58:31] association refused - wrong password? (recovery continues, reboot stays off)
[WARN][12/09 17:58:33] recover L2: restart dhcpcd (respawns the REAL per-interface supplicant)
[WARN][12/09 18:00:49] recover L3: reload brcmfmac firmware (the 3-second cure a wedge needs)
[OK][12/09 18:01:05] internet restored: HomeNet
```

Lab verdict: same boot id after 403 s (past the lab's 4-minute valve), healed when the right password returned. Same result on the NetworkManager image.

## 2. Home access point goes down, then comes back

**Situation.** The priority-10 network disappears. A priority-5 network (here one with an Arabic name) is still on the air.

**Stock system.** wpa_supplicant roams to the other stored network by itself; NetworkManager does too. Neither comes back when the home network returns unless the current link drops, and neither knows which network actually uploads faster.

**AWACS.** The base layer moves the box; if it is slow about it, the fight does it (`best_by_upload` measured the Arabic network at 1484 kbps on the NM image). Then every `PREF_CHECK`, `best_pref_id` looks for a visible stored network with a strictly higher priority; after two consecutive sightings AWACS goes home and measures on arrival.

**Log (legacy image).**

```text
[WARN][12/09 19:54:45] internet lost on wlan0 - engaging
[OK][12/09 19:55:04] internet restored: شبكة البيت
[INFO][12/09 19:56:47] higher-priority network visible - trying to go home
[OK][12/09 19:57:07] returned to preferred network: HomeNet (upload 7445 kbps)
```

**Log (NetworkManager image).**

```text
[WARN][12/09 17:52:03] internet lost on wlan0 - engaging
[INFO][12/09 17:53:56] candidate [6b81e11c-…] شبكة البيت uploads at 1484 kbps
[OK][12/09 17:54:15] internet restored: شبكة البيت
[INFO][12/09 17:57:48] higher-priority network visible - trying to go home
[OK][12/09 17:58:06] returned to preferred network: HomeNet (upload 1948 kbps)
```

The move took 18 s on the legacy image and 162 s on NM, because on NM AWACS waits out NetworkManager's own retries first. The WiFi cell on the site switched to `1484,2,2,5GHz,شبكة البيت`.

## 3. Every stored network is gone: emergency network, then an open one, then home

**Situation.** All stored networks are off the air. A phone hotspot listed in `SAFETY_NET` may or may not be on; a cafe's open network is.

**Stock system.** Nothing. Both stacks only know the stored networks.

**AWACS.** `try_safety` first: every `SAFETY_NET` entry is attempted even if the scan does not show it. Then `try_open`: truly open networks, one attempt per SSID, weak strangers skipped. The connected network is a temporary entry — wpa: a live-supplicant network id never saved; NM: a `/run` keyfile, `autoconnect=false`, mode 0600, nothing under `/etc`. When a stored network is current again, the temporary entry is removed.

**Log (NetworkManager image).**

```text
[WARN][12/09 18:08:55] internet lost on wlan0 - engaging
[INFO][12/09 18:10:20] outage looks external (round 1) — waiting, not rebooting
[INFO][12/09 18:10:27] trying emergency networks (1 listed)
[INFO][12/09 18:11:03] trying open networks as last resort
[OK][12/09 18:11:35] connected to OPEN network: FreeCafe
[OK][12/09 18:11:36] internet restored: FreeCafe
[WARN][12/09 18:13:05] internet lost on wlan0 - engaging
[INFO][12/09 18:14:25] trying emergency networks (1 listed)
[OK][12/09 18:14:53] connected to EMERGENCY network: LabHotspot
[OK][12/09 18:14:54] internet restored: LabHotspot
[INFO][12/09 18:18:45] higher-priority network visible - trying to go home
[OK][12/09 18:19:23] returned to preferred network: HomeNet (upload 2302 kbps)
```

Lab evidence: `awacs-crutch-1789236666-2629` lived in `/run/NetworkManager/system-connections`, mode 0600, `autoconnect=false`; nothing of AWACS in `/etc/NetworkManager/system-connections`; after the return home no `awacs-*` connection remained. On the legacy image the live supplicant held 3 networks (2 owner + 1 crutch) during the fallback and 2 afterwards.

## 4. ISP outage: the router answers, the internet does not

**Situation.** The WiFi link is perfect; the upstream is down.

**Stock system.** Both stacks are happy: they see an association and a lease. A naive watchdog reboots the box every N minutes for hours.

**AWACS.** `gw_ok` passes, so the outage is external. The clock stays at zero, the ladder does not run, and each round logs the verdict and waits 20 s. Emergency and open networks are still tried, because a different network may have a different upstream. Site lines spool meanwhile and land after recovery.

**Log (NetworkManager image).**

```text
[WARN][12/09 18:22:44] internet lost on wlan0 - engaging
[INFO][12/09 18:23:57] outage looks external (round 1) — waiting, not rebooting
[INFO][12/09 18:24:07] trying emergency networks (1 listed)
[INFO][12/09 18:24:42] trying open networks as last resort
[INFO][12/09 18:26:44] outage looks external (round 2) — waiting, not rebooting
[OK][12/09 18:28:06] internet restored: FreeCafe
```

Site log after recovery: `[INFO] AWACS: الانقطاع يبدو خارجياً (جولة 1) — ننتظر بلا إعادة تشغيل, 12/09/2026 09:23:58 PM.` — the spool held 6 lines while offline and delivered them in order.

## 5. A real wedge on NetworkManager: the reboot valve

**Situation.** The stored network beacons and accepts the association, but no lease ever arrives and no other network is on the air. On NM the device drops the link and settles in disconnected/failed.

**Stock system.** NetworkManager retries a few times and stops. The box sits offline until someone power-cycles it.

**AWACS.** ME evidence: visible stored network, `LINK_OK=0`, no gateway, no credentials signature. On NM the clock arms only once `nm_me_settled` sees NM given up twice in a row. The ladder runs L1, L2, L3 and repeats. After `REBOOT_AFTER_MIN` of continuous evidence the valve fires — locally logged only, because nothing can be sent — and the box comes back connected.

**Log (NetworkManager image, `REBOOT_AFTER_MIN=4`).**

```text
[WARN][12/09 19:00:53] internet lost on wlan0 - engaging
[DEBUG][12/09 19:04:01] fight round 1: ME evidence (LINK_OK=0, gw unreachable, auth_failing=0)
[WARN][12/09 19:04:02] recover L1: radio bounce
[WARN][12/09 19:05:07] recover L2: re-kick NetworkManager on wlan0
[WARN][12/09 19:06:15] recover L3: restart NetworkManager + reload WiFi firmware
[WARN][12/09 19:08:10] recover L1: radio bounce
[WARN][12/09 19:09:09] recover L2: re-kick NetworkManager on wlan0
[WARN][12/09 19:10:28] recover L3: restart NetworkManager + reload WiFi firmware
[ERROR][12/09 19:11:22] wedged 4min with networks visible — rebooting (repeats per streak until cured)
[INFO][12/09 19:13:48] AWACS 1.0 starting on wlan0 (device cam1)
[INFO][12/09 19:13:48] NetworkManager backend - AWACS supervises it (full capability)
```

A second lab run masked and stopped NetworkManager entirely (`nmcli` exit 8, state unreadable). L3's `systemctl restart NetworkManager` could not help; once L3 was spent the clock armed, the valve fired 47 s after it ripened, and the box reconnected after the reboot.

Note the same setup on the legacy image is **not** an outage: dhcpcd keeps its valid lease and default route, the internet stays up, and AWACS correctly stays quiet.

## 6. `iw scan` says "Device or resource busy"

**Situation.** The device is associated and the supplicant or NM is scanning right now. `iw dev wlan0 scan` fails with `command failed: Device or resource busy (-16)`.

**Stock system.** Not a problem for the stacks; a problem for any script that scans with `iw`. In the lab 77 of 107 daemon scans on the legacy image and 17 of 25 on NM hit it.

**AWACS.** On `busy` it waits three seconds once, then reads the backend's own table: `wpa_cli scan_results` or `nmcli device wifi list --rescan no`, converted to the same TSV. Before this fix the log was full of `scan failed - using previous results (if any)` and `evaluate`/`scan` printed an empty air; after it, `scan: 1/3 tries used` and every toolbox word worked on both images (16/16 and 17/17 checks).

## 7. A tool is missing

**Situation.** `iw` was removed (or never installed on a minimal image).

**Stock system.** Every script that needs it fails silently.

**AWACS.** `check_tools` inventories the backend's tool list at start and reports what is missing. At the first proven-healthy moment (third healthy tick) `install_tools` runs one bounded `apt-get install` in the background, once per boot, with the right package names (`wpa_cli` → `wpasupplicant`, `nmcli` → `network-manager`, `ip` → `iproute2`, `ping` → `iputils-ping`, `pgrep` → `procps`, `flock` → `util-linux`, `modprobe` → `kmod`). Success is judged by the tool appearing in `PATH`, not by apt's exit code.

**Log (NetworkManager image).**

```text
[INFO][12/09 18:38:30] AWACS 1.0 starting on wlan0 (device cam1)
[ERROR][12/09 18:38:32] missing tools: iw - will try to install once online
[INFO][12/09 18:40:15] installing missing tools: iw
[OK][12/09 18:41:30] tools installed: iw
```

When `nmcli` itself is the missing tool on an NM image, AWACS parks in monitor-only mode, installs it (`--reinstall`, because the NetworkManager package is present but broken), and exits so the respawn loop restarts it at full capability:

```text
[ERROR][12/09 19:19:06] missing tools: nmcli - will try to install once online
[ERROR][12/09 19:19:07] NetworkManager image but AWACS cannot drive it (unmanaged/no nmcli) - monitoring only
[OK][12/09 19:24:09] nmcli is now installed - restarting as a full NetworkManager supervisor
[INFO][12/09 19:24:26] NetworkManager backend - AWACS supervises it (full capability)
```

## 8. The daemon dies while on a temporary network

**Situation.** AWACS is killed (crash, OOM, operator) while the box rides an open network it created.

**Stock system.** Not applicable; the stray profile would stay.

**AWACS.** The temporary network's id is written to `/run/awacs/open_id` before the attempt. The respawned daemon reaps it at start (`reap_crutches`; on NM also a name-prefix sweep and a `/run` glob), re-enables all stored networks, and the base layer or the next fight brings the box back.

**Lab (NetworkManager image).** `connected to OPEN network: FreeCafe` → kill → `AWACS 1.0 starting on wlan0` → crutch reaped → online again on the stored Arabic network 25 s later. The first runs of this scenario took 10–25 minutes to come back; that traced to L1 switching off every radio in the VM with `nmcli radio wifi off` and to a rung firing five seconds after NM had already reconnected. Both are fixed: L1 bounces only the interface's own rfkill switch, and every rung boundary re-checks NM first.

## 9. Sustained slow upload

**Situation.** The device is uploading, and the link delivers 107 kbps for three samples in a row while the floor is 400.

**Stock system.** Nothing; the link is "connected".

**AWACS.** Three strikes and the cooldown elapsed: one honest probe of the current network. If it measures above the floor, no switch (the passive meter saw a small feed, not a slow link). If it measures below, `best_by_upload` tries the other visible stored networks and switches only when one beats the incumbent by the gain.

**Log (legacy image).**

```text
[WARN][12/09 21:01:27] sustained slow upload (107 kbps) - evaluating known networks
```

The probe measured 4260 kbps, no switch happened, and the WiFi cell on the site read `4260,2,2,2.4GHz,HomeNet`.

## What was not exercised in the lab

Captive portals, a real ISP, IPv6, hidden `SAFETY_NET` networks, and the Raspberry Pi's own `brcmfmac` driver (the lab radio is `mac80211_hwsim`). The list is in [testing.md](testing.md).
