# Features

Every row names the function in `awacs.sh` that implements it and the reason it exists. Nothing here is planned; each line is in the code.

## Connectivity and recovery

| Capability | Function(s) | Why |
| --- | --- | --- |
| Internet check every tick: two pings, then `generate_204`, then the site's own `400` signature | `have_net` | A captive portal answers 200/302, never 204 or a 400 "no operation"; a carrier that eats ICMP still passes the HTTP rungs. |
| Fight after `NET_FAIL_TICKS` ticks without internet | `main`, `fight` | Short blips heal by themselves; thirty seconds is the line between a blip and an outage. |
| Gentle opening: reassociate, wait for a lease, check | `fight`, `reassociate`, `wait_ip` | Let the base layer (supplicant or NM) finish what it may already be doing before anything is torn down. |
| Try every visible stored network and keep the one with the best measured upload | `best_by_upload`, `visible_known_ids`, `connect_id` | Signal strength does not predict throughput; a measured upload does. |
| Three-rung recovery ladder, one layer per rung | `wpa_recover`, `nm_recover` | Each rung cures a different failure: radio, network service, WiFi firmware. |
| Emergency networks with passwords from the conf, tried before open strangers | `try_safety` | Your own hotspot is safer than a cafe's open network. |
| Open networks as the last resort, weak signals skipped | `try_open` | Any internet beats no internet, but a -85 dBm stranger is not internet. |
| Temporary networks are marked on disk and reaped by the next daemon | `mark_crutch`, `drop_open`, `reap_crutches`, `nm_reap` | A crash in the middle of a fight must not leave a stray network behind. |
| Temporary network retired as soon as a real network is current again | `main` (crutch block) | The box must not stay on a stranger's network after home returns. |
| Association plus IPv4 lease required before a connection counts | `wait_ip` | Association alone is not a connection. |
| Hidden stored networks are probed for (wpa: runtime `scan_ssid 1`) | `wpa_arm_hidden`, `pref_prescan` | A hidden home network never appears in a broadcast scan. |
| Boot aggression: no internet at start means fight now | `main` | The thirty-second grace is for running systems, not for a box that just booted offline. |
| Single instance via `flock`; a second launch on a terminal gets a clear box | dispatch block, `on_shutdown` | Two daemons on one radio fight each other. |

## Classification and the reboot valve

| Capability | Function(s) | Why |
| --- | --- | --- |
| Gateway check separates "my side" from "upstream" | `gw_ok` | A router that answers means the WiFi link works; no local action can fix an ISP outage. |
| Three "my side" tells: visible stored network that cannot be ridden, radio sees nothing, empty stored list | `fight` | Each is something only the device itself can be responsible for. |
| Wrong-password signature disarms the reboot clock but keeps the ladder running | `wpa_auth_failing`, `nm_auth_sig`, `fight` | No reboot fixes credentials; a real wedge can still coincide with one stale password. |
| Reboot only after `REBOOT_AFTER_MIN` of continuous "my side" evidence | `fight` | A reboot is a last resort and is logged as such. |
| On NM the clock arms only after NM has settled in disconnected/failed twice in a row | `nm_me_settled`, `nm_note_state` | NM cycling through its own retries is not a wedge. |
| A dead NetworkManager (nmcli exit 8 sustained, L3 already spent) does arm the clock | `nm_me_settled` | A hosed NM has one remaining cure. |

## NetworkManager supervision

| Capability | Function(s) | Why |
| --- | --- | --- |
| Backend detection with up to 60 s boot patience | `detect_backend` | NM may be enabled but not yet active early in boot; deciding `wpa` then would put two authorities on one radio. |
| Waits while NM is mid-transition (states 40–90, 110) | `nm_wait_settled`, `nm_busy` | Issuing `connection up` under an NM that is activating produces the proven reboot loop. |
| Re-check at every rung boundary; a connected-without-internet device takes the router-side branch, no rung | `fight` | Evidence takes ~12 s to gather; NM may have won in the meantime. |
| L1 bounces the interface's own rfkill switch, not the whole WLAN type | `nm_recover` | `nmcli radio wifi off` kills every radio in the box. |
| Temporary networks are `/run` keyfiles, `autoconnect=false`, mode 0600, named `awacs-crutch-*` / `awacs-safety-*` | `nm_add_crutch` | `nmcli device wifi connect` would persist a profile in `/etc`. |
| Deletion refuses anything not named and located like an AWACS crutch | `nm_del_own` | A delete must never reach an owner profile. |
| SSID matching in lowercase hex | `text2hex`, `iw2hex`, `nm_profile_hexssid`, `nm_wifi_list` | Arabic, emoji, colons and backslashes in names survive every tool's escaping. |
| `wpa_cli` tripwire under the NM backend | dispatch block | A missed call site shows up in the log as `BUG: wpa_cli reached` instead of racing NM. |
| Monitor-only park for unmanaged interfaces or a missing `nmcli`, with exit-and-respawn once `nmcli` is installed | `main` | Fighting an unmanaged device is inert; a repaired install should come back at full capability without a reboot. |

## Quality of the link

