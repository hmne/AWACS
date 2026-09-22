# Integration

The daemon talks to one URL: `${SITE_URL}/${DEVICE_ID}/${SITE_API}`. Every request to the site goes there as an HTTP POST: log lines, the WiFi cell, the fourth rung of the internet check and the upload probe (the probe goes to `PROBE_URL` instead when that knob is set). Anything that answers the contract below can receive it: the two receivers shipped in `server/`, a dashboard of your own, or an existing site with an endpoint of its own name.

## The endpoint

`SITE_URL` is the base URL; a trailing slash is stripped. `DEVICE_ID` comes from the environment, then `/tmp/device_id`, then the short hostname, then the word `device`; only a slug of letters, digits, `_` and `-` up to 32 characters is accepted. `SITE_API` is the file name under `${SITE_URL}/${DEVICE_ID}/`. It defaults to `receiver.php`, the receiver shipped in `server/`. A site that already has an endpoint of another name sets `SITE_API` to that name in `/etc/awacs.conf`, or through `install.sh --api NAME`. The value must start with a letter, digit or `_`, may contain letters, digits and `_ . / -`, is at most 64 characters long and must not contain `..`; any other value falls back to `receiver.php` without a message.

Under Apache or nginx the receiver file on the server carries exactly the `SITE_API` name. The Python receiver and PHP's built-in server in router mode answer only the path `/<device-id>/receiver.php`; with those two, leave `SITE_API` at its default.

## The contract

Transport: HTTP POST with a form-encoded body and a plain-text reply. The daemon reads only the status code; reply bodies are ignored. The contract carries no credential; see [SECURITY.md](../../SECURITY.md).

| Request | Reply | Effect |
| --- | --- | --- |
| `file=log/log.txt` and `data=<line>` | `200`, body `OK` | The line is appended. |
| `file=tmp/wifi.tmp` and `data=<cell>` | `200`, body `OK` | The file is overwritten atomically. |
| POST with no `file` field (a raw body counts; so does GET) | `400`, body `Error: no operation` | Nothing is written. The daemon reads this exact code as "site reachable". |
| `file=` with any other path | `403`, body `Error: forbidden file` | Nothing is written. |

The four requests as the script issues them; `$API` stands for the endpoint URL:

```sh
# a log line
curl -sf --max-time 4 --data-urlencode "file=log/log.txt" --data-urlencode "data=$line" "$API"
# the WiFi cell
curl -sf --max-time 4 --data-urlencode "file=tmp/wifi.tmp" --data-urlencode "data=850,2,3,2.4GHz,HomeNet" "$API"
# the internet rung: the printed code must be 400
curl -s -o /dev/null -w '%{http_code}' --max-time 3 --data-urlencode "probe=1" "$API"
# the upload probe: PROBE_KB kilobytes of zeros as a raw body; the speed is curl's own figure
head -c $((PROBE_KB * 1024)) /dev/zero | curl -s -o /dev/null -w '%{speed_upload}' --max-time 15 --data-binary @- "$PROBE_URL"
```

### Log lines

One POST per event with `file=log/log.txt`. The line is `[LEVEL] AWACS: <message>, dd/mm/yyyy hh:mm:ss AM/PM.` and the levels are `INFO`, `OK`, `WARN` and `ERROR`; `DEBUG` lines stay in the local file. The message is the event's Arabic text when the program has one, otherwise the English text of the local log; the local file always carries the English line. The timestamp uses `SITE_TZ` when it is set (an IANA zone name such as `Europe/Berlin`; letters, digits and `/ _ + -`, up to 64 characters), otherwise the device's own zone.

Lines are sent only when `LOG_TARGET` is `both` or `remote` and `SITE_URL` is set; with `remote` the local file keeps only the WARN and ERROR site lines (DEBUG lines and the local-only lines are unaffected). While the internet is down, and whenever a send fails (no answer within 4 s, or a 4xx or 5xx status), the line goes to the spool `/run/awacs/spool` instead. The spool keeps `SPOOL_CAP` lines (default 60): its first line, the opening of the outage, is pinned and the middle rolls off. It is sent in order three ticks (about 30 s) after the internet is verified healthy, then retried every 30 ticks (about 5 min) while lines remain, and at a daemon start that finds the internet up; a failed send stops the flush and the remainder waits.

### The WiFi cell

