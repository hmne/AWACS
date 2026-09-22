<div dir="rtl">

# استكشاف الأخطاء

كل مدخل هنا سطر يطبعه السكربت، ومستواه، وما يعنيه، وما تفعله. السجل المحلي هو `/var/log/awacs.log`؛ وصيغة السطر المحلي `[LEVEL][dd/mm HH:MM:SS] message`. يصل الخرج القياسي للأخطاء من الحارس إلى `journalctl -u awacs` تحت `systemd` ولا يصل إلى أي مكان تحت حلقة `rc.local`؛ فأفضل طريقة لرؤية رفضَي ملف الضبط أدناه هي تشغيل `sudo awacs.sh status` على الطرفية، لأن كل تشغيل بصلاحيات `root` يقرأ ملف الضبط.

## الضبط

### `awacs: IGNORING /etc/awacs.conf (not owned by root — chown root: it)`

الخرج القياسي للأخطاء، عند كل تشغيل بصلاحيات `root`. مالك ملف الضبط ليس `root`، وذلك عادة بعد استعادته بمستخدم آخر؛ يعمل الحارس بالافتراضيات (لا `SAFETY_NET` ولا موقع). الحل: `sudo chown root:root /etc/awacs.conf`.

### `awacs: IGNORING /etc/awacs.conf (group/world can access it — chmod 600 it)`

الخرج القياسي للأخطاء، عند كل تشغيل بصلاحيات `root`. الصلاحيات تحوي بتات للمجموعة أو للآخرين (`0644` أو `0640`)؛ وملف الضبط الذي يحمل كلمات سر نقاط الاتصال يُرفض حين يستطيع غيرك قراءته أو الكتابة فيه. الحل: `sudo chmod 600 /etc/awacs.conf`.

### مفتاح ضبطته لا يُطبَّق، بلا رسالة

القيمة لم تجتز الفحص والافتراضي هو المستعمل؛ والسقوط الصامت مقصود، فالخطأ المطبعي يجب ألا يوقف الحارس. قاعدة كل مفتاح في [configuration.md](configuration.md). مدخلات `SAFETY_NET` تحتاج الشكل الدقيق `SAFETY_NET["Name"]="password"`. الحل: صحّح السطر وأعد تشغيل الحارس.

### `LOG_TARGET asked for the site but SITE_URL is empty - running local-only`

`WARN`، السجل المحلي، مرة عند البداية. كان `LOG_TARGET` هو `both` أو `remote` بلا `SITE_URL`؛ فخُفِّضت الوجهة إلى `local`. الحل: اضبط `SITE_URL`، أو اجعل `LOG_TARGET="local"`.

### `reporting: local | probe: none - signal mode | wifi cell: auto`

`INFO`، السجل المحلي، بعد سطر البداية: مفاتيح التقارير كما طُبِّقت. مع موقع مضبوط تتبع وجهةَ السجل علامةُ `->` ثم عنوان الموقع، ويسمّي `probe:` هدف القياس. `probe: none - signal mode` يعني أن لا `SITE_URL` ولا `PROBE_URL` مضبوط: لا قياس للرفع ولا تبديل بحسب السرعة. إن ضبطت المفاتيح وما زلت تقرأ `local` فملف الضبط لم يُطبَّق (الرفضان أعلاه) أو أن `SITE_URL` لم يجتز الفحص.

## البداية

### `missing tools: iw nmcli - will try to install once online`

`ERROR`، عند البداية. الأدوات المسمّاة ليست في `PATH`؛ والجرد هو `iw ip ping curl awk sed grep pgrep rfkill flock timeout stat date modprobe` زائد `wpa_cli` (على `wpa`) أو `nmcli` (على `nm`). في الدورة الصحيحة الثالثة يعمل `apt-get install` واحد في الخلفية، مرة كل إقلاع (العلامة `/run/awacs/apt_tried`): `installing missing tools: <packages>`، ثم `tools installed: <packages>` أو `tool install failed - still missing: <tools> - install manually`؛ وبلا `apt-get`: `no apt-get on this system - install manually: <tools>`. أسماء الحزم: `wpasupplicant` و`network-manager` و`iproute2` و`iputils-ping` و`mawk` و`procps` و`util-linux` و`coreutils` و`kmod`؛ وسائر الأدوات تُثبَّت باسمها. لا يوجد مفتاح لتعطيل المحاولة. الحل إن فشلت: ثبّت الحزم يدوياً؛ وتتكرر المحاولة عند الإقلاع التالي.

