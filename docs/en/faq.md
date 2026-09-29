# FAQ

Short answers. The mechanics are in [how-it-works.md](how-it-works.md), the knobs in [configuration.md](configuration.md).

## Does it change my saved networks?

No. The script contains no `save_config`, no `disable_network`, no `nmcli connection modify` and no `nmcli device wifi connect`; it joins stored networks by id through the live supplicant or `nmcli connection up`. Three runtime-only changes exist: `scan_ssid 1` on the stored entries of the live supplicant (wpa); a temporary entry for an emergency or open network, kept in the live supplicant or as a keyfile under `/run/NetworkManager/system-connections` and removed by the daemon; and a network joined from a site's WiFi menu, kept in the live supplicant or as a `/run` keyfile named `awacs-joined-<hexssid>` and re-added from `/etc/awacs.networks` at every start. To check: `sudo md5sum /etc/wpa_supplicant/wpa_supplicant.conf` (or `ls -l /etc/NetworkManager/system-connections`) before the install and after a week.

## Does it store my WiFi passwords?

Two kinds. The ones you write into `/etc/awacs.conf` under `SAFETY_NET`, in plain text; the file must be owned by root with mode `0600`, or the daemon ignores it. And the ones typed on a site's WiFi menu for a network the device did not know: once that network has delivered internet, its password is kept in `/etc/awacs.networks` (root, `0600`, one `<hexssid>\t<psk>` line per network) so it is re-added at every start; a password that failed is never written. It never reads or copies the passwords in `wpa_supplicant.conf` or in NetworkManager profiles. See the key under [Can the site tell it what to do?](#can-the-site-tell-it-what-to-do).

## Does it need internet to install?

The one-line install downloads `install.sh`, then `awacs.sh` and `SHA256SUMS`. From a clone the wizard installs the local `awacs.sh`, verified against `SHA256SUMS` when that file sits beside it, and works offline when every required tool is present; missing packages come from `apt-get`. A site that does not answer during the wizard is accepted under `--yes`; the daemon spools its lines until the site is reachable.

## Which systems does it run on?

Raspberry Pi OS and other Debian derivatives with either `dhcpcd` plus `wpa_supplicant` (the wpa backend) or NetworkManager (the nm backend), bash 4 or newer, and the tools listed under Requirements in the [README](../../README.md). Without `apt-get` the daemon logs `no apt-get on this system - install manually: ...` and you install missing tools yourself. Ethernet is not handled: without a wireless interface the daemon logs `interface wlan0 not present - is the WiFi hardware alive?` and keeps trying.

## What happens on reboot?

`/run/awacs` is tmpfs: the lock, the scan cache, the spool and the markers are gone, and so is the temporary network. Spooled lines not sent before a power cut are lost. Before a reboot the daemon orders itself it copies the spool beside the log and writes a marker; the next start restores the story in front of its own lines and says `starting after the reboot AWACS ordered at <time> - wedged 30 min (<sign>), <n> recovery runs before it`, so the site reads the outage, the reboot line and the start in order. `/etc/awacs.conf` and `/var/log/awacs.log` persist. The launcher starts the daemon again; without internet at that moment recovery starts at once, and the reboot timer starts from zero.

## How do I stop it?

`sudo systemctl stop awacs` under systemd. With `rc.local`, comment out the launch line first, then `sudo kill "$(head -1 /run/awacs/lock)"`; without the first step the loop starts it again after 10 s. On SIGTERM, SIGINT or SIGHUP the daemon re-enables every stored network, says `AWACS stopping on SIGTERM (systemctl stop or shutdown) - stored networks re-enabled, the network layer runs on its own until the next start` (naming the signal) and exits 0. `sudo ./install.sh --uninstall` removes the service or the `rc.local` lines and the script ([install.md](install.md)).

## Can I disable reboots?

No. `REBOOT_AFTER_MIN` accepts 1 to 9999999 minutes; 0 is rejected and falls back to 30. A reboot is considered only for evidence that the fault is on the device, persisting for that many minutes: a stored network on the air that cannot be joined, no gateway that answers, no wrong-password sign, and on nm a NetworkManager that has given up.

## Why no reboot on an ISP outage?

