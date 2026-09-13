<div dir="rtl">

# استكشاف الأخطاء

كل مدخل سطر يطبعه السكربت نفسه، وأين يظهر، وماذا يعني، وماذا تفعل. اللوق المحلي: `/var/log/awacs.log`. stderr للحارس لا يذهب إلى مكان تحت حلقة إعادة التشغيل، فأفضل طريقة لرؤية رفضَي ملف الضبط أدناه هي تشغيل `sudo awacs.sh status` على الطرفية.

## `awacs: IGNORING /etc/awacs.conf (not owned by root — chown root: it)`

أين: stderr، عند كل بداية (الحارس أو كلمة أدوات بصلاحيات root).

المعنى: ملف الضبط موجود لكنه ليس ملك root. غالباً استُعيد من نسخة احتياطية بمستخدم آخر. الحارس يعمل بالافتراضيات: لا `SAFETY_NET`، لا موقع.

الحل: `sudo chown root:root /etc/awacs.conf`.

## `awacs: IGNORING /etc/awacs.conf (group/world can access it — chmod 600 it)`

أين: stderr، عند كل بداية.

المعنى: الصلاحيات تحوي بتات للمجموعة أو الغير (`0644`، `0640`، …). الملف يحمل كلمات سر الهوتسبوت؛ الملف المقروء للجميع تسريب كالقابل للكتابة، فيُرفَض.

الحل: `sudo chmod 600 /etc/awacs.conf`.

## مفتاح ضبطته لا يُطبَّق، بلا رسالة

المعنى: قيمته فشلت في الفحص. الأرقام يجب أن تكون أعداداً صحيحة غير صفرية من سبعة أرقام على الأكثر؛ `NIGHT_START`/`NIGHT_END` يجب أن يكونا `HH:MM`؛ `RUN_DIR` يجب أن يبدأ بـ `/`. القيم الفاشلة تسقط للافتراضي بصمت عن قصد (الخطأ المطبعي لا يجب أن يُسقط الحارس).

الحل: افحص السطر في الملف. مدخلات `SAFETY_NET` تحتاج الشكل الدقيق `SAFETY_NET["Name"]="password"`.

## `missing tools: X Y - will try to install once online`

أين: `[ERROR]`، عند البداية.

المعنى: لم يجد `check_tools` الأداتَين X وY في `PATH`. الجرد يتبع النظام: `wpa_cli` على الصور القديمة، `nmcli` على صور NM، زائد `iw ip ping curl awk sed grep pgrep rfkill flock timeout stat date modprobe`.

ما يحدث بعدها: في الدورة الصحيحة الثالثة يشغّل `install_tools` أمر `apt-get install` مرة كل إقلاع في الخلفية. توقّع `installing missing tools: <packages>` ثم إما `tools installed: …` أو `tool install failed - still missing: … - install manually`. إن لم يكن في الجهاز `apt-get`: `no apt-get on this system - install manually: …`.

الحل إن فشل: ثبّت الحزم المذكورة يدوياً، أو انتظر الإقلاع التالي (علامة مرة-كل-إقلاع هي `/run/awacs/apt_tried`).

## `interface wlan0 not present - is the WiFi hardware alive?`

أين: `[ERROR]`، عند البداية.

المعنى: لم يجد `detect_if` أي كرت لاسلكي في `iw dev` فسقط إلى `wlan0`، وهو غير موجود أيضاً. راديو ميت، دونجل مفصول، تعريف ناقص، أو `iw` نفسه ناقص (حينها يسبقه سطر `missing tools: iw`).

الحل: افحص `iw dev` و`rfkill list` و`dmesg | grep -i brcm`. اضبط `AWACS_IF` إن كان للكرت اسم غير معتاد.

## `internet lost on wlan0 - engaging`

أين: `[WARN]`، مرة لكل انقطاع.

المعنى: `NET_FAIL_TICKS` دورة بلا نجاح أي درجة في `have_net`. يبدأ القتال ويتكرر كل دورة حتى يعود الإنترنت. ليس خطأً بذاته؛ اقرأ السطور التالية.

## `outage looks external (round N) — waiting, not rebooting`

