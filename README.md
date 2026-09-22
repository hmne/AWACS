# AWACS

AWACS (Advanced WiFi Auto Connection System) is one bash script, `awacs.sh`, that runs as a daemon and keeps a headless Linux device on the internet over WiFi. The device it is written for has nobody in front of it: a Raspberry Pi at a remote site, a sensor box, a kiosk. When the internet is lost, the daemon reconnects the device without anyone at the keyboard, and it does so without editing the stored network configuration of the system.

[Arabic](README.ar.md) | [Documentation](docs/en/) | [Changelog](CHANGELOG.md)

## Situations wpa_supplicant and NetworkManager do not handle

Both stacks join a stored network and keep the association alive. Neither checks whether the internet is reachable through it, neither compares networks by throughput, and neither distinguishes a fault on the device from a fault upstream. The situations below leave a headless device offline.

A wrong password on the only network. The stack retries the same network; a watchdog that reboots on lost connectivity reboots in a loop. AWACS reads the refusal, logs `association refused - wrong password? (recovery continues, reboot stays off)`, continues with the other networks and the recovery rungs, and does not reboot for a credential fault.

The home access point goes down, then comes back. The stack stays on whatever it landed on. AWACS falls back to a working stored network (the fastest by measured upload when a probe target exists), then looks every `PREF_CHECK` seconds for a visible stored network of higher priority and returns to it after seeing it twice in a row.

Every stored network is gone. The stack sits disconnected. AWACS joins an emergency network from `SAFETY_NET` (a phone hotspot with its password), and failing that an open network, through a temporary entry that is never written to disk. When a stored network is back, the temporary entry is removed.

The ISP is down while the router is up. The link is fine, so the stack sees nothing wrong; a connectivity watchdog reboots for nothing. AWACS pings the gateway, logs `outage looks external (round N) — waiting, not rebooting`, and waits.

The fault is on the device. The driver or the supplicant is stuck while a stored network is visible. The stack retries forever. AWACS bounces the radio, restarts the network service, reloads the WiFi firmware, and reboots only when a stored network has stayed visible and unreachable for `REBOOT_AFTER_MIN` minutes (30 by default).

The link is slow while a faster stored network is available. The stack chooses by priority and signal and never measures speed. AWACS measures upload by POSTing `PROBE_KB` kilobytes to the site. After `UP_STRIKES` slow samples of real traffic it uploads through each visible stored network and switches only to one that reaches `SWITCH_GAIN_PCT` percent of the current network's measured speed.

## How it works

1. Every `TICK` seconds (10) the daemon checks the internet: a ping to 8.8.8.8, then to 1.1.1.1, then an HTTP 204 from connectivitycheck.gstatic.com, then, when a site is configured, an HTTP 400 from the site endpoint. One rung passing means online. A check that fails while the device is still sending is repeated once in a patient form (three pings per target, 8-second HTTP limits) before it counts as a failure, once per outage.
2. After `NET_FAIL_TICKS` failed checks (3) it logs `internet lost on wlan0 - engaging` and starts recovery: 40 to 63 seconds after the loss on a link whose gateway has gone silent, about 72 to 83 seconds when the router keeps answering and one patient check is spent first. A device that boots without internet starts recovery at once.
3. Recovery opens gently: every stored network is re-enabled, the network stack is asked to reconnect (`wpa_cli reassociate`, or `nmcli device connect` on a device NetworkManager reports disconnected or failed), and an IPv4 lease plus a passed internet check ends recovery. While the gateway still answers, the first recovery of an outage keeps the live association and skips that reconnect; the second one performs it.
4. Otherwise three rounds follow. Each round tries every visible stored network, measured by upload when a probe target exists and in signal order otherwise.
5. Before any teardown the outage is classified. Gateway silent, no lease this round, and a stored network visible (or a radio that hears nothing, or an empty stored list): the fault is on the device. Gateway answering: the outage is external and the daemon waits.
6. On the device-side branch the round runs one recovery rung. L1 bounces the radio; L2 restarts dhcpcd on the wpa backend or reapplies and reconnects the device through nmcli on the nm backend; L3 reloads the brcmfmac firmware, after a NetworkManager restart on the nm backend.
7. A round that has not restored the internet ends with the emergency networks from `SAFETY_NET`, then open networks, each on a temporary entry.
8. A reboot happens only when the device-side evidence has persisted for `REBOOT_AFTER_MIN` minutes. A wrong-password sign resets that timer, and on NetworkManager images the timer runs only after NetworkManager has itself given up.
9. The daemon never calls `save_config` or `disable_network`, never runs `nmcli connection modify`, `delete` or `down` on a stored profile, and never runs `nmcli device wifi connect`. Temporary entries live in the running supplicant or under `/run` and are removed by the next daemon start.
10. With a site configured and `LOG_TARGET` set to `both` or `remote`, every event goes to the site; `both` keeps the full local log, `remote` keeps only `WARN` and `ERROR` lines in it. Lines that cannot be sent during an outage are spooled and delivered in order after recovery; the first spooled line is kept so the outage's start time survives.