A reboot cannot fix it. When the gateway answers a ping the link works and the fault is upstream: the round is classified as external, `outage looks external: the router answers, the fault is upstream (round N) — waiting, not rebooting`, and the reboot timer is cleared. The first recovery of such an outage also keeps the working association: it skips the reassociate and evaluates the other stored networks around the one the device is on.

## Will it reboot on a wrong password?

No. A `TEMP-DISABLED` entry in the supplicant (wpa) or an authentication error from `nmcli` (nm) logs `association refused by <name> - wrong password? (recovery continues, reboot stays off)` (the plain `association refused - wrong password? (recovery continues, reboot stays off)` when no name is known) and sets the reboot timer to zero every time it is seen. The rungs still run, in case a real fault coincides with a stale password.

## Can I stop the background package install?

There is no knob. It runs at most once per boot, in the background, and only for tools the start-up inventory found missing. Install the tools yourself, or have no `apt-get`, and nothing is attempted.

## What does it contact on the internet?

ICMP echo to `8.8.8.8` and `1.1.1.1`; HTTP to `http://connectivitycheck.gstatic.com/generate_204`; HTTP or HTTPS to `${SITE_URL}/${DEVICE_ID}/${SITE_API}` and to `PROBE_URL`; the apt mirrors once per boot when a tool is missing. An egress firewall must allow those. Nothing else is contacted.

## What does the site receive?

POST requests to `${SITE_URL}/${DEVICE_ID}/${SITE_API}`: `file=log/log.txt&data=<line>` per reported event when `LOG_TARGET` is `both` or `remote`; `file=tmp/wifi.tmp&data=kbps,visible,total,band,SSID` about every 60 s when `REPORT_WIFI` allows it; `file=tmp/wifi_scan.tmp&data=<list>` (the networks the radio heard, one tab-separated row each, with whether the device knows the network and its SSID as hex) after each real scan, at most once per 60 s, under the same knob; `file=tmp/wifi_state.tmp&data=<answer>` after a command the site sent; `file=wifi_key&data=<64 hex>` once per boot, the device key that opens a password typed on the site; the upload probe body with no `file` field (to `PROBE_URL` instead when set); and the `probe=1` POST of the fourth internet rung, which the endpoint must answer with 400. Network names reach the site in the cell, the scan list and log lines that name one; no password leaves the device, and the key crosses once, at registration, never in a log. The contract is in [integration.md](integration.md).

## Can the log lines be in Arabic?

Yes. `LOG_LANG` selects the language of the local log and `SITE_LANG` that of the site copy, each `en` (the default) or `ar`, independently of the other. `DEBUG` lines stay English, and a line with no Arabic text stays English.

## Can the site tell it what to do?

Three things, from a site with a WiFi menu: scan now, try a stored network (`switch`), and try a new network with a password typed on the site (`join`). The daemon does not poll for them; the site's relay on the device (the reference dashboard's capture script) writes `/run/awacs/cmd` and sends `SIGUSR1`, the daemon acts within a fraction of a second, and the tap-to-answer path is about one to three seconds. A switch or join is a trial: after 15 s the daemon measures and stays only when the network beats the one it left by `SWITCH_GAIN_PCT`, else it goes back; nothing is forced. The menu's "keep me on this network" sends the switch with `hold=1800`: the daemon then stays on that network for 30 minutes even when it measured slower, as long as it has internet, and neither the preferred-network return nor the evaluation moves it; a real outage still ends the hold and the recovery chooses the network. The password passes through the site encrypted under the device key (`/etc/awacs.key`, registered with the site once per boot); a device that lost its key after a reflash is re-paired from the site's admin page once. The channel, the states and the key are in [integration.md](integration.md); the receivers in `server/` accept the answers and the key but carry no command.

## Can I run two devices against one site?

Yes. Give each device its own `DEVICE_ID`; the site path is `${SITE_URL}/${DEVICE_ID}/`, and the shipped receivers keep `log/log.txt` and `tmp/wifi.tmp` per id. Two devices with the same id write into one log and overwrite one cell.

## Does it work without a site?

