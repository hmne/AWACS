# Integration

AWACS talks to one endpoint: `${SITE_URL}/${DEVICE_ID}/device_api.php`. Anything that speaks the contract below can receive its story: the receivers shipped in `server/`, a full dashboard, or your own code.

## The device_api contract

Transport: HTTP POST, `application/x-www-form-urlencoded`, plain-text reply. No authentication in the contract; see [SECURITY.md](../../SECURITY.md).

| Request | Reply | Meaning |
| --- | --- | --- |
| `file=<relative path>` and `data=<text>` | `200`, body `OK\n` | Write `data` to the file. Paths in an append list are appended (one line per call); other paths are overwritten atomically. |
| `file=` with a path not on the whitelist | `403` | Refused. |
| any POST with no recognised operation (e.g. `probe=1`, or a raw body) | `400`, body `Error: no operation\n` | The signature reply. AWACS uses this exact code as the last rung of its internet check and as the upload probe's landing. |

Files AWACS sends:

| Path | Mode | Content | Cadence |
| --- | --- | --- | --- |
| `log/log.txt` | append | one line per event: `[LEVEL] AWACS: <message>, dd/mm/yyyy hh:mm:ss AM/PM.` — Arabic surface when the event has one, English otherwise | per event; spooled lines arrive in order after an outage |
| `tmp/wifi.tmp` | overwrite | `kbps,visible,total,band,SSID` | every ~60 s while online, when `REPORT_WIFI` is on |
| (probe) | — | `PROBE_KB` KB of zeros as a raw POST body | at decision moments only |

Levels: `INFO`, `OK`, `WARN`, `ERROR`. The timestamp on site lines uses `SITE_TZ` when it is set (an IANA zone name), otherwise the device's own zone. `DEBUG` lines never leave the device.

`tmp/wifi.tmp` fields: measured upload in kbps (`0` when no measurement exists for the current network), number of stored networks currently visible, number of stored networks, band (`2.4GHz`, `5GHz`, `6GHz` or empty), and the SSID last so its own commas survive a 5-field split. Example: `4260,2,2,2.4GHz,HomeNet`.

How the script uses the endpoint:

```sh
# a log line
curl -sf --max-time 4 --data-urlencode "file=log/log.txt" --data-urlencode "data=$line" "$SITE/device_api.php"
# the WiFi cell
curl -sf --max-time 4 --data-urlencode "file=tmp/wifi.tmp" --data-urlencode "data=4260,2,2,2.4GHz,HomeNet" "$SITE/device_api.php"
# the internet rung: must answer 400
curl -s -o /dev/null -w '%{http_code}' --max-time 3 --data-urlencode "probe=1" "$SITE/device_api.php"
# the upload probe: speed_upload is read from curl
head -c $((PROBE_KB * 1024)) /dev/zero | curl -s -o /dev/null -w '%{speed_upload}' --max-time 15 --data-binary @- "$PROBE_URL"
```

The `400` rung matters: captive portals answer 200, 302 or 511 to anything; none fabricates a 400. A receiver that answers 200 to an empty POST would make a portal splash read as "online". Keep the 400.

## The shipped receivers

`server/` holds two minimal receivers that speak the contract, no database, no dependencies: a whitelist of two paths (`log/log.txt` appended and kept under 256 KB, `tmp/wifi.tmp` overwritten atomically), `403 Error: forbidden file` for any other path, `400 Error: no operation` for a POST without `file` (and for GET).

`server/receiver.php` (PHP 7.4+), two ways to host:

```sh
# 1. behind Apache or nginx: one copy per device id, data lands beside it
#    <docroot>/cam1/device_api.php  ->  <docroot>/cam1/log/log.txt, <docroot>/cam1/tmp/wifi.tmp
# 2. PHP's built-in server as a router for every device id, data in server/data/<id>/
php -S 0.0.0.0:8080 server/receiver.php
```

`server/receiver.py` (Python 3, standard library), one process for every device id:

```sh
python3 server/receiver.py --port 8080 --data /srv/awacs-data     # files in /srv/awacs-data/<DEVICE_ID>/...
```

Then on the device:

```sh
SITE_URL="https://example.com/cams"      # or http://<host>:8080 for the built-in servers
LOG_TARGET="both"
```

Check from any machine; `400` is the expected answer:

```sh
curl -s -o /dev/null -w '%{http_code}\n' --data-urlencode probe=1 https://example.com/cams/cam1/device_api.php
```

Put the receiver behind HTTPS and restrict who can POST to it (IP allow-list, a reverse-proxy secret header, or a client certificate). The contract carries no credential of its own. `server/README.md` has the details.

## The site cell

The reference dashboard renders `tmp/wifi.tmp` as a WiFi cell beside the device's status, following the same rule its battery cell uses: fresh file, cell shown; stale or absent file, cell hidden. The reference site treats a `wifi.tmp` older than 180 s as stale (three missed heartbeats). A device without AWACS therefore renders the page unchanged.

Rendered form, from the lab:

```html
<div class="wifi-box">Wi-Fi: <bdi>HomeNet</bdi> <span class="dim">2.4GHz</span> 4.3Mb/s↑ <span class="dim">(2/2)</span></div>
```

The speed is omitted when the first field is `0`. `(2/2)` is visible/total stored networks. `<bdi>` isolates the SSID's text direction so an Arabic name sits correctly in a left-to-right page.

The log file is shown as-is, newest last; the reference site caps it server-side.

## Pointing a different dashboard at it

Two options:

1. **Keep the contract.** Implement `device_api.php` (or any handler at that URL) with the three replies above. The device needs no change. Your dashboard reads `log/log.txt` and `tmp/wifi.tmp` however it likes: tail the log, split the cell line on the first four commas, hide the cell when the file is older than a few minutes.
2. **Change only the probe target.** If you want the log on your server but the upload probe elsewhere, set `PROBE_URL` separately. Whatever answers there must accept a POST body of `PROBE_KB` KB; its status code is irrelevant to the probe (`curl` measures the transfer) but the internet rung still uses `SITE_URL`'s `400`.

Splitting the cell in PHP, for example:

```php
[$kbps, $visible, $total, $band, $ssid] = explode(',', trim($line), 5) + [0, 0, 0, '', ''];
```

## Local-only

With `SITE_URL` empty nothing above is used. The log stays in `/var/log/awacs.log`, and any tool that tails a file can consume it. The line format there is `[LEVEL][dd/mm HH:MM:SS] message`, English.
