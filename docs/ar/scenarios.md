<div dir="rtl">

# سيناريوهات

تسع حالات، كل واحدة في ثلاثة أجزاء: ما يفعله النظام الأصلي، وما يفعله أواكس مع أسطر سجله بالترتيب، ومفاتيح الضبط المعنية. الأوقات والأسماء في العيّنات للتوضيح. `HomeNet` و`OfficeNet` شبكتان مخزنتان، و`PhoneHotspot` مدخل في `SAFETY_NET`، و`FreeCafe` شبكة مفتوحة، و`mydevice` معرّف الجهاز. العيّنات تعرض النظام الخلفي `wpa`؛ وعلى `nm` تكون أسطر الدرجات `recover L1: radio bounce` و`recover L2: re-kick NetworkManager on wlan0` و`recover L3: restart NetworkManager + reload WiFi firmware`. تُحذَف من العيّنات الأسطر المتكررة: محاولات الطوارئ والمفتوحة تتبع كل درجة، وسطر الأدلة بمستوى DEBUG يُسجَّل في كل جولة فيها أدلة على الجهاز. والأسطر التي يكررها الإنعاش داخل الانقطاع الواحد تُقال مرة وتُعدّ؛ وتأتي الأعداد بعد `internet restored`.

## 1. كلمة سر خاطئة على الشبكة الوحيدة المتاحة

### سلوك النظام الأصلي

`wpa_supplicant` يفشل في المصافحة، ويعلّم الشبكة `TEMP-DISABLED` لفترة تتزايد، ويعيد المحاولة بمؤقّته. NetworkManager يعيد محاولة ملف التعريف مرات قليلة ويترك الجهاز غير متصل. ولا واحد منهما يجرّب شبكة أخرى، وسكربت المراقبة الذي يعيد التشغيل عند فقد الإنترنت يعيد التشغيل بلا نهاية.

### سلوك أواكس

العلامات تشبه عطلاً في الجهاز (الشبكة ظاهرة، لا يمكن الانضمام إليها، لا موجّه)، لكن علامة كلمة السر حاضرة، فيُعاد مؤقّت إعادة التشغيل إلى الصفر في كل جولة. السلّم يعمل مع ذلك، لأن عطلاً قد يتزامن مع كلمة سر قديمة، وتتبع شبكات الطوارئ والمفتوحة كل درجة. ومع وضع كلمة السر الصحيحة ينجح الإنعاش التالي.

</div>

```text
2026-01-01T10:00:30+03:00 [WARN] internet lost on HomeNet - router none (not associated), engaging
2026-01-01T10:00:31+03:00 [INFO] router not answering - waiting up to 25 s for wlan0 to reconnect
2026-01-01T10:01:19+03:00 [INFO] scan heard 3 networks: HomeNet -48, Cafe -70, Guest -74 | known on the air: HomeNet | stored, not heard: OfficeNet
2026-01-01T10:01:20+03:00 [ERROR] association refused by HomeNet - wrong password? (recovery continues, reboot stays off)
2026-01-01T10:01:21+03:00 [WARN] recover L1: radio bounce
2026-01-01T10:01:30+03:00 [INFO] trying emergency networks (1 listed)
2026-01-01T10:02:04+03:00 [WARN] emergency network PhoneHotspot refused: never associated - trying the next
2026-01-01T10:02:04+03:00 [INFO] no emergency network delivered (1 tried, 0 skipped)
2026-01-01T10:02:05+03:00 [INFO] trying open networks as last resort (0 open networks heard)
2026-01-01T10:02:05+03:00 [INFO] no open network delivered internet (0 heard, 0 tried, 0 linked without internet)
2026-01-01T10:03:12+03:00 [WARN] recover L2: restart dhcpcd (respawns the REAL per-interface supplicant)
2026-01-01T10:05:30+03:00 [WARN] recover L3: reload brcmfmac firmware (the 3-second cure a wedge needs)
2026-01-01T10:06:05+03:00 [OK] internet restored: HomeNet - down 5 min, 1 recovery run
2026-01-01T10:06:05+03:00 [INFO] repeated 2 more times during the outage (last at 10:05): association refused by HomeNet - wrong password? (recovery continues, reboot stays off)
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
2026-01-01T12:00:30+03:00 [WARN] internet lost on HomeNet - router none (not associated), engaging
2026-01-01T12:00:31+03:00 [INFO] router not answering - waiting up to 25 s for wlan0 to reconnect
2026-01-01T12:00:44+03:00 [INFO] scan heard 5 networks: OfficeNet -61, Cafe -70, Guest -74, N5 -80, N6 -85 | known on the air: OfficeNet | stored, not heard: HomeNet
2026-01-01T12:00:45+03:00 [INFO] trying OfficeNet
2026-01-01T12:01:10+03:00 [INFO] candidate [1] OfficeNet uploads at 1484 kbps
2026-01-01T12:01:10+03:00 [INFO] switching to OfficeNet (1484 kbps, the fastest candidate)
2026-01-01T12:01:12+03:00 [OK] switched to OfficeNet (upload 1484 kbps)
2026-01-01T12:01:12+03:00 [OK] internet restored: OfficeNet - down 42 s, 1 recovery run
2026-01-01T12:21:30+03:00 [INFO] higher-priority network HomeNet visible twice - leaving OfficeNet to go home
2026-01-01T12:21:48+03:00 [INFO] measured 7445 kbps on HomeNet
2026-01-01T12:21:50+03:00 [OK] returned to preferred network: HomeNet (upload 7445 kbps)
```

