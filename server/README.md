# server/ - a receiver you can host yourself

`awacs.sh` reports to `${SITE_URL}/${DEVICE_ID}/${SITE_API}`; `SITE_API` defaults to `receiver.php`, the file shipped here. If you have no site, one of these two files is enough. Both speak the same contract:

| Request | Answer | Effect |
| --- | --- | --- |
| `POST file=log/log.txt&data=<line>` | `200 OK` | appends the line |
| `POST file=tmp/wifi.tmp&data=<cell>` | `200 OK` | overwrites the WiFi cell atomically |
| `POST` with no `file` field (the reachability check, the upload probe) | `400 Error: no operation` | nothing written |
| `POST file=<anything else>` | `403 Error: forbidden file` | nothing written |
| `POST` with a `data` field above 64 KB | `400 Error: too large` | nothing written |
| `GET` on the endpoint path | `400 Error: no operation` | nothing written |
| a path not shaped `/<device-id>/receiver.php` (receiver.py; receiver.php in router mode) | `404 Error: not found` | nothing written |

`log/log.txt` is trimmed once it passes 512 KB: the newest 256 KB are kept and the oldest lines are dropped. receiver.py also answers `413 Error: too large` to a request body above 8 MB.

The endpoint has no authentication: anyone who can reach the URL can write those two files. Keep it on a LAN, behind a VPN, or behind a reverse proxy that adds authentication. See [SECURITY.md](../SECURITY.md).

## receiver.py (python3, standard library)

```sh
python3 server/receiver.py --port 8080 --data /srv/awacs-data
```

On the device, `SITE_URL="http://<host>:8080"`; the files land in `/srv/awacs-data/<DEVICE_ID>/`. Flags: `--host`, `--port`, `--data`, `--quiet`.

## receiver.php (PHP 7.4 or later)

```sh
php -S 0.0.0.0:8080 server/receiver.php
```

In this router mode the script answers `/<DEVICE_ID>/receiver.php` for any device id, that name only, and keeps the data in `server/data/<DEVICE_ID>/`. Under Apache or nginx, copy the file to `<docroot>/<DEVICE_ID>/receiver.php`, or to the name set in `SITE_API`; the data lands beside it (`<DEVICE_ID>/log/log.txt`, `<DEVICE_ID>/tmp/wifi.tmp`), and the web server user needs write access to that folder. `SITE_URL` is then the docroot URL. The built-in server started with a document root (`php -S 0.0.0.0:8080 -t <docroot>`) behaves the same way.

Check from any machine; `400` is the expected answer:

```sh
curl -s -o /dev/null -w '%{http_code}\n' --data-urlencode probe=1 http://<host>:8080/mydevice/receiver.php
```
