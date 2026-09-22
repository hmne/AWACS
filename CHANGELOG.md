# Changelog

All notable changes to AWACS. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [Semantic Versioning](https://semver.org/).

## 1.0.0 - 2026-09-19

First public release.

### Added

- Two backends in one file: `wpa` (dhcpcd and wpa_supplicant, driven through `wpa_cli`) and `nm` (NetworkManager, driven through `nmcli`). On NetworkManager the daemon waits while NetworkManager reports the device in a transition (`NM is still trying - waiting it out`), runs no rung on a device NetworkManager reports as connected (`NetworkManager is connected, internet is not (round N) — router-side, no rung`), runs a recovery rung only when NetworkManager reports the device disconnected, failed or unavailable or when `nmcli` cannot read the state, checks NetworkManager again at every rung boundary, and credits a connection NetworkManager made on its own. The backend is detected at start, with up to 60 seconds of patience for NetworkManager at boot. Monitor-only mode when `nmcli` is missing or the interface is unmanaged; the daemon exits for a respawn once `nmcli` has been installed.
- Internet check every `TICK` seconds in two forms. The quick form starts every tick and is the only one the toolbox words `check` and `status` use: one ping to each of 8.8.8.8 and 1.1.1.1 with a 2-second wait, then HTTP 204 from connectivitycheck.gstatic.com and HTTP 400 from the site endpoint with 3-second limits. The patient form sends three pings per target 0.3 seconds apart, waits 5 seconds for each and gives both HTTP requests 8 seconds.
- A failed quick check is not a failure by itself. The daemon reads the interface's sent-bytes counter across the failed check: 16384 bytes or more means the device was busy sending, an upload or a live stream, and one patient check decides the tick. A link that sent less counts as failed at once, so a dead link keeps its timing. The patient check is paid at most once per outage; after one has failed, the quick check alone decides until it passes again.
- On the tick that reaches `NET_FAIL_TICKS`, while the default gateway still answers and no patient check has failed in this outage, one more patient check runs before anything is torn down. When it passes, the tick counts as healthy, no recovery starts and the local file records `internet answers late, not never - slow link, no recovery (${NET_FAIL_TICKS} quick checks timed out)`.
- Detection timing with the defaults: recovery starts 40 to 63 seconds after a loss on a link whose gateway has gone silent, and about 72 to 83 seconds after an upstream outage on a link whose router keeps answering, the difference being that single patient check.
- Recovery after `NET_FAIL_TICKS` failed checks: every visible stored network, one recovery rung per round (radio, network service, WiFi firmware), emergency networks with passwords (`SAFETY_NET`), open networks last.
- A recovery reads the link before it acts. While the gateway answers, the first recovery of an outage keeps the association instead of reassociating: it remembers the network the device is on, leaves it out of the candidates, and returns to it when no other network delivered. The second recovery of the same outage reassociates anyway, because a router that answers a ping yet forwards nothing for this device is cured by a fresh association.
- A network the device already rides with an address is never re-activated when a recovery or a return asks for it; it is proven where it stands, so a live association is not bounced.
- Every stored network is re-enabled again after a failed emergency or open-network attempt, before the round's 20-second wait, so no round waits with the stored networks left disabled.
- Outage classified as on-device or external before any teardown. A reboot only after `REBOOT_AFTER_MIN` minutes of on-device evidence; a wrong-password sign resets the timer; on NetworkManager the timer runs only after NetworkManager has given up (settled disconnected or failed twice in a row, or `nmcli` unreachable after the NetworkManager restart of rung L3).
- No writes to stored network configuration: no `save_config`, no `disable_network`, no `nmcli connection modify`, no `nmcli device wifi connect`. Temporary networks live only in the running supplicant or as `/run` keyfiles and are removed by the next daemon start; every stored network is re-enabled at every recovery start, win, loss and shutdown.
- Network choice by measured upload: a `PROBE_KB` POST to the probe target; a challenger must reach `SWITCH_GAIN_PCT` percent of the current network's measured speed; `DANCE_COOLDOWN` seconds between evaluations; a passive kernel-counter meter for routine checks.
- Return to a higher-priority stored network every `PREF_CHECK` seconds after two consecutive sightings, measured on arrival; a preferred network that measures too slow is set aside for three cooldowns.
- Day and night profile (`NIGHT_*`), live-stream awareness (`STREAM_MIN_KBPS`), optional stealth mode (`STEALTH_MODE`).
- `DEBUG=yes` decision lines, among them `quick check timed out under load (sent ${sent} B during it) - patient check passed`, `sent ${sent} B during the failed quick check, the patient check failed too - counting it` and `gentle open skipped: the link is alive (gateway reachable) - the outage is upstream`.
- Local log with rotation (`LOG_CAP`); site log with an Arabic message where the program has one; offline spool (`SPOOL_CAP`) with the first line kept, delivered in order after recovery.
- WiFi cell for a dashboard, `kbps,visible,total,band,SSID`, sent to `tmp/wifi.tmp` about every 60 seconds.
- Scan sources, for the daemon and for the `evaluate` and `scan` words: `iw`, then `iwlist`, then the backend's own scan table whenever `iw` returns nothing (a busy answer ends the `iw` retries early). A radio that hears nothing on three scans in a row drops the stale scan results.
- Rung L1 on NetworkManager blocks and unblocks only the interface's own rfkill index; `nmcli radio wifi` is the fallback for drivers without an rfkill node.
- Once-per-boot background install of missing tools with the Debian package names.
- Toolbox words `status`, `networks`, `evaluate`, `scan`, `speed`, `check`, `help`; `check` and `help` need no root. Compatibility flags `-d` and `-q`.
- Settings file `/etc/awacs.conf`: root-only 0600 enforced, plain assignments only, every numeric knob validated with fallback to the default.
- Reporting knobs `SITE_URL`, `SITE_API`, `LOG_TARGET`, `PROBE_URL`, `REPORT_WIFI`, `SITE_TZ`; `DEVICE_ID` from the environment (fallback: `/tmp/device_id`, then the short hostname). Signal mode when no site and no probe target is configured: connectivity supervision without upload measurement or switching; the site lines say `signal mode` in place of a speed, `speed` answers `no probe target (signal mode)`, and the start-up `reporting:` line states the applied knobs.
- Non-ASCII network names: raw-text matching on wpa, lowercase-hex matching on nm, decoded display everywhere.
- Shutdown on TERM (`systemctl stop`, a closing terminal): the handler ignores further signals while it runs, re-enables every stored network and exits 0.
- Setup wizard `install.sh` (whiptail or plain prompts, English and Arabic, `--yes`, `--dry-run`, `--uninstall [--purge]`), the systemd unit `systemd/awacs.service`, two self-hosted receivers (`server/receiver.php`, `server/receiver.py`) and a read-only terminal dashboard (`tools/awacs-tui.sh`).

### Known limitations

Listed in the Limitations section of [README.md](README.md).
