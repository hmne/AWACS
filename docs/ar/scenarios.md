<div dir="rtl">

# سيناريوهات

حالات عملية، كل واحدة: الحالة، ما يفعله النظام وحده، ما يفعله أواكس، وما يظهر في اللوق. سطور اللوق حقيقية من المختبر (`lab/evidence/*/RESULT.txt` وملفات `awacs.log` المحفوظة). عمل المختبر بـ `REBOOT_AFTER_MIN=4` و`PREF_CHECK=60` و`DANCE_COOLDOWN=120` لتقصير الانتظار؛ والأزمنة داخل الأجهزة الافتراضية أبطأ 3–5 مرات من جهاز حقيقي.

## 1. كلمة سر خاطئة على الشبكة الوحيدة المتاحة

**الحالة.** تغيّرت كلمة سر الراوتر أو المخزنة خاطئة. لا شبكة مخزنة أخرى في الهواء.

**النظام وحده.** wpa_supplicant يعلّم الشبكة `TEMP-DISABLED` ويعيد المحاولة بجدوله؛ NetworkManager يحاول ويفشل ويترك الكرت منقطعاً. لا شيء يُكتب، لا شيء آخر يُجرَّب، وسكربت المراقبة الذي «يعيد التشغيل حين ينقطع الإنترنت» يعيد التشغيل إلى الأبد.

**أواكس.** يبدأ القتال. توقيع الأدلة يشبه العطل المحلي (شبكة ظاهرة، لا تُركَب، لا راوتر)، لكن `auth_failing` يُطلِق، فتُصفَّر ساعة الريبوت كل مرة تُرى. السلّم يعمل مع ذلك (قد يتزامن عطل حقيقي مع كلمة سر قديمة)، وتُجرَّب شبكات الطوارئ والمفتوحة، ولحظة عودة الكلمة الصحيحة يشفى الجهاز.

**اللوق (الصورة القديمة، 2026-09-12).**

</div>

```text
[WARN][12/09 17:54:36] internet lost on wlan0 - engaging
[ERROR][12/09 17:56:21] association refused - wrong password? (recovery continues, reboot stays off)
[WARN][12/09 17:56:22] recover L1: radio bounce
[INFO][12/09 17:56:31] trying emergency networks (1 listed)
[INFO][12/09 17:57:06] trying open networks as last resort
[ERROR][12/09 17:58:31] association refused - wrong password? (recovery continues, reboot stays off)
[WARN][12/09 17:58:33] recover L2: restart dhcpcd (respawns the REAL per-interface supplicant)
[WARN][12/09 18:00:49] recover L3: reload brcmfmac firmware (the 3-second cure a wedge needs)
[OK][12/09 18:01:05] internet restored: HomeNet
```

<div dir="rtl">

حكم المختبر: نفس معرّف الإقلاع بعد 403 ثانية (بعد صمّام المختبر ذي الأربع دقائق)، وشُفي حين عادت الكلمة الصحيحة. نفس النتيجة على صورة NetworkManager.

## 2. نقطة البيت تسقط ثم تعود

**الحالة.** شبكة الأولوية 10 تختفي. شبكة بأولوية 5 (هنا باسم عربي) ما زالت في الهواء.

**النظام وحده.** wpa_supplicant ينتقل بنفسه إلى الشبكة المخزنة الأخرى؛ وNetworkManager كذلك. لا أحد منهما يعود حين ترجع شبكة البيت ما لم يسقط الرابط الحالي، ولا أحد منهما يعرف أي شبكة ترفع أسرع فعلاً.

**أواكس.** الطبقة الأساسية تنقل الجهاز؛ وإن تأخرت يفعل القتال ذلك (`best_by_upload` قاس الشبكة العربية 1484 kbps على صورة NM). ثم كل `PREF_CHECK` يبحث `best_pref_id` عن شبكة مخزنة ظاهرة بأولوية أعلى تماماً؛ بعد رؤيتين متتاليتين يعود أواكس إلى البيت ويقيس عند الوصول.

**اللوق (الصورة القديمة).**

</div>

```text
[WARN][12/09 19:54:45] internet lost on wlan0 - engaging
[OK][12/09 19:55:04] internet restored: شبكة البيت
[INFO][12/09 19:56:47] higher-priority network visible - trying to go home
[OK][12/09 19:57:07] returned to preferred network: HomeNet (upload 7445 kbps)
```

<div dir="rtl">

**اللوق (صورة NetworkManager).**

</div>