### `interface wlan0 not present - is the WiFi hardware alive?`

`ERROR`، عند البداية. لا واجهة لاسلكية في `iw dev`، ولا `wlan0` أيضاً، ويمضي الحارس باسم لا جهاز خلفه: راديو ميت، أو محوّل مفصول، أو تعريف ناقص، أو `iw` نفسه ناقص (وحينها يليه `missing tools: iw`). الحل: افحص `iw dev` و`rfkill list` و`dmesg | grep -i brcm`؛ واضبط متغير البيئة `AWACS_IF` إن كان للواجهة اسم غير معتاد.

### `NetworkManager image but AWACS cannot drive it (unmanaged/no nmcli) - monitoring only`

`ERROR`، عند البداية. `NetworkManager` يعمل أو مفعّل، وإما أن `nmcli` ناقص أو أن الواجهة خارج الإدارة (حالة الجهاز 10). يتوقف الحارس عن التدخل: يفحص الإنترنت كل 300 ثانية، ويفرّغ المخزون المؤقت، ويترك تثبيت الأدوات يعمل مرة؛ ولا يعمل أي إنعاش. لـ `nmcli` الناقص انتظر التثبيت أو شغّل `apt-get install --reinstall network-manager` بنفسك: يتبعه `nmcli is now installed - restarting as a full NetworkManager supervisor`، فيخرج الحارس لتعيد حلقة التشغيل إطلاقه، وتسجّل البداية التالية `NetworkManager backend - AWACS supervises it (full capability)`. للواجهة خارج الإدارة ابحث عن `unmanaged-devices` في `/etc/NetworkManager/NetworkManager.conf` و`/etc/NetworkManager/conf.d/`، أو شغّل `nmcli device set wlan0 managed yes`، ثم أعد تشغيل الحارس؛ فالحارس المتوقف لا يعيد الاكتشاف بنفسه.

### `aasw.sh is still running - two WiFi authorities will fight; remove its rc.local line`

`WARN`، عند البداية. تعمل عملية يحوي سطر أمرها `/usr/local/bin/aasw`: حارس واي فاي أقدم ينازع على الراديو. الحل: احذف سطر تشغيله من `/etc/rc.local` واحذف الملف.

## الانقطاع والإنعاش

### `internet lost on wlan0 - engaging`

`WARN`، مرة لكل انقطاع. فشل `NET_FAIL_TICKS` فحصاً متتالياً للإنترنت؛ يبدأ الإنعاش ويتكرر كل دورة حتى يختم `internet restored: <network>` الانقطاع. ليس خطأً بذاته؛ اقرأ الأسطر التالية.

### `internet answers late, not never - slow link, no recovery (${NET_FAIL_TICKS} quick checks timed out)`

`INFO`، الملف المحلي فقط، مرة واحدة على الأكثر في الانقطاع. انتهت مهلة `NET_FAIL_TICKS` فحصاً سريعاً متتالياً، لكن الوصلة نفسها كانت حية (البوابة الافتراضية ردت، أو ذكرها جدول الجيران في النواة بحالة `REACHABLE`)، ونال فحص صبور واحد، بثلاث رسائل `ping` لكل هدف وحد 8 ثوانٍ لطلبات HTTP، جواباً. الوصلة بطيئة أو مزدحمة لا مقطوعة: لا يُكتب سطر فقد، ولا يجري إنعاش، وتُحسب الدورة سليمة. الحل: لا شيء. وتكراره يعني وصلة تصل أجوبتها بعد الثانيتين أو الثلاث التي ينتظرها الفحص السريع، غالباً تحت رفع مزدحم؛ ارفع `TICK` أو `NET_FAIL_TICKS` لتنال وصلة كهذه وقتاً أطول قبل أن يبدأ الحارس الإنعاش أصلاً.

### `outage looks external (round 1) — waiting, not rebooting`

