# Integration

The daemon talks to one URL: `${SITE_URL}/${DEVICE_ID}/${SITE_API}`. Every request to the site goes there as an HTTP POST: log lines, the WiFi cell, the WiFi scan list, the answers to the site's WiFi commands, the registration of the device key, the fourth rung of the internet check and the upload probe (the probe goes to `PROBE_URL` instead when that knob is set). Anything that answers the contract below can receive it: the two receivers shipped in `server/`, a dashboard of your own, or an existing site with an endpoint of its own name.

## The endpoint

`SITE_URL` is the base URL; a trailing slash is stripped. `DEVICE_ID` comes from the environment, then `/tmp/device_id`, then the short hostname, then the word `device`; only a slug of letters, digits, `_` and `-` up to 32 characters is accepted. `SITE_API` is the file name under `${SITE_URL}/${DEVICE_ID}/`. It defaults to `receiver.php`, the receiver shipped in `server/`. A site that already has an endpoint of another name sets `SITE_API` to that name in `/etc/awacs.conf`, or through `install.sh --api NAME`. The value must start with a letter, digit or `_`, may contain letters, digits and `_ . / -`, is at most 64 characters long and must not contain `..`; any other value falls back to `receiver.php` and the knob is named in the fallen-knobs line at start.

Under Apache or nginx the receiver file on the server carries exactly the `SITE_API` name. The Python receiver and PHP's built-in server in router mode answer only the path `/<device-id>/receiver.php`; with those two, leave `SITE_API` at its default.

## The contract

Transport: HTTP POST with a form-encoded body and a plain-text reply. The daemon reads only the status code; reply bodies are ignored. The contract carries no credential; see [SECURITY.md](../../SECURITY.md).

| Request | Reply | Effect |
| --- | --- | --- |
| `file=log/log.txt` and `data=<line>` | `200`, body `OK` | The line is appended. |
| `file=tmp/wifi.tmp` and `data=<cell>` | `200`, body `OK` | The file is overwritten atomically. |
| `file=tmp/wifi_scan.tmp` and `data=<list>` | `200`, body `OK` | The file is overwritten atomically. |
| `file=tmp/wifi_state.tmp` and `data=<answer>` | `200`, body `OK` | The file is overwritten atomically. |
| `file=wifi_key` and `data=<64 lowercase hex>`, plus `proof=<hex>` when the key changed | `200`, body `OK`; `400 Error: bad key`; `403 Error: proof required` | The key is kept outside every served path; nothing under `file=` is written. |
| POST with no `file` field (a raw body counts; so does GET) | `400`, body `Error: no operation` | Nothing is written. The daemon reads this exact code as "site reachable". |
| `file=` with any other path | `403`, body `Error: forbidden file` | Nothing is written. |

The seven requests as the script issues them; `$API` stands for the endpoint URL:

```sh
# a log line
curl -sf --max-time 4 --data-urlencode "file=log/log.txt" --data-urlencode "data=$line" "$API"
# the WiFi cell
curl -sf --max-time 4 --data-urlencode "file=tmp/wifi.tmp" --data-urlencode "data=850,2,3,2.4GHz,HomeNet" "$API"
# the WiFi scan list: line 1 the scan's unix time, then one tab-separated row per network
curl -sf --max-time 4 --data-urlencode "file=tmp/wifi_scan.tmp" --data-urlencode "data=$list" "$API"
# the answer to a site command: <answer_epoch>\t<cmd_epoch>\t<state>\t<field>..., re-sent until a 2xx
curl -s -o /dev/null -w '%{http_code}' --max-time 4 --data-urlencode "file=tmp/wifi_state.tmp" --data-urlencode "data=$answer" "$API"
# the device key, once per boot until a 2xx; proof only when the key differs from the one the site knows
curl -s -o /dev/null -w '%{http_code}' --max-time 4 --data-urlencode "file=wifi_key" --data-urlencode "data=$key" "$API"
# the internet rung: the printed code must be 400
curl -s -o /dev/null -w '%{http_code}' --max-time 3 --data-urlencode "probe=1" "$API"
# the upload probe: PROBE_KB kilobytes of zeros as a raw body; the speed is curl's own figure
head -c $((PROBE_KB * 1024)) /dev/zero | curl -s -o /dev/null -w '%{speed_upload}' --max-time 15 --data-binary @- "$PROBE_URL"
```

