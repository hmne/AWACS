<div dir="rtl">

# القدرات

ما يفعله `awacs.sh` مجمَّعاً بحسب المجال. القيم الافتراضية بين قوسين هي قيم السكربت؛ ويتقدّم عليها `/etc/awacs.conf` ([configuration.md](configuration.md)). أسطر السجل منقولة كما يطبعها البرنامج؛ و`N` و`NAME` و`ID` تعني الرقم واسم الشبكة ومعرّفها التي يملؤها السكربت، و`wlan0` اسم الواجهة.

## الاتصال والإنعاش

فحص الإنترنت. كل `TICK` ثانية (10): `ping` إلى 8.8.8.8، ثم `ping` إلى 1.1.1.1، ثم طلب HTTP إلى `connectivitycheck.gstatic.com/generate_204` يجب أن يرد بـ 204، ثم، حين يُضبَط `SITE_URL`، طلب `POST` إلى نقطة استقبال الموقع يجب أن يرد بـ 400. بوابة الدخول ترد بـ 200 أو 302 فتُحسَب انقطاعاً. وللخطوات الأربع نفسها صيغة صبورة تُستعمل حيث تُقرأ الوصلة المشغولة خطأً: ثلاث رسائل `ping` لكل هدف بفاصل 0.3 ثانية وانتظار 5 ثوانٍ لكل منها، وحد 8 ثوانٍ لطلبَي HTTP. ولا يُعذَر الفحص السريع الفاشل بفحص صبور إلا حين تكون الواجهة قد أرسلت 16384 بايت أو أكثر أثناء فشله، ومرة واحدة في الانقطاع الواحد.

بدء الإنعاش. بعد `NET_FAIL_TICKS` (3) فحوص فاشلة متتالية يسجّل الحارس `internet lost on wlan0 - engaging` مرة واحدة ويبدأ الإنعاش، ويكرره كل دورة حتى `internet restored: NAME`. وفي تلك الدورة، ما دامت البوابة ترد ولم يفشل فحص صبور في هذا الانقطاع، يجري فحص صبور واحد أولاً: فإن نجح لم يُهدم شيء وسجّل الملف المحلي `internet answers late, not never - slow link, no recovery (${NET_FAIL_TICKS} quick checks timed out)`. ويبدأ الإنعاش بعد 40 إلى 63 ثانية من الفقد على وصلة صمتت بوابتها، وبعد نحو 72 إلى 83 ثانية على وصلة ما زال موجّهها يرد. الحارس الذي يبدأ بلا إنترنت يبدأ الإنعاش فوراً.

الافتتاح الهادئ. كل إنعاش يعيد تفعيل كل الشبكات المخزنة، ويعيد تسليح البحث عن الشبكات المخفية، ويطلب من الطبقة الأساسية إعادة الارتباط، وينتظر حتى `ASSOC_WAIT` ثانية (25) ارتباطاً وعنوان IPv4 قبل هدم أي شيء. وما دامت البوابة ترد يتخطى الإنعاش الأول من الانقطاع إعادة الارتباط ويبقي الارتباط الحي: تُستثنى الشبكة التي عليها الجهاز من المرشحين وهي التي يعود إليها، أما الإنعاش الثاني في الانقطاع نفسه فيعيد الارتباط على أي حال. والشبكة التي يركبها الجهاز فعلاً ومعه عنوان تُثبَت كما هي ولا يُعاد تفعيلها أبداً.

الاختيار بالقياس. تُفعَّل كل شبكة مخزنة ظاهرة بدورها وتُقاس برفع `PROBE_KB` (200) كيلوبايت إلى `PROBE_URL`، أو إلى نقطة استقبال الموقع حين يكون فارغاً، حتى ترفع إحداها بأربعة أمثال الحد الأدنى: `candidate [ID] NAME uploads at N kbps`. تُبقى الأفضل: `connected: NAME (upload N kbps)`. قوة الإشارة وحدها لا تقرر أبداً.

سلّم الإنعاش. درجة واحدة في كل جولة، وكل درجة تستهدف طبقة مختلفة. على `wpa`: `recover L1: radio bounce` (إنزال الواجهة ورفعها)، `recover L2: restart dhcpcd (respawns the REAL per-interface supplicant)`، `recover L3: reload brcmfmac firmware (the 3-second cure a wedge needs)`. على `nm`: `recover L1: radio bounce` (مفتاح `rfkill` الخاص بالواجهة نفسها)، `recover L2: re-kick NetworkManager on wlan0` (`nmcli device reapply` ثم فصل ووصل)، `recover L3: restart NetworkManager + reload WiFi firmware`.