<div dir="rtl">

لو قيست `HomeNet` تحت الحد عند الوصول لكان السطر `preferred network HomeNet too slow (120 kbps, floor 400) - benched for 60 min, going back to OfficeNet` ثم `back on OfficeNet`، وتُترَك `HomeNet` تلك الستين دقيقة (ثلاث فترات تبريد). و`HomeNet` التي تظهر بفحص وتغيب بالتالي تُقال مرة في الإقامة الواحدة، `preferred network HomeNet was visible at one check and gone at the next - staying on OfficeNet until it holds for two checks in a row`، ويحمل سطر المحاولة بعدها `(seen and lost N times before)`.

### مفاتيح الضبط المعنية

`PREF_CHECK`، و`MIN_UP_KBPS` و`NIGHT_MIN_UP_KBPS`، و`DANCE_COOLDOWN` (يدوم الاستبعاد ثلاث فترات منه)، و`PROBE_KB`، والأولويات في ضبط الشبكات (`priority=` على `wpa`، و`connection.autoconnect-priority` على `nm`)؛ والرجوع يحتاج أولوية للبيت أعلى تماماً من الحالية.

## 3. كل الشبكات المخزنة غائبة

### سلوك النظام الأصلي

لا شيء. النظامان لا يعرفان إلا الشبكات المخزنة.

### سلوك أواكس

لا شبكة مخزنة في الهواء، وشبكات أخرى موجودة، والموجّه صامت: لا تنطبق أي من علامات الجهاز الثلاث، فتُصنَّف الجولة خارجية ولا تعمل أي درجة. تُجرَّب مدخلات `SAFETY_NET` سواء أظهرها المسح أم لا، ثم الشبكات المفتوحة. الشبكة المنضَم إليها مدخل مؤقت بأولوية 0. وحين تعود شبكة مخزنة بأولوية أعلى يعيد فحص الشبكة المفضلة الجهاز إلى البيت ويُحذَف المدخل في الدورة الصحيحة التالية؛ فلا يبقى ملف تعريف `awacs-*` على `nm` ولا معرّف شبكة زائد في `supplicant` الحي على `wpa`.

</div>

```text
2026-01-01T14:00:30+03:00 [WARN] internet lost on HomeNet - router none (not associated), engaging
2026-01-01T14:00:31+03:00 [INFO] router not answering - waiting up to 25 s for wlan0 to reconnect
2026-01-01T14:01:54+03:00 [INFO] scan heard 4 networks: FreeCafe -55, Guest -70, N5 -80, N6 -85 | known on the air: none | stored, not heard: HomeNet, OfficeNet
2026-01-01T14:01:55+03:00 [INFO] outage looks external: none of your 2 stored networks is on the air, 4 others heard (round 1) — waiting, not rebooting
2026-01-01T14:02:02+03:00 [INFO] trying emergency networks (1 listed)
2026-01-01T14:02:37+03:00 [WARN] emergency network PhoneHotspot refused: never associated - trying the next
2026-01-01T14:02:37+03:00 [INFO] no emergency network delivered (1 tried, 0 skipped)
2026-01-01T14:02:38+03:00 [INFO] trying open networks as last resort (1 open networks heard)
2026-01-01T14:03:10+03:00 [OK] connected to OPEN network: FreeCafe (upload 620 kbps) - stored networks stay armed, home again when one returns
2026-01-01T14:03:11+03:00 [OK] internet restored: FreeCafe - down 2 min, 1 recovery run
2026-01-01T14:42:30+03:00 [INFO] higher-priority network HomeNet visible twice - leaving FreeCafe to go home
2026-01-01T14:43:06+03:00 [INFO] measured 2302 kbps on HomeNet
2026-01-01T14:43:08+03:00 [OK] returned to preferred network: HomeNet (upload 2302 kbps)
2026-01-01T14:43:21+03:00 [OK] back on a stored network: HomeNet - temporary network FreeCafe removed
```

