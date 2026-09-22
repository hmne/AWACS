# FAQ

Short answers. The mechanics are in [how-it-works.md](how-it-works.md), the knobs in [configuration.md](configuration.md).

## Does it change my saved networks?

No. The script contains no `save_config`, no `disable_network`, no `nmcli connection modify` and no `nmcli device wifi connect`; it joins stored networks by id through the live supplicant or `nmcli connection up`. Two runtime-only changes exist: `scan_ssid 1` on the stored entries of the live supplicant (wpa), and a temporary entry for an emergency or open network, kept in the live supplicant or as a keyfile under `/run/NetworkManager/system-connections` and removed by the daemon. To check: `sudo md5sum /etc/wpa_supplicant/wpa_supplicant.conf` (or `ls -l /etc/NetworkManager/system-connections`) before the install and after a week.

## Does it store my WiFi passwords?

Only the ones you write into `/etc/awacs.conf` under `SAFETY_NET`, in plain text; the file must be owned by root with mode `0600`, or the daemon ignores it. It never reads or copies the passwords in `wpa_supplicant.conf` or in NetworkManager profiles.

## Does it need internet to install?

The one-line install downloads `install.sh`, then `awacs.sh` and `SHA256SUMS`. From a clone the wizard installs the local `awacs.sh`, verified against the local `SHA256SUMS`, and works offline when every required tool is present; missing packages come from `apt-get`. A site that does not answer during the wizard is accepted under `--yes`; the daemon spools its lines until the site is reachable.

## Which systems does it run on?

Raspberry Pi OS and other Debian derivatives with either `dhcpcd` plus `wpa_supplicant` (the wpa backend) or NetworkManager (the nm backend), bash 4 or newer, and the tools listed under Requirements in the [README](../../README.md). Without `apt-get` the daemon logs `no apt-get on this system - install manually: ...` and you install missing tools yourself. Ethernet is not handled: without a wireless interface the daemon logs `interface wlan0 not present - is the WiFi hardware alive?` and keeps trying.

## What happens on reboot?

`/run/awacs` is tmpfs: the lock, the scan cache, the spool and the markers are gone, and so is the temporary network. Spooled lines not sent before the reboot are lost; the site learns of the reboot from the next start line. `/etc/awacs.conf` and `/var/log/awacs.log` persist. The launcher starts the daemon again; without internet at that moment recovery starts at once, and the reboot timer starts from zero.

## How do I stop it?

`sudo systemctl stop awacs` under systemd. With `rc.local`, comment out the launch line first, then `sudo kill "$(head -1 /run/awacs/lock)"`; without the first step the loop starts it again after 10 s. On SIGTERM, SIGINT or SIGHUP the daemon re-enables every stored network and exits 0. `sudo ./install.sh --uninstall` removes the service or the `rc.local` lines and the script ([install.md](install.md)).

## Can I disable reboots?

No. `REBOOT_AFTER_MIN` accepts 1 to 9999999 minutes; 0 is rejected and falls back to 30. A reboot is considered only for evidence that the fault is on the device, persisting for that many minutes: a stored network on the air that cannot be joined, no gateway that answers, no wrong-password sign, and on nm a NetworkManager that has given up.

## Why no reboot on an ISP outage?

A reboot cannot fix it. When the gateway answers a ping the link works and the fault is upstream: the round is classified as external, `outage looks external (round N) — waiting, not rebooting`, and the reboot timer is cleared. The first recovery of such an outage also keeps the working association: it skips the reassociate and evaluates the other stored networks around the one the device is on.

## Will it reboot on a wrong password?

No. A `TEMP-DISABLED` entry in the supplicant (wpa) or an authentication error from `nmcli` (nm) logs `association refused - wrong password? (recovery continues, reboot stays off)` and sets the reboot timer to zero every time it is seen. The rungs still run, in case a real fault coincides with a stale password.

## Can I stop the background package install?

There is no knob. It runs at most once per boot, in the background, and only for tools the start-up inventory found missing. Install the tools yourself, or have no `apt-get`, and nothing is attempted.

## What does it contact on the internet?

ICMP echo to `8.8.8.8` and `1.1.1.1`; HTTP to `http://connectivitycheck.gstatic.com/generate_204`; HTTP or HTTPS to `${SITE_URL}/${DEVICE_ID}/${SITE_API}` and to `PROBE_URL`; the apt mirrors once per boot when a tool is missing. An egress firewall must allow those. Nothing else is contacted.

## What does the site receive?