شبكات الطوارئ. مدخلات `SAFETY_NET` (اسم وكلمة سر في `/etc/awacs.conf`) تُجرَّب بعد الشبكات المخزنة وقبل أي شبكة مفتوحة، سواء أظهرها المسح أم لا: `trying emergency networks (N listed)` ثم `connected to EMERGENCY network: NAME`.

الشبكات المفتوحة. مع `OPEN_NETWORKS="yes"` (الافتراضي) تأتي الشبكات المفتوحة أخيراً، محاولة واحدة لكل اسم، مع تجاوز الإشارات تحت -80 dBm (`wpa`) أو 25 % (`nm`): `trying open networks as last resort` ثم `connected to OPEN network: NAME`.

المدخلات المؤقتة. شبكة الطوارئ أو الشبكة المفتوحة مدخل مؤقت: على `wpa` معرّف شبكة في `supplicant` الحي لا يُحفَظ أبداً؛ وعلى `nm` ملف مفاتيح تحت `/run/NetworkManager/system-connections/` اسمه `awacs-crutch-*` أو `awacs-safety-*`، بـ `autoconnect=false` وصلاحيات 0600. يُكتَب معرّفه في `/run/awacs/open_id` قبل المحاولة، فيحذفه الحارس التالي إن مات هذا؛ ويُحذَف فور عودة شبكة مخزنة إلى الواجهة.

الشبكات المخفية. على `wpa` يضبط الحارس `scan_ssid 1` على كل شبكة مخزنة عند البداية وعند كل إنعاش وبعد الدرجتين L2 وL3، وقت التشغيل فقط. على `nm` يجب أن يحمل ملف التعريف `802-11-wireless.hidden yes`؛ والحارس لا يكتبه.

## تصنيف الانقطاع وشرط إعادة التشغيل

فحص الموجّه. قبل أي درجة، وبعد تفعيل كل شبكة مخزنة ظاهرة وتبيّن أنها بلا إنترنت، يرسل الحارس `ping` إلى البوابة الافتراضية. الرد يعني أن الرابط سليم وأن العطل في الأعلى: `outage looks external (round N) — waiting, not rebooting`. لا تعمل أي درجة، ويبقى مؤقّت إعادة التشغيل صفراً، وتُجرَّب شبكات الطوارئ والمفتوحة مع ذلك، ثم تنتظر الجولة 20 ثانية.

ثلاث علامات على أن العطل في الجهاز. مع صمت الموجّه وعدم الحصول على عنوان في هذه الجولة، أي واحدة من هذه تبدأ مؤقّت إعادة التشغيل: شبكة مخزنة ظاهرة لا يمكن الانضمام إليها؛ راديو لا يسمع شيئاً؛ قائمة مخزنة فارغة. يُسجَّل ذلك بمستوى DEBUG هكذا: `fight round N: ME evidence (LINK_OK=0, gw unreachable, auth_failing=N)`؛ و`N` الأخيرة تساوي 1 حين تكون علامة كلمة السر حاضرة، وإلا 0.

كلمة السر الخاطئة. `wpa` يعلّم الشبكة `TEMP-DISABLED`؛ وعلى `nm` يفشل التفعيل برسالة تخص بيانات الاعتماد. يسجّل الحارس `association refused - wrong password? (recovery continues, reboot stays off)`، ويصفّر المؤقّت، ويُبقي السلّم يعمل.

شرط إعادة التشغيل. تحتاج إعادة التشغيل إلى `REBOOT_AFTER_MIN` دقيقة (30) من أدلة متصلة على أن العطل في الجهاز بلا دورة صحيحة ولا علامة كلمة سر؛ وعلى `nm` يجب أيضاً أن يكون NetworkManager قد استقر في حالة غير متصل أو فاشل في جولتين متتاليتين، أو أن يكون `nmcli` يخرج بالرمز 8 بعد الدرجة L3. يُكتَب `wedged 30min with networks visible — rebooting (repeats per streak until cured)` في السجل المحلي فقط، ثم `sync` و`reboot`؛ ويبدأ المؤقّت بعدها من الصفر. المفتاح يرفض 0: إعادة التشغيل تؤجَّل ولا تُعطَّل.