<div dir="rtl">

هنا كانت نقطة الاتصال مطفأة؛ ولو كانت تعمل لكان السطران `connected to EMERGENCY network: PhoneHotspot (upload 1100 kbps) - stored networks stay armed, home again when one returns` و`internet restored: PhoneHotspot - down 2 min, 1 recovery run`، ولا تُجرَّب أي شبكة مفتوحة.

### مفاتيح الضبط المعنية

`SAFETY_NET` و`OPEN_NETWORKS` و`PREF_CHECK`، وأولوية فوق 0 على الشبكات المخزنة.

## 4. انقطاع المزوّد والموجّه يرد

### سلوك النظام الأصلي

النظامان يريان ارتباطاً وعنواناً ولا يفعلان شيئاً. وسكربت المراقبة الذي يعيد التشغيل عند فقد الإنترنت يعيد التشغيل كل بضع دقائق طوال الانقطاع.

### سلوك أواكس

يُعلَن الفقد هنا متأخراً عنه على وصلة ميتة: البوابة ما زالت ترد، فيجري فحص صبور واحد قبل أن يُحسب الفحص السريع الثالث الفاشل، ويبدأ الإنعاش بعد نحو 72 إلى 83 ثانية من الفقد بدل 40 إلى 63. والإنعاش الأول يُبقي الارتباط القائم: تُتخطى إعادة الارتباط، وتُستثنى الشبكة التي عليها الجهاز من المرشحين، وتنتهي المحاولات الفاشلة بالعودة إليها. بعد تفعيل كل شبكة مخزنة ظاهرة وتبيّن أنها بلا إنترنت ينجح `ping` الموجّه، فالانقطاع خارجي: لا درجة، ويبقى مؤقّت إعادة التشغيل صفراً. تجرّب كل جولة مع ذلك شبكات الطوارئ والمفتوحة، لأن شبكة أخرى قد يكون لها مزوّد آخر، ثم تنتظر 20 ثانية؛ للإنعاش ثلاث جولات ويبدأ إنعاش جديد كل دورة ما دام الانقطاع. أسطر الموقع تُخزَّن في الأثناء وتُسلَّم بالترتيب حين يعود الرابط.

</div>

```text
2026-01-01T16:00:30+03:00 [WARN] internet lost on HomeNet - router still answers, engaging
2026-01-01T16:00:31+03:00 [INFO] router answers on HomeNet - keeping the link, trying the other stored networks first
2026-01-01T16:00:57+03:00 [INFO] scan heard 6 networks: HomeNet -48, OfficeNet -61, Cafe -70, Guest -74, N5 -80, N6 -85 | known on the air: HomeNet, OfficeNet | stored, not heard: none
2026-01-01T16:00:58+03:00 [INFO] trying OfficeNet
2026-01-01T16:01:39+03:00 [WARN] could not connect to OfficeNet: linked but no internet - trying the next
2026-01-01T16:01:40+03:00 [INFO] outage looks external: the router answers, the fault is upstream (round 1) — waiting, not rebooting
2026-01-01T16:01:50+03:00 [INFO] trying emergency networks (1 listed)
2026-01-01T16:02:24+03:00 [WARN] emergency network PhoneHotspot refused: never associated - trying the next
2026-01-01T16:02:24+03:00 [INFO] no emergency network delivered (1 tried, 0 skipped)
2026-01-01T16:02:25+03:00 [INFO] trying open networks as last resort (2 open networks heard)
2026-01-01T16:02:58+03:00 [WARN] open network Cafe linked but no internet (captive portal?) - trying the next
2026-01-01T16:03:30+03:00 [INFO] no open network delivered internet (2 heard, 2 tried, 1 linked without internet)
2026-01-01T16:48:10+03:00 [OK] internet restored: HomeNet - down 47 min, 12 recovery runs
2026-01-01T16:48:10+03:00 [INFO] repeated 35 more times during the outage (last at 16:47): outage looks external: the router answers, the fault is upstream — waiting, not rebooting
```

