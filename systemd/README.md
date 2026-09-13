# systemd/awacs.service

The daemon was born as one line in `/etc/rc.local`:

```sh
( while :; do /usr/local/bin/awacs.sh; sleep 10; done ) >/dev/null 2>&1 &
```

`awacs.service` is that line as a unit. `install.sh --service systemd` writes it and a
drop-in `awacs.service.d/10-device-id.conf` holding `Environment=DEVICE_ID=<id>`.
Use one method or the other, never both: a second copy loses the daemon's lock and exits
every 10 seconds for nothing.

## What the unit preserves

- **The respawn.** `Restart=always` + `RestartSec=10` is the loop. `awacs.sh` exits 0 on
  purpose in two cases and expects to be started again: when it loses the single-instance
  lock, and when a NetworkManager image that lacked `nmcli` has just had it installed
  ("restarting as a full NetworkManager supervisor"). `StartLimitIntervalSec=0` keeps
  systemd from giving up after a burst of such exits — the rc.local loop never gave up.
- **The environment.** `DEVICE_ID` is read from the environment first, then
  `/tmp/device_id`, then falls back to the short hostname, then to `device`. The drop-in is the environment here.
- **The shutdown.** On `systemctl stop`, SIGTERM reaches the daemon and its helper
  processes. `awacs.sh` traps it (and ignores the second TERM systemd sends to the group a moment
  later), re-enables every stored network (`enable_all`), prints its GRACEFUL SHUTDOWN
  box into the journal and exits 0. `TimeoutStopSec=40` leaves room for the `nmcli -w 5` that runs inside that handler.

## Ordering: early, and not behind network-online

The daemon's job is to make the network work, so it must not wait for
`network-online.target`. It starts after `network-pre.target` and, when they exist, after
`NetworkManager.service` and `dhcpcd.service` (a missing unit in `After=` is ignored).
Inside, `awacs.sh` waits up to about 60 seconds for NetworkManager to become active before
it decides the backend, and opens its first fight at once if the box boots without
internet.

Logging is file-only by design: `/var/log/awacs.log`. `journalctl -u awacs` shows only
start and stop events.

## Ordering against a camera stack (or any consumer of the link)

`awacs.sh` lives on the SD card and works with no internet; a camera stack that is fetched
from a site does not. Order the consumer after the daemon:

```ini
# /etc/systemd/system/camera.service  (example consumer)
[Unit]
After=awacs.service
Wants=awacs.service
```

"After" means *started after*, not *online after*: `awacs.service` is `Type=simple`, so the
consumer must still wait for connectivity itself (the daemon may be mid-fight). If the
consumer runs from `/etc/rc.local` while AWACS is a unit, a drop-in keeps the order strict:

```sh
sudo systemctl edit rc-local.service
# add:
[Unit]
After=awacs.service
```

## Checking

```sh
systemctl status awacs            # active (running) + the daemon pid
sudo awacs.sh status              # the daemon's own view: backend, network, internet
sudo tail -f /var/log/awacs.log
```
