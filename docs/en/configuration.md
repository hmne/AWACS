# Configuration

One file holds every setting: `/etc/awacs.conf`. A knob that is not written there keeps the default built into `awacs.sh`. The template `awacs.conf.example` in the repository root lists every knob on one line with its default and its allowed values, all commented out; `install.sh` writes only the reporting knobs and the `SAFETY_NET` lines you gave it. This page is the full explanation: for each knob, what it does, what it interacts with, the log lines that belong to it, when to change it, and an example.

## Loading

The daemon reads the settings file only when it runs as root. `awacs.sh check` and `awacs.sh help` run without root and therefore on the built-in defaults; every other toolbox word runs as root and reads the file the same way the daemon does. The environment variable `AWACS_CONF` names another file; the default is `/etc/awacs.conf`. A file that does not exist is skipped, and the daemon says so once at start, after the `reporting:` line: `settings file ${AWACS_CONF} not found - running on built-in defaults (no site, no emergency networks)` (WARN; with no file there is no `SITE_URL`, so the line stays in the local log unless the environment supplies one).

Because the file is executed as root and holds hotspot passwords, two checks guard it. It must be owned by root, and `0600` is the documented mode; the check refuses only a read or write bit for group or others (execute bits are not looked at), so `0400` and `0700` also pass, while `0640`, `0644` and `0660` are refused. A refused file is announced on standard error at once, and the daemon then runs entirely on defaults:

- `awacs: IGNORING ${AWACS_CONF} (group/world can access it — chmod 600 it)`
- `awacs: IGNORING ${AWACS_CONF} (not owned by root — chown root: it)`

On a terminal the message is visible; under systemd it lands in the journal; under the `rc.local` launch line, which discards output, it is not seen anywhere, so check the owner and mode by hand after editing the file from another account.

The daemon repeats the verdict once in the log at start, after the `reporting:` line, as a WARN story line, so it is seen where the stderr print is not (the mode is the octal mode found, for example `644`):

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] settings file ${AWACS_CONF} ignored: mode ${mode}, chmod 600 it - running on built-in defaults (no site, no emergency networks)`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] settings file ${AWACS_CONF} ignored: not owned by root, chown root: it - running on built-in defaults (no site, no emergency networks)`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] settings file ${AWACS_CONF} not found - running on built-in defaults (no site, no emergency networks)`

A refused or missing file leaves `SITE_URL` empty, so these lines reach the site only when the environment carries a `SITE_URL`; the local log always has them.

The file is sourced by bash, so it must hold plain assignments only: `KEY=value`, `KEY="value"` and `SAFETY_NET["Name"]="password"`. No `readonly` and no `declare`, because the validation step must be able to rewrite a value; no `unset`; no commands and no `$(...)`, because any other code in the file runs as root and nothing stops it. To keep a default, leave the line commented out rather than unsetting the knob. After loading and validation every knob is sealed read-only; nothing changes it at run time except the day and night working copies described under the night profile. The file is read once at each start, by the daemon and by every toolbox word that runs as root alike, so a change takes effect at the next daemon restart.

## Validation

Every value is checked once at start. A bad value falls back to the default, and the daemon names the knobs that fell back once at start, after the `reporting:` line (names only, never values); a clean start says nothing. The `LOG_TARGET` downgrade at the end of this list has a line of its own.

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] settings file ${AWACS_CONF} applied, but ${n} values failed validation and use their defaults: ${names}` (comma-separated knob names, for example `TICK, NIGHT_START, SITE_TZ`; for `SITE_URL`, `PROBE_URL` and `SITE_TZ` an empty value is a choice and is not counted, only a non-empty value that fails its check is)

Numbers. Seventeen knobs are numeric: `TICK`, `NET_FAIL_TICKS`, `ASSOC_WAIT`, `PREF_CHECK`, `REBOOT_AFTER_MIN`, `PROBE_KB`, `MIN_UP_KBPS`, `UP_STRIKES`, `SWITCH_GAIN_PCT`, `DANCE_COOLDOWN`, `STREAM_MIN_KBPS`, `NIGHT_MIN_UP_KBPS`, `NIGHT_GAIN_PCT`, `NIGHT_DANCE_COOLDOWN`, `LOG_CAP`, `SCAN_TTL` and `SPOOL_CAP`. Each must match `^0*[1-9][0-9]{0,6}$`: a whole number from 1 to 9999999. Leading zeros are accepted and dropped (`08` becomes 8, stored as a decimal number). Zero, an empty or unset value, a negative number, a decimal, text or more than seven significant digits restores the default. Zero is refused for all of them because it is meaningless for each (a zero tick would spin the loop; a zero spool cap breaks the first-line rule), and very long numbers because they would overflow into negative or endless sleeps.

Clock times. `NIGHT_START` and `NIGHT_END` must match `^([01]?[0-9]|2[0-3]):[0-5][0-9]$`: hour 0 to 23 with one or two digits, a colon, minutes 00 to 59 with two digits. Each falls back to its own default (`22:00`, `06:00`) independently.

Mode words. These are exact and case-sensitive. `LOG_TARGET` accepts `local`, `both` or `remote`, else `local`. `REPORT_WIFI` accepts `auto`, `yes` or `no`, else `auto`. `LOG_LANG` and `SITE_LANG` accept `en` or `ar`, else `en`.

Switches. `OPEN_NETWORKS`, `NIGHT_MODE`, `STEALTH_MODE` and `DEBUG` are never rewritten. Each is compared with the exact lowercase word `yes` at the one place it is used; any other value, `Yes`, `true`, `1` and an empty value included, means off, with no fallback and no warning.

Addresses and names. `SITE_URL` must match `^https?://[^[:space:]/]+(/[^[:space:]]*)?$`: `http` or `https`, a host without spaces or slashes, an optional path without spaces; anything else becomes empty, which means local-only operation. One trailing slash is dropped when the site address is built. `PROBE_URL` must match `^https?://[^[:space:]]+$`, else empty. `SITE_TZ` must match `^[A-Za-z0-9/_+-]{0,64}$`, else empty; only the shape is checked here; whether the device knows the zone is checked once at start and reported under [SITE_TZ](#site_tz). `SITE_API` must match `^[A-Za-z0-9_][A-Za-z0-9_./-]{0,63}$` and must not contain `..` (so it cannot escape the device folder); anything else, an empty value included, becomes `receiver.php`.

Paths. `RUN_DIR` must begin with `/`, else `/run/awacs`; every runtime file lives under it, so changing it moves them all together. `LOG_FILE` is not checked at all: no test that the path is absolute, no test that it exists, and no fallback.

Emergency networks. `SAFETY_NET` entries are not checked when the file is loaded; each entry is checked when it is tried (see [Emergency networks](#emergency-networks)).

The downgrade. `LOG_TARGET` set to `both` or `remote` while `SITE_URL` is empty (never set, or emptied by the shape check) is set back to `local`, and the daemon says so once at start:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] LOG_TARGET asked for the site but SITE_URL is empty - running local-only`

## Applying changes

```sh
sudo cp awacs.conf.example /etc/awacs.conf
sudo chown root:root /etc/awacs.conf && sudo chmod 600 /etc/awacs.conf
sudo nano /etc/awacs.conf
```

Then restart the daemon (see [install.md](install.md#stopping-and-restarting)). Every start opens with the same lines. The first is a story line, `AWACS ${VERSION} starting on ${IF} (device ${DEVICE_ID}) - ${backend} backend, ${tail}`; it follows `LOG_TARGET` like every story line, so under `remote` it goes to the site only. The backend is `wpa` or `NetworkManager`; the tail is `first start of this boot, up ${uptime}` (the uptime as `45 s`, `3 min`, `2 h 15 min` or `3 d 4 h`) or `restart ${n} of this boot` when a launcher brought the daemon back in the same boot (the count lives in `RUN_DIR/starts`, so it begins again at every boot). The second is the confirmation: it is written straight to the local log, in English whatever the settings, is never sent to the site, and shows the reporting settings as the daemon loaded them:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] reporting: ${LOG_TARGET} -> ${SITE_URL} | probe: ${probe target} | wifi cell: ${REPORT_WIFI} | lang: local ${LOG_LANG}, site ${SITE_LANG}`

The ` -> ${SITE_URL}` part is present only when `SITE_URL` is set and shows the value as written in the file. The probe part is the address the upload probe uses, or the words `none - signal mode` when there is none. A mistyped `SITE_URL` shows up here: because the shape check empties it (and names `SITE_URL` in the fallen-knobs line), the line then reads `reporting: local` and, unless `PROBE_URL` is set, `probe: none - signal mode`. With every knob at its default the line reads:

`${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] reporting: local | probe: none - signal mode | wifi cell: auto | lang: local en, site en`

After the confirmation line the daemon says what it read, once per start: the settings verdict when the file was not applied (the three WARN lines under [Loading](#loading)); the knobs that fell back, when any did (`settings file ${AWACS_CONF} applied, but ${n} values failed validation and use their defaults: ${names}`, names only, never values); `wifi cell asked for (REPORT_WIFI=yes) but SITE_URL is empty - nothing to publish to` when that pair is set; the time-zone and device-id checks described under [SITE_TZ](#site_tz) and [DEVICE_ID](#device_id); and then one INFO line with the working settings, in the form the decisions that follow will use:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] running with: measured mode, floor ${MIN_UP_KBPS}/${NIGHT_MIN_UP_KBPS} kbps day/night (night ${NIGHT_START}-${NIGHT_END}), switch gain ${SWITCH_GAIN_PCT}%, one evaluation per ${minutes} min, reboot after ${REBOOT_AFTER_MIN} min wedged, wifi cell ${on|off (REPORT_WIFI=no)|off (no SITE_URL)|off (auto with LOG_TARGET local)}, ${n} stored networks, ${m} emergency, open networks ${yes|no}, stamps in ${SITE_TZ|the device zone}`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] running with: signal mode (no probe target - networks chosen by signal), reboot after ${REBOOT_AFTER_MIN} min wedged, wifi cell ${on|off (REPORT_WIFI=no)|off (no SITE_URL)|off (auto with LOG_TARGET local)}, ${n} stored networks, ${m} emergency, open networks ${yes|no}, stamps in ${SITE_TZ|the device zone}` (no `SITE_URL` and no `PROBE_URL`)

With `NIGHT_MODE` off the floor part reads `floor ${MIN_UP_KBPS} kbps (night profile off)`. The minutes are `DANCE_COOLDOWN` in whole minutes, rounded up. The stored count is the number of distinct stored networks the backend lists at that moment (0 with a mute supplicant or a missing `nmcli`); the emergency count is the number of `SAFETY_NET` entries, never their names. No address appears in the line. With a site, `LOG_TARGET=both`, three stored networks and every other knob at its default the line reads: `running with: measured mode, floor 400/200 kbps day/night (night 22:00-06:00), switch gain 150%, one evaluation per 20 min, reboot after 30 min wedged, wifi cell on, 3 stored networks, 0 emergency, open networks yes, stamps in the device zone`.

In the log lines quoted on this page, `${...}` marks a value the daemon fills in. Local lines have the shape `yyyy-mm-ddThh:mm:ss+hh:mm [LEVEL] text`; lines sent to the site have the shape `yyyy-mm-ddThh:mm:ss+hh:mm [LEVEL][awacs] text`. Story lines are written locally in the `LOG_LANG` language and sent to the site in the `SITE_LANG` language; the text quoted on this page is their English form.

## Reporting

Where the daemon's story goes, how it measures upload speed, and in which language and time zone the site reads it. All site traffic is an HTTP POST to one address, `SITE_URL/DEVICE_ID/SITE_API`, and that address receives five kinds of request: the story lines (two form fields, `file=log/log.txt` and `data=` followed by the line, under a 4-second limit), the WiFi cell (`file=tmp/wifi.tmp` and `data=` followed by `kbps,visible,total,band,SSID`, under a 4-second limit), the WiFi scan list (`file=tmp/wifi_scan.tmp` and `data=` followed by the list text, under a 4-second limit), the upload probe (a raw body of `PROBE_KB` kilobytes under a 15-second limit; the reply is not inspected, only the transfer speed) and the last step of the internet check (a request carrying `probe=1` that must be answered with HTTP 400 and nothing else, under a 3-second limit in the quick form of the check and an 8-second limit in its patient form, which is how captive-portal pages answering 200 or 302 are rejected). The shipped receivers `server/receiver.php` (PHP 7.4 or newer, no dependencies) and `server/receiver.py` (Python 3, standard library only) answer this contract for any device id; [integration.md](integration.md) has the details. The toolbox words (`status`, `networks`, `evaluate`, `scan`, `speed` and `check`) never send story lines, the WiFi cell or the scan list; `status` and `check` do run the internet check, in its quick form only, with its endpoint step when a loaded `SITE_URL` gives it one, and `speed` uploads one probe body to the probe target.

### SITE_URL

Default: `""` (empty)

Allowed: `http://host` or `https://host`, an optional `:port`, an optional `/path`; no spaces anywhere and no slash inside the host; anything else becomes empty, and empty means local-only

Unit: URL

The base address of the reporting site. Every request the daemon sends to the site goes to one address built from it: `SITE_URL/DEVICE_ID/SITE_API`. That address receives the story lines, the WiFi cell, the upload probe body (unless `PROBE_URL` points elsewhere) and the last step of the internet check, a POST with `probe=1` that the endpoint must answer with HTTP 400. Empty means local-only: no site traffic at all, the log file is the only output, the last internet-check step does not exist and, with `PROBE_URL` also empty, the daemon runs in signal mode (see [Signal mode](#signal-mode)). A value of the wrong shape is emptied and `SITE_URL` is named in the fallen-knobs line at start; the `reporting:` line then shows `local`.

Setting `SITE_URL` while `LOG_TARGET` stays `local` turns on the upload probe and the internet-check step but sends no story lines and, with `REPORT_WIFI=auto`, no WiFi cell. `LOG_TARGET` `both` and `remote` take effect only when `SITE_URL` is set. `PROBE_URL`, when set, replaces the site endpoint as the probe target. `REPORT_WIFI=yes` publishes the cell whenever `SITE_URL` is set, even with `LOG_TARGET=local`; `auto` needs `both` or `remote` as well. `DEVICE_ID` is the folder in the path and `SITE_API` the file after it. The offline spool (`SPOOL_CAP`) only fills when `SITE_URL` is set and `LOG_TARGET` is `both` or `remote`. A site that refuses or does not answer a line while the internet is up is reported once per episode, and every delivery of held lines is reported after the lines themselves (below).

Log lines:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] reporting: ${LOG_TARGET} -> ${SITE_URL} | probe: ${probe target} | wifi cell: ${REPORT_WIFI} | lang: local ${LOG_LANG}, site ${SITE_LANG}`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] LOG_TARGET asked for the site but SITE_URL is empty - running local-only`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] running with: measured mode, floor ${MIN_UP_KBPS}/${NIGHT_MIN_UP_KBPS} kbps day/night (night ${NIGHT_START}-${NIGHT_END}), switch gain ${SWITCH_GAIN_PCT}%, one evaluation per ${minutes} min, reboot after ${REBOOT_AFTER_MIN} min wedged, wifi cell ${on|off (REPORT_WIFI=no)|off (no SITE_URL)|off (auto with LOG_TARGET local)}, ${n} stored networks, ${m} emergency, open networks ${yes|no}, stamps in ${SITE_TZ|the device zone}` (the working settings, once per start; see [Applying changes](#applying-changes); no address in it)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] site did not take the log line (${reply}) - holding lines, delivery retried about every ${minutes} min` (once per episode, when a line's POST gets a reply outside 2xx and 3xx while the internet is up; the reply reads `http ${code}` or `no reply in 4 s`; the refused line and this one wait in the spool; the minutes are 30 passes of `TICK`, 5 with the default)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] delivered ${n} held lines stamped ${first} to ${last} - they stand above this line with their own times` (after every delivery of held lines, sent in the foreground after them, except the start flush of a start that held only its own start lines; `delivered 1 held line stamped ${first} - it stands above this line with its own time` for a single line; the stamps are `HH:MM`)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [OK] site reachable again - delivered ${n} held lines stamped ${first} to ${last}, they stand above this line with their own times` (the delivery that ends a refusal episode, when every held line went out; `site reachable again - delivered 1 held line stamped ${first}, it stands above this line with its own time` for a single line)

When to change it: set it as soon as a receiver or the full site exists for this device; leave it empty for a device that should only keep a local log and needs no upload measurement.

A device whose id is `mydevice` then posts everything to `https://example.org/mydevice/receiver.php`.

```sh
SITE_URL="https://example.org"
```

### SITE_API

Default: `"receiver.php"`

Allowed: 1 to 64 characters; the first a letter, digit or underscore, the rest letters, digits, underscore, dot, slash or hyphen; no `..` (no escape from the device folder); anything else, an empty value included, becomes `receiver.php`

Unit: file name, sub-folders allowed

The endpoint file name appended after the device folder: `SITE_URL/DEVICE_ID/SITE_API`. This is the only address the daemon talks to on the site, and it receives five kinds of request: story lines (form fields `file=log/log.txt` and `data=` followed by the line), the WiFi cell (`file=tmp/wifi.tmp` and `data=` followed by `kbps,visible,total,band,SSID`), the WiFi scan list (`file=tmp/wifi_scan.tmp` and `data=` followed by the list text), the upload probe (a raw POST body of `PROBE_KB` kilobytes, only while `PROBE_URL` is empty) and the internet-check request (a POST with `probe=1`, to be answered with HTTP 400). The shipped receivers in `server/` (one in PHP 7.4 or newer with no dependencies, one in Python 3 with the standard library only) answer this contract for any device id; [integration.md](integration.md) describes the contract itself.

It has no effect while `SITE_URL` is empty. `DEVICE_ID` is the folder before it. `PROBE_URL` bypasses it for the probe only; the story lines, the WiFi cell and the internet check always use it.

Log lines:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] reporting: ${LOG_TARGET} -> ${SITE_URL} | probe: ${SITE_URL}/${DEVICE_ID}/${SITE_API} | wifi cell: ${REPORT_WIFI} | lang: local ${LOG_LANG}, site ${SITE_LANG}` (the endpoint appears in the probe part only while `PROBE_URL` is empty)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] site did not take the log line (http ${code}) - holding lines, delivery retried about every ${minutes} min` (the endpoint's own reply to a story line, once per episode; `no reply in 4 s` when nothing came within the limit)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] wifi cell not accepted by the site (http ${code}) - the page drops the cell when it goes stale` (the endpoint's reply to the WiFi cell, once per episode)

When to change it: when your site's endpoint is not called `receiver.php`: the full site's own endpoint name, or a receiver kept under another path, for example one folder down.

The site keeps its endpoint one folder down, so the device posts to `SITE_URL/mydevice/api/receiver.php`.

```sh
SITE_API="api/receiver.php"
```

### LOG_TARGET

Default: `"local"`

Allowed: `local`, `both` or `remote`; any other word becomes `local`; `both` and `remote` need `SITE_URL` (with it empty, or emptied by the shape check, the value is forced back to `local` and the daemon says so once at start)

Unit: mode word

Where the story lines go. `local`: the log file only. `both`: the log file and the site. `remote`: the site only, except that WARN and ERROR story lines are still written to the local file. Lines that are not story lines are always written locally whatever this says: DEBUG diagnostics, the `reporting:` line at start, the downgrade warning, the scan warnings raised by a hand-run toolbox word, and three internal error lines. The line written before a reboot the daemon orders is a story line: it is held in a copy of the spool saved beside the log and delivered after the boot (see [REBOOT_AFTER_MIN](#reboot_after_min)). In `both` and `remote`, a line that cannot be sent (offline, or a failed send) is kept in a spool file and delivered in order once the internet is back; delivery stops at the first failed send and the rest waits for the next attempt. The spool holds `SPOOL_CAP` lines and its first line is always kept. A refusal while the internet is up is said once per episode, every delivery of held lines is announced after them, and lines the cap dropped are counted and said once the story is out in full.

Needs `SITE_URL`; without it the value is forced back to `local` and the daemon says so once. `REPORT_WIFI=auto` follows it: the cell is sent only in `both` or `remote`. `SPOOL_CAP` bounds the offline story. DEBUG lines are never sent to the site and never dropped by `remote`. `LOG_LANG` still picks the language of what `remote` leaves in the local file.

Log lines:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] reporting: ${LOG_TARGET} -> ${SITE_URL} | probe: ${probe target} | wifi cell: ${REPORT_WIFI} | lang: local ${LOG_LANG}, site ${SITE_LANG}`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] LOG_TARGET asked for the site but SITE_URL is empty - running local-only`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] running with: ... wifi cell off (auto with LOG_TARGET local) ...` (the start summary; the cell part reads so when `REPORT_WIFI=auto` and this knob is `local`; the full line is under [Applying changes](#applying-changes))
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] site did not take the log line (${reply}) - holding lines, delivery retried about every ${minutes} min` (once per episode; see [SITE_URL](#site_url))
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] delivered ${n} held lines stamped ${first} to ${last} - they stand above this line with their own times` (after every delivery of held lines, except a start flush that held only the start's own lines; `delivered 1 held line stamped ${first} - it stands above this line with its own time` for one)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [OK] site reachable again - delivered ${n} held lines stamped ${first} to ${last}, they stand above this line with their own times` (the delivery that closes a refusal episode)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] outage story trimmed - ${n} lines dropped from its middle (the spool keeps ${SPOOL_CAP})` (once per outage, after the delivery line of the flush that sent the whole story)

When to change it: set `both` once a site exists and you still want a copy on the SD card; set `remote` when the site is the record and the local file should keep only warnings and errors.

The site gets the full story while the SD card keeps a copy for troubleshooting offline.

```sh
LOG_TARGET="both"
```

### PROBE_URL

Default: `""` (empty: the site endpoint `SITE_URL/DEVICE_ID/SITE_API`, or signal mode when `SITE_URL` is empty too)

Allowed: any `http://` or `https://` address without spaces, used exactly as written, with nothing appended; anything else becomes empty

Unit: URL

Where the upload probe sends its test body. The probe uploads `PROBE_KB` kilobytes of zeros with `curl` under a 15-second limit and reads curl's own upload-speed figure. If `curl` is missing or reports zero, `wget` posts the same bytes from a temporary file and the elapsed time gives the figure; if `wget` is missing too, the figure is 0 and the probe is reported as failed (the WARN line below). The server's reply is not inspected, only the transfer speed, so any server that accepts a POST body works; with the wget fallback a 4xx or 5xx reply still counts as a completed upload, and only a transport failure or a timeout reads as 0. Empty means the site endpoint is used, so a site alone gives measurement. When both `PROBE_URL` and `SITE_URL` are empty there is nowhere to upload to and the daemon runs in signal mode.

`SITE_URL` supplies the fallback target and `PROBE_KB` the body size. In signal mode `MIN_UP_KBPS`, `UP_STRIKES`, `SWITCH_GAIN_PCT`, `DANCE_COOLDOWN`, `STREAM_MIN_KBPS` and the three night figures (`NIGHT_MIN_UP_KBPS`, `NIGHT_GAIN_PCT` and `NIGHT_DANCE_COOLDOWN`) take no part in any decision, because there is no measurement to compare; the day and night profile lines are still logged. `awacs.sh speed` probes this same target. `PROBE_URL` alone, with no `SITE_URL`, gives measured network choice with no reporting.

Log lines:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] reporting: ${LOG_TARGET} | probe: ${PROBE_URL} | wifi cell: ${REPORT_WIFI} | lang: local ${LOG_LANG}, site ${SITE_LANG}`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] reporting: local | probe: none - signal mode | wifi cell: ${REPORT_WIFI} | lang: local ${LOG_LANG}, site ${SITE_LANG}` (both addresses empty)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] measured ${kbps} kbps on ${SSID}`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] measured ${kbps} kbps on ${SSID} - above the ${floor} kbps floor, staying`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] trying ${SSID}`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] could not connect to ${SSID}: ${reason} - trying the next` (the reasons are listed under [ASSOC_WAIT](#assoc_wait))
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [OK] connected: ${SSID} (signal mode - no upload probe target configured)`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [OK] returned to preferred network: ${SSID} (signal mode)`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] running with: signal mode (no probe target - networks chosen by signal), reboot after ${REBOOT_AFTER_MIN} min wedged, wifi cell ${on|off (REPORT_WIFI=no)|off (no SITE_URL)|off (auto with LOG_TARGET local)}, ${n} stored networks, ${m} emergency, open networks ${yes|no}, stamps in ${SITE_TZ|the device zone}` (the start summary with both addresses empty)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] upload probe failed on ${SSID} - the probe target accepted nothing (site or endpoint down?), counting it as 0 kbps` (in place of the `measured` or `candidate` line when the target took no bytes, with curl and with the wget fallback; the decision counts the probe as 0)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] measured ${kbps} kbps on ${SSID} - under the ${floor} kbps floor, a challenger must beat ${bar} kbps` (the evaluation's baseline when it is under the floor; the bar is the measurement times the gain, divided by 100)

When to change it: when uploads should be measured against a different host than the reporting site (a nearer server, or a plain sink), or when you want measured network choice without running any site.

Uploads are measured against a dedicated sink instead of the reporting site.

```sh
PROBE_URL="https://probe.example.org/sink"
```

### REPORT_WIFI

Default: `"auto"`

Allowed: `auto`, `yes` or `no`; any other word becomes `auto`

Unit: mode word

Whether the daemon publishes the WiFi cell to the site: one line of the form `kbps,visible,total,band,SSID`, posted as `file=tmp/wifi.tmp` to the site endpoint. `auto`: only when story lines also go to the site (`SITE_URL` set and `LOG_TARGET` `both` or `remote`). `yes`: whenever `SITE_URL` is set, even with `LOG_TARGET=local`. `no`: never. Without `SITE_URL` nothing is sent in any mode (`yes` without `SITE_URL` is reported once at start). The cell goes out from the main loop only while the internet is verified, on the first healthy pass and then every sixth healthy tick (about 60 to 80 s with the defaults), in the background, and never from monitor-only mode (a NetworkManager image the daemon cannot drive). `total` is the number of stored networks and `visible` those of them on the air; both come from the existing scan picture (NetworkManager's own list on that backend, without a rescan), so no radio work is caused. On wpa, before any scan has run in this boot, the visible names come from the supplicant's own table; and a device associated to one of its stored networks never reports fewer than one visible. `kbps` is the last measured upload speed, sent only if it was measured on the network the device is on now, otherwise 0 (always 0 in signal mode). `band` is `2.4GHz`, `5GHz` or `6GHz` from the live link frequency and empty when it cannot be read. The name comes last so its own commas survive, and a dash stands in when there is none.

The same knob gates the WiFi scan list, `file=tmp/wifi_scan.tmp`: the networks the radio heard, for the list behind the site's WiFi box. It is decided in the main loop on the cell's minute and posted in the background, at most once per 60 seconds and only when a new scan exists: on wpa a scan that really hit the radio (the daemon's own scan, its tool fallback, or the verdict that the radio heard nothing, which publishes an empty list); on NetworkManager its own table, read without a rescan, when its rows changed. A served cache is never republished, and a refused list is retried every minute. The text is the scan's unix time on the first line, then one line per network, strongest first, at most 12, with six tab-separated fields: the display name, the signal in dBm (on NetworkManager converted from its percent, 100 % at -40 dBm and 0 % at -100), the upload measured on that network while this process ran, the unix time of that measurement (both empty when never measured), `known` (`1` for a stored network, `0` otherwise) and the SSID as lowercase hex, the key a site command names the network by. The speeds are the daemon's own upload probes of a named network (the incumbent at an evaluation, each candidate, the preferred network on arrival, a temporary network that won) and live for the process; a probe the target refused is not remembered. The list is never sent from the toolbox words.

It depends on `SITE_URL` (nothing is sent without it), on `LOG_TARGET` (`auto` follows it), on `TICK` (which sets the cadence), on `SCAN_TTL` (how fresh the visible count is), on `PROBE_URL` and signal mode (`kbps` stays 0), and on a network change since the last measurement (`kbps` is shown as 0). The request is `file=tmp/wifi.tmp` with `data=${kbps},${visible},${total},${band},${SSID}`, and the setting shows in the `reporting:` line at start as `wifi cell: ${REPORT_WIFI}`.

Log lines:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] reporting: ${LOG_TARGET} -> ${SITE_URL} | probe: ${probe target} | wifi cell: ${REPORT_WIFI} | lang: local ${LOG_LANG}, site ${SITE_LANG}` (the setting shows in the `wifi cell:` part; no line is written per send)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] running with: ... wifi cell ${on|off (REPORT_WIFI=no)|off (no SITE_URL)|off (auto with LOG_TARGET local)} ...` (the start summary names the cell state as applied)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] wifi cell asked for (REPORT_WIFI=yes) but SITE_URL is empty - nothing to publish to` (once at start; local log only, since there is no site)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] wifi cell not accepted by the site (${reply}) - the page drops the cell when it goes stale` (once per episode, when the cell's POST gets a reply outside 2xx and 3xx; the reply reads `http ${code}` or `no reply in 4 s`; later refusals are silent)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [OK] wifi cell accepted again` (the first accepted cell after a refusal)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] wifi scan list not accepted by the site (${reply}) - the list behind the WiFi box will not show` (once per episode, when the list's POST gets a reply outside 2xx and 3xx; the reply reads `http ${code}` or `no reply in 4 s`; the post is retried every minute, silently)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [OK] wifi scan list accepted again` (the first accepted list after a refusal)