On a NetworkManager image the daemon supervises NetworkManager. While NetworkManager reports the device in a transition (connecting or deactivating) it waits and logs `NM is still trying - waiting it out`. A device NetworkManager reports as connected while the internet is down gets no rung either; the log says `NetworkManager is connected, internet is not (round N) — router-side, no rung` and the round goes on to the emergency networks. A recovery rung runs only when NetworkManager reports the device disconnected, failed or unavailable, or when `nmcli` cannot read the state, and the reboot timer arms only after two disconnected or failed readings in a row. If `nmcli` is missing or the interface is unmanaged, the daemon monitors only and says so in the log.

## Requirements

Debian-family Linux: Raspberry Pi OS with dhcpcd and wpa_supplicant, Raspberry Pi OS Bookworm and other NetworkManager images, Debian derivatives with `apt`. bash 4 or later. The tools `iw`, `ip`, `ping`, `curl`, `awk`, `sed`, `grep`, `pgrep`, `rfkill`, `flock`, `timeout`, `stat`, `date`, `modprobe`, and `wpa_cli` or `nmcli`; all are stock on Raspberry Pi OS and Debian. `iwlist` and `wget` are optional fallbacks. The daemon runs as root. Nothing is installed on the device beyond these tools: a missing tool is reported in the log and installed once per boot in the background with `apt-get`; without `apt-get` the log names the missing tools.

## Install

The wizard downloads `awacs.sh`, verifies it against `SHA256SUMS`, and asks for language, missing tools, device id (default: the short hostname), log target and site, emergency networks and boot method:

```sh
curl -fsSL https://raw.githubusercontent.com/hmne/AWACS/main/install.sh | sudo bash
```

Unattended:

```sh
curl -fsSL https://raw.githubusercontent.com/hmne/AWACS/main/install.sh | sudo bash -s -- --yes --device-id mydevice --log local
```

From a clone, `sudo ./install.sh` installs the local `awacs.sh` instead of downloading it. Manual install:

```sh
sudo install -m 755 awacs.sh /usr/local/bin/awacs.sh
sudo install -m 600 -o root -g root awacs.conf.example /etc/awacs.conf
sudo nano /etc/awacs.conf
```

Then start it at boot by one of two methods, never both: a second launcher's instance loses the single-instance lock and exits every ten seconds. The systemd unit is `systemd/awacs.service`; it needs a drop-in with the device id:

```sh
sudo install -m 644 systemd/awacs.service /etc/systemd/system/awacs.service
sudo mkdir -p /etc/systemd/system/awacs.service.d
printf '[Service]\nEnvironment=DEVICE_ID=mydevice\n' | sudo tee /etc/systemd/system/awacs.service.d/10-device-id.conf
sudo systemctl daemon-reload
sudo systemctl enable --now awacs
```

The `rc.local` method is two lines placed before anything that needs the network:

```sh
export DEVICE_ID="mydevice"
( while :; do /usr/local/bin/awacs.sh; sleep 10; done ) >/dev/null 2>&1 &
```

Verify with `sudo awacs.sh status`: the daemon line shows a pid, the internet line shows ONLINE. The first line in `/var/log/awacs.log` carries `AWACS 1.0 starting on wlan0 (device mydevice)`, followed by a `reporting:` line with the applied reporting knobs. With `LOG_TARGET` set to `both` or `remote`, the site's `log/log.txt` receives a start line and `tmp/wifi.tmp` appears within a minute. Upgrade, uninstall and every wizard option are in [docs/en/install.md](docs/en/install.md).

## Configuration

One file, `/etc/awacs.conf`, owned by root with mode `0600` and plain `KEY=value` lines. The script refuses a file that is not owned by root or that group or others can read or write, and prints why. Every number is validated; a bad value falls back to the default instead of stopping the daemon. The daemon reads the file at start, so restart it after an edit (`sudo systemctl restart awacs`; under `rc.local`, send TERM to the pid shown by `status` and the loop respawns the daemon within ten seconds).

The reporting knobs:

