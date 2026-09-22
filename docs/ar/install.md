<div dir="rtl">

# التثبيت

AWACS سكربت واحد، `awacs.sh`، زائد ملف إعدادات اختياري واحد، `/etc/awacs.conf`. المعالج `install.sh` يضع الاثنين في مكانهما ويهيّئ طريقة الإقلاع؛ ويمكن تنفيذ كل خطوة يدوياً.

## المتطلبات

- صلاحيات `root`. يحتاجها الحارس وكل كلمات صندوق الأدوات عدا `check` و`help`.
- `bash` 4 أو أحدث لـ `awacs.sh`؛ و`bash` 5 للوحة الطرفية الاختيارية `tools/awacs-tui.sh`.
- Raspberry Pi OS أو أي توزيعة مشتقة من Debian فيها `apt-get`: صورة `dhcpcd` مع `wpa_supplicant` (النظام `wpa`) أو صورة NetworkManager (النظام `nm`). بلا `apt-get` يكتفي المعالج بالإبلاغ عن الأدوات الناقصة، ويسجّل الحارس `no apt-get on this system - install manually:` متبوعاً بأسماء الأدوات.
- الأدوات: `iw` و`ip` و`ping` و`curl` و`awk` و`sed` و`grep` و`pgrep` و`rfkill` و`flock` و`timeout` و`stat` و`date` و`modprobe`، و`wpa_cli` أو `nmcli` بحسب النظام؛ و`iwlist` و`wget` بديلان اختياريان. يثبّت المعالج الأدوات الناقصة من حزم Debian: `iw` و`iproute2` و`iputils-ping` و`curl` و`mawk` و`sed` و`grep` و`procps` و`rfkill` و`util-linux` و`coreutils` و`kmod`، و`wpasupplicant` أو `network-manager`.
- منفذ خارجي إلى `8.8.8.8` و`1.1.1.1` (ICMP)، وإلى `http://connectivitycheck.gstatic.com`، وإلى الموقع عبر HTTP أو HTTPS حين يُضبط موقع. الإجراءات المميّزة التي ينفّذها الحارس مذكورة في [SECURITY.md](../../SECURITY.md).

## المعالج

</div>

```sh
curl -fsSL https://raw.githubusercontent.com/hmne/AWACS/main/install.sh | sudo bash
```

<div dir="rtl">

أو من نسخة مستنسخة: `sudo ./install.sh`. يستعمل المعالج قوائم `whiptail` حين تكون موجودة وأسئلة نصية بسيطة وإلا، ويحتاج طرفية ما لم يُعطَ `--yes`. أمر السطر الواحد ينزّل `awacs.sh` و`SHA256SUMS` من عنوان الإصدار ويتوقف حين لا تتطابق بصمة التحقق؛ والنسخة المستنسخة تُثبَّت من الملف المحلي، ويُتحقق منها مقابل `SHA256SUMS` حين يكون هذا الملف بجانبها. الخطوات:

1. اللغة: الإنجليزية أو العربية لنصوص المعالج نفسه. السجل المحلي إنجليزي في الحالتين.
2. الأدوات الناقصة: تُفحص قائمة أدوات النظام وتُثبَّت الحزم الناقصة بـ `apt-get` بعد موافقتك. إن رفضت، يحاول الحارس مرة واحدة بنفسه بعد اتصاله بالإنترنت.
3. معرّف الجهاز: حروف وأرقام و`_` و`-`، حتى 32 حرفاً. الافتراضي هو معرّف تثبيت سابق، وإلا اسم المضيف المختصر.
4. وجهة السجل: `local` (الملف فقط) أو `both` (الملف والموقع) أو `remote` (الموقع؛ ويحتفظ الملف بـ `WARN` و`ERROR` والأسطر المحلية فقط)؛ ويسأل `both` و`remote` عن عنوان الموقع ويتحققان أن `${SITE_URL}/${DEVICE_ID}/${SITE_API}` يرد بـ HTTP 400، وحين لا يرد يُعرض عليك إدخال عنوان آخر أو الإبقاء على العنوان كما كتبته أو التسجيل المحلي. بلا موقع يسأل المعالج بعدها عن عنوان قياس اختياري، ومع موقع عن المنطقة الزمنية لأختام سجل الموقع.
5. شبكات الطوارئ: مدخلات `SAFETY_NET`، الاسم وكلمة السر، بالعدد الذي تريد. ثم تُكتب الإجابات في `/etc/awacs.conf` (`root:root`، الصلاحية 0600).
6. طريقة الإقلاع: وحدة systemd (الافتراضي حين يوجد `systemctl`) أو كتلة معلَّمة في `/etc/rc.local`؛ وإعادة التشغيل التي تغيّر الطريقة تحذف الأخرى. يُكتشف هنا أي سكربت باسم `aasw.sh` ويعرض المعالج تعطيله.
7. التثبيت وإعادة التشغيل: يوضع `awacs.sh` في `/usr/local/bin/awacs.sh` (`root`، الصلاحية 0755) ويُعاد تشغيل الحارس، وتحت `rc.local` بإرسال إشارة إلى الحارس العامل أو ببدء حلقة حين لا توجد واحدة.
8. الفحص: يُشغَّل `awacs.sh check` وتُعرض نتيجته.
9. الملخص: الملفات المكتوبة وأوامر متابعة الحارس.