<div dir="rtl">

تتكرر محاولات الطوارئ والمفتوحة في كل جولة حتى يعود المزوّد؛ أما الحكم والرفوض وأسطر ختام المرور فتُقال مرة لكل انقطاع وتُعدّ، وتأتي الأعداد بعد `internet restored`. وعلى `nm` يأخذ الجهاز المُبلَّغ عنه متصلاً مع صمت الموجّه الفرع نفسه بالسطر `NetworkManager is connected, internet is not (round N) — router-side, no rung`.

### مفاتيح الضبط المعنية

`NET_FAIL_TICKS` و`SAFETY_NET` و`OPEN_NETWORKS` و`SPOOL_CAP` و`LOG_TARGET`.

## 5. عطل في الجهاز: راديو أصم وإعادة التشغيل

### سلوك النظام الأصلي

الراديو يتوقف عن سماع أي شيء. `wpa_supplicant` يمسح ولا يجد شيئاً إلى ما لا نهاية؛ وNetworkManager يترك الجهاز غير متصل أو غير متاح. لا شيء يعيد تحميل التعريف أو يعيد تشغيل الجهاز.

### سلوك أواكس

ثلاثة مسوح متتالية بلا شيء من أي مصدر تُسقط الصورة القديمة؛ والراديو الذي لا يسمع شيئاً علامة على الجهاز، فيبدأ مؤقّت إعادة التشغيل. يعمل السلّم L1 وL2 وL3 مع محاولات الطوارئ والمفتوحة بعد كل درجة، وتكرره الإنعاشات التالية. وحين تستمر الأدلة `REBOOT_AFTER_MIN` دقيقة بلا دورة صحيحة يُكتَب سطر إعادة التشغيل، وتُحفظ قصة الانقطاع بجانب السجل، ويُعاد تشغيل الجهاز. على `nm` لا يعمل المؤقّت إلا بعد أن يستقر NetworkManager في حالة غير متصل أو فاشل في جولتين متتاليتين؛ والحالة 20 (غير متاح) لا تبدؤه أبداً.

</div>

```text
2026-01-01T18:00:30+03:00 [WARN] internet lost on HomeNet - router none (not associated), engaging
2026-01-01T18:00:31+03:00 [INFO] router not answering - waiting up to 25 s for wlan0 to reconnect
2026-01-01T18:01:05+03:00 [WARN] radio heard nothing on 3 scans in a row - previous results dropped
2026-01-01T18:01:05+03:00 [INFO] scan heard 0 networks | known on the air: none | stored, not heard: HomeNet, OfficeNet
2026-01-01T18:01:06+03:00 [DEBUG] fight round 1: ME evidence (LINK_OK=0, gw unreachable, auth_failing=0)
2026-01-01T18:01:06+03:00 [WARN] fault looks on the device: the radio hears no network at all - recovery follows
2026-01-01T18:01:06+03:00 [WARN] reboot clock armed - the device reboots after 18:31 unless the internet returns or the fault reads external
2026-01-01T18:01:07+03:00 [WARN] recover L1: radio bounce
2026-01-01T18:01:15+03:00 [INFO] trying emergency networks (1 listed)
2026-01-01T18:01:50+03:00 [INFO] trying open networks as last resort (0 open networks heard)
2026-01-01T18:02:40+03:00 [WARN] recover L2: restart dhcpcd (respawns the REAL per-interface supplicant)
2026-01-01T18:04:10+03:00 [WARN] recover L3: reload brcmfmac firmware (the 3-second cure a wedge needs)
2026-01-01T18:31:10+03:00 [ERROR] rebooting now: wedged 30 min (the radio hears no network at all) - reboot 1 for this fault, the story continues after the boot
2026-01-01T18:33:20+03:00 [INFO] AWACS 1.0 starting on wlan0 (device mydevice) - wpa backend, first start of this boot, up 45 s
2026-01-01T18:33:20+03:00 [WARN] starting after the reboot AWACS ordered at 2026-01-01 18:31 - wedged 30 min (the radio hears no network at all), 9 recovery runs before it
```

<div dir="rtl">