`INFO`، حتى ثلاث مرات في كل إنعاش. العطل ليس في الجهاز: الموجّه يرد، أو ارتبطت شبكة وحصلت على عنوان في هذه الجولة، أو يسمع الراديو شبكات ليس بينها أي من المخزنة، أو كان `NetworkManager` على `nm` ما زال يعمل على الجهاز في بداية الجولة (السطر السابق `NM is still trying`). المشكلة في الأعلى (مزوّد الخدمة، أو جانب `WAN` في الموجّه، أو `DNS` عند الموجّه) أو أن الشبكات المخزنة خارج المدى. يُصفَّر مؤقت إعادة التشغيل؛ وتُجرَّب شبكات الطوارئ والشبكات المفتوحة مع ذلك، ثم تنتظر الجولة 20 ثانية. الحل: لا شيء على الجهاز. افحص الموجّه؛ وإن لم تكن أي من شبكاتك ظاهرة فافحص الموضع.

### `association refused - wrong password? (recovery continues, reboot stays off)`

`ERROR`، في كل جولة إنعاش. على `wpa` توجد شبكة مخزنة بعلامة `TEMP-DISABLED` في `wpa_cli list_networks`؛ وعلى `nm` فشل تفعيل بخطأ يذكر الأسرار أو المصادقة أو `802-1X` أو إدارة المفاتيح أو المفتاح المشترك. يستمر سلّم الإنعاش؛ ويُصفَّر مؤقت إعادة التشغيل كلما ظهرت هذه العلامة. الحل: صحّح كلمة السر في ضبطك أنت (`wpa_supplicant.conf` أو ملف تعريف `NetworkManager`)؛ فالحارس لا يعدّله أبداً.

### `fight round 1: ME evidence (LINK_OK=0, gw unreachable, auth_failing=0)`

`DEBUG`، السجل المحلي فقط، ما لم يُضبط `DEBUG="no"` في ملف الضبط أو `AWACS_DEBUG=no` في البيئة. صنّفت الجولة الانقطاع على أنه من الجهاز نفسه: الموجّه لا يرد، ولم ترتبط أي شبكة وتحصل على عنوان في هذه الجولة، وشبكة مخزنة ظاهرة لا يمكن استعمالها، أو المسح فارغ، أو القائمة المخزنة فارغة. يعمل السلّم ويبدأ مؤقت إعادة التشغيل (على `nm` لا يبدأ إلا بعد أن يستسلم `NetworkManager`؛ انظر مدخل إعادة التشغيل).

### `recover L1: radio bounce`

`WARN`، الجولة الأولى من إنعاش صُنّف انقطاعه على أنه في الجهاز؛ درجة واحدة في كل جولة. تسجّل الجولة الثانية `recover L2: restart dhcpcd (respawns the REAL per-interface supplicant)` (على `wpa`) أو `recover L2: re-kick NetworkManager on wlan0` (على `nm`)؛ وتسجّل الجولة الثالثة `recover L3: reload brcmfmac firmware (the 3-second cure a wedge needs)` أو `recover L3: restart NetworkManager + reload WiFi firmware`. على `wpa` الدرجات هي إنزال الواجهة ورفعها، ثم إعادة تشغيل `dhcpcd` (أو `wpa_supplicant`)، ثم إعادة تحميل وحدة `brcmfmac`؛ وعلى `nm` حظر `rfkill` وفكّه (أو `nmcli radio wifi`)، ثم `nmcli device reapply` يتبعه فصل ووصل، ثم إعادة تشغيل `NetworkManager` مع إعادة تحميل الوحدة. تسرد [how-it-works.md](how-it-works.md) كل أمر. إعادة تحميل الوحدة لا تفعل شيئاً على عتاد لا يستعمل ذلك التعريف. السلّم الذي يتكرر لدقائق طويلة بلا `internet restored` يحقق شرط إعادة التشغيل أدناه.

### `wedged 30min with networks visible — rebooting (repeats per streak until cured)`

