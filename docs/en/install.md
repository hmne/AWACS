# Install

AWACS is one file, `awacs.sh`, plus one optional conf file. It needs root, bash 4 or later, and the stock tools of Raspberry Pi OS or Debian.

## The wizard

```sh
curl -fsSL https://raw.githubusercontent.com/hmne/AWACS/main/install.sh | sudo bash
```

Or from a clone: `sudo ./install.sh`. The wizard uses `whiptail` menus when it is present (stock on Raspberry Pi OS) and plain prompts otherwise. It walks through nine steps:

1. **Language** — English or Arabic for the wizard's own text. The script's log is bilingual regardless: English in the local file, Arabic on the site.
2. **Missing tools** — the backend's tool list is checked; missing Debian packages are shown and installed with `apt-get` only after you agree.
3. **Device id** — a short slug (`[A-Za-z0-9_-]`, up to 32 characters), default `cam1`. It names the device on the site and in the start-up log line.
4. **Log target** — `local` (the file only), `both` (file and site), or `remote` (site, with only WARN/ERROR kept locally). `both` and `remote` ask for the site URL and check that `${SITE_URL}/${DEVICE_ID}/device_api.php` answers `400`.
5. **Emergency networks** — `SAFETY_NET` entries, SSID and password, as many as you want. The password is asked in a password box and lands only in the root-only conf.
6. **Boot method** — the systemd unit (default when `systemctl` exists) or a line in `/etc/rc.local`. One method only; a re-run that changes the method removes the other. If an old `aasw.sh` is found, the wizard offers to disable it.
7. **Install** — `awacs.sh` to `/usr/local/bin/awacs.sh` (mode 755), sha256-verified against `SHA256SUMS` when downloaded.
8. **Check** — `awacs.sh check`.
9. **Summary** — what was written, where.

`/etc/awacs.conf` is written root:root 0600 with plain `KEY=value` lines holding only the values you chose. The wizard never edits `/etc/wpa_supplicant/wpa_supplicant.conf` or a NetworkManager profile.

Unattended and dry runs:

```sh
sudo ./install.sh --yes --device-id cam1 --log local                      # defaults, no questions
sudo ./install.sh --yes --device-id cam2 --log both --site https://example.com/cams \
                  --safety 'MyPhone=hotspot-password' --service systemd
sudo ./install.sh --dry-run                                               # print every action, change nothing
curl -fsSL https://raw.githubusercontent.com/hmne/AWACS/main/install.sh | sudo bash -s -- --yes --device-id cam1
```

Options: `--lang en|ar`, `--device-id ID`, `--log local|both|remote`, `--site URL`, `--probe URL`, `--report-wifi auto|yes|no`, `--safety 'SSID=password'` (repeatable), `--no-safety`, `--service systemd|rc.local`, `--release-url URL`, `--yes`, `--dry-run`, `--uninstall [--purge]`, `--help`.

## Manual install

```sh
sudo install -m 755 awacs.sh /usr/local/bin/awacs.sh
sudo install -m 600 -o root -g root awacs.conf.example /etc/awacs.conf
sudo nano /etc/awacs.conf
```

In the conf, uncomment and set what you need. Typical minimum:

```sh
SITE_URL="https://example.com/cams"        # or leave empty for local-only
LOG_TARGET="both"
SAFETY_NET["MyPhoneHotspot"]="hotspot-password"
```

### systemd

The unit is `systemd/awacs.service` in the repository:

```ini
[Unit]
Description=AWACS - WiFi autonomy daemon
After=network-pre.target NetworkManager.service dhcpcd.service
StartLimitIntervalSec=0

[Service]
Type=simple
Environment=DEVICE_ID=cam1
ExecStart=/usr/local/bin/awacs.sh
Restart=always
RestartSec=10
TimeoutStopSec=40

[Install]
WantedBy=multi-user.target
```

```sh
sudo install -m 644 systemd/awacs.service /etc/systemd/system/awacs.service
sudo mkdir -p /etc/systemd/system/awacs.service.d
printf '[Service]\nEnvironment=DEVICE_ID=cam1\n' | sudo tee /etc/systemd/system/awacs.service.d/10-device-id.conf
sudo systemctl daemon-reload
sudo systemctl enable --now awacs
```

`Restart=always` plus `RestartSec=10` is the `rc.local` loop written as a unit. The daemon exits 0 on purpose in two cases and expects to be started again: when it loses the single-instance lock, and when a NetworkManager image that lacked `nmcli` has just had it installed. `StartLimitIntervalSec=0` keeps systemd from giving up after a burst of such exits. The unit starts after `network-pre.target`, not behind `network-online.target`: the daemon's job is to make the network work. `TimeoutStopSec=40` leaves room for the `nmcli -w 5` inside the shutdown handler. Details in `systemd/README.md`.

### rc.local

Add the two lines before anything that needs the network. Order matters: the `DEVICE_ID` export must come first.

```sh
export DEVICE_ID="cam1"
( while :; do /usr/local/bin/awacs.sh; sleep 10; done ) >/dev/null 2>&1 &
```