Yes. Leave `SITE_URL` empty. The log is local, the internet check uses the pings and `generate_204`, and the daemon runs in signal mode: on an outage the strongest visible stored network that delivers internet wins, no slow-upload evaluation runs, and the preferred-network return does not measure on arrival. To keep measured choice without a site, set `PROBE_URL` to any URL that accepts a POST body.

## Why is my hotspot tried before an open network?

The order in every recovery round is stored networks, then `SAFETY_NET` entries (emergency networks with passwords you chose), then open networks. Emergency entries are tried even when the scan does not show them, since a hotspot is often switched on a moment ago or hidden. Open networks belong to strangers: joined only with `OPEN_NETWORKS=yes`, and skipped below -80 dBm (wpa) or 25 % (nm).

## Does it interrupt a live stream?

Not while the stream is healthy. While `raspistill` (with `live_raw`, `preview.jpg` or `capture.jpg`) or `curl ... upfile=@` runs, no probe and no evaluation start unless the interface's own upload rate falls under `STREAM_MIN_KBPS`. Other workloads are not detected and count as ordinary traffic.

## How much traffic does it generate?

Idle: one ping per `TICK` when the first answers, two when it does not, and one small HTTP request when both pings fail, two when `SITE_URL` is set. A check that fails while the device is sending adds one patient check, three pings per target and the same one or two HTTP requests, once per outage. A scan at most once per `SCAN_TTL`, and only when something asks for one. Upload probes of `PROBE_KB` only at decision moments. With a site: one small POST per reported event, one per minute for the WiFi cell and one for the scan list after each real scan.

## Do non-ASCII network names work?

Yes. Display decodes them; matching uses the escaped text on wpa and lowercase hex on nm. Two limits on wpa only: open networks with non-ASCII names are skipped as last-resort candidates, and stored names containing a backslash, a double quote, a tab, a newline, an escape byte or a leading or trailing space never match the scan. The nm backend has neither limit.

## Hidden networks?

wpa: the daemon sets `scan_ssid 1` at runtime on every stored entry, at start, at every recovery start and after its own rungs L2 and L3. nm: NetworkManager probes hidden profiles itself, but the profile must already carry `802-11-wireless.hidden=yes`; the daemon does not write it.

## Can I run it alongside NetworkManager?

That is the nm backend. The daemon waits while NetworkManager is connecting and intervenes only through `nmcli` after NetworkManager reports the device disconnected or failed. It never runs `wpa_cli`, `ip link` down or up, or a `dhcpcd` restart on an nm image.

## Can it run beside another WiFi watchdog?

No. Two controllers on one radio undo each other's work.

## What is the night profile?

Between `NIGHT_START` and `NIGHT_END`, when `NIGHT_MODE` is `yes`, the upload floor is `NIGHT_MIN_UP_KBPS`, the switch gain `NIGHT_GAIN_PCT` and the evaluation cooldown `NIGHT_DANCE_COOLDOWN`: slower links are tolerated and switching is rarer. `TICK` stays the same. Transitions are logged as `night profile active until 06:00 - floor 200 kbps, a challenger must reach 300% of the incumbent, evaluations 40 min apart` and `day profile active until 22:00 - floor 400 kbps, a challenger must reach 150% of the incumbent, evaluations 20 min apart`.

## Does `check` need root?

No. `awacs.sh check` prints `internet: OK` (exit 0) or `internet: DOWN` (exit 1) and is meant for scripts and cron; `help` is also unprivileged. Without root the conf is not read, so `check` uses the built-in defaults and the first three rungs only; `sudo awacs.sh check` reads the conf and adds the site rung. The other words need root.

## Where is the state?

`/run/awacs`, root-only, tmpfs: the lock with the daemon's pid, the scan cache with its empty-scan counter and the stamp of the last real scan, the spool, the temporary-network marker, the once-per-boot install marker, the start counter, the reporting-channel markers and the site-command files (`cmd`, `cmd.ready`, `cmd.last`, `cmd.answer`, `join_id`). Nothing persists across reboots except the log, the conf, the device key `/etc/awacs.key`, the joined networks `/etc/awacs.networks` and the self-reboot memory beside the log (`awacs.log.reboot`, `awacs.log.spool`, `awacs.log.reboots`), which the next start consumes.
