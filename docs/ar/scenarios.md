<div dir="rtl">

# سيناريوهات

تسع حالات، كل واحدة في ثلاثة أجزاء: ما يفعله النظام الأصلي، وما يفعله أواكس مع أسطر سجله بالترتيب، ومفاتيح الضبط المعنية. الأوقات والأسماء في العيّنات للتوضيح. `HomeNet` و`OfficeNet` شبكتان مخزنتان، و`PhoneHotspot` مدخل في `SAFETY_NET`، و`FreeCafe` شبكة مفتوحة، و`mydevice` معرّف الجهاز. العيّنات تعرض النظام الخلفي `wpa`؛ وعلى `nm` تكون أسطر الدرجات `recover L1: radio bounce` و`recover L2: re-kick NetworkManager on wlan0` و`recover L3: restart NetworkManager + reload WiFi firmware`. تُحذَف من العيّنات الأسطر المتكررة: محاولات الطوارئ والمفتوحة تتبع كل درجة، وسطر الأدلة بمستوى DEBUG يُسجَّل في كل جولة فيها أدلة على الجهاز.

## 1. كلمة سر خاطئة على الشبكة الوحيدة المتاحة

### سلوك النظام الأصلي

`wpa_supplicant` يفشل في المصافحة، ويعلّم الشبكة `TEMP-DISABLED` لفترة تتزايد، ويعيد المحاولة بمؤقّته. NetworkManager يعيد محاولة ملف التعريف مرات قليلة ويترك الجهاز غير متصل. ولا واحد منهما يجرّب شبكة أخرى، وسكربت المراقبة الذي يعيد التشغيل عند فقد الإنترنت يعيد التشغيل بلا نهاية.

### سلوك أواكس

العلامات تشبه عطلاً في الجهاز (الشبكة ظاهرة، لا يمكن الانضمام إليها، لا موجّه)، لكن علامة كلمة السر حاضرة، فيُعاد مؤقّت إعادة التشغيل إلى الصفر في كل جولة. السلّم يعمل مع ذلك، لأن عطلاً قد يتزامن مع كلمة سر قديمة، وتتبع شبكات الطوارئ والمفتوحة كل درجة. ومع وضع كلمة السر الصحيحة ينجح الإنعاش التالي.

</div>

```text
[WARN][01/01 10:00:30] internet lost on wlan0 - engaging
[ERROR][01/01 10:01:20] association refused - wrong password? (recovery continues, reboot stays off)
[WARN][01/01 10:01:21] recover L1: radio bounce
[INFO][01/01 10:01:30] trying emergency networks (1 listed)
[INFO][01/01 10:02:05] trying open networks as last resort
[ERROR][01/01 10:03:10] association refused - wrong password? (recovery continues, reboot stays off)
[WARN][01/01 10:03:12] recover L2: restart dhcpcd (respawns the REAL per-interface supplicant)
[WARN][01/01 10:05:30] recover L3: reload brcmfmac firmware (the 3-second cure a wedge needs)
[OK][01/01 10:06:05] internet restored: HomeNet
```

<div dir="rtl">

على `nm` تأتي علامة كلمة السر من نص خطأ التفعيل وتبقى طوال الإنعاش.

### مفاتيح الضبط المعنية

`NET_FAIL_TICKS` و`ASSOC_WAIT` و`SAFETY_NET` و`OPEN_NETWORKS`. ولا دور لـ `REBOOT_AFTER_MIN` ما دامت علامة كلمة السر مرئية.

## 2. نقطة البيت تسقط ثم تعود

### سلوك النظام الأصلي

حين يسقط الرابط الحالي يختار `wpa_supplicant` شبكة مفعّلة أخرى من ضبطه ويفعّل NetworkManager ملف تعريف آخر يعمل تلقائياً. ولا واحد منهما يعود إلى الشبكة الأعلى أولوية ما دام الرابط الحالي صامداً، ولا واحد منهما يقيس السرعة.

### سلوك أواكس

