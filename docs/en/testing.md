# Testing

Two layers: a sandbox harness for fast decision tests, and a real-stack lab in QEMU.

## The sandbox idea

The script exposes two hooks for testing its decisions without a radio: `AWACS_TEST_KBPS` makes `up_kbps` and `tx_kbps` return a fixed number, and `AWACS_TEST_SCAN` makes `scan` serve whatever is in the scan cache without touching the radio. `AWACS_CONF` points at a test conf and `AWACS_IF` at any interface name. With thin shims in front of `wpa_cli` and `nmcli` that record their argv and answer from canned tables, the fight, the classification and the no-block law can be driven through hundreds of scripted moments in seconds. Every earlier round of AWACS was tested this way; the shims from the lab (`lab/guest/wpa_cli-shim.sh`, `lab/guest/nmcli-shim.sh`) are the starting point.

What the sandbox cannot tell you: whether `iw` returns busy under a real supplicant, how long NM takes to settle, whether a rung actually cures anything. That is what the lab is for.

## The lab

`lab/` in this repository is a controller (`lab.sh`) that builds a Debian 12 virtual machine per profile under QEMU with five `mac80211_hwsim` radios:

| Radio | Where | Role |
| --- | --- | --- |
| wlan0 | root namespace | AWACS's station: dhcpcd + wpa_supplicant on the **legacy** profile, NetworkManager on the **nm** profile |
| wlan1 | namespace `ap` | hostapd `HomeNet`, WPA2, priority 10 |
| wlan2 | namespace `ap` | hostapd `شبكة البيت` (Arabic SSID), WPA2, priority 5 |
| wlan3 | namespace `ap` | hostapd `FreeCafe`, open, not stored anywhere |
| wlan4 | namespace `ap` | hostapd `LabHotspot`, WPA2, the conf's `SAFETY_NET` entry, normally off |

Each AP has its own dnsmasq. The `ap` namespace NATs its clients to the VM's user-mode NIC, so a WiFi client gets real internet (apt works over it). The root namespace has no default route of its own: the only way out is wlan0's lease. Cut the WiFi and the internet is gone, exactly like a real board.

A copy of the receiving site runs inside the VM, reachable only over WiFi, so the spool, the WiFi cell and the upload probe are exercised end to end. `awacs.sh` is installed as on a real device (`/usr/local/bin`, `/etc/awacs.conf` root 0600, the respawn loop as a systemd unit, `DEVICE_ID=cam1`). Two thin recorders sit in front of `wpa_cli` and `nmcli`; they log every argv and `exec` the real tool. The no-block proofs read those logs; the script under test is byte-verified by sha256 inside the VM.

Lab conf, identical on both profiles: `PREF_CHECK=60`, `REBOOT_AFTER_MIN=4`, `DANCE_COOLDOWN=120`, `NIGHT_MODE="no"`, `SAFETY_NET["LabHotspot"]="hotspot-pass-2026"`. Everything else is the script's default.

### Scenarios

| # | Scenario | What it proves |
| --- | --- | --- |
| 01 | boot and connect | start line, backend verdict, priority-10 network, boot story on the site, WiFi cell |
| 02 | AP1 down → AP2 → home | fallback, measured candidate, preferred-network return |
| 03 | wrong PSK | auth verdict, ladder runs, no reboot, heals on the right PSK |
| 04 | open fallback → safety net → home | order of last resorts, crutch in `/run` only, retirement |
| 05 | external outage | external classification, no ladder, spool delivered after recovery |
| 06 | install_tools | `iw` removed and reboot → inventory → apt → back on `PATH` |
| 07 | site cell | QA path on a real trickle, one honest probe, measured speed on the site |
| 08 | CLI words | every toolbox word on both backends, Arabic decoded, exit codes |
| 09 | reboot valve | ME evidence → L1..L3 → valve → reconnect after reboot (nm) |
| 10 | NM backend matrix | missing `nmcli` park and respawn, unmanaged interface, negative priority, `-w 5` |
| 11 | NM crutch reap | kill on a crutch, respawn reaps, online again |
| 12 | NM unreachable valve | NM masked, `nmcli` exit 8, L3 spent → valve |
| 13 | hidden network | runtime `scan_ssid` (wpa) / `hidden=yes` profile (NM), re-found, preferred return to a hidden home |
| 14 | reboot valve, two wedges | MAC-ACL refusal reads as credentials (no reboot); a deaf radio (`hwsim` group) reaches the valve, one reboot, boot story once |
| 15 | night profile | night floor, one evaluation on a real trickle, cooldown holds, day transition once |
| 16 | stream law | a healthy stream is never touched; a starving one gets one honest probe, no switch |
| 17 | spool head-pin | first line pinned across roll-overs, ordered delivery, no duplicates |
| 18 | toolbox on a full air | every word with a live temporary network + hidden + Arabic; boxes byte-compared to the original |
| 19 | true DHCP death | dhcpcd keeps the lease then falls to link-local: external verdict, no reboot, recovery |
| 20 | graceful stop | `systemctl stop` ×3: GRACEFUL box in the journal, `enable_all` inside the handler, no SIGKILL; `kill -INT`; respawn |
| 21 | local-only mode | signal mode announce, zero site traffic, no QA without a probe, signal-mode connect, preferred return without veto, downgrade WARN, remote-only local file |
| 22 | deaf cache drop | third empty scan drops the stale picture once; empty cache served; CLI shows nothing visible; streak ends when the radio hears again |

