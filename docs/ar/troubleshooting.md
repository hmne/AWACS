<div dir="rtl">

# استكشاف الأخطاء

كل مدخل هنا سطر يطبعه السكربت، ومستواه، وما يعنيه، وما تفعله. السجل المحلي هو `/var/log/awacs.log`؛ وصيغة السطر المحلي `yyyy-mm-ddThh:mm:ss+hh:mm [LEVEL] message`. يصل الخرج القياسي للأخطاء من الحارس إلى `journalctl -u awacs` تحت `systemd` ولا يصل إلى أي مكان تحت حلقة `rc.local`؛ فأفضل طريقة لرؤية رفضَي ملف الضبط أدناه هي تشغيل `sudo awacs.sh status` على الطرفية، لأن كل تشغيل بصلاحيات `root` يقرأ ملف الضبط. ويقول الحارس الحكم نفسه عند البدء بسطر `WARN` يبدأ بـ `settings file`، في السجل وعلى الموقع؛ مدخلاته أدناه.

## الضبط

### `awacs: IGNORING /etc/awacs.conf (not owned by root — chown root: it)`

الخرج القياسي للأخطاء، عند كل تشغيل بصلاحيات `root`. مالك ملف الضبط ليس `root`، وذلك عادة بعد استعادته بمستخدم آخر؛ يعمل الحارس بالافتراضيات (لا `SAFETY_NET` ولا موقع). الحل: `sudo chown root:root /etc/awacs.conf`.

### `awacs: IGNORING /etc/awacs.conf (group/world can access it — chmod 600 it)`

الخرج القياسي للأخطاء، عند كل تشغيل بصلاحيات `root`. الصلاحيات تحوي بتات للمجموعة أو للآخرين (`0644` أو `0640`)؛ وملف الضبط الذي يحمل كلمات سر نقاط الاتصال يُرفض حين يستطيع غيرك قراءته أو الكتابة فيه. الحل: `sudo chmod 600 /etc/awacs.conf`.

### `settings file /etc/awacs.conf not found - running on built-in defaults (no site, no emergency networks)`