POST requests to `${SITE_URL}/${DEVICE_ID}/${SITE_API}`: `file=log/log.txt&data=<line>` per reported event when `LOG_TARGET` is `both` or `remote`; `file=tmp/wifi.tmp&data=kbps,visible,total,band,SSID` about every 60 s when `REPORT_WIFI` allows it; the upload probe body with no `file` field (to `PROBE_URL` instead when set); and the `probe=1` POST of the fourth internet rung, which the endpoint must answer with 400. Network names reach the site only in the cell and in log lines that name one; no password leaves the device. The contract is in [integration.md](integration.md).

## Can the log lines be in Arabic?

Yes. `LOG_LANG` selects the language of the local log and `SITE_LANG` that of the site copy, each `en` (the default) or `ar`, independently of the other. `DEBUG` lines stay English, and a line with no Arabic text stays English.

## Can I run two devices against one site?

Yes. Give each device its own `DEVICE_ID`; the site path is `${SITE_URL}/${DEVICE_ID}/`, and the shipped receivers keep `log/log.txt` and `tmp/wifi.tmp` per id. Two devices with the same id write into one log and overwrite one cell.

## Does it work without a site?

Yes. Leave `SITE_URL` empty. The log is local, the internet check uses the pings and `generate_204`, and the daemon runs in signal mode: on an outage the strongest visible stored network that delivers internet wins, no slow-upload evaluation runs, and the preferred-network return does not measure on arrival. To keep measured choice without a site, set `PROBE_URL` to any URL that accepts a POST body.

## Why is my hotspot tried before an open network?

The order in every recovery round is stored networks, then `SAFETY_NET` entries (emergency networks with passwords you chose), then open networks. Emergency entries are tried even when the scan does not show them, since a hotspot is often switched on a moment ago or hidden. Open networks belong to strangers: joined only with `OPEN_NETWORKS=yes`, and skipped below -80 dBm (wpa) or 25 % (nm).

## Does it interrupt a live stream?

Not while the stream is healthy. While `raspistill` (with `live_raw`, `preview.jpg` or `capture.jpg`) or `curl ... upfile=@` runs, no probe and no evaluation start unless the interface's own upload rate falls under `STREAM_MIN_KBPS`. Other workloads are not detected and count as ordinary traffic.

## How much traffic does it generate?

Idle: one ping per `TICK` when the first answers, two when it does not, and one small HTTP request when both pings fail, two when `SITE_URL` is set. A check that fails while the device is sending adds one patient check, three pings per target and the same one or two HTTP requests, once per outage. A scan at most once per `SCAN_TTL`, and only when something asks for one. Upload probes of `PROBE_KB` only at decision moments. With a site: one small POST per reported event and one per minute for the WiFi cell.

## Do non-ASCII network names work?

Yes. Display decodes them; matching uses the escaped text on wpa and lowercase hex on nm. Two limits on wpa only: open networks with non-ASCII names are skipped as last-resort candidates, and stored names containing a backslash, a double quote, a tab, a newline, an escape byte or a leading or trailing space never match the scan. The nm backend has neither limit.

## Hidden networks?

wpa: the daemon sets `scan_ssid 1` at runtime on every stored entry, at start, at every recovery start and after its own rungs L2 and L3. nm: NetworkManager probes hidden profiles itself, but the profile must already carry `802-11-wireless.hidden=yes`; the daemon does not write it.

## Can I run it alongside NetworkManager?

That is the nm backend. The daemon waits while NetworkManager is connecting and intervenes only through `nmcli` after NetworkManager reports the device disconnected or failed. It never runs `wpa_cli`, `ip link` down or up, or a `dhcpcd` restart on an nm image.

## Can it run beside another WiFi watchdog?

No. Two controllers on one radio undo each other's work.

## What is the night profile?

Between `NIGHT_START` and `NIGHT_END`, when `NIGHT_MODE` is `yes`, the upload floor is `NIGHT_MIN_UP_KBPS`, the switch gain `NIGHT_GAIN_PCT` and the evaluation cooldown `NIGHT_DANCE_COOLDOWN`: slower links are tolerated and switching is rarer. `TICK` stays the same. Transitions are logged as `night profile active (floor N kbps)` and `day profile active (floor N kbps)`.

## Does `check` need root?

No. `awacs.sh check` prints `internet: OK` (exit 0) or `internet: DOWN` (exit 1) and is meant for scripts and cron; `help` is also unprivileged. Without root the conf is not read, so `check` uses the built-in defaults and the first three rungs only; `sudo awacs.sh check` reads the conf and adds the site rung. The other words need root.

## Where is the state?

`/run/awacs`, root-only, tmpfs: the lock with the daemon's pid, the scan cache and its empty-scan counter, the spool, the temporary-network marker and the once-per-boot install marker. Nothing persists across reboots except the log and the conf.