بعد إعادة التشغيل يبدأ المؤقّت من الصفر؛ والعطل الذي ينجو منها لا يستحق التالية إلا بعد نافذة كاملة أخرى، ويرتفع العدد في سطر إعادة التشغيل (`reboot 2 for this fault`) حتى تمسحه دورة صحيحة. وتصل قصة الانقطاع وسطر إعادة التشغيل والسطران بعده إلى الموقع بهذا الترتيب حين يعود الجهاز إلى الإنترنت: نُسخ المخزون بجانب السجل قبل إعادة التشغيل واستُعيد في هذا البدء.

### مفاتيح الضبط المعنية

`REBOOT_AFTER_MIN` و`NET_FAIL_TICKS` و`SCAN_TTL`.

## 6. رابط بطيء وشبكة مخزنة أسرع متاحة

### سلوك النظام الأصلي

لا شيء. الرابط المتصل رابط متصل.

### سلوك أواكس

يقرأ المقياس السلبي عدّاد الإرسال كل دورة. معدل بين 20 كيلوبت/ث والحد الأدنى في `UP_STRIKES` دورات متتالية، مع انقضاء فترة التبريد، يبدأ تقييماً بقياس رفع واحد للشبكة الحالية. القياس فوق الحد ينهيه (`measured 800 kbps on HomeNet - above the 400 kbps floor, staying`): المقياس رأى تدفقاً صغيراً لا رابطاً بطيئاً. والقياس تحت الحد، هنا 250 كيلوبت/ث، يضع عتبة المنافِسة عند `SWITCH_GAIN_PCT` بالمئة منه، أي 375 كيلوبت/ث؛ تُفعَّل كل شبكة مخزنة ظاهرة أخرى وتُقاس، وتُبقى الأفضل فوق العتبة.

</div>

```text
2026-01-01T20:01:27+03:00 [WARN] sustained slow upload on HomeNet (107 kbps for 3 samples, floor 400) - evaluating known networks
2026-01-01T20:01:28+03:00 [INFO] scan heard 6 networks: HomeNet -48, OfficeNet -61, Cafe -70, Guest -74, N5 -80, N6 -85 | known on the air: HomeNet, OfficeNet | stored, not heard: none
2026-01-01T20:01:40+03:00 [INFO] measured 250 kbps on HomeNet - under the 400 kbps floor, a challenger must beat 375 kbps
2026-01-01T20:01:41+03:00 [INFO] trying OfficeNet
2026-01-01T20:01:58+03:00 [INFO] candidate [1] OfficeNet uploads at 1620 kbps
2026-01-01T20:01:58+03:00 [INFO] switching to OfficeNet (1620 kbps against 250 kbps here) - plainly fast, over 4x the 400 kbps floor, probing stopped at it
2026-01-01T20:02:20+03:00 [OK] switched to OfficeNet (upload 1620 kbps)
```

<div dir="rtl">

وحين لا تتجاوز أي مرشحة العتبة يعود الحارس: `no challenger beat the incumbent - staying on HomeNet (best was OfficeNet at 300 kbps, needed 375)`. والعيّنات البطيئة التي تنضج من جديد داخل فترة التبريد تُقال مرة في النافذة، `upload still slow on HomeNet (107 kbps, floor 400) - evaluation on cooldown, next look in 12 min`. وتحت بث مباشر يبدأ التقييم من `live stream starving on HomeNet (N kbps for 3 samples, floor 50) - evaluating known networks`، وفقط حين يعمل البث نفسه تحت `STREAM_MIN_KBPS`.

### مفاتيح الضبط المعنية

`MIN_UP_KBPS` و`UP_STRIKES` و`SWITCH_GAIN_PCT` و`DANCE_COOLDOWN` و`PROBE_KB` و`PROBE_URL`، والبدائل الليلية `NIGHT_MIN_UP_KBPS` و`NIGHT_GAIN_PCT` و`NIGHT_DANCE_COOLDOWN`، و`STREAM_MIN_KBPS`.

## 7. الحارس يموت وهو على شبكة مؤقتة

### سلوك النظام الأصلي

لا ينطبق. ملف تعريف أُنشئ بـ `nmcli device wifi connect` كان سيبقى تحت `/etc` ولا شيء يحذفه.

### سلوك أواكس

