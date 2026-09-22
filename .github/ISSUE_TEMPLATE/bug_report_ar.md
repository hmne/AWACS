---
name: بلاغ عن خطأ
about: سلوك خاطئ من awacs.sh أو install.sh
labels: bug
---

## البيئة

- اللوحة ونظام التشغيل (`cat /etc/os-release | head -2`):
- نظام الشبكة الذي يعرضه `sudo awacs.sh status` (NetworkManager أو dhcpcd + wpa_supplicant):
- إصدار awacs.sh (`head -3 /usr/local/bin/awacs.sh`):
- طريقة الإقلاع: وحدة systemd أو سطر في rc.local:

## ماذا حدث

## ما كنت تتوقعه

## خطوات إعادة الحالة

1.
2.

## سطور اللوق

`sudo tail -n 100 /var/log/awacs.log` - احذف أسماء الشبكات التي لا تريد نشرها.

```text

```

## الإعدادات

`sudo grep -v SAFETY_NET /etc/awacs.conf` - لا تنسخ كلمات السر أبداً.

```text

```