When to change it: set `no` when the site has neither the WiFi cell nor the scan list, or you want to cut the periodic requests; set `yes` when you want the cell while story lines stay local.

The site has no WiFi widget, so posting the cell every six healthy ticks (about 60 to 80 s with the defaults) is wasted traffic.

```sh
REPORT_WIFI="no"
```

### SITE_TZ

Default: `""` (empty: the device's own time zone)

Allowed: a zone name of up to 64 characters made of letters, digits, `/`, `_`, `+` and `-`, such as `Asia/Kuwait`, `Europe/Berlin` or `UTC`; anything else becomes empty

Unit: time zone name, in the tz database form

The time zone of the timestamp on the lines sent to the site. Each site line is built as `yyyy-mm-ddThh:mm:ss+hh:mm [LEVEL][awacs] text` and that stamp is taken with `TZ` set to this value. The local log uses the same stamp, so the two files read the same instant. Lines kept in the spool while offline carry the stamp of the moment they happened, not of the moment they were delivered. Only the shape of the value is checked, not that the device knows the zone: a well-shaped name the device does not know passes the check, and the site stamps then read UTC. The daemon checks an `Area/City` name against `/usr/share/zoneinfo` once at start and says so when the zone is missing (below); a POSIX string such as `KST-3` needs no file and is not checked.

Only matters when story lines go to the site (`SITE_URL` set and `LOG_TARGET` `both` or `remote`). `SITE_LANG` changes the text part of the same line, not the stamp. The WiFi cell carries no timestamp. The night window (`NIGHT_START`, `NIGHT_END`) follows the device clock, not this zone.

Log lines:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [${LEVEL}][awacs] ${text}` (the line as sent to the site; the same event is written locally as `${yyyy-mm-ddThh:mm:ss+hh:mm} [${LEVEL}] ${text}` in the device zone)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] time zone ${SITE_TZ} is unknown on this device (${why}) - stamps fall back to UTC` (once at start; the reason is `no such zone` or `tzdata not installed`)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] running with: measured mode, floor ${MIN_UP_KBPS}/${NIGHT_MIN_UP_KBPS} kbps day/night (night ${NIGHT_START}-${NIGHT_END}), switch gain ${SWITCH_GAIN_PCT}%, one evaluation per ${minutes} min, reboot after ${REBOOT_AFTER_MIN} min wedged, wifi cell ${on|off (REPORT_WIFI=no)|off (no SITE_URL)|off (auto with LOG_TARGET local)}, ${n} stored networks, ${m} emergency, open networks ${yes|no}, stamps in ${SITE_TZ|the device zone}` (the `stamps in` part names this zone, or `the device zone` when the knob is empty)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] clock set ${forward|back} ${delta} by time sync - the lines above carry the old time` (once per step: the device clock moved by more than 60 s between two passes against the uptime clock, as a board without a clock battery does at its first time sync; the stamps above it, in whatever zone, carry the time before the step; the delta reads `7 h 0 min` or `2 min`)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] reboot clock armed - the device reboots after ${HH:MM} unless the internet returns or the fault reads external` (the hour is in this zone)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] repeated ${n} more times during the outage (last at ${HH:MM}): ${line}` (the hour is in this zone)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] starting after the reboot AWACS ordered at ${yyyy-mm-dd HH:MM} - wedged ${REBOOT_AFTER_MIN} min (${sign}), ${runs} recovery runs before it` (the stamp in the line is in this zone)

When to change it: when the device clock runs on UTC or another zone while the person reading the site lives in a different one.

The device clock runs on UTC while the dashboard is read in Kuwait.

```sh
SITE_TZ="Asia/Kuwait"
```

### LOG_LANG

Default: `"en"`

Allowed: `en` or `ar`; any other value becomes `en`

Unit: language code

The language of the story lines written to the local log file. Every story line in the script carries an English text and an Arabic text; `ar` picks the Arabic one for the local file. DEBUG diagnostics always stay English, and so do the fixed lines written straight to the file: the `reporting:` line at start, the `LOG_TARGET` downgrade warning and the three internal error lines. The choice is independent of `SITE_LANG`: the local file and the site can be in different languages.

`SITE_LANG` is independent. DEBUG lines ignore it. With `LOG_TARGET=remote` the WARN and ERROR lines that remain in the local file still follow this language, and so do the reboot line and the scan warnings of a hand-run toolbox word.

Log lines:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] reporting: ${LOG_TARGET} -> ${SITE_URL} | probe: ${probe target} | wifi cell: ${REPORT_WIFI} | lang: local ${LOG_LANG}, site ${SITE_LANG}`

When to change it: when the person who reads `/var/log/awacs.log` on the device prefers Arabic.

The technician who reads the SD-card log reads Arabic.

```sh
LOG_LANG="ar"
```

### SITE_LANG

Default: `"en"`

Allowed: `en` or `ar`; any other value becomes `en`

Unit: language code

The language of the text in the story lines sent to the site, chosen independently of `LOG_LANG`. The stamp and the `[LEVEL][awacs]` tag at the front are the same in both languages; only the text after them changes. The WiFi cell is numbers and a network name, so it is not affected.

Only visible when story lines go to the site (`SITE_URL` set and `LOG_TARGET` `both` or `remote`). `SITE_TZ` sets the stamp on the same line. `LOG_LANG` is independent.

Log lines:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [${LEVEL}][awacs] ${text}`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] reporting: ${LOG_TARGET} -> ${SITE_URL} | probe: ${probe target} | wifi cell: ${REPORT_WIFI} | lang: local ${LOG_LANG}, site ${SITE_LANG}`

When to change it: when the dashboard is read in Arabic while the local log should stay English, or the reverse.

The dashboard is read in Arabic while the local log stays English for the technician.

```sh
SITE_LANG="ar"
```

### DEVICE_ID

`DEVICE_ID` is not a settings-file knob. It is the folder in every site address, `SITE_URL/DEVICE_ID/SITE_API`, and comes from the daemon's environment: the `export DEVICE_ID=` line in `rc.local`, or the systemd drop-in `awacs.service.d/10-device-id.conf` holding `Environment=DEVICE_ID=`. The daemon resolves it fresh every time it is needed, not once at start, because a boot script may write the id after the daemon has launched. The order is:

1. The variable `DEVICE_ID`, if set and not empty.
2. Otherwise the first non-empty line of `/tmp/device_id`.
3. The result must be 1 to 32 characters made only of letters, digits, underscore and hyphen (`^[A-Za-z0-9_-]{1,32}$`); if it is not, the short hostname (`hostname -s`) is used instead.
4. The hostname is checked against the same rule, and if it fails too the id is the word `device`.

A variable value that fails the check goes straight to the hostname; the `/tmp` file is consulted only when the variable is empty. A present value that fails the check is reported once at start; an absent id is the design and says nothing. The id is resolved again at the WiFi cell cadence, and a change is reported once. The rule exists because `/tmp` is writable by every local user and the id lands in a root terminal and in an outbound URL. The id also appears in the first line of every start and in the `device` row of `awacs.sh status`:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] AWACS ${VERSION} starting on ${IF} (device ${DEVICE_ID}) - ${backend} backend, ${tail}` (the tail is described under [Applying changes](#applying-changes))
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] device id not usable (${source}: ${value}) - reporting as ${id}` (once at start; the source is `DEVICE_ID` or `/tmp/device_id`, the value is shown with control characters removed and cut to 40 characters, the id is the hostname or `device`)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] device id changed: ${old} -> ${new} - reporting under ${new} from now` (once per change, at the WiFi cell cadence, every six healthy ticks (about 60 to 80 s with the defaults); a boot script writing `/tmp/device_id` after the daemon started produces it once)

### Deployment shapes

Local-only, no server at all. Leave the reporting block at its defaults:

```sh
# SITE_URL=""
# LOG_TARGET="local"
# PROBE_URL=""
```

The log file `/var/log/awacs.log` is the only output; no request leaves the device for reporting; the daemon runs in signal mode, choosing networks by signal strength with no upload measurement and no WiFi cell. Recovery, the outage classification, the reboot rule, the emergency networks, the open networks and the day and night profiles all work as they do with a site. The start line reads `reporting: local | probe: none - signal mode | wifi cell: auto | lang: local en, site en`. To keep measured network choice without a site, add only `PROBE_URL` pointing at any address that accepts a POST body, for example `PROBE_URL="https://probe.example.org/sink"`.

Self-hosted receiver. One of the shipped receivers in `server/`, placed on your own host so that `SITE_URL/DEVICE_ID/receiver.php` answers (see [integration.md](integration.md)):

```sh
SITE_URL="https://example.org/awacs"
SITE_API="receiver.php"
LOG_TARGET="both"
SITE_TZ="Asia/Kuwait"
```

A device whose id is `mydevice` posts to `https://example.org/awacs/mydevice/receiver.php`. Story lines go to the file and the site, the upload probe uses the same endpoint (measured network choice is on), the internet check gains its endpoint step, and the WiFi cell is posted every six healthy ticks (about 60 to 80 s with the defaults; `REPORT_WIFI=auto` with `LOG_TARGET=both`). The start line reads `reporting: both -> https://example.org/awacs | probe: https://example.org/awacs/mydevice/receiver.php | wifi cell: auto | lang: local en, site en`.