| Capability | Function(s) | Why |
| --- | --- | --- |
| Passive upload meter from kernel counters, 3 s sample | `tx_kbps` | Zero traffic; the device's own uploads are the measurement. |
| Sustained slow upload (`UP_STRIKES` samples under the floor) triggers one honest probe, then an evaluation | `main` (QA block), `up_kbps` | Never leave a working link on one bad sample. |
| A challenger must beat the incumbent by `SWITCH_GAIN_PCT` | `best_by_upload` | Switching disrupts; a marginal gain is not worth it. |
| Evaluations at least `DANCE_COOLDOWN` apart | `main` | Every comparison interrupts real traffic to measure it. |
| Live stream detection: never probe or switch under a healthy stream | `streaming`, `main` | The stream is a free upload meter; a healthy one proves the link carries its job. |
| Preferred-network return every `PREF_CHECK`, after two consecutive sightings | `best_pref_id`, `main` | A fight can strand the box on a metered hotspot after home returns. |
| Measure on arrival; a slow preferred network is benched for three cooldowns | `main` | Priority must not overrule the measured-upload law. |
| Upload probe via `curl`, with a `wget` fallback and honest zero on transport failure | `up_kbps`, `up_kbps_wget` | One dead tool must not blind the measurement; a fast failure must not read as a fast upload. |
| Day/night profiles with transition-only logging | `apply_profile` | Tolerate slower links and switch less while nobody is watching. |

## Scanning

| Capability | Function(s) | Why |
| --- | --- | --- |
| Cached scan with `SCAN_TTL`, up to 3 tries (6 in the first three minutes of uptime) | `scan` | Scans go off-channel; the radio answers slowly right after boot. |
| On `Device or resource busy`, wait once and read the backend's own scan table | `scan`, `scan_backend` | The supplicant or NM is mid-scan exactly when AWACS needs a picture most. |
| `iwlist` as a second source | `scan_iwlist` | Some drivers only answer it. |
| A successful but empty scan keeps the previous cache | `scan` | An all-hidden air must not read as "radio sees nothing". |
| Control bytes stripped from displayed names | `pssid`, `disp_ssid` | A neighbour can name an AP with escape codes. |

## Logging and reporting

| Capability | Function(s) | Why |
| --- | --- | --- |
| Local log with rotation at `LOG_CAP` lines | `log` | Bounded disk use on an SD card. |
| Decision-trace lines when `DEBUG=yes` | `dbg` | A fight must be explainable after the fact. |
| Bilingual site lines: English in the local file, Arabic on the site | `site_log` | The dashboard reader and the terminal reader are not the same person. |
| Offline lines spool; the first line is pinned so the outage's start survives the cap | `site_log` | A capped story must keep its head and its newest tail. |
| Spool flushed in order after ~30 s of proven health, then every ~5 min while lines remain | `flush_spool`, `main` | A just-healed link should carry frames before history; a site-down phase must not park the spool forever. |
| WiFi cell `kbps,visible,total,band,SSID` every ~60 s | `report_wifi` | The dashboard shows what the device is on and how fast it uploads. |
| The speed shown is only the one measured on the current network | `note_kbps`, `report_wifi` | One network's number must never sit beside another's name. |
| Missing tools reported, then installed once per boot in the background | `check_tools`, `install_tools` | The fight never waits on apt; tool names map to real Debian package names. |
| Old `aasw.sh` still running is reported | `main` | Two WiFi authorities fight. |

## Safety and hygiene

| Capability | Function(s) | Why |
| --- | --- | --- |
| Conf accepted only if root-owned and not group/world accessible; refusal is printed, never silent | conf block | The conf carries hotspot passwords. |
| Every numeric knob validated (non-zero, up to 7 digits, octal-safe); bad values fall back to defaults | conf block | A typo must not crash the daemon into a respawn loop. |
| Runtime files under a private root-only `/run/awacs` | `RUN_DIR` | Shared `/tmp` allows name squatting; SSID lists are location data. |
| `umask 077` | top of file | Every runtime file lands root-only. |
| Passwords never in argv (wpa: stdin; NM: 0600 keyfile) | `try_safety`, `nm_add_crutch` | `/proc/PID/cmdline` is world-readable. |
| `DEVICE_ID` validated to a plain slug | `device_id` | Its bytes land in a URL and a root terminal. |
| Optional stealth: drop ICMP echo on the interface, stop avahi | `enable_stealth` | Lower LAN visibility when wanted. |
| Graceful shutdown re-enables all networks before exiting | `on_shutdown` | A Ctrl+C mid-fight must hand the supplicant back its autonomy. |

## Toolbox

| Word | Function | What it shows |
| --- | --- | --- |
| `status` | `cli` | device, backend, daemon pid, network, signal, ip, gateway, internet, viewer, passive upload |
| `networks` | `cli` | stored networks (id/uuid, name, priority, flags, source) and the visible subset |
| `evaluate` | `cli` | visible networks strongest first with stored id, priority, security; stored-but-invisible tail |
| `scan` | `cli`, `scan` | raw TSV `ssid<TAB>signal<TAB>open|sec` |
| `speed` | `cli`, `up_kbps` | one real upload probe |
| `check` | `cli`, `have_net` | `internet: OK` / `internet: DOWN` with exit code; no root needed |
| `help` | `cli` | the word list |

Known limits are listed in [faq.md](faq.md).