```text
[WARN][12/09 17:52:03] internet lost on wlan0 - engaging
[INFO][12/09 17:53:56] candidate [6b81e11c-…] شبكة البيت uploads at 1484 kbps
[OK][12/09 17:54:15] internet restored: شبكة البيت
[INFO][12/09 17:57:48] higher-priority network visible - trying to go home
[OK][12/09 17:58:06] returned to preferred network: HomeNet (upload 1948 kbps)
```

<div dir="rtl">

الانتقال أخذ 18 ثانية على الصورة القديمة و162 على NM، لأن أواكس على NM ينتظر محاولات NetworkManager أولاً. خانة الواي فاي في الموقع تحوّلت إلى `1484,2,2,5GHz,شبكة البيت`.

## 3. كل الشبكات المخزنة غائبة: شبكة طوارئ ثم مفتوحة ثم البيت

**الحالة.** كل الشبكات المخزنة خارج الهواء. هوتسبوت هاتف مدرج في `SAFETY_NET` قد يكون مشغَّلاً أو لا؛ وشبكة مقهى مفتوحة موجودة.

**النظام وحده.** لا شيء. النظامان لا يعرفان إلا الشبكات المخزنة.

**أواكس.** `try_safety` أولاً: كل مدخل في `SAFETY_NET` يُجرَّب حتى لو لم يُظهره المسح. ثم `try_open`: الشبكات المفتوحة فعلاً، محاولة واحدة لكل اسم، والغرباء الضعاف يُتجاوَزون. الشبكة المتصلة مدخل مؤقت — wpa: معرّف شبكة في supplicant الحي لا يُحفَظ أبداً؛ NM: ملف مفاتيح في `/run`، `autoconnect=false`، صلاحيات 0600، لا شيء تحت `/etc`. حين تعود شبكة مخزنة إلى الواجهة يُحذَف المدخل المؤقت.

**اللوق (صورة NetworkManager).**

</div>

```text
[WARN][12/09 18:08:55] internet lost on wlan0 - engaging
[INFO][12/09 18:10:20] outage looks external (round 1) — waiting, not rebooting
[INFO][12/09 18:10:27] trying emergency networks (1 listed)
[INFO][12/09 18:11:03] trying open networks as last resort
[OK][12/09 18:11:35] connected to OPEN network: FreeCafe
[OK][12/09 18:11:36] internet restored: FreeCafe
[WARN][12/09 18:13:05] internet lost on wlan0 - engaging
[INFO][12/09 18:14:25] trying emergency networks (1 listed)
[OK][12/09 18:14:53] connected to EMERGENCY network: LabHotspot
[OK][12/09 18:14:54] internet restored: LabHotspot
[INFO][12/09 18:18:45] higher-priority network visible - trying to go home
[OK][12/09 18:19:23] returned to preferred network: HomeNet (upload 2302 kbps)
```

<div dir="rtl">

دليل المختبر: `awacs-crutch-1789236666-2629` عاش في `/run/NetworkManager/system-connections` بصلاحيات 0600 و`autoconnect=false`؛ لا شيء من أواكس في `/etc/NetworkManager/system-connections`؛ وبعد العودة للبيت لم يبقَ أي اتصال `awacs-*`. على الصورة القديمة حمل supplicant الحي 3 شبكات (2 للمالك + عكاز) أثناء الملجأ و2 بعده.

## 4. انقطاع المزوّد: الراوتر يرد والإنترنت لا

**الحالة.** رابط الواي فاي سليم؛ المزوّد ساقط.

**النظام وحده.** النظامان راضيان: يريان ارتباطاً وعنواناً. سكربت مراقبة ساذج يعيد تشغيل الجهاز كل N دقيقة لساعات.

**أواكس.** `gw_ok` ينجح، فالانقطاع خارجي. الساعة تبقى صفراً، السلّم لا يعمل، وكل جولة تسجّل الحكم وتنتظر 20 ثانية. شبكات الطوارئ والمفتوحة تُجرَّب مع ذلك، لأن شبكة مختلفة قد يكون لها مزوّد مختلف. أسطر الموقع تُخزَّن وتصل بعد التعافي.

**اللوق (صورة NetworkManager).**

</div>

```text
[WARN][12/09 18:22:44] internet lost on wlan0 - engaging
[INFO][12/09 18:23:57] outage looks external (round 1) — waiting, not rebooting
[INFO][12/09 18:24:07] trying emergency networks (1 listed)
[INFO][12/09 18:24:42] trying open networks as last resort
[INFO][12/09 18:26:44] outage looks external (round 2) — waiting, not rebooting
[OK][12/09 18:28:06] internet restored: FreeCafe
```

<div dir="rtl">