كان معرّف المدخل قد كُتب في `/run/awacs/open_id` قبل المحاولة. المشغِّل (حلقة `rc.local` أو وحدة systemd، بعد 10 ثوانٍ) يبدأ حارساً جديداً يحذف المدخل عند البداية: على `wpa` بـ `remove_network` للمعرّف المسجَّل؛ وعلى `nm` بحذف محروس لملف التعريف المسجَّل ثم كنس كل ملف تعريف `awacs-*` وكل ملف مفاتيح في `/run`. حذف المدخل يُسقط الرابط، فيكون الحارس الجديد بلا إنترنت ويبدأ الإنعاش فوراً، بلا انتظار `NET_FAIL_TICKS`؛ وللحذف ولفقد البدء سطراهما، ويُعلَن الفوز في أول دورة صحيحة. وإن كان الحارس السابق قد انتهى بخطأ لا بقتل، وقف سطره `AWACS exited unexpectedly (status N, last command ...: ...) - the launcher restarts it in 10 s` فوق سطر البدء حين يُسلَّم المخزون.

</div>

```text
2026-01-01T22:00:00+03:00 [INFO] AWACS 1.0 starting on wlan0 (device mydevice) - wpa backend, restart 1 of this boot
2026-01-01T22:00:01+03:00 [WARN] removed the temporary network FreeCafe left by the previous run - the device was still on it, recovery follows
2026-01-01T22:00:05+03:00 [WARN] no internet at start on wlan0 - router none (not associated), engaging
2026-01-01T22:00:06+03:00 [INFO] router not answering - waiting up to 25 s for wlan0 to reconnect
2026-01-01T22:01:24+03:00 [INFO] scan heard 4 networks: FreeCafe -55, Guest -70, N5 -80, N6 -85 | known on the air: none | stored, not heard: HomeNet, OfficeNet
2026-01-01T22:01:25+03:00 [INFO] outage looks external: none of your 2 stored networks is on the air, 4 others heard (round 1) — waiting, not rebooting
2026-01-01T22:01:32+03:00 [INFO] trying emergency networks (1 listed)
2026-01-01T22:02:08+03:00 [INFO] trying open networks as last resort (1 open networks heard)
2026-01-01T22:02:40+03:00 [OK] connected to OPEN network: FreeCafe (upload 640 kbps) - stored networks stay armed, home again when one returns
2026-01-01T22:02:53+03:00 [OK] internet restored: FreeCafe - down 2 min, 1 recovery run
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
2026-01-01T07:00:30+03:00 [WARN] internet lost on HomeNet - router silent too, engaging
2026-01-01T07:00:31+03:00 [INFO] router not answering - waiting up to 25 s for wlan0 to reconnect
2026-01-01T07:01:05+03:00 [OK] internet restored: HomeNet - down 35 s, 1 recovery run
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
2026-01-01T08:00:00+03:00 [INFO] AWACS 1.0 starting on wlan0 (device mydevice) - wpa backend, first start of this boot, up 38 s
2026-01-01T08:00:00+03:00 [INFO] reporting: local | probe: none - signal mode | wifi cell: auto
2026-01-01T08:00:01+03:00 [INFO] running with: signal mode (no probe target - networks chosen by signal), reboot after 30 min wedged, wifi cell off (no SITE_URL), 2 stored networks, 1 emergency, open networks yes, stamps in the device zone
2026-01-01T08:00:04+03:00 [OK] online at start via HomeNet
2026-01-01T09:10:30+03:00 [WARN] internet lost on HomeNet - router silent too, engaging
2026-01-01T09:10:31+03:00 [INFO] router not answering - waiting up to 25 s for wlan0 to reconnect
2026-01-01T09:10:54+03:00 [INFO] scan heard 5 networks: OfficeNet -61, Cafe -70, Guest -74, N5 -80, N6 -85 | known on the air: OfficeNet | stored, not heard: HomeNet
2026-01-01T09:10:55+03:00 [INFO] trying OfficeNet
2026-01-01T09:11:20+03:00 [OK] connected: OfficeNet (signal mode - no upload probe target configured)
2026-01-01T09:11:20+03:00 [OK] internet restored: OfficeNet - down 50 s, 1 recovery run
2026-01-01T09:31:30+03:00 [INFO] higher-priority network HomeNet visible twice - leaving OfficeNet to go home
2026-01-01T09:31:50+03:00 [OK] returned to preferred network: HomeNet (signal mode)
```

<div dir="rtl">

### مفاتيح الضبط المعنية

`SITE_URL` و`PROBE_URL` و`LOG_TARGET` و`REPORT_WIFI`.

[features.md](features.md) تسرد كل القدرات؛ و[troubleshooting.md](troubleshooting.md) تشرح كل سطر سجل؛ و[configuration.md](configuration.md) فيها جدول المفاتيح.

</div>