`ERROR`، السجل المحلي فقط، قبل إعادة التشغيل مباشرة؛ لا يصل السطر إلى الموقع أبداً لأن الشبكة منقطعة والنسخة المخزونة كانت ستزول مع إعادة التشغيل (`/run` على `tmpfs`). استمرت أدلة العطل في الجهاز `REBOOT_AFTER_MIN` دقيقة متصلة (افتراضياً 30). يُصفَّر المؤقت بأي دورة صحيحة أو تصنيف خارجي أو علامة كلمة سر خاطئة، وعلى `nm` بأي رصد لـ `NetworkManager` وهو ما زال يعمل؛ وعلى `nm` تشترط إعادة التشغيل أيضاً أن يكون `NetworkManager` قد استسلم: الحالة 30 (منفصل) أو 120 (فاشل) في تصنيفين متتاليين، أو تعذّر الوصول إلى `nmcli` بعد إعادة التشغيل في الدرجة الثالثة. لا يمكن تعطيل إعادة التشغيل؛ `REBOOT_AFTER_MIN` يؤخرها فقط. إن تكرر ذلك فالخلل تحت الحارس: التعريف، أو مزوّد الطاقة، أو بطاقة `SD`، أو موجّه يبثّ ولا يعطي عناوين. اقرأ `journalctl -b -1` و`dmesg` من الإقلاع السابق.

### `NM is still trying - waiting it out`

`INFO`، على `nm`، في بداية الجولة ومرة أخرى بعد جمع الأدلة. الجهاز في حالات الاتصال عند `NetworkManager` (من 40 إلى 90، أو 110): لا تُجرَّب الشبكات المخزنة، ولا تعمل درجة، ويُصفَّر مؤقت إعادة التشغيل. في بداية الجولة تسلك الجولة المسار الخارجي (يتبعه `outage looks external`، وتُجرَّب شبكات الطوارئ والمفتوحة مع ذلك، وتنتظر الجولة 20 ثانية)؛ وبعد جمع الأدلة لا تنتظر الجولة إلا 20 ثانية. طبيعي على `nm` أثناء الانقطاع.

### `NetworkManager is connected, internet is not (round 1) — router-side, no rung`

`INFO`، على `nm`، بعد جمع الأدلة: يبلّغ `NetworkManager` الحالة 100 (متصل، بعنوان) بينما يفشل فحص الإنترنت، وهذه مشكلة الموجّه. لا تعمل درجة، ويُصفَّر مؤقت إعادة التشغيل، وتُجرَّب شبكات الطوارئ والمفتوحة مع ذلك.

### `trying emergency networks (2 listed)`

`INFO`، بعد فشل الشبكات المخزنة؛ يغيب حين يكون `SAFETY_NET` فارغاً. يُجرَّب كل مدخل بدوره، ظهر في المسح أم لا، نحو `ASSOC_WAIT` ثانية لكل محاولة على `wpa` (افتراضياً 25) وحتى ثلاثة أمثال ذلك على `nm`؛ والنجاح يسجّل `connected to EMERGENCY network: <name>`. على `wpa` يُتخطّى الاسم الذي يحوي شرطة مائلة عكسية أو علامة اقتباس مزدوجة، وكلمة السر التي تحوي علامة اقتباس مزدوجة؛ وعلى `nm` يجب أن تكون كلمة السر من 8 إلى 63 حرفاً أو 64 رقماً سداسياً عشرياً.

### `trying open networks as last resort`

`INFO`، بعد فشل شبكات الطوارئ؛ يغيب ما لم يكن `OPEN_NETWORKS` هو `yes`. تُجرَّب الشبكات بلا تشفير، الأقوى أولاً، مع تخطي الإشارات الأضعف من -80 dBm (على `wpa`) أو من 25 % (على `nm`)؛ وعلى `wpa` يُتخطّى الاسم الذي يحوي حروفاً غير `ASCII`. النجاح يسجّل `connected to OPEN network: <name>`. يعيش المدخل المؤقت في `wpa_supplicant` الحي أو تحت `/run/NetworkManager/system-connections/`، ويُزال حين يعود الجهاز إلى شبكة مخزنة، أو عند الإنعاش التالي، أو عند بداية الحارس التالية.

## الراديو والمسح

### `scan failed - using previous results (if any)`