إن انتقلت الطبقة الأساسية خلال `NET_FAIL_TICKS` دورة لا يُسجَّل شيء. وإلا يبدأ الإنعاش؛ وقد يجد افتتاحه الهادئ الجهاز قد انتقل، فلا يتبع ذلك إلا `internet restored`. وإن لم يكن، تُفعَّل كل شبكة مخزنة ظاهرة وتُقاس وتُبقى الأفضل. بعد ذلك، كل `PREF_CHECK` ثانية، يبحث الحارس عن شبكة مخزنة ظاهرة بأولوية أعلى تماماً؛ ورؤيتان متتاليتان تعيدان الجهاز إلى البيت مع قياس الرفع عند الوصول.

</div>

```text
[WARN][01/01 12:00:30] internet lost on wlan0 - engaging
[INFO][01/01 12:01:10] candidate [1] OfficeNet uploads at 1484 kbps
[OK][01/01 12:01:12] connected: OfficeNet (upload 1484 kbps)
[OK][01/01 12:01:12] internet restored: OfficeNet
[INFO][01/01 12:21:30] higher-priority network visible - trying to go home
[OK][01/01 12:21:50] returned to preferred network: HomeNet (upload 7445 kbps)
```

<div dir="rtl">

لو قيست `HomeNet` تحت الحد عند الوصول لكان السطر `preferred network too slow (N kbps) - benching it, going back`، وتُترَك `HomeNet` ثلاث فترات تبريد.

### مفاتيح الضبط المعنية

`PREF_CHECK`، و`MIN_UP_KBPS` و`NIGHT_MIN_UP_KBPS`، و`DANCE_COOLDOWN` (يدوم الاستبعاد ثلاث فترات منه)، و`PROBE_KB`، والأولويات في ضبط الشبكات (`priority=` على `wpa`، و`connection.autoconnect-priority` على `nm`)؛ والرجوع يحتاج أولوية للبيت أعلى تماماً من الحالية.

## 3. كل الشبكات المخزنة غائبة

### سلوك النظام الأصلي

لا شيء. النظامان لا يعرفان إلا الشبكات المخزنة.

### سلوك أواكس

لا شبكة مخزنة في الهواء، وشبكات أخرى موجودة، والموجّه صامت: لا تنطبق أي من علامات الجهاز الثلاث، فتُصنَّف الجولة خارجية ولا تعمل أي درجة. تُجرَّب مدخلات `SAFETY_NET` سواء أظهرها المسح أم لا، ثم الشبكات المفتوحة. الشبكة المنضَم إليها مدخل مؤقت بأولوية 0. وحين تعود شبكة مخزنة بأولوية أعلى يعيد فحص الشبكة المفضلة الجهاز إلى البيت ويُحذَف المدخل في الدورة الصحيحة التالية؛ فلا يبقى ملف تعريف `awacs-*` على `nm` ولا معرّف شبكة زائد في `supplicant` الحي على `wpa`.

</div>

```text
[WARN][01/01 14:00:30] internet lost on wlan0 - engaging
[INFO][01/01 14:01:55] outage looks external (round 1) — waiting, not rebooting
[INFO][01/01 14:02:02] trying emergency networks (1 listed)
[INFO][01/01 14:02:38] trying open networks as last resort
[OK][01/01 14:03:10] connected to OPEN network: FreeCafe
[OK][01/01 14:03:11] internet restored: FreeCafe
[INFO][01/01 14:42:30] higher-priority network visible - trying to go home
[OK][01/01 14:43:08] returned to preferred network: HomeNet (upload 2302 kbps)
```

<div dir="rtl">

هنا كانت نقطة الاتصال مطفأة؛ ولو كانت تعمل لكان السطران `connected to EMERGENCY network: PhoneHotspot` و`internet restored: PhoneHotspot`، ولا تُجرَّب أي شبكة مفتوحة.

### مفاتيح الضبط المعنية

`SAFETY_NET` و`OPEN_NETWORKS` و`PREF_CHECK`، وأولوية فوق 0 على الشبكات المخزنة.

## 4. انقطاع المزوّد والموجّه يرد

### سلوك النظام الأصلي

النظامان يريان ارتباطاً وعنواناً ولا يفعلان شيئاً. وسكربت المراقبة الذي يعيد التشغيل عند فقد الإنترنت يعيد التشغيل كل بضع دقائق طوال الانقطاع.

### سلوك أواكس