## الإشراف على NetworkManager

اكتشاف النظام الخلفي. NetworkManager نشطاً أو مفعّلاً يجعل النظام الخلفي `nm`، بعد انتظار الخدمة حتى 60 ثانية: `NetworkManager backend - AWACS supervises it (full capability)`. وإلا فالنظام الخلفي `wpa`.

انتظار NetworkManager. ما دامت حالة الجهاز في نطاق الاتصال (40 إلى 90، أو 110) لا يصدر أي تدخل، `NM is still trying - waiting it out`، ويُصفَّر مؤقّت إعادة التشغيل. كل حدّ درجة يعيد الفحص؛ والجهاز المُبلَّغ عنه متصلاً بلا إنترنت يأخذ فرع الموجّه: `NetworkManager is connected, internet is not (round N) — router-side, no rung`.

حارس الحذف. لا يمر `connection down` و`connection delete` إلا عبر دالة واحدة ترفض أي ملف تعريف لا يحمل الاسم `awacs-(crutch|safety)-<epoch>-<pid>` أو يقع خارج `/run/NetworkManager/system-connections/`، وتسجّل `REFUSING delete: 'NAME' is not an awacs crutch` أو `REFUSING delete: 'NAME' lives outside /run (owner file?)`.

الأسماء بالنظام الست عشري. كل مقارنة أسماء على `nm` تجري ببايتات ست عشرية بأحرف صغيرة، فتتطابق الحروف غير اللاتينية والنقطتان والشرطة المائلة العكسية بدقة، وأي استدعاء يصل إلى `wpa_cli` تحت `nm` يُسجَّل `BUG: wpa_cli reached under nm backend:` ويفشل.

وضع المراقبة فقط. الواجهة خارج الإدارة أو غياب `nmcli` يوقف الحارس في وضع المراقبة: `NetworkManager image but AWACS cannot drive it (unmanaged/no nmcli) - monitoring only`. يظل يفرّغ المخزون ويحاول تثبيت الأدوات؛ وحين يظهر `nmcli` يسجّل `nmcli is now installed - restarting as a full NetworkManager supervisor` ويخرج ليعيد المشغِّل تشغيله.

## جودة الرابط والتبديل

تقييم الرابط البطيء. كل دورة صحيحة تقرأ عدّاد الإرسال للواجهة على مدى 3 ثوانٍ. معدل بين 20 كيلوبت/ث والحد الأدنى (`MIN_UP_KBPS`، 400) في `UP_STRIKES` (3) دورات متتالية، بعد `DANCE_COOLDOWN` ثانية (1200) من آخر تقييم: `sustained slow upload (N kbps) - evaluating known networks`. يتبع ذلك قياس واحد للشبكة الحالية؛ القياس تحت الحد وحده يبدأ المقارنة، ويجب أن تبلغ المنافِسة `SWITCH_GAIN_PCT` (150) بالمئة من ذلك القياس وإلا عاد الحارس: `no challenger beat the incumbent - staying on NAME`.

البث المباشر. ما دامت تعمل عملية تطابق `raspistill` مع `live_raw` أو `preview.jpg` أو `capture.jpg`، أو `curl` مع `upfile=@`، فمعدلها هو المقياس: بين 5 كيلوبت/ث و`STREAM_MIN_KBPS` (50) في `UP_STRIKES` دورات يعطي `live stream starving (N kbps) - evaluating known networks`. البث السليم لا يقطعه قياس ولا تبديل ولا فحص الشبكة المفضلة.

الرجوع إلى الشبكة المفضلة. كل `PREF_CHECK` ثانية (600) يبحث الحارس عن شبكة مخزنة ظاهرة بأولوية أعلى تماماً (`priority` على `wpa`، و`connection.autoconnect-priority` على `nm`). رؤيتان متتاليتان: `higher-priority network visible - trying to go home`. تحت الحد عند الوصول: `preferred network too slow (N kbps) - benching it, going back` واستبعاد لثلاث فترات تبريد؛ وإلا `returned to preferred network: NAME (upload N kbps)`.

وضع الإشارة. بلا `SITE_URL` ولا `PROBE_URL` ينضم الإنعاش إلى أقوى شبكة مخزنة ظاهرة توصل الإنترنت، `connected: NAME (signal mode - no upload probe target configured)`؛ ويتعطل التقييم والمقارنة والقياس عند الوصول.

## المسح