If an older `aasw.sh` line exists, delete it and remove `/usr/local/bin/aasw.sh`. Two WiFi authorities fight each other; AWACS logs a warning if it sees the old one running.

## Verify

```sh
awacs.sh check              # internet: OK  (exit 0)  — no root needed
sudo awacs.sh status
sudo awacs.sh networks
sudo tail -f /var/log/awacs.log
```

The first log lines on a healthy box:

```text
[INFO][12/09 17:37:04] AWACS 1.0 starting on wlan0 (device cam1)
```

and on a NetworkManager image also:

```text
[INFO][12/09 17:43:36] NetworkManager backend - AWACS supervises it (full capability)
```

`status` should show the daemon running with its pid and `internet ONLINE`. With a site configured, its log receives `[INFO] AWACS: أواكس 1.0 بدأ العمل على wlan0, …` and `tmp/wifi.tmp` appears within a minute. `tools/awacs-tui.sh` is a read-only terminal dashboard that shows the same facts, redrawn every two seconds.

The no-block law can be checked by hand: `sudo md5sum /etc/wpa_supplicant/wpa_supplicant.conf` (or `ls -l /etc/NetworkManager/system-connections`) before install, after a reboot, and after a day. Nothing changes.

## systemd versus rc.local

| | systemd | rc.local |
| --- | --- | --- |
| Restart on exit | `Restart=always`, `RestartSec=10`, no start limit | the `while :; do …; sleep 10; done` loop |
| Logs of the launcher itself | `journalctl -u awacs` (start/stop events only; the daemon logs to its file) | none (`>/dev/null`) |
| Start order | after `network-pre.target`, `NetworkManager.service`, `dhcpcd.service`; the daemon itself waits up to 60 s for NetworkManager on NM images | runs when `rc.local` runs, usually before the network is up — that is fine, AWACS fights from the first second |
| `DEVICE_ID` | drop-in `awacs.service.d/10-device-id.conf` | the `export` line |
| Stop | `systemctl stop awacs` (SIGTERM → `enable_all` → exit 0) | `kill $(head -1 /run/awacs/lock)` (the loop respawns it in 10 s; comment out the line first) |

Both are supported. Use systemd when the image has it. Never both: a second copy loses the daemon's lock and exits every ten seconds for nothing.

## Upgrading

Re-running the wizard updates what is there: `sudo ./install.sh` (or the one-liner) replaces the binary, keeps the conf, and restarts the daemon. By hand:

```sh
sudo install -m 755 awacs.sh /usr/local/bin/awacs.sh
sudo systemctl restart awacs                 # systemd
sudo kill "$(head -1 /run/awacs/lock)"       # rc.local: the loop restarts it within 10 s
```

The daemon's shutdown handler re-enables every stored network before it exits, so a restart never leaves the supplicant narrowed. Check `sudo awacs.sh status` afterwards; the log shows a fresh `AWACS … starting` line.

## Uninstall

```sh
sudo ./install.sh --uninstall            # remove service/rc.local line + binary; keep settings and log
sudo ./install.sh --uninstall --purge    # ... and remove /etc/awacs.conf and /var/log/awacs.log too
```

By hand:

```sh
sudo systemctl disable --now awacs && sudo rm -rf /etc/systemd/system/awacs.service /etc/systemd/system/awacs.service.d && sudo systemctl daemon-reload
# or: remove the two lines from /etc/rc.local, then kill "$(head -1 /run/awacs/lock)"
sudo rm -f /usr/local/bin/awacs.sh
sudo rm -f /etc/awacs.conf             # holds hotspot passwords — remove it deliberately
sudo rm -f /var/log/awacs.log
```

Nothing else to clean:

- `/run/awacs` and any `awacs-*` keyfile under `/run/NetworkManager/system-connections` are tmpfs and vanish at reboot. To remove them now: `sudo rm -rf /run/awacs; sudo rm -f /run/NetworkManager/system-connections/awacs-*.nmconnection; sudo nmcli connection reload`.
- On the wpa backend a temporary network lives only in the live supplicant; `sudo wpa_cli -i wlan0 reconfigure` or a reboot drops it.
- The stealth rule (if enabled) is a runtime `iptables` rule; `avahi-daemon` was stopped, not disabled. Both revert at reboot.
- Your `wpa_supplicant.conf` and NetworkManager profiles were never written to. There is nothing to restore.

## Files after install

| Path | Owner/mode | Contents |
| --- | --- | --- |
| `/usr/local/bin/awacs.sh` | root 0755 | the daemon and toolbox |
| `/etc/awacs.conf` | root 0600 | your settings, including hotspot passwords |
| `/var/log/awacs.log` | root 0600 | the local log, rotated at `LOG_CAP` lines |
| `/run/awacs/` | root 0700 | lock, scan cache, spool, temporary-network marker, once-per-boot apt marker |
| `/etc/systemd/system/awacs.service` + `awacs.service.d/10-device-id.conf`, or a marked block in `/etc/rc.local` | root | the launcher |