`WARN`. أعاد `iw dev wlan0 scan` لا شيء بعد كل محاولة (ثلاث محاولات بينها 3 ثوانٍ، وست في الدقائق الثلاث الأولى بعد الإقلاع)، وأعاد `iwlist` وجدول النظام الخلفي نفسه (`wpa_cli scan_results` أو `nmcli device wifi list`) لا شيء أيضاً. تُحفظ الصورة السابقة ويُجدَّد ختمها الزمني، فيُسأل الراديو من جديد مرة كل `SCAN_TTL`. الرد `Device or resource busy` لا يُعاد المسح بعده: بعد 3 ثوانٍ يُقرأ `iwlist` وجدول النظام الخلفي بدلاً منه، ولا يظهر السطر إلا حين يكونان فارغين أيضاً. تشغيل `awacs.sh scan` يدوياً يسجّل السطر محلياً فقط. الحل إن استمر والجهاز متصل: `iw dev wlan0 scan` يدوياً يُظهر خطأ التعريف.

### `radio heard nothing on 3 scans in a row - previous results dropped`

`WARN`، مرة واحدة، لحظة إسقاط الصورة. ثلاثة مسوح متتالية، بكل مصدر في كل منها، لم تسمع أي شبكة؛ تُفرَّغ الذاكرة المؤقتة كي يتوقف الإنعاش وصندوق الأدوات وخانة الواي فاي عن عرض شبكات غير موجودة. المسح الفارغ دليل على أن العطل في الجهاز (الراديو السليم يسمع جيرانه)؛ وبعد `REBOOT_AFTER_MIN` دقيقة منه يتحقق شرط إعادة التشغيل. أول مسح يسمع شيئاً ينهي السلسلة بصمت. الحل: `rfkill list`، و`iw dev wlan0 scan` يدوياً، و`dmesg`. إن لم يتحرك الجهاز والجيران موجودون فالراديو أو تعريفه عالق.

## اختيار الشبكة

### `connected: HomeNet (signal mode - no upload probe target configured)`

`OK`؛ ويسجّل الرجوع إلى الشبكة المفضلة `returned to preferred network: HomeNet (signal mode)`. لا هدف للقياس: أبقى الإنعاش أقوى شبكة مخزنة أوصلت الإنترنت، ومضى الرجوع إلى الشبكة المفضلة بلا قياس. يطبع `awacs.sh speed` العبارة `no probe target (signal mode)`. للاختيار المقيس اضبط `SITE_URL` أو `PROBE_URL`.

### `sustained slow upload (150 kbps) - evaluating known networks`

`WARN`؛ ومع بث حي يعمل يكون السطر `live stream starving (12 kbps) - evaluating known networks`. بقيت العيّنة السلبية من عدّادات النواة (3 ثوانٍ) بين 20 كيلوبت/ث والحد الحالي (`MIN_UP_KBPS` نهاراً و`NIGHT_MIN_UP_KBPS` ليلاً) لمدة `UP_STRIKES` دورة متتالية، وانقضت فترة التهدئة منذ آخر تقييم؛ وصيغة البث تحتاج عملية `raspistill` تخدم `live_raw` أو `preview.jpg` أو `capture.jpg`، أو رفع `curl` يحوي `upfile=@`، وتدفقاً بين 5 كيلوبت/ث و`STREAM_MIN_KBPS`. يتبع ذلك قياس واحد للشبكة الحالية؛ فإن قاست تحت الحد تُقاس الشبكات المخزنة الظاهرة الأخرى (`candidate [<id>] <name> uploads at <n> kbps` لكل منها) والنتيجة `connected: <name> (upload <n> kbps)` أو المدخل التالي. الحل إن تكرر في كل فترة تهدئة: الشبكة بطيئة بالنسبة إلى الحد الذي ضبطته؛ عدّل `MIN_UP_KBPS` أو الحد الليلي، أو اقبل التبديل.

### `no challenger beat the incumbent - staying on HomeNet`

`OK`. قاس تقييمٌ الشبكات المخزنة الأخرى ولم تتفوق أي منها على الحالية بالزيادة المطلوبة (`SWITCH_GAIN_PCT` نهاراً و`NIGHT_GAIN_PCT` ليلاً)؛ فعاد الجهاز إلى حيث كان. ليس خطأً.