```text
SITE_URL=""              # base URL of a reporting site; empty = local-only operation
SITE_API="receiver.php"  # endpoint file name under SITE_URL/DEVICE_ID/; the shipped receiver's name
LOG_TARGET="local"       # local | both | remote; both and remote need SITE_URL
PROBE_URL=""             # upload-probe target; empty = the site endpoint when SITE_URL is set
REPORT_WIFI="auto"       # WiFi cell to the site; auto = on when SITE_URL is set and LOG_TARGET is both or remote
SITE_TZ=""               # time zone of the site log stamps, e.g. Europe/Berlin; empty = the device's zone
LOG_LANG="en"            # language of the local log's story lines: en | ar
SITE_LANG="en"           # language of the lines sent to the site: en | ar
```

With no site and no probe target the daemon runs in signal mode: it supervises connectivity, joins the strongest working stored network when the internet is lost, and does no upload measurement and no switching.

`DEVICE_ID` comes from the environment (the `rc.local` export or the systemd drop-in), not from the file. The log is `/var/log/awacs.log`, rotated to `LOG_CAP` lines. Runtime state lives in `/run/awacs`, root-only, gone at reboot. Every knob with its default is in [awacs.conf.example](awacs.conf.example); the full table with ranges and effects is in [docs/en/configuration.md](docs/en/configuration.md).

## Commands

The same file is a toolbox. These words run beside the daemon and are read-only except `speed`; the labels they print are bilingual.

| Command | Root | Output |
| --- | --- | --- |
| `sudo awacs.sh status` | yes | device, backend, daemon pid, network, signal, address, gateway, internet, viewer, current upload rate |
| `sudo awacs.sh networks` | yes | stored networks, and which of them are visible now |
| `sudo awacs.sh evaluate` | yes | visible networks ranked by signal: current mark, id, priority, signal, security, name |
| `sudo awacs.sh scan` | yes | the raw scan, cached for `SCAN_TTL` seconds |
| `sudo awacs.sh speed` | yes | one real upload probe to the probe target |
| `awacs.sh check` | no | `internet: OK` with exit 0, or `internet: DOWN` with exit 1 |
| `awacs.sh help` | no | the command list |

Non-ASCII network names are decoded for display and matched byte-exactly inside.

## Documentation

| Page | Contents |
| --- | --- |
| [features.md](docs/en/features.md) | every behaviour with its knob and log line |
| [how-it-works.md](docs/en/how-it-works.md) | main loop, recovery order, on-device versus external outage, reboot condition, NetworkManager supervision, spool, scan sources |
| [configuration.md](docs/en/configuration.md) | every knob with default, unit, effect and range; the file's rules; deployment shapes |
| [scenarios.md](docs/en/scenarios.md) | what the stock stack does versus what AWACS does, with sample log lines |
| [install.md](docs/en/install.md) | wizard, manual install, systemd versus rc.local, upgrade, uninstall |
| [integration.md](docs/en/integration.md) | the endpoint contract, the shipped receivers, the WiFi cell |
| [troubleshooting.md](docs/en/troubleshooting.md) | log lines and what each means |
| [faq.md](docs/en/faq.md) | short answers |

## Dashboard and receivers

`tools/awacs-tui.sh` is a read-only terminal dashboard: run it on the device with `sudo`, it needs bash 5, and it takes `--plain`, `--once`, `--lang en|ar` and `--interval N`. `server/receiver.php` (PHP 7.4 or later) and `server/receiver.py` (Python 3, standard library) are two self-hosted receivers for the endpoint contract; both are described in [server/README.md](server/README.md).

## Limitations

- WiFi only: there is no Ethernet fallback, and a connection counts only with an IPv4 lease. IPv6-only networks are not supported.
- A ping that succeeds while DNS is dead reads as online.
- Live-stream detection matches only `raspistill` processes with `live_raw`, `preview.jpg` or `capture.jpg` in their command line and `curl` processes with `upfile=@`; other workloads are not detected.
- Rung L3 reloads the `brcmfmac` module unconditionally; on other WiFi chips that rung does nothing.
- The reboot cannot be switched off, only delayed: `REBOOT_AFTER_MIN` rejects 0.
- The once-per-boot background `apt-get` install of missing tools has no off switch.
- Open networks are joined as a last resort by default (`OPEN_NETWORKS="yes"`).
- Site log lines carry an Arabic message where the program has one; the local log is English.
- wpa backend only: open networks with non-ASCII names are skipped, and stored names containing a backslash, a double quote, a tab, a newline, an escape byte or an edge space never match visibility.
- nm backend: a hidden stored profile must already carry `802-11-wireless.hidden=yes`, and NetworkManager device state 20 (unavailable) never starts the reboot timer.
- Not tested: captive portals, a real ISP outage, IPv6.

## License

MIT. See [LICENSE](LICENSE).
