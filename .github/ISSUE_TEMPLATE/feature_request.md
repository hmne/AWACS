---
name: Feature request / طلب ميزة
about: A behaviour you want AWACS to have / سلوك تريد أن يقوم به AWACS
labels: enhancement
---

## The situation / الحالة

What happens on your device today, and why it is a problem.
ما الذي يحدث على جهازك اليوم، ولماذا هو مشكلة.

## The wanted behaviour / السلوك المطلوب

One paragraph. Say which backend it concerns (NetworkManager, dhcpcd + wpa_supplicant, both).
فقرة واحدة. اذكر أي نظام شبكة تعنيه (NetworkManager أو dhcpcd + wpa_supplicant أو كلاهما).

## Rules it must keep / القواعد التي يجب ألا تُخالَف

AWACS never writes `wpa_supplicant.conf` or a NetworkManager profile, never disables a stored
network, and never reboots for an outage that is not its own. Say how the request fits.
لا يكتب AWACS في wpa_supplicant.conf ولا في ملفات NetworkManager، ولا يعطّل شبكة مخزنة، ولا يعيد
التشغيل لانقطاع ليس من جهته. اذكر كيف ينسجم الطلب مع ذلك.

## Alternatives you considered / بدائل فكرت فيها
