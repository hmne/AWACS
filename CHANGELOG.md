# Changelog

All notable changes to AWACS. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [Semantic Versioning](https://semver.org/).

## [1.0.0] — 2026-09-13

First public release. Successor to the private `aasw.sh` line; every capability of the predecessor is kept, improved, or replaced by a documented alternative.

### Added

- Dual backend in one file: `wpa` (dhcpcd + wpa_supplicant, driven through `wpa_cli`) and `nm` (NetworkManager, driven through `nmcli` as a supervisor that waits out NM's own retries). Detection at start with up to 60 s boot patience; monitor-only park when `nmcli` is missing or the interface is unmanaged, with exit-and-respawn once `nmcli` is installed.
- Network choice by measured upload (`best_by_upload`), with a configurable gain a challenger must beat and a cooldown between evaluations. Passive kernel-counter meter for routine checks; probes only at decision moments.
- Fight ladder: gentle reassociate, every visible stored network, three recovery rungs per backend (radio, network service, WiFi firmware), emergency networks with passwords (`SAFETY_NET`), open networks last.
- ME-versus-external classification before any teardown; reboot valve armed only by the device's own wedge for `REBOOT_AFTER_MIN` minutes; wrong-password signature disarms it; on NM the valve arms only after NM has settled in disconnected/failed twice, or when NM itself is unreachable and its restart is spent.
- No-block law: no `save_config`, no `disable_network`, no `nmcli connection modify`, no `nmcli device wifi connect`; temporary networks live only in the live supplicant or as `/run` keyfiles and are reaped by the next daemon; all stored networks re-enabled at every fight start, win, loss and shutdown.
- Preferred-network return every `PREF_CHECK` after two consecutive sightings, measured on arrival, with a three-cooldown bench for a slow preferred network.
- Day/night profile (`NIGHT_*`), live-stream awareness (`STREAM_MIN_KBPS`), optional stealth mode.
- Bilingual logging: English local file with rotation, Arabic site lines, offline spool with a pinned first line, ordered delivery after recovery.
- WiFi cell for a dashboard: `kbps,visible,total,band,SSID` every ~60 s.
- Once-per-boot background install of missing tools with correct Debian package names.
- Toolbox words: `status`, `networks`, `evaluate`, `scan`, `speed`, `check`, `help`; `check` and `help` need no root. Compat flags `-d`, `-q`.
- Isolated conf `/etc/awacs.conf`: root-only 0600 enforced, plain assignments only, every numeric knob validated with fallback to defaults.
- Public-edition knobs: `SITE_URL`, `LOG_TARGET`, `PROBE_URL`, `REPORT_WIFI`, `SITE_TZ`; `DEVICE_ID` from the environment (fallback: hostname). Local-only operation when no site is configured: "signal mode" — connectivity supervision without upload QA, dance or veto; the start line reports the applied knobs (`reporting: … | probe: … | wifi cell: …`).
- Arabic and other non-ASCII SSIDs: raw-text matching on wpa, lowercase-hex matching on NM, decoded display everywhere.
- Real-stack lab under QEMU with `mac80211_hwsim` radios, hostapd, dnsmasq, dhcpcd/wpa_supplicant and NetworkManager (`lab/`), 22 scenarios, byte-level no-block proofs.
- Setup wizard `install.sh` (whiptail or plain prompts, English/Arabic, unattended `--yes`, `--dry-run`, `--uninstall [--purge]`), the systemd unit `systemd/awacs.service`, two self-hosted receivers (`server/receiver.php`, `server/receiver.py`), a read-only terminal dashboard (`tools/awacs-tui.sh`) and a knob-table generator (`tools/gen-config-table.sh`).

### Fixed

- 2026-09-12 — `iw dev … scan` answers `Device or resource busy` whenever the supplicant or NetworkManager is mid-scan, which is exactly when AWACS scans most (77 of 107 legacy daemon scans and 17 of 25 NM scans in the lab fell back to a stale cache; the toolbox words `evaluate` and `scan` printed an empty air and `speed` failed). `scan()` now waits once on busy and reads the backend's own table through the new `scan_backend()` (wpa `scan_results`; NM `device wifi list --rescan no` with percent converted back to dBm and hex back to `iw`'s escaped text). Order: `iw` → `iwlist` → backend table. After the fix every toolbox word passed on both images (16/16, 17/17) and scans succeed on the first try.
- 2026-09-13 — On NetworkManager, recovery rung L1 fired five seconds after NM's own autoconnect had already activated the home network (the ME evidence takes ~12 s to gather and the rung ran unconditionally). `fight()` now re-checks NM at every rung boundary: `nm_wait_settled`, credit `have_net`, and a device NM reports connected (state 100) without internet takes the router-side branch with no rung. Root-caused from NM's live journal (`lab/evidence/nm/11-INVESTIGATION.md`).
- 2026-09-13 — Rung L1 on NM used `nmcli radio wifi off`, which soft-blocks every wireless radio on the box (a second dongle; in the lab, the access points themselves). It now blocks and unblocks only the interface's own rfkill index from `/sys/class/net/IF/phy80211/rfkill*`, keeping `nmcli radio` as the fallback for drivers without an rfkill node, then waits for NM to settle. With both 2026-09-13 fixes, a box killed on a temporary network came back online 25 s after the respawn's reap instead of 10–25 minutes.
- 2026-09-13 — A radio that heard nothing (lab: the station moved to an empty `hwsim` group) hid behind a stale scan cache for 37 minutes on the NM image: `scan()` only ever replaced the cache with non-empty results, so the fight's "radio sees nothing" tell could not fire and the reboot valve never armed. `scan()` now counts consecutive fresh scans that heard nothing and drops the stale picture at the third (`radio heard nothing on 3 scans in a row - previous results dropped`); an empty fresh cache is served for `SCAN_TTL` like any other, and a failed scan refreshes the cache timestamp so the radio is asked once per `SCAN_TTL`, not once per caller.
- 2026-09-13 — At the rung boundary on NM, a device back in the connecting band (40–90, 110) fell through to a recovery rung. It now gets the round-top treatment: `NM is still trying - waiting it out`, 20 s, next round.
- 2026-09-13 — `systemctl stop` (a cgroup SIGTERM) killed the shutdown handler before `enable_all` and the goodbye box (6 of 6 stops in the lab): the handler reset its trap, and systemd's second TERM landed inside it. The handler now ignores the signals for its own duration and exits 0.
- 2026-09-13 — Signal mode: with no probe target `up_kbps` read 0, which made the preferred-network return veto home as `too slow (0 kbps)` and would have let a slow real flow trigger a dance with no measurement behind it. Upload QA and the arrival measurement now require a probe target; the story lines say `signal mode` instead of a number; `speed` says `no probe target (signal mode)`.
- 2026-09-13 — The ROOT ACCESS box was one space short of the original on its `Run:` line.

### Known limits

- wpa backend only: open networks with non-ASCII names are skipped as last-resort candidates; stored names containing a literal backslash, double quote, tab, newline, escape byte or edge space never match visibility.
- NM backend: a hidden owner profile must already carry `802-11-wireless.hidden=yes`; NM device state 20 (unavailable) never arms the reboot valve.
- The lab is a Linux VM with `mac80211_hwsim`; the Raspberry Pi's `brcmfmac` driver, real wall-clock timings, captive portals, a real ISP and IPv6 were not exercised.

[1.0.0]: https://github.com/hmne/AWACS/releases/tag/v1.0.0
