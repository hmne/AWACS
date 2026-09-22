# Configuration

One file holds every setting: `/etc/awacs.conf`. A knob that is not written there keeps the default built into `awacs.sh`. The template `awacs.conf.example` in the repository root lists every knob on one line with its default and its allowed values, all commented out; `install.sh` writes only the reporting knobs and the `SAFETY_NET` lines you gave it. This page is the full explanation: for each knob, what it does, what it interacts with, the log lines that belong to it, when to change it, and an example.

## Loading

The daemon reads the settings file only when it runs as root. `awacs.sh check` and `awacs.sh help` run without root and therefore on the built-in defaults; every other toolbox word runs as root and reads the file the same way the daemon does. The environment variable `AWACS_CONF` names another file; the default is `/etc/awacs.conf`. A file that does not exist is skipped without a message.

Because the file is executed as root and holds hotspot passwords, two checks guard it. It must be owned by root, and `0600` is the documented mode; the check refuses only a read or write bit for group or others (execute bits are not looked at), so `0400` and `0700` also pass, while `0640`, `0644` and `0660` are refused. A refused file is announced on standard error, not in the log, and the daemon then runs entirely on defaults:

- `awacs: IGNORING ${AWACS_CONF} (group/world can access it — chmod 600 it)`
- `awacs: IGNORING ${AWACS_CONF} (not owned by root — chown root: it)`

On a terminal the message is visible; under systemd it lands in the journal; under the `rc.local` launch line, which discards output, it is not seen anywhere, so check the owner and mode by hand after editing the file from another account.

The file is sourced by bash, so it must hold plain assignments only: `KEY=value`, `KEY="value"` and `SAFETY_NET["Name"]="password"`. No `readonly` and no `declare`, because the validation step must be able to rewrite a value; no `unset`; no commands and no `$(...)`, because any other code in the file runs as root and nothing stops it. To keep a default, leave the line commented out rather than unsetting the knob. After loading and validation every knob is sealed read-only; nothing changes it at run time except the day and night working copies described under the night profile. The file is read once at each start, by the daemon and by every toolbox word that runs as root alike, so a change takes effect at the next daemon restart.

## Validation

Every value is checked once at start. A bad value falls back to the default silently; the only fallback the daemon reports is the `LOG_TARGET` downgrade at the end of this list.

Numbers. Seventeen knobs are numeric: `TICK`, `NET_FAIL_TICKS`, `ASSOC_WAIT`, `PREF_CHECK`, `REBOOT_AFTER_MIN`, `PROBE_KB`, `MIN_UP_KBPS`, `UP_STRIKES`, `SWITCH_GAIN_PCT`, `DANCE_COOLDOWN`, `STREAM_MIN_KBPS`, `NIGHT_MIN_UP_KBPS`, `NIGHT_GAIN_PCT`, `NIGHT_DANCE_COOLDOWN`, `LOG_CAP`, `SCAN_TTL` and `SPOOL_CAP`. Each must match `^0*[1-9][0-9]{0,6}$`: a whole number from 1 to 9999999. Leading zeros are accepted and dropped (`08` becomes 8, stored as a decimal number). Zero, an empty or unset value, a negative number, a decimal, text or more than seven significant digits restores the default. Zero is refused for all of them because it is meaningless for each (a zero tick would spin the loop; a zero spool cap breaks the first-line rule), and very long numbers because they would overflow into negative or endless sleeps.

Clock times. `NIGHT_START` and `NIGHT_END` must match `^([01]?[0-9]|2[0-3]):[0-5][0-9]$`: hour 0 to 23 with one or two digits, a colon, minutes 00 to 59 with two digits. Each falls back to its own default (`22:00`, `06:00`) independently.

Mode words. These are exact and case-sensitive. `LOG_TARGET` accepts `local`, `both` or `remote`, else `local`. `REPORT_WIFI` accepts `auto`, `yes` or `no`, else `auto`. `LOG_LANG` and `SITE_LANG` accept `en` or `ar`, else `en`.

Switches. `OPEN_NETWORKS`, `NIGHT_MODE`, `STEALTH_MODE` and `DEBUG` are never rewritten. Each is compared with the exact lowercase word `yes` at the one place it is used; any other value, `Yes`, `true`, `1` and an empty value included, means off, with no fallback and no warning.

Addresses and names. `SITE_URL` must match `^https?://[^[:space:]/]+(/[^[:space:]]*)?$`: `http` or `https`, a host without spaces or slashes, an optional path without spaces; anything else becomes empty, which means local-only operation. One trailing slash is dropped when the site address is built. `PROBE_URL` must match `^https?://[^[:space:]]+$`, else empty. `SITE_TZ` must match `^[A-Za-z0-9/_+-]{0,64}$`, else empty; only the shape is checked, not whether the device knows the zone. `SITE_API` must match `^[A-Za-z0-9_][A-Za-z0-9_./-]{0,63}$` and must not contain `..` (so it cannot escape the device folder); anything else, an empty value included, becomes `receiver.php`.

Paths. `RUN_DIR` must begin with `/`, else `/run/awacs`; every runtime file lives under it, so changing it moves them all together. `LOG_FILE` is not checked at all: no test that the path is absolute, no test that it exists, and no fallback.