تُحفَظ النتائج في الذاكرة المؤقتة `SCAN_TTL` ثانية (30). المسح يجري حتى 3 محاولات (6 في الدقائق الثلاث الأولى بعد الإقلاع)؛ وعند `Device or resource busy` ينتظر 3 ثوانٍ مرة واحدة ثم يقرأ `iwlist` أو جدول النظام الخلفي نفسه (`wpa_cli scan_results`، `nmcli device wifi list --rescan no`). حين لا يعيد أي مصدر شيئاً تُحفَظ الصورة السابقة، `scan failed - using previous results (if any)`؛ وثلاثة مسوح كهذه متتالية تُسقطها، `radio heard nothing on 3 scans in a row - previous results dropped`. المسح الذي ينجح ولا يسمّي أي شبكة يحتفظ بالصورة السابقة.

## التسجيل والتقارير

السجل المحلي. `/var/log/awacs.log`، بالشكل `[LEVEL][dd/mm HH:MM:SS] message`؛ بعد تجاوز `LOG_CAP` (1500) بمئتي سطر يُقصّ الملف إلى `LOG_CAP`. `DEBUG="yes"` (الافتراضي؛ ومتغير البيئة `AWACS_DEBUG` يتقدم عليه) يضيف أسطر تتبّع القرار.

سجل الموقع. مع ضبط `SITE_URL` و`LOG_TARGET` بقيمة `both` أو `remote` يُرسَل كل حدث أيضاً إلى `SITE_URL/DEVICE_ID/SITE_API` بوصفه `file=log/log.txt`، بالشكل `[LEVEL] AWACS: message, dd/mm/yyyy hh:mm:ss AM.` بمنطقة `SITE_TZ`؛ ويتلقى الموقع النص العربي حيث يملكه البرنامج. `remote` يُبقي محلياً أسطر WARN وERROR فقط. سطر البداية `reporting:` يذكر وجهة السجل وهدف القياس وضبط خانة الواي فاي.

المخزون. الأسطر التي يتعذر إرسالها تذهب إلى `/run/awacs/spool`، بحد `SPOOL_CAP` (60)، مع تثبيت السطر الأول كي يبقى سطر افتتاح الانقطاع. يُفرَّغ بالترتيب بعد ثلاث دورات صحيحة، ثم كل 30 دورة ما بقيت أسطر.

خانة الواي فاي. كل ست دورات صحيحة يرسل الحارس `file=tmp/wifi.tmp` بمحتوى `kbps,visible,total,band,SSID`؛ ولا تُرسَل السرعة إلا حين قيست على الشبكة الحالية، وإلا 0. `REPORT_WIFI` هو `auto` (يعمل مع سجل الموقع) أو `yes` أو `no`.

الأدوات. عند البداية: `missing tools: iw - will try to install once online`. في الدورة الصحيحة الثالثة يجري `apt-get install` واحد في الخلفية مرة كل إقلاع بأسماء حزم Debian: `installing missing tools:`، ثم `tools installed:` أو `tool install failed - still missing:`؛ وبلا apt: `no apt-get on this system - install manually:`.

## الأمان والنظافة

لا كتابة في الضبط المخزن. لا `save_config`، ولا `disable_network`، ولا `nmcli connection modify`، ولا `nmcli device wifi connect`؛ و`connection down` و`delete` عبر حارس الحذف فقط. يُعاد تفعيل كل الشبكات المخزنة عند البداية، وعند بدء كل إنعاش، وبعد كل نجاح، وعند خروج كل إنعاش فاشل، وعند الإيقاف.

ملف الإعدادات. لا يُقرأ `/etc/awacs.conf` إلا حين يكون ملك `root` وغير مقروء ولا قابل للكتابة للمجموعة أو الغير؛ وإلا يذهب `awacs: IGNORING /etc/awacs.conf (group/world can access it — chmod 600 it)` أو `awacs: IGNORING /etc/awacs.conf (not owned by root — chown root: it)` إلى الخرج القياسي للأخطاء وتُطبَّق القيم الافتراضية. المفاتيح الرقمية يجب أن تكون أرقاماً غير صفرية بسبعة أرقام على الأكثر، و`NIGHT_START` و`NIGHT_END` بالشكل `HH:MM`؛ وأي شيء آخر يسقط إلى الافتراضي.