### Log lines

One POST per event with `file=log/log.txt`. The line is `yyyy-mm-ddThh:mm:ss+hh:mm [LEVEL][awacs] <message>` and the levels are `INFO`, `OK`, `WARN` and `ERROR`; `DEBUG` lines stay in the local file. The message is in the language `SITE_LANG` selects, `en` by default or `ar`; the local file follows `LOG_LANG` independently, and a line with no Arabic text stays English in both. The timestamp uses `SITE_TZ` when it is set (an IANA zone name such as `Europe/Berlin`; letters, digits and `/ _ + -`, up to 64 characters), otherwise the device's own zone.

Lines are sent only when `LOG_TARGET` is `both` or `remote` and `SITE_URL` is set; with `remote` the local file keeps only the WARN and ERROR site lines (DEBUG lines and the local-only lines are unaffected). While the internet is down, and whenever a send fails (no answer within 4 s, or a 4xx or 5xx status), the line goes to the spool `/run/awacs/spool` instead. The spool keeps `SPOOL_CAP` lines (default 60): its first line, the opening of the outage, is pinned and the middle rolls off. It is sent in order three ticks (about 30 s) after the internet is verified healthy, then retried every 30 ticks (about 5 min) while lines remain, and at a daemon start that finds the internet up; a failed send stops the flush and the remainder waits.

### The WiFi cell

One POST every six healthy ticks (about 60 to 80 s with the defaults) while the internet is up, with `file=tmp/wifi.tmp`. It is sent when `REPORT_WIFI` is `yes` and `SITE_URL` is set, or when it is `auto` and log lines go to the site; `no` never sends. The value is one line of five comma-separated fields:

| Field | Content |
| --- | --- |
| kbps | The last measured upload speed; `0` when nothing was measured on the network the device is on now. |
| visible | Stored networks currently present in the scan cache (the daemon's on wpa, NetworkManager's on nm). The report causes no radio traffic. |
| total | Stored networks. |
| band | `2.4GHz`, `5GHz`, `6GHz` or empty. |
| SSID | The current network's name, or `-` when the device is not associated. |

The SSID is last so that its own commas survive: split on the first four commas only. Example: `850,2,3,2.4GHz,HomeNet`.

### The WiFi scan list

One POST with `file=tmp/wifi_scan.tmp`, under the same `REPORT_WIFI` rule as the cell, while the internet is up, on the cell's minute and at most once per 60 s, only when a new scan exists: on wpa a scan that really hit the radio (a served cache is not republished; a radio that heard nothing publishes an empty list), on nm NetworkManager's own table read without a rescan, when its rows changed. The list causes no radio traffic of its own; a refused list is retried every minute. The value is a text of several lines:

