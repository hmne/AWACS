# AWACS

[![ShellCheck](https://github.com/hmne/AWACS/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/hmne/AWACS/actions/workflows/shellcheck.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

AWACS (Advanced WiFi Auto Connection System) is a single bash daemon that keeps a headless Linux device on the internet over WiFi. It checks the link every ten seconds, and when the internet is gone it works through the stored networks, an emergency list and open networks until one delivers. It never edits the system's own network files.

[العربية](README.ar.md) · [Documentation](docs/en/) · [Changelog](CHANGELOG.md)

## Who it is for

A device nobody sits in front of: a Raspberry Pi camera, a sensor box, a kiosk, any Debian-like machine that must stay reachable over WiFi. If the box loses the internet at 3 a.m., AWACS is what gets it back.

## Two backends, one script

AWACS detects the network stack at start (`detect_backend`) and drives it through that stack's own tool only:

| Image | Backend | Tool | Role |
| --- | --- | --- | --- |
| Legacy Raspberry Pi OS (dhcpcd + wpa_supplicant) | `wpa` | `wpa_cli` | AWACS is the WiFi brain |
| NetworkManager images (Bookworm default, most Debian desktops) | `nm` | `nmcli` | AWACS supervises NetworkManager: it waits out NM's own retries and intervenes only after NM has provably given up |

If NetworkManager is enabled or active, the image is an NM image. If `nmcli` is missing or the interface is unmanaged, AWACS runs in monitor-only mode and says so in the log.

## Core ideas

- **Fight until connected.** Three ticks without internet start a fight: reassociate, try every visible stored network, run a three-rung recovery ladder (radio, network service, WiFi firmware), then emergency networks, then open networks.
- **Upload decides, not signal.** When several networks work, AWACS uploads a 200 KB probe through each and keeps the fastest (`best_by_upload`). A challenger must beat the current network by a configurable margin before a switch happens. Without a probe target it falls back to signal order.
- **No-block law.** Zero `save_config`, zero `disable_network`, zero `nmcli connection modify`. The only networks AWACS removes are the temporary ones it created this boot. Every fight start, win, loss and shutdown re-enables all stored networks.
- **Reboot valve for the device's own wedge only.** A reboot needs a known network on the air that the device provably cannot ride, no gateway, no wrong-password signature, and the condition persisting for `REBOOT_AFTER_MIN` minutes. A wrong password or an ISP outage never reboots the box.
- **Patience with external outages.** If the gateway answers, the problem is upstream. AWACS logs `outage looks external — waiting, not rebooting` and waits.
- **Last resorts.** `SAFETY_NET` networks (your phone hotspot, with password) are tried before any open stranger. Both live as temporary entries and are retired the moment a real network returns.
- **Day and night profiles.** Slower links are tolerated and switching is rarer between `NIGHT_START` and `NIGHT_END`.
- **Installs its own tools.** A missing `iw`, `nmcli`, `rfkill` or similar is reported, then installed once per boot with the right Debian package names, in the background, after the first proven-healthy moment.
- **Spooled story.** With a reporting site configured, every event is logged locally and sent to the site. Lines that cannot be sent during an outage are spooled and delivered in order after recovery, first line pinned so the outage's start time survives.

## Quick install

Wizard (language, missing tools, device id, log target and site, emergency networks, boot method):

```sh
curl -fsSL https://raw.githubusercontent.com/hmne/AWACS/main/install.sh | sudo bash
# unattended: ... | sudo bash -s -- --yes --device-id cam1 --log local
```

Manual:

```sh
sudo install -m 755 awacs.sh /usr/local/bin/awacs.sh
sudo install -m 600 -o root -g root awacs.conf.example /etc/awacs.conf
sudo nano /etc/awacs.conf           # emergency networks, site URL, anything else you want to change
```

Then start it from systemd or `rc.local` with `DEVICE_ID` in the environment:

```sh
# /etc/rc.local, before anything that needs the network
export DEVICE_ID="cam1"
( while :; do /usr/local/bin/awacs.sh; sleep 10; done ) >/dev/null 2>&1 &
```

The systemd unit is `systemd/awacs.service` (`Restart=always` is the loop). Verify with `sudo awacs.sh status`. Upgrade, uninstall and the unattended flags are in [docs/en/install.md](docs/en/install.md).

## Toolbox

The same file is a toolbox. These words run beside the daemon and are read-only except `speed`:

```text
sudo awacs.sh status     # live network + daemon state
sudo awacs.sh networks   # stored vs visible networks
sudo awacs.sh evaluate   # ranked table: CUR ID PRIO SIGNAL SEC SSID
sudo awacs.sh scan       # raw scan, cached 30 s
sudo awacs.sh speed      # one real upload probe to the site
awacs.sh check           # "internet: OK" exit 0 / "internet: DOWN" exit 1 — no root needed
awacs.sh help
```

`status` on a connected box:

```text
  device      cam1 on wlan0
  backend     wpa / نظام إدارة الشبكة
  daemon    ✓ running (pid 637) / الحارس يعمل
  network     HomeNet
  signal      -20 dBm / قوة الإشارة
  ip          10.10.1.18/24
  gateway   ✓ reachable / الراوتر يرد
  internet  ✓ ONLINE / متصل
  viewer      none / لا مشاهد
  upload      0 kbps flowing (3s kernel sample)
```

`evaluate`:

```text
CUR  ID       PRIO  SIGNAL   SEC   SSID
              -     -20      open  FreeCafe
*    0        10    -20      sec   HomeNet
     1        5     -27      sec   شبكة البيت
```

Arabic and other non-ASCII network names are decoded for display and matched byte-exactly inside.

## Configuration

One file: `/etc/awacs.conf`, owned by root, mode `0600`, plain `KEY=value` lines. The script refuses a file with any other owner or mode and prints why. Every number is validated; a bad value falls back to the default instead of crashing the daemon. All knobs with defaults are in [awacs.conf.example](awacs.conf.example) and explained in [docs/en/configuration.md](docs/en/configuration.md).

The public-edition knobs:

```text
SITE_URL=""          # base URL of a reporting site; empty = local-only operation
LOG_TARGET="local"   # local | both | remote
PROBE_URL=""         # upload-probe target; defaults to the site when SITE_URL is set
REPORT_WIFI="auto"   # publish the WiFi cell to the site; auto = on when SITE_URL is set
SITE_TZ=""           # time zone of the site log stamps, e.g. Europe/Berlin; empty = the device's zone
```

With no site the daemon runs in signal mode: it supervises connectivity, rides the strongest working stored network when the internet is lost, and does no upload measurement.

`DEVICE_ID` comes from the environment (`rc.local` export or systemd `Environment=`). The log lives in `/var/log/awacs.log`, rotated at `LOG_CAP` lines. Runtime state lives in `/run/awacs`, root-only, gone at reboot.

## Documentation

| Page | Contents |
| --- | --- |
| [features.md](docs/en/features.md) | every capability, the function that implements it, and why |
| [how-it-works.md](docs/en/how-it-works.md) | main loop, fight ladder, ME-vs-external classification, reboot valve, NM deference, spool, scan sources |
| [configuration.md](docs/en/configuration.md) | every knob with default, unit, effect and safe range; conf security rules; deployment shapes |
| [scenarios.md](docs/en/scenarios.md) | what stock wpa_supplicant or NetworkManager does versus what AWACS does, with real log lines |
| [install.md](docs/en/install.md) | wizard, manual install, systemd vs rc.local, upgrade, uninstall |
| [troubleshooting.md](docs/en/troubleshooting.md) | failure signatures from the log and what each means |
| [faq.md](docs/en/faq.md) | short answers |
| [integration.md](docs/en/integration.md) | the device_api contract, the shipped receiver, the site cell |
| [testing.md](docs/en/testing.md) | the QEMU/hwsim lab and how to reproduce it |

## Repository layout

| Path | Contents |
| --- | --- |
| `awacs.sh` | the daemon and toolbox, one file |
| `awacs.conf.example` | every knob with its default, commented out |
| `install.sh` | the setup wizard: install, update, uninstall; `--yes` for unattended runs |
| `systemd/` | `awacs.service` and its notes |
| `server/` | two self-hosted receivers for the device_api contract, PHP and Python |
| `tools/` | `awacs-tui.sh`, a read-only terminal dashboard; `gen-config-table.sh`, a knob table generated from the code |
| `docs/en/`, `docs/ar/` | the documentation, same pages in both languages |
| `lab/` | the QEMU/hwsim lab: controller, guest files, scenarios |

## Status

Version 1.0. Exercised against real wpa_supplicant, dhcpcd, NetworkManager and hostapd in a QEMU lab with virtual radios: 24 scenario runs on two images, owner network files byte-identical before and after every run. Details in [docs/en/testing.md](docs/en/testing.md). The lab is a Linux VM, not a Raspberry Pi; the testing page lists what was not verified.

## Requirements

bash 4+, `iw`, `ip`, `ping`, `curl`, `awk`, `sed`, `grep`, `pgrep`, `rfkill`, `flock`, `timeout`, `stat`, `date`, `modprobe`, and `wpa_cli` or `nmcli`. All are stock on Raspberry Pi OS and Debian. `iwlist` and `wget` are optional fallbacks.

## License

MIT. See [LICENSE](LICENSE).
