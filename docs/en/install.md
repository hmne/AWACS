# Install

AWACS is one script, `awacs.sh`, plus one optional settings file, `/etc/awacs.conf`. The wizard `install.sh` puts both in place and sets up a boot method; every step can also be done by hand.

## Requirements

- Root. The daemon and every toolbox word except `check` and `help` need it.
- bash 4 or later for `awacs.sh`; bash 5 for the optional dashboard `tools/awacs-tui.sh`.
- Raspberry Pi OS or another Debian derivative with `apt-get`: a dhcpcd plus wpa_supplicant image (backend `wpa`) or a NetworkManager image (backend `nm`). Without `apt-get` the wizard only reports missing tools and the daemon logs `no apt-get on this system - install manually:` followed by the tool names.
- Tools: `iw`, `ip`, `ping`, `curl`, `awk`, `sed`, `grep`, `pgrep`, `rfkill`, `flock`, `timeout`, `stat`, `date`, `modprobe`, and `wpa_cli` or `nmcli` depending on the backend; `iwlist` and `wget` are optional fallbacks. The wizard installs missing tools from the Debian packages `iw`, `iproute2`, `iputils-ping`, `curl`, `mawk`, `sed`, `grep`, `procps`, `rfkill`, `util-linux`, `coreutils`, `kmod`, and `wpasupplicant` or `network-manager`.
- Outbound access to `8.8.8.8` and `1.1.1.1` (ICMP), to `http://connectivitycheck.gstatic.com` and, when a site is configured, to the site over HTTP or HTTPS. The privileged actions the daemon takes are listed in [SECURITY.md](../../SECURITY.md).

## The wizard

```sh
curl -fsSL https://raw.githubusercontent.com/hmne/AWACS/main/install.sh | sudo bash
```

Or from a clone: `sudo ./install.sh`. The wizard uses `whiptail` menus when present and plain prompts otherwise, and needs a terminal unless `--yes` is given. The one-liner downloads `awacs.sh` and `SHA256SUMS` from the release URL and stops when the checksum does not match; a clone is installed from the local copy, verified against `SHA256SUMS` when that file sits beside it. The steps:

1. Language: English or Arabic for the wizard's own text. The local log is English in either case.
2. Missing tools: the backend's tool list is checked and missing packages are installed with `apt-get` after you agree. If you decline, the daemon makes one attempt by itself once it is online.
3. Device id: letters, digits, `_` and `-`, up to 32 characters. The default is the id of an earlier install, otherwise the short hostname.
4. Log target: `local` (the file only), `both` (file and site) or `remote` (site; the file keeps `WARN`, `ERROR` and the local-only lines); `both` and `remote` ask for the site URL and check that `${SITE_URL}/${DEVICE_ID}/${SITE_API}` answers HTTP 400, offering another URL, the URL as typed or local logging when it does not. Without a site the wizard then asks for an optional probe URL, with a site for the time zone of the site's log stamps.
5. Emergency networks: `SAFETY_NET` entries, name and password, as many as you want. The answers are then written to `/etc/awacs.conf` (root:root, mode 0600).
6. Boot method: the systemd unit (default when `systemctl` exists) or a marked block in `/etc/rc.local`; a re-run that changes the method removes the other. A script named `aasw.sh` is detected here and the wizard offers to disable it.
7. Install and restart: `awacs.sh` goes to `/usr/local/bin/awacs.sh` (root, mode 0755) and the daemon is restarted, under `rc.local` by signalling the running daemon or by starting a loop when none runs.
8. Check: `awacs.sh check` is run and its result shown.
9. Summary: the files written and the commands to watch the daemon.

A re-run updates what is there. The reporting values of an existing `/etc/awacs.conf` become the defaults, its other lines are kept, the managed keys are replaced, and a `SAFETY_NET` entry with the same name is replaced. The wizard never edits `/etc/wpa_supplicant/wpa_supplicant.conf` or a NetworkManager profile.

Unattended and dry runs:

```sh
sudo ./install.sh --yes --device-id mydevice --log local
sudo ./install.sh --yes --device-id mydevice --log both --site https://example.org \
                  --safety 'MyPhone=hotspot-password' --service systemd
sudo ./install.sh --dry-run
curl -fsSL https://raw.githubusercontent.com/hmne/AWACS/main/install.sh | sudo bash -s -- --yes --device-id mydevice
```

`--yes` takes the defaults plus the options given; `--log both` or `--log remote` without `--site` stops unless an existing conf already carries a site URL. `--dry-run` prints every action and changes nothing.

