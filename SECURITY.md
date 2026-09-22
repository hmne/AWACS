# Security

## What the daemon does as root

`awacs.sh` runs as root and takes these privileged actions on the device, and no others:

- `reboot`, only when the reboot condition is met: a stored network visible and unreachable, the gateway silent, no wrong-password sign, for `REBOOT_AFTER_MIN` minutes.
- `modprobe -r brcmfmac` and `modprobe brcmfmac` (recovery rung L3).
- `systemctl restart dhcpcd` or `systemctl restart wpa_supplicant` (rung L2, wpa backend); `systemctl restart NetworkManager` (rung L3, nm backend).
- `rfkill unblock wifi` at start and in rung L1; `rfkill block` and `unblock` on the interface's own rfkill index (rung L1, nm backend), with `nmcli radio wifi off` and `on` as the fallback.
- `ip link set IF down` and `up` (rung L1, wpa backend); `iw dev IF set power_save off`.
- `nmcli device reapply`, `nmcli device disconnect` and `nmcli device connect` on the WiFi interface; `nmcli connection up` on any stored profile (that is how a stored network is selected); `nmcli connection down` and `delete` on its own temporary profiles only; `nmcli connection load` of its own `/run` keyfile and `nmcli connection reload` (nm backend).
- `wpa_cli reassociate`, `select_network`, `enable_network all`, `add_network`, `set_network` and `scan`, `remove_network` on its own temporary id only, and read-only queries (wpa backend).
- An `iptables` INPUT rule dropping ICMP echo on the WiFi interface and `systemctl stop avahi-daemon`, only with `STEALTH_MODE="yes"`.
- One background `apt-get install` per boot for tools it found missing at start. There is no knob to disable it; without `apt-get` nothing is installed and the log names the missing tools.

`/etc/awacs.conf` is sourced by bash as root. That is why the script refuses it unless it is owned by root with no read or write bits for group or others, and why it must contain plain assignments only.

## What it talks to

- ICMP echo to 8.8.8.8 and 1.1.1.1 every `TICK` seconds, and to the default gateway during recovery and in `status`.
- HTTP GET to `http://connectivitycheck.gstatic.com/generate_204`.
- HTTP POST to `${SITE_URL}/${DEVICE_ID}/${SITE_API}` when `SITE_URL` is set: the reachability check, log lines, the WiFi cell and upload probes; and to `PROBE_URL` when set.
- The Debian package mirrors through `apt-get`, once per boot, when a tool is missing.

An egress filter must allow at least one internet-check rung, or the daemon reads every network as offline and keeps recovering.

## What the script protects

- `/etc/awacs.conf` holds the passwords of your `SAFETY_NET` networks in plain text. The script refuses to load it unless it is owned by root with no read or write bits for group or others (`0600`), and prints the reason when it refuses. Keep it that way; do not commit it (the repository `.gitignore` excludes `awacs.conf`).
- Runtime state lives in `/run/awacs`, mode `0700`, created with `umask 077`. SSID lists are location data; the scan cache and spool are root-only.
- Passwords never appear in a process's argv: on the wpa backend they go to `wpa_cli` over stdin; on NetworkManager they are written to a `/run` keyfile with mode `0600`.
- `DEVICE_ID` is validated to `[A-Za-z0-9_-]{1,32}` before it reaches a URL or a root terminal. Network names are stripped of control bytes before display; matching never uses the decoded form.
- The script never writes to `/etc/wpa_supplicant/wpa_supplicant.conf` or to NetworkManager profiles.
- Stealth mode (`STEALTH_MODE="yes"`) drops ICMP echo on the WiFi interface and stops `avahi-daemon`. It is a visibility measure, not access control.

## What the site owner is responsible for

The endpoint (`SITE_API`, `receiver.php` by default) carries no authentication: anyone who can reach it can append to `log/log.txt` and overwrite `tmp/wifi.tmp` for a device id. The shipped receivers whitelist the two paths and cap the log, nothing more. If you expose the endpoint:

- serve it over HTTPS;
- restrict who can POST (an IP allow-list, a reverse-proxy header the device adds, or client certificates);
- treat the log as untrusted text and escape it before rendering.

The device sends log lines (which may contain SSIDs seen on the air), the WiFi cell (current SSID, band, counts, a speed), and upload probes whose body is `PROBE_KB` kilobytes of zero-filled data. It never sends passwords.

## Open networks

With `OPEN_NETWORKS="yes"` (the default) the device joins, as a last resort, an open network it does not know. Traffic on such a network is visible to its operator. The daemon joins only after every stored and emergency network has failed, retires the network as soon as a stored one is back, and stores nothing about it. Set `OPEN_NETWORKS="no"` if that is not acceptable for your device.

## Reporting a vulnerability

Do not open a public issue for a security problem. Use GitHub's private vulnerability reporting on this repository (Report a vulnerability under the Security tab). Include the script version (`awacs.sh help` prints it), the backend (`sudo awacs.sh status`), and the relevant log lines.