إعادة تشغيل المعالج تحدّث الموجود. قيم التقارير في `/etc/awacs.conf` القائم تصبح الافتراضيات، وتُحفظ سطوره الأخرى، وتُستبدل المفاتيح المُدارة، ويُستبدل مدخل `SAFETY_NET` الذي يحمل الاسم نفسه. المعالج لا يعدّل `/etc/wpa_supplicant/wpa_supplicant.conf` ولا أي ملف تعريف في NetworkManager.

التشغيل بلا أسئلة والتشغيل التجريبي:

</div>

```sh
sudo ./install.sh --yes --device-id mydevice --log local
sudo ./install.sh --yes --device-id mydevice --log both --site https://example.org \
                  --safety 'MyPhone=hotspot-password' --service systemd
sudo ./install.sh --dry-run
curl -fsSL https://raw.githubusercontent.com/hmne/AWACS/main/install.sh | sudo bash -s -- --yes --device-id mydevice
```

<div dir="rtl">

`--yes` يأخذ الافتراضيات مع الخيارات المعطاة؛ و`--log both` أو `--log remote` بلا `--site` يتوقف ما لم يحمل ملف إعدادات قائم عنوان موقع. `--dry-run` يطبع كل إجراء ولا يغيّر شيئاً.

| الخيار | المعنى |
| --- | --- |
| `--lang en\|ar` | لغة المعالج |
| `--device-id ID` | معرّف الجهاز، `[A-Za-z0-9_-]{1,32}` |
| `--log local\|both\|remote` | وجهة السجل؛ `both` و`remote` يحتاجان `--site` مع `--yes` |
| `--site URL` | العنوان الأساسي لموقع التقارير |
| `--probe URL` | هدف قياس سرعة الرفع |
| `--report-wifi auto\|yes\|no` | نشر خانة الواي فاي إلى الموقع |
| `--tz ZONE` | المنطقة الزمنية لأختام سجل الموقع، مثل `Europe/Berlin` |
| `--log-lang en\|ar` | لغة أسطر القصة في اللوق المحلي. المعالج يسأل عنها؛ افتراضيها لغة المعالج نفسه. |
| `--site-lang en\|ar` | لغة الأسطر المرسلة إلى الموقع. تُسأل فقط حين تكون وجهة اللوق `both` أو `remote`. |
| `--api NAME` | اسم ملف نقطة الاستقبال تحت `<site>/<device id>/`، الافتراضي `receiver.php` |
| `--safety 'SSID=password'` | شبكة طوارئ، يتكرر |
| `--no-safety` | تجاوز خطوة شبكات الطوارئ |
| `--service systemd\|rc.local` | طريقة الإقلاع |
| `--release-url URL` | من أين يُنزَّل `awacs.sh` و`SHA256SUMS` |
| `--yes` | بلا أسئلة: الافتراضيات مع الخيارات أعلاه |
| `--dry-run` | طباعة كل إجراء دون تغيير |
| `--uninstall` | إزالة طريقة الإقلاع و`awacs.sh` مع الإبقاء على الإعدادات والسجل |
| `--purge` | مع `--uninstall`: حذف `/etc/awacs.conf` والسجل أيضاً |
| `--help` | نص الاستعمال |