| Option | Meaning |
| --- | --- |
| `--lang en\|ar` | wizard language |
| `--device-id ID` | device id, `[A-Za-z0-9_-]{1,32}` |
| `--log local\|both\|remote` | log target; `both` and `remote` need `--site` under `--yes` |
| `--site URL` | reporting site base URL |
| `--probe URL` | upload-speed probe target |
| `--report-wifi auto\|yes\|no` | publish the WiFi cell to the site |
| `--tz ZONE` | time zone of the site log stamps, e.g. `Europe/Berlin` |
| `--log-lang en\|ar` | Language of the local log's story lines. The wizard asks; the default is the wizard's own language. |
| `--site-lang en\|ar` | Language of the lines sent to the site. Asked only when the log target is `both` or `remote`. |
| `--api NAME` | endpoint file name under `<site>/<device id>/`, default `receiver.php` |
| `--safety 'SSID=password'` | emergency network, repeatable |
| `--no-safety` | skip the emergency-network step |
| `--service systemd\|rc.local` | boot method |
| `--release-url URL` | where `awacs.sh` and `SHA256SUMS` are downloaded from |
| `--yes` | no questions: defaults plus the options above |
| `--dry-run` | print every action, change nothing |
| `--uninstall` | remove the boot method and `awacs.sh`, keep settings and log |
| `--purge` | with `--uninstall`: also remove `/etc/awacs.conf` and the log |
| `--help` | usage text |

## Manual install

```sh
sha256sum -c --ignore-missing SHA256SUMS
sudo install -m 755 awacs.sh /usr/local/bin/awacs.sh
sudo install -m 600 -o root -g root awacs.conf.example /etc/awacs.conf
sudo nano /etc/awacs.conf
```

In the conf, uncomment and set what you need. Typical minimum:

```sh
SITE_URL="https://example.org"        # or leave empty for local-only operation
LOG_TARGET="both"
SAFETY_NET["MyPhoneHotspot"]="hotspot-password"
```

Every knob is described in [configuration.md](configuration.md). Then choose one boot method.

### systemd

The unit is `systemd/awacs.service`:

```ini
[Unit]
Description=AWACS - WiFi autonomy daemon
After=network-pre.target NetworkManager.service dhcpcd.service
StartLimitIntervalSec=0

[Service]
Type=simple
Environment=DEVICE_ID=device1
ExecStart=/usr/local/bin/awacs.sh
Restart=always
RestartSec=10
TimeoutStopSec=40

[Install]
WantedBy=multi-user.target
```

Install it with a drop-in that carries the device id:

```sh
sudo install -m 644 systemd/awacs.service /etc/systemd/system/awacs.service
sudo mkdir -p /etc/systemd/system/awacs.service.d
printf '[Service]\nEnvironment=DEVICE_ID=mydevice\n' | sudo tee /etc/systemd/system/awacs.service.d/10-device-id.conf
sudo systemctl daemon-reload
sudo systemctl enable --now awacs
```

`Restart=always` with `RestartSec=10` is the `rc.local` loop written as a unit. The daemon exits 0 on purpose in two cases and expects to be started again: when it loses the single-instance lock, and when a NetworkManager image that lacked `nmcli` has just had it installed. `StartLimitIntervalSec=0` keeps systemd from giving up after a burst of such exits. The unit starts after `network-pre.target`, not behind `network-online.target`: the daemon's job is to make the network work. `TimeoutStopSec=40` leaves room for the `nmcli -w 5` inside the shutdown handler. `journalctl -u awacs` shows the start and stop events; the daemon itself logs to its file. Details in [systemd/README.md](../../systemd/README.md).

### rc.local

Add the two lines before anything that needs the network. The `DEVICE_ID` export must come first.

```sh
export DEVICE_ID="mydevice"
( while :; do /usr/local/bin/awacs.sh; sleep 10; done ) >/dev/null 2>&1 &
```

`/etc/rc.local` must be executable (`sudo chmod 755 /etc/rc.local`); on systemd images it runs through `rc-local.service`, check it with `systemctl status rc-local`. The wizard writes the same lines between the markers `# >>> awacs (managed by install.sh) >>>` and `# <<< awacs <<<`. Remove any other WiFi watchdog from `rc.local`; the daemon warns in its log when a script named `aasw.sh` is running.

Use systemd when the image has it. Do not install both: the second copy loses the daemon's lock and exits every ten seconds.

## Verification

```sh
awacs.sh check              # prints internet: OK (exit 0) or internet: DOWN (exit 1); no root needed
sudo awacs.sh status
sudo awacs.sh networks
sudo tail -f /var/log/awacs.log
```

The first lines of a healthy start with a local-only conf:

```text
[INFO][20/09 10:15:04] AWACS 1.0 starting on wlan0 (device mydevice)
[INFO][20/09 10:15:04] reporting: local | probe: none - signal mode | wifi cell: auto
```

With a site, the second line names the site and the probe target instead of `none - signal mode`. A NetworkManager image adds `NetworkManager backend - AWACS supervises it (full capability)`. The line `NetworkManager image but AWACS cannot drive it (unmanaged/no nmcli) - monitoring only` means the interface is unmanaged or `nmcli` is missing; the daemon only watches until that is fixed. `interface ${IF} not present - is the WiFi hardware alive?` means the detected interface does not exist; set `AWACS_IF` in the launcher's environment.

