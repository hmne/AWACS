<div dir="rtl">

# التثبيت

أواكس ملف واحد، `awacs.sh`، زائد ملف ضبط اختياري. يحتاج root، وbash 4 أو أحدث، والأدوات الأصلية في Raspberry Pi OS أو Debian.

## المعالج

</div>

```sh
curl -fsSL https://raw.githubusercontent.com/hmne/AWACS/main/install.sh | sudo bash
```

<div dir="rtl">

أو من نسخة محلية: `sudo ./install.sh`. يستعمل المعالج قوائم `whiptail` حين تكون موجودة (أصلية في Raspberry Pi OS) وأسئلة نصية بسيطة وإلا. يمرّ بتسع خطوات:

1. **اللغة** — الإنجليزية أو العربية لنصوص المعالج نفسه. لوق السكربت ثنائي اللغة في كل حال: إنجليزي في الملف المحلي، عربي على الموقع.
2. **الأدوات الناقصة** — تُفحَص قائمة أدوات النظام؛ حزم Debian الناقصة تُعرَض وتُثبَّت بـ `apt-get` بعد موافقتك فقط.
3. **معرّف الجهاز** — اسم قصير (`[A-Za-z0-9_-]`، حتى 32 حرفاً)، الافتراضي `cam1`. يسمّي الجهاز على الموقع وفي سطر بداية اللوق.
4. **وجهة اللوق** — `local` (الملف فقط)، `both` (الملف والموقع)، أو `remote` (الموقع، مع الاحتفاظ بـ WARN/ERROR فقط محلياً). `both` و`remote` يسألان عن رابط الموقع ويتحققان أن `${SITE_URL}/${DEVICE_ID}/device_api.php` يرد بـ `400`.
5. **شبكات الطوارئ** — مدخلات `SAFETY_NET`، الاسم وكلمة السر، بالعدد الذي تريد. كلمة السر تُسأل في صندوق كلمة سر ولا تصل إلا إلى ملف الضبط الخاص بـ root.
6. **طريقة الإقلاع** — وحدة systemd (الافتراضي حين يوجد `systemctl`) أو سطر في `/etc/rc.local`. طريقة واحدة فقط؛ إعادة التشغيل التي تغيّر الطريقة تحذف الأخرى. إن وُجد `aasw.sh` قديم يعرض المعالج تعطيله.
7. **التثبيت** — `awacs.sh` إلى `/usr/local/bin/awacs.sh` (صلاحيات 755)، مع التحقق بـ sha256 مقابل `SHA256SUMS` حين يُنزَّل.
8. **الفحص** — `awacs.sh check`.
9. **الملخص** — ما كُتب وأين.

يُكتَب `/etc/awacs.conf` بـ root:root 0600 وبسطور `KEY=value` بسيطة تحمل القيم التي اخترتها فقط. المعالج لا يعدّل `/etc/wpa_supplicant/wpa_supplicant.conf` ولا أي ملف NetworkManager أبداً.

التشغيل بلا أسئلة والتشغيل التجريبي:

</div>

```sh
sudo ./install.sh --yes --device-id cam1 --log local                      # الافتراضيات، بلا أسئلة
sudo ./install.sh --yes --device-id cam2 --log both --site https://example.com/cams \
                  --safety 'MyPhone=hotspot-password' --service systemd
sudo ./install.sh --dry-run                                               # يعرض كل خطوة ولا يغيّر شيئاً
curl -fsSL https://raw.githubusercontent.com/hmne/AWACS/main/install.sh | sudo bash -s -- --yes --device-id cam1
```

<div dir="rtl">

الخيارات: `--lang en|ar`، `--device-id ID`، `--log local|both|remote`، `--site URL`، `--probe URL`، `--report-wifi auto|yes|no`، `--safety 'SSID=password'` (يتكرر)، `--no-safety`، `--service systemd|rc.local`، `--release-url URL`، `--yes`، `--dry-run`، `--uninstall [--purge]`، `--help`.

## التثبيت اليدوي

</div>

```sh
sudo install -m 755 awacs.sh /usr/local/bin/awacs.sh
sudo install -m 600 -o root -g root awacs.conf.example /etc/awacs.conf
sudo nano /etc/awacs.conf
```

<div dir="rtl">

في ملف الضبط، أزل التعليق واضبط ما تحتاجه. الحد الأدنى المعتاد:

</div>