`WARN`، مرة عند كل بدء بصلاحيات `root` لا يجد فيه الحارس ملف الضبط (أو الملف الذي يسمّيه `AWACS_CONF`). يعمل الحارس بالقيم الافتراضية المضمّنة كلها: لا موقع، ولا شبكات طوارئ، ووضع الإشارة. يُكتب السطر في الملف المحلي دائماً؛ ولا يصل إلى الموقع إلا حين يأتي `SITE_URL` من البيئة، لأن الملف الغائب يتركه فارغاً. الحل: أنشئ الملف من `awacs.conf.example` (انظر [configuration.md](configuration.md#تطبيق-التغييرات))، أو اترك الأمر إن كان العمل المحلي مقصوداً.

### `settings file /etc/awacs.conf ignored: mode 644, chmod 600 it - running on built-in defaults (no site, no emergency networks)`

`WARN`، مرة عند البدء، وهو ما يصل إلى السجل من الرفض `group/world can access it` المطبوع على الخرج القياسي للأخطاء. `mode` هو صلاحية الملف بالنظام الثماني كما قرأها `stat`. الحل: `sudo chmod 600 /etc/awacs.conf` ثم أعد تشغيل الحارس.

### `settings file /etc/awacs.conf ignored: not owned by root, chown root: it - running on built-in defaults (no site, no emergency networks)`

`WARN`، مرة عند البدء، نظير الرفض `not owned by root` المطبوع على الخرج القياسي للأخطاء. الحل: `sudo chown root:root /etc/awacs.conf` ثم أعد تشغيل الحارس.

### `settings file /etc/awacs.conf applied, but 2 values failed validation and use their defaults: TICK, SITE_TZ`

`WARN`، مرة عند البدء، وفقط حين سقط مفتاح واحد على الأقل؛ البدء السليم لا يكتب شيئاً. طُبِّق الملف، لكن القيم المسمّاة لم تجتز فحص شكلها فحلّت الافتراضيات محلها؛ يذكر السطر أسماء المفاتيح وعددها ولا يذكر القيم أبداً. لا يُحسب `SITE_URL` أو `PROBE_URL` أو `SITE_TZ` الفارغ سقوطاً، لأن الفراغ اختيار؛ ويُحسب ما كُتب فيها بشكل خاطئ. قاعدة كل مفتاح في [configuration.md](configuration.md#الفحص). الحل: صحّح الأسطر المسمّاة وأعد تشغيل الحارس.

### مفتاح ضبطته لا يُطبَّق

القيمة لم تجتز الفحص والافتراضي هو المستعمل؛ والسقوط مقصود، فالخطأ المطبعي يجب ألا يوقف الحارس، ويسمّي سطر `settings file ... applied, but N values failed validation` أعلاه المفتاح مرة عند البدء. قاعدة كل مفتاح في [configuration.md](configuration.md). مدخلات `SAFETY_NET` تحتاج الشكل الدقيق `SAFETY_NET["Name"]="password"`، ولا تُفحص إلا حين تُجرَّب؛ فيُقال المدخل الساقط أثناء الإنعاش بسطر `emergency network X skipped` أدناه. الحل: صحّح السطر وأعد تشغيل الحارس.

### `LOG_TARGET asked for the site but SITE_URL is empty - running local-only`

`WARN`، السجل المحلي، مرة عند البداية. كان `LOG_TARGET` هو `both` أو `remote` بلا `SITE_URL`؛ فخُفِّضت الوجهة إلى `local`. الحل: اضبط `SITE_URL`، أو اجعل `LOG_TARGET="local"`.

### `wifi cell asked for (REPORT_WIFI=yes) but SITE_URL is empty - nothing to publish to`

`WARN`، السجل المحلي، مرة عند البدء، بجانب تحذير تخفيض `LOG_TARGET`: طُلبت خانة الواي فاي صراحة ولا موقع يستقبلها. أما `auto` مع `LOG_TARGET=local` فليس عطلاً ولا يُقال إلا في سطر `running with` بالكلمات `wifi cell off (auto with LOG_TARGET local)`. الحل: اضبط `SITE_URL`، أو أعد `REPORT_WIFI` إلى `auto` أو `no`.

### `time zone Asia/Kuwaitt is unknown on this device (no such zone) - stamps fall back to UTC`

`WARN`، مرة عند البدء، لاسم بالشكل `Area/City` فقط؛ سلسلة POSIX مثل `KST-3` لا تحتاج ملفاً فلا تُفحص. القوس `no such zone` حين لا يوجد ملف عادي باسم `/usr/share/zoneinfo/${SITE_TZ}` (المجلد مثل `Asia` ليس منطقة)، و`tzdata not installed` حين يغيب `/usr/share/zoneinfo` كله. السلوك كما كان: `glibc` يختم بتوقيت UTC لمنطقة لا يعرفها، والسطر يقول ذلك فحسب. الحل: صحّح الاسم (`timedatectl list-timezones`)، أو ثبّت `tzdata`.

### `device id not usable (DEVICE_ID: my camera) - reporting as cam1`

`WARN`، مرة عند البدء، حين توجد قيمة للهوية (المتغير `DEVICE_ID`، وإلا أول سطر غير فارغ من `/tmp/device_id`) لكنها لا تطابق `^[A-Za-z0-9_-]{1,32}$`؛ الهوية الغائبة تصميم موثّق ولا تُقال. يذكر السطر المصدر والقيمة بعد حذف محارف التحكم وقصّها إلى 40 حرفاً، والهوية التي يبلّغ بها الحارس بدلاً منها (اسم المضيف المختصر، أو `device`). وحين تتغير الهوية أثناء العمل، كسكربت إقلاع يكتب `/tmp/device_id` بعد انطلاق الحارس، يُكتب `device id changed: raspberrypi -> mydevice - reporting under mydevice from now` بمستوى `INFO`، مرة لكل تغيير، على إيقاع خانة الواي فاي؛ ويسمّي المجلد الذي تنزل فيه القصة من تلك اللحظة. الحل: هوية من حروف وأرقام و`_` و`-` بلا مسافات؛ انظر [configuration.md](configuration.md#device_id).

### `reporting: local | probe: none - signal mode | wifi cell: auto`

`INFO`، السجل المحلي، بعد سطر البداية: مفاتيح التقارير كما طُبِّقت. مع موقع مضبوط تتبع وجهةَ السجل علامةُ `->` ثم عنوان الموقع، ويسمّي `probe:` هدف القياس. `probe: none - signal mode` يعني أن لا `SITE_URL` ولا `PROBE_URL` مضبوط: لا قياس للرفع ولا تبديل بحسب السرعة. إن ضبطت المفاتيح وما زلت تقرأ `local` فملف الضبط لم يُطبَّق (الرفضان أعلاه) أو أن `SITE_URL` لم يجتز الفحص. يليه سطر `running with:` التالي.

### `running with: measured mode, floor 400/200 kbps day/night (night 22:00-06:00), switch gain 150%, one evaluation per 20 min, reboot after 30 min wedged, wifi cell on, 3 stored networks, 0 emergency, open networks yes, stamps in the device zone`

`INFO`، مرة عند كل بدء، آخر أسطر البداية: الإعدادات كما تعمل فعلاً بعد الفحص، وهو السطر الذي يفسّر كل سطر يأتي بعده. `measured mode` يعني أن هدف قياس موجود (`SITE_URL` أو `PROBE_URL`)؛ وبدونهما يقرأ السطر `running with: signal mode (no probe target - networks chosen by signal), reboot after 30 min wedged, wifi cell off (no SITE_URL), 3 stored networks, 0 emergency, open networks yes, stamps in the device zone`، ويبقى في الملف المحلي وحده لأن لا موقع. مع `NIGHT_MODE` غير `yes` يقرأ جزء الحد `floor 400 kbps (night profile off)`. `one evaluation per` هو `DANCE_COOLDOWN` بالدقائق مقرَّباً إلى الأعلى. `wifi cell` يقرأ `on`، أو `off (REPORT_WIFI=no)`، أو `off (no SITE_URL)`، أو `off (auto with LOG_TARGET local)`. عدد الشبكات المخزنة يُقرأ من الطبقة الأساسية عند البدء، فـ `0 stored networks` مع ضبط سليم يعني `wpa_cli` صامتاً أو `nmcli` غائباً. `emergency` عدد مدخلات `SAFETY_NET` بلا أسماء. `stamps in` هو `SITE_TZ` أو `the device zone`. لا عنوان في السطر. إن قرأت هنا غير ما ضبطته فراجع سطر `settings file` الذي يسبقه.

## البداية

### `AWACS 1.0 starting on wlan0 (device mydevice) - wpa backend, restart 3 of this boot`

`INFO`، كل بدء. الرأس كما كان؛ والذيل يسمّي النظام الخلفي (`wpa` أو `NetworkManager`) وهل هذا أول بدء منذ إقلاع الجهاز (`first start of this boot, up 1 min`، ومدة التشغيل بالشكل `45 s` أو `3 min` أو `2 h 15 min` أو `3 d 4 h`) أو إعادة تشغيل للحارس (`restart N of this boot`). العدّاد ملف `/run/awacs/starts` يزول مع الإقلاع ولا تزيده إلا النسخة التي ربحت القفل. `restart` بعد ساعات من الإقلاع يعني أن الحارس مات وأعاده المشغّل: ابحث عن سطر `AWACS exited unexpectedly` قبله، وعن حالة الخروج في `journalctl -u awacs`. على صورة NetworkManager بلا `nmcli` يقرأ الذيل `NetworkManager backend` ويتبعه سطر `ERROR` فوراً؛ وإعادة التشغيل بعد وصول `nmcli` تُحسب `restart` أيضاً.

### `starting after the reboot AWACS ordered at 2026-01-01 03:41 - wedged 30 min (HomeNet, OfficeNet on the air but this device cannot join), 7 recovery runs before it`

`WARN`، مرة، في أول بدء بعد إعادة تشغيل أمر بها الحارس نفسه: وُجدت علامة إعادة التشغيل بجانب السجل ومعرّف الإقلاع فيها غير معرّف الإقلاع الحالي. قبل سطر البداية تُوضع قصة الانقطاع المحفوظة على بطاقة الذاكرة أمام المخزون المؤقت، فيسلّم أول تفريغ بالترتيب: قصة الانقطاع، ثم `rebooting now`، ثم سطر البداية، ثم هذا السطر. الختم بتوقيت `SITE_TZ`؛ والقوس هو العلامة التي حكمت لحظة إعادة التشغيل (انظر `rebooting now` أدناه)؛ والعدد هو عدد جولات الإنعاش قبلها. انقطاع الكهرباء لا يترك علامة، فيبقى سطر البداية بعده بلا هذا السطر. ليس خطأً بذاته: اقرأ القصة التي فوقه؛ وإن تكررت إعادة التشغيل نفسها فالعطل تحت الحارس.

### `the reboot AWACS ordered at 2026-01-01 03:41 did not happen - the reboot command failed, check the device`

`ERROR`، مرة. بقي الحارس حياً 60 ثانية في الإقلاع نفسه الذي كان يجب أن ينتهي: إما أن أمر `reboot` فشل في العملية نفسها، أو أعاد المشغّل حارساً جديداً وجد العلامة بمعرّف الإقلاع الحالي. تُحذف العلامة والنسخة المحفوظة، ويبقى عدّاد إعادات التشغيل لهذا العطل. الحل: افحص `journalctl -b` عن سبب رفض `reboot` (`systemd` لا يرد، أو نظام ملفات للقراءة فقط)، وأعد تشغيل الجهاز بيدك إن لزم.

### `missing tools: iw nmcli - will try to install once online`

`ERROR`، عند البداية. الأدوات المسمّاة ليست في `PATH`؛ والجرد هو `iw ip ping curl awk sed grep pgrep rfkill flock timeout stat date modprobe` زائد `wpa_cli` (على `wpa`) أو `nmcli` (على `nm`). في الدورة الصحيحة الثالثة يعمل `apt-get install` واحد في الخلفية، مرة كل إقلاع (العلامة `/run/awacs/apt_tried`): `installing missing tools: <packages>`، ثم `tools installed: <packages>` أو `tool install failed - still missing: <tools> - install manually`؛ وبلا `apt-get`: `no apt-get on this system - install manually: <tools>`. أسماء الحزم: `wpasupplicant` و`network-manager` و`iproute2` و`iputils-ping` و`mawk` و`procps` و`util-linux` و`coreutils` و`kmod`؛ وسائر الأدوات تُثبَّت باسمها. لا يوجد مفتاح لتعطيل المحاولة. الحل إن فشلت: ثبّت الحزم يدوياً؛ وتتكرر المحاولة عند الإقلاع التالي.

### `interface wlan0 not present - is the WiFi hardware alive?`

`ERROR`، عند البداية. لا واجهة لاسلكية في `iw dev`، ولا `wlan0` أيضاً، ويمضي الحارس باسم لا جهاز خلفه: راديو ميت، أو محوّل مفصول، أو تعريف ناقص، أو `iw` نفسه ناقص (وحينها يليه `missing tools: iw`). الحل: افحص `iw dev` و`rfkill list` و`dmesg | grep -i brcm`؛ واضبط متغير البيئة `AWACS_IF` إن كان للواجهة اسم غير معتاد.

### `interface wlan0 has vanished - WiFi hardware or driver gone, rung L3 reloads the driver (a USB dongle needs replugging)`

`ERROR`، مرة لكل انقطاع، في بداية الإنعاش: فشل `iw dev wlan0 info` لواجهة كانت حية في هذا التشغيل؛ والواجهة الغائبة من البدء لها سطرها `interface wlan0 not present`. محوّل USB مفصول، أو واجهة زالت بعد انهيار التعريف. تعمل الدرجات، وL3 تعيد تحميل التعريف؛ والوصلة المفصولة تحتاج توصيلاً بيد. الحل: `iw dev` و`lsusb` و`dmesg`.

### `NetworkManager image but AWACS cannot drive it: nmcli is missing - will install it once online and restart - monitoring only`

`ERROR`، عند البداية؛ وله ثلاث صيغ بحسب السبب والعلاج: هذه حين يغيب `nmcli` والحارس تحت حلقة `rc.local` أو الوحدة؛ و`NetworkManager image but AWACS cannot drive it: nmcli is missing - will install it once online, then restart AWACS by hand (started with -d) - monitoring only` حين شُغّل بالراية `-d` التي لا مشغّل خلفها؛ و`NetworkManager image but AWACS cannot drive it: wlan0 is unmanaged by NetworkManager - fix unmanaged-devices in NetworkManager.conf and restart AWACS - monitoring only` حين تكون الواجهة خارج الإدارة (حالة الجهاز 10). `NetworkManager` يعمل أو مفعّل في الحالات كلها. يتوقف الحارس عن التدخل: يفحص الإنترنت كل 300 ثانية، ويفرّغ المخزون المؤقت، ويترك تثبيت الأدوات يعمل مرة؛ ولا يعمل أي إنعاش. لـ `nmcli` الناقص انتظر التثبيت أو شغّل `apt-get install --reinstall network-manager` بنفسك: يتبعه `nmcli is now installed - restarting as a full NetworkManager supervisor`، فيخرج الحارس لتعيد حلقة التشغيل إطلاقه، وتسجّل البداية التالية `NetworkManager backend - AWACS supervises it (full capability)`. للواجهة خارج الإدارة ابحث عن `unmanaged-devices` في `/etc/NetworkManager/NetworkManager.conf` و`/etc/NetworkManager/conf.d/`، أو شغّل `nmcli device set wlan0 managed yes`، ثم أعد تشغيل الحارس؛ فالحارس المتوقف لا يعيد الاكتشاف بنفسه.

### `internet lost on HomeNet - monitoring only, AWACS cannot recover here`

`WARN`، في وضع المراقبة فقط، مرة لكل انقطاع: فشل فحص الإنترنت الذي يجري كل 300 ثانية بعد أن كان ينجح، أو فشل أول فحص بعد البدء. لا يعمل أي إنعاش؛ وحين يعود الإنترنت يُفرَّغ المخزون أولاً ثم يُكتب `internet back on HomeNet - monitoring only` بمستوى `OK`، فيقرأ الموقع الفقد ثم العودة بترتيبهما. زوج واحد لكل انقطاع، ولا شيء في المرورات بينهما. الحل: ما يقوله مدخل وضع المراقبة أعلاه.

### `aasw.sh is still running - two WiFi authorities will fight; remove its rc.local line`

`WARN`، عند البداية. تعمل عملية يحوي سطر أمرها `/usr/local/bin/aasw`: حارس واي فاي أقدم ينازع على الراديو. الحل: احذف سطر تشغيله من `/etc/rc.local` واحذف الملف.

### `wifi radio was soft-blocked at start - unblocked (a WLAN country not set, or a saved rfkill state)`

`WARN`، مرة عند البدء. قرأ الحارس `rfkill list wifi` قبل رفع الحجب فوجد `Soft blocked: yes`، ثم رفعه كما كان يفعل دائماً (`rfkill unblock wifi`، وعلى `nm` أيضاً `nmcli radio wifi on`). الجهاز الذي يقلع محجوباً برمجياً يبقى بلا واي فاي في كل إقلاع حتى يبدأ الحارس؛ والسببان المعتادان بلد الواي فاي غير المضبوط وحالة `rfkill` محفوظة من إيقاف سابق. الحل: اضبط البلد (`raspi-config`، أو `country=` في `wpa_supplicant.conf`)، أو امسح الحالة المحفوظة (`sudo rfkill unblock wifi` ثم احذف الملفات تحت `/var/lib/systemd/rfkill/`).

### `wifi radio is hard-blocked - a hardware switch, AWACS cannot unblock it`

`WARN`، مرة عند البدء. أظهر `rfkill list wifi` قبل رفع الحجب `Hard blocked: yes`: مفتاح مادي أو وصلة في العتاد، ولا أمر يرفعه. يبقى الجهاز بلا واي فاي حتى يُحرَّك المفتاح، ويتبع ذلك `no internet at start` وإنعاش لا يجدي. الحل: على الجهاز نفسه.

### `stealth mode partly active: iptables missing - pings still answered`

`WARN`، مرة عند البدء مع `STEALTH_MODE="yes"`، بدل سطر `stealth mode active (icmp hidden, avahi stopped)` الذي لا يُكتب إلا حين تنجح الخطوتان. الأجزاء المحتملة، بفاصلة بينها: `iptables missing - pings still answered` (لا `iptables` في المسار)، و`ping rule could not be added - pings still answered` (فشل `iptables -C` و`iptables -I` معاً)، و`avahi could not be stopped` (ما زالت `avahi-daemon` نشطة بعد أمر الإيقاف؛ والصورة التي لا تحوي avahi أصلاً ليست فشلاً). الحل: ثبّت `iptables`، أو افحص سبب رفض القاعدة بـ `iptables -L INPUT` بيدك، أو أوقف avahi وافحص من يعيد تشغيله عبر المقبس.

### `removed the temporary network FreeCafe left by the previous run - the device was still on it, recovery follows`

`WARN`، مرة عند البدء لكل مدخل مؤقت تركه حارس سابق مات وهو عليه (العلامة `/run/awacs/open_id`، وعلى `nm` أيضاً كل ملف تعريف `awacs-*` يجده الكنس). يُسمّى المدخل قبل حذفه؛ وكان الجهاز ما زال يركبه، فحذفه هو الانقطاع الذي يتبعه مباشرة: `no internet at start` ثم إنعاش يعيد الجهاز إلى شبكة مخزنة أو إلى شبكة مؤقتة جديدة. وحين لا يكون الجهاز عليه يقرأ السطر `removed the temporary network FreeCafe left by the previous run` بمستوى `INFO` بلا ذيل. ليس خطأً؛ لكن تكراره في كل بدء مع `restart N of this boot` يعني حارساً يموت على الشبكة المؤقتة: اقرأ `AWACS exited unexpectedly`.

### `no internet at start on HomeNet - router still answers, engaging`

`WARN`، مرة عند البدء حين يفشل فحص الإنترنت الأول، قبل إنعاش البدء. الشبكة هي التي وجد الحارس الجهاز عليها، أو الواجهة إن لم يكن على شبكة؛ وكلمة الموجّه هي كلمة سطر `internet lost` نفسها: `still answers` (البوابة ترد، فالعطل فوقها)، أو `silent too` (مرتبط والبوابة صامتة)، أو `none (not associated)`. الفوز في إنعاش البدء يُقال في أول دورة صحيحة بسطر `internet restored: X - down D, N recovery runs` ثم أسطر `repeated`؛ والخسارة لا تُعلن مرة ثانية، بل تتبعها إنعاشات الحلقة بأسطرها. النظير الصحيح `online at start via HomeNet` بمستوى `OK`، ويأتي بعد تفريغ المخزون كي تصل قصة الحارس السابق أولاً.

### `AWACS exited unexpectedly (status 1, last command in fight: echo "$UNBOUND_THING") - the launcher restarts it in 10 s`

`ERROR`، مرة، عند أي خروج لم يأمر به أحد: متغير غير مضبوط تحت `set -u`، أو `exec` فاشل، أو `exit` شارد. يذكر السطر حالة الخروج، وآخر أمر كما هو في نص السكربت بلا توسيع فلا تسافر كلمة سر، واسم الدالة إن كان الخروج داخل دالة؛ ولا يذكر رقم السطر لأن `bash` يبلّغ عن `LINENO` بالقيمة 1 داخل مصيدة `EXIT`. الذيل `the launcher restarts it in 10 s` تحت حلقة `rc.local` أو الوحدة، و`no launcher under -d, start it again` حين شُغّل الحارس بـ `-d`. يُرسل السطر في المقدمة قبل الخروج؛ وإن كان الموقع بعيد المنال بقي في المخزون وسلّمه البدء التالي. يصمت السطر عند الإيقاف بإشارة، وعند خسارة القفل، وعند خروج وضع المراقبة لإعادة التشغيل بعد وصول `nmcli`، وعند إعادة تشغيل الجهاز التي يأمر بها الحارس. الحل: الأمر المسمّى هو موضع الخلل؛ أبلغ عنه مع السطر.

### `another AWACS already holds the lock (pid 1234) - two launchers are running it, keep one (the rc.local line or the systemd unit)`

`WARN`، مرة في كل إقلاع (العلامة `/run/awacs/lock_lost`)، من النسخة التي خسرت القفل بلا طرفية؛ وكل خسارة لاحقة كل 10 ثوانٍ صامتة كما ينص عقد حلقة `rc.local`. رقم العملية من السطر الأول لملف القفل، و`?` إن لم يكن رقماً. يقع السطر في المخزون المشترك ويسلّمه التفريغ التالي للنسخة الرابحة. الإطلاق الثاني من طرفية يعرض صندوق `INSTANCE ERROR` بدلاً منه. الحل: أبقِ مشغّلاً واحداً (`sudo systemctl disable awacs`، أو احذف كتلة rc.local)؛ انظر «مشغّلان اثنان» أدناه.

## الانقطاع والإنعاش

### `internet lost on HomeNet - router still answers, engaging`

`WARN`، مرة لكل انقطاع. يذكر السطر الشبكة التي كان الجهاز عليها حين انقطع الإنترنت، أو الواجهة (`wlan0`) إن لم يكن على أي شبكة، وما يفعله الموجّه في تلك اللحظة، بـ `ping` واحد للبوابة في هذه الدورة: `still answers` (الوصلة حية والعطل فوقها: المزوّد، أو جانب WAN في الموجّه)، أو `silent too` (مرتبط والبوابة لا ترد: الموجّه نفسه أو الرابط)، أو `none (not associated)` (لا ارتباط أصلاً). فشل `NET_FAIL_TICKS` فحصاً متتالياً للإنترنت؛ يبدأ الإنعاش ويتكرر كل دورة حتى يختم `internet restored: HomeNet - down 3 min, 2 recovery runs` الانقطاع، ويذكر ذلك السطر مدة الانقطاع (بالشكل `45 s` أو `3 min` أو `2 h 5 min`) وعدد الإنعاشات؛ وتتبعه أسطر `repeated N more times during the outage (last at HH:MM): ...`، واحد لكل خطوة تكررت في الانقطاع، بوقت آخر تكرار بتوقيت الموقع. ليس خطأً بذاته؛ كلمة الموجّه هي ما يمكن فعله عن بُعد: اتصل بالمزوّد حين يرد، واطلب إعادة تشغيل الموجّه حين يصمت.

### `internet answers late, not never - slow link, no recovery (${NET_FAIL_TICKS} quick checks timed out)`

`INFO`، الملف المحلي فقط، مرة واحدة على الأكثر في الانقطاع. انتهت مهلة `NET_FAIL_TICKS` فحصاً سريعاً متتالياً، لكن الوصلة نفسها كانت حية (البوابة الافتراضية ردت، أو ذكرها جدول الجيران في النواة بحالة `REACHABLE`)، ونال فحص صبور واحد، بثلاث رسائل `ping` لكل هدف وحد 8 ثوانٍ لطلبات HTTP، جواباً. الوصلة بطيئة أو مزدحمة لا مقطوعة: لا يُكتب سطر فقد، ولا يجري إنعاش، وتُحسب الدورة سليمة. الحل: لا شيء. وتكراره يعني وصلة تصل أجوبتها بعد الثانيتين أو الثلاث التي ينتظرها الفحص السريع، غالباً تحت رفع مزدحم؛ ارفع `TICK` أو `NET_FAIL_TICKS` لتنال وصلة كهذه وقتاً أطول قبل أن يبدأ الحارس الإنعاش أصلاً.

### `uplink answering late on HomeNet - 3 quick checks timed out, the patient check passed, no recovery`

`INFO`، يصل إلى الموقع، مرة في بداية كل نوبة تأخر: الحدث نفسه الذي يكتبه السطر المحلي أعلاه، قيل مرة للموقع بدل أن يتكرر كل 40 إلى 60 ثانية تحت حمل مستمر. المرات التالية في النوبة تُعدّ ولا تُقال؛ وكل ساعة على الأكثر، إن وُجدت مرات جديدة، يُكتب `internet answered late 4 more times in the last hour on HomeNet - slow link, no recovery`. تُختم النوبة بعد 30 دورة متتالية نجح فيها الفحص السريع (نحو 5 دقائق) بسطر `uplink answers normally again on HomeNet - answered late 6 times over 26 min`؛ ولا تُفتح نوبة جديدة قبل 30 دقيقة من الختم، وما يقع في تلك النافذة يُطوى في النوبة التالية بعدّه ومدته. وإن انتهت النوبة بانقطاع كتب الحارس `internet answered late 2 more times before this loss on HomeNet - slow link` ثم سطر الفقد. سطران في الساعة على الأكثر على أسوأ وصلة. الحل: كما في المدخل المحلي أعلاه.

### `outage looks external (round 1) — waiting, not rebooting`

`INFO`، مرة لكل انقطاع لكل علامة؛ وكل جولة لاحقة تصل إلى الحكم نفسه تُعدّ، ويأتي العدد بعد `internet restored` في السطر `repeated N more times during the outage (last at HH:MM): outage looks external ...` بلا رقم الجولة. الحكم يسمّي العلامة التي أخرجت العطل من الجهاز، بترتيب فحصها: الشكل القصير أعلاه حين كان `NetworkManager` على `nm` ما زال يعمل على الجهاز في بداية الجولة (السطر السابق `NM is still trying`)؛ و`outage looks external: the router answers, the fault is upstream (round 1) — waiting, not rebooting` حين ترد البوابة؛ و`outage looks external: OfficeNet linked but no internet, the fault is behind that network (round 1) — waiting, not rebooting` حين ارتبطت شبكة مخزنة وحصلت على عنوان في هذه الجولة بلا إنترنت؛ و`outage looks external: none of your 3 stored networks is on the air, 5 others heard (round 1) — waiting, not rebooting` حين يسمع الراديو شبكات ليس بينها أي من المخزنة. المشكلة في الأعلى (مزوّد الخدمة، أو جانب `WAN` في الموجّه، أو `DNS` عند الموجّه) أو أن الشبكات المخزنة خارج المدى. يُصفَّر مؤقت إعادة التشغيل؛ وتُجرَّب شبكات الطوارئ والشبكات المفتوحة مع ذلك، ثم تنتظر الجولة 20 ثانية. الحل: لا شيء على الجهاز. افحص الموجّه أو الشبكة المسمّاة؛ وإن لم تكن أي من شبكاتك ظاهرة فافحص الموضع.

### `association refused by HomeNet - wrong password? (recovery continues, reboot stays off)`

`ERROR`، مرة لكل انقطاع لكل مجموعة أسماء؛ والجولات المتطابقة تُعدّ، و`association refused - wrong password? (recovery continues, reboot stays off)` هو الشكل حين لا يُعرف اسم. الشبكات المسمّاة: على `wpa` هي صفوف `wpa_cli list_networks` التي تحمل `TEMP-DISABLED`، وعلى `nm` المرشح الذي فشل تفعيله بخطأ يذكر الأسرار أو المصادقة أو `802-1X` أو إدارة المفاتيح أو المفتاح المشترك. شبكة ثانية ترفض لاحقاً في الانقطاع نفسه تُقال من جديد. يستمر سلّم الإنعاش؛ ويُصفَّر مؤقت إعادة التشغيل كلما ظهرت هذه العلامة. الحل: صحّح كلمة سر الشبكة المسمّاة في ضبطك أنت (`wpa_supplicant.conf` أو ملف تعريف `NetworkManager`)؛ فالحارس لا يعدّله أبداً.

### `fault looks on the device: HomeNet, OfficeNet on the air but this device cannot join - recovery follows`

`WARN`، مرة لكل انقطاع لكل علامة، قبل درجة الجولة مباشرة؛ ويُتخطى حين قال سطر كلمة السر حكمه في هذه الجولة. القوس هو العلامة التي حكمت، بترتيب فحصها: `HomeNet, OfficeNet on the air but this device cannot join` (شبكات مخزنة ظاهرة لا يُنضَم إليها، عشرة أسماء على الأكثر ثم `and N more`)، أو `the radio hears no network at all`، أو `the stored network list cannot be read` (على `nm`، حين يخرج `nmcli` بالرمز 8)، أو `the stored network list reads empty`. العلامة التي تتغير أثناء الانقطاع تُقال مرة أخرى؛ والجولات المتطابقة تُعدّ. هذا هو السطر الذي يفسّر لماذا تعمل الدرجات ولماذا يبدأ مؤقت إعادة التشغيل؛ وعلى `nm` لا يُكتب في الجولات التي يلتقط فيها NetworkManager الجهاز أو يبلّغ اتصالاً بلا إنترنت، فلها أسطرها. الحل: بحسب العلامة؛ الشبكات الظاهرة التي لا يُنضَم إليها تعني كلمة سر قديمة أو موجّهاً لا يعطي عناوين، والراديو الأصم عتاداً أو تعريفاً، والقائمة الفارغة `wpa_supplicant` صامتاً تعالجه الدرجة L2.

### `reboot clock armed - the device reboots after 03:41 unless the internet returns or the fault reads external`

`WARN`، مرة لكل انقطاع، لحظة ضبط مؤقت إعادة التشغيل لأول مرة: على `wpa` في أول جولة تُصنَّف عطلاً في الجهاز، وعلى `nm` حين يستسلم NetworkManager. الوقت بتوقيت `SITE_TZ`، وهو لحظة الضبط زائد `REBOOT_AFTER_MIN` دقيقة؛ و`after` لا `at` لأن الشرط لا يُفحص إلا في نهاية إنعاش خاسر. إعادة الضبط في الانقطاع نفسه تُعدّ. على `nm` يُكتب `reboot clock cleared - NetworkManager picked the device up again` بمستوى `INFO` حين يصفّر التقاطُ NetworkManager للجهاز مؤقتاً كان قد أُعلن؛ والتصفيرات الأخرى (حكم خارجي، أو كلمة سر، أو دورة صحيحة، أو اتصال ناجح) لها أسطرها ولا تُقال هنا. ليس خطأً بل موعد: إن كان الانقطاع في الشبكة لا في الجهاز فسيقرأ الحارس ذلك ويصفّره، وإلا فاقرأ `rebooting now`.

### `fight round 1: ME evidence (LINK_OK=0, gw unreachable, auth_failing=0)`

`DEBUG`، السجل المحلي فقط، تُكتب فقط مع `DEBUG="yes"` في ملف الضبط أو `AWACS_DEBUG=yes` في البيئة. صنّفت الجولة الانقطاع على أنه من الجهاز نفسه: الموجّه لا يرد، ولم ترتبط أي شبكة وتحصل على عنوان في هذه الجولة، وشبكة مخزنة ظاهرة لا يمكن استعمالها، أو المسح فارغ، أو القائمة المخزنة فارغة. يعمل السلّم ويبدأ مؤقت إعادة التشغيل (على `nm` لا يبدأ إلا بعد أن يستسلم `NetworkManager`؛ انظر مدخل إعادة التشغيل).

### `recover L1: radio bounce`

`WARN`، الجولة الأولى من إنعاش صُنّف انقطاعه على أنه في الجهاز؛ درجة واحدة في كل جولة. تسجّل الجولة الثانية `recover L2: restart dhcpcd (respawns the REAL per-interface supplicant)` (على `wpa`) أو `recover L2: re-kick NetworkManager on wlan0` (على `nm`)؛ وتسجّل الجولة الثالثة `recover L3: reload brcmfmac firmware (the 3-second cure a wedge needs)` أو `recover L3: restart NetworkManager + reload WiFi firmware`. على `wpa` الدرجات هي إنزال الواجهة ورفعها، ثم إعادة تشغيل `dhcpcd` (أو `wpa_supplicant`)، ثم إعادة تحميل وحدة `brcmfmac`؛ وعلى `nm` حظر `rfkill` وفكّه (أو `nmcli radio wifi`)، ثم `nmcli device reapply` يتبعه فصل ووصل، ثم إعادة تشغيل `NetworkManager` مع إعادة تحميل الوحدة. تسرد [how-it-works.md](how-it-works.md) كل أمر. إعادة تحميل الوحدة لا تفعل شيئاً على عتاد لا يستعمل ذلك التعريف. على النظامين تُقال الدرجة مرة لكل انقطاع، وتُعدّ الإنعاشات التالية التي تكررها بعد `internet restored`. والدرجة التي لا تتم تقول ذلك بأسطر `did not complete` التالية. السلّم الذي يتكرر لدقائق طويلة بلا `internet restored` يحقق شرط إعادة التشغيل أدناه.

### `recover L1 did not complete: wlan0 would not come back up - radio not bounced`

`WARN`، على `wpa`، مرة لكل انقطاع: أعاد `ip link set wlan0 up` فشلاً بعد إنزال الواجهة. الواجهة التي لا تُرفع تعريف أو عتاد ضائع؛ تتبع الدرجتان التاليتان، والدرجة L3 تعيد تحميل التعريف. الحل: `dmesg | tail` و`ip link show wlan0`.

### `recover L2 did not complete: dhcpcd and wpa_supplicant both refused to restart - supplicant not respawned`

`WARN`، على `wpa`، مرة لكل انقطاع: فشل `systemctl restart dhcpcd` ثم `systemctl restart wpa_supplicant`. بلا مشغّل جديد للشبكة لا تُشفى القائمة المخزنة الفارغة. الحل: `systemctl status dhcpcd wpa_supplicant` و`journalctl -u dhcpcd`.

### `recover L3 did not complete: brcmfmac would not unload - firmware not reloaded`

`WARN`، على النظامين، مرة لكل انقطاع: كان تعريف `brcmfmac` محمّلاً (`/sys/module/brcmfmac` موجود) ورفض `modprobe -r brcmfmac` إزالته؛ والعتاد الذي لا يستعمل هذا التعريف لا ينبّه أبداً. تعريف عالق تحت راديو متجمد على الأغلب؛ وإن استمرت العلامات فإعادة التشغيل هي العلاج التالي. الحل: `lsmod | grep brcm` و`dmesg`.

### `recover L3 did not complete: NetworkManager refused to restart - firmware reload follows`

`WARN`، على `nm`، مرة لكل انقطاع: أعاد `systemctl restart NetworkManager` فشلاً؛ ويُقال ذلك قبل خطوة التعريف، التي تجري بعده على أي حال. الحل: `systemctl status NetworkManager` و`journalctl -u NetworkManager`.

### `NetworkManager is not answering nmcli (exit 8) - stored networks cannot be tried until it is restarted (recover L3)`

`ERROR`، على `nm`، مرة في كل سلسلة: خرج `nmcli` بالرمز 8 (NetworkManager نفسه لا يرد) لأول مرة؛ والرمز 8 اللاحق بعد قراءة سليمة يُعدّ. ما دام كذلك يقرأ سبب فشل الاتصال `NetworkManager not answering` وعلامة الجهاز `the stored network list cannot be read`. الدرجة L3 تعيد تشغيل NetworkManager. الحل: `systemctl status NetworkManager`؛ وإن تكرر فالخدمة تنهار.

### `rebooting now: wedged 30 min (HomeNet, OfficeNet on the air but this device cannot join) - reboot 1 for this fault, the story continues after the boot`

`ERROR`، قبل إعادة التشغيل مباشرة. الشبكة منقطعة فيقع السطر في المخزون لا على الموقع، لكن الحارس ينسخ المخزون كله مع هذا السطر إلى بطاقة الذاكرة بجانب السجل (`${LOG_FILE}.spool`) ويكتب علامة (`${LOG_FILE}.reboot`) وعدّاد إعادات التشغيل لهذا العطل (`${LOG_FILE}.reboots`)، فيسلّم البدء التالي القصة كلها بالترتيب ثم `starting after the reboot AWACS ordered at ...`. القوس هو العلامة التي حكمت: الشبكات المخزنة الظاهرة التي لا يُنضَم إليها، أو `the radio hears no network at all`، أو `the stored network list reads empty`. العدد يزيد مع كل إعادة تشغيل للعطل نفسه ويُحذف في أول دورة صحيحة. استمرت أدلة العطل في الجهاز `REBOOT_AFTER_MIN` دقيقة متصلة (افتراضياً 30). يُصفَّر المؤقت بأي دورة صحيحة أو تصنيف خارجي أو علامة كلمة سر خاطئة، وعلى `nm` بأي رصد لـ `NetworkManager` وهو ما زال يعمل؛ وعلى `nm` تشترط إعادة التشغيل أيضاً أن يكون `NetworkManager` قد استسلم: الحالة 30 (منفصل) أو 120 (فاشل) في تصنيفين متتاليين، أو تعذّر الوصول إلى `nmcli` بعد إعادة التشغيل في الدرجة الثالثة. لا يمكن تعطيل إعادة التشغيل؛ `REBOOT_AFTER_MIN` يؤخرها فقط. إن تكرر ذلك فالخلل تحت الحارس: التعريف، أو مزوّد الطاقة، أو بطاقة `SD`، أو موجّه يبثّ ولا يعطي عناوين. اقرأ `journalctl -b -1` و`dmesg` من الإقلاع السابق.

### `NM is still trying - waiting it out`

`INFO`، على `nm`، في بداية الجولة ومرة أخرى بعد جمع الأدلة؛ يُقال مرة لكل انقطاع، وتُعدّ المشاهدات اللاحقة وتأتي بعد `internet restored`. الجهاز في حالات الاتصال عند `NetworkManager` (من 40 إلى 90، أو 110): لا تُجرَّب الشبكات المخزنة، ولا تعمل درجة، ويُصفَّر مؤقت إعادة التشغيل. في بداية الجولة تسلك الجولة المسار الخارجي (يتبعه `outage looks external`، وتُجرَّب شبكات الطوارئ والمفتوحة مع ذلك، وتنتظر الجولة 20 ثانية)؛ وبعد جمع الأدلة لا تنتظر الجولة إلا 20 ثانية. طبيعي على `nm` أثناء الانقطاع.

### `NetworkManager is connected, internet is not (round 1) — router-side, no rung`

`INFO`، على `nm`، بعد جمع الأدلة: يبلّغ `NetworkManager` الحالة 100 (متصل، بعنوان) بينما يفشل فحص الإنترنت، وهذه مشكلة الموجّه. لا تعمل درجة، ويُصفَّر مؤقت إعادة التشغيل، وتُجرَّب شبكات الطوارئ والمفتوحة مع ذلك.

### `trying emergency networks (2 listed)`

`INFO`، بعد فشل الشبكات المخزنة، مرة لكل انقطاع (المرورات التالية تُعدّ)؛ يغيب حين يكون `SAFETY_NET` فارغاً. يُجرَّب كل مدخل بدوره، ظهر في المسح أم لا، نحو `ASSOC_WAIT` ثانية لكل محاولة على `wpa` (افتراضياً 25) وحتى ثلاثة أمثال ذلك على `nm`؛ والنجاح يسجّل `connected to EMERGENCY network: MyPhone (upload 850 kbps) - stored networks stay armed, home again when one returns` بقياس رفع واحد على الشبكة الجديدة (`signal mode` بدل الرقم بلا هدف قياس). مصير كل مدخل يُقال مرة لكل انقطاع بالأسطر الأربعة التالية؛ ويُختم المرور الخاسر بـ `no emergency network delivered (2 tried, 1 skipped)` بمستوى `INFO`. على `wpa` يُتخطّى الاسم الذي يحوي شرطة مائلة عكسية أو علامة اقتباس مزدوجة، وكلمة السر التي تحوي علامة اقتباس مزدوجة؛ وعلى `nm` يجب أن تكون كلمة السر من 8 إلى 63 حرفاً أو 64 رقماً سداسياً عشرياً.

### `emergency network MyPhone skipped: password must be 8-63 characters or 64 hex digits`

`ERROR`، على `nm`، مرة لكل انقطاع لكل مدخل: كلمة سر المدخل في `SAFETY_NET` ليست من 8 إلى 63 حرفاً ولا 64 رقماً ست عشرياً، فلا يُنشأ له ملف. عطل في الضبط لا في الشبكة. الحل: صحّح المدخل في `/etc/awacs.conf` وأعد تشغيل الحارس.

### `emergency network MyPhone skipped: name or password carries a quote or backslash the supplicant cannot take`

`ERROR`، على `wpa`، مرة لكل انقطاع لكل مدخل: يحوي الاسم شرطة مائلة عكسية أو علامة تنصيص مزدوجة، أو تحوي كلمة السر علامة تنصيص مزدوجة، وكلاهما لا يمر في وسيط `wpa_cli` المقتبس. الحل: غيّر اسم نقطة الاتصال أو كلمة سرها.

### `could not create the temporary entry for MyPhone - skipping it`

`WARN`، مرة لكل انقطاع لكل مدخل: رفضت الطبقة الأساسية إنشاء المدخل المؤقت (`add_network` أو `set_network` على `wpa`، أو كتابة ملف المفاتيح وتحميله على `nm`). `wpa_cli` الصامت يُفشل كل المدخلات بهذه الطريقة، بعدد القائمة؛ وتعالجه الدرجة L2. الحل: `wpa_cli status` بيدك؛ وعلى `nm` `journalctl -u NetworkManager`.

### `emergency network MyPhone refused: never associated - trying the next`

`WARN`، مرة لكل انقطاع لكل مدخل وسبب: أُنشئ المدخل وفشل الاتصال به؛ والسبب أحد أسباب الاتصال المذكورة تحت `could not connect to`. نقطة اتصال مطفأة أو خارج المدى أو بكلمة سر قديمة. يُجرَّب المدخل التالي. الحل: شغّل نقطة الاتصال، أو حدّث كلمة سرها في الملف.

### `trying open networks as last resort (3 open networks heard)`

`INFO`، بعد فشل شبكات الطوارئ، مرة لكل انقطاع (المرورات التالية تُعدّ)؛ يغيب ما لم يكن `OPEN_NETWORKS` هو `yes`. العدد هو الشبكات المفتوحة في صورة المسح التي يقرؤها المرور. تُجرَّب الشبكات بلا تشفير، الأقوى أولاً، مع تخطي الإشارات الأضعف من -80 dBm (على `wpa`) أو من 25 % (على `nm`)؛ وعلى `wpa` يُتخطّى الاسم الذي يحوي حروفاً غير `ASCII`. النجاح يسجّل `connected to OPEN network: FreeCafe (upload 620 kbps) - stored networks stay armed, home again when one returns`. المرور الخاسر يُختم بـ `no open network delivered internet (3 heard, 2 tried, 1 linked without internet)` بمستوى `INFO`، مرة لكل انقطاع، حتى حين لا تُسمع أي شبكة مفتوحة. يعيش المدخل المؤقت في `wpa_supplicant` الحي أو تحت `/run/NetworkManager/system-connections/`، ويُزال حين يعود الجهاز إلى شبكة مخزنة (`back on a stored network: HomeNet - temporary network FreeCafe removed`، بمستوى `OK`)، أو عند الإنعاش التالي (`dropping temporary network FreeCafe - it stopped delivering`، بمستوى `INFO` مرة لكل انقطاع)، أو عند بداية الحارس التالية (`removed the temporary network FreeCafe left by the previous run`).

### `open network FreeCafe linked but no internet (captive portal?) - trying the next`

`WARN`، مرة لكل انقطاع لكل شبكة: قامت الوصلة إلى الشبكة المفتوحة وحصل الجهاز على عنوان، وفشل فحص الإنترنت؛ صفحة دخول على الأغلب. تُجرَّب التالية؛ والشبكة الغريبة التي ترفض الارتباط أصلاً تُعدّ ولا تُقال لأن لا شيء يُفعل بشأنها. الحل: لا شيء؛ أو أضف شبكة تثق بها إلى `SAFETY_NET`.

### `could not return to HomeNet: never associated - stored networks re-enabled, waiting 20 s`

`WARN`، في الفرع الخارجي من الإنعاش، مرة لكل انقطاع: كانت الوصلة حية عند بدء الإنعاش فتُذكَّرت شبكتها بيتاً، وبعد محاولات الطوارئ والمفتوحة فشل الرجوع إليها بسبب حقيقي؛ أما `linked but no internet` فليس فشل رجوع بل الانقطاع الخارجي نفسه، ولا يُقال هنا. تُعاد كل الشبكات المخزنة إلى التفعيل وتنتظر الجولة 20 ثانية؛ والرجوع الناجح صامت. الحل: افحص الموجّه؛ الجولات التالية تُعدّ.

## الراديو والمسح

### `scan failed - using previous results (if any)`

`WARN`. أعاد `iw dev wlan0 scan` لا شيء بعد كل محاولة (ثلاث محاولات بينها 3 ثوانٍ، وست في الدقائق الثلاث الأولى بعد الإقلاع)، وأعاد `iwlist` وجدول النظام الخلفي نفسه (`wpa_cli scan_results` أو `nmcli device wifi list`) لا شيء أيضاً. تُحفظ الصورة السابقة ويُجدَّد ختمها الزمني، فيُسأل الراديو من جديد مرة كل `SCAN_TTL`. الرد `Device or resource busy` لا يُعاد المسح بعده: بعد 3 ثوانٍ يُقرأ `iwlist` وجدول النظام الخلفي بدلاً منه، ولا يظهر السطر إلا حين يكونان فارغين أيضاً. تشغيل `awacs.sh scan` يدوياً يسجّل السطر محلياً فقط. الحل إن استمر والجهاز متصل: `iw dev wlan0 scan` يدوياً يُظهر خطأ التعريف.

### `radio heard nothing on 3 scans in a row - previous results dropped`

`WARN`، مرة واحدة، لحظة إسقاط الصورة. ثلاثة مسوح متتالية، بكل مصدر في كل منها، لم تسمع أي شبكة؛ تُفرَّغ الذاكرة المؤقتة كي يتوقف الإنعاش وصندوق الأدوات وخانة الواي فاي عن عرض شبكات غير موجودة. المسح الفارغ دليل على أن العطل في الجهاز (الراديو السليم يسمع جيرانه)؛ وبعد `REBOOT_AFTER_MIN` دقيقة منه يتحقق شرط إعادة التشغيل. أول مسح يسمع شيئاً ينهي السلسلة بصمت. الحل: `rfkill list`، و`iw dev wlan0 scan` يدوياً، و`dmesg`. إن لم يتحرك الجهاز والجيران موجودون فالراديو أو تعريفه عالق.

## اختيار الشبكة

### `connected: HomeNet (signal mode - no upload probe target configured)`

`OK`؛ ويسجّل الرجوع إلى الشبكة المفضلة `returned to preferred network: HomeNet (signal mode)`. لا هدف للقياس: أبقى الإنعاش أقوى شبكة مخزنة أوصلت الإنترنت، ومضى الرجوع إلى الشبكة المفضلة بلا قياس. يطبع `awacs.sh speed` العبارة `no probe target (signal mode)`. للاختيار المقيس اضبط `SITE_URL` أو `PROBE_URL`.

### `sustained slow upload on HomeNet (150 kbps for 3 samples, floor 400) - evaluating known networks`

`WARN`؛ ومع بث حي يعمل يكون السطر `live stream starving on HomeNet (12 kbps for 3 samples, floor 50) - evaluating known networks`. يذكر السطر الشبكة، والتدفق المقروء، وعدد العيّنات (`UP_STRIKES`)، والحد الذي قيست عليه. بقيت العيّنة السلبية من عدّادات النواة (3 ثوانٍ) بين 20 كيلوبت/ث والحد الحالي (`MIN_UP_KBPS` نهاراً و`NIGHT_MIN_UP_KBPS` ليلاً) لمدة `UP_STRIKES` دورة متتالية، وانقضت فترة التهدئة منذ آخر تقييم؛ وصيغة البث تحتاج عملية `raspistill` تخدم `live_raw` أو `preview.jpg` أو `capture.jpg`، أو رفع `curl` يحوي `upfile=@`، وتدفقاً بين 5 كيلوبت/ث و`STREAM_MIN_KBPS`. وحين تنضج العيّنات وفترة التهدئة لم تنقضِ لا يُكتب التحذير بل `upload still slow on HomeNet (150 kbps, floor 400) - evaluation on cooldown, next look in 12 min` (أو `live stream still starving on HomeNet (12 kbps, floor 50) - evaluation on cooldown, next look in 12 min`) بمستوى `INFO`، مرة واحدة في نافذة التهدئة الواحدة، وليس قبل أول تقييم أبداً. يتبع التحذير سطرُ المسح `scan heard 6 networks: HomeNet -48, OfficeNet -61, Cafe -70 | known on the air: HomeNet, OfficeNet | stored, not heard: GarageNet` ثم قياس واحد للشبكة الحالية: `measured 250 kbps on HomeNet - under the 400 kbps floor, a challenger must beat 375 kbps` حين قاست تحت الحد، فتُجرَّب الشبكات المخزنة الظاهرة الأخرى (`trying <name>` ثم `candidate [<id>] <name> uploads at <n> kbps`، أو `could not connect to <name>: <reason> - trying the next`) والنتيجة `switching to <name> (<n> kbps against <m> kbps here)` يتبعها `switched to <name> (upload <n> kbps)`، أو مدخل البقاء التالي؛ والمرشح الذي يقيس أربعة أمثال الحد ينهي القياس ويحمل سطر تبديله الذيل `- plainly fast, over 4x the 400 kbps floor, probing stopped at it`. والقياس فوق الحد ينهي التقييم بـ `measured <n> kbps on <name> - above the <floor> kbps floor, staying`؛ والقياس الذي لم يُقبل يقول `upload probe failed on <name>` أدناه. الحل إن تكرر في كل فترة تهدئة: الشبكة بطيئة بالنسبة إلى الحد الذي ضبطته؛ عدّل `MIN_UP_KBPS` أو الحد الليلي، أو اقبل التبديل.

### `upload probe failed on HomeNet - the probe target accepted nothing (site or endpoint down?), counting it as 0 kbps`

`WARN`، في لحظة قرار فقط (قياس الشبكة الحالية عند بدء تقييم، أو مرشح، أو الوصول إلى شبكة مفضلة)، بدل سطر `measured 0 kbps`: لم يقبل هدف القياس أي بايت، لا عبر `curl` ولا عبر بديله `wget`. يُحسب القياس 0 كما كان: 0 للشبكة الحالية يجعل العتبة 0 وتُبقي قاعدة الزيادة على الصفر الجهاز على شبكته؛ و0 لشبكة مفضلة يُبعدها بسطر `preferred network ... too slow (0 kbps, ...)` الذي يتبعه. الإنترنت يعمل والموقع أو نقطة الاستقبال لا يقبلان الرفع. الحل: اختبار `400` في [integration.md](integration.md)؛ وانظر `site did not take the log line` إن ظهر معه.

### `no challenger beat the incumbent - staying on HomeNet (best was OfficeNet at 300 kbps, needed 375)`

`OK`. قاس تقييمٌ الشبكات المخزنة الأخرى ولم تتفوق أي منها على الحالية بالزيادة المطلوبة (`SWITCH_GAIN_PCT` نهاراً و`NIGHT_GAIN_PCT` ليلاً)؛ فعاد الجهاز إلى حيث كان. القوس يسمّي أقرب مرشح ورقمه والعتبة التي كان عليه بلوغها؛ وداخل الإنعاش يبقى السطر بلا قوس. وللمقارنة التي لم تقس أحداً أسطرها الصادقة: `no other known network on the air - staying on HomeNet at 250 kbps` حين لم يكن مرشح غير البيت ظاهراً، و`the only candidate did not deliver internet - staying on HomeNet at 250 kbps`، و`none of the 3 candidates delivered internet - staying on HomeNet at 250 kbps`؛ ويغيب ذيل الكيلوبت داخل الإنعاش. ليس خطأً.

### `could not connect to OfficeNet: linked but no internet - trying the next`

`WARN`، مرة لكل مرشح وسبب داخل مقارنة أو إنعاش (التكرار يُعدّ)؛ ويسبقه `trying OfficeNet`. السبب واحد من: `never associated` (لم يقم الارتباط خلال `ASSOC_WAIT`)، أو `associated but got no address` (ارتباط بلا عنوان IPv4)، أو `refused - wrong password?` (على `wpa` صف الشبكة يحمل `TEMP-DISABLED`؛ وعلى `nm` خطأ بيانات الاعتماد)، أو `not found on the air` (على `nm`)، أو `timed out after 25 s` (على `nm`، بحد `ASSOC_WAIT`)، أو `NetworkManager not answering` (خروج `nmcli` بالرمز 8)، أو `NetworkManager: <message>` (رسالة NetworkManager نفسها مقصوصة إلى 100 حرف حين لا تناسبها عبارة ثابتة)، أو `linked but no internet` (قامت الوصلة وفشل فحص الإنترنت)، أو `no association or no address` الاحتياطية. يُجرَّب المرشح التالي. الأسباب نفسها تظهر في كل سطر يحمل سبب اتصال: التبديل، والرجوع، والشبكة المفضلة، وشبكات الطوارئ. الحل إن فشلت الشبكة نفسها كل مرة: افحص كلمة سرها وموجّهها؛ وكلمة السر الخاطئة تنتج أيضاً `association refused by OfficeNet - wrong password? (recovery continues, reboot stays off)`.

### `switching to OfficeNet failed: never associated - going back to HomeNet`

`WARN`. اختارت المقارنة OfficeNet (يسبقه `switching to OfficeNet (...)`)، لكن الاتصال الثاني بها فشل بالسبب المذكور؛ فيعود الحارس إلى الشبكة التي غادرها ويسجّل `back on HomeNet`، أو `back on HomeNet - linked but still no internet` حين قامت الوصلة بلا إنترنت، أو `could not return to HomeNet: <reason>` حين فشل الرجوع نفسه. وداخل الإنعاش، حيث لا شبكة يُرجع إليها، ينتهي السطر عند السبب. شبكة عملت قبل لحظة توقفت عن الرد؛ ليس عطلاً في الحارس.

### `could not return to HomeNet: never associated`

`WARN`، مرة لكل انقطاع لكل شبكة وسبب (التكرار يُعدّ). فشل الرجوع إلى الشبكة السابقة بسبب حقيقي من أسباب الاتصال أعلاه: بعد مقارنة خاسرة، أو بعد تبديل فاشل، أو بعد عودة إلى شبكة مفضلة قيست بطيئة أو تعذر الوصول إليها. أما الوصلة التي تقوم إلى البيت بلا إنترنت فليست فشل رجوع بل الانقطاع نفسه، وتُقال بمستوى `INFO`: `back on HomeNet - linked but still no internet, recovery continues` داخل الإنعاش، و`back on HomeNet - linked but still no internet` خارجه، ويقول السطر الذي يليها ما يحدث بعدها. بعد المقارنة الخاسرة التي فشل رجوعها يُنضَم إلى أفضل مرشح على أي حال بسطر `switching to OfficeNet (300 kbps, below the 375 kbps bar) - the best left, HomeNet: never associated` (وداخل الإنعاش `switching to OfficeNet (0 kbps) - it delivered internet, HomeNet: never associated`). اقرأ الأسطر التالية: فحص الإنترنت التالي يقرر، ويبدأ الإنعاش إن غاب الإنترنت.

### `evaluation ended with no working network - on nothing now, the next check decides and recovery follows if the internet is gone`

`WARN`، مرة في نهاية تقييم فشل تبديله وفشل رجوعه معاً، أو لم يجد مرشحاً وفشل رجوعه: أُعيدت كل الشبكات المخزنة إلى التفعيل ثم قُرئت الشبكة الحالية، `on OfficeNet now` أو `on nothing now`. فحص الإنترنت التالي يقرر: إن غاب الإنترنت جاء `internet lost` والإنعاش خلال 30 إلى 45 ثانية. لا يُكتب داخل الإنعاش الذي لجولاته أسطرها.

### `could not reach the preferred network HomeNet: never associated - going back to Hotspot`

`WARN`. ظهرت شبكة أعلى أولوية في فحصين متتاليين لكن تعذر الانضمام إليها بالسبب المذكور؛ فيرجع الحارس إلى الشبكة التي كان عليها ويسجّل `back on Hotspot`، أو `back on Hotspot - linked but still no internet`، أو `could not return to Hotspot: <reason>` ثم `the way back to Hotspot failed` أدناه. وحين لا يعرف الحارس شبكته الحالية (`wpa_cli` صامت لحظتها) يقرأ الذيل `- no stored network to go back to, the next check decides`. تُعاد المحاولة بعد الرؤيتين التاليتين. الحل إن تكرر: الشبكة المفضلة ظاهرة لكنها ترفض هذا الجهاز؛ افحص كلمة سرها، وابحث عن `association refused by HomeNet - wrong password?`.

### `preferred network HomeNet too slow (120 kbps, floor 400) - benched for 60 min, going back to Hotspot`

`WARN`. ظهرت شبكة مخزنة أعلى أولوية في فحصين متتاليين (بينهما `PREF_CHECK`)، فانتقل الحارس إليها (يسبق هذا السطرَ `higher-priority network HomeNet visible twice - leaving Hotspot to go home`)، وقاسها تحت الحد المذكور، فعاد. مدة الإبعاد ثلاث فترات تهدئة: 60 دقيقة نهاراً و120 ليلاً بالافتراضيات. وحين تنهي هذه المرة إبعاداً جارياً لشبكة أخرى يُذيَّل السطر بـ `, ends the bench on OfficeNet`. وحين لا يعرف الحارس الشبكة التي جاء منها يقرأ الذيل `- benched for 60 min, staying on it`. والقياس الذي لم يُقبل يسبقه سطر `upload probe failed` ويقرأ هنا `0 kbps`. لا تُجرَّب تلك الشبكة مرة أخرى حتى ينقضي الإبعاد.

### `the way back to Hotspot failed - on no network now, the next check decides`

`WARN`، مرة، بعد محاولة شبكة مفضلة (بعد إبعادها، أو بعد فشل الاتصال بها) حين يفشل الرجوع إلى الشبكة السابقة بسبب حقيقي؛ يسبقه `could not return to Hotspot: <reason>`. وحين يكون السبب `linked but no internet` فالجهاز على الشبكة السابقة فعلاً، ويكفي سطر `back on Hotspot - linked but still no internet` ولا يُكتب هذا. أين الجهاز الآن يُقرأ بعد المحاولة. الحل: الفحص التالي يقرر؛ فإن غاب الإنترنت بدأ الإنعاش.

## أوامر الموقع

أسطر قائمة الواي فاي في الموقع: مسح عند الطلب، وتجربة يدوية لشبكة مخزنة (`switch`)، وتجربة شبكة جديدة بكلمة سر تُكتب على الموقع (`join`). القناة وحالات الجواب والمفتاح موصوفة في [integration.md](integration.md). كل سطر هنا يسمّي شبكات وأرقاماً فقط؛ ولا تصل كلمة سر ولا مفتاح ولا نص مشفّر إلى سجل أبداً.

صياغة الصفحة المقتبسة أدناه صياغة لوحة المتابعة المرجعية؛ والموقع الذي تبنيه أنت يصوغ رموز السبب بكلماته.

### `site command scan expired - it waited 2 min behind a recovery, tap again`

`INFO`. وصل الأمر إلى الجهاز قبل أكثر من 60 ثانية بساعة مدة التشغيل عند الجهاز (كان إنعاش جارياً، والأمر لا يُقرأ إلا في رأس الحلقة الرئيسية). تعرض صفحة الموقع `Command expired`. الحل: اضغط من جديد بعد رجوع الإنترنت.

### `site command switch refused - a recovery is running, tap again when the internet is back`

`INFO`. وصل الأمر أثناء إنعاش مشغول؛ ولا يجري شيء يخص أمراً داخل إنعاش. تعرض الصفحة `AWACS is busy`. الحل: انتظر `internet restored` ثم اضغط من جديد.

### `scan asked from the site while offline - the list cannot be published until the internet is back`

`INFO`. يمكن مسح الراديو لكن القائمة لا مكان تذهب إليه والإنترنت مقطوع؛ الجواب `failed` مع `offline` وتقول الصفحة إن الكاميرا بلا إنترنت. والسطر نفسه موجود لـ `switch` و`join` (`... recovery decides the network until the internet is back`).

### `scan asked from the site under a live stream - a few seconds of stutter`

`INFO`. المسح يأخذ الراديو عن قناته؛ والمالك طلب المسح فيجري مرة، ويتقطع البث المباشر على المشاهد أثناءه. و`manual trial under a live stream - the viewer stutters while the network changes` هو التحذير نفسه لتبديل أو انضمام.

### `scan from the site heard 7 networks - list published`

`INFO`. جرى المسح متجاوزاً ذاكرة `SCAN_TTL` وبوابة الدقيقة الواحدة، وأُرسلت القائمة في المقدمة، وتبعها الجواب `done` مع العدد. والصفحة التي ما زالت تعرض الصفوف القديمة لم تستطلع بعد.

### `switch asked from the site to OfficeNet - not a stored network, nothing to try`

`WARN`. المفتاح الذي أرسله الموقع لا يطابق أي شبكة مخزنة (أُزيلت الشبكة من `supplicant` أو NetworkManager بعد نشر القائمة، أو الصفحة قديمة). الجواب `failed` مع `out_of_reach`. الحل: امسح من جديد من القائمة؛ والشبكة غير المعروفة يُنضَم إليها ولا يُبدَّل إليها.

### `switch asked from the site to HomeNet - already on it`

`INFO`. الشبكة المختارة هي الحالية؛ لا يتحرك شيء والجواب `switched` مع آخر سرعة مقيسة (0 حين لا قياس).

### `switch asked from the site to HomeNet - already on it, holding it`

`INFO`. الحالة نفسها مع طلب تثبيت (`hold=<seconds>` في الحقل الخامس من الأمر): لا تجربة، يبدأ التثبيت الآن والجواب `switched NAME KBPS hold=<seconds>`؛ ويتبعه سطر `hold on HomeNet for 30 min ...`.

### `manual trial: OfficeNet for 15 s, leaving HomeNet (1200 kbps) - it stays only at 1800 kbps or more`

`INFO`، السطر الافتتاحي لكل تجربة. يسمّي الحارس من أين يترك، ورفع الأصل (آخر قياس له حين يكون أحدث من 120 ثانية، وإلا قياس واحد الآن)، والحد الذي يجب أن تبلغه التجربة: رفع الأصل مضروباً في `SWITCH_GAIN_PCT` (أو نسبة الليل) مقسوماً على 100، وهو الحد نفسه الذي يلقاه كل منافس. ثم الاتصال: الرابط الذي يتشكل ويوصل الإنترنت يُجاب بـ `trying`.

### `manual trial: OfficeNet upload 2000 kbps, the 1800 kbps bar met - staying on it`

`OK`. القياس الواحد، الجاري داخل الـ 15 ثانية على شبكة التجربة، وجدها عند الحد أو فوقه؛ تبقى الشبكة والجواب `switched` (أو `joined`). وفي وضع الإشارة يقرأ السطر `signal mode` مكان الرفع وتبقى أي شبكة توصل الإنترنت.

### `manual trial: OfficeNet uploads at 700 kbps, under the 1800 kbps bar (HomeNet 1200 kbps at 150%) - going back`

`INFO`. كانت شبكة التجربة أبطأ من الحد؛ يرجع الحارس إلى الأصل ويجيب بـ `returned` مع زوجَي الأرقام، وتقول الصفحة `Back on HomeNet`. هذا تصميم المالك: الاختيار اليدوي تجربة لا استيلاء.

### `manual trial: OfficeNet uploads at 700 kbps, under the 1800 kbps bar (HomeNet 1200 kbps at 150%) - staying anyway, held from the menu`

`INFO`. طلب التبديل تثبيتاً وفي شبكة التجربة إنترنت (حمل القياس بايتات، أو نجح الفحص السريع عند الحكم)، فتُبقى الشبكة الأبطأ كما طُلب؛ الجواب `switched NAME KBPS hold=<seconds>` والسطر التالي سطر التثبيت. والتبديل المثبَّت الذي تبلغ تجربته الحد يسجّل سطر `bar met - staying on it` المعتاد ثم سطر التثبيت.

### `hold on OfficeNet for 30 min - no preferred-network return and no evaluation leaves it; an internet loss or a new command ends it`

`INFO`. بدأ التثبيت: طوال تلك المدة (بساعة مدة تشغيل الجهاز) لا تجري نظرة الشبكة المفضلة ولا تقييم الرفع البطيء. والإنعاش لا يُمَس. والسطر الافتتاحي للتجربة سمّاه أيضاً: `... - the bar is 1800 kbps, and it stays for 30 min either way while it has internet`.

### `hold on OfficeNet ended - back to its own judgement`

`INFO`. انتهى وقت التثبيت؛ وتعود نظرة الشبكة المفضلة التالية والتقييم التالي إلى سلوكهما المعتاد. والنهايتان الأخريان: `hold on OfficeNet ended - internet lost` (انقطاع حقيقي: الإنعاش يختار الشبكة من هنا) و`hold on OfficeNet ended - a new command from the site` (أي أمر نفّذه الحارس؛ والتبديل المثبَّت الجديد يبدأ تثبيته الخاص).

### `manual trial: OfficeNet measured 0 kbps and fails the internet check - the hold is not taken, going back to HomeNet`

`INFO`. طلب التبديل تثبيتاً، لكن شبكة التجربة عند الحكم لم تحمل بايتات وفشل فحص الإنترنت السريع: الوصول أولاً، فيُرفَض التثبيت ويجري طريق العودة كأي تجربة أبطأ (`back on HomeNet` والجواب `returned`).

### `upload slow on OfficeNet (120 kbps, floor 400) - held from the menu, no evaluation until the hold ends in 25 min`

`INFO`، مرة لكل تثبيت. اكتملت ضربات الرفع البطيء أثناء تثبيت؛ والتقييم الذي كان سيجري الآن قد يترك الشبكة المثبَّتة، فلا يجري. وتُعدّ الضربات من جديد، ويأتي أول تقييم بعد التثبيت ما إن تكتمل.

### `hold on OfficeNet ends with this stop - the next start judges on its own`

`INFO`، ضمن أسطر الإيقاف السلس. يعيش التثبيت في الذاكرة فقط؛ والحارس المعاد تشغيله لا يعرف عنه شيئاً ويرجع إلى شبكة مفضلة أو يقيّم كالعادة.

### `manual trial: OfficeNet never associated - going back to HomeNet`

`WARN`. فشل الاتصال بشبكة التجربة؛ والسبب هو حكم الاتصال (`never associated` أو `not found on the air` أو `associated but got no address` أو `refused - wrong password?` أو `linked but no internet` أو `timed out after 45 s` على NetworkManager) ويتبعه رمز سبب الجواب: `wrong_password` للرفض، و`no_internet` لرابط بلا إنترنت، و`out_of_reach` لكل ما عداهما. يرجع الحارس إلى الأصل فوراً. ينتظر اتصال التجربة `TRIAL_ASSOC_WAIT` (45 ثانية، أو `ASSOC_WAIT` حين تكون أكبر) حيث ينتظر الإنعاش `ASSOC_WAIT`: الشبكة الجديدة أو البعيدة قد تمسح 7 إلى 23 ثانية قبل أن تصادق، وتُقرأ علامة كلمة السر الخاطئة طوال الميزانية، فلا تُجاب شبكة في المتناول بـ `out_of_reach` ولا كلمة سر خاطئة كذلك. وللانضمام يبدأ السطر بـ `join: NAME ... - removing it, going back to HomeNet` ويُزال المدخل.

### `back on HomeNet`

`OK`. طريق العودة بعد تجربة شكّل رابطاً وأوصل الإنترنت. والعودة التي ترتبط بلا إنترنت لا تقول شيئاً أكثر هنا (الانقطاع في الأعلى؛ والجهاز في بيته) وتُحسب مع ذلك `returned`.

### `the way back to HomeNet failed - on no network now, the next check decides and recovery follows if the internet is gone`

`WARN`. لم يأخذ الأصل الجهاز بعد التجربة (و`on OfficeNet now` حين يجلس الجهاز على شبكة ما). الجواب `failed` مع `return_failed`؛ والدورة التالية تقرر ويتولى الإنعاش العادي إن غاب الإنترنت. لم يُعطَّل شيء: كل شبكة مخزنة تُعاد إلى التفعيل عند كل خروج من تجربة.

### `join asked from the site: CafeNet - adding it at runtime and trying it for 15 s`

`INFO`. فُتحت كلمة السر واجتازت قاعدة الشكل (8 إلى 63 حرفاً أو 64 خانة ست عشرية، بلا جدولة ولا سطر جديد)؛ تُضاف الشبكة في وقت التشغيل فقط (`add_network` على `wpa`، وملف مفاتيح `awacs-join-<epoch>-<pid>` في `/run` على `nm`) وتتبعها التجربة أعلاه. وعلى `wpa` لا يمكن تمرير كلمة سر تحمل علامة تنصيص مزدوجة أو شرطة مائلة عكسية إلى `supplicant`، فتُرفض قبل هذا السطر: `join: the supplicant cannot take a quote or backslash in a password - CafeNet not added` (`WARN`، والجواب `wrong_password`). وكلمة السر خارج قاعدة الشكل `join asked from the site for CafeNet - the password must be 8 to 63 characters or 64 hex digits`.

### `join asked from the site for CafeNet - the password could not be opened with this device's key; the site holds another key? open admin/wifi.php?reset_key=1 once and try again`

`WARN`. لم يثبت `MAC` الحزمة أو فشل فكّ التشفير: شفّر الموقع بمفتاح ليس مفتاح هذا الجهاز (أُعيد تثبيت البطاقة والموقع ما زال يحمل المفتاح القديم، أو ملف المفتاح معطوب). يعرض الحارس مفتاحه على الموقع من جديد (لا يُؤخذ إلا بإثبات) ويجيب بـ `failed` مع `key_changed`؛ وتسمّي الصفحة خطوة إعادة الضبط. الحل: افتح `admin/wifi.php?reset_key=1` في الموقع مرة تحت رمز الإدارة، وانتظر `device key registered with the site` (خلال الدقيقة الصحيحة التالية)، ثم انضم من جديد.

### `joined CafeNet - password kept in /etc/awacs.networks, re-added at every start`

`OK`. ارتبطت شبكة التجربة وأوصلت الإنترنت، فكلمة السر صحيحة؛ كُتبت في `/etc/awacs.networks` (لـ `root` بصلاحية 0600) قبل أي شيء آخر، وعلى `nm` تولى ملف التعريف الدائم `awacs-joined-<hexssid>` مكان مدخل التجربة. وما زالت تجربة الـ 15 ثانية تقرر هل يبقى الجهاز (`joined`) أم يرجع إلى أصل أسرع (`returned`)؛ وكلمة السر محفوظة في الحالين. و`joined CafeNet but /etc/awacs.networks could not be written - the network lasts until the next start` (`WARN`) يعني أن بطاقة الذاكرة رفضت الكتابة: تعمل الشبكة حتى البدء التالي ولا تُعاد إضافتها. وعلى `nm` يعني `join: the stored entry for CafeNet could not take over - riding the trial entry until the next start` (`WARN`) أن ملف التعريف الدائم لم يُفعَّل؛ ويحمل مدخل التجربة الجهاز حتى يعيد البدء التالي إضافة الشبكة من الملف.

### `re-added 1 networks joined from the site: CafeNet`

`INFO`، عند البدء وبعد درجات الإنعاش التي تعيد تشغيل `supplicant` (`L2` و`L3` على `wpa`) أو NetworkManager (`L3` على `nm`). أُضيف من جديد كل سطر في `/etc/awacs.networks` لا ملف تعريف لاسمه بعد. والشبكة التي تعذرت إعادة إضافتها لها `WARN` خاص: `joined network CafeNet could not be re-added to the supplicant` (أو `... to NetworkManager`، أو `joined network CafeNet refused by the supplicant - not re-added`).

### `removed an unfinished join of CafeNet left by the previous run`

`INFO`، عند البدء. مات الحارس السابق بين إضافة شبكة من الموقع وإثبات كلمة سرها (`/run/awacs/join_id` كان ما زال هناك)؛ يُزال المدخل كي لا يبقى شيء أنشأه الحارس بعده. وعلى `wpa` لا يذهب المدخل إلا ما دام معرّفه يحمل ذاك الاسم. الحل: لا شيء؛ انضم من جديد من القائمة.

### `device key made for passwords typed on the site (/etc/awacs.key)`

`INFO`، مرة. أول بدء وجد `openssl` صنع مفتاح الجهاز (64 خانة ست عشرية، لـ `root` بصلاحية 0600). و`could not write /etc/awacs.key - join from the menu is off` و`could not make the device key (openssl rand failed) - join from the menu is off` (كلاهما `WARN`) يعنيان أن الملف لم يُصنع؛ ويبقى المسح والتبديل يعملان.

### `device key registered with the site - a password typed there can be opened here`

`INFO`، مرة في الإقلاع. رد الموقع بـ 2xx على `file=wifi_key`، عند البدء أو في الدورة الصحيحة الثالثة ثم مرة كل دقيقة صحيحة حتى يُقبل. وحتى يظهر هذا السطر في الإقلاع قد لا يحمل الموقع مفتاحاً بعد، وتجيب نافذة الانضمام فيه `the camera has not registered a key yet (AWACS start pending)`.

### `the site holds another key for this camera (a reflash?) - open admin/wifi.php?reset_key=1 once from your phone, then join from the menu works again`

`WARN`، مرة في الإقلاع. رد الموقع بـ 403 على التسجيل: يحمل مفتاحاً مختلفاً وهذا الجهاز لا يستطيع إثبات تدوير (لا `/etc/awacs.key.prev` بالمفتاح الذي عرفه الموقع)، وهذه حال ما بعد إعادة التثبيت. والمستقبِل الذي لا يعرف `wifi_key` أصلاً يرد بـ 403 أيضاً (`Error: forbidden file`) ويستحق هذا السطر؛ حدّث المستقبِل أو تجاهله. يبقى المسح والتبديل يعملان؛ ويفشل الانضمام بـ `key_changed` حتى ينسى الموقع المفتاح القديم. الحل: خطوة إعادة الضبط التي في السطر، مرة، تحت رمز الإدارة. ومع المستقبِلَين المرفقَين احذف `private/wifi.key` في مجلد الجهاز.

### `openssl is missing - a password typed on the site cannot be opened here, join from the menu is off`

`WARN`، عند البدء. `openssl` غير مثبّت، فلا يُصنع مفتاح ولا تُفتح كلمة سر؛ و`openssl` جزء من كل صورة Raspberry Pi OS، فهذا يشير إلى صورة مقلَّمة. الحل: `apt-get install openssl` ثم أعد تشغيل الحارس.

### الأسطر المحلية لقناة الأوامر

خمسة أسطر `INFO` تبقى في السجل المحلي ولا تصل إلى الموقع أبداً، لأنها تصف سطراً لم يقصده الموقع أو سبق تنفيذه: `site command dropped - unreadable line` (السطر المنقول لم يجتز فحص الشكل)، و`site command scan delivered twice (epoch N) - already handled` (أرسل الناقل الإشارة مرتين لأمر واحد؛ التقطها `/run/awacs/cmd.last`)، و`site switch dropped - no network key` و`site join dropped - no network key or no password` (لم يسمّ الأمر شبكة؛ والموقع يجيب عن هذه الحالات بنفسه قبل الإرسال)، و`site switch: the fifth field is not a hold - switching without one` (تبديل حقله الخامس ليس فارغاً ولا `hold=<1 إلى 86400>`). أما أسطر الناقل المحلية (`wifi command relayed to awacs`، و`wifi command dropped ... awacs is not running`، و`... an older build without the command trap`) فتخص سكربت التصوير في لوحة المتابعة المرجعية وسجله المحلي لا هذا الحارس.

## التقارير

### `site did not take the log line (http 500) - holding lines, delivery retried about every 5 min`

`WARN`، مرة في كل نوبة رفض: رد الموقع على سطر قصة، حي أو من المخزون، برمز خارج 2xx و3xx، أو لم يرد خلال حد `curl` (`no reply in 4 s`)، بينما الإنترنت يعمل. يُحتفظ بالسطر المرفوض في المخزون ويُلحق هذا التحذير خلفه، ويُكتب في الملف المحلي أيضاً (يمر مرشح `remote` لأنه `WARN`). كل رفض لاحق صامت حتى يسلّم تفريغ الأسطر المحتجزة كلها فيختم النوبة بسطر `site reachable again - delivered 9 held lines stamped 03:10 to 03:41, they stand above this line with their own times` بمستوى `OK`؛ والتفريغ الذي يسلّم أسطراً محتجزة بلا نوبة رفض يقول `delivered 9 held lines stamped 03:10 to 03:41 - they stand above this line with their own times` بمستوى `INFO` (وللسطر الواحد `delivered 1 held line stamped 03:10 - it stands above this line with its own time`). الدقائق هي إيقاع التفريغ: كل 30 دورة صحيحة، أي `TICK` مضروباً في 30 مقسوماً على 60. الحل: نقطة الاستقبال ترفض أو معطلة؛ افحص سجل الخادم واختبار `400` في [integration.md](integration.md). الرمز رمز نقطة الاستقبال: 500 المستقبِل يفشل، و403 أو 404 خطأ في `SITE_URL` أو `SITE_API` أو مجلد الجهاز، ولا رد مضيف لا يجيب.

### `outage story trimmed - 14 lines dropped from its middle (the spool keeps 60)`

`WARN`، مرة لكل انقطاع، بعد تفريغ سلّم كل الأسطر المحتجزة وبعد سطر `delivered`: تجاوز المخزون `SPOOL_CAP` سطراً أثناء الانقطاع فسقطت أسطر من وسطه (السطر الأول محفوظ دائماً). العدد مجموع كل قصّ في الانقطاع، محفوظ في `/run/awacs/spool.dropped`، فيقوله خليفة الحارس عن سلفه أيضاً. الحل: ارفع `SPOOL_CAP` إن أردت القصة كاملة.

### `stop drain reached its budget - the remaining held lines wait for the next start`

`INFO`، الملف المحلي فقط، مرة في الإيقاف الواحد على الأكثر. تفريغ الإيقاف (عند `SIGTERM` أو `SIGINT` أو `SIGHUP` أو خروج المصيدة) يرسل المحتجز في المقدمة، لكنه محدود بستة أسطر أو 20 ثانية كي ينتهي داخل `TimeoutStopSec=40` في الوحدة؛ وما بعد الحد يبقى في المخزون ويسلّمه تفريغ بدء الخليفة، ولا يُكتب سطر `delivered` في تفريغ الإيقاف. الحل: لا شيء؛ القصة تصل مع البدء التالي.

### `wifi cell not accepted by the site (http 403) - the page drops the cell when it goes stale`

`WARN`، مرة في كل نوبة: رد الموقع على إرسال خانة الواي فاي (`file=tmp/wifi.tmp`) برمز خارج 2xx و3xx، أو لم يرد (`no reply in 4 s`). يتكرر الإرسال كل نحو 60 ثانية من الصحة بصمت حتى يُقبل، فيُكتب `wifi cell accepted again` بمستوى `OK`. حين يكون الموقع معطلاً كله يظهر هذا التحذير و`site did not take the log line` معاً، كل منهما مرة عن قناته. الحل: كما في مدخل الموقع؛ و`403` يعني أن المستقبِل يرفض هذا الملف أو هذه الهوية.

### `wifi scan list not accepted by the site (http 500) - the list behind the WiFi box will not show`

`WARN`، مرة في كل نوبة: رد الموقع على إرسال قائمة المسح (`file=tmp/wifi_scan.tmp`) برمز خارج 2xx و3xx، أو لم يرد (`no reply in 4 s`)؛ فتبقى قائمة الشبكات المسموعة على الموقع كما كانت. يتكرر الإرسال كل دقيقة بصمت ما دامت النوبة، حتى يُقبل فيُكتب `wifi scan list accepted again` بمستوى `OK`. القائمة تتبع مفتاح الخانة `REPORT_WIFI`، فـ `no` يوقف الاثنتين معاً. الحل: كما في مدخل الخانة؛ و`403` يعني أن المستقبِل لا يعرف هذا الملف، فالمستقبِلان المرفقان يقبلان أسماء ملفات محددة فقط (انظر [integration.md](integration.md)).

### `local log /var/log/awacs.log not writable - SD card read-only? the site keeps the story`

`WARN`، يصل إلى الموقع، مرة في كل سلسلة فشل: فشل إلحاق سطر بالملف المحلي (العلامة `/run/awacs/log.down`)، ويُقال في أول دورة صحيحة بعده؛ إلحاق هذا السطر نفسه يفشل أيضاً ولا يعيد تسليح شيء. حين ينجح إلحاق من جديد يُكتب `local log /var/log/awacs.log writable again` بمستوى `OK` مرة. بلا `SITE_URL` لا شاهد على الفشل. السبب المعتاد بطاقة ذاكرة صارت للقراءة فقط، أو نظام ملفات ممتلئ، أو مجلد غائب. الحل: `mount | grep ' / '` و`df -h` و`dmesg | grep -i mmc`.

## حواجز لا يجب أن تعمل أبداً

### `BUG: wpa_cli reached under nm backend: ...`

`ERROR`، السجل المحلي فقط. استدعى مسار في الكود مساعد `wpa` بينما النظام الخلفي هو `NetworkManager`؛ يُرجع الاستدعاء فشلاً ولا يصل شيء إلى `wpa_cli`. أبلغ عنه مع سطر السجل؛ فهو يسمّي الوسائط.

### `REFUSING delete: 'name' is not an awacs profile`

`ERROR`، السجل المحلي فقط، على `nm`؛ والصيغة الثانية `REFUSING delete: 'name' lives outside /run (owner file?)`. طُلب حذف ملف تعريف لا يحمل اسم `awacs-crutch-*` أو `awacs-safety-*` أو `awacs-join-*` أو `awacs-joined-*`، أو ليس ملفه تحت `/run/NetworkManager/system-connections/`؛ ولم يحدث الحذف. هذا آخر حاجز أمام ملفات تعريفك أنت. أبلغ عنه مع سطر السجل.

## صندوق الأدوات

### صندوق `ROOT ACCESS REQUIRED`

`status` و`networks` و`evaluate` و`scan` و`speed` تحتاج `root`: فهي تقرأ `wpa_supplicant` أو `NetworkManager` ومجلد الحالة الخاص. فقط `check` و`help` تعملان بلا صلاحيات.

### `usage: awacs.sh [status|networks|evaluate|scan|speed|check|help|-d]   (no argument = daemon)` ورمز الخروج 1

الكلمة مكتوبة خطأً. يجري الفحص قبل بوابة `root`، فيبقى الخطأ المطبعي ونسيان `sudo` متمايزَين.

### صندوق `INSTANCE ERROR`

شغّلت الحارس يدوياً بينما تحمل نسخة أخرى القفل (`flock` على `/run/awacs/lock`)؛ ويُظهر الصندوق رقم عملية تلك النسخة. بلا طرفية تخرج النسخة الخاسرة بالرمز 0 بعد أن تكتب، مرة في كل إقلاع، السطر `another AWACS already holds the lock (pid N) - ...` في المخزون المشترك. استعمل كلمات صندوق الأدوات بدلاً من ذلك؛ فهي تعمل بجانب الحارس بلا أخذ القفل.

### `awacs.sh speed` يطبع `0 kbps — probe failed`

لم يقبل هدف القياس الرفع ضمن المهلة، لا مع `curl` ولا مع بديله `wget`. الحارس نفسه يقول الشيء نفسه في لحظات قراره بسطر `upload probe failed on <name> - the probe target accepted nothing (site or endpoint down?), counting it as 0 kbps`. افحص الهدف باختبار `400` في [integration.md](integration.md). أما `no probe target (signal mode)` فيعني أن لا `SITE_URL` ولا `PROBE_URL` مضبوط.

## أعراض بلا سطر خاص بها

### `awacs.sh status` يبلّغ عن الحارس `NOT running`

يقرأ صف `daemon` القيمة `running (pid N)` حين يكون رقم العملية المكتوب في `/run/awacs/lock` حياً وسطر أمره يسمّي `awacs`، و`NOT running` فيما عدا ذلك. افحص المشغّل: `systemctl status awacs`، أو سطر `/etc/rc.local` مع `pgrep -af awacs.sh`؛ ثم `journalctl -u awacs` لحالة الخروج، والسجل المحلي لمعرفة إلى أين وصلت البداية الأخيرة.

### سجل الموقع لا يُظهر شيئاً رغم أن `LOG_TARGET` هو `both`

افحص بالترتيب. نقطة الاستقبال ترد من الجهاز: `curl -s -o /dev/null -w '%{http_code}\n' --data-urlencode probe=1 "$SITE_URL/$DEVICE_ID/receiver.php"` (أو اسم `SITE_API`) يجب أن يطبع `400`. ملف الضبط مطبَّق: لا رفض في الخرج القياسي للأخطاء، وسطر `reporting:` يسمّي الموقع. الأسطر المنتظرة في المخزون المؤقت `/run/awacs/spool` تُسلَّم بعد نحو 30 ثانية من ثبوت صحة الإنترنت ويُعاد إرسالها كل 5 دقائق تقريباً؛ ورفض الموقع لها يُقال في الملف المحلي بسطر `site did not take the log line (...)`، وتسليمها بسطر `delivered N held lines ...`. ثم اقرأ `log/log.txt` عند المستقبِل على الخادم.

### أسطر سجل الموقع بلغة غير المطلوبة

`SITE_LANG` يختار لغة نسخة الموقع و`LOG_LANG` لغة الملف المحلي، وكل منهما `en` (الافتراضي) أو `ar`؛ والسطر الذي لا نص عربياً له يبقى بالإنجليزية. اضبط المفتاح في `/etc/awacs.conf` وأعد تشغيل الحارس. أسطر `DEBUG` بالإنجليزية في الحالتين.

### سطر البداية يتكرر كل 10 ثوانٍ

يخرج الحارس بعد قليل من `AWACS 1.0 starting on wlan0 (device mydevice) - wpa backend, restart N of this boot` وتعيد حلقة التشغيل (`rc.local` أو `Restart=always`) إطلاقه بعد 10 ثوانٍ؛ ويزيد العدد في ذيل السطر مع كل مرة. يسبق كل بداية سطر `AWACS exited unexpectedly (status N, last command ...)` يسمّي الأمر الذي أخرج الحارس وحالته؛ ويُظهر `journalctl -u awacs` حالة الخروج نفسها؛ وتُظهر الأسطر المحلية بين سطرَي بداية إلى أين وصل. المشغّل الثاني لا ينتج هذا العرض: النسخة التي تخسر القفل لا تكتب سطر بداية، بل سطر `another AWACS already holds the lock` مرة في الإقلاع.

### مشغّلان اثنان

يعمل الحارس من `/etc/rc.local` ومن `awacs.service` معاً. تخسر النسخة الثانية القفل وتخرج بالرمز 0 ويُعاد إطلاقها كل 10 ثوانٍ؛ وتكتب أول خسارة في الإقلاع السطر `another AWACS already holds the lock (pid N) - two launchers are running it, keep one (the rc.local line or the systemd unit)` الذي يسلّمه تفريغ النسخة الرابحة إلى الموقع، وتصمت الخسارات التالية. يُظهر `journalctl -u awacs` بداية وخروجاً نظيفاً كل 10 ثوانٍ، أو يُظهر `pgrep -af awacs.sh` نسخة ليست العملية الرئيسية للوحدة. الحل: أبقِ مشغّلاً واحداً.

### خانة الواي فاي لا تُظهر سرعة

طبيعي. تُقاس السرعة في لحظات القرار فقط (مرشح أثناء الإنعاش، أو تقييم بعد رفع بطيء، أو الوصول إلى شبكة مفضلة)، وتُعرض فقط ما دام الجهاز على الشبكة التي قيست عليها؛ و`0` في الحقل الأول يعني أنه لا قياس لهذه الشبكة بعد.

## أسطر أخرى

أسطر بلا مدخل أعلاه، بقيم نموذجية. تحمل أسطر الموقع الحدث نفسه بلغة `SITE_LANG`.

| السطر | المستوى | متى |
| --- | --- | --- |
| `AWACS 1.0 starting on wlan0 (device mydevice) - wpa backend, first start of this boot, up 1 min` | `INFO` | كل بداية للحارس؛ والذيل `restart N of this boot` حين أعاده المشغّل. |
| `running with: measured mode, floor 400/200 kbps day/night (night 22:00-06:00), switch gain 150%, one evaluation per 20 min, reboot after 30 min wedged, wifi cell on, 3 stored networks, 0 emergency, open networks yes, stamps in the device zone` | `INFO` | كل بداية، بعد أحكام ملف الضبط؛ وبلا هدف قياس `running with: signal mode (no probe target - networks chosen by signal), ...`. |
| `online at start via HomeNet` | `OK` | نجح فحص الإنترنت الأول عند البدء، بعد تفريغ المخزون. |
| `removed the temporary network FreeCafe left by the previous run` | `INFO` | البدء يجد مدخلاً مؤقتاً تركه حارس سابق والجهاز ليس عليه. |
| `stealth mode active (icmp hidden, avahi stopped)` | `INFO` | البداية مع `STEALTH_MODE="yes"` حين تنجح الخطوتان. |
| `NetworkManager backend - AWACS supervises it (full capability)` | `INFO` | البداية على `nm`. |
| `internet back on HomeNet - monitoring only` | `OK` | عودة الإنترنت في وضع المراقبة فقط، بعد تفريغ المخزون. |
| `clock set forward 7 h 0 min by time sync - the lines above carry the old time` | `INFO` | قفزت ساعة الجهاز أكثر من 60 ثانية بين دورتين (مزامنة الوقت على لوحة بلا ساعة ببطارية)؛ و`back` للقفزة إلى الخلف. |
| `device id changed: cam1 -> cam2 - reporting under cam2 from now` | `INFO` | تغيّرت هوية الجهاز أثناء العمل. |
| `day profile active until 22:00 - floor 400 kbps, a challenger must reach 150% of the incumbent, evaluations 20 min apart` | `INFO` | الدورة الأولى نهاراً، ثم عند `NIGHT_END` (مع `NIGHT_MODE="yes"`). |
| `night profile active until 06:00 - floor 200 kbps, a challenger must reach 300% of the incumbent, evaluations 40 min apart` | `INFO` | الدورة الأولى ليلاً، ثم عند `NIGHT_START`. |
| `uplink answering late on HomeNet - 3 quick checks timed out, the patient check passed, no recovery` | `INFO` | بداية نوبة تأخر؛ ثم `internet answered late N more times in the last hour on HomeNet - slow link, no recovery` كل ساعة على الأكثر، و`uplink answers normally again on HomeNet - answered late N times over 26 min` عند ختمها. |
| `router answers on HomeNet - keeping the link, trying the other stored networks first` | `INFO` | افتتاح الإنعاش على وصلة حية، مرة لكل انقطاع؛ وعلى `wpa` في الإنعاش الثاني `router answers on HomeNet but forwards nothing - reassociating anyway this time`؛ وعلى وصلة ميتة `router not answering - waiting up to 25 s for wlan0 to reconnect`. |
| `reboot clock cleared - NetworkManager picked the device up again` | `INFO` | على `nm`، بعد `reboot clock armed`، حين يلتقط NetworkManager الجهاز من جديد. |
| `internet restored: HomeNet - down 5 min, 3 recovery runs` | `OK` | عاد الإنترنت بعد فقده؛ المدة من سطر الفقد، والعدد إنعاشات الانقطاع (`1 recovery run` للواحد). |
| `repeated 3 more times during the outage (last at 03:41): recover L1: radio bounce` | `INFO` | بعد `internet restored`، سطر لكل خطوة تكررت في الانقطاع، بوقت آخر تكرار. |
| `connected to EMERGENCY network: MyPhone (upload 620 kbps) - stored networks stay armed, home again when one returns` | `OK` | أوصلت شبكة طوارئ الإنترنت؛ `(signal mode)` بلا هدف قياس. |
| `no emergency network delivered (2 tried, 1 skipped)` | `INFO` | انتهى مرور شبكات الطوارئ بلا فوز، مرة لكل انقطاع. |
| `trying open networks as last resort (3 open networks heard)` | `INFO` | بدء مرور الشبكات المفتوحة، مرة لكل انقطاع. |
| `connected to OPEN network: FreeCafe (upload 620 kbps) - stored networks stay armed, home again when one returns` | `OK` | أوصلت شبكة مفتوحة الإنترنت. |
| `no open network delivered internet (3 heard, 2 tried, 1 linked without internet)` | `INFO` | انتهى مرور الشبكات المفتوحة بلا فوز، مرة لكل انقطاع. |
| `dropping temporary network FreeCafe - it stopped delivering` | `INFO` | بداية إنعاش والجهاز على شبكة مؤقتة توقفت عن التوصيل، مرة لكل انقطاع. |
| `back on a stored network: HomeNet - temporary network FreeCafe removed` | `OK` | الدورة الصحيحة التي تجد الجهاز على شبكة مخزنة بعد شبكة مؤقتة. |
| `scan heard 6 networks: HomeNet -48, OfficeNet -61, Cafe -70 \| known on the air: HomeNet, OfficeNet \| stored, not heard: GarageNet` | `INFO` | ما سمعه الراديو حين بدأ التقييم، الأقوى أولاً؛ وداخل الإنعاش مرة لكل صورة مختلفة في الانقطاع. |
| `measured 250 kbps on HomeNet - under the 400 kbps floor, a challenger must beat 375 kbps` | `INFO` | قياس الشبكة الحالية عند بدء تقييم؛ وينتهي بـ `- above the 400 kbps floor, staying` حين لا تتبعه مقارنة؛ وبلا ذيل عند الوصول إلى شبكة مفضلة. |
| `upload still slow on HomeNet (150 kbps, floor 400) - evaluation on cooldown, next look in 12 min` | `INFO` | نضجت العيّنات البطيئة وفترة التهدئة لم تنقضِ، مرة في النافذة؛ وتحت بث `live stream still starving on HomeNet (12 kbps, floor 50) - evaluation on cooldown, next look in 12 min`. |
| `trying OfficeNet` | `INFO` | مرشح يُتصل به. |
| `candidate [3] OfficeNet uploads at 850 kbps` | `INFO` | كل مرشح مقيس. |
| `switching to OfficeNet (850 kbps against 250 kbps here)` | `INFO` | الفائز قبل الانتقال؛ و`(850 kbps, the fastest candidate)` داخل الإنعاش؛ ويُذيَّل بـ `- plainly fast, over 4x the 400 kbps floor, probing stopped at it` حين أنهى القياس مبكراً. |
| `switching to OfficeNet (300 kbps, below the 375 kbps bar) - the best left, HomeNet: never associated` | `INFO` | خسر المرشح المقارنة وفشل الرجوع إلى البيت فأُخذ على أي حال؛ وداخل الإنعاش `switching to OfficeNet (0 kbps) - it delivered internet, HomeNet: never associated`. |
| `switched to OfficeNet (upload 850 kbps)` | `OK` | أُخذ أفضل مرشح مقيس. |
| `no other known network on the air - staying on HomeNet at 250 kbps` | `OK` | مقارنة بلا مرشح غير البيت؛ وأخواتها `the only candidate did not deliver internet - staying on HomeNet at 250 kbps` و`none of the 3 candidates delivered internet - staying on HomeNet at 250 kbps`؛ وبلا ذيل الكيلوبت داخل الإنعاش. |
| `back on HomeNet` | `OK` | الرجوع بعد تبديل فاشل أو شبكة مفضلة بطيئة. |
| `back on HomeNet - linked but still no internet` | `INFO` | الرجوع قام بلا إنترنت خارج الإنعاش؛ وداخله `back on HomeNet - linked but still no internet, recovery continues`. |
| `higher-priority network HomeNet visible twice - leaving OfficeNet to go home` | `INFO` | رصدان متتاليان لشبكة مفضلة؛ ويُذيَّل بـ `(seen and lost 3 times before)` حين تذبذبت في هذه الإقامة قبل أن تثبت. |
| `preferred network HomeNet was visible at one check and gone at the next - staying on OfficeNet until it holds for two checks in a row` | `INFO` | شبكة مفضلة ظهرت بفحص وغابت بالتالي، مرة في الإقامة الواحدة على الشبكة الحالية. |
| `returned to preferred network: HomeNet (upload 900 kbps)` | `OK` | اجتازت الشبكة المفضلة القياس. |
| `delivered 9 held lines stamped 03:10 to 03:41 - they stand above this line with their own times` | `INFO` | تفريغ سلّم أسطراً محتجزة؛ و`site reachable again - delivered ...` بمستوى `OK` حين يختم نوبة رفض الموقع. |
| `wifi cell accepted again` | `OK` | قبل الموقع خانة الواي فاي بعد رفض. |
| `wifi scan list accepted again` | `OK` | قبل الموقع قائمة مسح الواي فاي بعد رفض. |
| `local log /var/log/awacs.log writable again` | `OK` | نجح الإلحاق بالملف المحلي بعد فشل. |
| `AWACS stopping on SIGTERM (systemctl stop or shutdown) - stored networks re-enabled, the network layer runs on its own until the next start` | `INFO` | الإيقاف بإشارة، مرة؛ وتُسمّى الإشارة: `SIGINT (Ctrl+C)`، `SIGHUP (terminal closed)`، `SIGQUIT`. يُرسل في المقدمة قبل الخروج ولا يعد بإعادة تشغيل. |

أسطر `DEBUG` أخرى (`scan: 1/3 tries used` و`connect_id: activating ...` و`QA: flow=...` و`best_pref_id: ...` و`quick check timed out under load (sent ${sent} B during it) - patient check passed` و`sent ${sent} B during the failed quick check, the patient check failed too - counting it` و`gentle open skipped: the link is alive (gateway reachable) - the outage is upstream`) تتتبع القرارات في الملف المحلي وتُسكَت بـ `DEBUG="no"`.

</div>