لوق الموقع بعد التعافي: `[INFO] AWACS: الانقطاع يبدو خارجياً (جولة 1) — ننتظر بلا إعادة تشغيل, 12/09/2026 09:23:58 PM.` — حمل المخزون 6 أسطر أثناء الانقطاع وسلّمها بالترتيب.

## 5. عطل حقيقي على NetworkManager: صمّام الريبوت

**الحالة.** الشبكة المخزنة تبثّ وتقبل الارتباط، لكن لا عنوان يصل أبداً ولا شبكة أخرى في الهواء. على NM يسقط الكرت الرابط ويستقر في disconnected/failed.

**النظام وحده.** NetworkManager يحاول مرات ويتوقف. الجهاز يبقى منقطعاً حتى يفصل أحد الكهرباء ويعيدها.

**أواكس.** أدلة «عندي»: شبكة مخزنة ظاهرة، `LINK_OK=0`، لا راوتر، لا علامة كلمة سر. على NM لا تُسلَّح الساعة إلا حين يرى `nm_me_settled` استسلام NM مرتين متتاليتين. السلّم يعمل L1 وL2 وL3 ويتكرر. بعد `REBOOT_AFTER_MIN` من الأدلة المتصلة يُطلَق الصمّام — مسجَّلاً محلياً فقط لأن لا شيء يُرسَل — ويعود الجهاز متصلاً.

**اللوق (صورة NetworkManager، `REBOOT_AFTER_MIN=4`).**

</div>

```text
[WARN][12/09 19:00:53] internet lost on wlan0 - engaging
[DEBUG][12/09 19:04:01] fight round 1: ME evidence (LINK_OK=0, gw unreachable, auth_failing=0)
[WARN][12/09 19:04:02] recover L1: radio bounce
[WARN][12/09 19:05:07] recover L2: re-kick NetworkManager on wlan0
[WARN][12/09 19:06:15] recover L3: restart NetworkManager + reload WiFi firmware
[WARN][12/09 19:08:10] recover L1: radio bounce
[WARN][12/09 19:09:09] recover L2: re-kick NetworkManager on wlan0
[WARN][12/09 19:10:28] recover L3: restart NetworkManager + reload WiFi firmware
[ERROR][12/09 19:11:22] wedged 4min with networks visible — rebooting (repeats per streak until cured)
[INFO][12/09 19:13:48] AWACS 1.0 starting on wlan0 (device cam1)
[INFO][12/09 19:13:48] NetworkManager backend - AWACS supervises it (full capability)
```

<div dir="rtl">

تشغيل ثانٍ في المختبر حجب NetworkManager وأوقفه كلياً (`nmcli` يخرج بـ 8، الحالة غير مقروءة). `systemctl restart NetworkManager` في L3 لم يستطع المساعدة؛ حين استُهلكت L3 تسلّحت الساعة، وانطلق الصمّام بعد 47 ثانية من نضوجها، وعاد الجهاز متصلاً بعد الريبوت.

لاحظ أن نفس الإعداد على الصورة القديمة **ليس** انقطاعاً: dhcpcd يحتفظ بعقده الصالح ومساره الافتراضي، الإنترنت يبقى، وأواكس يصمت بحق.

## 6. `iw scan` يقول «Device or resource busy»

**الحالة.** الجهاز مرتبط وsupplicant أو NM يمسح الآن. `iw dev wlan0 scan` يفشل بـ `command failed: Device or resource busy (-16)`.

**النظام وحده.** ليست مشكلة للنظامَين؛ مشكلة لأي سكربت يمسح بـ `iw`. في المختبر أصابت 77 من 107 مسحاً للحارس على الصورة القديمة و17 من 25 على NM.

**أواكس.** عند `busy` ينتظر ثلاث ثوانٍ مرة واحدة ثم يقرأ جدول النظام نفسه: `wpa_cli scan_results` أو `nmcli device wifi list --rescan no`، محوَّلاً إلى نفس TSV. قبل هذا الإصلاح امتلأ اللوق بـ `scan failed - using previous results (if any)` وطبع `evaluate`/`scan` هواءً فارغاً؛ بعده `scan: 1/3 tries used` وعملت كل كلمات صندوق الأدوات على الصورتَين (16/16 و17/17 فحصاً).

## 7. أداة ناقصة

**الحالة.** حُذفت `iw` (أو لم تُثبَّت أصلاً على صورة مصغّرة).

**النظام وحده.** كل سكربت يحتاجها يفشل بصمت.