Full site. The complete site with a dashboard per device and its endpoint under its own path:

```sh
SITE_URL="https://example.org"
SITE_API="api/receiver.php"
LOG_TARGET="remote"
REPORT_WIFI="auto"
SITE_TZ="Asia/Kuwait"
LOG_LANG="en"
SITE_LANG="ar"
```

The site is the record: INFO and OK story lines go only there, while the local file keeps the WARN and ERROR story lines and the always-local lines. The site reads Arabic while the local file stays English, site timestamps are in Kuwait time, and the WiFi cell feeds the dashboard. The start line reads `reporting: remote -> https://example.org | probe: https://example.org/mydevice/api/receiver.php | wifi cell: auto | lang: local en, site ar`. Use `LOG_TARGET="both"` instead of `remote` to keep a full local copy as well.

### Signal mode

Signal mode is how the daemon runs when `PROBE_URL` and `SITE_URL` are both empty. There is nowhere to upload a test body, so upload speed is never measured and networks are never compared by speed.

What still runs: the internet check every pass (without its endpoint step), recovery when the internet is lost, the return to a higher-priority stored network every `PREF_CHECK`, the emergency networks and the open networks.

What is switched off: the upload probe (it prints 0 without traffic), the sustained-slow-upload check and the starving-stream check (so `UP_STRIKES`, `MIN_UP_KBPS`, `STREAM_MIN_KBPS`, `SWITCH_GAIN_PCT` and the cooldowns never act), the too-slow check of a preferred network on arrival, and the `kbps` figure in the WiFi cell, which is always 0.

How a network is chosen when the internet is lost: the stored networks that are on the air are taken strongest signal first (a network heard on two bands is one candidate), each is connected in turn, and the first one that delivers internet wins. If none delivers, the recovery moves on to its next step. Nothing is skipped and there is no return to the previous network, because both need a measurement.

The lines that mark this mode:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] reporting: local | probe: none - signal mode | wifi cell: ${REPORT_WIFI} | lang: local ${LOG_LANG}, site ${SITE_LANG}`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] trying ${SSID}`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] could not connect to ${SSID}: ${reason} - trying the next` (the reasons are listed under [ASSOC_WAIT](#assoc_wait))
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] could not return to ${SSID}: ${reason}`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [OK] connected: ${SSID} (signal mode - no upload probe target configured)` (the measured form reads `switched to ${SSID} (upload ${kbps} kbps)`)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [OK] returned to preferred network: ${SSID} (signal mode)` (the measured form ends with `(upload ${kbps} kbps)`)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] running with: signal mode (no probe target - networks chosen by signal), reboot after ${REBOOT_AFTER_MIN} min wedged, wifi cell ${on|off (REPORT_WIFI=no)|off (no SITE_URL)|off (auto with LOG_TARGET local)}, ${n} stored networks, ${m} emergency, open networks ${yes|no}, stamps in ${SITE_TZ|the device zone}` (the start summary in this mode)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [OK] connected to EMERGENCY network: ${name} (signal mode) - stored networks stay armed, home again when one returns` and `${yyyy-mm-ddThh:mm:ss+hh:mm} [OK] connected to OPEN network: ${name} (signal mode) - stored networks stay armed, home again when one returns` (the measured form carries `(upload ${kbps} kbps)` instead)

`awacs.sh speed` prints a failed upload row that begins `no probe target (signal mode)`.

## Emergency networks

### SAFETY_NET

Default: empty (no emergency network); the script declares an empty array and expects entries only in `/etc/awacs.conf`

Allowed: one line per network, `SAFETY_NET["Name"]="password"`; the name as broadcast; the password 8 to 63 characters, or exactly 64 hex digits (NetworkManager backend only), or `""` for an open hotspot listed on purpose

Unit: none (a list of name and password pairs)

Emergency networks with passwords, typically a phone hotspot, that the daemon may join when nothing else works. During a recovery, once the visible stored networks have been tried and the round's own recovery step has not brought the internet back, the daemon walks this list and tries each entry in turn, before it considers any unknown open network. Every entry is attempted whether or not it appeared in the daemon's last radio scan: the function never reads the scan picture, it asks the network layer to connect, because a hotspot is often switched on a moment ago. The entry is created as a visible, not hidden, network, so list hotspots that broadcast their name. A successful entry is temporary: on the wpa backend it is a runtime network id in the live supplicant (the script never writes `wpa_supplicant.conf`); on the NetworkManager backend it is a keyfile under `/run` with `autoconnect=false`, gone at reboot. The temporary entry is removed when the device is back on a stored network, at the start of the next recovery, and by the start-up sweep if the daemon died while on it. Entries are tried in the order bash iterates its associative array, not in the order of the lines in the file.

The whole file, `SAFETY_NET` included, is read only when the daemon runs as root and the file passes the owner and mode checks; a refused file means no emergency network at all. Each attempt is bounded by `ASSOC_WAIT`: on wpa one wait for association and an address (25 seconds by default); on NetworkManager a settle wait, then the `nmcli` activation wait, then the address wait, so up to two or three times `ASSOC_WAIT` per entry. `NET_FAIL_TICKS` decides when a recovery starts from the main loop; a recovery also runs at start when there is no internet. A recovery has three rounds and the list is walked in each round that has not restored the internet, so an entry may be tried up to three times per recovery; the only round that skips the list is one on NetworkManager where NetworkManager picks the interface up again while the round gathers evidence. Unknown open networks (`OPEN_NETWORKS`) are tried only after every emergency entry failed or when the list is empty; an entry with an empty password is tried before them. The marker naming the temporary entry, `open_id`, lives under `RUN_DIR`. In monitor-only mode (NetworkManager present but `nmcli` missing, or the interface unmanaged) no recovery ever runs, so the list is never used. `LOG_LANG` and `SITE_LANG` pick the language of the INFO and OK lines below for the local file and for the site; with `LOG_TARGET=remote` those two lines are not written locally, only sent; and `DEBUG=yes` adds the local `connect_id` line whatever `LOG_TARGET` says.

Log lines:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] trying emergency networks (${count} listed)`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [OK] connected to EMERGENCY network: ${name} (upload ${kbps} kbps) - stored networks stay armed, home again when one returns` (`(signal mode)` in place of the upload figure without a probe target; the upload is one probe on the new network)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [DEBUG] connect_id: activating ${id} (backend ${BACKEND})`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [OK] internet restored: ${name} - down ${duration}, ${n} recovery ${run|runs}` (on the first healthy pass after the win, for a recovery started from the main loop and for the start-up recovery alike)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO][awacs] trying emergency networks (${count} listed)` and `${yyyy-mm-ddThh:mm:ss+hh:mm} [OK][awacs] connected to EMERGENCY network: ${name} (upload ${kbps} kbps) - stored networks stay armed, home again when one returns` (the same two lines as the site receives them)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [ERROR] emergency network ${name} skipped: password must be 8-63 characters or 64 hex digits` (NetworkManager backend, once per outage per entry)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [ERROR] emergency network ${name} skipped: name or password carries a quote or backslash the supplicant cannot take` (wpa backend, once per outage per entry)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] could not create the temporary entry for ${name} - skipping it` (the entry could not be created in the supplicant or as a keyfile; once per outage per entry)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] emergency network ${name} refused: ${reason} - trying the next` (the entry was tried and failed; the reasons are listed under [ASSOC_WAIT](#assoc_wait); once per outage per entry and reason)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] no emergency network delivered (${tried} tried, ${skipped} skipped)` (the walk ended without a win; once per outage)

A skipped entry, an entry that could not be created and a refused entry each get a line, once per outage per entry, and the walk closes with the count; later recoveries of the same outage count the repeats, said after `internet restored`. When every entry has failed and `OPEN_NETWORKS=yes`, the next line is `trying open networks as last resort (${n} open networks heard)`. When the list is empty no line is written and open networks follow directly.

When to change it: add an entry for every hotspot you can switch on from a phone near the device and for any trusted guest network whose password you know, and make sure the hotspot broadcasts its name. Leave it empty if there is no such network; the daemon then goes straight to open networks (when `OPEN_NETWORKS=yes`) after the stored networks. Add an entry with an empty password only for an open hotspot you deliberately trust and want tried before unknown open networks. Remove an entry when the hotspot is retired or its password changed; a stale password only costs the attempt time in every round. On the wpa backend give each entry a passphrase of 8 to 63 characters, since a 64-hex key is not usable there. Keep the entries in `/etc/awacs.conf`, root-owned, mode 0600, never in `awacs.sh` itself, which is a shared file.

A phone hotspot switched on when the home router is down, and an open hotspot you trust, tried before unknown open networks.

```sh
SAFETY_NET["MyPhoneHotspot"]="hotspot-password"
SAFETY_NET["TrustedOpenCafe"]=""
```

### Syntax and rules