أين: `[INFO]`، حتى ثلاث مرات لكل قتال.

المعنى: الراوتر يرد (أو NM في منتصف تحوّل)، فرابط الواي فاي يعمل والمشكلة فوق: المزوّد، WAN الراوتر، DNS عند الراوتر. أواكس يجرّب `SAFETY_NET` والمفتوحة مع ذلك لعل شبكة أخرى لها مزوّد مختلف، ثم ينتظر.

الحل: لا شيء على الجهاز. افحص الراوتر.

## `association refused - wrong password? (recovery continues, reboot stays off)`

أين: `[ERROR]`، لكل جولة قتال.

المعنى: على wpa شبكة مخزنة `TEMP-DISABLED` في `wpa_cli list_networks`؛ على NM فشل تفعيل بخطأ أسرار/مصادقة. السلّم يعمل مع ذلك؛ وساعة الريبوت معطَّلة.

الحل: صحّح كلمة السر في ضبط شبكتك أنت (`wpa_supplicant.conf` أو ملف NM). أواكس لا يعدّله أبداً.

## `fight round N: ME evidence (LINK_OK=0, gw unreachable, auth_failing=0)`

أين: `[DEBUG]` (يحتاج `DEBUG=yes`).

المعنى: صنّفت الجولة الانقطاع على أنه من الجهاز نفسه: شبكة مخزنة ظاهرة لا تُركَب، أو الراديو لا يرى شيئاً، أو القائمة المخزنة فارغة؛ لا راوتر؛ لا علامة كلمة سر. السلّم يعمل وساعة الريبوت مسلَّحة (على NM فقط حين يوافق `nm_me_settled`).

## `recover L1: radio bounce` / `recover L2: …` / `recover L3: …`

أين: `[WARN]`.

المعنى: سلّم الإنعاش يعمل، درجة لكل جولة: الراديو، خدمة الشبكة (`dhcpcd` أو NetworkManager)، تعريف الواي فاي (`brcmfmac`). سلّم يتكرر كل قتال لدقائق طويلة بلا `internet restored` هو عطل محلي حقيقي ويقود إلى الصمّام أدناه.

## `wedged Nmin with networks visible — rebooting (repeats per streak until cured)`

أين: `[ERROR]`، في اللوق المحلي فقط، قبل الريبوت مباشرة.

المعنى: أدلة «عندي» متصلة `REBOOT_AFTER_MIN` دقيقة، كل درجة جُرّبت، لا علامة كلمة سر، لا راوتر. الريبوت آخر العلاج. بعد الريبوت تبدأ السلسلة من الصفر؛ وإن نجا العطل من الريبوت يأتي التالي بعد سلسلة كاملة أخرى.

إن تكرر هذا: الخلل تحت أواكس — التعريف، مزوّد الطاقة، كارت SD، راوتر يبثّ ولا يعطي عناوين. `journalctl -b -1` و`dmesg` من الإقلاع السابق هما المكانان التاليان للنظر. رفع `REBOOT_AFTER_MIN` يباعد الريبوتات؛ لا يصلح السبب.

## `NetworkManager image but AWACS cannot drive it (unmanaged/no nmcli) - monitoring only`

أين: `[ERROR]`، عند البداية.

المعنى: NetworkManager يعمل أو مفعّل، لكن إما `nmcli` ناقص أو الكرت خارج الإدارة (حالة الكرت 10). أواكس يقف: يفحص الإنترنت كل 300 ثانية، يفرّغ المخزون، ويترك `install_tools` يعمل مرة. قتال كرت خارج الإدارة كان سيكون بلا أثر.

الحل لـ `nmcli` الناقص: انتظر التثبيت (يتبعه `nmcli is now installed - restarting as a full NetworkManager supervisor` ثم سطر بداية جديد)، أو `apt-get install --reinstall network-manager`.

الحل للكرت خارج الإدارة: ابحث في `/etc/NetworkManager/conf.d/` و`/etc/NetworkManager/NetworkManager.conf` عن `unmanaged-devices`، أو `nmcli device set wlan0 managed yes`. إعادة التشغيل التالية تعيد الاكتشاف وتسجّل `NetworkManager backend - AWACS supervises it (full capability)`.

