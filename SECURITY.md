# Security

## What the script protects

- `/etc/awacs.conf` holds the passwords of your `SAFETY_NET` networks in plain text. The script refuses to load it unless it is owned by root with no group/other bits (`0600`), and prints the reason when it refuses. Keep it that way; do not commit it (the repository `.gitignore` excludes `awacs.conf`).
- Runtime state lives in `/run/awacs`, mode `0700`, created with `umask 077`. SSID lists are location data; the scan cache and spool are root-only.
- Passwords never appear in a process's argv: on the wpa backend they go to `wpa_cli` over stdin; on NetworkManager they are written to a `/run` keyfile with mode `0600`.
- `DEVICE_ID` is validated to `[A-Za-z0-9_-]{1,32}` before it reaches a URL or a root terminal. Network names are stripped of control bytes before display; matching never uses the decoded form.
- The script never writes to `/etc/wpa_supplicant/wpa_supplicant.conf` or to NetworkManager profiles.
- Stealth mode (`STEALTH_MODE="yes"`) drops ICMP echo on the WiFi interface and stops `avahi-daemon`. It is a visibility measure, not access control.

## What the site owner is responsible for

The `device_api.php` contract carries no authentication: anyone who can reach the endpoint can append to `log/log.txt` and overwrite `tmp/wifi.tmp` for a device id. The shipped receiver whitelists paths and caps the log, nothing more. If you expose it:

- serve it over HTTPS;
- restrict who can POST (IP allow-list, a reverse-proxy header the device adds, or client certificates);
- treat the log as untrusted text when rendering it (escape it; the reference dashboard does).

The device sends: log lines (which may contain SSIDs seen on the air), the WiFi cell (current SSID, band, counts, a speed), and upload probes of zeros. It never sends passwords.

## Open networks

With `OPEN_NETWORKS="yes"` (the default) the device will, as a last resort, join an open network it does not know. Traffic on such a network is visible to its operator. AWACS only joins after every stored and emergency network has failed, retires the network as soon as a stored one is back, and stores nothing about it. Set `OPEN_NETWORKS="no"` if that is not acceptable for your device.

## Reporting a vulnerability

Please do not open a public issue for a security problem. Use GitHub's private vulnerability reporting on this repository ("Report a vulnerability" under the Security tab), or contact the maintainers through the address in the repository profile. Include the script version (`awacs.sh help` prints it), the backend (`awacs.sh status`), and the relevant log lines. You will get an acknowledgement within a week.