An entry is a plain assignment into the array the script declares: `SAFETY_NET["Name"]="password"`. A `readonly` or `declare` line in the file is unsupported. The whole file, `SAFETY_NET` included, is read under the conditions given under [Loading](#loading); a refused file means no emergency network at all. The validation block holds no rule for `SAFETY_NET`, and the array is sealed read-only with the rest of the settings. Entries are not validated when the file is loaded; the checks run when an entry is tried, and they differ by backend.

When entries are tried. A recovery starts when `NET_FAIL_TICKS` consecutive checks find no internet, and also at start when the device boots without internet. It first removes any leftover temporary entry, re-enables every stored network, asks the base layer to reconnect (skipped in the first run of an outage while the default gateway still answers) and waits once for an address and the internet. Then, in each of three rounds, it tries the visible stored networks (by measured upload, or by signal), classifies the outage, runs the round's recovery step when the fault looks on-device, and only then walks the emergency list and, after it, the open networks. So the list is reached after the stored networks failed in that round, an entry may be tried up to three times in one recovery, and unknown open networks are reached only after every emergency entry failed or when the list is empty. A success anywhere ends the recovery at once.

No search in the scan. The daemon walks every key in the array and never consults the scan cache: each entry is handed to the network layer directly, because hotspots are often switched on a moment earlier. The entry is created as an ordinary, not hidden, network, so the hotspot must broadcast its name, but it need not have appeared in the last scan. Each attempt is bounded by `ASSOC_WAIT`: on wpa one wait for association and an IPv4 address; on NetworkManager a settle wait of up to `ASSOC_WAIT` seconds, then `nmcli -w ${ASSOC_WAIT} connection up`, then the address wait itself, so up to three times `ASSOC_WAIT` per entry. A connection counts only after the internet check passes; an entry that associates without internet is torn down like a failed one.

Temporary and never saved. On wpa the entry is a runtime network id created with `wpa_cli add_network`, and the script has no save command for the supplicant's settings, so nothing reaches `wpa_supplicant.conf`. On NetworkManager the entry is a keyfile written to `/run/NetworkManager/system-connections/awacs-safety-${time}-${pid}.nmconnection` with `autoconnect=false` and mode 0600 and loaded with `nmcli connection load`; `/run` is in memory, so it does not survive a reboot. An entry with an empty password takes the same pattern with a different second word. Before each attempt the id is written to the marker `RUN_DIR/open_id`, so a daemon killed in the middle of an attempt leaves a trace that the next start removes; on failure the id is removed and the marker deleted. After a win every stored network is re-enabled so that the supplicant or NetworkManager can bring the device back to a stored network by itself, and when the main loop sees the device on a different real network the temporary entry is deleted. It is also deleted at the start of the next recovery, and on NetworkManager the third recovery step wipes every `awacs-*.nmconnection` file and the marker.

NetworkManager backend. A non-empty password must be 8 to 63 characters long or exactly 64 hex digits; otherwise the entry is skipped and said once per outage: `emergency network ${name} skipped: password must be 8-63 characters or 64 hex digits`. Any name bytes are accepted, because the name is stored as a byte array, so Arabic, emoji and symbol names work. The keyfile is written to `/run/NetworkManager/system-connections/awacs-safety-${time}-${pid}.nmconnection` with `autoconnect=false` and mode 0600 and loaded with `nmcli connection load`; an entry with an empty password gets no security section and a different second word in the same name pattern. Deletion is guarded: the daemon refuses to remove any profile whose name does not follow its own `awacs-...-${numbers}-${numbers}` pattern (`awacs-`, then the second word, then two numbers separated by a hyphen: the time and the process id) or whose file is not under `/run/NetworkManager/system-connections/awacs-*`, logging the refusal at ERROR with a line that begins `REFUSING delete:`. A saved profile is never touched.

wpa backend. The entry is skipped, and said once per outage as `emergency network ${name} skipped: name or password carries a quote or backslash the supplicant cannot take`, when the name contains a backslash or a double quote, or when the password contains a double quote, because both are placed inside a double-quoted `wpa_cli` argument. The password is piped to `wpa_cli` over its standard input rather than passed on the command line, so it never appears in the process list. The script applies no length check of its own on this backend: each `set_network` command must answer OK, or the entry is skipped and its id removed (`could not create the temporary entry for ${name} - skipping it`). Because the value is always sent quoted, the supplicant reads it as a passphrase, so a 64-hex key is not usable on this backend; use a passphrase of 8 to 63 characters, which is accepted on both backends.

Empty password on purpose. An empty value marks an open hotspot listed deliberately. On wpa the entry is created with `key_mgmt NONE`; on NetworkManager the keyfile is written without a `[wifi-security]` section. Such an entry is tried with the other emergency entries, that is before any unknown open network, and the NetworkManager length rule applies only to non-empty values.

How `install.sh` writes these lines. Step 5 of the wizard asks `Add an emergency network?`, then for a name and a password (read without echo), then `Add another one?` after each entry. It is stricter than the daemon: the name must be 1 to 32 bytes, and neither the name nor the password may contain a double quote, a backslash, `$`, a backtick or a control character, because the value lands inside a double-quoted assignment that bash executes as root. Rejections read `Name rejected: 1 to 32 bytes, without quotes, backslash, $ or backtick.` and `Password rejected: 8 to 63 characters, or 64 hex digits, or empty. No quotes, backslash, $ or backtick.` and the entry is asked again. The same entries can be given without prompts with the repeatable flag `--safety 'SSID=password'`, split at the first `=` and checked by the same rules, so a name containing `=` cannot be given that way; `--no-safety` or `--yes` skips the prompts but still writes the flagged entries. When the file is rewritten, existing lines are kept, except the eight reporting keys, the wizard's own marker line (which begins `# awacs install.sh`) and any `SAFETY_NET` entry with the same name, which are replaced; each entry is printed as `SAFETY_NET["name"]="password"`, exactly the form the daemon expects; the write is atomic: the file is written through a temporary file in `/etc`, `chmod 600` and `chown root:root`, then moved into place, and under `--dry-run` the content is only printed with every password masked as `********`. The wizard never edits `wpa_supplicant.conf` or a NetworkManager profile.

## Timing

Five knobs set the rhythm of the main loop, the patience of every connection attempt and the reboot rule. All five follow the numeric rule (a whole number from 1 to 9999999, else the default) and are sealed after loading, so a change needs a daemon restart. None of them changes at night. Monitor-only mode (a NetworkManager image without `nmcli`, or with an unmanaged interface) ignores them all and checks every 300 seconds.

One pass of the main loop, in order: apply the day or night profile; run the internet check (a ping to `8.8.8.8`, then `1.1.1.1`, then an HTTP 204 request, then the site endpoint when `SITE_URL` is set, stopping at the first success; a check that fails while the interface sent 16384 bytes or more during it is repeated once in the patient form, at most once per outage). On a healthy pass: reset the failure counter and the fault clock, deliver the offline spool on the third consecutive healthy pass and then every thirtieth, attempt the once-per-boot tool install on the third, refresh the WiFi cell on the first and then every sixth, retire a temporary network entry once back on a stored network, take the 3-second transmit-counter sample for the upload rules, and run the preferred-network look when `PREF_CHECK` is due. On an offline pass: zero the healthy-pass count and add one to the failure counter that `NET_FAIL_TICKS` reads. Then sleep `TICK`.

A recovery run is: a gentle first step (ask the base layer to reconnect, wait up to `ASSOC_WAIT` for a link and an address, check the internet; in the first run of an outage the reconnect is skipped while the default gateway still answers, so a working association is not dropped for it); then three rounds, each trying the visible stored networks (by measured upload, or by signal in signal mode), classifying the outage as an on-device fault or external, running one recovery step for an on-device fault (round 1 a radio bounce, round 2 a re-kick or restart of the network service, round 3 a WiFi firmware reload), then the emergency and open networks; and finally, when all three rounds lost, the reboot rule.

### TICK

Default: `10`

Allowed: whole number 1 to 9999999; anything else becomes 10

Unit: seconds

How long the daemon sleeps between two passes of its main loop. The real period is longer than `TICK`: about 3 seconds more when online, for the transmit-counter sample; about 4 seconds more again on a network that blocks ping, because both pings time out before the HTTP check answers; and up to about 7 to 10 seconds more when offline, while the pings and HTTP checks time out, with about 26 seconds on top of the one offline pass that pays for a patient check. No sleep happens inside a recovery run, which blocks the loop for as long as it takes. Several housekeeping cadences are counted in consecutive healthy passes, not seconds, so they scale with `TICK`: the offline story is delivered on the third consecutive healthy pass and then every thirtieth, the once-per-boot tool install is attempted on the third, and the WiFi cell is refreshed on the first and then every sixth; an offline pass resets that count.

Time to the first recovery run is about `NET_FAIL_TICKS` times (`TICK` plus the offline check's time), plus the one patient check when the router keeps answering. The night profile does not change `TICK`. At boot there is no grace at all: a daemon that starts without internet begins a recovery run immediately. Monitor-only mode sleeps a fixed 300 seconds and ignores `TICK`. Delivering a long offline story on the third healthy pass can stretch that one pass, because each spooled line is sent one by one with a 4-second limit; on legacy images the preferred-network look adds a 4-second wait to its pass.

Log lines:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [DEBUG] QA: flow=${flow} kbps, strikes=${strikes}, profile=${day|night}`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [DEBUG] QA(stream): flow=${flow} kbps, strikes=${strikes}`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] site did not take the log line (${reply}) - holding lines, delivery retried about every ${minutes} min` (the minutes are 30 passes of `TICK`, 5 with the default)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] clock set ${forward|back} ${delta} by time sync - the lines above carry the old time` (the device clock is compared with the uptime clock on every pass; a difference above 60 s between two passes is a step)

When to change it: raise it (15 to 30) on a battery or very low-power unit to cut the per-pass ping, counter read and CPU wake-ups; lower it (5) when you want the failure counter to fill faster so recovery starts sooner. The offline check and the 3-second sample add seconds on top of every pass, and `NET_FAIL_TICKS` multiplies whatever you choose.

A battery-powered unit: one ping every 15 seconds is enough, and with `NET_FAIL_TICKS=3` recovery still starts about 70 seconds after a loss, or about 26 seconds later when the router keeps answering and the one patient check is paid.

```sh
TICK=15
```

### NET_FAIL_TICKS

Default: `3`

Allowed: whole number 1 to 9999999; anything else becomes 3

Unit: main-loop passes

How many consecutive passes must find no internet before the daemon starts a recovery run. Each offline pass adds one to a failure counter; any pass with internet resets it to zero. When the counter reaches `NET_FAIL_TICKS` the daemon logs the loss, on that pass only, so one outage produces one loss line, and calls the recovery run. On that pass one test comes first, on two conditions: the link itself is alive (the default gateway answers a ping, or the kernel's neighbour table reports it reachable) and no patient check has failed in this outage yet. That test is a patient internet check, and when it passes the pass counts as a healthy one: no loss line, no recovery run, and the local file records `internet answers late, not never - slow link, no recovery (${NET_FAIL_TICKS} quick checks timed out)`, a line that is never sent to the site. The site gets the episode instead: an opener at the first such pass, a count at most once an hour while late answers continue, a closer after about 5 minutes of quick answers, and a note when a loss ends the episode (the lines below). If the run does not win, the counter keeps growing past the threshold and the run is called again on every following offline pass until the internet is verified, so this knob only delays the first run of an outage; a won run resets the counter. The boot pass bypasses it: a daemon that starts without internet runs recovery at once and says `no internet at start on ${SSID} - router ${state}, engaging`; a start with internet says `online at start via ${SSID}`. A short outage that heals between two runs is still announced as restored on the next healthy pass.

Time to the first recovery run is about `NET_FAIL_TICKS` times (`TICK` plus the offline check's time, up to about 7 to 10 seconds while the pings and HTTP checks time out); with the defaults that is roughly 40 to 63 seconds after the loss on a link whose gateway has gone silent, and about 72 to 83 seconds when the router keeps answering and the one patient check is paid. Because the internet check already tries three sources in a row (four when `SITE_URL` is set), a value of 1 means one fully failed check starts recovery. Larger values protect a flaky but usually-working uplink from unnecessary reconnects; smaller values react faster.

Log lines:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] internet lost on ${SSID} - router ${still answers|silent too|none (not associated)}, engaging` (the network the device was on, or the interface name when it was on none; one gateway ping on this pass says whether the router still answers, is silent too, or there is no association)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] trying ${SSID}`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] could not connect to ${SSID}: ${reason} - trying the next` (the reasons are listed under [ASSOC_WAIT](#assoc_wait))
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] switching to ${SSID} (${best_kbps} kbps, the fastest candidate)`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [OK] switched to ${SSID} (upload ${best_kbps} kbps)`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] switching to ${SSID} failed: ${reason}`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [OK] internet restored: ${SSID} - down ${duration}, ${n} recovery ${run|runs}` (the duration from the loss line, as `45 s`, `3 min` or `2 h 5 min`; the runs are the recoveries the outage took)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] repeated ${n} more times during the outage (last at ${HH:MM}): ${line}` (after `internet restored`, one per step the recovery runs repeated: a step is said the first time it happens in an outage and counted after that; the hour is the last repeat's, in `SITE_TZ`)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] internet answers late, not never - slow link, no recovery (${NET_FAIL_TICKS} quick checks timed out)` (local file only)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] no internet at start on ${SSID} - router ${still answers|silent too|none (not associated)}, engaging` (the start-up recovery's own loss line; the pass counter plays no part)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [OK] online at start via ${SSID}` (a start that finds the internet up; the interface name when not associated)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] uplink answering late on ${SSID} - ${NET_FAIL_TICKS} quick checks timed out, the patient check passed, no recovery` (the first late pass of an episode; no new episode opens within 30 minutes of the last closer, and late passes in that window are folded into the next one)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] internet answered late ${n} more times in the last hour on ${SSID} - slow link, no recovery` (at most once an hour while the episode is open, only when new late passes happened)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] uplink answers normally again on ${SSID} - answered late ${n} times over ${span}` (after 30 quick passes in a row, about 5 minutes)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] internet answered late ${n} more times before this loss on ${SSID} - slow link` (a loss that ends an open episode with uncounted passes; written before the loss line)

When to change it: raise it (5 to 6) where the uplink has frequent 20 to 40 second blips that clear on their own and a reconnect would only make them longer; lower it to 1 or 2 on a device whose job cannot tolerate a minute offline.

This uplink drops for about 40 seconds several times a day and heals by itself; wait one to two minutes before touching the WiFi.

```sh
NET_FAIL_TICKS=6
```

### ASSOC_WAIT

Default: `25`

Allowed: whole number 1 to 9999999; anything else becomes 25

Unit: seconds

How long the daemon waits for a network it just asked for to come up: a loop checks about once a second, for `ASSOC_WAIT` rounds, that the interface reports both a WiFi association and a global IPv4 address, and the attempt fails when the bound runs out. This bound applies to every attempt on any network: a stored network during recovery, an emergency network, an open network, the move to a higher-priority network and the way back from it. One exception: the connect of a manual trial from the site (`switch`, `join`) gets `TRIAL_ASSOC_WAIT`, 45 s, or `ASSOC_WAIT` when that is larger, because a new or far network can scan for 7 to 23 s before it authenticates; the way back from the trial keeps `ASSOC_WAIT`. On NetworkManager images the same number is also handed to `nmcli` as its own wait limit for the activation, and it bounds the settle wait that precedes every `nmcli` command (until the device leaves its connecting or deactivating states), so one attempt there can take up to two or three times `ASSOC_WAIT`. The gentle first step of every recovery run uses the same bound; in the first run of an outage on a link whose gateway still answers, that step is the wait alone, without the reconnect before it.

Each candidate tried in a recovery run costs up to `ASSOC_WAIT` seconds (two to three times that on NetworkManager) plus an upload probe when the link comes up, so with many stored networks a recovery run grows linearly with this value, and that spaces out the moments when `REBOOT_AFTER_MIN` is compared. A value shorter than the router's real DHCP time makes a working network look broken: it is skipped and, during recovery, may feed the on-device fault evidence because no link came up. On NetworkManager images, if `nmcli` cannot report a device state at all, every settle wait costs the full `ASSOC_WAIT`. The radio-bounce recovery step does not use this knob: on NetworkManager images it switches the radio off, pauses 2 seconds, switches it on and then waits for the device to settle under a fixed 15-second bound; on legacy images it takes the interface down, pauses 2 seconds, brings it up and pauses 3 seconds.

Every line that says why a connection failed carries one of these reasons: `never associated` (no association within the bound), `associated but got no address` (an association but no IPv4 lease within the bound), `refused - wrong password?` (the supplicant marked the network `TEMP-DISABLED`, or NetworkManager's activation named the credentials), `not found on the air` (NetworkManager could not find the network), `timed out after ${ASSOC_WAIT} s` (NetworkManager's own wait ran out), `NetworkManager not answering` (`nmcli` exit 8), `NetworkManager: ${message}` (NetworkManager's own message for any other failure, its fixed prefix dropped and cut to 100 characters) and `linked but no internet` (association and address, then a failed internet check). `no association or no address` remains the fallback when none of them applies.

Log lines:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [DEBUG] connect_id: activating ${id} (backend ${BACKEND})`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] trying ${SSID}`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] could not connect to ${SSID}: ${reason} - trying the next` (the reasons are listed under [ASSOC_WAIT](#assoc_wait))
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] could not reach the preferred network ${SSID}: ${reason} - going back to ${current}` (`- no stored network to go back to, the next check decides` when the network the device left is not known)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] could not return to ${SSID}: ${reason}` (once per outage per network and reason)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [OK] back on ${SSID}`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] router not answering - waiting up to ${ASSOC_WAIT} s for ${IF} to reconnect` (the opening of a recovery whose gateway is silent; once per outage)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] the way back to ${previous} failed - on ${SSID|no network} now, the next check decides` (after a preferred-network attempt whose way back failed for a reason other than `linked but no internet`)

When to change it: raise it (35 to 45) when the router or hotspot is known to be slow to hand out addresses; the sign is a network that keeps failing exactly `ASSOC_WAIT` seconds after its `activating` line in the log, yet works when joined by hand. Lower it (15) only on fast networks when you want recovery runs to move through many candidates quickly.

The office router answers DHCP after about 30 seconds and kept being counted as a failed connection.

```sh
ASSOC_WAIT=40
```

### PREF_CHECK

Default: `600`

Allowed: whole number 1 to 9999999; anything else becomes 600

Unit: seconds

The minimum number of seconds between two looks for a stored network with a strictly higher priority than the one the daemon is on (the `priority=` value in `wpa_supplicant.conf` on legacy images, `autoconnect-priority` on NetworkManager images). A look runs only on a healthy pass, is skipped while a live stream, preview, capture or upload is running, and costs no internet traffic, only radio work: on legacy images a supplicant-side directed scan (which also surfaces hidden networks) with a 4-second wait, then a read of the scan results; on NetworkManager images a network list with NetworkManager's own rescan; plus a read of the stored-network list. The first look happens on the first healthy, non-streaming pass after start. A candidate must be present on two consecutive looks before the daemon tries to move, and a look that finds no candidate resets that count, so with the default the move comes 10 to 20 minutes after the higher-priority network appears. On arrival, when a probe target exists, the upload is measured: below the active floor (`MIN_UP_KBPS` by day, `NIGHT_MIN_UP_KBPS` at night) the candidate is set aside for three times the active cooldown and the daemon goes straight back to the previous network; otherwise it stays and reports the return. If the connection attempt itself fails, the daemon says so with the reason and goes back to the previous network; a way back that fails is reported too. A candidate seen at one look and gone at the next is reported once per stay on the current network; the attempt line then says how many times that happened before the candidate held.

A running stream blocks the look entirely and the timer is not advanced then, so the look runs on the first free healthy pass afterwards. The set-aside length is three times the cooldown in force: `DANCE_COOLDOWN` (1200 seconds by default, so 3600) by day and `NIGHT_DANCE_COOLDOWN` (2400, so 7200) at night; only one network is set aside at a time (a new one replaces the old) and the candidate search skips it until the time expires. The too-slow test needs a probe target; in signal mode the daemon never sets a network aside and stays on the higher-priority network. `ASSOC_WAIT` bounds the connect attempt and the way back. The search never picks a network of equal priority, so with every stored network left at the default priority this knob has nothing to do; a temporary emergency or open network has priority 0, so any stored network with a higher priority is a candidate while the daemon sits on one.

Log lines:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [DEBUG] best_pref_id: cur=${current_id}(p=${current_priority}) -> best=${candidate_id|none}(p=${best_priority}) veto=${set_aside_id|none}`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] higher-priority network ${name} visible twice - leaving ${current} to go home` (the second consecutive sighting; ` (seen and lost ${n} times before)` is appended when the candidate flickered during this stay)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] preferred network ${name} was visible at one check and gone at the next - staying on ${current} until it holds for two checks in a row` (the first flicker of a stay; later ones are counted into the attempt line)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] could not reach the preferred network ${name}: ${reason} - going back to ${current}` (the reasons are listed under [ASSOC_WAIT](#assoc_wait); `- no stored network to go back to, the next check decides` when the network the device left is not known)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] measured ${kbps} kbps on ${SSID}` (on arrival, with a probe target; `upload probe failed on ${SSID} - the probe target accepted nothing (site or endpoint down?), counting it as 0 kbps` when the probe took nothing)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] preferred network ${SSID} too slow (${kbps} kbps, floor ${floor}) - benched for ${minutes} min, going back to ${previous}` (`- benched for ${minutes} min, staying on it` when there is no network to go back to; `, ends the bench on ${name}` is appended when another network's bench was still running; the minutes are three cooldowns, 60 by day and 120 at night with the defaults)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [OK] back on ${SSID}`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] back on ${SSID} - linked but still no internet` (the way back linked without internet; the next check decides)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] could not return to ${SSID}: ${reason}` (the way back failed; once per outage per network and reason)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] the way back to ${previous} failed - on ${SSID|no network} now, the next check decides` (follows the line above; skipped when the reason was `linked but no internet`, since the device is then back)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [OK] returned to preferred network: ${SSID} (upload ${kbps} kbps)`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [OK] returned to preferred network: ${SSID} (signal mode)`

When to change it: lower it (300) when a phone hotspot with a data cap is a common fallback and you want to return home sooner (two sightings then take 5 to 10 minutes); raise it (1800) when scans disturb the link or the home network comes and goes and you want a very calm return. Set the stored networks' priorities first: without a strictly higher priority somewhere, no value of `PREF_CHECK` does anything.

The fallback is a metered hotspot; look every 5 minutes so the return home takes 5 to 10 minutes instead of 10 to 20.

```sh
PREF_CHECK=300
```

### REBOOT_AFTER_MIN

Default: `30`

Allowed: whole number 1 to 9999999; anything else becomes 30

Unit: minutes

How long an on-device WiFi fault must persist before the daemon reboots the device. The clock is an in-memory timestamp set the first time a recovery round gathers on-device evidence, and it is compared only at the end of a recovery run that lost all three rounds: if the first sighting is at least `REBOOT_AFTER_MIN` minutes old (and, on NetworkManager images, NetworkManager has provably given up) the daemon writes one ERROR line, saves the outage story beside the log, syncs the disks, waits 2 seconds and runs `reboot`. On-device evidence means, in one round: the default gateway does not answer a ping (or there is no default route), no network reached association plus an address in this round, NetworkManager is not actively connecting, and at least one of three signs: a stored network is visible on the air yet unreachable; the radio scan comes back empty (no cached picture since boot, or the previous picture dropped after three consecutive empty scans); or the stored-network list reads back empty. The clock goes back to zero on any round classified as external (the gateway answers; a link with an address came up but carried no internet; or no stored network is visible while other networks are heard), on every sighting of a wrong password (a network the supplicant has temporarily disabled on legacy images, or an `nmcli` failure of the credentials kind on NetworkManager; the recovery steps still run), on any moment of verified internet, on every healthy pass, and on NetworkManager images whenever NetworkManager is still trying, is connected without internet, or reports the device unavailable (state 20). Since the clock lives in memory, a reboot or daemon restart starts it from zero, so a fault that survives the reboot earns the next one only after another full `REBOOT_AFTER_MIN` streak. A counter beside the log (`${LOG_FILE}.reboots`) numbers the reboots of one fault; the first healthy pass removes it.

The check runs only at the end of a losing recovery run, so the reboot lands between `REBOOT_AFTER_MIN` and `REBOOT_AFTER_MIN` plus the length of one run (the gentle step, three rounds of candidate attempts bounded by `ASSOC_WAIT`, one recovery step per round, the emergency and open attempts, and 20-second pauses on the external branches). The ERROR line is a story line, but the network is down, so it is held in the spool; because the spool is on memory-backed storage and would die with the reboot, the daemon copies it beside the log (`${LOG_FILE}.spool`) together with a marker (`${LOG_FILE}.reboot`: the time, the number of recovery runs, the boot id and the sign that decided). The next start puts the saved copy in front of its own lines, removes the marker and says that the reboot was its own; the first flush then delivers the outage story, the reboot line, the start line and that WARN, in order. A power cut leaves no marker, so a start after one stays plain. A marker whose boot id equals the running boot's means the reboot command did not run: after 60 seconds alive the daemon says so and drops the marker. The empty-scan sign depends on the fixed three-empty-scans rule and on `SCAN_TTL`, which bounds how long a cached picture is trusted. On NetworkManager images the clock arms only when the device state reads disconnected (30) or failed (120) on two consecutive checks with no connecting sighting between them, or when `nmcli` itself is unreachable after the NetworkManager-restart step was already spent; any other state read resets the clock, a healthy pass wipes the NetworkManager evidence too, and a device reported unavailable (state 20: halted radio firmware, rfkill) never arms it. The smallest legal value is 1 minute and the knob cannot be switched off by value; a very large value (up to 9999999) postpones the reboot indefinitely in practice.

Log lines:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [ERROR] rebooting now: wedged ${REBOOT_AFTER_MIN} min (${sign}) - reboot ${n} for this fault, the story continues after the boot` (the sign is `${names} on the air but this device cannot join`, `the radio hears no network at all` or `the stored network list reads empty`; `n` counts the reboots of this fault)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] starting after the reboot AWACS ordered at ${yyyy-mm-dd HH:MM} - wedged ${REBOOT_AFTER_MIN} min (${sign}), ${runs} recovery runs before it` (the first start after a reboot the daemon ordered, right after the start line; the stamp is in `SITE_TZ`)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [ERROR] the reboot AWACS ordered at ${yyyy-mm-dd HH:MM} did not happen - the reboot command failed, check the device` (60 seconds into a start that finds the marker with its own boot id, or 60 seconds after the `reboot` command in the daemon that issued it)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] reboot clock armed - the device reboots after ${HH:MM} unless the internet returns or the fault reads external` (the first arming of an outage; the hour is the deadline in `SITE_TZ`; later armings are counted)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] reboot clock cleared - NetworkManager picked the device up again` (NetworkManager only: a connecting or readable state after an announced arming)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] fault looks on the device: ${sign} - recovery follows` (the first on-device round of an outage that runs a rung; the sign is `${names} on the air but this device cannot join` (at most 10 names, then `and ${n} more`), `the radio hears no network at all`, `the stored network list cannot be read` (NetworkManager not answering `nmcli`) or `the stored network list reads empty`; a changed sign speaks again, identical rounds are counted)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [ERROR] association refused by ${names} - wrong password? (recovery continues, reboot stays off)` (the networks the supplicant marked `TEMP-DISABLED`, or the profile whose activation named the credentials; `association refused - wrong password? (recovery continues, reboot stays off)` when no name is known)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] outage looks external (round ${round}) — waiting, not rebooting` (NetworkManager was busy at the start of the round; every external verdict is said once per outage and counted on later rounds)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] outage looks external: the router answers, the fault is upstream (round ${round}) — waiting, not rebooting`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] outage looks external: ${name} linked but no internet, the fault is behind that network (round ${round}) — waiting, not rebooting`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] outage looks external: none of your ${k} stored networks is on the air, ${n} others heard (round ${round}) — waiting, not rebooting`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] NM is still trying - waiting it out` (once per outage; later rounds are counted)
- the INFO line written when NetworkManager reports the device connected while the internet check fails, which names the round number (once per outage; later rounds are counted)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [ERROR] NetworkManager is not answering nmcli (exit 8) - stored networks cannot be tried until it is restarted (recover L3)` (the first exit 8 of a streak)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [ERROR] interface ${IF} has vanished - WiFi hardware or driver gone, rung L3 reloads the driver (a USB dongle needs replugging)` (at a recovery start, when an interface seen alive earlier in this run is gone; once per outage)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] repeated ${n} more times during the outage (last at ${HH:MM}): ${line}` (after `internet restored`, one per repeated step; the rungs, the emergency list, the refused candidates and the verdicts above are counted the same way; the hour is the last repeat's)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] radio heard nothing on ${empties} scans in a row - previous results dropped`

When to change it: raise it (60 to 120) when reboots are expensive (a long boot, an attached workload that loses state) and the radio faults you see usually clear within the hour; lower it (15) on a device whose WiFi chip is known to lock up and where a quick reboot is the accepted cure.

This device takes minutes to boot and its radio glitches usually clear within the hour; give recovery an hour first.

```sh
REBOOT_AFTER_MIN=60
```

## Upload rules

Six knobs decide when the daemon considers its link too slow, how it measures, and what another network must offer before the daemon moves. All six follow the numeric rule and are sealed after loading. The floor, the gain and the cooldown have night counterparts: `MIN_UP_KBPS`, `SWITCH_GAIN_PCT` and `DANCE_COOLDOWN` are copied into working values that the night profile swaps between `NIGHT_START` and `NIGHT_END` when `NIGHT_MODE=yes`, the default (see [Night profile](#night-profile)); every comparison in this section reads the working value, so wherever this section says the floor, the gain or the cooldown, it means the day or night value in force at that moment. `PROBE_KB`, `UP_STRIKES` and `STREAM_MIN_KBPS` have no night counterpart. The probe target is `PROBE_URL` when set, otherwise `SITE_URL/DEVICE_ID/SITE_API`; with neither the daemon is in signal mode and all six are inert: no slow sample is counted, no warning is written, no probe is sent and no evaluation runs, while the DEBUG `QA` lines still print the flow.

The passive sample. On every online pass the daemon reads `/sys/class/net/${IF}/statistics/tx_bytes` twice, 3 seconds apart, and turns the difference into kbps. No traffic is generated. This is what every healthy pass measures, and what the DEBUG `QA` lines show as `flow`.

The probe. At decision moments only, the daemon uploads `PROBE_KB` kilobytes of zeros to the probe target (`PROBE_URL`, otherwise the site endpoint) and reads the achieved speed. A probe is sent for the current network when an evaluation fires, for each stored network tried during an evaluation or an outage recovery, on arrival after a return to a higher-priority network, and for `awacs.sh speed`.

The evaluation. When enough slow samples have been counted and the cooldown allows, the daemon zeroes the count, records the start moment, logs a warning, names what the radio hears (`scan heard ${count} networks: ${SSID} ${dBm}, ... | known on the air: ${SSID}, ... | stored, not heard: ${SSID}, ...`, strongest first, at most ten names in each part), probes the current network and logs `measured ${kbps} kbps on ${SSID} - under the ${floor} kbps floor, a challenger must beat ${bar} kbps` (or `upload probe failed on ${SSID} - the probe target accepted nothing (site or endpoint down?), counting it as 0 kbps` when the target took nothing); only if that probe is also below the floor does it leave the network, with a bar of that probe times the gain divided by 100, to try the other visible stored networks in turn, in the order the stored-network list reports them: `trying ${SSID}`, connect (association, DHCP and an internet check; a candidate that fails is logged as `could not connect to ${SSID}: ${reason} - trying the next` and skipped unprobed), probe, log the result as `candidate [${id}] ${name} uploads at ${kbps} kbps` (or the probe-failed line), remember the fastest, and stop early at four times the floor (the switching line then ends `- plainly fast, over 4x the ${floor} kbps floor, probing stopped at it`). Otherwise the measured line ends `- above the ${floor} kbps floor, staying`, the cooldown is used up, and the measured figure reaches the WiFi cell in its next send. It goes back home unless a challenger reached the gain bar: if the best candidate did not reach the bar, or measured 0, the daemon reconnects the original network and logs `no challenger beat the incumbent - staying on ${SSID} (best was ${name} at ${kbps} kbps, needed ${bar})`; when nobody was measured the line is `the only candidate did not deliver internet - staying on ${SSID} at ${kbps} kbps` or `none of the ${n} candidates delivered internet - staying on ${SSID} at ${kbps} kbps`, and `no other known network on the air - staying on ${SSID} at ${kbps} kbps` when there was nobody to try; otherwise it announces `switching to ${SSID} (${best_kbps} kbps against ${kbps} kbps here)`, connects to the best one and logs `switched to ${SSID} (upload ${best_kbps} kbps)`. A switch that fails is logged as `switching to ${SSID} failed: ${reason} - going back to ${home}`, followed by `back on ${home}` or `could not return to ${home}: ${reason}`. If the original network cannot be reconnected after a lost comparison (`could not return to ${SSID}: ${reason}`, or `back on ${SSID} - linked but still no internet` when it linked without internet), the best candidate is connected anyway: `switching to ${SSID} (${best_kbps} kbps, below the ${bar} kbps bar) - the best left, ${home}: ${reason}`. If the whole evaluation fails, the daemon hands the link back to the supplicant or NetworkManager, says `evaluation ended with no working network - on ${SSID} now, the next check decides and recovery follows if the internet is gone` (`nothing` in place of the name when the device sits on no network) and lets the next pass's internet check decide. During an outage recovery the same evaluation runs with no bar and no home network, so any working network wins; its announcement reads `switching to ${SSID} (${best_kbps} kbps, the fastest candidate)` and a failed switch there `switching to ${SSID} failed: ${reason}`; when the recovery kept a live link as home and every delivering candidate measured 0, the line is `switching to ${name} (${kbps} kbps) - it delivered internet, ${home}: ${reason}`. The reasons are listed under [ASSOC_WAIT](#assoc_wait). A pass whose slow samples are ripe while the cooldown still runs says so once per cooldown window: `upload still slow on ${SSID} (${flow} kbps, floor ${floor}) - evaluation on cooldown, next look in ${minutes} min`.

### PROBE_KB

Default: `200`

Allowed: whole number 1 to 9999999; anything else becomes 200

Unit: KB (1 KB = 1024 bytes)

The size of the body the daemon uploads each time it measures real upload speed. The body is `PROBE_KB` times 1024 zero bytes sent to the probe target as an HTTP POST; the result is the average bytes per second of that transfer, converted to kbps (bytes per second times 8, divided by 1000). A probe is sent only at decision moments, never on a routine pass: the baseline check of the current network when an evaluation fires, each stored network tried during an evaluation or an outage recovery, the arrival check after a return to a higher-priority network, and the manual `awacs.sh speed` (root only; it reads the settings file). Routine passes read the transmit counter instead, which costs no traffic.

Needs a probe target: `PROBE_URL` if set, otherwise `SITE_URL/DEVICE_ID/SITE_API`; with neither, no probe is sent and the measurement prints 0. `curl` is given 15 seconds and still reports the average of what was sent up to then, so on a very slow link the probe is cut short: with 200 KB (1,638,400 bits) any link slower than about 109 kbps hits that limit and the figure is a partial average. If `curl` is missing or reports 0 and `wget` exists, `wget` posts the same bytes from a file in the private run directory with a 15-second network timeout under a 20-second hard limit; exit 0 or 8 (the server answered) counts as success and the rate is computed from the wall-clock time; any other exit prints 0 and the probe is reported as failed. Each stored network tried in an evaluation costs one probe plus the connection wait (up to `ASSOC_WAIT` seconds for association and DHCP, then an internet check); a candidate that fails the internet check is skipped without a probe.

Log lines:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] measured ${kbps} kbps on ${SSID}`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] measured ${kbps} kbps on ${SSID} - above the ${floor} kbps floor, staying`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] candidate [${id}] ${name} uploads at ${kbps} kbps`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] measured ${kbps} kbps on ${SSID} - under the ${floor} kbps floor, a challenger must beat ${bar} kbps`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] upload probe failed on ${SSID} - the probe target accepted nothing (site or endpoint down?), counting it as 0 kbps` (in place of the `measured` or `candidate` line when no byte was accepted, with curl and with the wget fallback)
- `awacs.sh speed` prints a row labelled `probing:` reading `${PROBE_KB}KB -> ${probe_url} ...`, then a row labelled `upload:` whose English half reads `${kbps} kbps`, or `0 kbps — probe failed` when the probe failed (the `upload:` row carries an English half and an Arabic half)

When to change it: raise it (500 to 1000) on fast links where 200 KB finishes in well under a second and readings jump around; lower it (50 to 100) on metered or very slow links to cut the data each decision costs and keep the probe inside the 15-second limit.

On a fibre-backed hotspot a 200 KB probe finishes too fast to give a steady reading.

```sh
PROBE_KB=500
```

### MIN_UP_KBPS

Default: `400`

Allowed: whole number 1 to 9999999; anything else becomes 400

Unit: kbps

The daytime upload floor: the rate below which the daemon treats the link as too slow for its job. Every pass while online and no live stream is running, the daemon reads the transmit counter over 3 seconds. A reading from 20 kbps up to but not including this floor is one slow sample; a reading under 20 kbps (idle) or at or above the floor is not slow and clears the slow-sample count. When the count reaches `UP_STRIKES` and the cooldown allows, the daemon sends one real upload probe on the current network; only if that probe is also below the floor does it try the other stored networks. The floor also stops an evaluation early: a candidate measuring at least four times the floor ends the round without trying the rest (the gain bar is still applied to it afterwards). When the device returns to a higher-priority network, that network is probed on arrival; below the floor it is set aside and the device goes back to the network it came from.

`NIGHT_MODE` is `yes` by default, so between `NIGHT_START` and `NIGHT_END` (22:00 to 06:00) `NIGHT_MIN_UP_KBPS` (default 200) replaces this value; the swap happens at the top of every pass, and every comparison (below the floor, four times the floor) uses the value in force. Inert without a probe target: the slow-sample test is skipped and the arrival check is not applied. While a live stream runs, `STREAM_MIN_KBPS` is the slow-sample threshold instead, but the probe that follows is still judged against the day or night floor. The four-times early stop applies in outage recovery too.

Log lines:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [DEBUG] QA: flow=${flow} kbps, strikes=${strikes}, profile=${day|night}`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] sustained slow upload on ${SSID} (${flow} kbps for ${UP_STRIKES} samples, floor ${floor}) - evaluating known networks`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] scan heard ${count} networks: ${SSID} ${dBm}, ... | known on the air: ${SSID}, ... | stored, not heard: ${SSID}, ...` (strongest first, at most 10 names in each part, then `and ${n} more`; `none` in a part that is empty; `scan heard 0 networks | known on the air: none | stored, not heard: ${every stored network}` when the radio hears nothing; inside a recovery the line is said once per distinct picture per outage and counted after that)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] measured ${kbps} kbps on ${SSID}`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] measured ${kbps} kbps on ${SSID} - above the ${floor} kbps floor, staying`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] preferred network ${SSID} too slow (${kbps} kbps, floor ${floor}) - benched for ${minutes} min, going back to ${previous}` (`- benched for ${minutes} min, staying on it` when there is no network to go back to; `, ends the bench on ${name}` is appended when another network's bench was still running; the minutes are three cooldowns, 60 by day and 120 at night with the defaults)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [OK] returned to preferred network: ${SSID} (upload ${kbps} kbps)`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] day profile active until ${NIGHT_START} - floor ${MIN_UP_KBPS} kbps, a challenger must reach ${SWITCH_GAIN_PCT}% of the incumbent, evaluations ${minutes} min apart`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] upload still slow on ${SSID} (${flow} kbps, floor ${floor}) - evaluation on cooldown, next look in ${minutes} min` (slow samples ripe while the cooldown runs; once per cooldown window)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] measured ${kbps} kbps on ${SSID} - under the ${floor} kbps floor, a challenger must beat ${bar} kbps`

When to change it: set it to the upload rate the workload really needs (the stream bitrate plus a margin). Too high for a link that can never reach it means a probe and an evaluation every cooldown for nothing, each one taking the device off its network; too low means a suffering link is never noticed.

A 4G hotspot that tops out near 600 kbps; the stream needs 200.

```sh
MIN_UP_KBPS=250
```

### UP_STRIKES

Default: `3`

Allowed: whole number 1 to 9999999; anything else becomes 3

Unit: consecutive slow samples, one per pass

How many slow samples in a row must be seen before the daemon considers an evaluation. A sample is one 3-second reading of the transmit counter, taken on every pass while online (about `TICK` seconds plus the reading and the internet check, so roughly every 13 to 15 seconds); no sample is taken while offline. A slow sample is a reading inside the slow band: from 20 kbps up to but not including the day or night floor normally, or from 5 kbps up to but not including `STREAM_MIN_KBPS` while a live stream runs. The count goes up by one on each slow sample and drops back to zero on any sample outside the band, the moment an evaluation fires, and when the internet returns after an outage. With the default 3, the third consecutive slow sample fires the evaluation, so roughly 30 to 45 seconds of sustained slowness is needed.

The count is shared between the streaming and non-streaming branches, so two slow samples without a stream plus one starving sample under a stream add up. If the count reaches `UP_STRIKES` while the cooldown (`DANCE_COOLDOWN`, or `NIGHT_DANCE_COOLDOWN` at night) has not elapsed, the count keeps growing instead of resetting, so the evaluation fires on the first slow sample after the cooldown ends. `TICK` sets the spacing of samples. In signal mode no slow sample is ever counted.

Log lines:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [DEBUG] QA: flow=${flow} kbps, strikes=${strikes}, profile=${day|night}`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [DEBUG] QA(stream): flow=${flow} kbps, strikes=${strikes}`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] sustained slow upload on ${SSID} (${flow} kbps for ${UP_STRIKES} samples, floor ${floor}) - evaluating known networks`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] live stream starving on ${SSID} (${flow} kbps for ${UP_STRIKES} samples, floor ${STREAM_MIN_KBPS}) - evaluating known networks`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] upload still slow on ${SSID} (${flow} kbps, floor ${floor}) - evaluation on cooldown, next look in ${minutes} min`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] live stream still starving on ${SSID} (${flow} kbps, floor ${STREAM_MIN_KBPS}) - evaluation on cooldown, next look in ${minutes} min`

When to change it: raise it (5 to 6) on links with bursty traffic where short dips are normal and were triggering evaluations; lower it to 2 when the workload is time-critical and a bad link must be left quickly. 1 means a single slow reading is enough.

The camera uploads in bursts; three slow samples in a row kept matching normal pauses.

```sh
UP_STRIKES=5
```

### SWITCH_GAIN_PCT

Default: `150`

Allowed: whole number 1 to 9999999; anything else becomes 150; keep it at or above 100, since a smaller value would allow a move to a slower network

Unit: percent of the current network's measured upload speed

The bar another stored network must reach before the daemon moves to it. When an evaluation fires, the daemon first probes the network it is on (the baseline); the evaluation goes on only if that baseline is below the day or night floor. The bar is the baseline times `SWITCH_GAIN_PCT` divided by 100, in whole numbers. The daemon then connects to each visible stored network in turn, in the order the stored-network list reports them (association, DHCP and an internet check; a candidate without internet is skipped unprobed), probes it, logs the result and remembers the fastest; a candidate at four times the floor ends the loop at once. If the best candidate did not reach the bar, or measured 0, the daemon reconnects the original network and says so; otherwise it connects to the best one and logs the new speed. With the default 150, a challenger must measure at least one and a half times the current network.

At night `NIGHT_GAIN_PCT` (default 300) takes its place. Only an evaluation started from a healthy pass uses the bar; during an outage recovery the same comparison runs with no bar and no home network, so any working network wins. Because the evaluation only runs when the baseline is below the floor, the bar is always below the floor times `SWITCH_GAIN_PCT` divided by 100. If the baseline probe fails (0 kbps) the bar is 0, and the extra rule that the best must be above 0 keeps the device on its current network unless a candidate really uploaded. If the original network cannot be reconnected after a lost evaluation, the best candidate is connected anyway, bar or not, as the only working link, and the switching line says so with the reason the way home failed. Inert in signal mode.

Log lines:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] trying ${SSID}`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] could not connect to ${SSID}: ${reason} - trying the next` (the reasons are listed under [ASSOC_WAIT](#assoc_wait))
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] candidate [${id}] ${name} uploads at ${kbps} kbps`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [OK] no challenger beat the incumbent - staying on ${SSID} (best was ${name} at ${kbps} kbps, needed ${bar})` (the closest candidate and the bar it had to reach; inside a recovery the line ends at the name)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] could not return to ${SSID}: ${reason}`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] switching to ${SSID} (${best_kbps} kbps against ${kbps} kbps here)`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [OK] switched to ${SSID} (upload ${best_kbps} kbps)`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] switching to ${SSID} failed: ${reason} - going back to ${home}`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [OK] back on ${SSID}`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] measured ${kbps} kbps on ${SSID} - under the ${floor} kbps floor, a challenger must beat ${bar} kbps` (the bar this knob sets)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [OK] no other known network on the air - staying on ${SSID} at ${kbps} kbps` (nobody to compare with)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [OK] the only candidate did not deliver internet - staying on ${SSID} at ${kbps} kbps` and `${yyyy-mm-ddThh:mm:ss+hh:mm} [OK] none of the ${n} candidates delivered internet - staying on ${SSID} at ${kbps} kbps` (candidates walked, none measured)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] switching to ${SSID} (${best_kbps} kbps against ${kbps} kbps here) - plainly fast, over 4x the ${floor} kbps floor, probing stopped at it` (a candidate at four times the floor ended the probing)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] switching to ${SSID} (${best_kbps} kbps, below the ${bar} kbps bar) - the best left, ${home}: ${reason}` (the comparison was lost and the way home failed for the reason given)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] back on ${SSID} - linked but still no internet` (the way home linked without internet)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] evaluation ended with no working network - on ${SSID} now, the next check decides and recovery follows if the internet is gone` (the switch and the way home both failed; `nothing` when the device sits on no network)

When to change it: raise it (200 to 300) when the device keeps flipping between two networks of similar speed; lower it toward 120 only when a modest gain is worth the disruption of a switch.

Two hotspots measure within 30 percent of each other; require a clear doubling before moving.

```sh
SWITCH_GAIN_PCT=200
```

### DANCE_COOLDOWN

Default: `1200`

Allowed: whole number 1 to 9999999; anything else becomes 1200

Unit: seconds

The minimum time between two evaluations. Each evaluation takes the device off its network to test others, so evaluations are rationed. The moment an evaluation fires the current time is stored, before the baseline probe, so an evaluation that ends with the daemon staying put, or one whose baseline probe is not below the floor and therefore never leaves the network, still uses up the cooldown. The next evaluation needs both enough slow samples and this many seconds since the last one. The stored time starts at 0, so the first evaluation after the daemon starts is not delayed. The same value also sets how long a higher-priority network that measured too slow on return is set aside: three times the cooldown in force at that moment, during which the preferred-network look does not pick it.

At night `NIGHT_DANCE_COOLDOWN` (default 2400) takes its place; the elapsed time is compared against whichever value is in force when the check runs. Slow samples keep counting during the cooldown, so an evaluation fires on the first slow sample after it ends; a pass whose samples are ripe while the cooldown still runs says so once per cooldown window, with the minutes left. Only one set-aside network is remembered at a time; a newer too-slow return replaces it. Inert in signal mode (no evaluation and no set-aside).

Log lines:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] sustained slow upload on ${SSID} (${flow} kbps for ${UP_STRIKES} samples, floor ${floor}) - evaluating known networks`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] live stream starving on ${SSID} (${flow} kbps for ${UP_STRIKES} samples, floor ${STREAM_MIN_KBPS}) - evaluating known networks`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] preferred network ${SSID} too slow (${kbps} kbps, floor ${floor}) - benched for ${minutes} min, going back to ${previous}` (`- benched for ${minutes} min, staying on it` when there is no network to go back to; `, ends the bench on ${name}` is appended when another network's bench was still running; the minutes are three cooldowns, 60 by day and 120 at night with the defaults)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] upload still slow on ${SSID} (${flow} kbps, floor ${floor}) - evaluation on cooldown, next look in ${minutes} min` (once per cooldown window)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] live stream still starving on ${SSID} (${flow} kbps, floor ${STREAM_MIN_KBPS}) - evaluation on cooldown, next look in ${minutes} min` (the same under a live stream; the two share the window)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] day profile active until ${NIGHT_START} - floor ${MIN_UP_KBPS} kbps, a challenger must reach ${SWITCH_GAIN_PCT}% of the incumbent, evaluations ${minutes} min apart` (the minutes are this knob, rounded up)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] running with: ... one evaluation per ${minutes} min ...` (the start summary; the minutes are this knob, rounded up)

When to change it: raise it (3600 or more) when any interruption is costly and the set of nearby networks rarely changes; lower it (600) when networks come and go quickly, as on a moving vehicle or with rotating hotspots.

Each evaluation takes the device off its network for a minute or more; once every 30 minutes is enough.

```sh
DANCE_COOLDOWN=1800
```

### STREAM_MIN_KBPS

Default: `50`

Allowed: whole number 1 to 9999999; anything else becomes 50

Unit: kbps

The rate below which a running live stream counts as starving. While a stream, preview, still capture or file upload is running (a `raspistill` process whose command line names `live_raw`, `preview.jpg` or `capture.jpg`, or a `curl` process sending `upfile=@`), the real traffic is the meter and the day or night floor is not used for the slow-sample test. A 3-second transmit reading at or above `STREAM_MIN_KBPS` means the stream is healthy: no probe, no evaluation, and the slow-sample count clears. A reading from 5 kbps up to but not including this value is one starving sample; a reading under 5 kbps means the stream is not really moving, so nothing is counted and the count clears. When the sample count and the cooldown allow, the daemon logs the starving warning, sends one real probe under the stream, and only if that probe is below the day or night floor leaves the network to try the other stored networks against the gain bar. While a stream runs the preferred-network look is skipped entirely, and `awacs.sh status` shows a viewer row that begins `live - QA on hold`.

No night variant. Must sit below the stream's real bitrate; set above it, every healthy stream reads as starving and the daemon probes under it once per cooldown. Requires a probe target: in signal mode a starving stream is never acted on, because a real probe is what tells a starving stream from a deliberately small feed. The probe that follows is judged against the day or night floor, not this value. Shares the slow-sample count with the non-stream branch.

Log lines:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [DEBUG] QA(stream): flow=${flow} kbps, strikes=${strikes}`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] live stream starving on ${SSID} (${flow} kbps for ${UP_STRIKES} samples, floor ${STREAM_MIN_KBPS}) - evaluating known networks`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] scan heard ${count} networks: ${SSID} ${dBm}, ... | known on the air: ${SSID}, ... | stored, not heard: ${SSID}, ...` (strongest first, at most 10 names in each part, then `and ${n} more`; `none` in a part that is empty; `scan heard 0 networks | known on the air: none | stored, not heard: ${every stored network}` when the radio hears nothing; inside a recovery the line is said once per distinct picture per outage and counted after that)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] measured ${kbps} kbps on ${SSID}`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] measured ${kbps} kbps on ${SSID} - above the ${floor} kbps floor, staying`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] live stream still starving on ${SSID} (${flow} kbps, floor ${STREAM_MIN_KBPS}) - evaluation on cooldown, next look in ${minutes} min` (the stream still starving while the cooldown runs; once per cooldown window)