يُعلَن الفقد هنا متأخراً عنه على وصلة ميتة: البوابة ما زالت ترد، فيجري فحص صبور واحد قبل أن يُحسب الفحص السريع الثالث الفاشل، ويبدأ الإنعاش بعد نحو 72 إلى 83 ثانية من الفقد بدل 40 إلى 63. والإنعاش الأول يُبقي الارتباط القائم: تُتخطى إعادة الارتباط، وتُستثنى الشبكة التي عليها الجهاز من المرشحين، وتنتهي المحاولات الفاشلة بالعودة إليها. بعد تفعيل كل شبكة مخزنة ظاهرة وتبيّن أنها بلا إنترنت ينجح `ping` الموجّه، فالانقطاع خارجي: لا درجة، ويبقى مؤقّت إعادة التشغيل صفراً. تجرّب كل جولة مع ذلك شبكات الطوارئ والمفتوحة، لأن شبكة أخرى قد يكون لها مزوّد آخر، ثم تنتظر 20 ثانية؛ للإنعاش ثلاث جولات ويبدأ إنعاش جديد كل دورة ما دام الانقطاع. أسطر الموقع تُخزَّن في الأثناء وتُسلَّم بالترتيب حين يعود الرابط.

</div>

```text
[WARN][01/01 16:00:30] internet lost on wlan0 - engaging
[INFO][01/01 16:01:40] outage looks external (round 1) — waiting, not rebooting
[INFO][01/01 16:01:50] trying emergency networks (1 listed)
[INFO][01/01 16:02:25] trying open networks as last resort
[INFO][01/01 16:03:00] outage looks external (round 2) — waiting, not rebooting
[OK][01/01 16:48:10] internet restored: HomeNet
```

<div dir="rtl">

تتكرر المجموعة ذات الأسطر الثلاثة في كل جولة حتى يعود المزوّد. وعلى `nm` يأخذ الجهاز المُبلَّغ عنه متصلاً مع صمت الموجّه الفرع نفسه بالسطر `NetworkManager is connected, internet is not (round N) — router-side, no rung`.

### مفاتيح الضبط المعنية

`NET_FAIL_TICKS` و`SAFETY_NET` و`OPEN_NETWORKS` و`SPOOL_CAP` و`LOG_TARGET`.

## 5. عطل في الجهاز: راديو أصم وإعادة التشغيل

### سلوك النظام الأصلي

الراديو يتوقف عن سماع أي شيء. `wpa_supplicant` يمسح ولا يجد شيئاً إلى ما لا نهاية؛ وNetworkManager يترك الجهاز غير متصل أو غير متاح. لا شيء يعيد تحميل التعريف أو يعيد تشغيل الجهاز.

### سلوك أواكس

ثلاثة مسوح متتالية بلا شيء من أي مصدر تُسقط الصورة القديمة؛ والراديو الذي لا يسمع شيئاً علامة على الجهاز، فيبدأ مؤقّت إعادة التشغيل. يعمل السلّم L1 وL2 وL3 مع محاولات الطوارئ والمفتوحة بعد كل درجة، وتكرره الإنعاشات التالية. وحين تستمر الأدلة `REBOOT_AFTER_MIN` دقيقة بلا دورة صحيحة يُكتَب سطر إعادة التشغيل في السجل المحلي ويُعاد تشغيل الجهاز. على `nm` لا يعمل المؤقّت إلا بعد أن يستقر NetworkManager في حالة غير متصل أو فاشل في جولتين متتاليتين؛ والحالة 20 (غير متاح) لا تبدؤه أبداً.

</div>

```text
[WARN][01/01 18:00:30] internet lost on wlan0 - engaging
[WARN][01/01 18:01:05] radio heard nothing on 3 scans in a row - previous results dropped
[DEBUG][01/01 18:01:06] fight round 1: ME evidence (LINK_OK=0, gw unreachable, auth_failing=0)
[WARN][01/01 18:01:07] recover L1: radio bounce
[INFO][01/01 18:01:15] trying emergency networks (1 listed)
[INFO][01/01 18:01:50] trying open networks as last resort
[WARN][01/01 18:02:40] recover L2: restart dhcpcd (respawns the REAL per-interface supplicant)
[WARN][01/01 18:04:10] recover L3: reload brcmfmac firmware (the 3-second cure a wedge needs)
[ERROR][01/01 18:31:10] wedged 30min with networks visible — rebooting (repeats per streak until cured)
[INFO][01/01 18:33:20] AWACS 1.0 starting on wlan0 (device mydevice)
```