## `NM is still trying - waiting it out`

أين: `[INFO]`، لكل جولة قتال على NM، وعند حدّ الدرجة.

المعنى: الكرت في نطاق اتصال NetworkManager — في بداية الجولة، أو من جديد حين يُقرأ NM بعد جمع الأدلة. أواكس يتنحّى: لا تجربة مرشحين، لا درجة، وساعة ME مصفَّرة. طبيعي على NM أثناء الانقطاع.

## `NetworkManager is connected, internet is not (round N) — router-side, no rung`

أين: `[INFO]`، على NM فقط.

المعنى: عند حدّ درجة أبلغ NM الحالة 100 (متصل، بعنوان) لكن `have_net` يفشل. هذه مشكلة الراوتر لا الجهاز؛ لا تعمل درجة والساعة مصفَّرة.

## `BUG: wpa_cli reached under nm backend: …`

أين: `[ERROR]`.

المعنى: مسار في الكود استدعى الدالة `wpa()` بينما النظام NetworkManager. هذه مصيدة ولا يجب أن تُطلِق أبداً. الاستدعاء يُرجع فشلاً ولا يُرسَل شيء إلى `wpa_cli`.

الحل: أبلغ عنها مع سطر اللوق؛ فهو يسمّي الوسائط.

## `scan failed - using previous results (if any)`

أين: `[WARN]`.

المعنى: `iw` و`iwlist` وجدول مسح النظام كلها أرجعت لا شيء بعد كل محاولة. بعد الإقلاع مباشرة يرد الراديو ببطء (أواكس يسمح أصلاً بست محاولات في أول ثلاث دقائق). إن استمر بينما الجهاز متصل فالراديو أو التعريف عليل؛ `iw dev wlan0 scan` يدوياً يُظهر الخطأ. `Device or resource busy` وحدها لم تعد تنتج هذا السطر: أواكس يقرأ جدول supplicant أو NM بدلاً منها. تُقدَّم الصورة القديمة ويُجدَّد ختمها (محاولة واحدة كل `SCAN_TTL`)؛ والمسح الفارغ الثالث على التوالي يسقطها — انظر المدخل التالي.

## `radio heard nothing on N scans in a row - previous results dropped`

أين: `[WARN]`، مرة لكل صمت.

المعنى: ثلاثة مسوح جديدة متتالية (`iw` و`iwlist` وجدول النظام) لم تسمع أي إشارة منارة. أُسقطت صورة المسح القديمة كي يتوقف القتال والأدوات وخانة الواي فاي عن عرض شبكات غير موجودة. الراديو السليم يسمع الجيران دائماً؛ فإن ظهر هذا السطر والجهاز ثابت في مكانه فالراديو أو تعريفه معلَّق — سيصنّفه القتال عطلاً في الجهاز نفسه، وبعد `REBOOT_AFTER_MIN` دقيقة من ذلك يعمل صمّام الريبوت. السطر لا يتكرر؛ وأول منارة تُسمَع من جديد تنهي السلسلة بصمت.

## `reporting: local | probe: none - signal mode | wifi cell: auto`

أين: `[INFO]`، بعد سطر البداية مباشرة.

المعنى: مفاتيح التقارير كما طُبِّقت: وجهة اللوق (والموقع)، هدف قياس الرفع، وضع خانة الواي فاي. `probe: none - signal mode` يقول إنه لا `SITE_URL` ولا `PROBE_URL`: لا QA للرفع، لا رقصة، واختيار الشبكة بالإشارة عند فقد الإنترنت. إن ضبطت المفاتيح في `/etc/awacs.conf` وما زلت ترى `local` فالملف لم يُطبَّق (المالك/الصلاحيات أعلاه) أو أن `SITE_URL` لم يجتز الفحص (رابط `http://` أو `https://` بسيط بلا مسافات).

## `LOG_TARGET asked for the site but SITE_URL is empty - running local-only`

أين: `[WARN]`، مرة عند البداية.

المعنى: كان `LOG_TARGET` هو `both` أو `remote` بلا `SITE_URL`. خُفِّضت الوجهة إلى `local`. اضبط `SITE_URL` أو اجعل `LOG_TARGET="local"` لإسكاته.