**أواكس.** `check_tools` يجرد قائمة أدوات النظام عند البداية ويذكر الناقص. في أول لحظة صحة مؤكدة (الدورة الصحيحة الثالثة) يشغّل `install_tools` أمر `apt-get install` واحداً محدوداً في الخلفية، مرة كل إقلاع، بأسماء الحزم الصحيحة (`wpa_cli` → `wpasupplicant`، `nmcli` → `network-manager`، `ip` → `iproute2`، `ping` → `iputils-ping`، `pgrep` → `procps`، `flock` → `util-linux`، `modprobe` → `kmod`). النجاح يُحكَم بظهور الأداة في `PATH` لا برمز خروج apt.

**اللوق (صورة NetworkManager).**

</div>

```text
[INFO][12/09 18:38:30] AWACS 1.0 starting on wlan0 (device cam1)
[ERROR][12/09 18:38:32] missing tools: iw - will try to install once online
[INFO][12/09 18:40:15] installing missing tools: iw
[OK][12/09 18:41:30] tools installed: iw
```

<div dir="rtl">

حين تكون `nmcli` نفسها الأداة الناقصة على صورة NM، يقف أواكس في وضع المراقبة، يثبّتها (بـ `--reinstall` لأن حزمة NetworkManager موجودة لكنها معطوبة)، ويخرج كي تعيد حلقة إعادة التشغيل تشغيله بكامل القدرة:

</div>

```text
[ERROR][12/09 19:19:06] missing tools: nmcli - will try to install once online
[ERROR][12/09 19:19:07] NetworkManager image but AWACS cannot drive it (unmanaged/no nmcli) - monitoring only
[OK][12/09 19:24:09] nmcli is now installed - restarting as a full NetworkManager supervisor
[INFO][12/09 19:24:26] NetworkManager backend - AWACS supervises it (full capability)
```

<div dir="rtl">

## 8. الحارس يموت وهو على شبكة مؤقتة

**الحالة.** قُتل أواكس (انهيار، نفاد ذاكرة، مشغّل) بينما الجهاز يركب شبكة مفتوحة أنشأها.

**النظام وحده.** لا ينطبق؛ الملف الشارد كان سيبقى.

**أواكس.** معرّف الشبكة المؤقتة يُكتَب في `/run/awacs/open_id` قبل المحاولة. الحارس المُعاد تشغيله يحصده عند البداية (`reap_crutches`؛ على NM أيضاً مسح بادئة الاسم وملفات `/run`)، يعيد تفعيل كل الشبكات المخزنة، والطبقة الأساسية أو القتال التالي يعيد الجهاز.

**المختبر (صورة NetworkManager).** `connected to OPEN network: FreeCafe` → قتل → `AWACS 1.0 starting on wlan0` → حُصد العكاز → عاد متصلاً بالشبكة العربية المخزنة بعد 25 ثانية. التشغيلات الأولى لهذا السيناريو أخذت 10–25 دقيقة للعودة؛ تبيّن أن L1 كانت تطفئ كل راديو في الجهاز الافتراضي بـ `nmcli radio wifi off` وأن درجة انطلقت بعد خمس ثوانٍ من نجاح NM. كلاهما أُصلح: L1 تقلب مفتاح rfkill الخاص بالكرت فقط، وكل حدّ درجة يعيد فحص NM أولاً.

## 9. رفع بطيء مستمر

**الحالة.** الجهاز يرفع، والرابط يعطي 107 kbps في ثلاث عيّنات متتالية بينما الحد 400.

**النظام وحده.** لا شيء؛ الرابط «متصل».

**أواكس.** ثلاث ضربات وانتهى التبريد: قياس صادق واحد للشبكة الحالية. إن قاس فوق الحد لا تبديل (المقياس السلبي رأى تدفقاً صغيراً لا رابطاً بطيئاً). وإن قاس تحته، يجرّب `best_by_upload` الشبكات المخزنة الظاهرة الأخرى ويبدّل فقط حين تتفوّق واحدة على الحالية بالنسبة المطلوبة.

**اللوق (الصورة القديمة).**

</div>

```text
[WARN][12/09 21:01:27] sustained slow upload (107 kbps) - evaluating known networks
```

<div dir="rtl">

قاس القياس 4260 kbps، لم يحدث تبديل، وخانة الواي فاي في الموقع قرأت `4260,2,2,2.4GHz,HomeNet`.

## ما لم يُجرَّب في المختبر

بوابات الدخول، مزوّد حقيقي، IPv6، شبكات `SAFETY_NET` مخفية، وتعريف `brcmfmac` الخاص بـ Raspberry Pi (راديو المختبر `mac80211_hwsim`). القائمة في [testing.md](testing.md).

</div>