### `preferred network too slow (120 kbps) - benching it, going back`

`WARN`. ظهرت شبكة مخزنة أعلى أولوية في فحصين متتاليين (بينهما `PREF_CHECK`)، فانتقل الحارس إليها (يسبق هذا السطرَ `higher-priority network visible - trying to go home`)، وقاسها تحت الحد، فعاد. لا تُجرَّب تلك الشبكة مرة أخرى لثلاث فترات تهدئة.

## حواجز لا يجب أن تعمل أبداً

### `BUG: wpa_cli reached under nm backend: ...`

`ERROR`، السجل المحلي فقط. استدعى مسار في الكود مساعد `wpa` بينما النظام الخلفي هو `NetworkManager`؛ يُرجع الاستدعاء فشلاً ولا يصل شيء إلى `wpa_cli`. أبلغ عنه مع سطر السجل؛ فهو يسمّي الوسائط.

### `REFUSING delete: 'name' is not an awacs crutch`

`ERROR`، السجل المحلي فقط، على `nm`؛ والصيغة الثانية `REFUSING delete: 'name' lives outside /run (owner file?)`. طُلب حذف ملف تعريف لا يحمل اسم `awacs-crutch-*` أو `awacs-safety-*`، أو ليس ملفه تحت `/run/NetworkManager/system-connections/`؛ ولم يحدث الحذف. هذا آخر حاجز أمام ملفات تعريفك أنت. أبلغ عنه مع سطر السجل.

## صندوق الأدوات

### صندوق `ROOT ACCESS REQUIRED`

`status` و`networks` و`evaluate` و`scan` و`speed` تحتاج `root`: فهي تقرأ `wpa_supplicant` أو `NetworkManager` ومجلد الحالة الخاص. فقط `check` و`help` تعملان بلا صلاحيات.

### `usage: awacs.sh [status|networks|evaluate|scan|speed|check|help|-d]   (no argument = daemon)` ورمز الخروج 1

الكلمة مكتوبة خطأً. يجري الفحص قبل بوابة `root`، فيبقى الخطأ المطبعي ونسيان `sudo` متمايزَين.

### صندوق `INSTANCE ERROR`

شغّلت الحارس يدوياً بينما تحمل نسخة أخرى القفل (`flock` على `/run/awacs/lock`)؛ ويُظهر الصندوق رقم عملية تلك النسخة. بلا طرفية تخرج النسخة الخاسرة بالرمز 0 بصمت. استعمل كلمات صندوق الأدوات بدلاً من ذلك؛ فهي تعمل بجانب الحارس بلا أخذ القفل.

### `awacs.sh speed` يطبع `0 kbps — probe failed`

لم يقبل هدف القياس الرفع ضمن المهلة، لا مع `curl` ولا مع بديله `wget`. افحص الهدف باختبار `400` في [integration.md](integration.md). أما `no probe target (signal mode)` فيعني أن لا `SITE_URL` ولا `PROBE_URL` مضبوط.

## أعراض بلا سطر خاص بها

### `awacs.sh status` يبلّغ عن الحارس `NOT running`

يقرأ صف `daemon` القيمة `running (pid N)` حين يكون رقم العملية المكتوب في `/run/awacs/lock` حياً وسطر أمره يسمّي `awacs`، و`NOT running` فيما عدا ذلك. افحص المشغّل: `systemctl status awacs`، أو سطر `/etc/rc.local` مع `pgrep -af awacs.sh`؛ ثم `journalctl -u awacs` لحالة الخروج، والسجل المحلي لمعرفة إلى أين وصلت البداية الأخيرة.

### سجل الموقع لا يُظهر شيئاً رغم أن `LOG_TARGET` هو `both`

افحص بالترتيب. نقطة الاستقبال ترد من الجهاز: `curl -s -o /dev/null -w '%{http_code}\n' --data-urlencode probe=1 "$SITE_URL/$DEVICE_ID/receiver.php"` (أو اسم `SITE_API`) يجب أن يطبع `400`. ملف الضبط مطبَّق: لا رفض في الخرج القياسي للأخطاء، وسطر `reporting:` يسمّي الموقع. الأسطر المنتظرة في المخزون المؤقت `/run/awacs/spool` تُسلَّم بعد نحو 30 ثانية من ثبوت صحة الإنترنت ويُعاد إرسالها كل 5 دقائق تقريباً. ثم اقرأ `log/log.txt` عند المستقبِل على الخادم.