## `connected: X (signal mode - no upload probe target configured)` / `returned to preferred network: X (signal mode)`

أين: `[OK]`.

المعنى: وضع الإشارة (لا هدف قياس). أبقى القتال أقوى شبكة مخزنة ظاهرة أعطت إنترنت؛ والرجوع للمفضلة عاد للبيت بلا قياس. لا يذكر السطران سرعة لأن شيئاً لم يُقَس. `awacs.sh speed` في هذا الوضع يطبع `no probe target (signal mode)`: اضبط `SITE_URL` أو `PROBE_URL` للاختيار المقيس.

## `aasw.sh is still running - two WiFi authorities will fight; remove its rc.local line`

أين: `[WARN]`، عند البداية.

المعنى: السكربت السابق ما زال يُشغَّل من مكان ما. احذف سطره من `rc.local` وملفه.

## `REFUSING delete: 'name' is not an awacs crutch` / `… lives outside /run (owner file?)`

أين: `[ERROR]`، على NM فقط.

المعنى: طُلب حذف ملف لا يحمل اسم `awacs-crutch-*`/`awacs-safety-*` أو لا يعيش تحت `/run/NetworkManager/system-connections/`. الحذف لم يحدث. هذا آخر حرس قانون لا-بلوك؛ لا يجب أن يُطلِق أبداً.

## `no challenger beat the incumbent - staying on X`

أين: `[OK]`.

المعنى: قاس تقييمٌ الشبكات المخزنة الأخرى ولم تتفوّق أي منها على الحالية بالنسبة المطلوبة. عاد الجهاز إلى حيث كان. ليس خطأً.

## `preferred network too slow (N kbps) - benching it, going back`

أين: `[WARN]`.

المعنى: عادت الشبكة الأعلى أولوية، انتقل أواكس إليها وقاسها تحت الحد، فعاد إلى الشبكة السابقة ولن يجرّب تلك مرة أخرى لثلاث فترات تبريد.

## صندوق الأدوات يطبع صندوق ROOT ACCESS REQUIRED

المعنى: `status` و`networks` و`evaluate` و`scan` و`speed` تحتاج root (تقرأ supplicant أو NM ومجلد الحالة الخاص). فقط `check` و`help` تعملان بلا صلاحيات.

## `usage: awacs.sh …` ورمز الخروج 1

المعنى: الكلمة مكتوبة خطأً. الفحص يجري قبل بوابة root كي يبقى الخطأ المطبعي ونسيان `sudo` متمايزَين.

## نسخة أخرى تعمل بالفعل (صندوق INSTANCE ERROR)

المعنى: شغّلت الحارس يدوياً بينما الخدمة تشغّله أصلاً. القفل `flock` على `/run/awacs/lock`؛ والصندوق يُظهر رقم العملية العاملة. استعمل كلمات صندوق الأدوات بدلاً من ذلك؛ فهي تعمل بجانب الحارس.

## لوق الموقع لا يُظهر شيئاً رغم أن `LOG_TARGET` هو `both`

افحص بالترتيب: `SITE_URL` مضبوط ويمكن الوصول إليه من الجهاز (`curl -s -o /dev/null -w '%{http_code}\n' --data-urlencode probe=1 "$SITE_URL/$DEVICE_ID/device_api.php"` يجب أن يطبع `400`)؛ ملف الضبط مطبَّق فعلاً (المالك/الصلاحيات أعلاه)؛ المخزون `/run/awacs/spool` — الأسطر المنتظرة فيه تُسلَّم ~30 ثانية بعد ثبوت صحة الإنترنت ويُعاد إرسالها كل ~5 دقائق.

## خانة الواي فاي لا تُظهر سرعة

طبيعي. السرعة تُقاس في لحظات القرار فقط (قياس مرشح في قتال، تقييم بعد رفع بطيء، الوصول إلى شبكة مفضلة)، وتُعرَض فقط ما دام الجهاز على الشبكة التي قيست عليها. `0` في الحقل الأول يعني «لا قياس لهذه الشبكة بعد».

</div>