## التثبيت اليدوي

</div>

```sh
sha256sum -c --ignore-missing SHA256SUMS
sudo install -m 755 awacs.sh /usr/local/bin/awacs.sh
sudo install -m 600 -o root -g root awacs.conf.example /etc/awacs.conf
sudo nano /etc/awacs.conf
```

<div dir="rtl">

في ملف الإعدادات أزل التعليق واضبط ما تحتاجه. الحد الأدنى المعتاد:

</div>

```sh
SITE_URL="https://example.org"        # أو اتركه فارغاً للعمل المحلي فقط
LOG_TARGET="both"
SAFETY_NET["MyPhoneHotspot"]="hotspot-password"
```

<div dir="rtl">

كل مفتاح موصوف في [configuration.md](configuration.md). ثم اختر طريقة إقلاع واحدة.

### systemd

الوحدة هي `systemd/awacs.service`:

</div>

```ini
[Unit]
Description=AWACS - WiFi autonomy daemon
After=network-pre.target NetworkManager.service dhcpcd.service
StartLimitIntervalSec=0

[Service]
Type=simple
Environment=DEVICE_ID=device1
ExecStart=/usr/local/bin/awacs.sh
Restart=always
RestartSec=10
TimeoutStopSec=40

[Install]
WantedBy=multi-user.target
```

<div dir="rtl">

ثبّتها مع ملف إضافي يحمل معرّف الجهاز:

</div>

```sh
sudo install -m 644 systemd/awacs.service /etc/systemd/system/awacs.service
sudo mkdir -p /etc/systemd/system/awacs.service.d
printf '[Service]\nEnvironment=DEVICE_ID=mydevice\n' | sudo tee /etc/systemd/system/awacs.service.d/10-device-id.conf
sudo systemctl daemon-reload
sudo systemctl enable --now awacs
```

<div dir="rtl">

`Restart=always` مع `RestartSec=10` هو حلقة `rc.local` مكتوبة كوحدة. يخرج الحارس برمز 0 عمداً في حالتين ويتوقع إعادة تشغيله: حين يفقد قفل النسخة الوحيدة، وحين تُثبَّت `nmcli` للتو على صورة NetworkManager كانت تفتقدها. `StartLimitIntervalSec=0` يمنع systemd من الاستسلام بعد دفعة من هذه الخروجات. تبدأ الوحدة بعد `network-pre.target` لا خلف `network-online.target`: عمل الحارس أن يجعل الشبكة تعمل. `TimeoutStopSec=40` يترك مجالاً لـ `nmcli -w 5` داخل معالج الإيقاف. يعرض `journalctl -u awacs` أحداث البدء والإيقاف؛ والحارس نفسه يسجّل في ملفه. التفاصيل في [systemd/README.md](../../systemd/README.md).

### rc.local

أضف السطرين قبل أي شيء يحتاج الشبكة. سطر تصدير `DEVICE_ID` يجب أن يأتي أولاً.

</div>

```sh
export DEVICE_ID="mydevice"
( while :; do /usr/local/bin/awacs.sh; sleep 10; done ) >/dev/null 2>&1 &
```

<div dir="rtl">

يجب أن يكون `/etc/rc.local` قابلاً للتنفيذ (`sudo chmod 755 /etc/rc.local`)؛ وعلى صور systemd يعمل عبر `rc-local.service`، فافحصها بـ `systemctl status rc-local`. يكتب المعالج السطرين نفسيهما بين العلامتين `# >>> awacs (managed by install.sh) >>>` و`# <<< awacs <<<`. أزل أي حارس واي فاي آخر من `rc.local`؛ يحذّر الحارس في سجله حين يعمل سكربت باسم `aasw.sh`.

استعمل systemd حين تملكه الصورة. لا تثبّت الطريقتين معاً: النسخة الثانية تفقد قفل الحارس وتخرج كل عشر ثوانٍ.

## التحقق

</div>

```sh
awacs.sh check              # يطبع internet: OK (رمز الخروج 0) أو internet: DOWN (رمز الخروج 1)؛ بلا root
sudo awacs.sh status
sudo awacs.sh networks
sudo tail -f /var/log/awacs.log
```

<div dir="rtl">