| Line | Content |
| --- | --- |
| 1 | The unix time of the scan. |
| 2 and on | One network per line, strongest first, at most 12 rows, six tab-separated fields: the display name (decoded, control bytes removed; it may hold spaces and right-to-left text), the signal in dBm (an integer; on nm converted from NetworkManager's percent, 100 % at -40 dBm and 0 % at -100), the upload measured on that network in kbps, the unix time of that measurement, `known` (`1` when the network is stored on the device, in the supplicant or as a NetworkManager profile, `0` when it is not), and `key`, the SSID's bytes as lowercase hex. The third and fourth are empty when the daemon never measured that network since it started. The key is the exact identity: display names are decoded and can collide, so a site command names a network by its key and never by its name. |

The speeds are the daemon's own upload probes of a named network (the incumbent at an evaluation, each candidate, the preferred network on arrival, a temporary network that won); a probe the target refused is not recorded, and the memory lives for the process, so a restart empties the last two fields until the next measurement. Example:

```text
1767225660
HomeNet	-45	850	1767225300	1	486f6d654e6574
OfficeNet	-67	300	1767224100	1	4f66666963654e6574
CafeFree	-82			0	4361666546726565
```

A list written by a daemon from before the two last columns carries four fields per row; a dashboard that reads both pads the row and treats a missing `known` as `1` and a missing key as no key.

### The command answer

One POST with `file=tmp/wifi_state.tmp`, only after a site command (see [Site commands](#site-commands-scan-switch-and-join)); a device that receives no commands never sends it. The value is one line of tab-separated fields: `<answer_epoch>\t<cmd_epoch>\t<state>\t<field>...`. `answer_epoch` is the device's own unix time and is display only; `cmd_epoch` is the epoch the site stamped on the command, so a page knows which tap is being answered. The states and their fields:

| State | Fields | Meaning |
| --- | --- | --- |
| `taken` | none | The command was read; the first answer to every accepted command. |
| `scanning` | none | The radio is being scanned. |
| `done` | `N` | The scan ended; `N` networks were heard and the list was published. |
| `trying` | `NAME` | The trial network is linked and delivers internet; the 15 s window has opened. |
| `measuring` | `NAME` | The trial's upload probe is running inside the window (it started within 2 s of `trying`); the number arrives with the verdict. |
| `switched` | `NAME`, `KBPS`, then `hold=<seconds>` when the switch asked for a hold | The trial network stays (a switch); with the third field, the hold has started. |
| `joined` | `NAME`, `KBPS` | The trial network stays (a join); the password is kept. |
| `returned` | `ORIGIN`, `ORIGIN_KBPS`, `TRIAL`, `TRIAL_KBPS` | The trial was slower; the device is back on the network it left. |
| `failed` | `REASON` | `expired`, `busy`, `offline`, `wrong_password`, `out_of_reach`, `no_internet`, `key_changed` or `return_failed`. |

Fields are data, not prose: the speed is in kbps and a page words it in its own units. A tab or newline inside a network name is replaced by a space. The latest answer is kept in `/run/awacs/cmd.answer`, posted in the foreground at the moment it is decided, and re-sent on every healthy tick until the site answers 2xx, so an answer decided on a trial network without internet still arrives. A page reads the file on its ordinary poll and shows the newest pair of `cmd_epoch` and `state`; the file is not a liveness signal.

### The device key

A password typed on a site travels to the device encrypted, and the key that opens it is the device's own: 32 random bytes made once with `openssl rand -hex 32` and kept as 64 lowercase hex characters in `/etc/awacs.key` (root, mode 0600). At every start, at the third healthy tick of the boot and then once a healthy minute until the site accepts it, the daemon posts it as `file=wifi_key` with `data=<64 hex>` until one 2xx has been received in this boot; the value is never written to any log or site line. The site must accept the first registration, answer 2xx to a re-registration of the same key, and refuse a different key with `403` unless the request carries `proof=<hex>`, the HMAC-SHA256 whose key is the old key's 32 raw bytes and whose message is the new key's 64 hex characters as ASCII text. The daemon sends that proof only when `/etc/awacs.key.prev` holds the key the site knew; a device that lost its key (a reflashed card) cannot prove anything, so the site keeps the old key until its owner forgets it once, from the site's own admin page (on the reference dashboard's admin page; the log line names its path). A `403` is said once per boot: `the site holds another key for this camera (a reflash?) - open admin/wifi.php?reset_key=1 once from your phone, then join from the menu works again`. A receiver that does not know `wifi_key` answers `403 Error: forbidden file`, which the daemon reads the same way, so a site that carries no commands either updates its receiver or lives with that one line per boot.

The cipher, so that another site can build the blob: `Kenc = HMAC-SHA256(K, "enc")` and `Kmac = HMAC-SHA256(K, "mac")` with `K` the 32 raw key bytes; the password is AES-256-CBC with PKCS7 padding under `Kenc` and a random 16-byte IV; `blob = <iv_hex>.<ct_base64>.<mac_hex>` where `mac = HMAC-SHA256(Kmac, the ASCII text "<iv_hex>.<ct_base64>")`. The device checks the MAC before it decrypts anything: `printf %s "$iv.$ct" | openssl dgst -sha256 -mac HMAC -macopt hexkey:$kmac`, then `openssl enc -d -aes-256-cbc -a -A -K $kenc -iv $iv`. Nothing beyond `openssl` is needed on the device. The derived keys pass through `openssl`'s argument list for the duration of each call, visible in `ps` to root on the device, which is single-user; that is accepted and stated here rather than hidden. The password itself never enters an argument list: it goes to the supplicant over stdin and to NetworkManager in a 0600 keyfile.

### The internet rung

The internet check tries, in order, a ping to `8.8.8.8`, a ping to `1.1.1.1`, an HTTP `204` from `http://connectivitycheck.gstatic.com/generate_204`, and finally a POST to the endpoint that must answer exactly `400`. The last rung exists only when `SITE_URL` is set; it rescues a carrier network that drops ICMP or rewrites the 204 page. The code must stay 400: a captive portal answers its splash page with 200, 302 or 511, and a receiver that answered 200 to an empty POST would make a portal read as online.

### The upload probe

At decision moments the daemon measures upload speed by posting `PROBE_KB` KB (default 200) of zeros to the probe target: `PROBE_URL` when set, otherwise the endpoint. curl reports its own `speed_upload` and the daemon converts bytes per second to kbps. The reply's status code plays no part in the measurement; the body carries no `file` field, so a receiver answers `400`. When curl is missing or reports zero, wget posts the same bytes from a file with a 15 s timeout and the speed is computed from the elapsed time; a wget exit other than 0 or 8 (the server answered 4xx or 5xx after the upload) reads as `0` kbps. A probe target therefore has to accept a body of that size and answer with an HTTP status.

`awacs.sh speed` runs one probe by hand and prints the target and the result.

## Site commands: scan, switch and join

A site with a WiFi menu can ask the daemon for three things: a scan of the air now, a trial of a stored network (`switch`), and a trial of a network the device does not know, with a password typed on the site (`join`). The daemon never polls the site for them: the site's own device-side relay hands a command over, and the daemon answers through `tmp/wifi_state.tmp`. The reference relay is the capture script of the maintainer's camera dashboard, which is not part of this repository and already holds a long poll on the site; the receivers shipped here store the answers and the key and carry no command themselves. What the relay owes the daemon:

- One line in `/run/awacs/cmd`, written under `umask 077` and renamed into place: `<uptime_seconds>\t<epoch>\t<cmd>\t<key>\t<blob>`. `uptime_seconds` is the device's `/proc/uptime` at the moment of the write; `epoch` is the site's stamp on the command; `cmd` is `scan`, `switch` or `join`; `key` is the SSID as lowercase hex (the scan list's sixth column), empty for a scan; `blob` is the encrypted password for a join, `hold=<seconds>` on a switch that asks to stay (see [The hold](#the-hold)), and empty otherwise.
- Then `SIGUSR1` to the PID in `/run/awacs/lock`, only while `/run/awacs/cmd.ready` exists and `/proc/<pid>/cmdline` names `awacs`. The marker exists only while a daemon that traps the signal holds the lock; a daemon from before this addition would be killed by the signal, and a PID reused by another process must never receive it. A relay that finds no such daemon answers the site itself with `failed` and `awacs_not_running`, or `awacs_old` when the lock is held but the marker is missing.

The daemon reads the command at one point only, the top of its main loop; nothing about a command runs inside a recovery or an evaluation. Its sleep between ticks is interruptible, so the signal ends the wait at once and the command is handled within a fraction of a second of the signal. End to end, from the tap on the site to the device's first answer, the path adds the site's own hold and one HTTP round trip: about one to three seconds while the relay's lane is up, not the fraction of a second the signal alone takes. Ages are compared in uptime, never with the site's clock, since a board without a clock battery cannot be trusted for that: a command older than 60 s by uptime is answered `failed` with `expired` (it waited behind a recovery); one delivered twice with the same epoch is ignored; one that arrives while a recovery is running is answered `failed` with `busy`; one that arrives while the internet is down is answered `failed` with `offline`, because the list and the answers cannot be published until the internet is back. A command file left from a previous run is read at the first loop top and answered `failed expired` when older than 60 s by uptime, otherwise served.

`scan` asks the radio now, past the `SCAN_TTL` cache and the once-a-minute gate of the list: on wpa the cache is dropped and a scan runs, on nm `nmcli device wifi rescan` then NetworkManager's own list. The list is posted in the foreground, then the answer `done` with the count. Under a live stream the stream stutters for a few seconds; one INFO line says so.

`switch` and `join` are a trial, never a takeover. The daemon remembers where it leaves from (the network and its last measured upload when fresher than 120 s, else one probe), connects to the chosen network with the trial's association budget (`TRIAL_ASSOC_WAIT`, 45 s, or `ASSOC_WAIT` when larger: a new or far network can scan 7 to 23 s before it authenticates, and the wrong-password mark is read for the whole budget), and only when the link forms and delivers internet answers `trying`; a connect that fails goes back to the origin at once and answers `failed` with the connect verdict's word (`wrong_password`, `no_internet`, else `out_of_reach`). The 15 s window opens when the internet is verified; `trying` and the cell are POSTed from a background child, the one probe starts inside the window once that child has left the uplink or after 2 s, `trying` stands alone for 5 s (`TRIAL_HEAD`), then `measuring` follows from a child too, after the `trying` child has ended, so the answers arrive in order; at the later of the two (the window's end or the probe's) the daemon applies the bar every challenger meets: the trial stays only when its upload is at least `SWITCH_GAIN_PCT` percent of the origin's (the night gain at night); otherwise the daemon returns to the origin and answers `returned` with both numbers, or `failed` with `return_failed` when the way back did not form a link; the verdict's answer is the one POST the trial waits for. In signal mode any trial that delivers internet stays. Every stored network is re-enabled on every exit; the trial counts as an evaluation for the cooldown; the ordinary evaluation and the recovery are never called from it.

### The hold

A switch may ask for a hold: `hold=<seconds>` in the fifth field of the command line, the slot a join uses for the blob (the reference site sends 1800; the daemon takes 1 to 86400, and anything else there is not a hold, so the switch runs without one and the local log says `site switch: the fifth field is not a hold - switching without one`). The trial runs as always and the same bar is applied, but a verdict that would return to the origin is skipped while the trial network has internet (the probe carried bytes, or the quick internet check passes at that moment): the daemon stays, answers `switched NAME KBPS hold=<seconds>`, and says `manual trial: OfficeNet uploads at 700 kbps, under the 1800 kbps bar (HomeNet 1200 kbps at 150%) - staying anyway, held from the menu` and then `hold on OfficeNet for 30 min - no preferred-network return and no evaluation leaves it; an internet loss or a new command ends it`. The opening line names it too (`... - the bar is 1800 kbps, and it stays for 30 min either way while it has internet`). A switch to the network the device is already on, with a hold, starts the hold without a trial: `switch asked from the site to HomeNet - already on it, holding it`. For the hold's seconds, counted on the device's uptime clock, the preferred-network return and the slow-upload evaluation do not run (a vetoed evaluation is said once per hold: `upload slow on OfficeNet (120 kbps, floor 400) - held from the menu, no evaluation until the hold ends in 25 min`); the recovery is untouched, so a real outage ends the hold, `hold on OfficeNet ended - internet lost`, and the fight chooses the network as always. Any new command the daemon serves ends it (`hold on OfficeNet ended - a new command from the site`); when the time is up the daemon says `hold on OfficeNet ended - back to its own judgement`, and the next preferred-network look and evaluation behave as always. A trial network without internet at the verdict is not held, `manual trial: OfficeNet measured 0 kbps and fails the internet check - the hold is not taken, going back to HomeNet`, and the way back runs. The hold lives in the daemon's memory only: a restart forgets it, and a graceful stop says so, `hold on OfficeNet ends with this stop - the next start judges on its own`. A join never carries a hold.

`join` verifies the MAC and decrypts, refuses a password outside 8 to 63 characters (or 64 hex digits) or one carrying a tab or newline, then adds the network at run time only: on wpa `add_network`, the SSID as hex, the password over stdin, `scan_ssid 1`, `enable_network`, never `save_config`; on nm a keyfile in `/run` named `awacs-join-<epoch>-<pid>` with autoconnect off, never `nmcli device wifi connect`. A marker `/run/awacs/join_id` covers the attempt, so a daemon restarted mid-join removes the unfinished entry with its own line. Once the link delivers internet the password is right: it is appended to `/etc/awacs.networks` (root 0600, one line `<hexssid>\t<psk>` per network; a newer password for the same name replaces the older line) before anything else, on nm the persistent profile `awacs-joined-<hexssid>` (autoconnect on, still in `/run`) takes over from the trial entry, the list is republished so the row turns known, and the 15 s trial decides `joined` or `returned`. The password is kept either way, because the owner asked that a password that works be kept; a password that fails is removed with its entry and never written anywhere. At every start, and after the recovery rungs that restart the supplicant or NetworkManager, every network in `/etc/awacs.networks` whose SSID has no profile yet is re-added, said once as `re-added N networks joined from the site: NAME, ...`. Nothing in `wpa_supplicant.conf` or under `/etc/NetworkManager` is ever written.

Two things follow from a site that needs no login, and both are stated rather than solved. The relay's long poll is a plain GET: whoever fetches it first consumes a pending command, exactly as a shutter press on such a site works today. And the password passes through the site once, encrypted with a key that the device registered over the same unauthenticated endpoint: the registration is pinned (a rotation needs proof), so an outsider cannot swap the key later, but one who reaches the endpoint before the device ever registers holds the key the site will use; the device then sees `403` at every start and says so, which is the owner's cue to reset the key on the site. Keep the endpoint restricted as [SECURITY.md](../../SECURITY.md) asks.

## The shipped receivers

`server/receiver.php` and `server/receiver.py` implement the contract with no database and no dependencies. Where they route by path (the Python receiver and PHP's router mode), the device id must be letters, digits, `_` and `-` up to 32 characters, the rule the daemon applies to `DEVICE_ID`. Both append `log/log.txt` and keep it under 256 KB: once the file passes 512 KB the newest 256 KB survive and the partial first line is dropped. Both overwrite `tmp/wifi.tmp` through a temporary file and a rename. Both accept four file names (`ALLOWED_FILES` in the PHP receiver, `ALLOWED` in the Python one): `log/log.txt` to append, `tmp/wifi.tmp`, `tmp/wifi_scan.tmp` and `tmp/wifi_state.tmp` to overwrite; any other name is answered `403`. Both take the `wifi_key` registration exactly as described under [The device key](#the-device-key): the first key is stored, the same key again answers `200` without a write, a different key needs a valid `proof` or gets `403 Error: proof required`, and anything but 64 lowercase hex gets `400 Error: bad key`. The key lands in `private/wifi.key` under the device's data directory with mode 0600, never under a name the device could also write as a file. Under Apache the PHP receiver's data sits inside the docroot, so it writes a `.htaccess` with `Require all denied` (Apache 2.4) into that `private/` directory once; under nginx deny `/<device-id>/private/` in the server block yourself. A receiver of your own that leaves `tmp/wifi_scan.tmp` out makes the daemon say `wifi scan list not accepted by the site (http 403) - the list behind the WiFi box will not show` once per refusal episode and retry every minute; `wifi scan list accepted again` closes the episode. One that answers `403` to `wifi_key` costs one `the site holds another key for this camera ...` line per boot. Both answer `400 Error: too large` when `data` exceeds 64 KB, `500 Error: write failed` when the disk write fails, and `400 Error: no operation` to GET.

`server/receiver.php` (PHP 7.4 or newer) has two hosting modes. Behind Apache or nginx, copy it to `<docroot>/<device-id>/receiver.php`, or to the name set in `SITE_API`; the data lands beside it in `<device-id>/log/log.txt` and `<device-id>/tmp/wifi.tmp`, so the web server user needs write access to that directory. `SITE_URL` is then the docroot URL. Under PHP's built-in server the file is the router for every device id:

```sh
php -S 0.0.0.0:8080 server/receiver.php
```

In that mode it answers `/<device-id>/receiver.php`, keeps the data in `server/data/<device-id>/` and answers `404 Error: not found` to any other path. The built-in server started with a document root instead (`php -S 0.0.0.0:8080 -t <docroot>`) serves the file like Apache or nginx do, and the data lands beside it.

`server/receiver.py` (Python 3, standard library) is one process for every device id:

```sh
python3 server/receiver.py --port 8080 --data /srv/awacs-data
```

The defaults are `--host 0.0.0.0` and `--port 8080`; `--data` defaults to the `data` directory beside the script, and `--quiet` drops the per-request line. Files land in `/srv/awacs-data/<device-id>/log/log.txt` and `/srv/awacs-data/<device-id>/tmp/wifi.tmp`. A path not shaped `/<device-id>/receiver.php` answers `404 Error: not found`; a body over 8 MB answers `413 Error: too large`.

On the device:

```sh
SITE_URL="https://example.org"       # or http://<host>:8080 for the built-in servers
LOG_TARGET="both"
```

Check from any machine; `400` is the expected answer:

```sh
curl -s -o /dev/null -w '%{http_code}\n' --data-urlencode probe=1 https://example.org/mydevice/receiver.php
```

Neither receiver authenticates: anyone who can reach the URL can append to the log and overwrite the cell. Put the receiver behind HTTPS and restrict who can POST to it (an IP allow-list, a reverse-proxy secret header, a client certificate); [SECURITY.md](../../SECURITY.md) has the details.

## Reading the files from a dashboard

`log/log.txt` is append-only, newest line last; show its tail. Escape the text before rendering it: the SSID inside a line is chosen by whoever runs the access point.

`tmp/wifi.tmp` is one line, rewritten every six healthy ticks (about 60 to 80 s with the defaults) while online and not at all while the internet is down, so the file's age is the liveness signal: hide the cell when the file is older than about 180 s (three missed writes). Show the speed only when the first field is not `0`. Split on the first four commas only; the SSID may contain right-to-left text, so isolate its direction when rendering (`<bdi>` in HTML).

`tmp/wifi_scan.tmp` is rewritten only when the radio was really scanned, so its age is not a liveness signal: show the time on its first line as the scan's time. Split each following line on tabs, at most six fields; the name may contain right-to-left text (`<bdi>`), and the third and fourth fields may be empty, which means the daemon has not measured that network since it started. The fifth field says whether the device knows the network (`1`) or not (`0`), and the sixth is the SSID as lowercase hex: a menu that offers a switch on a known row and a join on an unknown one names the network by that key. A row with fewer fields comes from an older daemon; treat it as known with no key. The rows are already strongest first and never more than 12.

`tmp/wifi_state.tmp` is one line, the device's latest answer to a site command (the shape and the states are under [The command answer](#the-command-answer)). Its age means nothing; compare the second field with the epoch of the command the page sent and show the state only when they match, wording the kbps fields in the page's own units. The reason tokens after `failed` are meant to be worded by the page, not shown raw.

## Your own endpoint

An existing site keeps the device unchanged by implementing the replies of the contract at `${SITE_URL}/${DEVICE_ID}/${SITE_API}` and by having `SITE_API` set to its file name. The `400` for a POST without `file` is the part that must not change: it is the daemon's reachability signal. `tmp/wifi_state.tmp` and `wifi_key` matter only to a site that sends commands; a site without a WiFi menu may answer `403` to both, at the cost of one key line per boot, or accept the registration to keep the log clean.

To keep the log on one server and the probe elsewhere, set `PROBE_URL`. The probe target only has to accept a POST body of `PROBE_KB` KB and answer with an HTTP status; the internet rung still uses the endpoint's `400`.

## Local-only operation

With `SITE_URL` empty nothing above is used: no request reaches a site, the internet check has three rungs, and the daemon runs in signal mode (no upload measurement; when the internet is lost the strongest stored network that delivers internet wins). `LOG_TARGET` set to `both` or `remote` without `SITE_URL` is downgraded to `local` with a warning in the log, and `REPORT_WIFI=yes` without `SITE_URL` sends nothing. `PROBE_URL` alone enables the upload measurement and nothing else. The local log is `/var/log/awacs.log`, one line per event in the form `yyyy-mm-ddThh:mm:ss+hh:mm [LEVEL] message`, in the language `LOG_LANG` selects (`en` by default); any tool that tails a file can consume it.