<div dir="rtl">

بعد إعادة التشغيل يبدأ المؤقّت من الصفر؛ والعطل الذي ينجو منها لا يستحق التالية إلا بعد نافذة كاملة أخرى.

### مفاتيح الضبط المعنية

`REBOOT_AFTER_MIN` و`NET_FAIL_TICKS` و`SCAN_TTL`.

## 6. رابط بطيء وشبكة مخزنة أسرع متاحة

### سلوك النظام الأصلي

لا شيء. الرابط المتصل رابط متصل.

### سلوك أواكس

يقرأ المقياس السلبي عدّاد الإرسال كل دورة. معدل بين 20 كيلوبت/ث والحد الأدنى في `UP_STRIKES` دورات متتالية، مع انقضاء فترة التبريد، يبدأ تقييماً بقياس رفع واحد للشبكة الحالية. القياس فوق الحد ينهيه: المقياس رأى تدفقاً صغيراً لا رابطاً بطيئاً. والقياس تحت الحد، هنا 250 كيلوبت/ث، يضع عتبة المنافِسة عند `SWITCH_GAIN_PCT` بالمئة منه، أي 375 كيلوبت/ث؛ تُفعَّل كل شبكة مخزنة ظاهرة أخرى وتُقاس، وتُبقى الأفضل فوق العتبة.

</div>

```text
[WARN][01/01 20:01:27] sustained slow upload (107 kbps) - evaluating known networks
[INFO][01/01 20:01:58] candidate [1] OfficeNet uploads at 1620 kbps
[OK][01/01 20:02:20] connected: OfficeNet (upload 1620 kbps)
```

<div dir="rtl">

وحين لا تتجاوز أي مرشحة العتبة يعود الحارس: `no challenger beat the incumbent - staying on HomeNet`. وتحت بث مباشر يبدأ التقييم من `live stream starving (N kbps) - evaluating known networks`، وفقط حين يعمل البث نفسه تحت `STREAM_MIN_KBPS`.

### مفاتيح الضبط المعنية

`MIN_UP_KBPS` و`UP_STRIKES` و`SWITCH_GAIN_PCT` و`DANCE_COOLDOWN` و`PROBE_KB` و`PROBE_URL`، والبدائل الليلية `NIGHT_MIN_UP_KBPS` و`NIGHT_GAIN_PCT` و`NIGHT_DANCE_COOLDOWN`، و`STREAM_MIN_KBPS`.

## 7. الحارس يموت وهو على شبكة مؤقتة

### سلوك النظام الأصلي

لا ينطبق. ملف تعريف أُنشئ بـ `nmcli device wifi connect` كان سيبقى تحت `/etc` ولا شيء يحذفه.

### سلوك أواكس

كان معرّف المدخل قد كُتب في `/run/awacs/open_id` قبل المحاولة. المشغِّل (حلقة `rc.local` أو وحدة systemd، بعد 10 ثوانٍ) يبدأ حارساً جديداً يحذف المدخل عند البداية: على `wpa` بـ `remove_network` للمعرّف المسجَّل؛ وعلى `nm` بحذف محروس لملف التعريف المسجَّل ثم كنس كل ملف تعريف `awacs-*` وكل ملف مفاتيح في `/run`. حذف المدخل يُسقط الرابط، فيكون الحارس الجديد بلا إنترنت ويبدأ الإنعاش فوراً، بلا انتظار `NET_FAIL_TICKS` وبلا سطر `internet lost`.

</div>

```text
[INFO][01/01 22:00:00] AWACS 1.0 starting on wlan0 (device mydevice)
[INFO][01/01 22:01:25] outage looks external (round 1) — waiting, not rebooting
[INFO][01/01 22:01:32] trying emergency networks (1 listed)
[INFO][01/01 22:02:08] trying open networks as last resort
[OK][01/01 22:02:40] connected to OPEN network: FreeCafe
```

<div dir="rtl">

وإن كانت شبكة مخزنة قد عادت في الأثناء انضم إليها الإنعاش بدلاً من ذلك.

### مفاتيح الضبط المعنية