أول سطور بداية سليمة بإعدادات محلية فقط:

</div>

```text
[INFO][20/09 10:15:04] AWACS 1.0 starting on wlan0 (device mydevice)
[INFO][20/09 10:15:04] reporting: local | probe: none - signal mode | wifi cell: auto
```

<div dir="rtl">

مع موقع، يسمّي السطر الثاني الموقع وهدف القياس بدل `none - signal mode`. تضيف صورة NetworkManager السطر `NetworkManager backend - AWACS supervises it (full capability)`. أما السطر `NetworkManager image but AWACS cannot drive it (unmanaged/no nmcli) - monitoring only` فيعني أن الواجهة خارج الإدارة أو أن `nmcli` ناقص؛ ويكتفي الحارس بالمراقبة حتى يُصلَح ذلك. والسطر `interface ${IF} not present - is the WiFi hardware alive?` يعني أن الواجهة المكتشفة غير موجودة؛ اضبط `AWACS_IF` في بيئة المشغّل.

يطبع `status` صفاً لكل حقيقة: الجهاز (المعرّف والواجهة)، والنظام، والحارس (يعمل برقم عمليته، أو متوقف)، والشبكة، والإشارة، وعنوان IP، والموجّه (يرد أو لا يرد)، والإنترنت (متصل أو مقطوع)، والمشاهد (هل يعمل بث مباشر)، والرفع (معدل عدّادات النواة خلال ثلاث ثوانٍ). تسميات الصفوف إنجليزية؛ وعدد من القيم يحمل شرحاً عربياً بعد شرطة مائلة، ويسبق الصفوف سطر ملاحظة بالعربية.

مع موقع مضبوط و`LOG_TARGET` على `both` أو `remote`، يصل سطر البداية إلى `<device-id>/log/log.txt` بجانب المستقبِل، ويُكتب `<device-id>/tmp/wifi.tmp` في أول دورة سليمة ويتجدد كل نحو 60 ثانية. وحين يبدأ الجهاز بلا إنترنت تنتظر السطور في المخزون المؤقت وتصل بعد أول 30 ثانية من إنترنت متحقَّق منه.

سطر بداية يتكرر كل عشر ثوانٍ يعني أن الحارس يخرج فور بدئه وأن المشغّل يعيده؛ والسطور بين سطري بداية تعطي السبب. أما المشغّل الثاني فلا ينتج سطور بداية: النسخة الخاسرة تخرج صامتة وتُعاد بلا فائدة. تحقق أن طريقة واحدة فقط مثبَّتة بـ `systemctl is-enabled awacs` و`grep awacs.sh /etc/rc.local`.

يمكن فحص قاعدة عدم الكتابة يدوياً: `sudo md5sum /etc/wpa_supplicant/wpa_supplicant.conf` (أو `ls -l /etc/NetworkManager/system-connections`) قبل التثبيت وبعد إعادة تشغيل الجهاز وبعد يوم. لا شيء يتغير.

### لوحة الطرفية

`tools/awacs-tui.sh` لوحة طرفية للقراءة فقط: الوصلة، ورقم عملية الحارس، والشبكات المخزنة والظاهرة، وذيل السجل، تتجدد كل ثانيتين. تحتاج `bash` 5 وطرفية 80x24، وتعمل على الجهاز (`sudo tools/awacs-tui.sh` للصورة الكاملة)، ولا تطلق مسحاً أبداً؛ والمفتاح `s` يشغّل `awacs.sh speed` عند الطلب. الخيارات: `--plain` (بلا رموز تحكم)، و`--once` (إطار واحد)، و`--lang en|ar`، و`--interval N`.

## الإيقاف وإعادة التشغيل

`systemctl stop awacs` يرسل SIGTERM؛ فيعيد الحارس تفعيل كل شبكة مخزنة ويخرج برمز 0. تحت `rc.local` يفعل `kill "$(head -1 /run/awacs/lock)"` الشيء نفسه وتبدأ الحلقة حارساً جديداً خلال عشر ثوانٍ؛ وللإيقاف نهائياً علّق السطر في `/etc/rc.local` أولاً. الإيقاف في منتصف إنعاش يترك مدخل شبكة مؤقتاً؛ والبدء التالي يحذفه قبل أول محاولة اتصال. يُقرأ ملف الإعدادات عند البدء فقط: بعد تعديل `/etc/awacs.conf` أعد تشغيل الحارس.