Every scenario ends with the same two checks: the owner's network files byte-identical before and after (`wpa_supplicant.conf`; NM keyfiles plus the profile list), and the argv log free of `save_config` / `disable_network` (wpa) or of any modify/delete/down against an owner profile and any `device wifi connect` (NM).

### Results of the first full pass (2026-09-12/13)

202 PASS / 12 FAIL / 3 NOT-RUN across 24 scenario runs (12 per profile). Every FAIL line is classified in `lab/LAB-REPORT.md`: nine are the lab's own check bugs or environment artifacts, two are a scenario design flaw (on dhcpcd, a dead DHCP server is not an outage because the lease is kept), one is an ordering note. No FAIL points at AWACS after the two fixes the lab found:

- **A1** `iw scan` answers `Device or resource busy` whenever the supplicant or NM is mid-scan; 77 of 107 legacy daemon scans fell back to a stale cache. Fixed by reading the backend's own scan table on busy.
- **A2** On NM, a recovery rung fired five seconds after NM's own autoconnect had succeeded, and L1's `nmcli radio wifi off` switched off every radio in the VM. Fixed by re-checking NM at every rung boundary and bouncing only the interface's own rfkill switch.

Hundreds of real `wpa_cli` and `nmcli` calls were recorded: zero `save_config`, zero `disable_network`, zero modify/delete/down against an owner profile, no `device wifi connect`, every `device connect` with `-w 5`.

### Not verified by the lab

- The Raspberry Pi's `brcmfmac` driver: the lab radio is `mac80211_hwsim`. Busy scans were constant there and may be rarer on a real board; scan timing and roaming differ.
- Wall-clock durations: the VMs run without KVM (TCG), 3–5× slower. `ASSOC_WAIT`, `PREF_CHECK` and `REBOOT_AFTER_MIN` were exercised for order, not for their real lengths.
- A cycling NM never ripening the clock through a full fight; the exact 4-minute arithmetic of the nm valve (only the terminal outcomes were observed).
- Hidden `SAFETY_NET` networks, captive portals, a real ISP, IPv6.
- A real board. The lab is a rehearsal; a spare Raspberry Pi remains the gold standard.

## Reproducing

Inside WSL Ubuntu or any Linux with QEMU (the controller re-executes itself under WSL when started from Git Bash):

```sh
cd lab
bash lab.sh deps                 # QEMU (rootless unpack), Debian cloud image + checksum
bash lab.sh up legacy            # first boot: cloud-init installs packages, reboots into the lab
bash lab.sh up nm
bash lab.sh scenario legacy all  # evidence -> lab/evidence/legacy/<scenario>/
bash lab.sh scenario nm all
bash lab.sh ssh nm '/opt/lab/apctl.sh status'    # drive the access points by hand
bash lab.sh console legacy                       # serial console
```

Each scenario leaves `RESULT.txt` (one PASS/FAIL/NOTE line per check), the daemon log, the site log, the spool, the argv log, and before/after snapshots of the owner's network files. `lab/evidence/TABLE.md` is regenerated from the RESULT files.

Without KVM a first boot takes about 25 minutes and a full 12-scenario pass about two hours per profile. With KVM (`qemu-system-x86` from the distro and membership in the `kvm` group, then `-accel kvm` in `lab.sh`) it is roughly ten times faster.

## Static checks

Every shell script in the repository must pass `shellcheck -x` with zero findings and `bash -n`. The CI workflow in `.github/workflows/shellcheck.yml` runs both on every push, rejects CRLF line endings, runs `install.sh --selftest` (every wizard string present in both languages), checks that `install.sh --print-unit` matches `systemd/awacs.service`, and parses both receivers (`php -l`, `python3 -m py_compile`).
