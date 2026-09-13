---
name: Bug report / بلاغ عن خطأ
about: Something awacs.sh or install.sh did wrong / سلوك خاطئ من awacs.sh أو install.sh
labels: bug
---

## Environment / البيئة

- Board and OS (`cat /etc/os-release | head -2`):
- Network backend shown by `sudo awacs.sh status` (NetworkManager, or dhcpcd + wpa_supplicant):
- awacs.sh version (`head -3 /usr/local/bin/awacs.sh`):
- Boot method: systemd unit or rc.local line:

## What happened / ماذا حدث

## What you expected / ما كنت تتوقعه

## Steps to reproduce / خطوات إعادة الحالة

1.
2.

## Log lines / سطور اللوق

`sudo tail -n 100 /var/log/awacs.log` — remove network names you do not want public.
احذف أسماء الشبكات التي لا تريد نشرها.

```text

```

## Settings / الإعدادات

`sudo grep -v SAFETY_NET /etc/awacs.conf` — never paste passwords.
لا تنسخ كلمات السر أبداً.

```text

```
