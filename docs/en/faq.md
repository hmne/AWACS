# FAQ

**Does AWACS store my WiFi passwords?**
Only the ones you put in `/etc/awacs.conf` under `SAFETY_NET`, in plain text, which is why the file must be root-owned and `0600`. It never reads or copies the passwords in `wpa_supplicant.conf` or NetworkManager profiles; it asks the supplicant or NM to connect by network id.

**Does it change my WiFi settings?**
No. There is no `save_config`, no `disable_network`, no `nmcli connection modify`, no `nmcli device wifi connect` in the script. Runtime-only changes exist (`scan_ssid 1` on stored networks so hidden ones are probed, a temporary network for the emergency/open fallback) and they live in the live supplicant or under `/run`; a reboot leaves no trace. The lab compared your network files byte for byte before and after every scenario.

**Why upload speed and not download?**
The devices this was built for send data (camera frames, sensor readings). Download tells them nothing. A 200 KB upload probe at decision moments costs little and answers the only question that matters: which network delivers our data fastest. There are no routine download tests.

**Why no reboot on an ISP outage?**
Because a reboot cannot fix it. If the gateway answers, the link works and the fault is upstream. The reboot valve arms only on evidence that the device itself is wedged: a stored network on the air that it provably cannot ride, no gateway, no wrong-password signature, for `REBOOT_AFTER_MIN` minutes.

**Will it reboot on a wrong password?**
No. A `TEMP-DISABLED` network (wpa) or an authentication error (NM) sets the reboot clock to zero every time it is seen. The recovery ladder still runs, in case a real wedge coincides with one stale password.

**Do Arabic (or emoji) network names work?**
Yes. Display decodes them; matching uses the raw escaped text on the wpa backend and lowercase hex on NM, so nothing is lost in translation. Two limits on the wpa backend only: open networks with non-ASCII names are skipped as last-resort candidates (the supplicant's quoted parser cannot take `iw`'s escaped form), and stored names containing a literal backslash, double quote, tab, newline, escape byte or leading/trailing space never match visibility. Every sane name works. The NM backend has neither limit.

**Hidden networks?**
wpa backend: AWACS sets `scan_ssid 1` at runtime on every stored network, at start and after every supplicant restart, so directed probes find them. NM backend: NM probes hidden profiles itself, but the profile must carry `802-11-wireless.hidden=yes` already; AWACS will not write it in.

**Multiple devices?**
Each device gets its own `DEVICE_ID`, and the site path is `${SITE_URL}/${DEVICE_ID}/`. One receiver serves many devices; each writes its own `log/log.txt` and `tmp/wifi.tmp` under its own id.

**Does it work without a site?**
Yes. Leave `SITE_URL` empty. The log is local, the internet check uses pings and `generate_204`, and when several stored networks work the choice falls back to signal order because there is nothing to upload to ("signal mode"). Without a probe target there is no upload QA at all: no strikes, no evaluation, no `too slow` veto — the daemon supervises connectivity only. The fight, ladder, classification, valve, emergency and open networks, and day/night profile all work the same. To keep measured choice without a site, point `PROBE_URL` at any URL that accepts a POST body.

**Does it work on Ethernet-only boxes?**
It is a WiFi tool. With no wireless interface it logs `interface wlan0 not present` and keeps trying; it will not help an Ethernet link.

**How much traffic does it generate?**
Idle: two ICMP pings per `TICK` (10 s) and, when they fail, two small HTTP requests. A scan every `SCAN_TTL` at most, and only when something asks for one. Upload probes of `PROBE_KB` only at decision moments. The WiFi cell is one tiny POST per minute when a site is configured.

**Does it interrupt a live stream?**
No. While the camera stack's stream or upload processes run, AWACS never probes or evaluates unless the stream itself is starving (its own kernel-counter rate under `STREAM_MIN_KBPS`). A healthy stream is the measurement.

**Why does `evaluate` not show a speed per network?**
By design. Estimating throughput from signal strength is exactly what the script refuses to do. Measured speeds are in the log at decision moments and in the site's WiFi cell.

**Can I run it alongside NetworkManager?**
That is the NM backend. AWACS observes NM, waits while it is mid-transition, and intervenes only through `nmcli` after NM has provably stopped trying. Never `wpa_cli`, never `ip link down/up`, never `dhcpcd` on an NM image.

**What about the old `aasw.sh`?**
Remove it. Two WiFi authorities on one radio fight each other; AWACS warns if it sees the old one running. The old launch flags (`-d`, `-q`) still work so old `rc.local` lines keep starting the new script.

**What is the "night profile"?**
Between `NIGHT_START` and `NIGHT_END` the upload floor drops to `NIGHT_MIN_UP_KBPS`, the switch gain rises to `NIGHT_GAIN_PCT`, and evaluations are `NIGHT_DANCE_COOLDOWN` apart. Slower links are tolerated and switching is rarer while nobody is watching. `TICK` stays the same.

**Does `check` need root?**
No. `awacs.sh check` prints `internet: OK` (exit 0) or `internet: DOWN` (exit 1) and is meant for scripts and cron. `help` is also unprivileged. The other words need root because they read the supplicant/NM and the private state directory.

**How do I see why it did something?**
`DEBUG=yes` (the default) writes `[DEBUG]` decision-trace lines to the local log: scan tries, QA flow and strikes, preferred-network candidates, ME evidence per round.

**Where is the state?**
`/run/awacs`, root-only, tmpfs. Lock and daemon pid, scan cache, spool, temporary-network marker, once-per-boot apt marker. Nothing persists across reboots except the log and the conf.