</div>

```sh
sudo systemctl restart awacs                 # systemd
sudo kill "$(head -1 /run/awacs/lock)"       # rc.local: الحلقة تعيد تشغيله خلال 10 ثوانٍ
```

<div dir="rtl">

لتغيير معرّف الجهاز لاحقاً، عدّل `Environment=DEVICE_ID=` في الملف الإضافي أو سطر `export DEVICE_ID=` في `rc.local` وأعد التشغيل، أو أعد تشغيل المعالج مع `--device-id`.

## الترقية

إعادة تشغيل المعالج (`sudo ./install.sh` أو أمر السطر الواحد) تستبدل `awacs.sh` وتحتفظ بملف الإعدادات وتعيد تشغيل الحارس. يدوياً: تحقق من البصمة، وثبّت الملف، وأعد التشغيل كما أعلاه. افحص `sudo awacs.sh status` بعدها؛ يُظهر السجل سطر بداية جديداً.

## الإزالة

</div>

```sh
sudo ./install.sh --uninstall            # يحذف الوحدة أو كتلة rc.local و awacs.sh؛ ويحتفظ بالإعدادات والسجل
sudo ./install.sh --uninstall --purge    # ويحذف أيضاً /etc/awacs.conf و /var/log/awacs.log و /run/awacs
```

<div dir="rtl">

قد تبقى حلقة `rc.local` التي بدأت في الإقلاع الحالي حية بعد `--uninstall`؛ وتنتهي عند إعادة التشغيل التالية. يدوياً:

</div>

```sh
sudo systemctl disable --now awacs && sudo rm -rf /etc/systemd/system/awacs.service /etc/systemd/system/awacs.service.d && sudo systemctl daemon-reload
# أو: احذف كتلة awacs من /etc/rc.local ثم kill "$(head -1 /run/awacs/lock)"
sudo rm -f /usr/local/bin/awacs.sh
sudo rm -f /etc/awacs.conf             # يحمل كلمات سر نقاط الاتصال
sudo rm -f /var/log/awacs.log
```

<div dir="rtl">

لا شيء آخر للتنظيف:

- `/run/awacs` وأي ملف مفاتيح `awacs-*` تحت `/run/NetworkManager/system-connections` في ذاكرة `tmpfs` ويزولان عند إعادة التشغيل. لحذفهما الآن: `sudo rm -rf /run/awacs; sudo rm -f /run/NetworkManager/system-connections/awacs-*.nmconnection; sudo nmcli connection reload`.
- على النظام `wpa` تعيش الشبكة المؤقتة في `wpa_supplicant` الحي فقط؛ و`sudo wpa_cli -i wlan0 reconfigure` أو إعادة التشغيل تسقطها.
- قاعدة التخفي، إن فُعّلت، قاعدة `iptables` وقت التشغيل؛ و`avahi-daemon` أُوقف ولم يُعطَّل. كلاهما يعود عند إعادة التشغيل.
- `wpa_supplicant.conf` وملفات تعريف NetworkManager لم تُكتب أبداً. لا شيء لاستعادته.

## الملفات بعد التثبيت

| المسار | المالك والصلاحية | المحتوى |
| --- | --- | --- |
| `/usr/local/bin/awacs.sh` | `root` 0755 | الحارس وصندوق الأدوات |
| `/etc/awacs.conf` | `root` 0600 | إعداداتك، ومنها كلمات سر نقاط الاتصال |
| `/var/log/awacs.log` | `root` 0600 | السجل المحلي، يُدوَّر عند `LOG_CAP` سطراً |
| `/run/awacs/` | `root` 0700 | القفل ورقم العملية، وذاكرة المسح المؤقتة، وعدّاد المسوح الفارغة، والمخزون المؤقت، وعلامة الشبكة المؤقتة، وجسم القياس، وعلامة `apt` مرة كل إقلاع |
| `/etc/systemd/system/awacs.service` و`awacs.service.d/10-device-id.conf` | `root` 0644 | المشغّل (systemd) |
| الكتلة المعلَّمة في `/etc/rc.local` | `root` 0755 | المشغّل (rc.local) |

</div>