### أسطر سجل الموقع بالعربية

مقصود: يحمل سطر الموقع النص العربي للحدث حين يكون للبرنامج نص عربي له؛ ويحمل الملف المحلي السطر الإنجليزي. لا يوجد مفتاح لذلك.

### سطر البداية يتكرر كل 10 ثوانٍ

يخرج الحارس بعد قليل من `AWACS 1.0 starting on wlan0 (device mydevice)` وتعيد حلقة التشغيل (`rc.local` أو `Restart=always`) إطلاقه بعد 10 ثوانٍ. يُظهر `journalctl -u awacs` حالة الخروج؛ وتُظهر الأسطر المحلية بين سطرَي بداية إلى أين وصل. المشغّل الثاني لا ينتج هذا العرض: النسخة التي تخسر القفل تخرج قبل أن تسجّل أي شيء.

### مشغّلان اثنان

يعمل الحارس من `/etc/rc.local` ومن `awacs.service` معاً. تخسر النسخة الثانية القفل وتخرج بالرمز 0 بلا سطر سجل ويُعاد إطلاقها كل 10 ثوانٍ: يُظهر `journalctl -u awacs` بداية وخروجاً نظيفاً كل 10 ثوانٍ، أو يُظهر `pgrep -af awacs.sh` نسخة ليست العملية الرئيسية للوحدة. الحل: أبقِ مشغّلاً واحداً.

### خانة الواي فاي لا تُظهر سرعة

طبيعي. تُقاس السرعة في لحظات القرار فقط (مرشح أثناء الإنعاش، أو تقييم بعد رفع بطيء، أو الوصول إلى شبكة مفضلة)، وتُعرض فقط ما دام الجهاز على الشبكة التي قيست عليها؛ و`0` في الحقل الأول يعني أنه لا قياس لهذه الشبكة بعد.

## أسطر أخرى

أسطر بلا مدخل أعلاه، بقيم نموذجية. تحمل أسطر الموقع النص العربي للحدث نفسه.

| السطر | المستوى | متى |
| --- | --- | --- |
| `AWACS 1.0 starting on wlan0 (device mydevice)` | `INFO` | كل بداية للحارس. |
| `stealth mode active (icmp hidden, avahi stopped)` | `INFO` | البداية مع `STEALTH_MODE="yes"`. |
| `day profile active (floor 400 kbps)` | `INFO` | الدورة الأولى نهاراً، ثم عند `NIGHT_END` (مع `NIGHT_MODE="yes"`). |
| `night profile active (floor 200 kbps)` | `INFO` | الدورة الأولى ليلاً، ثم عند `NIGHT_START`. |
| `internet restored: HomeNet` | `OK` | عاد الإنترنت بعد فقده. |
| `connected to EMERGENCY network: MyPhone` | `OK` | أوصلت شبكة طوارئ الإنترنت. |
| `connected to OPEN network: CafeFree` | `OK` | أوصلت شبكة مفتوحة الإنترنت. |
| `candidate [3] OfficeNet uploads at 850 kbps` | `INFO` | كل مرشح مقيس. |
| `connected: OfficeNet (upload 850 kbps)` | `OK` | أُخذ أفضل مرشح مقيس. |
| `higher-priority network visible - trying to go home` | `INFO` | رصدان متتاليان لشبكة مفضلة. |
| `returned to preferred network: HomeNet (upload 900 kbps)` | `OK` | اجتازت الشبكة المفضلة القياس. |

أسطر `DEBUG` أخرى (`scan: 1/3 tries used` و`connect_id: activating ...` و`QA: flow=...` و`best_pref_id: ...` و`quick check timed out under load (sent ${sent} B during it) - patient check passed` و`sent ${sent} B during the failed quick check, the patient check failed too - counting it` و`gentle open skipped: the link is alive (gateway reachable) - the outage is upstream`) تتتبع القرارات في الملف المحلي وتُسكَت بـ `DEBUG="no"`.

</div>
