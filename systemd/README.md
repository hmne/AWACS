# systemd/awacs.service

The unit reproduces the `rc.local` launch line:

```sh
( while :; do /usr/local/bin/awacs.sh; sleep 10; done ) >/dev/null 2>&1 &
```

`install.sh --service systemd` writes the unit and a drop-in `awacs.service.d/10-device-id.conf` holding `Environment=DEVICE_ID=<id>`. Use one launch method or the other, never both: a second copy loses the daemon's single-instance lock and exits every 10 seconds.

## What the unit preserves

### The respawn

`Restart=always` with `RestartSec=10` is the loop. `awacs.sh` exits 0 on purpose in two cases and expects to be started again: when it loses the single-instance lock, and when a NetworkManager image that lacked `nmcli` has just had it installed (`nmcli is now installed - restarting as a full NetworkManager supervisor`). `StartLimitIntervalSec=0` keeps systemd from giving up after a burst of such exits, as the `rc.local` loop does not give up.

### The environment

`DEVICE_ID` is read from the environment first, then from `/tmp/device_id`, then falls back to the short hostname, then to `device`. The drop-in is the environment here. The `Environment=DEVICE_ID=device1` line in the unit itself is the example the drop-in overrides; edit the drop-in, not the unit.

### The shutdown

On `systemctl stop`, SIGTERM reaches the daemon and its helper processes. `awacs.sh` traps it, ignores the second TERM systemd sends to the group a moment later, re-enables every stored network (`enable_all`), prints its shutdown box into the journal and exits 0. A temporary network entry in use at that moment is removed by the next daemon start. `TimeoutStopSec=40` leaves room for the `nmcli -w 5` inside that handler.

## Ordering: early, not behind network-online

The daemon's job is to make the network work, so it must not wait for `network-online.target`. It starts after `network-pre.target` and, when they exist, after `NetworkManager.service` and `dhcpcd.service` (a missing unit in `After=` is ignored). Inside, `awacs.sh` waits up to about 60 seconds for NetworkManager to become active before it decides the backend, and starts recovery at once if the device boots without internet.

Logging is file-only: `/var/log/awacs.log`. `journalctl -u awacs` shows only start and stop events.

## Ordering a consumer of the link

`awacs.sh` lives on the SD card and works with no internet. Any service that needs the network (an uploader, a service fetched at boot) should be ordered after the daemon:

```ini
# /etc/systemd/system/consumer.service  (example consumer)
[Unit]
After=awacs.service
Wants=awacs.service
```

`After` means started after, not online after: `awacs.service` is `Type=simple`, so the consumer must still wait for connectivity itself; the daemon may be in the middle of a recovery. If the consumer runs from `/etc/rc.local` while AWACS is a unit, a drop-in keeps the order:

```sh
sudo systemctl edit rc-local.service
# add:
[Unit]
After=awacs.service
```

## Checking

```sh
systemctl status awacs            # active (running) and the daemon pid
sudo awacs.sh status              # the daemon's own view: backend, network, internet
sudo tail -f /var/log/awacs.log
```