When to change it: set it to roughly half the lowest bitrate the stream produces. Raise it if the stream visibly stutters while the daemon stays silent; lower it if the daemon warns about starving during a low-quality feed that viewers find fine.

The stream runs at about 300 kbps; below 120 viewers see freezes.

```sh
STREAM_MIN_KBPS=120
```

## Night profile

Between `NIGHT_START` and `NIGHT_END`, when `NIGHT_MODE` is `yes`, three working thresholds are swapped: the upload floor (`MIN_UP_KBPS` gives way to `NIGHT_MIN_UP_KBPS`), the gain (`SWITCH_GAIN_PCT` to `NIGHT_GAIN_PCT`) and the cooldown (`DANCE_COOLDOWN` to `NIGHT_DANCE_COOLDOWN`). Nothing else changes at night: not `TICK`, not `UP_STRIKES`, not `STREAM_MIN_KBPS`, not `PREF_CHECK`, not `REBOOT_AFTER_MIN`.

The check runs at the top of every pass of the main loop, against the device's own clock, read with `date +%H` and `date +%M` in the zone the daemon runs in (`SITE_TZ` plays no part; it concerns the site stamps only). The computed profile is compared with the remembered one and nothing happens while it is unchanged; on a change the three values are swapped and one line is written. Because nothing is remembered at start, the very first pass with the profile on always writes one of the two profile lines, then only real changes are logged. Only the daemon applies the profile: `awacs.sh status`, `networks`, `evaluate`, `scan`, `speed` and `check` run in their own process, never apply it and never read the floor, the gain or the cooldown: `evaluate` orders the visible networks by signal, and `speed` runs one probe and prints the figure without comparing it with any floor.