```sh
SITE_URL="https://example.com/cams"        # أو اتركه فارغاً للعمل المحلي فقط
LOG_TARGET="both"
SAFETY_NET["MyPhoneHotspot"]="hotspot-password"
```

<div dir="rtl">

### systemd

الوحدة هي `systemd/awacs.service` في المستودع:

</div>

```ini
[Unit]
Description=AWACS - WiFi autonomy daemon
After=network-pre.target NetworkManager.service dhcpcd.service
StartLimitIntervalSec=0

[Service]
Type=simple
Environment=DEVICE_ID=cam1
ExecStart=/usr/local/bin/awacs.sh
Restart=always
RestartSec=10
TimeoutStopSec=40

[Install]
WantedBy=multi-user.target
```

```sh
sudo install -m 644 systemd/awacs.service /etc/systemd/system/awacs.service
sudo mkdir -p /etc/systemd/system/awacs.service.d
printf '[Service]\nEnvironment=DEVICE_ID=cam1\n' | sudo tee /etc/systemd/system/awacs.service.d/10-device-id.conf
sudo systemctl daemon-reload
sudo systemctl enable --now awacs
```

<div dir="rtl">

`Restart=always` مع `RestartSec=10` هو حلقة `rc.local` مكتوبة كوحدة. يخرج الحارس برمز 0 عمداً في حالتَين ويتوقع إعادة تشغيله: حين يفقد قفل النسخة الوحيدة، وحين تُثبَّت `nmcli` للتو على صورة NetworkManager كانت تفتقدها. `StartLimitIntervalSec=0` يمنع systemd من الاستسلام بعد دفعة من هذه الخروجات. تبدأ الوحدة بعد `network-pre.target` لا خلف `network-online.target`: عمل الحارس أن يجعل الشبكة تعمل. `TimeoutStopSec=40` يترك مجالاً لـ `nmcli -w 5` داخل معالج الإيقاف. التفاصيل في `systemd/README.md`.

### rc.local

أضف السطرَين قبل أي شيء يحتاج الشبكة. الترتيب مهم: سطر `export DEVICE_ID` أولاً.

</div>

```sh
export DEVICE_ID="cam1"
( while :; do /usr/local/bin/awacs.sh; sleep 10; done ) >/dev/null 2>&1 &
```

<div dir="rtl">

إن وُجد سطر `aasw.sh` قديم فاحذفه واحذف `/usr/local/bin/aasw.sh`. حارسان للواي فاي يتصارعان؛ ويسجّل أواكس تحذيراً إن رأى القديم يعمل.

## التحقق

</div>

```sh
awacs.sh check              # internet: OK  (رمز 0)  — بلا root
sudo awacs.sh status
sudo awacs.sh networks
sudo tail -f /var/log/awacs.log
```

<div dir="rtl">

أول سطور اللوق على جهاز سليم:

</div>

```text
[INFO][12/09 17:37:04] AWACS 1.0 starting on wlan0 (device cam1)
```

<div dir="rtl">

وعلى صورة NetworkManager أيضاً:

</div>

```text
[INFO][12/09 17:43:36] NetworkManager backend - AWACS supervises it (full capability)
```

<div dir="rtl">

يجب أن يُظهر `status` الحارس يعمل برقم عمليته و`internet ONLINE`. ومع موقع مضبوط يستلم لوقه `[INFO] AWACS: أواكس 1.0 بدأ العمل على wlan0, …` ويظهر `tmp/wifi.tmp` خلال دقيقة. `tools/awacs-tui.sh` لوحة طرفية للقراءة فقط تعرض نفس الحقائق وتتجدد كل ثانيتَين.

يمكن فحص قانون لا-بلوك يدوياً: `sudo md5sum /etc/wpa_supplicant/wpa_supplicant.conf` (أو `ls -l /etc/NetworkManager/system-connections`) قبل التثبيت وبعد ريبوت وبعد يوم. لا شيء يتغير.

## systemd مقابل rc.local