`RUN_DIR` (مكان العلامة) و`SAFETY_NET` و`OPEN_NETWORKS`.

## 8. شبكة بيت مخفية

### سلوك النظام الأصلي

`wpa_supplicant` لا ينضم إلى شبكة مخفية إلا حين تحمل كتلتها `scan_ssid=1`؛ وNetworkManager إلا حين يحمل ملف التعريف `hidden=yes`. المسح العام يعرض نقطة الوصول بلا اسم.

### سلوك أواكس

على `wpa` يضبط الحارس `scan_ssid 1` على كل شبكة مخزنة عند البداية وعند كل إنعاش وبعد الدرجتين L2 وL3، وقت التشغيل فقط، فتعمل كتلة بيت بلا هذا السطر ما دام الحارس يعمل. فحص الشبكة المفضلة يطلب أولاً من `supplicant` مسحه الخاص ويأخذ اتحاد صورة `iw` و`wpa_cli scan_results` الذي يسمّي الشبكة المخفية. أثناء الإنعاش، حين ينجح مسح `iw` لا يسمّي الشبكة، فلا تكون مرشحة مقيسة، ويرتبط بها `supplicant` نفسه بعد الافتتاح الهادئ أو درجة ويحتسب الحارس النتيجة؛ وحين يسقط المسح إلى جدول `supplicant` تُسمّى وتصبح مرشحة. هواء لا يحوي إلا شبكات مخفية يحتفظ بصورة المسح السابقة وليس راديو أصم. على `nm` يجب أن يحمل ملف التعريف `hidden=yes`؛ NetworkManager يبحث عنها ويعرضها، والحارس لا يكتب الخاصية أبداً. `evaluate` يعرض الشبكة المخفية بين الشبكات المخزنة غير الظاهرة لأن المسح العام لا يحمل اسماً لها.

</div>

```text
[WARN][01/01 07:00:30] internet lost on wlan0 - engaging
[OK][01/01 07:01:05] internet restored: HomeNet
```

<div dir="rtl">

### مفاتيح الضبط المعنية

`PREF_CHECK`؛ وضبط الشبكة (`scan_ssid=1` اختياري على `wpa`، و`hidden=yes` واجب على `nm`).

## 9. التشغيل بلا موقع تقارير (وضع الإشارة)

### سلوك النظام الأصلي

لا ينطبق.

### سلوك أواكس

مع فراغ `SITE_URL` و`PROBE_URL` لا يوجد ما يُرفَع إليه. فحص الإنترنت بثلاث درجات بدل أربع. ينضم الإنعاش إلى أقوى شبكة مخزنة ظاهرة توصل الإنترنت، بترتيب الإشارة، بلا قياس؛ ويتعطل تقييم الرابط البطيء والمقارنة واستبعاد الوصول، ويظل الرجوع إلى الشبكة المفضلة يعمل. لا يُرسَل شيء ولا يُستعمَل المخزون؛ و`LOG_TARGET` بغير `local` يُخفَّض مع السطر `LOG_TARGET asked for the site but SITE_URL is empty - running local-only`. و`speed` يبلّغ أن لا هدف للقياس. ضبط `PROBE_URL` وحده (أي عنوان يقبل جسم `POST`) يعيد الاختيار بالقياس بلا سجل موقع.

</div>

```text
[INFO][01/01 08:00:00] AWACS 1.0 starting on wlan0 (device mydevice)
[INFO][01/01 08:00:00] reporting: local | probe: none - signal mode | wifi cell: auto
[WARN][01/01 09:10:30] internet lost on wlan0 - engaging
[OK][01/01 09:11:20] connected: OfficeNet (signal mode - no upload probe target configured)
[OK][01/01 09:11:20] internet restored: OfficeNet
[INFO][01/01 09:31:30] higher-priority network visible - trying to go home
[OK][01/01 09:31:50] returned to preferred network: HomeNet (signal mode)
```

<div dir="rtl">

### مفاتيح الضبط المعنية

`SITE_URL` و`PROBE_URL` و`LOG_TARGET` و`REPORT_WIFI`.

[features.md](features.md) تسرد كل القدرات؛ و[troubleshooting.md](troubleshooting.md) تشرح كل سطر سجل؛ و[configuration.md](configuration.md) فيها جدول المفاتيح.

</div>