### NIGHT_MODE

Default: `"yes"`

Allowed: exactly the lowercase word `yes` turns the night profile on; any other value (`no`, `YES`, `true`, `1`, empty) leaves it off, silently: there is no validation, no fallback and no log line for this knob, so a misspelling means off

Unit: yes/no switch

Turns the night profile on or off. When it is `yes`, the daemon starts every pass by reading the clock, deciding whether the current time lies inside the window and swapping the three working thresholds between the day values and the night values. While the internet is up a pass takes about `TICK` plus 3 seconds, so with the defaults the check runs roughly every 13 seconds. When it is anything but `yes` the profile function returns at once: the day values stay in force around the clock, no profile line is ever written, and the DEBUG `QA` line always shows `profile=day`.

With `NIGHT_MODE=yes` the other five night knobs matter; with it off they are ignored entirely. `TICK` is not changed at night. In signal mode the night floor, gain and cooldown have no effect, because every slow-upload check is skipped, but the two transition lines are still logged.

Log lines:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] night profile active until ${NIGHT_END} - floor ${NIGHT_MIN_UP_KBPS} kbps, a challenger must reach ${NIGHT_GAIN_PCT}% of the incumbent, evaluations ${minutes} min apart`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] day profile active until ${NIGHT_START} - floor ${MIN_UP_KBPS} kbps, a challenger must reach ${SWITCH_GAIN_PCT}% of the incumbent, evaluations ${minutes} min apart`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [DEBUG] QA: flow=${flow} kbps, strikes=${strikes}, profile=${day|night}`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] running with: measured mode, floor ${MIN_UP_KBPS}/${NIGHT_MIN_UP_KBPS} kbps day/night (night ${NIGHT_START}-${NIGHT_END}), ...` (the start summary; `floor ${MIN_UP_KBPS} kbps (night profile off)` with the profile off)

When to change it: set it to `no` when the feed is watched around the clock and you want the same strictness at every hour, or when the device clock is unreliable (no time sync) and a wrong-hour profile would be worse than none. Leave `yes` for a camera whose viewers sleep at night.

This camera is watched by a night shift; keep the day rules all night.

```sh
NIGHT_MODE="no"
```

### NIGHT_START

Default: `"22:00"`

Allowed: `HH:MM` on a 24-hour clock, hour 0 to 23 with one or two digits (`6:00` and `06:00` both pass), one colon, minutes 00 to 59 with exactly two digits, and nothing else (no seconds, no `24:00`, no bare hour, no spaces); a malformed or empty value becomes `22:00`, and `NIGHT_END` is checked on its own, so one bad value does not reset the other

Unit: clock time, device local time

The minute of the day at which the night profile begins. The script converts it to minutes since midnight and compares it with the current time, read on every pass from the device clock with `date +%H` and `date +%M` (the clock and zone the daemon runs in; `SITE_TZ` plays no part). The start minute itself is inside the window. If `NIGHT_START` is later in the day than `NIGHT_END` (the default 22:00 to 06:00) the window wraps past midnight: it is night when the time is at or after `NIGHT_START` or before `NIGHT_END`. If `NIGHT_START` is earlier than `NIGHT_END` (say 01:00 to 05:00) the window lies inside one day: night when the time is at or after `NIGHT_START` and before `NIGHT_END`. If the two are equal the window is empty and the night profile never activates.

Ignored unless `NIGHT_MODE=yes`. Pairs with `NIGHT_END`. The switch lands within about 13 seconds of the boundary when the daemon is idle, later if a recovery run or an upload probe is keeping the loop busy. A board without a battery-backed clock that has not yet synced time picks the profile from whatever time it believes. `NIGHT_END` is validated separately, so one bad value does not reset the other.

Log lines:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] night profile active until ${NIGHT_END} - floor ${NIGHT_MIN_UP_KBPS} kbps, a challenger must reach ${NIGHT_GAIN_PCT}% of the incumbent, evaluations ${minutes} min apart`

When to change it: move it later when the household or business stays active into the late evening, earlier when viewing stops early. Use a start later than the end to span midnight, a start earlier than the end for a window inside a single day.

The shop closes at 23:30 and nobody watches after that.

```sh
NIGHT_START="23:30"
```

### NIGHT_END

Default: `"06:00"`

Allowed: same shape as `NIGHT_START`; anything else becomes `06:00`

Unit: clock time, device local time

The minute of the day at which the night profile ends and the day values return. The end minute is not part of the window, so at exactly `NIGHT_END` the day profile applies. Together with `NIGHT_START` it defines the window: when `NIGHT_END` is earlier in the day than `NIGHT_START` the window wraps midnight; when it is later the window sits inside one day; when both are equal no minute is ever night.

Ignored unless `NIGHT_MODE=yes`. Evaluated against the device clock on every pass. On the first pass after the daemon starts, whichever profile the clock says is written to the log once; after that only changes are logged.

Log lines:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] day profile active until ${NIGHT_START} - floor ${MIN_UP_KBPS} kbps, a challenger must reach ${SWITCH_GAIN_PCT}% of the incumbent, evaluations ${minutes} min apart`

When to change it: set it to the hour when people start watching again. If you want the relaxed rules all day long, do not set the start equal to the end (that disables the night profile); lower the day knobs themselves instead.

The first viewer looks at the feed after seven.

```sh
NIGHT_END="07:00"
```

### NIGHT_MIN_UP_KBPS

Default: `200`

Allowed: whole number 1 to 9999999 (leading zeros are dropped, so `0200` becomes 200); zero, a negative number, a decimal, an empty value or text becomes 200, and the knob is named in the fallen-knobs line at start

Unit: kbps

The minimum acceptable upload speed while the night profile is active; it replaces `MIN_UP_KBPS` and is used in the same four places. On every healthy pass with no stream, preview, capture or upload in progress, a transmit-counter reading of at least 20 kbps but below this floor counts as one slow sample. After `UP_STRIKES` slow samples, and once the cooldown has passed, the daemon probes the current network by uploading a test body of `PROBE_KB` kilobytes to the probe target (15 seconds at most; a failed probe reads 0), and only if that measured rate is also below this floor does it go on to test the other stored networks; otherwise the samples are cleared. On return to a higher-priority network, a measured upload below this floor makes the daemon set that network aside for three times the cooldown and go back to the previous one. While testing candidates, once one uploads at four times this floor or more the daemon stops testing further candidates as plainly fast enough; this also applies during the recovery from lost internet.

Effective only with `NIGHT_MODE=yes` and inside the window; by day `MIN_UP_KBPS` is used. Needs a probe target: without one the slow-sample check, the measured-upload checks and the set-aside test are all skipped, so the floor changes nothing. While a live stream is running the slow-sample gate uses `STREAM_MIN_KBPS` instead, but the measured-upload check that follows still uses this floor. `UP_STRIKES` is the same by day and night. The four-times early stop means a lower night floor also lets recovery settle sooner on a merely adequate network (800 kbps at night versus 1600 by day with the defaults). With a floor of 20 or below the passive check can never count a slow sample, because it only looks at activity of at least 20 kbps; the two measured-upload comparisons that remain (after a starving stream, and on return to a higher-priority network) then fire only when the probe measures below that tiny number, which in practice means only when it fails and returns 0.