`status` prints one row per fact: device (id and interface), backend, daemon (running with its pid, or not running), network, signal, ip, gateway (reachable or not), internet (ONLINE or OFFLINE), viewer (whether a live stream is running) and upload (the kernel counter rate over three seconds). Row labels are English; several values carry an Arabic gloss after a slash, and a note line in Arabic precedes the rows.

With a site configured and `LOG_TARGET` set to `both` or `remote`, the start line reaches `<device-id>/log/log.txt` beside the receiver, and `<device-id>/tmp/wifi.tmp` is written on the first healthy tick and refreshed about every 60 seconds. When the box starts offline the lines wait in the spool and arrive after the first 30 seconds of verified internet.

A start line that repeats every ten seconds means the daemon exits right after starting and the launcher respawns it; the lines between two start lines give the reason. A second launcher does not produce start lines: the losing copy exits silently and is respawned for nothing. Check that only one method is installed with `systemctl is-enabled awacs` and `grep awacs.sh /etc/rc.local`.

The no-write rule can be checked by hand: `sudo md5sum /etc/wpa_supplicant/wpa_supplicant.conf` (or `ls -l /etc/NetworkManager/system-connections`) before install, after a reboot and after a day. Nothing changes.

### Dashboard

`tools/awacs-tui.sh` is a read-only terminal dashboard: link, daemon pid, stored and visible networks and the log tail, redrawn every two seconds. It needs bash 5 and an 80x24 terminal, runs on the device (`sudo tools/awacs-tui.sh` for the full picture) and never triggers a scan; the `s` key runs `awacs.sh speed` on demand. Flags: `--plain` (no escape codes), `--once` (one frame), `--lang en|ar`, `--interval N`.

## Stopping and restarting

`systemctl stop awacs` sends SIGTERM; the daemon re-enables every stored network and exits 0. Under `rc.local`, `kill "$(head -1 /run/awacs/lock)"` does the same and the loop starts a new daemon within ten seconds; to stop for good, comment the line out in `/etc/rc.local` first. A stop in the middle of a recovery leaves a temporary network entry behind; the next start removes it before its first connection attempt. The conf is read at start only: after editing `/etc/awacs.conf`, restart the daemon.

```sh
sudo systemctl restart awacs                 # systemd
sudo kill "$(head -1 /run/awacs/lock)"       # rc.local: the loop restarts it within 10 s
```

To change the device id later, edit `Environment=DEVICE_ID=` in the drop-in or the `export DEVICE_ID=` line in `rc.local` and restart, or re-run the wizard with `--device-id`.

## Upgrade

Re-running the wizard (`sudo ./install.sh` or the one-liner) replaces `awacs.sh`, keeps the conf and restarts the daemon. By hand: verify the checksum, install the file and restart as above. Check `sudo awacs.sh status` afterwards; the log shows a fresh start line.

## Uninstall

```sh
sudo ./install.sh --uninstall            # remove the unit or the rc.local block and awacs.sh; keep settings and log
sudo ./install.sh --uninstall --purge    # also remove /etc/awacs.conf, /var/log/awacs.log and /run/awacs
```

An `rc.local` loop started in the current boot may still be alive after `--uninstall`; it ends at the next reboot. By hand:

```sh
sudo systemctl disable --now awacs && sudo rm -rf /etc/systemd/system/awacs.service /etc/systemd/system/awacs.service.d && sudo systemctl daemon-reload
# or: remove the awacs block from /etc/rc.local, then kill "$(head -1 /run/awacs/lock)"
sudo rm -f /usr/local/bin/awacs.sh
sudo rm -f /etc/awacs.conf             # holds hotspot passwords
sudo rm -f /var/log/awacs.log
```

Nothing else to clean:

- `/run/awacs` and any `awacs-*` keyfile under `/run/NetworkManager/system-connections` are tmpfs and vanish at reboot. To remove them now: `sudo rm -rf /run/awacs; sudo rm -f /run/NetworkManager/system-connections/awacs-*.nmconnection; sudo nmcli connection reload`.
- On the wpa backend a temporary network lives only in the live supplicant; `sudo wpa_cli -i wlan0 reconfigure` or a reboot drops it.
- The stealth rule, if enabled, is a runtime `iptables` rule; `avahi-daemon` was stopped, not disabled. Both revert at reboot.
- `wpa_supplicant.conf` and the NetworkManager profiles were never written to. There is nothing to restore.

## Files after install

| Path | Owner and mode | Contents |
| --- | --- | --- |
| `/usr/local/bin/awacs.sh` | root 0755 | the daemon and toolbox |
| `/etc/awacs.conf` | root 0600 | your settings, including hotspot passwords |
| `/var/log/awacs.log` | root 0600 | the local log, rotated at `LOG_CAP` lines |
| `/run/awacs/` | root 0700 | lock and pid, scan cache, empty-scan counter, spool, temporary-network marker, probe body, once-per-boot apt marker |
| `/etc/systemd/system/awacs.service` and `awacs.service.d/10-device-id.conf` | root 0644 | the launcher (systemd) |
| the marked block in `/etc/rc.local` | root 0755 | the launcher (rc.local) |
