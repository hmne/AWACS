<div dir="rtl">

# أواكس (AWACS)

[![ShellCheck](https://github.com/hmne/AWACS/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/hmne/AWACS/actions/workflows/shellcheck.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

أواكس (Advanced WiFi Auto Connection System) سكربت bash واحد يعمل كخدمة دائمة، يُبقي جهاز لينكس بلا شاشة متصلاً بالإنترنت عبر الواي فاي. يفحص الاتصال كل عشر ثوانٍ، وعندما ينقطع الإنترنت يجرّب الشبكات المخزنة ثم قائمة الطوارئ ثم الشبكات المفتوحة حتى تعمل إحداها. ولا يعدّل ملفات الشبكة الخاصة بالنظام أبداً.

[English](README.md) · [التوثيق](docs/ar/) · [سجل التغييرات](CHANGELOG.md)

## لمن هو؟

لجهاز لا يجلس أحد أمامه: كاميرا على Raspberry Pi، صندوق حساسات، شاشة عرض، أو أي جهاز شبيه بـ Debian يجب أن يبقى قابلاً للوصول عبر الواي فاي. إذا فقد الجهاز الإنترنت في الثالثة فجراً، فأواكس هو من يعيده.

## نظامان، سكربت واحد

يكتشف أواكس نظام الشبكة عند التشغيل (`detect_backend`) ويتعامل معه عبر أداته الخاصة فقط:

| الصورة | النظام | الأداة | الدور |
| --- | --- | --- | --- |
| Raspberry Pi OS القديم (dhcpcd + wpa_supplicant) | `wpa` | `wpa_cli` | أواكس هو عقل الواي فاي |
| صور NetworkManager (الافتراضي في Bookworm ومعظم أنظمة Debian) | `nm` | `nmcli` | أواكس يشرف على NetworkManager: ينتظر محاولاته ولا يتدخل إلا بعد أن يثبت فشله |

إذا كان NetworkManager مفعّلاً أو يعمل فالصورة صورة NM. وإذا كان `nmcli` ناقصاً أو الكرت خارج إدارة NM، يعمل أواكس في وضع المراقبة فقط ويقول ذلك في اللوق.

## الأفكار الأساسية

- **القتال حتى الاتصال.** ثلاث دورات بلا إنترنت تبدأ القتال: إعادة الارتباط، ثم كل شبكة مخزنة ظاهرة، ثم سلّم إنعاش من ثلاث درجات (الراديو، خدمة الشبكة، تعريف الواي فاي)، ثم شبكات الطوارئ، ثم الشبكات المفتوحة.
- **سرعة الرفع تقرر، لا قوة الإشارة.** حين تعمل عدة شبكات، يرفع أواكس 200 كيلوبايت عبر كل واحدة ويبقي الأسرع (`best_by_upload`). ولا يبدّل إلا إذا تفوّقت المنافِسة على الحالية بنسبة قابلة للضبط. وبلا هدف للقياس يعود إلى ترتيب الإشارة.
- **قانون لا-بلوك.** لا `save_config`، لا `disable_network`، لا `nmcli connection modify`. الشبكات الوحيدة التي يحذفها أواكس هي المؤقتة التي أنشأها في هذا الإقلاع. وفي كل بداية قتال ونهايته وعند الإيقاف يُعيد تفعيل كل الشبكات المخزنة.
- **صمّام الريبوت لعطل الجهاز نفسه فقط.** الريبوت يحتاج شبكة معروفة ظاهرة لا يستطيع الجهاز ركوبها، وراوتر لا يرد، ولا علامة كلمة سر خاطئة، واستمرار الحالة `REBOOT_AFTER_MIN` دقيقة. كلمة السر الخاطئة وانقطاع مزوّد الإنترنت لا يعيدان تشغيل الجهاز أبداً.
- **الصبر على الانقطاع الخارجي.** إذا رد الراوتر فالمشكلة عند المزوّد. يسجّل أواكس `outage looks external — waiting, not rebooting` وينتظر.
- **الملاجئ الأخيرة.** شبكات `SAFETY_NET` (هوتسبوت هاتفك بكلمة سر) تُجرَّب قبل أي شبكة مفتوحة غريبة. كلتاهما مدخلات مؤقتة تُحذف لحظة عودة شبكة حقيقية.
- **وضع النهار والليل.** بين `NIGHT_START` و`NIGHT_END` يتساهل مع الروابط الأبطأ ويبدّل أقل.
- **يثبّت أدواته بنفسه.** الأداة الناقصة (`iw` أو `nmcli` أو `rfkill` وغيرها) تُذكر في اللوق ثم تُثبَّت مرة واحدة كل إقلاع بأسماء حزم Debian الصحيحة، في الخلفية، بعد أول لحظة صحة مؤكدة.
- **القصة المخزونة (spool).** مع موقع للتقارير، يُسجَّل كل حدث محلياً ويُرسَل للموقع. الأسطر التي لا تُرسَل أثناء الانقطاع تُخزَّن وتصل بالترتيب بعد التعافي، والسطر الأول مثبَّت كي يبقى وقت بداية الانقطاع.

## التثبيت السريع

المعالج (اللغة، الأدوات الناقصة، معرّف الجهاز، وجهة اللوق والموقع، شبكات الطوارئ، طريقة الإقلاع):

</div>

```sh
curl -fsSL https://raw.githubusercontent.com/hmne/AWACS/main/install.sh | sudo bash
# بلا أسئلة: ... | sudo bash -s -- --yes --device-id cam1 --log local
```

<div dir="rtl">

يدوياً:

</div>

```sh
sudo install -m 755 awacs.sh /usr/local/bin/awacs.sh
sudo install -m 600 -o root -g root awacs.conf.example /etc/awacs.conf
sudo nano /etc/awacs.conf           # شبكات الطوارئ، رابط الموقع، وأي شيء آخر تريد تغييره
```

<div dir="rtl">

ثم شغّله من systemd أو من `rc.local` مع `DEVICE_ID` في البيئة:

</div>

```sh
# /etc/rc.local — قبل أي شيء يحتاج الشبكة
export DEVICE_ID="cam1"
( while :; do /usr/local/bin/awacs.sh; sleep 10; done ) >/dev/null 2>&1 &
```

<div dir="rtl">

وحدة systemd هي `systemd/awacs.service` (`Restart=always` هو الحلقة). تحقّق بـ `sudo awacs.sh status`. الترقية والإزالة وخيارات التشغيل بلا أسئلة في [docs/ar/install.md](docs/ar/install.md).

## صندوق الأدوات

الملف نفسه صندوق أدوات. هذه الكلمات تعمل بجانب الخدمة، وكلها للقراءة فقط عدا `speed`:

</div>

```text
sudo awacs.sh status     # حالة الشبكة والحارس الآن
sudo awacs.sh networks   # الشبكات المخزنة والمرئية
sudo awacs.sh evaluate   # جدول مرتب: CUR ID PRIO SIGNAL SEC SSID
sudo awacs.sh scan       # مسح خام، مخبّأ 30 ثانية
sudo awacs.sh speed      # قياس رفع حقيقي واحد إلى الموقع
awacs.sh check           # "internet: OK" برمز 0 / "internet: DOWN" برمز 1 — بلا root
awacs.sh help
```

<div dir="rtl">

`status` على جهاز متصل:

</div>

```text
  device      cam1 on wlan0
  backend     wpa / نظام إدارة الشبكة
  daemon    ✓ running (pid 637) / الحارس يعمل
  network     HomeNet
  signal      -20 dBm / قوة الإشارة
  ip          10.10.1.18/24
  gateway   ✓ reachable / الراوتر يرد
  internet  ✓ ONLINE / متصل
  viewer      none / لا مشاهد
  upload      0 kbps flowing (3s kernel sample)
```

<div dir="rtl">

`evaluate`:

</div>

```text
CUR  ID       PRIO  SIGNAL   SEC   SSID
              -     -20      open  FreeCafe
*    0        10    -20      sec   HomeNet
     1        5     -27      sec   شبكة البيت
```

<div dir="rtl">

الأسماء العربية وغير اللاتينية تُفكّ للعرض وتُطابَق داخلياً بايتاً بايتاً.

## الضبط

ملف واحد: `/etc/awacs.conf`، ملكه root، صلاحياته `0600`، وسطوره من شكل `KEY=value` فقط. يرفض السكربت ملفاً بمالك أو صلاحيات مختلفة ويطبع السبب. كل رقم يُفحص، والقيمة الخاطئة تسقط إلى الافتراضي بدل أن تُسقط الخدمة. كل المفاتيح مع قيمها الافتراضية في [awacs.conf.example](awacs.conf.example) وشرحها في [docs/ar/configuration.md](docs/ar/configuration.md).

مفاتيح النسخة العامة:

</div>

```text
SITE_URL=""          # رابط موقع التقارير؛ فارغ = عمل محلي فقط
LOG_TARGET="local"   # local | both | remote
PROBE_URL=""         # هدف قياس الرفع؛ افتراضياً الموقع حين يكون SITE_URL مضبوطاً
REPORT_WIFI="auto"   # نشر خانة الواي فاي للموقع؛ auto = مفعّل حين يكون SITE_URL مضبوطاً
SITE_TZ=""           # المنطقة الزمنية لختم أسطر الموقع، مثل Europe/Berlin؛ الفارغ = منطقة الجهاز
```

<div dir="rtl">

`DEVICE_ID` يأتي من البيئة (سطر `export` في `rc.local` أو `Environment=` في systemd). اللوق في `/var/log/awacs.log` ويُدوَّر عند `LOG_CAP` سطراً. حالة التشغيل في `/run/awacs`، لـ root فقط، وتزول مع الريبوت.

## التوثيق

| الصفحة | المحتوى |
| --- | --- |
| [features.md](docs/ar/features.md) | كل قدرة، والدالة التي تنفّذها، ولماذا |
| [how-it-works.md](docs/ar/how-it-works.md) | الحلقة الرئيسية، سلّم القتال، تصنيف «عندي أم خارجي»، صمّام الريبوت، التنحّي لـ NM، المخزون، مصادر المسح |
| [configuration.md](docs/ar/configuration.md) | كل مفتاح: الافتراضي والوحدة والأثر والمدى الآمن؛ قواعد أمان الملف؛ أشكال النشر |
| [scenarios.md](docs/ar/scenarios.md) | ما يفعله wpa_supplicant أو NetworkManager وحده مقابل ما يفعله أواكس، بسطور لوق حقيقية |
| [install.md](docs/ar/install.md) | المعالج، التثبيت اليدوي، systemd مقابل rc.local، الترقية، الإزالة |
| [troubleshooting.md](docs/ar/troubleshooting.md) | علامات الفشل في اللوق ومعنى كل منها |
| [faq.md](docs/ar/faq.md) | أجوبة قصيرة |
| [integration.md](docs/ar/integration.md) | عقد device_api، المستقبِل المرفق، خانة الموقع |
| [testing.md](docs/ar/testing.md) | مختبر QEMU/hwsim وكيف تعيد تشغيله |

## محتوى المستودع

| المسار | المحتوى |
| --- | --- |
| `awacs.sh` | الحارس وصندوق الأدوات، ملف واحد |
| `awacs.conf.example` | كل مفتاح مع قيمته الافتراضية، معلَّقاً |
| `install.sh` | معالج الإعداد: تثبيت، تحديث، إزالة؛ `--yes` للتشغيل بلا أسئلة |
| `systemd/` | `awacs.service` وملاحظاته |
| `server/` | مستقبِلان ذاتيا الاستضافة لعقد device_api، بـ PHP وPython |
| `tools/` | `awacs-tui.sh` لوحة طرفية للقراءة فقط؛ `gen-config-table.sh` جدول مفاتيح يُولَّد من الكود |
| `docs/en/`، `docs/ar/` | التوثيق، نفس الصفحات باللغتَين |
| `lab/` | مختبر QEMU/hwsim: وحدة التحكم، ملفات الضيف، السيناريوهات |

## الحالة

النسخة 1.0. جُرِّب على wpa_supplicant وdhcpcd وNetworkManager وhostapd حقيقية في مختبر QEMU بكروت واي فاي افتراضية: 24 تشغيل سيناريو على صورتَين، وملفات الشبكة مطابقة بالبايت قبل كل تشغيل وبعده. التفاصيل في [docs/ar/testing.md](docs/ar/testing.md). المختبر جهاز لينكس افتراضي لا Raspberry Pi؛ صفحة الاختبار تذكر ما لم يُتحقَّق منه.

## المتطلبات

bash 4 أو أحدث، و`iw` و`ip` و`ping` و`curl` و`awk` و`sed` و`grep` و`pgrep` و`rfkill` و`flock` و`timeout` و`stat` و`date` و`modprobe`، و`wpa_cli` أو `nmcli`. كلها موجودة أصلاً في Raspberry Pi OS وDebian. أما `iwlist` و`wget` فبديلان اختياريان.

## الرخصة

MIT. انظر [LICENSE](LICENSE).

</div>