Log lines:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] night profile active until ${NIGHT_END} - floor ${NIGHT_MIN_UP_KBPS} kbps, a challenger must reach ${NIGHT_GAIN_PCT}% of the incumbent, evaluations ${minutes} min apart`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] sustained slow upload on ${SSID} (${flow} kbps for ${UP_STRIKES} samples, floor ${floor}) - evaluating known networks`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] scan heard ${count} networks: ${SSID} ${dBm}, ... | known on the air: ${SSID}, ... | stored, not heard: ${SSID}, ...` (strongest first, at most 10 names in each part, then `and ${n} more`; `none` in a part that is empty; `scan heard 0 networks | known on the air: none | stored, not heard: ${every stored network}` when the radio hears nothing; inside a recovery the line is said once per distinct picture per outage and counted after that)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] measured ${kbps} kbps on ${SSID}`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] measured ${kbps} kbps on ${SSID} - above the ${floor} kbps floor, staying`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] preferred network ${SSID} too slow (${kbps} kbps, floor ${floor}) - benched for ${minutes} min, going back to ${previous}` (`- benched for ${minutes} min, staying on it` when there is no network to go back to; `, ends the bench on ${name}` is appended when another network's bench was still running; the minutes are three cooldowns, 60 by day and 120 at night with the defaults)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] candidate [${id}] ${name} uploads at ${kbps} kbps`

When to change it: lower it when the overnight feed is small (a low-quality night stream needs far less than the day feed) and you would rather stay on a slow but stable link than hunt for a faster one; raise it toward the day value if night uploads are as heavy as day uploads.

The night stream runs at low quality and 100 kbps carries it.

```sh
NIGHT_MIN_UP_KBPS=100
```

### NIGHT_GAIN_PCT

Default: `300`

Allowed: whole number 1 to 9999999; anything else becomes 300; values below 100 pass validation but would let a slower network replace the current one

Unit: percent of the current network's measured upload speed

How much faster another stored network must upload before the daemon switches to it at night; it replaces `SWITCH_GAIN_PCT`. When an evaluation starts, the daemon first measures the current network's real upload speed, then computes the bar as that measurement times `NIGHT_GAIN_PCT` divided by 100, in whole numbers. It connects to each other visible stored network in turn and measures it (stopping early once one reaches four times the night floor); the best candidate wins only if its measured upload reaches the bar and is above zero. Otherwise the daemon reconnects the original network and logs that nobody beat it; if that reconnect fails, it takes the best candidate anyway. With the default 300 a candidate must upload three times as fast as the current network, versus one and a half times by day.

Effective only with `NIGHT_MODE=yes` and inside the window. Used only in the two slow-upload evaluations, which need a probe target and are gated by `NIGHT_MIN_UP_KBPS` (the evaluation happens only when the measured upload is below the floor) and by `NIGHT_DANCE_COOLDOWN`. It is not used in the recovery from lost internet, where the best measured candidate wins. When the current network's measurement is 0 (probe target unreachable while the internet is up) the bar is 0 and only the above-zero rule keeps the current network. A very high value forbids night switching in practice, but the daemon still visits and measures the candidates, interrupting the connection for the duration, before returning.

Log lines:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [OK] no challenger beat the incumbent - staying on ${SSID} (best was ${name} at ${kbps} kbps, needed ${bar})` (the closest candidate and the bar it had to reach; inside a recovery the line ends at the name)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] could not return to ${SSID}: ${reason}`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] switching to ${SSID} (${best_kbps} kbps against ${kbps} kbps here)`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [OK] switched to ${SSID} (upload ${best_kbps} kbps)`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] switching to ${SSID} failed: ${reason} - going back to ${home}`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [OK] back on ${SSID}`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] night profile active until ${NIGHT_END} - floor ${NIGHT_MIN_UP_KBPS} kbps, a challenger must reach ${NIGHT_GAIN_PCT}% of the incumbent, evaluations ${minutes} min apart`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] measured ${kbps} kbps on ${SSID} - under the ${floor} kbps floor, a challenger must beat ${bar} kbps` (the bar this knob sets at night)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] switching to ${SSID} (${best_kbps} kbps, below the ${bar} kbps bar) - the best left, ${home}: ${reason}`

When to change it: raise it when night switches have been happening for marginal gains; lower it, toward the day value, when the night link is genuinely bad and a moderately better network should be allowed to take over.

At night, move only when another network uploads at least twice as fast.

```sh
NIGHT_GAIN_PCT=200
```

### NIGHT_DANCE_COOLDOWN

Default: `2400`

Allowed: whole number 1 to 9999999; anything else becomes 2400

Unit: seconds

The minimum time between two evaluations while the night profile is active; it replaces `DANCE_COOLDOWN`. An evaluation starts only when the slow-sample count has reached `UP_STRIKES` and at least this many seconds have passed since the previous evaluation began. The timer starts at zero when the daemon starts, so the first evaluation after a start is never delayed by it. The same value, times three, is how long a higher-priority network that measured too slow on return is set aside before the daemon tries to go back to it again (7200 seconds, two hours, at night by default; one hour by day).

Effective only with `NIGHT_MODE=yes` and inside the window. The comparison uses whichever profile is active at the moment of the check, not at the moment of the last evaluation: an evaluation that ran at 21:50 by day is followed, once 22:00 arrives, by a 2400-second wait measured from 21:50. Evaluations also need a probe target and a measured upload below the floor; slow samples reset to zero on every pass in which the passive activity is outside the slow band, so the wait only matters while uploads stay slow. Each evaluation interrupts real traffic, which is why the night value is longer.

Log lines:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] sustained slow upload on ${SSID} (${flow} kbps for ${UP_STRIKES} samples, floor ${floor}) - evaluating known networks`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] live stream starving on ${SSID} (${flow} kbps for ${UP_STRIKES} samples, floor ${STREAM_MIN_KBPS}) - evaluating known networks`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] preferred network ${SSID} too slow (${kbps} kbps, floor ${floor}) - benched for ${minutes} min, going back to ${previous}` (`- benched for ${minutes} min, staying on it` when there is no network to go back to; `, ends the bench on ${name}` is appended when another network's bench was still running; the minutes are three cooldowns, 60 by day and 120 at night with the defaults)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] night profile active until ${NIGHT_END} - floor ${NIGHT_MIN_UP_KBPS} kbps, a challenger must reach ${NIGHT_GAIN_PCT}% of the incumbent, evaluations ${minutes} min apart` (the minutes are this knob, rounded up)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] upload still slow on ${SSID} (${flow} kbps, floor ${floor}) - evaluation on cooldown, next look in ${minutes} min` (once per cooldown window)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] live stream still starving on ${SSID} (${flow} kbps, floor ${STREAM_MIN_KBPS}) - evaluation on cooldown, next look in ${minutes} min`

When to change it: raise it when overnight evaluations are disturbing recordings or the stream and the link is only marginally slow; lower it when a slow night link should be re-examined sooner.

At most one evaluation per hour at night.

```sh
NIGHT_DANCE_COOLDOWN=3600
```

## Behaviour

Three switches. None of them passes through the validation block: each is compared once with the exact lowercase word `yes` at the one place it is used; any other spelling means off, silently, with no fallback and no warning. The template writes `"yes" | "no"`, but only `yes` is recognised.

The order of a recovery run decides when the open networks come in. A run starts at boot without internet, or after `NET_FAIL_TICKS` consecutive passes without it, the latter announced by `internet lost on ${SSID} - router ${still answers|silent too|none (not associated)}, engaging`, the former by `no internet at start on ${SSID} - router ${state}, engaging`. It first drops any temporary entry left from the previous attempt, then opens gently (a reassociation and a wait; in the first run of an outage the reassociation is skipped while the default gateway still answers), then runs up to three rounds. In each round the stored networks are tried first, unless NetworkManager itself is in the middle of a connection; then the diagnosis decides: on-device evidence (the gateway silent, no successful association in this round, plus a visible stored network, an empty scan or an empty stored list) triggers the round's recovery step, then the emergency networks, then the open networks; otherwise the outage is called external (`outage looks external: the router answers, the fault is upstream (round ${round}) — waiting, not rebooting`, or one of the other verdict lines listed under [REBOOT_AFTER_MIN](#reboot_after_min)) and the emergency and then the open networks are tried before a 20-second wait, a failed attempt being followed by a return to the network the run started on and by re-enabling every stored network. On NetworkManager, inside the on-device branch, a NetworkManager still activating makes the round wait 20 seconds and continue with no emergency or open attempt, and a NetworkManager reporting connected without internet skips the recovery step and goes straight to the emergency and then the open networks. A successful connection to an open or emergency network is followed by the main loop's `internet restored: ${SSID} - down ${duration}, ${n} recovery ${run|runs}` line on the first healthy pass, for a run started from a pass and for the boot run alike.

### OPEN_NETWORKS

Default: `"yes"`

Allowed: the word `yes` turns it on; any other value (`no`, empty, `YES`, `true`, `1`) turns it off, with no fallback and no warning

Unit: yes/no switch

When the device has lost the internet and neither its stored networks nor the emergency networks bring it back, this switch lets the daemon join a passwordless network that anybody nearby broadcasts. Open networks are the last step of each of the up to three rounds of a recovery run: after the gentle first step, after the stored networks, and after the emergency networks that follow the round's recovery step (for an on-device fault) or follow the classification directly (for an external outage). On a NetworkManager image two special cases apply: when NetworkManager reports connected but there is no internet, the recovery step is skipped and the emergency and then the open networks are tried directly; when NetworkManager is found mid-activation after the on-device evidence has been gathered, the round only waits 20 seconds and moves on, trying neither; a NetworkManager that is busy at the start of a round takes the external path, where the emergency and open networks are still tried. Only networks the scan marks as open are candidates: on the legacy backend a network counts as secured when its `iw` capability line carries Privacy or a WPA or RSN block (with `iwlist` as the fallback: `Encryption key:on`; with the supplicant table as the fallback: flags carrying WPA, RSN or WEP); on NetworkManager a network is open when the `SECURITY` column of `nmcli` is empty. Open strangers with a signal below -80 dBm (wpa) or 25 percent (NetworkManager) are skipped, a dual-band network counts once, and a network whose splash page intercepts traffic fails the internet check, so it is dropped again unless the portal lets ping through, since a ping answer alone counts as online. The network is added as a temporary entry that is never written to disk: on wpa an in-memory supplicant entry with `key_mgmt NONE`; on NetworkManager a keyfile under `/run/NetworkManager/system-connections`, named on the daemon's own pattern, with `autoconnect=false`, gone at reboot. Its id is written to `RUN_DIR/open_id` before the attempt so a crashed daemon's successor removes it at start; on success the stored networks are re-enabled so the device can drift back home on its own, and the temporary entry is deleted on the first healthy pass that finds the device on a different network, at the start of the next recovery run, and after the third recovery step on NetworkManager.

Emergency networks (`SAFETY_NET`) are always tried first; open networks are reached only when that list is empty or every entry failed. On the legacy wpa backend (`dhcpcd` and `wpa_supplicant`) any open network whose name contains non-ASCII characters, or a literal backslash, is skipped, because the scan escapes such names in the `\xNN` form and the supplicant's quoted form cannot carry a backslash; on NetworkManager names are matched as hex bytes and written as byte arrays, so Arabic, emoji and symbol names are usable. Monitor-only mode never runs a recovery, so the switch has no effect there. The marker `open_id` moves with `RUN_DIR`. On wpa the candidates come from the scan picture, served from the cache while it is younger than `SCAN_TTL`; on NetworkManager they come from NetworkManager's own list with its rescan. The two story lines below reach the site when `LOG_TARGET` is `both` or `remote` and `SITE_URL` is set; under `remote` they are not kept in the local file, and `LOG_LANG=ar` replaces their local text with the Arabic wording. Retiring the entry is said with the entry's name: `back on a stored network: ${SSID} - temporary network ${name} removed` on the healthy pass that finds the device home, `dropping temporary network ${name} - it stopped delivering` at the start of the next recovery, and `removed the temporary network ${name} left by the previous run` at a daemon start (with `- the device was still on it, recovery follows` when the device still rode it); on NetworkManager a profile already gone by then writes one DEBUG line, and the deletion guard's refusal one ERROR line beginning `REFUSING delete:`. On NetworkManager the deletion helper refuses to remove any profile the daemon did not create (a name that does not follow its pattern, or a file outside `/run/NetworkManager/system-connections/awacs-*`), so your own profiles are never touched.

Log lines:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] trying open networks as last resort (${n} open networks heard)` (once per outage; the count is the open networks in the list the walk reads)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] open network ${SSID} linked but no internet (captive portal?) - trying the next` (once per outage per network; a stranger that refuses the association is counted, not said)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] no open network delivered internet (${heard} heard, ${tried} tried, ${portals} linked without internet)` (the walk ended without a win, also when nothing open was heard; once per outage)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [OK] connected to OPEN network: ${SSID} (upload ${kbps} kbps) - stored networks stay armed, home again when one returns` (`(signal mode)` in place of the upload figure without a probe target)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] dropping temporary network ${name} - it stopped delivering` (the next recovery starts while the device is on the entry; once per outage)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [OK] back on a stored network: ${SSID} - temporary network ${name} removed` (the healthy pass that finds the device on a stored network)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] removed the temporary network ${name} left by the previous run` (a daemon start that finds the marker; `[WARN]` with `- the device was still on it, recovery follows` appended when the device still rode the entry)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [DEBUG] connect_id: activating ${id} (backend ${BACKEND})`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [DEBUG] del_own: ${uuid} already gone` (NetworkManager, when the temporary entry has already vanished by the time it is retired)

When to change it: set it to `no` when the device must never attach to a stranger's network (site policy, or a place full of hotel and cafe portals where each attempt is wasted). Keep `yes` for a device whose only duty is to get its data out and where any working internet beats none.

This camera sits in an office where joining unknown networks is not allowed.

```sh
OPEN_NETWORKS="no"
```

### STEALTH_MODE

Default: `"no"`

Allowed: the word `yes` turns it on; any other value (`no`, empty, `YES`, `true`) leaves it off, with no fallback and no warning

Unit: yes/no switch

Makes the device harder to spot with a casual IPv4 ping sweep or an mDNS browser on the local network. Once, during daemon start, it adds one firewall rule that silently drops incoming ping requests arriving on the WiFi interface: it first tests whether the rule exists (`iptables -C INPUT -i "$IF" -p icmp --icmp-type echo-request -j DROP`) and only if absent inserts it at the top of the INPUT chain (`iptables -I` with the same arguments), so a respawning launcher never stacks duplicate rules. It then stops the Avahi service with `systemctl stop avahi-daemon`: the service is stopped, not disabled or masked, so it returns at the next boot and is stopped again when the daemon starts. Only incoming IPv4 ping requests are blocked: the rule lives in the INPUT chain and matches echo requests only, so the daemon's own outgoing pings and their replies still pass and the internet check and the gateway check keep working; no `ip6tables` rule is added, so an IPv6 ping still gets an answer. Each leg is checked: when the rule is in place and Avahi is stopped (or absent) the INFO line below is written; otherwise a WARN names what failed, and the device still answers pings or still announces itself. Nothing is undone when the daemon stops (the stop handler only re-enables the stored networks and prints the farewell box): the ping-drop rule stays in the kernel until reboot or a manual `iptables -D INPUT -i ${IF} -p icmp --icmp-type echo-request -j DROP`, and Avahi stays stopped until reboot, a manual `systemctl start avahi-daemon`, or socket activation. The DHCP hostname is not hidden by this switch; do that in `/etc/dhcpcd.conf` if wanted.

The rule binds to the detected interface (or `AWACS_IF`) only; a second WiFi dongle or the Ethernet port still answers pings. `iptables` is not in the daemon's tool inventory, so a missing binary is not installed; it is reported in the WARN line below. Monitor-only mode parks before this step, so stealth is never applied there. The toolbox words never apply it. Only `avahi-daemon.service` is stopped; `avahi-daemon.socket` is left alone, so socket activation can start the service again before the next boot if a local program opens Avahi's socket. The story line reaches the site when `LOG_TARGET` is `both` or `remote` and `SITE_URL` is set, and under `remote` it is not kept in the local file; `LOG_LANG=ar` replaces its local text with the Arabic wording. With stealth on, IPv4 ping from the LAN to the device fails and `hostname.local` stops resolving, so LAN monitoring that relies on either must use another method.

Log lines:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] stealth mode active (icmp hidden, avahi stopped)`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] stealth mode partly active: ${parts}` (once at start; the parts, comma-joined, are one or two of `iptables missing - pings still answered`, `ping rule could not be added - pings still answered` and `avahi could not be stopped`; an image without Avahi is not a failure)

When to change it: turn it on for a device that lives on a shared or untrusted network (a shared building WiFi, a hotspot with strangers) where you do not want it visible to neighbours. Leave it off when you check the device from the LAN with ping or find it by `hostname.local`, since both stop working. It is applied once at start and not removed at stop.

The camera hangs on a shared building network and should not show up on a ping sweep.

```sh
STEALTH_MODE="yes"
```

### DEBUG

Default: `"no"` (or the value of the `AWACS_DEBUG` environment variable when that is set and not empty)

Allowed: the word `yes` writes DEBUG lines; any other value (`no`, empty, `YES`, `true`) silences them, with no fallback and no warning

Unit: yes/no switch

Controls whether the daemon writes its decision-trace lines, at level DEBUG, into the local log file. These lines go straight to `LOG_FILE`: they never travel to the reporting site, they are always in English whatever `LOG_LANG` says, and they are still written locally under `LOG_TARGET=remote`, because that filter concerns story lines only. There are exactly seven of them: the number of radio scan tries used after each fresh scan (only when the scan cache was older than `SCAN_TTL`); on NetworkManager, a note when a temporary entry asked to be deleted is already gone; a line before every network activation the daemon performs, naming the id and the backend; the outcome of each preferred-network look, with the current and best priorities and any set-aside network; a line during a recovery round when the evidence points to an on-device fault; and, on every healthy pass, one upload-meter line with the transmit-counter rate and the slow-sample count, either the `QA(stream)` form while a live stream or upload is running or the `QA` form with the day or night profile otherwise. The default is taken from the environment: an exported non-empty `AWACS_DEBUG` (in `rc.local` before the launch loop, or an `Environment=` line in the systemd unit) becomes the default, while an unset or empty `AWACS_DEBUG` gives `no`. The settings file is read afterwards, so a `DEBUG=` line there overrides both the built-in default and the environment variable, and the value is then sealed.

`AWACS_DEBUG` supplies the default only; a `DEBUG` line in the file wins. The `-d` self-daemonize relaunches the script through `setsid` and hands the environment on to the background daemon, so `AWACS_DEBUG` carries through. DEBUG lines count toward the log rotation: with `DEBUG=yes` one `QA` line lands every healthy pass, and a pass takes about `TICK` plus 3 seconds, so the 1500-line `LOG_CAP` holds roughly five hours of a healthy day instead of days of story lines. `LOG_LANG`, `LOG_TARGET` and `SITE_URL` have no effect on these lines. With `NIGHT_MODE` off the `QA` line always reads `profile=day`. In signal mode the `QA` lines still print the flow, but no evaluation follows. The toolbox words run as root with the file loaded and write to the same log: `evaluate` and `scan` call the scanner on both backends, and `networks` does so on the wpa backend, so a hand-run command also writes the `scan:` DEBUG line into the daemon's log whenever the scan cache is older than `SCAN_TTL`; `status` and `speed` never scan; `check` and `help` run without root and never write DEBUG lines.

Log lines:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [DEBUG] scan: ${used}/${tries} tries used`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [DEBUG] del_own: ${uuid} already gone`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [DEBUG] connect_id: activating ${id} (backend ${BACKEND})`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [DEBUG] best_pref_id: cur=${current_id}(p=${current_priority}) -> best=${candidate_id|none}(p=${best_priority}) veto=${set_aside_id|none}`
- the on-device evidence line of a recovery round, which names the round number and whether a wrong password was seen
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [DEBUG] QA(stream): flow=${flow} kbps, strikes=${strikes}`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [DEBUG] QA: flow=${flow} kbps, strikes=${strikes}, profile=${day|night}`

When to change it: set it to `no` once a device is stable and you want the local log to keep days of story lines instead of hours of per-pass meter readings. Keep `yes` while working out why the device did or did not switch networks: the DEBUG lines are the only record of the per-pass upload meter, the slow-sample count, the preferred-network verdicts and the on-device fault evidence. Use `AWACS_DEBUG` when the launcher rather than the settings file should decide, and then leave `DEBUG` out of the file, or the file wins.

The device has run cleanly for weeks; keep the 1500-line log for the story, not the meter.

```sh
DEBUG="no"
```

## Files

Five knobs place the daemon's files and bound their sizes. `LOG_CAP`, `SCAN_TTL` and `SPOOL_CAP` follow the numeric rule; `RUN_DIR` must begin with `/`; `LOG_FILE` is never checked. All five are sealed after loading, so a change needs a daemon restart. Two files have no knob and a fixed path, `/etc/awacs.key` and `/etc/awacs.networks`; they are described after the `RUN_DIR` list.

### LOG_FILE

Default: `/var/log/awacs.log`

Allowed: any absolute path; the script never checks the value (it is the only Files knob absent from the validation block: no test that the path is absolute, no test that it exists), so there is no fallback

Unit: file path

The local log. Every line the daemon writes locally goes through one function that appends `yyyy-mm-ddThh:mm:ss+hh:mm [LEVEL] text` to this path; the levels are INFO, OK, WARN, ERROR and DEBUG. The file is created on the first write, readable by root only, because the script sets `umask 077` near its start, before any file is touched. A write never waits on the network and never stops the daemon: when the path cannot be opened for appending (a missing directory, a read-only or full filesystem, an empty value), each line is dropped, the line count that follows reads zero, and the daemon keeps running; the first healthy pass after a failed append says so to the site once, and the first after an append succeeds again says that too (the lines below). When the file grows past the `LOG_CAP` limit it is trimmed through a sibling temporary file, `${LOG_FILE}.t`, that is renamed over the log.

`LOG_LANG` picks the language of the story lines written here (DEBUG lines stay English). `DEBUG=yes` writes one DEBUG line on every healthy pass, which is what fills the file. `LOG_TARGET=remote` keeps only the WARN and ERROR story lines locally, but DEBUG lines, local-only lines and the `reporting:` line at start (and the downgrade warning when it applies) still land here. `LOG_CAP` sets the trim size. Every root run of the script, the toolbox words included, appends through the same function. `install.sh --uninstall --purge` removes only the default path and its `.t` sibling, not a moved log. The optional terminal tool `tools/awacs-tui.sh` reads `LOG_FILE` from the settings file and accepts only an absolute value.

Log lines:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [${LEVEL}] ${text}` (the shape of every local line)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] local log ${LOG_FILE} not writable - SD card read-only? the site keeps the story` (once per failure streak; its own local copy fails too)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [OK] local log ${LOG_FILE} writable again`

When to change it: rarely. Move it when the log must live on another disk (a USB stick, to spare the SD card) or where another tool expects it. The directory must exist and be writable at the moment of each write: lines written before it is available are lost, with no fallback and no warning.

Keeps the per-pass DEBUG writes off the SD card; lines written before `/mnt/usb` is mounted are lost, and the first healthy pass reports the failure to the site once.

```sh
LOG_FILE=/mnt/usb/awacs.log
```

### LOG_CAP

Default: `1500`

Allowed: whole number 1 to 9999999; anything else becomes 1500

Unit: lines

