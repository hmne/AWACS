# server/ — a receiver you can host yourself

`awacs.sh` reports to `SITE_URL/DEVICE_ID/device_api.php`. If you have no site, one of
these two files is enough. Both speak the same contract:

| request | answer | effect |
|---|---|---|
| `POST file=log/log.txt&data=<line>` | `200 OK` | appends the line; the file stays under 256 KB |
| `POST file=tmp/wifi.tmp&data=<cell>` | `200 OK` | overwrites the WiFi cell atomically |
| `POST` with no `file` field (the reachability check, the upload probe) | `400 Error: no operation` | nothing written |
| `POST file=<anything else>` | `403 Error: forbidden file` | nothing written |

**No authentication.** Anyone who can reach the URL can write those two files. Keep it on a
LAN, behind a VPN, or behind a reverse proxy that adds auth. See `SECURITY.md`.

## receiver.py (python3, standard library)

```sh
python3 server/receiver.py --port 8080 --data /srv/awacs-data
# device side:  SITE_URL="http://<host>:8080"   -> files in /srv/awacs-data/<DEVICE_ID>/...
```

## receiver.php (PHP 7.4+)

```sh
php -S 0.0.0.0:8080 server/receiver.php          # router mode: data in server/data/<DEVICE_ID>/
```

Apache or nginx: copy the file to `<docroot>/<DEVICE_ID>/device_api.php`. The data lands
beside it (`<DEVICE_ID>/log/log.txt`, `<DEVICE_ID>/tmp/wifi.tmp`); the web server user needs
write access to that folder. `SITE_URL` is the docroot URL.

Check from any machine — `400` is the expected answer:

```sh
curl -s -o /dev/null -w '%{http_code}\n' --data-urlencode probe=1 http://<host>:8080/cam1/device_api.php
```