Emergency networks. `SAFETY_NET` entries are not checked when the file is loaded; each entry is checked when it is tried (see [Emergency networks](#emergency-networks)).

The downgrade. `LOG_TARGET` set to `both` or `remote` while `SITE_URL` is empty (never set, or emptied by the shape check) is set back to `local`, and the daemon says so once at start:

- `[WARN][${dd/mm HH:MM:SS}] LOG_TARGET asked for the site but SITE_URL is empty - running local-only`

## Applying changes

```sh
sudo cp awacs.conf.example /etc/awacs.conf
sudo chown root:root /etc/awacs.conf && sudo chmod 600 /etc/awacs.conf
sudo nano /etc/awacs.conf
```

Then restart the daemon (see [install.md](install.md#stopping-and-restarting)). Every start opens with two lines. The first is a story line, `AWACS ${VERSION} starting on ${IF} (device ${DEVICE_ID})`; it follows `LOG_TARGET` like every story line, so under `remote` it goes to the site only. The second is the confirmation: it is written straight to the local log, in English whatever the settings, is never sent to the site, and shows the reporting settings as the daemon loaded them:

- `[INFO][${dd/mm HH:MM:SS}] reporting: ${LOG_TARGET} -> ${SITE_URL} | probe: ${probe target} | wifi cell: ${REPORT_WIFI} | lang: local ${LOG_LANG}, site ${SITE_LANG}`

The ` -> ${SITE_URL}` part is present only when `SITE_URL` is set and shows the value as written in the file. The probe part is the address the upload probe uses, or the words `none - signal mode` when there is none. A mistyped `SITE_URL` shows up here: because the shape check empties it silently, the line then reads `reporting: local` and, unless `PROBE_URL` is set, `probe: none - signal mode`. With every knob at its default the line reads:

`[INFO][${dd/mm HH:MM:SS}] reporting: local | probe: none - signal mode | wifi cell: auto | lang: local en, site en`

In the log lines quoted on this page, `${...}` marks a value the daemon fills in. Local lines have the shape `[LEVEL][dd/mm HH:MM:SS] text`; lines sent to the site have the shape `[LEVEL] AWACS: text, dd/mm/yyyy hh:mm:ss AM.` (or `PM`). Story lines are written locally in the `LOG_LANG` language and sent to the site in the `SITE_LANG` language; the text quoted on this page is their English form.

## Reporting

Where the daemon's story goes, how it measures upload speed, and in which language and time zone the site reads it. All site traffic is an HTTP POST to one address, `SITE_URL/DEVICE_ID/SITE_API`, and that address receives four kinds of request: the story lines (two form fields, `file=log/log.txt` and `data=` followed by the line, under a 4-second limit), the Wi-Fi cell (`file=tmp/wifi.tmp` and `data=` followed by `kbps,visible,total,band,SSID`, under a 4-second limit), the upload probe (a raw body of `PROBE_KB` kilobytes under a 15-second limit; the reply is not inspected, only the transfer speed) and the last step of the internet check (a request carrying `probe=1` that must be answered with HTTP 400 and nothing else, under a 3-second limit in the quick form of the check and an 8-second limit in its patient form, which is how captive-portal pages answering 200 or 302 are rejected). The shipped receivers `server/receiver.php` (PHP 7.4 or newer, no dependencies) and `server/receiver.py` (Python 3, standard library only) answer this contract for any device id; [integration.md](integration.md) has the details. The toolbox words (`status`, `networks`, `evaluate`, `scan`, `speed` and `check`) never send story lines or the Wi-Fi cell; `status` and `check` do run the internet check, in its quick form only, with its endpoint step when a loaded `SITE_URL` gives it one, and `speed` uploads one probe body to the probe target.

### SITE_URL

Default: `""` (empty)

Allowed: `http://host` or `https://host`, an optional `:port`, an optional `/path`; no spaces anywhere and no slash inside the host; anything else becomes empty, and empty means local-only

Unit: URL

The base address of the reporting site. Every request the daemon sends to the site goes to one address built from it: `SITE_URL/DEVICE_ID/SITE_API`. That address receives the story lines, the Wi-Fi cell, the upload probe body (unless `PROBE_URL` points elsewhere) and the last step of the internet check, a POST with `probe=1` that the endpoint must answer with HTTP 400. Empty means local-only: no site traffic at all, the log file is the only output, the last internet-check step does not exist and, with `PROBE_URL` also empty, the daemon runs in signal mode (see [Signal mode](#signal-mode)). A value of the wrong shape is emptied silently; the `reporting:` line at start then shows `local`.

Setting `SITE_URL` while `LOG_TARGET` stays `local` turns on the upload probe and the internet-check step but sends no story lines and, with `REPORT_WIFI=auto`, no Wi-Fi cell. `LOG_TARGET` `both` and `remote` take effect only when `SITE_URL` is set. `PROBE_URL`, when set, replaces the site endpoint as the probe target. `REPORT_WIFI=yes` publishes the cell whenever `SITE_URL` is set, even with `LOG_TARGET=local`; `auto` needs `both` or `remote` as well. `DEVICE_ID` is the folder in the path and `SITE_API` the file after it. The offline spool (`SPOOL_CAP`) only fills when `SITE_URL` is set and `LOG_TARGET` is `both` or `remote`.

Log lines:

- `[INFO][${dd/mm HH:MM:SS}] reporting: ${LOG_TARGET} -> ${SITE_URL} | probe: ${probe target} | wifi cell: ${REPORT_WIFI} | lang: local ${LOG_LANG}, site ${SITE_LANG}`
- `[WARN][${dd/mm HH:MM:SS}] LOG_TARGET asked for the site but SITE_URL is empty - running local-only`

When to change it: set it as soon as a receiver or the full site exists for this device; leave it empty for a device that should only keep a local log and needs no upload measurement.

A device whose id is `mydevice` then posts everything to `https://example.org/mydevice/receiver.php`.

```sh
SITE_URL="https://example.org"
```

### SITE_API

Default: `"receiver.php"`

Allowed: 1 to 64 characters; the first a letter, digit or underscore, the rest letters, digits, underscore, dot, slash or hyphen; no `..` (no escape from the device folder); anything else, an empty value included, becomes `receiver.php`

Unit: file name, sub-folders allowed

The endpoint file name appended after the device folder: `SITE_URL/DEVICE_ID/SITE_API`. This is the only address the daemon talks to on the site, and it receives four kinds of request: story lines (form fields `file=log/log.txt` and `data=` followed by the line), the Wi-Fi cell (`file=tmp/wifi.tmp` and `data=` followed by `kbps,visible,total,band,SSID`), the upload probe (a raw POST body of `PROBE_KB` kilobytes, only while `PROBE_URL` is empty) and the internet-check request (a POST with `probe=1`, to be answered with HTTP 400). The shipped receivers in `server/` (one in PHP 7.4 or newer with no dependencies, one in Python 3 with the standard library only) answer this contract for any device id; [integration.md](integration.md) describes the contract itself.

It has no effect while `SITE_URL` is empty. `DEVICE_ID` is the folder before it. `PROBE_URL` bypasses it for the probe only; the story lines, the Wi-Fi cell and the internet check always use it.

Log lines:

- `[INFO][${dd/mm HH:MM:SS}] reporting: ${LOG_TARGET} -> ${SITE_URL} | probe: ${SITE_URL}/${DEVICE_ID}/${SITE_API} | wifi cell: ${REPORT_WIFI} | lang: local ${LOG_LANG}, site ${SITE_LANG}` (the endpoint appears in the probe part only while `PROBE_URL` is empty)

When to change it: when your site's endpoint is not called `receiver.php`: the full site's own endpoint name, or a receiver kept under another path, for example one folder down.

The site keeps its endpoint one folder down, so the device posts to `SITE_URL/mydevice/api/receiver.php`.

```sh
SITE_API="api/receiver.php"
```

### LOG_TARGET

Default: `"local"`

Allowed: `local`, `both` or `remote`; any other word becomes `local`; `both` and `remote` need `SITE_URL` (with it empty, or emptied by the shape check, the value is forced back to `local` and the daemon says so once at start)

Unit: mode word

Where the story lines go. `local`: the log file only. `both`: the log file and the site. `remote`: the site only, except that WARN and ERROR story lines are still written to the local file. Lines that are not story lines are always written locally whatever this says: DEBUG diagnostics, the `reporting:` line at start, the downgrade warning, the reboot line, the scan warnings raised by a hand-run toolbox word, and three internal error lines. In `both` and `remote`, a line that cannot be sent (offline, or a failed send) is kept in a spool file and delivered in order once the internet is back; delivery stops at the first failed send and the rest waits for the next attempt. The spool holds `SPOOL_CAP` lines and its first line is always kept.

Needs `SITE_URL`; without it the value is forced back to `local` and the daemon says so once. `REPORT_WIFI=auto` follows it: the cell is sent only in `both` or `remote`. `SPOOL_CAP` bounds the offline story. DEBUG lines are never sent to the site and never dropped by `remote`. `LOG_LANG` still picks the language of what `remote` leaves in the local file.

Log lines:

- `[INFO][${dd/mm HH:MM:SS}] reporting: ${LOG_TARGET} -> ${SITE_URL} | probe: ${probe target} | wifi cell: ${REPORT_WIFI} | lang: local ${LOG_LANG}, site ${SITE_LANG}`
- `[WARN][${dd/mm HH:MM:SS}] LOG_TARGET asked for the site but SITE_URL is empty - running local-only`

When to change it: set `both` once a site exists and you still want a copy on the SD card; set `remote` when the site is the record and the local file should keep only warnings and errors.

The site gets the full story while the SD card keeps a copy for troubleshooting offline.

```sh
LOG_TARGET="both"
```

### PROBE_URL

Default: `""` (empty: the site endpoint `SITE_URL/DEVICE_ID/SITE_API`, or signal mode when `SITE_URL` is empty too)

Allowed: any `http://` or `https://` address without spaces, used exactly as written, with nothing appended; anything else becomes empty

Unit: URL

Where the upload probe sends its test body. The probe uploads `PROBE_KB` kilobytes of zeros with `curl` under a 15-second limit and reads curl's own upload-speed figure. If `curl` is missing or reports zero, `wget` posts the same bytes from a temporary file and the elapsed time gives the figure; if `wget` is missing too, the figure is 0. The server's reply is not inspected, only the transfer speed, so any server that accepts a POST body works; with the wget fallback a 4xx or 5xx reply still counts as a completed upload, and only a transport failure or a timeout reads as 0. Empty means the site endpoint is used, so a site alone gives measurement. When both `PROBE_URL` and `SITE_URL` are empty there is nowhere to upload to and the daemon runs in signal mode.

`SITE_URL` supplies the fallback target and `PROBE_KB` the body size. In signal mode `MIN_UP_KBPS`, `UP_STRIKES`, `SWITCH_GAIN_PCT`, `DANCE_COOLDOWN`, `STREAM_MIN_KBPS` and the three night figures (`NIGHT_MIN_UP_KBPS`, `NIGHT_GAIN_PCT` and `NIGHT_DANCE_COOLDOWN`) take no part in any decision, because there is no measurement to compare; the day and night profile lines are still logged. `awacs.sh speed` probes this same target. `PROBE_URL` alone, with no `SITE_URL`, gives measured network choice with no reporting.

Log lines:

- `[INFO][${dd/mm HH:MM:SS}] reporting: ${LOG_TARGET} | probe: ${PROBE_URL} | wifi cell: ${REPORT_WIFI} | lang: local ${LOG_LANG}, site ${SITE_LANG}`
- `[INFO][${dd/mm HH:MM:SS}] reporting: local | probe: none - signal mode | wifi cell: ${REPORT_WIFI} | lang: local ${LOG_LANG}, site ${SITE_LANG}` (both addresses empty)
- `[OK][${dd/mm HH:MM:SS}] connected: ${SSID} (signal mode - no upload probe target configured)`
- `[OK][${dd/mm HH:MM:SS}] returned to preferred network: ${SSID} (signal mode)`

When to change it: when uploads should be measured against a different host than the reporting site (a nearer server, or a plain sink), or when you want measured network choice without running any site.

Uploads are measured against a dedicated sink instead of the reporting site.

```sh
PROBE_URL="https://probe.example.org/sink"
```

### REPORT_WIFI

Default: `"auto"`

Allowed: `auto`, `yes` or `no`; any other word becomes `auto`

Unit: mode word

Whether the daemon publishes the Wi-Fi cell to the site: one line of the form `kbps,visible,total,band,SSID`, posted as `file=tmp/wifi.tmp` to the site endpoint. `auto`: only when story lines also go to the site (`SITE_URL` set and `LOG_TARGET` `both` or `remote`). `yes`: whenever `SITE_URL` is set, even with `LOG_TARGET=local`. `no`: never. Without `SITE_URL` nothing is sent in any mode. The cell goes out from the main loop only while the internet is verified, on the first healthy pass and then every sixth (about every 80 seconds with the defaults), in the background, and never from monitor-only mode (a NetworkManager image the daemon cannot drive). `total` is the number of stored networks and `visible` those of them on the air; both come from the existing scan picture (NetworkManager's own list on that backend, without a rescan), so no radio work is caused. `kbps` is the last measured upload speed, sent only if it was measured on the network the device is on now, otherwise 0 (always 0 in signal mode). `band` is `2.4GHz`, `5GHz` or `6GHz` from the live link frequency and empty when it cannot be read. The name comes last so its own commas survive, and a dash stands in when there is none.

It depends on `SITE_URL` (nothing is sent without it), on `LOG_TARGET` (`auto` follows it), on `TICK` (which sets the cadence), on `SCAN_TTL` (how fresh the visible count is), on `PROBE_URL` and signal mode (`kbps` stays 0), and on a network change since the last measurement (`kbps` is shown as 0). The request is `file=tmp/wifi.tmp` with `data=${kbps},${visible},${total},${band},${SSID}`, and the setting shows in the `reporting:` line at start as `wifi cell: ${REPORT_WIFI}`.

Log lines:

- `[INFO][${dd/mm HH:MM:SS}] reporting: ${LOG_TARGET} -> ${SITE_URL} | probe: ${probe target} | wifi cell: ${REPORT_WIFI} | lang: local ${LOG_LANG}, site ${SITE_LANG}` (the setting shows in the `wifi cell:` part; no line is written per send)

When to change it: set `no` when the site has no Wi-Fi cell or you want to cut the periodic request; set `yes` when you want the cell while story lines stay local.

The site has no Wi-Fi widget, so posting the cell about every 80 seconds is wasted traffic.

```sh
REPORT_WIFI="no"
```

### SITE_TZ

Default: `""` (empty: the device's own time zone)

Allowed: a zone name of up to 64 characters made of letters, digits, `/`, `_`, `+` and `-`, such as `Asia/Kuwait`, `Europe/Berlin` or `UTC`; anything else becomes empty

Unit: time zone name, in the tz database form

The time zone of the timestamp on the lines sent to the site. Each site line is built as `[LEVEL] AWACS: text, dd/mm/yyyy hh:mm:ss AM.` and that stamp is taken with `TZ` set to this value. The local log file is not affected: its lines keep the device's own zone in the form `[LEVEL][dd/mm HH:MM:SS]`. Lines kept in the spool while offline carry the stamp of the moment they happened, not of the moment they were delivered. Only the shape of the value is checked, not that the device knows the zone: a well-shaped name the device does not know passes the check, and the site stamps then read UTC.

Only matters when story lines go to the site (`SITE_URL` set and `LOG_TARGET` `both` or `remote`). `SITE_LANG` changes the text part of the same line, not the stamp. The Wi-Fi cell carries no timestamp. The night window (`NIGHT_START`, `NIGHT_END`) follows the device clock, not this zone.

Log lines:

- `[${LEVEL}] AWACS: ${text}, ${dd/mm/yyyy hh:mm:ss AM|PM}.` (the line as sent to the site; the same event is written locally as `[${LEVEL}][${dd/mm HH:MM:SS}] ${text}` in the device zone)

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

- `[INFO][${dd/mm HH:MM:SS}] reporting: ${LOG_TARGET} -> ${SITE_URL} | probe: ${probe target} | wifi cell: ${REPORT_WIFI} | lang: local ${LOG_LANG}, site ${SITE_LANG}`

When to change it: when the person who reads `/var/log/awacs.log` on the device prefers Arabic.

The technician who reads the SD-card log reads Arabic.

```sh
LOG_LANG="ar"
```

### SITE_LANG

Default: `"en"`

Allowed: `en` or `ar`; any other value becomes `en`

Unit: language code

The language of the text in the story lines sent to the site, chosen independently of `LOG_LANG`. The fixed prefix `[LEVEL] AWACS:` and the timestamp at the end are the same in both languages; only the text between them changes. The Wi-Fi cell is numbers and a network name, so it is not affected.

Only visible when story lines go to the site (`SITE_URL` set and `LOG_TARGET` `both` or `remote`). `SITE_TZ` sets the stamp on the same line. `LOG_LANG` is independent.

Log lines:

- `[${LEVEL}] AWACS: ${text}, ${dd/mm/yyyy hh:mm:ss AM|PM}.`
- `[INFO][${dd/mm HH:MM:SS}] reporting: ${LOG_TARGET} -> ${SITE_URL} | probe: ${probe target} | wifi cell: ${REPORT_WIFI} | lang: local ${LOG_LANG}, site ${SITE_LANG}`

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

A variable value that fails the check goes straight to the hostname; the `/tmp` file is consulted only when the variable is empty. The rule exists because `/tmp` is writable by every local user and the id lands in a root terminal and in an outbound URL. The id also appears in the first line of every start and in the `device` row of `awacs.sh status`:

- `[INFO][${dd/mm HH:MM:SS}] AWACS ${VERSION} starting on ${IF} (device ${DEVICE_ID})`

### Deployment shapes

Local-only, no server at all. Leave the reporting block at its defaults:

```sh
# SITE_URL=""
# LOG_TARGET="local"
# PROBE_URL=""
```

The log file `/var/log/awacs.log` is the only output; no request leaves the device for reporting; the daemon runs in signal mode, choosing networks by signal strength with no upload measurement and no Wi-Fi cell. Recovery, the outage classification, the reboot rule, the emergency networks, the open networks and the day and night profiles all work as they do with a site. The start line reads `reporting: local | probe: none - signal mode | wifi cell: auto | lang: local en, site en`. To keep measured network choice without a site, add only `PROBE_URL` pointing at any address that accepts a POST body, for example `PROBE_URL="https://probe.example.org/sink"`.

Self-hosted receiver. One of the shipped receivers in `server/`, placed on your own host so that `SITE_URL/DEVICE_ID/receiver.php` answers (see [integration.md](integration.md)):

```sh
SITE_URL="https://example.org/awacs"
SITE_API="receiver.php"
LOG_TARGET="both"
SITE_TZ="Asia/Kuwait"
```

A device whose id is `mydevice` posts to `https://example.org/awacs/mydevice/receiver.php`. Story lines go to the file and the site, the upload probe uses the same endpoint (measured network choice is on), the internet check gains its endpoint step, and the Wi-Fi cell is posted about every 80 seconds (`REPORT_WIFI=auto` with `LOG_TARGET=both`). The start line reads `reporting: both -> https://example.org/awacs | probe: https://example.org/awacs/mydevice/receiver.php | wifi cell: auto | lang: local en, site en`.

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

The site is the record: INFO and OK story lines go only there, while the local file keeps the WARN and ERROR story lines and the always-local lines. The site reads Arabic while the local file stays English, site timestamps are in Kuwait time, and the Wi-Fi cell feeds the dashboard. The start line reads `reporting: remote -> https://example.org | probe: https://example.org/mydevice/api/receiver.php | wifi cell: auto | lang: local en, site ar`. Use `LOG_TARGET="both"` instead of `remote` to keep a full local copy as well.

### Signal mode

Signal mode is how the daemon runs when `PROBE_URL` and `SITE_URL` are both empty. There is nowhere to upload a test body, so upload speed is never measured and networks are never compared by speed.

What still runs: the internet check every pass (without its endpoint step), recovery when the internet is lost, the return to a higher-priority stored network every `PREF_CHECK`, the emergency networks and the open networks.

What is switched off: the upload probe (it prints 0 without traffic), the sustained-slow-upload check and the starving-stream check (so `UP_STRIKES`, `MIN_UP_KBPS`, `STREAM_MIN_KBPS`, `SWITCH_GAIN_PCT` and the cooldowns never act), the too-slow check of a preferred network on arrival, and the `kbps` figure in the Wi-Fi cell, which is always 0.

How a network is chosen when the internet is lost: the stored networks that are on the air are taken strongest signal first (a network heard on two bands is one candidate), each is connected in turn, and the first one that delivers internet wins. If none delivers, the recovery moves on to its next step. Nothing is skipped and there is no return to the previous network, because both need a measurement.

The lines that mark this mode:

- `[INFO][${dd/mm HH:MM:SS}] reporting: local | probe: none - signal mode | wifi cell: ${REPORT_WIFI} | lang: local ${LOG_LANG}, site ${SITE_LANG}`
- `[OK][${dd/mm HH:MM:SS}] connected: ${SSID} (signal mode - no upload probe target configured)` (the measured form reads `connected: ${SSID} (upload ${kbps} kbps)`)
- `[OK][${dd/mm HH:MM:SS}] returned to preferred network: ${SSID} (signal mode)` (the measured form ends with `(upload ${kbps} kbps)`)

`awacs.sh speed` prints a failed upload row that begins `no probe target (signal mode)`.

## Emergency networks

### SAFETY_NET

Default: empty (no emergency network); the script declares an empty array and expects entries only in `/etc/awacs.conf`

Allowed: one line per network, `SAFETY_NET["Name"]="password"`; the name as broadcast; the password 8 to 63 characters, or exactly 64 hex digits (NetworkManager backend only), or `""` for an open hotspot listed on purpose

Unit: none (a list of name and password pairs)

Emergency networks with passwords, typically a phone hotspot, that the daemon may join when nothing else works. During a recovery, once the visible stored networks have been tried and the round's own recovery step has not brought the internet back, the daemon walks this list and tries each entry in turn, before it considers any unknown open network. Every entry is attempted whether or not it appeared in the daemon's last radio scan: the function never reads the scan picture, it asks the network layer to connect, because a hotspot is often switched on a moment ago. The entry is created as a visible, not hidden, network, so list hotspots that broadcast their name. A successful entry is temporary: on the wpa backend it is a runtime network id in the live supplicant (the script never writes `wpa_supplicant.conf`); on the NetworkManager backend it is a keyfile under `/run` with `autoconnect=false`, gone at reboot. The temporary entry is removed when the device is back on a stored network, at the start of the next recovery, and by the start-up sweep if the daemon died while on it. Entries are tried in the order bash iterates its associative array, not in the order of the lines in the file.

The whole file, `SAFETY_NET` included, is read only when the daemon runs as root and the file passes the owner and mode checks; a refused file means no emergency network at all. Each attempt is bounded by `ASSOC_WAIT`: on wpa one wait for association and an address (25 seconds by default); on NetworkManager a settle wait, then the `nmcli` activation wait, then the address wait, so up to two or three times `ASSOC_WAIT` per entry. `NET_FAIL_TICKS` decides when a recovery starts from the main loop; a recovery also runs at start when there is no internet. A recovery has three rounds and the list is walked in each round that has not restored the internet, so an entry may be tried up to three times per recovery; the only round that skips the list is one on NetworkManager where NetworkManager picks the interface up again while the round gathers evidence. Unknown open networks (`OPEN_NETWORKS`) are tried only after every emergency entry failed or when the list is empty; an entry with an empty password is tried before them. The marker naming the temporary entry, `open_id`, lives under `RUN_DIR`. In monitor-only mode (NetworkManager present but `nmcli` missing, or the interface unmanaged) no recovery ever runs, so the list is never used. `LOG_LANG` and `SITE_LANG` pick the language of the INFO and OK lines below for the local file and for the site; with `LOG_TARGET=remote` those two lines are not written locally, only sent; and `DEBUG=yes` adds the local `connect_id` line whatever `LOG_TARGET` says.

Log lines:

- `[INFO][${dd/mm HH:MM:SS}] trying emergency networks (${count} listed)`
- `[OK][${dd/mm HH:MM:SS}] connected to EMERGENCY network: ${name}`
- `[DEBUG][${dd/mm HH:MM:SS}] connect_id: activating ${id} (backend ${BACKEND})`
- `[OK][${dd/mm HH:MM:SS}] internet restored: ${name}` (after a win inside a recovery started from the main loop; a win inside the start-up recovery gets no such line)
- `[INFO] AWACS: trying emergency networks (${count} listed), ${dd/mm/yyyy hh:mm:ss AM|PM}.` and `[OK] AWACS: connected to EMERGENCY network: ${name}, ${dd/mm/yyyy hh:mm:ss AM|PM}.` (the same two lines as the site receives them)

A skipped or failed entry produces no line of its own; the only trace is the DEBUG line above, when `DEBUG=yes`. When every entry has failed and `OPEN_NETWORKS=yes`, the next line is `trying open networks as last resort`. When the list is empty no line is written and open networks follow directly.

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

NetworkManager backend. A non-empty password must be 8 to 63 characters long or exactly 64 hex digits; otherwise the entry is skipped with no log line. Any name bytes are accepted, because the name is stored as a byte array, so Arabic, emoji and symbol names work. The keyfile is written to `/run/NetworkManager/system-connections/awacs-safety-${time}-${pid}.nmconnection` with `autoconnect=false` and mode 0600 and loaded with `nmcli connection load`; an entry with an empty password gets no security section and a different second word in the same name pattern. Deletion is guarded: the daemon refuses to remove any profile whose name does not follow its own `awacs-...-${numbers}-${numbers}` pattern (`awacs-`, then the second word, then two numbers separated by a hyphen: the time and the process id) or whose file is not under `/run/NetworkManager/system-connections/awacs-*`, logging the refusal at ERROR with a line that begins `REFUSING delete:`. A saved profile is never touched.

wpa backend. The entry is skipped, silently, when the name contains a backslash or a double quote, or when the password contains a double quote, because both are placed inside a double-quoted `wpa_cli` argument. The password is piped to `wpa_cli` over its standard input rather than passed on the command line, so it never appears in the process list. The script applies no length check of its own on this backend: each `set_network` command must answer OK, or the entry is skipped and its id removed. Because the value is always sent quoted, the supplicant reads it as a passphrase, so a 64-hex key is not usable on this backend; use a passphrase of 8 to 63 characters, which is accepted on both backends.

Empty password on purpose. An empty value marks an open hotspot listed deliberately. On wpa the entry is created with `key_mgmt NONE`; on NetworkManager the keyfile is written without a `[wifi-security]` section. Such an entry is tried with the other emergency entries, that is before any unknown open network, and the NetworkManager length rule applies only to non-empty values.

How `install.sh` writes these lines. Step 5 of the wizard asks `Add an emergency network?`, then for a name and a password (read without echo), then `Add another one?` after each entry. It is stricter than the daemon: the name must be 1 to 32 bytes, and neither the name nor the password may contain a double quote, a backslash, `$`, a backtick or a control character, because the value lands inside a double-quoted assignment that bash executes as root. Rejections read `Name rejected: 1 to 32 bytes, without quotes, backslash, $ or backtick.` and `Password rejected: 8 to 63 characters, or 64 hex digits, or empty. No quotes, backslash, $ or backtick.` and the entry is asked again. The same entries can be given without prompts with the repeatable flag `--safety 'SSID=password'`, split at the first `=` and checked by the same rules, so a name containing `=` cannot be given that way; `--no-safety` or `--yes` skips the prompts but still writes the flagged entries. When the file is rewritten, existing lines are kept, except the eight reporting keys, the wizard's own marker line (which begins `# awacs install.sh`) and any `SAFETY_NET` entry with the same name, which are replaced; each entry is printed as `SAFETY_NET["name"]="password"`, exactly the form the daemon expects; the write is atomic: the file is written through a temporary file in `/etc`, `chmod 600` and `chown root:root`, then moved into place, and under `--dry-run` the content is only printed with every password masked as `********`. The wizard never edits `wpa_supplicant.conf` or a NetworkManager profile.

## Timing

Five knobs set the rhythm of the main loop, the patience of every connection attempt and the reboot rule. All five follow the numeric rule (a whole number from 1 to 9999999, else the default) and are sealed after loading, so a change needs a daemon restart. None of them changes at night. Monitor-only mode (a NetworkManager image without `nmcli`, or with an unmanaged interface) ignores them all and checks every 300 seconds.

One pass of the main loop, in order: apply the day or night profile; run the internet check (a ping to `8.8.8.8`, then `1.1.1.1`, then an HTTP 204 request, then the site endpoint when `SITE_URL` is set, stopping at the first success; a check that fails while the interface sent 16384 bytes or more during it is repeated once in the patient form, at most once per outage). On a healthy pass: reset the failure counter and the fault clock, deliver the offline spool on the third consecutive healthy pass and then every thirtieth, attempt the once-per-boot tool install on the third, refresh the Wi-Fi cell on the first and then every sixth, retire a temporary network entry once back on a stored network, take the 3-second transmit-counter sample for the upload rules, and run the preferred-network look when `PREF_CHECK` is due. On an offline pass: zero the healthy-pass count and add one to the failure counter that `NET_FAIL_TICKS` reads. Then sleep `TICK`.

A recovery run is: a gentle first step (ask the base layer to reconnect, wait up to `ASSOC_WAIT` for a link and an address, check the internet; in the first run of an outage the reconnect is skipped while the default gateway still answers, so a working association is not dropped for it); then three rounds, each trying the visible stored networks (by measured upload, or by signal in signal mode), classifying the outage as an on-device fault or external, running one recovery step for an on-device fault (round 1 a radio bounce, round 2 a re-kick or restart of the network service, round 3 a Wi-Fi firmware reload), then the emergency and open networks; and finally, when all three rounds lost, the reboot rule.

### TICK

Default: `10`

Allowed: whole number 1 to 9999999; anything else becomes 10

Unit: seconds

How long the daemon sleeps between two passes of its main loop. The real period is longer than `TICK`: about 3 seconds more when online, for the transmit-counter sample; about 4 seconds more again on a network that blocks ping, because both pings time out before the HTTP check answers; and up to about 7 to 10 seconds more when offline, while the pings and HTTP checks time out, with about 26 seconds on top of the one offline pass that pays for a patient check. No sleep happens inside a recovery run, which blocks the loop for as long as it takes. Several housekeeping cadences are counted in consecutive healthy passes, not seconds, so they scale with `TICK`: the offline story is delivered on the third consecutive healthy pass and then every thirtieth, the once-per-boot tool install is attempted on the third, and the Wi-Fi cell is refreshed on the first and then every sixth; an offline pass resets that count.

Time to the first recovery run is about `NET_FAIL_TICKS` times (`TICK` plus the offline check's time), plus the one patient check when the router keeps answering. The night profile does not change `TICK`. At boot there is no grace at all: a daemon that starts without internet begins a recovery run immediately. Monitor-only mode sleeps a fixed 300 seconds and ignores `TICK`. Delivering a long offline story on the third healthy pass can stretch that one pass, because each spooled line is sent one by one with a 4-second limit; on legacy images the preferred-network look adds a 4-second wait to its pass.

Log lines:

- `[DEBUG][${dd/mm HH:MM:SS}] QA: flow=${flow} kbps, strikes=${strikes}, profile=${day|night}`
- `[DEBUG][${dd/mm HH:MM:SS}] QA(stream): flow=${flow} kbps, strikes=${strikes}`

When to change it: raise it (15 to 30) on a battery or very low-power unit to cut the per-pass ping, counter read and CPU wake-ups; lower it (5) when you want the failure counter to fill faster so recovery starts sooner. The offline check and the 3-second sample add seconds on top of every pass, and `NET_FAIL_TICKS` multiplies whatever you choose.

A battery-powered unit: one ping every 15 seconds is enough, and with `NET_FAIL_TICKS=3` recovery still starts about 70 seconds after a loss, or about 26 seconds later when the router keeps answering and the one patient check is paid.

```sh
TICK=15
```

### NET_FAIL_TICKS

Default: `3`

Allowed: whole number 1 to 9999999; anything else becomes 3

Unit: main-loop passes

How many consecutive passes must find no internet before the daemon starts a recovery run. Each offline pass adds one to a failure counter; any pass with internet resets it to zero. When the counter reaches `NET_FAIL_TICKS` the daemon logs the loss, on that pass only, so one outage produces one loss line, and calls the recovery run. On that pass one test comes first, on two conditions: the link itself is alive (the default gateway answers a ping, or the kernel's neighbour table reports it reachable) and no patient check has failed in this outage yet. That test is a patient internet check, and when it passes the pass counts as a healthy one: no loss line, no recovery run, and the local file records `internet answers late, not never - slow link, no recovery (${NET_FAIL_TICKS} quick checks timed out)`, a line that is never sent to the site. If the run does not win, the counter keeps growing past the threshold and the run is called again on every following offline pass until the internet is verified, so this knob only delays the first run of an outage; a won run resets the counter. The boot pass bypasses it: a daemon that starts without internet runs recovery at once. A short outage that heals between two runs is still announced as restored on the next healthy pass.

Time to the first recovery run is about `NET_FAIL_TICKS` times (`TICK` plus the offline check's time, up to about 7 to 10 seconds while the pings and HTTP checks time out); with the defaults that is roughly 40 to 63 seconds after the loss on a link whose gateway has gone silent, and about 72 to 83 seconds when the router keeps answering and the one patient check is paid. Because the internet check already tries three sources in a row (four when `SITE_URL` is set), a value of 1 means one fully failed check starts recovery. Larger values protect a flaky but usually-working uplink from unnecessary reconnects; smaller values react faster.

Log lines:

- `[WARN][${dd/mm HH:MM:SS}] internet lost on ${IF} - engaging`
- `[OK][${dd/mm HH:MM:SS}] internet restored: ${SSID}`
- `[INFO][${dd/mm HH:MM:SS}] internet answers late, not never - slow link, no recovery (${NET_FAIL_TICKS} quick checks timed out)` (local file only)

When to change it: raise it (5 to 6) where the uplink has frequent 20 to 40 second blips that clear on their own and a reconnect would only make them longer; lower it to 1 or 2 on a device whose job cannot tolerate a minute offline.

This uplink drops for about 40 seconds several times a day and heals by itself; wait one to two minutes before touching the Wi-Fi.

```sh
NET_FAIL_TICKS=6
```

### ASSOC_WAIT

Default: `25`

Allowed: whole number 1 to 9999999; anything else becomes 25

Unit: seconds

How long the daemon waits for a network it just asked for to come up: a loop checks about once a second, for `ASSOC_WAIT` rounds, that the interface reports both a Wi-Fi association and a global IPv4 address, and the attempt fails when the bound runs out. This bound applies to every attempt on any network: a stored network during recovery, an emergency network, an open network, the move to a higher-priority network and the way back from it. On NetworkManager images the same number is also handed to `nmcli` as its own wait limit for the activation, and it bounds the settle wait that precedes every `nmcli` command (until the device leaves its connecting or deactivating states), so one attempt there can take up to two or three times `ASSOC_WAIT`. The gentle first step of every recovery run uses the same bound; in the first run of an outage on a link whose gateway still answers, that step is the wait alone, without the reconnect before it.

Each candidate tried in a recovery run costs up to `ASSOC_WAIT` seconds (two to three times that on NetworkManager) plus an upload probe when the link comes up, so with many stored networks a recovery run grows linearly with this value, and that spaces out the moments when `REBOOT_AFTER_MIN` is compared. A value shorter than the router's real DHCP time makes a working network look broken: it is skipped and, during recovery, may feed the on-device fault evidence because no link came up. On NetworkManager images, if `nmcli` cannot report a device state at all, every settle wait costs the full `ASSOC_WAIT`. The radio-bounce recovery step does not use this knob: on NetworkManager images it switches the radio off, pauses 2 seconds, switches it on and then waits for the device to settle under a fixed 15-second bound; on legacy images it takes the interface down, pauses 2 seconds, brings it up and pauses 3 seconds.

Log lines:

- `[DEBUG][${dd/mm HH:MM:SS}] connect_id: activating ${id} (backend ${BACKEND})`

When to change it: raise it (35 to 45) when the router or hotspot is known to be slow to hand out addresses; the sign is a network that keeps failing exactly `ASSOC_WAIT` seconds after its `activating` line in the log, yet works when joined by hand. Lower it (15) only on fast networks when you want recovery runs to move through many candidates quickly.

The office router answers DHCP after about 30 seconds and kept being counted as a failed connection.

```sh
ASSOC_WAIT=40
```

### PREF_CHECK

Default: `600`

Allowed: whole number 1 to 9999999; anything else becomes 600

Unit: seconds

The minimum number of seconds between two looks for a stored network with a strictly higher priority than the one the daemon is on (the `priority=` value in `wpa_supplicant.conf` on legacy images, `autoconnect-priority` on NetworkManager images). A look runs only on a healthy pass, is skipped while a live stream, preview, capture or upload is running, and costs no internet traffic, only radio work: on legacy images a supplicant-side directed scan (which also surfaces hidden networks) with a 4-second wait, then a read of the scan results; on NetworkManager images a network list with NetworkManager's own rescan; plus a read of the stored-network list. The first look happens on the first healthy, non-streaming pass after start. A candidate must be present on two consecutive looks before the daemon tries to move, and a look that finds no candidate resets that count, so with the default the move comes 10 to 20 minutes after the higher-priority network appears. On arrival, when a probe target exists, the upload is measured: below the active floor (`MIN_UP_KBPS` by day, `NIGHT_MIN_UP_KBPS` at night) the candidate is set aside for three times the active cooldown and the daemon goes straight back to the previous network; otherwise it stays and reports the return. If the connection attempt itself fails it goes back to the previous network with no story line.

A running stream blocks the look entirely and the timer is not advanced then, so the look runs on the first free healthy pass afterwards. The set-aside length is three times the cooldown in force: `DANCE_COOLDOWN` (1200 seconds by default, so 3600) by day and `NIGHT_DANCE_COOLDOWN` (2400, so 7200) at night; only one network is set aside at a time (a new one replaces the old) and the candidate search skips it until the time expires. The too-slow test needs a probe target; in signal mode the daemon never sets a network aside and stays on the higher-priority network. `ASSOC_WAIT` bounds the connect attempt and the way back. The search never picks a network of equal priority, so with every stored network left at the default priority this knob has nothing to do; a temporary emergency or open network has priority 0, so any stored network with a higher priority is a candidate while the daemon sits on one.

Log lines:

- `[DEBUG][${dd/mm HH:MM:SS}] best_pref_id: cur=${current_id}(p=${current_priority}) -> best=${candidate_id|none}(p=${best_priority}) veto=${set_aside_id|none}`
- `[INFO][${dd/mm HH:MM:SS}] higher-priority network visible - trying to go home`
- `[WARN][${dd/mm HH:MM:SS}] preferred network too slow (${kbps} kbps) - benching it, going back`
- `[OK][${dd/mm HH:MM:SS}] returned to preferred network: ${SSID} (upload ${kbps} kbps)`
- `[OK][${dd/mm HH:MM:SS}] returned to preferred network: ${SSID} (signal mode)`

When to change it: lower it (300) when a phone hotspot with a data cap is a common fallback and you want to return home sooner (two sightings then take 5 to 10 minutes); raise it (1800) when scans disturb the link or the home network comes and goes and you want a very calm return. Set the stored networks' priorities first: without a strictly higher priority somewhere, no value of `PREF_CHECK` does anything.

The fallback is a metered hotspot; look every 5 minutes so the return home takes 5 to 10 minutes instead of 10 to 20.

```sh
PREF_CHECK=300
```

### REBOOT_AFTER_MIN

Default: `30`

Allowed: whole number 1 to 9999999; anything else becomes 30

Unit: minutes

How long an on-device Wi-Fi fault must persist before the daemon reboots the device. The clock is an in-memory timestamp set the first time a recovery round gathers on-device evidence, and it is compared only at the end of a recovery run that lost all three rounds: if the first sighting is at least `REBOOT_AFTER_MIN` minutes old (and, on NetworkManager images, NetworkManager has provably given up) the daemon writes one ERROR line to the local log file, syncs the disks, waits 2 seconds and runs `reboot`. On-device evidence means, in one round: the default gateway does not answer a ping (or there is no default route), no network reached association plus an address in this round, NetworkManager is not actively connecting, and at least one of three signs: a stored network is visible on the air yet unreachable; the radio scan comes back empty (no cached picture since boot, or the previous picture dropped after three consecutive empty scans); or the stored-network list reads back empty. The clock goes back to zero on any round classified as external (the gateway answers; a link with an address came up but carried no internet; or no stored network is visible while other networks are heard), on every sighting of a wrong password (a network the supplicant has temporarily disabled on legacy images, or an `nmcli` failure of the credentials kind on NetworkManager; the recovery steps still run), on any moment of verified internet, on every healthy pass, and on NetworkManager images whenever NetworkManager is still trying, is connected without internet, or reports the device unavailable (state 20). Since the clock lives in memory, a reboot or daemon restart starts it from zero, so a fault that survives the reboot earns the next one only after another full `REBOOT_AFTER_MIN` streak.

The check runs only at the end of a losing recovery run, so the reboot lands between `REBOOT_AFTER_MIN` and `REBOOT_AFTER_MIN` plus the length of one run (the gentle step, three rounds of candidate attempts bounded by `ASSOC_WAIT`, one recovery step per round, the emergency and open attempts, and 20-second pauses on the external branches). The ERROR line goes to the local file only, never to the site, because the network is down and the offline spool would die with the reboot; the site learns of it from the start lines after the boot. The empty-scan sign depends on the fixed three-empty-scans rule and on `SCAN_TTL`, which bounds how long a cached picture is trusted. On NetworkManager images the clock arms only when the device state reads disconnected (30) or failed (120) on two consecutive checks with no connecting sighting between them, or when `nmcli` itself is unreachable after the NetworkManager-restart step was already spent; any other state read resets the clock, a healthy pass wipes the NetworkManager evidence too, and a device reported unavailable (state 20: halted radio firmware, rfkill) never arms it. The smallest legal value is 1 minute and the knob cannot be switched off by value; a very large value (up to 9999999) postpones the reboot indefinitely in practice.

Log lines:

- `[ERROR][${dd/mm HH:MM:SS}] wedged ${REBOOT_AFTER_MIN}min with networks visible — rebooting (repeats per streak until cured)`
- `[ERROR][${dd/mm HH:MM:SS}] association refused - wrong password? (recovery continues, reboot stays off)`
- `[INFO][${dd/mm HH:MM:SS}] outage looks external (round ${round}) — waiting, not rebooting`
- `[INFO][${dd/mm HH:MM:SS}] NM is still trying - waiting it out`
- the INFO line written when NetworkManager reports the device connected while the internet check fails, which names the round number
- `[WARN][${dd/mm HH:MM:SS}] radio heard nothing on ${empties} scans in a row - previous results dropped`

When to change it: raise it (60 to 120) when reboots are expensive (a long boot, an attached workload that loses state) and the radio faults you see usually clear within the hour; lower it (15) on a device whose Wi-Fi chip is known to lock up and where a quick reboot is the accepted cure.

This device takes minutes to boot and its radio glitches usually clear within the hour; give recovery an hour first.

```sh
REBOOT_AFTER_MIN=60
```

## Upload rules

Six knobs decide when the daemon considers its link too slow, how it measures, and what another network must offer before the daemon moves. All six follow the numeric rule and are sealed after loading. The floor, the gain and the cooldown have night counterparts: `MIN_UP_KBPS`, `SWITCH_GAIN_PCT` and `DANCE_COOLDOWN` are copied into working values that the night profile swaps between `NIGHT_START` and `NIGHT_END` when `NIGHT_MODE=yes`, the default (see [Night profile](#night-profile)); every comparison in this section reads the working value, so wherever this section says the floor, the gain or the cooldown, it means the day or night value in force at that moment. `PROBE_KB`, `UP_STRIKES` and `STREAM_MIN_KBPS` have no night counterpart. The probe target is `PROBE_URL` when set, otherwise `SITE_URL/DEVICE_ID/SITE_API`; with neither the daemon is in signal mode and all six are inert: no slow sample is counted, no warning is written, no probe is sent and no evaluation runs, while the DEBUG `QA` lines still print the flow.

The passive sample. On every online pass the daemon reads `/sys/class/net/${IF}/statistics/tx_bytes` twice, 3 seconds apart, and turns the difference into kbps. No traffic is generated. This is what every healthy pass measures, and what the DEBUG `QA` lines show as `flow`.

The probe. At decision moments only, the daemon uploads `PROBE_KB` kilobytes of zeros to the probe target (`PROBE_URL`, otherwise the site endpoint) and reads the achieved speed. A probe is sent for the current network when an evaluation fires, for each stored network tried during an evaluation or an outage recovery, on arrival after a return to a higher-priority network, and for `awacs.sh speed`.

The evaluation. When enough slow samples have been counted and the cooldown allows, the daemon zeroes the count, records the start moment, logs a warning, probes the current network and, only if that probe is also below the floor, leaves the network, with a bar of that probe times the gain divided by 100, to try the other visible stored networks in turn, in the order the stored-network list reports them: connect (association, DHCP and an internet check; a candidate without internet is skipped unprobed), probe, log the result as `candidate [${id}] ${name} uploads at ${kbps} kbps`, remember the fastest, and stop early at four times the floor. Otherwise the warning stands alone, the cooldown is used up, and the measured figure reaches the Wi-Fi cell in its next send. It goes back home unless a challenger reached the gain bar: if the best candidate did not reach the bar, or measured 0, the daemon reconnects the original network and logs `no challenger beat the incumbent - staying on ${SSID}`; otherwise it connects to the best one and logs `connected: ${SSID} (upload ${best_kbps} kbps)`. If the original network cannot be reconnected, the best candidate is connected anyway. If the whole evaluation fails, the daemon hands the link back to the supplicant or NetworkManager and lets the next pass's internet check decide. During an outage recovery the same evaluation runs with no bar and no home network, so any working network wins.

### PROBE_KB

Default: `200`

Allowed: whole number 1 to 9999999; anything else becomes 200

Unit: KB (1 KB = 1024 bytes)

The size of the body the daemon uploads each time it measures real upload speed. The body is `PROBE_KB` times 1024 zero bytes sent to the probe target as an HTTP POST; the result is the average bytes per second of that transfer, converted to kbps (bytes per second times 8, divided by 1000). A probe is sent only at decision moments, never on a routine pass: the baseline check of the current network when an evaluation fires, each stored network tried during an evaluation or an outage recovery, the arrival check after a return to a higher-priority network, and the manual `awacs.sh speed` (root only; it reads the settings file). Routine passes read the transmit counter instead, which costs no traffic.

Needs a probe target: `PROBE_URL` if set, otherwise `SITE_URL/DEVICE_ID/SITE_API`; with neither, no probe is sent and the measurement prints 0. `curl` is given 15 seconds and still reports the average of what was sent up to then, so on a very slow link the probe is cut short: with 200 KB (1,638,400 bits) any link slower than about 109 kbps hits that limit and the figure is a partial average. If `curl` is missing or reports 0 and `wget` exists, `wget` posts the same bytes from a file in the private run directory with a 15-second network timeout under a 20-second hard limit; exit 0 or 8 (the server answered) counts as success and the rate is computed from the wall-clock time; any other exit prints 0. Each stored network tried in an evaluation costs one probe plus the connection wait (up to `ASSOC_WAIT` seconds for association and DHCP, then an internet check); a candidate that fails the internet check is skipped without a probe.

Log lines:

- `[INFO][${dd/mm HH:MM:SS}] candidate [${id}] ${name} uploads at ${kbps} kbps`
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

- `[DEBUG][${dd/mm HH:MM:SS}] QA: flow=${flow} kbps, strikes=${strikes}, profile=${day|night}`
- `[WARN][${dd/mm HH:MM:SS}] sustained slow upload (${flow} kbps) - evaluating known networks`
- `[WARN][${dd/mm HH:MM:SS}] preferred network too slow (${kbps} kbps) - benching it, going back`
- `[OK][${dd/mm HH:MM:SS}] returned to preferred network: ${SSID} (upload ${kbps} kbps)`
- `[INFO][${dd/mm HH:MM:SS}] day profile active (floor ${MIN_UP_KBPS} kbps)`

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

- `[DEBUG][${dd/mm HH:MM:SS}] QA: flow=${flow} kbps, strikes=${strikes}, profile=${day|night}`
- `[DEBUG][${dd/mm HH:MM:SS}] QA(stream): flow=${flow} kbps, strikes=${strikes}`

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

At night `NIGHT_GAIN_PCT` (default 300) takes its place. Only an evaluation started from a healthy pass uses the bar; during an outage recovery the same comparison runs with no bar and no home network, so any working network wins. Because the evaluation only runs when the baseline is below the floor, the bar is always below the floor times `SWITCH_GAIN_PCT` divided by 100. If the baseline probe fails (0 kbps) the bar is 0, and the extra rule that the best must be above 0 keeps the device on its current network unless a candidate really uploaded. If the original network cannot be reconnected after a lost evaluation, the best candidate is connected anyway, bar or not, as the only working link. Inert in signal mode.

Log lines:

- `[INFO][${dd/mm HH:MM:SS}] candidate [${id}] ${name} uploads at ${kbps} kbps`
- `[OK][${dd/mm HH:MM:SS}] no challenger beat the incumbent - staying on ${SSID}`
- `[OK][${dd/mm HH:MM:SS}] connected: ${SSID} (upload ${best_kbps} kbps)`

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

At night `NIGHT_DANCE_COOLDOWN` (default 2400) takes its place; the elapsed time is compared against whichever value is in force when the check runs. Slow samples keep counting during the cooldown, so an evaluation fires on the first slow sample after it ends. Only one set-aside network is remembered at a time; a newer too-slow return replaces it. Inert in signal mode (no evaluation and no set-aside).

Log lines:

- `[WARN][${dd/mm HH:MM:SS}] sustained slow upload (${flow} kbps) - evaluating known networks`
- `[WARN][${dd/mm HH:MM:SS}] live stream starving (${flow} kbps) - evaluating known networks`
- `[WARN][${dd/mm HH:MM:SS}] preferred network too slow (${kbps} kbps) - benching it, going back`

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

- `[DEBUG][${dd/mm HH:MM:SS}] QA(stream): flow=${flow} kbps, strikes=${strikes}`
- `[WARN][${dd/mm HH:MM:SS}] live stream starving (${flow} kbps) - evaluating known networks`

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

- `[INFO][${dd/mm HH:MM:SS}] night profile active (floor ${NIGHT_MIN_UP_KBPS} kbps)`
- `[INFO][${dd/mm HH:MM:SS}] day profile active (floor ${MIN_UP_KBPS} kbps)`
- `[DEBUG][${dd/mm HH:MM:SS}] QA: flow=${flow} kbps, strikes=${strikes}, profile=${day|night}`

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

- `[INFO][${dd/mm HH:MM:SS}] night profile active (floor ${NIGHT_MIN_UP_KBPS} kbps)`

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

- `[INFO][${dd/mm HH:MM:SS}] day profile active (floor ${MIN_UP_KBPS} kbps)`

When to change it: set it to the hour when people start watching again. If you want the relaxed rules all day long, do not set the start equal to the end (that disables the night profile); lower the day knobs themselves instead.

The first viewer looks at the feed after seven.

```sh
NIGHT_END="07:00"
```

### NIGHT_MIN_UP_KBPS

Default: `200`

Allowed: whole number 1 to 9999999 (leading zeros are dropped, so `0200` becomes 200); zero, a negative number, a decimal, an empty value or text becomes 200, silently

Unit: kbps

The minimum acceptable upload speed while the night profile is active; it replaces `MIN_UP_KBPS` and is used in the same four places. On every healthy pass with no stream, preview, capture or upload in progress, a transmit-counter reading of at least 20 kbps but below this floor counts as one slow sample. After `UP_STRIKES` slow samples, and once the cooldown has passed, the daemon probes the current network by uploading a test body of `PROBE_KB` kilobytes to the probe target (15 seconds at most; a failed probe reads 0), and only if that measured rate is also below this floor does it go on to test the other stored networks; otherwise the samples are cleared. On return to a higher-priority network, a measured upload below this floor makes the daemon set that network aside for three times the cooldown and go back to the previous one. While testing candidates, once one uploads at four times this floor or more the daemon stops testing further candidates as plainly fast enough; this also applies during the recovery from lost internet.

Effective only with `NIGHT_MODE=yes` and inside the window; by day `MIN_UP_KBPS` is used. Needs a probe target: without one the slow-sample check, the measured-upload checks and the set-aside test are all skipped, so the floor changes nothing. While a live stream is running the slow-sample gate uses `STREAM_MIN_KBPS` instead, but the measured-upload check that follows still uses this floor. `UP_STRIKES` is the same by day and night. The four-times early stop means a lower night floor also lets recovery settle sooner on a merely adequate network (800 kbps at night versus 1600 by day with the defaults). With a floor of 20 or below the passive check can never count a slow sample, because it only looks at activity of at least 20 kbps; the two measured-upload comparisons that remain (after a starving stream, and on return to a higher-priority network) then fire only when the probe measures below that tiny number, which in practice means only when it fails and returns 0.

Log lines:

- `[INFO][${dd/mm HH:MM:SS}] night profile active (floor ${NIGHT_MIN_UP_KBPS} kbps)`
- `[WARN][${dd/mm HH:MM:SS}] sustained slow upload (${flow} kbps) - evaluating known networks`
- `[WARN][${dd/mm HH:MM:SS}] preferred network too slow (${kbps} kbps) - benching it, going back`
- `[INFO][${dd/mm HH:MM:SS}] candidate [${id}] ${name} uploads at ${kbps} kbps`

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

- `[OK][${dd/mm HH:MM:SS}] no challenger beat the incumbent - staying on ${SSID}`
- `[OK][${dd/mm HH:MM:SS}] connected: ${SSID} (upload ${best_kbps} kbps)`

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

- `[WARN][${dd/mm HH:MM:SS}] sustained slow upload (${flow} kbps) - evaluating known networks`
- `[WARN][${dd/mm HH:MM:SS}] live stream starving (${flow} kbps) - evaluating known networks`
- `[WARN][${dd/mm HH:MM:SS}] preferred network too slow (${kbps} kbps) - benching it, going back`

When to change it: raise it when overnight evaluations are disturbing recordings or the stream and the link is only marginally slow; lower it when a slow night link should be re-examined sooner.

At most one evaluation per hour at night.

```sh
NIGHT_DANCE_COOLDOWN=3600
```

## Behaviour

Three switches. None of them passes through the validation block: each is compared once with the exact lowercase word `yes` at the one place it is used; any other spelling means off, silently, with no fallback and no warning. The template writes `"yes" | "no"`, but only `yes` is recognised.

The order of a recovery run decides when the open networks come in. A run starts at boot without internet, or after `NET_FAIL_TICKS` consecutive passes without it, the latter announced by `internet lost on ${IF} - engaging`. It first drops any temporary entry left from the previous attempt, then opens gently (a reassociation and a wait; in the first run of an outage the reassociation is skipped while the default gateway still answers), then runs up to three rounds. In each round the stored networks are tried first, unless NetworkManager itself is in the middle of a connection; then the diagnosis decides: on-device evidence (the gateway silent, no successful association in this round, plus a visible stored network, an empty scan or an empty stored list) triggers the round's recovery step, then the emergency networks, then the open networks; otherwise the outage is called external (`outage looks external (round ${round}) — waiting, not rebooting`) and the emergency and then the open networks are tried before a 20-second wait, a failed attempt being followed by a return to the network the run started on and by re-enabling every stored network. On NetworkManager, inside the on-device branch, a NetworkManager still activating makes the round wait 20 seconds and continue with no emergency or open attempt, and a NetworkManager reporting connected without internet skips the recovery step and goes straight to the emergency and then the open networks. A successful connection to an open or emergency network inside a run started from a pass is followed by the main loop's `internet restored: ${SSID}` line; a win inside the boot run prints no such line.

### OPEN_NETWORKS

Default: `"yes"`

Allowed: the word `yes` turns it on; any other value (`no`, empty, `YES`, `true`, `1`) turns it off, with no fallback and no warning

Unit: yes/no switch

When the device has lost the internet and neither its stored networks nor the emergency networks bring it back, this switch lets the daemon join a passwordless network that anybody nearby broadcasts. Open networks are the last step of each of the up to three rounds of a recovery run: after the gentle first step, after the stored networks, and after the emergency networks that follow the round's recovery step (for an on-device fault) or follow the classification directly (for an external outage). On a NetworkManager image two special cases apply: when NetworkManager reports connected but there is no internet, the recovery step is skipped and the emergency and then the open networks are tried directly; when NetworkManager is found mid-activation after the on-device evidence has been gathered, the round only waits 20 seconds and moves on, trying neither; a NetworkManager that is busy at the start of a round takes the external path, where the emergency and open networks are still tried. Only networks the scan marks as open are candidates: on the legacy backend a network counts as secured when its `iw` capability line carries Privacy or a WPA or RSN block (with `iwlist` as the fallback: `Encryption key:on`; with the supplicant table as the fallback: flags carrying WPA, RSN or WEP); on NetworkManager a network is open when the `SECURITY` column of `nmcli` is empty. Open strangers with a signal below -80 dBm (wpa) or 25 percent (NetworkManager) are skipped, a dual-band network counts once, and a network whose splash page intercepts traffic fails the internet check, so it is dropped again unless the portal lets ping through, since a ping answer alone counts as online. The network is added as a temporary entry that is never written to disk: on wpa an in-memory supplicant entry with `key_mgmt NONE`; on NetworkManager a keyfile under `/run/NetworkManager/system-connections`, named on the daemon's own pattern, with `autoconnect=false`, gone at reboot. Its id is written to `RUN_DIR/open_id` before the attempt so a crashed daemon's successor removes it at start; on success the stored networks are re-enabled so the device can drift back home on its own, and the temporary entry is deleted on the first healthy pass that finds the device on a different network, at the start of the next recovery run, and after the third recovery step on NetworkManager.

Emergency networks (`SAFETY_NET`) are always tried first; open networks are reached only when that list is empty or every entry failed. On the legacy wpa backend (`dhcpcd` and `wpa_supplicant`) any open network whose name contains non-ASCII characters, or a literal backslash, is skipped, because the scan escapes such names in the `\xNN` form and the supplicant's quoted form cannot carry a backslash; on NetworkManager names are matched as hex bytes and written as byte arrays, so Arabic, emoji and symbol names are usable. Monitor-only mode never runs a recovery, so the switch has no effect there. The marker `open_id` moves with `RUN_DIR`. On wpa the candidates come from the scan picture, served from the cache while it is younger than `SCAN_TTL`; on NetworkManager they come from NetworkManager's own list with its rescan. The two story lines below reach the site when `LOG_TARGET` is `both` or `remote` and `SITE_URL` is set; under `remote` they are not kept in the local file, and `LOG_LANG=ar` replaces their local text with the Arabic wording. Retiring the entry writes nothing to the log on wpa; on NetworkManager it writes one DEBUG line when the profile is already gone, and one ERROR line beginning `REFUSING delete:` when the deletion guard refuses. On NetworkManager the deletion helper refuses to remove any profile the daemon did not create (a name that does not follow its pattern, or a file outside `/run/NetworkManager/system-connections/awacs-*`), so your own profiles are never touched.

Log lines:

- `[INFO][${dd/mm HH:MM:SS}] trying open networks as last resort`
- `[OK][${dd/mm HH:MM:SS}] connected to OPEN network: ${SSID}`
- `[DEBUG][${dd/mm HH:MM:SS}] connect_id: activating ${id} (backend ${BACKEND})`
- `[DEBUG][${dd/mm HH:MM:SS}] del_own: ${uuid} already gone` (NetworkManager, when the temporary entry has already vanished by the time it is retired)

When to change it: set it to `no` when the device must never attach to a stranger's network (site policy, or a place full of hotel and cafe portals where each attempt is wasted). Keep `yes` for a device whose only duty is to get its data out and where any working internet beats none.

This camera sits in an office where joining unknown networks is not allowed.

```sh
OPEN_NETWORKS="no"
```

### STEALTH_MODE

Default: `"no"`

Allowed: the word `yes` turns it on; any other value (`no`, empty, `YES`, `true`) leaves it off, with no fallback and no warning

Unit: yes/no switch

Makes the device harder to spot with a casual IPv4 ping sweep or an mDNS browser on the local network. Once, during daemon start, it adds one firewall rule that silently drops incoming ping requests arriving on the Wi-Fi interface: it first tests whether the rule exists (`iptables -C INPUT -i "$IF" -p icmp --icmp-type echo-request -j DROP`) and only if absent inserts it at the top of the INPUT chain (`iptables -I` with the same arguments), so a respawning launcher never stacks duplicate rules. It then stops the Avahi service with `systemctl stop avahi-daemon`: the service is stopped, not disabled or masked, so it returns at the next boot and is stopped again when the daemon starts. Only incoming IPv4 ping requests are blocked: the rule lives in the INPUT chain and matches echo requests only, so the daemon's own outgoing pings and their replies still pass and the internet check and the gateway check keep working; no `ip6tables` rule is added, so an IPv6 ping still gets an answer. Both commands ignore failure, and the story line is printed unconditionally afterwards, so it appears even when `iptables` is missing or the stop failed. Nothing is undone when the daemon stops (the stop handler only re-enables the stored networks and prints the farewell box): the ping-drop rule stays in the kernel until reboot or a manual `iptables -D INPUT -i ${IF} -p icmp --icmp-type echo-request -j DROP`, and Avahi stays stopped until reboot, a manual `systemctl start avahi-daemon`, or socket activation. The DHCP hostname is not hidden by this switch; do that in `/etc/dhcpcd.conf` if wanted.

The rule binds to the detected interface (or `AWACS_IF`) only; a second Wi-Fi dongle or the Ethernet port still answers pings. `iptables` is not in the daemon's tool inventory, so a missing binary is neither reported nor installed and the failure is silent. Monitor-only mode parks before this step, so stealth is never applied there. The toolbox words never apply it. Only `avahi-daemon.service` is stopped; `avahi-daemon.socket` is left alone, so socket activation can start the service again before the next boot if a local program opens Avahi's socket. The story line reaches the site when `LOG_TARGET` is `both` or `remote` and `SITE_URL` is set, and under `remote` it is not kept in the local file; `LOG_LANG=ar` replaces its local text with the Arabic wording. With stealth on, IPv4 ping from the LAN to the device fails and `hostname.local` stops resolving, so LAN monitoring that relies on either must use another method.

Log lines:

- `[INFO][${dd/mm HH:MM:SS}] stealth mode active (icmp hidden, avahi stopped)`

When to change it: turn it on for a device that lives on a shared or untrusted network (a shared building Wi-Fi, a hotspot with strangers) where you do not want it visible to neighbours. Leave it off when you check the device from the LAN with ping or find it by `hostname.local`, since both stop working. It is applied once at start and not removed at stop.

The camera hangs on a shared building network and should not show up on a ping sweep.

```sh
STEALTH_MODE="yes"
```

### DEBUG

Default: `"yes"` (or the value of the `AWACS_DEBUG` environment variable when that is set and not empty)

Allowed: the word `yes` writes DEBUG lines; any other value (`no`, empty, `YES`, `true`) silences them, with no fallback and no warning

Unit: yes/no switch

Controls whether the daemon writes its decision-trace lines, at level DEBUG, into the local log file. These lines go straight to `LOG_FILE`: they never travel to the reporting site, they are always in English whatever `LOG_LANG` says, and they are still written locally under `LOG_TARGET=remote`, because that filter concerns story lines only. There are exactly seven of them: the number of radio scan tries used after each fresh scan (only when the scan cache was older than `SCAN_TTL`); on NetworkManager, a note when a temporary entry asked to be deleted is already gone; a line before every network activation the daemon performs, naming the id and the backend; the outcome of each preferred-network look, with the current and best priorities and any set-aside network; a line during a recovery round when the evidence points to an on-device fault; and, on every healthy pass, one upload-meter line with the transmit-counter rate and the slow-sample count, either the `QA(stream)` form while a live stream or upload is running or the `QA` form with the day or night profile otherwise. The default is taken from the environment: an exported non-empty `AWACS_DEBUG` (in `rc.local` before the launch loop, or an `Environment=` line in the systemd unit) becomes the default, while an unset or empty `AWACS_DEBUG` gives `yes`. The settings file is read afterwards, so a `DEBUG=` line there overrides both the built-in default and the environment variable, and the value is then sealed.

`AWACS_DEBUG` supplies the default only; a `DEBUG` line in the file wins. The `-d` self-daemonize relaunches the script through `setsid` and hands the environment on to the background daemon, so `AWACS_DEBUG` carries through. DEBUG lines count toward the log rotation: with `DEBUG=yes` one `QA` line lands every healthy pass, and a pass takes about `TICK` plus 3 seconds, so the 1500-line `LOG_CAP` holds roughly five hours of a healthy day instead of days of story lines. `LOG_LANG`, `LOG_TARGET` and `SITE_URL` have no effect on these lines. With `NIGHT_MODE` off the `QA` line always reads `profile=day`. In signal mode the `QA` lines still print the flow, but no evaluation follows. The toolbox words run as root with the file loaded and write to the same log: `evaluate` and `scan` call the scanner on both backends, and `networks` does so on the wpa backend, so a hand-run command also writes the `scan:` DEBUG line into the daemon's log whenever the scan cache is older than `SCAN_TTL`; `status` and `speed` never scan; `check` and `help` run without root and never write DEBUG lines.

Log lines:

- `[DEBUG][${dd/mm HH:MM:SS}] scan: ${used}/${tries} tries used`
- `[DEBUG][${dd/mm HH:MM:SS}] del_own: ${uuid} already gone`
- `[DEBUG][${dd/mm HH:MM:SS}] connect_id: activating ${id} (backend ${BACKEND})`
- `[DEBUG][${dd/mm HH:MM:SS}] best_pref_id: cur=${current_id}(p=${current_priority}) -> best=${candidate_id|none}(p=${best_priority}) veto=${set_aside_id|none}`
- the on-device evidence line of a recovery round, which names the round number and whether a wrong password was seen
- `[DEBUG][${dd/mm HH:MM:SS}] QA(stream): flow=${flow} kbps, strikes=${strikes}`
- `[DEBUG][${dd/mm HH:MM:SS}] QA: flow=${flow} kbps, strikes=${strikes}, profile=${day|night}`

When to change it: set it to `no` once a device is stable and you want the local log to keep days of story lines instead of hours of per-pass meter readings. Keep `yes` while working out why the device did or did not switch networks: the DEBUG lines are the only record of the per-pass upload meter, the slow-sample count, the preferred-network verdicts and the on-device fault evidence. Use `AWACS_DEBUG` when the launcher rather than the settings file should decide, and then leave `DEBUG` out of the file, or the file wins.

The device has run cleanly for weeks; keep the 1500-line log for the story, not the meter.

```sh
DEBUG="no"
```

## Files

Five knobs place the daemon's files and bound their sizes. `LOG_CAP`, `SCAN_TTL` and `SPOOL_CAP` follow the numeric rule; `RUN_DIR` must begin with `/`; `LOG_FILE` is never checked. All five are sealed after loading, so a change needs a daemon restart.

### LOG_FILE

Default: `/var/log/awacs.log`

Allowed: any absolute path; the script never checks the value (it is the only Files knob absent from the validation block: no test that the path is absolute, no test that it exists), so there is no fallback

Unit: file path

The local log. Every line the daemon writes locally goes through one function that appends `[LEVEL][dd/mm HH:MM:SS] text` to this path; the levels are INFO, OK, WARN, ERROR and DEBUG. The file is created on the first write, readable by root only, because the script sets `umask 077` near its start, before any file is touched. A write never waits on the network and never stops the daemon: when the path cannot be opened for appending (a missing directory, a read-only or full filesystem, an empty value), each line is dropped silently, the line count that follows reads zero, and the daemon keeps running. When the file grows past the `LOG_CAP` limit it is trimmed through a sibling temporary file, `${LOG_FILE}.t`, that is renamed over the log.

`LOG_LANG` picks the language of the story lines written here (DEBUG lines stay English). `DEBUG=yes` writes one DEBUG line on every healthy pass, which is what fills the file. `LOG_TARGET=remote` keeps only the WARN and ERROR story lines locally, but DEBUG lines, local-only lines and the `reporting:` line at start (and the downgrade warning when it applies) still land here. `LOG_CAP` sets the trim size. Every root run of the script, the toolbox words included, appends through the same function. `install.sh --uninstall --purge` removes only the default path and its `.t` sibling, not a moved log. The optional terminal tool `tools/awacs-tui.sh` reads `LOG_FILE` from the settings file and accepts only an absolute value.

Log lines:

- `[${LEVEL}][${dd/mm HH:MM:SS}] ${text}` (the shape of every local line)

When to change it: rarely. Move it when the log must live on another disk (a USB stick, to spare the SD card) or where another tool expects it. The directory must exist and be writable at the moment of each write: lines written before it is available are lost, with no fallback and no warning.

Keeps the per-pass DEBUG writes off the SD card; lines written before `/mnt/usb` is mounted are lost silently.

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

If the directory cannot be created or written, the lock file cannot be opened and the daemon does not run; the `rc.local` loop or the systemd unit (`RestartSec=10`) starts it again every 10 seconds, so the path must be on a writable filesystem from early boot. Two markers assume the directory is emptied at reboot: on persistent storage, `apt_tried` would block the automatic tool install on every later boot, and on the wpa backend a stale `open_id` from an earlier boot is handed to `remove_network` at the next start with no name check, which can remove a real stored network from the running supplicant until the supplicant restarts (the NetworkManager backend checks the entry's name and file location first and refuses anything it did not create). The toolbox words share the directory as root: `status` reads the lock for the PID; `scan`, `evaluate` and, on wpa, `networks` share the scan cache. `install.sh` uses the fixed default path for its own status and uninstall; the optional terminal tool `tools/awacs-tui.sh` reads `RUN_DIR` from the settings file and accepts only an absolute value. The rootless `check` and `help` never create it.

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
- `spool`: site-bound lines not yet delivered. `spool.sending`: the snapshot being sent during a delivery, rescued at the next start if a delivery was interrupted. `spool.t`: the temporary file used while trimming or merging.
- `open_id`: the id (wpa network number or NetworkManager profile UUID) of the temporary entry the daemon created itself for an open network or an emergency network. Written before each attempt and kept while the entry is in use, removed when the entry is retired or the attempt fails. A restarted daemon reads it first and removes that entry, so nothing the daemon created outlives it (on NetworkManager after checking the entry's name and file location; on wpa with no check).
- `probe`: `PROBE_KB` kilobytes of zeros used as the upload body when `curl` is missing or returned no speed and `wget` is used instead; deleted right after the measurement.
- `apt_tried`: an empty marker created before the single background package-install attempt of a boot; while it exists no further attempt is made.

Beside the log, not under `RUN_DIR`: `${LOG_FILE}.t`, the rotation temporary.

### SCAN_TTL

Default: `30`

Allowed: whole number 1 to 9999999; anything else becomes 30

Unit: seconds

How long one scan result is reused before the radio is asked again. A Wi-Fi scan takes the radio off its channel, so the result is written to `RUN_DIR/scan` and any request that arrives while the file is younger than `SCAN_TTL` seconds, measured by the file's modification time, gets the file instead of a new scan. An empty file that is fresh counts as a real answer (a radio that hears nothing) and is served the same way. When a scan hears nothing from every source (`iw`, then `iwlist`, then the backend's own table: the supplicant's scan results on wpa, NetworkManager's list on NetworkManager), the previous list is kept and the file's timestamp is refreshed, so a silent radio is asked again once per `SCAN_TTL`, not once per caller; after three such empty scans in a row (a fixed count, not a knob) the old list is dropped and an empty answer is cached for the next `SCAN_TTL`. A scan that returns entries but no network name keeps the previous list without refreshing the timestamp, so the next caller scans again.

On the wpa backend, everything that needs to know which networks are on the air (stored networks visible, open-network candidates, the preferred-network look, the empty-radio check, the ordering used in signal mode) reads this cache; the Wi-Fi cell counts read the file as it is, whatever its age, and never trigger a scan. On the NetworkManager backend the candidate lists and the cell counts come from NetworkManager's own table, and the cache only feeds the empty-radio check, the ordering used in signal mode, and the `scan` and `evaluate` toolbox words. Toolbox words run as root share the file, so a hand-run `sudo awacs.sh scan` refreshes the daemon's picture and the daemon's scan serves the toolbox. The age is the system clock minus the file's modification time; a clock that steps backward after the file was written (a board without a clock battery syncing time at boot) makes the cache look fresh for longer, and a forward step makes it look stale sooner. `awacs.sh help` prints the value in its `scan` row, but only under `sudo` does that row show the file's value, since the file is read only as root.

Log lines:

- `[WARN][${dd/mm HH:MM:SS}] scan failed - using previous results (if any)`
- `[WARN][${dd/mm HH:MM:SS}] radio heard nothing on ${empties} scans in a row - previous results dropped`
- `[DEBUG][${dd/mm HH:MM:SS}] scan: ${used}/${tries} tries used`
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

Only matters when `SITE_URL` is set and `LOG_TARGET` is `both` or `remote`; otherwise nothing is ever spooled. The spool is sent at a daemon start that finds the internet up, on the third consecutive healthy pass and on every thirtieth healthy pass after that while lines remain (a healthy pass takes about 13 seconds with the defaults, so after roughly 40 seconds and then about every six minutes), and every 300 seconds in monitor-only mode. A send that fails while the internet is up appends in the background without trimming; the cap catches up at the next offline append or delivery. Stored lines use `SITE_LANG` and the `SITE_TZ` time stamp. The file lives on memory-backed storage and is lost at reboot, which is why the line announcing a reboot is written locally only. A daemon killed in the middle of a delivery leaves `spool.sending`; the next start puts that whole snapshot back in front of newer lines, so a few lines already sent before the kill may be sent twice.

Log lines:

- `[${LEVEL}] AWACS: ${text}, ${dd/mm/yyyy hh:mm:ss AM|PM}.` (the shape of every stored line)

When to change it: raise it when the site should receive a long outage's whole story rather than its opening line and its last stretch; lower it to keep the burst of catch-up sends after recovery short.

The site is read every morning and a whole night's outage should arrive complete.

```sh
SPOOL_CAP=200
```

## Environment variables

These are read from the daemon's environment, not from the settings file. Set them in the launcher: the `Environment=` lines of the systemd unit's drop-in, or the `rc.local` line before the launch loop.

`DEVICE_ID`: the device's name on the reporting site, used in the site path `SITE_URL/DEVICE_ID/SITE_API`, in the first start line and in the `device` row of `awacs.sh status`. Resolved on every use as described under [DEVICE_ID](#device_id): the variable, then the first non-blank line of `/tmp/device_id`, checked against `^[A-Za-z0-9_-]{1,32}$`, then the short hostname, then the word `device`. The intended sources are the `export` line in `rc.local` and the drop-in `awacs.service.d/10-device-id.conf` that `install.sh` writes. It is not a settings knob and is not validated at load time; but because the settings file is executed in the same shell, a `DEVICE_ID=` line in it is seen exactly like the environment value. That is not the documented place for it: the environment is.

`AWACS_IF`: the Wi-Fi interface name. When set and not empty it replaces the automatic choice (the first connected interface, else the first one that is up, else the first present, else `wlan0`). It is not validated; a name that does not exist is reported once at start by a story line, `[ERROR][${dd/mm HH:MM:SS}] interface ${IF} not present - is the WiFi hardware alive?`, and the daemon carries on. The rootless `check` and `help` always use `wlan0`.

`AWACS_CONF`: the settings file path, default `/etc/awacs.conf`. A missing file is skipped silently; the same owner and mode rules apply to any path.

`AWACS_DEBUG`: the value `DEBUG` has before the settings file is read, default `yes`. Because the file is read afterwards, a `DEBUG=` line in the file replaces it, so the environment silences DEBUG lines only when the file leaves `DEBUG` unset.

Two more names appear in the script and are not settings. `AWACS_CLI` is set by the toolbox function itself so that the scan warnings raised during a hand-run word stay in the local log instead of going to the site; the check only tests that the variable is non-empty, so exporting it into the daemon's environment gives the daemon the same behaviour: do not, or the daemon's own scan warnings stay local too. `AWACS_DAEMONIZED` is set by the `-d` flag when it relaunches the script in the background through `setsid`, so that the child does not relaunch again. The parent takes the fast lane at backend detection and skips the early-boot wait, which the child then pays once; and a monitor-only daemon started with `-d` never exits to be restarted once `nmcli` appears, because the `-d` path has no relauncher.