One POST every six ticks (about 60 s) while the internet is up, with `file=tmp/wifi.tmp`. It is sent when `REPORT_WIFI` is `yes` and `SITE_URL` is set, or when it is `auto` and log lines go to the site; `no` never sends. The value is one line of five comma-separated fields:

| Field | Content |
| --- | --- |
| kbps | The last measured upload speed; `0` when nothing was measured on the network the device is on now. |
| visible | Stored networks currently present in the scan cache (the daemon's on wpa, NetworkManager's on nm). The report causes no radio traffic. |
| total | Stored networks. |
| band | `2.4GHz`, `5GHz`, `6GHz` or empty. |
| SSID | The current network's name, or `-` when the device is not associated. |

The SSID is last so that its own commas survive: split on the first four commas only. Example: `850,2,3,2.4GHz,HomeNet`.

### The internet rung

The internet check tries, in order, a ping to `8.8.8.8`, a ping to `1.1.1.1`, an HTTP `204` from `http://connectivitycheck.gstatic.com/generate_204`, and finally a POST to the endpoint that must answer exactly `400`. The last rung exists only when `SITE_URL` is set; it rescues a carrier network that drops ICMP or rewrites the 204 page. The code must stay 400: a captive portal answers its splash page with 200, 302 or 511, and a receiver that answered 200 to an empty POST would make a portal read as online.

### The upload probe

At decision moments the daemon measures upload speed by posting `PROBE_KB` KB (default 200) of zeros to the probe target: `PROBE_URL` when set, otherwise the endpoint. curl reports its own `speed_upload` and the daemon converts bytes per second to kbps. The reply's status code plays no part in the measurement; the body carries no `file` field, so a receiver answers `400`. When curl is missing or reports zero, wget posts the same bytes from a file with a 15 s timeout and the speed is computed from the elapsed time; a wget exit other than 0 or 8 (the server answered 4xx or 5xx after the upload) reads as `0` kbps. A probe target therefore has to accept a body of that size and answer with an HTTP status.

`awacs.sh speed` runs one probe by hand and prints the target and the result.

## The shipped receivers

`server/receiver.php` and `server/receiver.py` implement the contract with no database and no dependencies. Where they route by path (the Python receiver and PHP's router mode), the device id must be letters, digits, `_` and `-` up to 32 characters, the rule the daemon applies to `DEVICE_ID`. Both append `log/log.txt` and keep it under 256 KB: once the file passes 512 KB the newest 256 KB survive and the partial first line is dropped. Both overwrite `tmp/wifi.tmp` through a temporary file and a rename. Both answer `400 Error: too large` when `data` exceeds 64 KB, `500 Error: write failed` when the disk write fails, and `400 Error: no operation` to GET.

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

## Reading the two files from a dashboard

`log/log.txt` is append-only, newest line last; show its tail. Escape the text before rendering it: the SSID inside a line is chosen by whoever runs the access point.

`tmp/wifi.tmp` is one line, rewritten about every 60 s while online and not at all while the internet is down, so the file's age is the liveness signal: hide the cell when the file is older than about 180 s (three missed writes). Show the speed only when the first field is not `0`. Split on the first four commas only; the SSID may contain right-to-left text, so isolate its direction when rendering (`<bdi>` in HTML).

## Your own endpoint

An existing site keeps the device unchanged by implementing the four replies of the contract at `${SITE_URL}/${DEVICE_ID}/${SITE_API}` and by having `SITE_API` set to its file name. The `400` for a POST without `file` is the part that must not change: it is the daemon's reachability signal.

To keep the log on one server and the probe elsewhere, set `PROBE_URL`. The probe target only has to accept a POST body of `PROBE_KB` KB and answer with an HTTP status; the internet rung still uses the endpoint's `400`.

## Local-only operation

With `SITE_URL` empty nothing above is used: no request reaches a site, the internet check has three rungs, and the daemon runs in signal mode (no upload measurement; when the internet is lost the strongest stored network that delivers internet wins). `LOG_TARGET` set to `both` or `remote` without `SITE_URL` is downgraded to `local` with a warning in the log, and `REPORT_WIFI=yes` without `SITE_URL` sends nothing. `PROBE_URL` alone enables the upload measurement and nothing else. The local log is `/var/log/awacs.log`, one line per event in the form `[LEVEL][dd/mm HH:MM:SS] message`, English only; any tool that tails a file can consume it.