How many lines the local log keeps after a trim. After every line it writes, the daemon counts the file's lines; when the count exceeds `LOG_CAP` plus 200, it copies the newest `LOG_CAP` lines into `${LOG_FILE}.t` and renames that file over the log. So the file grows from `LOG_CAP` to `LOG_CAP` plus 201 lines and is cut back to `LOG_CAP`, again and again; the 200-line slack means the copy happens about once per 200 lines rather than on every write. Nothing is archived: the older lines are gone. The trim itself writes no log line.

With `DEBUG=yes` and the internet up, one DEBUG line is written per pass; a pass is `TICK` seconds plus the 3-second sample, about 13 seconds with the defaults, so roughly 280 lines an hour, and the default 1500 lines hold about five hours of history. With `DEBUG=no` only events are written and the same cap covers days or weeks. A smaller `TICK` fills it faster. `LOG_TARGET=remote` reduces the story lines kept locally. Every written line costs one count of the whole file, so a very large cap on a slow SD card adds work to every write. Any root run of the script, the toolbox words too, writes through the same function and can perform the trim.

Log lines: none

When to change it: raise it when a problem must be traced over more than a few hours of DEBUG output (or set `DEBUG=no` instead and keep the cap); lower it on a very small card.

About eighteen hours of DEBUG-level history with the default tick, enough to read an overnight outage in the morning.

```sh
LOG_CAP=5000
```

### RUN_DIR

Default: `/run/awacs`

Allowed: a path that begins with `/`; anything else, an empty value included, becomes `/run/awacs`; the directory is created at start when missing and a creation failure is ignored

Unit: directory path

The private directory holding every runtime file of the daemon (listed below). Every path under it is computed after the settings file is read, so changing `RUN_DIR` moves all of them together. The directory is created on every root run, after the root check and the interface choice and before anything touches a runtime file, with mode 0700 (`install -d -m 700`, with `mkdir -p` followed by `chmod 700` as the fallback); every file inside is created readable by root only. On the default path `/run` is memory-backed and emptied at every boot, which the per-boot markers rely on.

If the directory cannot be created or written, the lock file cannot be opened and the daemon does not run; the `rc.local` loop or the systemd unit (`RestartSec=10`) starts it again every 10 seconds, so the path must be on a writable filesystem from early boot. The markers assume the directory is emptied at reboot: on persistent storage `starts` would count restarts across boots, `lock_lost` would silence the second-launcher warning for good, `apt_tried` would block the automatic tool install on every later boot, and on the wpa backend a stale `open_id` from an earlier boot is handed to `remove_network` at the next start with no name check, which can remove a real stored network from the running supplicant until the supplicant restarts (the NetworkManager backend checks the entry's name and file location first and refuses anything it did not create). The toolbox words share the directory as root: `status` reads the lock for the PID; `scan`, `evaluate` and, on wpa, `networks` share the scan cache. `install.sh` uses the fixed default path for its own status and uninstall; the optional terminal tool `tools/awacs-tui.sh` reads `RUN_DIR` from the settings file and accepts only an absolute value. The rootless `check` and `help` never create it.

Log lines: none

When to change it: almost never. Only when `/run` cannot be used on an image; keep it on memory-backed storage so the per-boot markers still vanish at reboot.

An image where `/run` is locked down; still memory-backed, so the markers and the cache vanish at reboot as designed.

```sh
RUN_DIR=/dev/shm/awacs
```

### What lives under RUN_DIR

- `lock`: the single-instance lock, held on file descriptor 9 for the daemon's whole life. Its content is the daemon's PID, written by the instance that won the lock and opened in append mode so a losing second instance cannot wipe it. Background helpers close descriptor 9 so they never hold the lock. `awacs.sh status` reads it and checks that `/proc/${pid}/cmdline` names awacs before calling the daemon running, and the terminal box for a second launch shows it.
- `scan`: the scan cache, one line per network (name, signal, `open` or `sec`, tab-separated), strongest first. Its modification time is the age used against `SCAN_TTL`.
- `scan.empty`: a counter of consecutive scans that heard nothing from every source, removed the moment anything is heard; at three (a fixed count, not a knob) the cache is dropped.
- `scan.at`: the unix time of the last scan that really hit the radio (the picture, the tool fallback or the verdict that nothing was heard); the scan list is published once per such scan.
- `spool`: site-bound lines not yet delivered. `spool.sending`: the snapshot being sent during a delivery, rescued at the next start if a delivery was interrupted. `spool.t`: the temporary file used while trimming or merging.
- `open_id`: the id (wpa network number or NetworkManager profile UUID) of the temporary entry the daemon created itself for an open network or an emergency network. Written before each attempt and kept while the entry is in use, removed when the entry is retired or the attempt fails. A restarted daemon reads it first and removes that entry, so nothing the daemon created outlives it (on NetworkManager after checking the entry's name and file location; on wpa with no check).
- `probe`: `PROBE_KB` kilobytes of zeros used as the upload body when `curl` is missing or returned no speed and `wget` is used instead; deleted right after the measurement.
- `apt_tried`: an empty marker created before the single background package-install attempt of a boot; while it exists no further attempt is made.
- `starts`: the number of daemon starts in this boot, written by the instance that won the lock; the start line reads it to say `first start of this boot` or `restart ${n} of this boot`.
- `lock_lost`: a marker that the once-per-boot warning about a second launcher has been said.
- `probe.fail`: a marker that the last upload probe was accepted nowhere; it turns a measured 0 into the probe-failed line.
- `site.down`, `wifi.down`, `scan.down`, `log.down`: one marker per reporting channel in a refusal or failure episode (the site refusing story lines, the site refusing the WiFi cell, the site refusing the scan list, the local log not accepting appends); each is removed when the channel works again, so the episode is said once.
- `spool.dropped`: the number of lines the spool's cap dropped since the story last went out in full; said once and removed when a delivery sends everything held.
- `cmd`: a command from the site's WiFi menu, one line `<uptime_seconds>\t<epoch>\t<cmd>\t<key>\t<blob>`, written by the site's relay on the device (mode 0600) and deleted by the daemon the moment it is read, before anything acts on it; one left by a previous run is read at the first loop top and answered `failed expired` when older than 60 s by uptime, otherwise served. The line shape and the states are in [integration.md](integration.md).
- `cmd.ready`: an empty marker that a daemon holding the lock traps `SIGUSR1`; created right after the lock is won, removed at every exit. The relay signals only while it exists, so a daemon from before the command channel is never signalled (the signal would kill it).
- `cmd.last`: the epoch of the last command consumed; a command delivered again with the same epoch is ignored.
- `cmd.answer`: the latest answer to a command, kept until the site takes it with a 2xx and re-sent on every healthy tick until then.
- `join_id`: `<id>\t<hexssid>` while a join from the site is unfinished (the entry exists, the password is not yet proven); removed once `/etc/awacs.networks` holds the line. A restarted daemon reads it first and removes the unfinished entry, `removed an unfinished join of NAME left by the previous run`.

Beside the log, not under `RUN_DIR`: `${LOG_FILE}.t`, the rotation temporary; and the self-reboot memory, written just before a reboot the daemon orders and read at the next start: `${LOG_FILE}.reboot` (one line: the time, the recovery runs, the boot id and the sign that decided), `${LOG_FILE}.spool` (the copy of the spool that carries the outage story across the reboot) and `${LOG_FILE}.reboots` (the count of reboots of the current fault, removed by the first healthy pass).

### The device key and the joined networks

Two files with no knob live in `/etc`, both root-only (mode 0600), both created by the daemon itself, both outside `wpa_supplicant.conf` and NetworkManager's `/etc` store so that the no-writes rule holds.

`/etc/awacs.key` is the device key: 64 lowercase hex characters (32 random bytes from `openssl rand -hex 32`), made once at the first start that finds `openssl`, and registered with the site as `file=wifi_key` at every start, again at the third healthy tick and then once a healthy minute until one 2xx per boot. A password typed on the site is encrypted under keys derived from it and opened on the device; the recipe is in [integration.md](integration.md). The value is never written to a log or a site line. A different key is refused by the site unless the request carries a proof made with the previous key, which the daemon sends only when `/etc/awacs.key.prev` holds that previous key; a device that lost its key (a reflashed card) is re-paired once from the site's admin page (`admin/wifi.php?reset_key=1` on the maintainer's dashboard), and the refusal is said once per boot, `the site holds another key for this camera (a reflash?) - open admin/wifi.php?reset_key=1 once from your phone, then join from the menu works again`. The page named in that line belongs to the maintainer's dashboard, not to the shipped receivers; on a self-hosted receiver, re-pair by removing `private/wifi.key` in the device folder so the next registration is taken as the first. Without `openssl` the key is not made and `join` from the menu is off, said once: `openssl is missing - a password typed on the site cannot be opened here, join from the menu is off`. The derived keys pass through `openssl`'s argument list for the duration of each call, visible to root in `ps` on this single-user device; that is accepted and stated, not hidden. The password itself never enters an argument list.

`/etc/awacs.networks` holds the networks joined from the site, one line per network, `<hexssid>\t<psk>` (the SSID as lowercase hex, a tab, the password); a newer password for the same name replaces the older line. A line is written only after the network delivered internet, which proves the password. At every start, and after the recovery rungs that lose run-time entries (the supplicant restart of L2 and L3 on wpa, the NetworkManager restart of L3 on nm), every line whose SSID has no profile yet is re-added: on wpa into the live supplicant (never `save_config`), on nm as the keyfile `awacs-joined-<hexssid>` under `/run/NetworkManager/system-connections` with autoconnect on. Said once: `re-added N networks joined from the site: NAME, ...`. Nothing removes a line but you: delete it and restart the daemon, and on nm also `sudo rm /run/NetworkManager/system-connections/awacs-joined-<hexssid>.nmconnection; sudo nmcli connection reload`. `install.sh --uninstall --purge` does not touch these two files.

Log lines:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] device key made for passwords typed on the site (/etc/awacs.key)` (once, at the first start that makes it)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] device key registered with the site - a password typed there can be opened here` (once per boot, on the first 2xx)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] the site holds another key for this camera (a reflash?) - open admin/wifi.php?reset_key=1 once from your phone, then join from the menu works again` (once per boot)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] could not write /etc/awacs.key - join from the menu is off`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [OK] joined ${name} - password kept in /etc/awacs.networks, re-added at every start`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] joined ${name} but /etc/awacs.networks could not be written - the network lasts until the next start`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] re-added ${n} networks joined from the site: ${names}`

### SCAN_TTL

Default: `30`

Allowed: whole number 1 to 9999999; anything else becomes 30

Unit: seconds

How long one scan result is reused before the radio is asked again. A WiFi scan takes the radio off its channel, so the result is written to `RUN_DIR/scan` and any request that arrives while the file is younger than `SCAN_TTL` seconds, measured by the file's modification time, gets the file instead of a new scan. An empty file that is fresh counts as a real answer (a radio that hears nothing) and is served the same way. When a scan hears nothing from every source (`iw`, then `iwlist`, then the backend's own table: the supplicant's scan results on wpa, NetworkManager's list on NetworkManager), the previous list is kept and the file's timestamp is refreshed, so a silent radio is asked again once per `SCAN_TTL`, not once per caller; after three such empty scans in a row (a fixed count, not a knob) the old list is dropped and an empty answer is cached for the next `SCAN_TTL`. A scan that returns entries but no network name keeps the previous list without refreshing the timestamp, so the next caller scans again.

On the wpa backend, everything that needs to know which networks are on the air (stored networks visible, open-network candidates, the preferred-network look, the empty-radio check, the ordering used in signal mode) reads this cache; the WiFi cell counts read the file as it is, whatever its age, and never trigger a scan. On the NetworkManager backend the candidate lists and the cell counts come from NetworkManager's own table, and the cache only feeds the empty-radio check, the ordering used in signal mode, and the `scan` and `evaluate` toolbox words. Toolbox words run as root share the file, so a hand-run `sudo awacs.sh scan` refreshes the daemon's picture and the daemon's scan serves the toolbox. The age is the system clock minus the file's modification time; a clock that steps backward after the file was written (a board without a clock battery syncing time at boot) makes the cache look fresh for longer, and a forward step makes it look stale sooner. `awacs.sh help` prints the value in its `scan` row, but only under `sudo` does that row show the file's value, since the file is read only as root.

Log lines:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] scan failed - using previous results (if any)`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] radio heard nothing on ${empties} scans in a row - previous results dropped`
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [DEBUG] scan: ${used}/${tries} tries used`
- the `scan` row of `awacs.sh help` ends with `raw scan (cached ${SCAN_TTL}s)` (the English half of a row whose Arabic half comes first)

When to change it: raise it (60 to 120) on a device that never moves, to cut the number of off-channel scans; lower it (10 to 15) on a device that moves, where networks appear and disappear within a minute.

A device mounted on a vehicle: a fresher picture of the air is worth the extra radio time.

```sh
SCAN_TTL=15
```

### SPOOL_CAP

Default: `60`

Allowed: whole number 1 to 9999999; anything else becomes 60

Unit: lines

How many site-bound lines are kept while they cannot be delivered. When a story line is meant for the reporting site while the daemon's last verdict was that the internet is down, or a live send fails, the line is appended to `RUN_DIR/spool` in the site's format and delivered in order once the internet is back. While offline, after each append the file is counted; above `SPOOL_CAP` it is rewritten as its first line followed by the newest `SPOOL_CAP` minus 1 lines. The first line is normally the opening of the outage and carries the time it began, so it is always kept; what is lost is the middle of the story. The same trimming runs after a delivery, which sends line by line, stops at the first failure and merges the unsent remainder in front of any lines that arrived meanwhile.

Only matters when `SITE_URL` is set and `LOG_TARGET` is `both` or `remote`; otherwise nothing is ever spooled. The spool is sent at a daemon start that finds the internet up, on the third consecutive healthy pass and on every thirtieth healthy pass after that while lines remain (a healthy pass takes about 13 seconds with the defaults, so after roughly 40 seconds and then about every six minutes), and every 300 seconds in monitor-only mode. The stop's own drain is bounded to 6 lines or 20 seconds so the stop ends inside the unit's `TimeoutStopSec`; the remainder waits for the next start, and the local file notes `stop drain reached its budget - the remaining held lines wait for the next start`. A send that fails while the internet is up appends in the background without trimming; the cap catches up at the next offline append or delivery. Stored lines use `SITE_LANG` and the `SITE_TZ` time stamp. The file lives on memory-backed storage and is lost at reboot; before a reboot the daemon orders itself it copies the spool beside the log (`${LOG_FILE}.spool`), and the next start puts that copy in front of its own lines, so the outage story survives its own reboot (see [REBOOT_AFTER_MIN](#reboot_after_min)). Lines the cap dropped are counted and said once the story is out in full. A daemon killed in the middle of a delivery leaves `spool.sending`; the next start puts that whole snapshot back in front of newer lines, so a few lines already sent before the kill may be sent twice.

Log lines:

- `${yyyy-mm-ddThh:mm:ss+hh:mm} [${LEVEL}][awacs] ${text}` (the shape of every stored line)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] outage story trimmed - ${n} lines dropped from its middle (the spool keeps ${SPOOL_CAP})` (once per outage, after the delivery line of the flush that sent every held line; the count covers every trim since the story last went out in full and survives a daemon restart)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [INFO] delivered ${n} held lines stamped ${first} to ${last} - they stand above this line with their own times` (after every delivery, except the stop's drain and a start flush that held only the start's own lines; `delivered 1 held line stamped ${first} - it stands above this line with its own time` for one line; sent in the foreground and never held itself)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [OK] site reachable again - delivered ${n} held lines stamped ${first} to ${last}, they stand above this line with their own times` (the delivery that closes a refusal episode)
- `${yyyy-mm-ddThh:mm:ss+hh:mm} [WARN] site did not take the log line (${reply}) - holding lines, delivery retried about every ${minutes} min` (the refusal that opens an episode, held with the refused line)

When to change it: raise it when the site should receive a long outage's whole story rather than its opening line and its last stretch; lower it to keep the burst of catch-up sends after recovery short.

The site is read every morning and a whole night's outage should arrive complete.

```sh
SPOOL_CAP=200
```

## Environment variables

These are read from the daemon's environment, not from the settings file. Set them in the launcher: the `Environment=` lines of the systemd unit's drop-in, or the `rc.local` line before the launch loop.

`DEVICE_ID`: the device's name on the reporting site, used in the site path `SITE_URL/DEVICE_ID/SITE_API`, in the first start line and in the `device` row of `awacs.sh status`. Resolved on every use as described under [DEVICE_ID](#device_id): the variable, then the first non-blank line of `/tmp/device_id`, checked against `^[A-Za-z0-9_-]{1,32}$`, then the short hostname, then the word `device`. A present value that fails the rule is reported once at start (`device id not usable (${source}: ${value}) - reporting as ${id}`), and a change at run time once (`device id changed: ${old} -> ${new} - reporting under ${new} from now`). The intended sources are the `export` line in `rc.local` and the drop-in `awacs.service.d/10-device-id.conf` that `install.sh` writes. It is not a settings knob and is not validated at load time; but because the settings file is executed in the same shell, a `DEVICE_ID=` line in it is seen exactly like the environment value. That is not the documented place for it: the environment is.

`AWACS_IF`: the WiFi interface name. When set and not empty it replaces the automatic choice (the first connected interface, else the first one that is up, else the first present, else `wlan0`). It is not validated; a name that does not exist is reported once at start by a story line, `${yyyy-mm-ddThh:mm:ss+hh:mm} [ERROR] interface ${IF} not present - is the WiFi hardware alive?`, and the daemon carries on. The rootless `check` and `help` always use `wlan0`.

`AWACS_CONF`: the settings file path, default `/etc/awacs.conf`. A missing file is skipped and said once at start (`settings file ${AWACS_CONF} not found - running on built-in defaults (no site, no emergency networks)`); the same owner and mode rules apply to any path, and a refused file is said the same way.

`AWACS_DEBUG`: the value `DEBUG` has before the settings file is read, default `no`. Because the file is read afterwards, a `DEBUG=` line in the file replaces it, so the environment turns DEBUG lines on only when the file leaves `DEBUG` unset.

Two more names appear in the script and are not settings. `AWACS_CLI` is set by the toolbox function itself so that the scan warnings raised during a hand-run word stay in the local log instead of going to the site; the check only tests that the variable is non-empty, so exporting it into the daemon's environment gives the daemon the same behaviour: do not, or the daemon's own scan warnings stay local too. `AWACS_DAEMONIZED` is set by the `-d` flag when it relaunches the script in the background through `setsid`, so that the child does not relaunch again. The parent takes the fast lane at backend detection and skips the early-boot wait, which the child then pays once; and a monitor-only daemon started with `-d` never exits to be restarted once `nmcli` appears, because the `-d` path has no relauncher. Two lines say so: the monitor-only verdict reads `... then restart AWACS by hand (started with -d) ...`, and an unexpected exit ends `- no launcher under -d, start it again` instead of `- the launcher restarts it in 10 s`.