| | systemd | rc.local |
| --- | --- | --- |
| إعادة التشغيل عند الخروج | `Restart=always`، `RestartSec=10`، بلا حد للبدء | حلقة `while :; do …; sleep 10; done` |
| لوق المشغّل نفسه | `journalctl -u awacs` (أحداث البدء والإيقاف فقط؛ الحارس يسجّل في ملفه) | لا شيء (`>/dev/null`) |
| ترتيب البدء | بعد `network-pre.target` و`NetworkManager.service` و`dhcpcd.service`؛ والحارس نفسه ينتظر حتى 60 ثانية لـ NetworkManager على صور NM | يعمل حين يعمل `rc.local`، عادةً قبل أن تقوم الشبكة — وهذا جيد، أواكس يقاتل من الثانية الأولى |
| `DEVICE_ID` | ملف إضافي `awacs.service.d/10-device-id.conf` | سطر `export` |
| الإيقاف | `systemctl stop awacs` (SIGTERM ← `enable_all` ← خروج 0) | `kill $(head -1 /run/awacs/lock)` (الحلقة تعيده خلال 10 ثوانٍ؛ علّق السطر أولاً) |

كلاهما مدعوم. استعمل systemd حين تملكه الصورة. ولا تستعمل الطريقتَين معاً: النسخة الثانية تفقد قفل الحارس وتخرج كل عشر ثوانٍ بلا فائدة.

## الترقية

إعادة تشغيل المعالج تحدّث ما هو موجود: `sudo ./install.sh` (أو سطر curl) يستبدل الملف التنفيذي، يحتفظ بملف الضبط، ويعيد تشغيل الحارس. يدوياً:

</div>

```sh
sudo install -m 755 awacs.sh /usr/local/bin/awacs.sh
sudo systemctl restart awacs                 # systemd
sudo kill "$(head -1 /run/awacs/lock)"       # rc.local: الحلقة تعيد تشغيله خلال 10 ثوانٍ
```

<div dir="rtl">

معالج الإيقاف في الحارس يعيد تفعيل كل شبكة مخزنة قبل الخروج، فإعادة التشغيل لا تترك supplicant مضيَّقاً أبداً. افحص `sudo awacs.sh status` بعدها؛ يُظهر اللوق سطر `AWACS … starting` جديداً.

## الإزالة

</div>

```sh
sudo ./install.sh --uninstall            # يحذف الخدمة/سطر rc.local والملف التنفيذي؛ يحتفظ بالإعدادات واللوق
sudo ./install.sh --uninstall --purge    # ... ويحذف /etc/awacs.conf و/var/log/awacs.log أيضاً
```

<div dir="rtl">

يدوياً:

</div>

```sh
sudo systemctl disable --now awacs && sudo rm -rf /etc/systemd/system/awacs.service /etc/systemd/system/awacs.service.d && sudo systemctl daemon-reload
# أو: احذف السطرَين من /etc/rc.local ثم kill "$(head -1 /run/awacs/lock)"
sudo rm -f /usr/local/bin/awacs.sh
sudo rm -f /etc/awacs.conf             # يحمل كلمات سر الهوتسبوت — احذفه عن قصد
sudo rm -f /var/log/awacs.log
```

<div dir="rtl">

لا شيء آخر للتنظيف:

- `/run/awacs` وأي ملف `awacs-*` تحت `/run/NetworkManager/system-connections` في الذاكرة ويزولان مع الريبوت. لحذفهما الآن: `sudo rm -rf /run/awacs; sudo rm -f /run/NetworkManager/system-connections/awacs-*.nmconnection; sudo nmcli connection reload`.
- على نظام wpa تعيش الشبكة المؤقتة في supplicant الحي فقط؛ `sudo wpa_cli -i wlan0 reconfigure` أو ريبوت يسقطها.
- قاعدة التخفي (إن فُعِّلت) قاعدة `iptables` وقت التشغيل؛ و`avahi-daemon` أُوقف لا عُطِّل. كلاهما يعود مع الريبوت.
- ملفك `wpa_supplicant.conf` وملفات NetworkManager لم تُكتَب أبداً. لا شيء لاستعادته.

## الملفات بعد التثبيت

| المسار | المالك/الصلاحيات | المحتوى |
| --- | --- | --- |
| `/usr/local/bin/awacs.sh` | root 0755 | الحارس وصندوق الأدوات |
| `/etc/awacs.conf` | root 0600 | إعداداتك، بما فيها كلمات سر الهوتسبوت |
| `/var/log/awacs.log` | root 0600 | اللوق المحلي، يُدوَّر عند `LOG_CAP` سطراً |
| `/run/awacs/` | root 0700 | القفل، كاش المسح، المخزون، علامة الشبكة المؤقتة، علامة apt مرة-كل-إقلاع |
| `/etc/systemd/system/awacs.service` + `awacs.service.d/10-device-id.conf`، أو كتلة معلَّمة في `/etc/rc.local` | root | المشغّل |

</div>