ملفات التشغيل. كل ما تحت `RUN_DIR` (`/run/awacs`، صلاحيات 0700) يُنشأ بـ `umask 077`. كلمات السر تذهب إلى `supplicant` عبر المدخل القياسي وإلى NetworkManager في ملف مفاتيح بصلاحيات 0600، ولا تمر في سطر أوامر أبداً. `DEVICE_ID` يجب أن يطابق `[A-Za-z0-9_-]{1,32}`؛ وإلا فاسم المضيف القصير، ثم `device`. القفل `flock` على `/run/awacs/lock` يضمن نسخة واحدة.

التخفي. `STEALTH_MODE="yes"` يضيف قاعدة `iptables` واحدة تُسقط طلبات ICMP echo على الواجهة ويوقف `avahi-daemon`: `stealth mode active (icmp hidden, avahi stopped)`. وهو ليس تحكماً في الوصول.

الإيقاف. عند SIGINT أو SIGTERM أو SIGQUIT أو SIGHUP يعيد الحارس تفعيل كل الشبكات ويخرج بالرمز 0.

## صندوق الأدوات

كلمات صندوق الأدوات هي `status` و`networks` و`evaluate` و`scan` و`speed` و`check` و`help`؛ وتعمل `check` و`help` بلا `root` على القيم الافتراضية المدمجة لا على `/etc/awacs.conf`، ويصف [README.ar.md](../../README.ar.md) خرج كل كلمة. أي كلمة أخرى تطبع `usage: awacs.sh [status|networks|evaluate|scan|speed|check|help|-d]   (no argument = daemon)`؛ و`-d` يشغّل الحارس في الخلفية و`-q` يُتجاهَل.

## وضع النهار والليل

مع `NIGHT_MODE="yes"` (الافتراضي) ينتقل الحد الأدنى ونسبة التفوق وفترة التبريد من `MIN_UP_KBPS` و`SWITCH_GAIN_PCT` و`DANCE_COOLDOWN` إلى `NIGHT_MIN_UP_KBPS` (200) و`NIGHT_GAIN_PCT` (300) و`NIGHT_DANCE_COOLDOWN` (2400) بين `NIGHT_START` (22:00) و`NIGHT_END` (06:00)؛ ويجوز أن تعبر النافذة منتصف الليل. يُسجَّل كل انتقال مرة واحدة: `night profile active (floor 200 kbps)` أو `day profile active (floor 400 kbps)`.

## المثبّت والوحدة والمستقبِلان ولوحة الطرفية

يصف [install.md](install.md) المثبّت `install.sh` ووحدة systemd ولوحة الطرفية `tools/awacs-tui.sh`. ويصف [integration.md](integration.md) المستقبِلين `server/receiver.php` و`server/receiver.py` وعقد نقطة الاستقبال.

## الحدود

- واي فاي فقط: واجهة لاسلكية واحدة بلا بديل سلكي؛ والاتصال يحتاج عنوان IPv4.
- كشف البث المباشر مثبَّت على نمطي العمليات المذكورين أعلاه؛ والدرجة L3 تعيد تحميل `brcmfmac` دون شرط، وهو ما لا يفعل شيئاً على شريحة أخرى.
- إعادة التشغيل لا تُعطَّل بل تؤجَّل فقط؛ وتثبيت الحزم مرة كل إقلاع لا مفتاح لإيقافه.
- أسطر سجل الموقع تحمل النص العربي حيث يملكه البرنامج؛ والشبكات المفتوحة تُجرَّب افتراضياً؛ والشبكة التي يرد فيها `ping` ولا يعمل فيها DNS تُقرأ متصلة.
- `wpa`: الشبكات المفتوحة ذات الأسماء غير اللاتينية تُتجاوَز، والأسماء المخزنة أو مدخلات `SAFETY_NET` التي تحوي شرطة مائلة عكسية أو علامة تنصيص مزدوجة أو جدولة أو فاصل أسطر أو رمز هروب أو مسافة في الطرف لا تطابق أو تُتجاوَز.
- `nm`: ملف التعريف المخفي يجب أن يحمل `hidden=yes` بنفسه؛ وحالة الجهاز 20 (غير متاح) لا تبدأ مؤقّت إعادة التشغيل أبداً.

[scenarios.md](scenarios.md) تعرض تسع حالات بالترتيب؛ و[how-it-works.md](how-it-works.md) تصف الدورة الرئيسية؛ و[troubleshooting.md](troubleshooting.md) تشرح كل سطر سجل.

</div>
