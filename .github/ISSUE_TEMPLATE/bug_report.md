---
name: Bug report
about: Something awacs.sh or install.sh did wrong
labels: bug
---

## Environment

- Board and OS (`cat /etc/os-release | head -2`):
- Network backend shown by `sudo awacs.sh status` (NetworkManager, or dhcpcd + wpa_supplicant):
- awacs.sh version (`head -3 /usr/local/bin/awacs.sh`):
- Boot method: systemd unit or rc.local line:

## What happened

## What you expected

## Steps to reproduce

1.
2.

## Log lines

`sudo tail -n 100 /var/log/awacs.log` - remove network names you do not want public.

```text

```

## Settings

`sudo grep -v SAFETY_NET /etc/awacs.conf` - never paste passwords.

```text

```
