# مرجع الإعدادات

يقرأ AWACS ملف إعدادات واحداً: `/etc/awacs.conf`. تعرض هذه الصفحة كل مفتاح، وقيمته الافتراضية في السكربت وفي ملف `awacs.conf.example` المرفق، وهل يفحصه السكربت، وأي دوال تقرأه. الجدول يولَّد من الكود بالأداة `tools/gen-config-table.sh`. لا تعدّل الجدول يدوياً.

## كيف يُحمَّل الملف

- المسار: `/etc/awacs.conf`. المتغير البيئي `AWACS_CONF` يوجّه السكربت إلى ملف آخر (تستعمله الاختبارات).
- يُقرأ الملف فقط حين يعمل السكربت بصلاحيات root. الأمران `awacs.sh check` و`awacs.sh help` يعملان بلا root وعلى القيم الافتراضية المدمجة.
- يجب أن يكون الملف ملكاً للـ root وبلا أي صلاحية للمجموعة أو الآخرين (`chmod 600`). وإلا يتجاهله السكربت ويطبع أحد هذين السطرين على stderr:
  - `awacs: IGNORING /etc/awacs.conf (not owned by root — chown root: it)`
  - `awacs: IGNORING /etc/awacs.conf (group/world can access it — chmod 600 it)`
- يُنفَّذ الملف بـ bash (source)، فلا يحوي إلا سطور `KEY=value` بسيطة ومدخلات `SAFETY_NET["name"]="password"`. أي سطر `readonly` أو `declare` فيه يمنع الفحص الموصوف أدناه من إصلاح القيمة الخاطئة.
- بعد التحميل تُختم كل المفاتيح `readonly`. لا يغيّرها شيء أثناء العمل سوى نسخ النهار والليل الموصوفة أدناه.

## الفحص

- المفاتيح الرقمية يجب أن تطابق `^0*[1-9][0-9]{0,6}$`: عدد صحيح من 1 إلى 9999999. الأصفار البادئة مقبولة وتُطبَّع (`08` تصبح `8`). الصفر أو القيمة الفارغة أو العدد السالب أو النص يعود إلى الافتراضي. السبب هو السلامة: رقم خاطئ داخل حساب bash يُسقط الحارس في حلقة إعادة تشغيل، و`TICK` صفر يجعل الحلقة تدور بلا توقف.
- `NIGHT_START` و`NIGHT_END` بصيغة `H:MM` أو `HH:MM` بين `00:00` و`23:59`؛ وإلا تُستعمل `22:00` و`06:00`.
- `RUN_DIR` يجب أن يبدأ بـ `/`؛ وإلا يُستعمل `/run/awacs`. تحته يعيش ملف القفل وكاش المسح والسبول وعلامة التعريف المؤقت وملف القياس، فتغييره ينقلها كلها معاً.
- المفاتيح النصية (`OPEN_NETWORKS` و`NIGHT_MODE` و`STEALTH_MODE` و`DEBUG`) تُقارن بالكلمة `yes`. أي قيمة أخرى تعني التعطيل.

## النهار والليل

تُنسخ `MIN_UP_KBPS` و`SWITCH_GAIN_PCT` و`DANCE_COOLDOWN` عند بدء السكربت إلى `CUR_MIN_UP` و`CUR_GAIN` و`CUR_COOLDOWN`. داخل فترة الليل تستبدلها الدالة `apply_profile` بـ `NIGHT_MIN_UP_KBPS` و`NIGHT_GAIN_PCT` و`NIGHT_DANCE_COOLDOWN`، وتعيد قيم النهار في الصباح. كود القرار (`main` و`best_by_upload`) يقرأ نسخ `CUR_*` فقط. لهذا يُدرج الجدول المفاتيح الستة تحت `apply_profile` و`(المستوى الأعلى)` لا تحت الدوال التي تتصرف بها.

## مفاتيح التقارير (النسخة العامة)

تحدد هذه المفاتيح إلى أين يرسل الجهاز تقاريره. وُثِّقت بحسب واجهة النسخة العامة؛ الشرطة في عمودَي السكربت في الجدول تعني أن ملف `awacs.sh` الذي وُلِّد منه الجدول لم يحمل المفتاح بعد. أعد التوليد بعد تحديث السكربت.

| المفتاح | المعنى |
| --- | --- |
| `SITE_URL` | العنوان الأساسي لموقع التقارير. يخاطب السكربت `${SITE_URL}/${DEVICE_ID}/device_api.php`. فارغ = عمل محلي فقط. |
| `LOG_TARGET` | `local` أو `both` أو `remote`. الخياران `both` و`remote` يحتاجان `SITE_URL`. مع `remote` يبقى في الملف المحلي سطور WARN وERROR فقط. |
| `PROBE_URL` | هدف قياس سرعة الرفع (جسم طلب POST). فارغ مع `SITE_URL` = ملف `device_api.php` في الموقع. فارغ بلا `SITE_URL` = لا قياس للرفع، وتُختار الشبكات بترتيب الإشارة («وضع الإشارة»). |
| `REPORT_WIFI` | إرسال خانة الواي فاي `kbps,visible,total,band,SSID` إلى الموقع باسم `tmp/wifi.tmp`. القيمة `auto` = تعمل عند ضبط `SITE_URL`. |
| `DEVICE_ID` | ليس مفتاحاً في ملف الإعدادات. يُقرأ من بيئة الحارس (`export DEVICE_ID=` في rc.local، أو `Environment=` في وحدة systemd). حروف وأرقام و`_` و`-` فقط، من 1 إلى 32 حرفاً؛ غير ذلك يعود إلى `cam1`. |

## المتغيرات البيئية التي يقرأها السكربت

| المتغير | الأثر |
| --- | --- |
| `DEVICE_ID` | معرّف الجهاز (انظر أعلاه). إن لم يُضبط، يُجرَّب أول سطر غير فارغ من `/tmp/device_id`، ثم `cam1`. |
| `AWACS_CONF` | مسار ملف الإعدادات (الافتراضي `/etc/awacs.conf`). |
| `AWACS_IF` | واجهة الواي فاي. الافتراضي: أول واجهة متصلة، وإلا أول واجهة مرفوعة، وإلا أول واجهة موجودة، وإلا `wlan0`. |
| `AWACS_DEBUG` | الافتراضي لـ `DEBUG` حين لا يضبطه ملف الإعدادات (`yes` إن غاب). |
| `AWACS_TEST_KBPS` و`AWACS_TEST_SCAN` | خطافا اختبار: رقم رفع ثابت بدل القياس؛ وإعادة استعمال كاش المسح بدل مسح الراديو. ليسا للإنتاج. |

## جدول المفاتيح

معنى الأعمدة:

- **الافتراضي في awacs.sh** — القيمة المعيَّنة في كتلة الإعدادات أعلى السكربت.
- **الافتراضي في awacs.conf.example** — القيمة في أول سطر `# KEY=` للمفتاح في ملف المثال. السطر المتروك خلف `#` يبقي ذلك الافتراضي.
- **يُفحص؟** — `نعم: رقم` تعني أن المفتاح ضمن حلقة الفحص الرقمي في السكربت؛ `نعم: HH:MM` و`نعم: مسار مطلق` هما فحصا الصيغة؛ `لا` تعني أن القيمة تُؤخذ كما كُتبت.
- **يُستخدم في** — الدوال التي تذكر المفتاح في أجسامها، بترتيب أول ظهور. `(المستوى الأعلى)` هو كود خارج أي دالة يعمل بعد ختم المفاتيح.

<!-- BEGIN GENERATED TABLE -->
| المفتاح | الافتراضي في awacs.sh | الافتراضي في awacs.conf.example | يُفحص؟ | يُستخدم في |
| --- | --- | --- | --- | --- |
| `TICK` | `10` | `10` | نعم: رقم | `main` |
| `NET_FAIL_TICKS` | `3` | `3` | نعم: رقم | `main` |
| `ASSOC_WAIT` | `25` | `25` | نعم: رقم | `nm_wait_settled`, `be_activate`, `wait_ip` |
| `PROBE_KB` | `200` | `200` | نعم: رقم | `up_kbps`, `up_kbps_wget`, `cli` |
| `MIN_UP_KBPS` | `400` | `400` | نعم: رقم | `(المستوى الأعلى)`, `apply_profile` |
| `UP_STRIKES` | `3` | `3` | نعم: رقم | `main` |
| `SWITCH_GAIN_PCT` | `150` | `150` | نعم: رقم | `(المستوى الأعلى)`, `apply_profile` |
| `DANCE_COOLDOWN` | `1200` | `1200` | نعم: رقم | `(المستوى الأعلى)`, `apply_profile` |
| `PREF_CHECK` | `600` | `600` | نعم: رقم | `main` |
| `REBOOT_AFTER_MIN` | `30` | `30` | نعم: رقم | `fight` |
| `OPEN_NETWORKS` | `"yes"` | `"yes"` | لا | `try_open` |
| `SITE_URL` | `""` | `""` | نعم: صيغة | `site`, `remote_on`, `probe_url`, `probe_on`, `have_net`, `report_wifi`, `main`, `cli` |
| `LOG_TARGET` | `"local"` | `"local"` | نعم: أحد local / both / remote | `remote_on`, `site_log`, `main` |
| `PROBE_URL` | `""` | `""` | نعم: صيغة | `probe_url`, `probe_on`, `cli` |
| `REPORT_WIFI` | `"auto"` | `"auto"` | نعم: أحد auto / yes / no | `report_wifi`, `main` |
| `SITE_TZ` | `""` | `""` | نعم: صيغة | `stamp` |
| `SAFETY_NET` | (فارغ) | أمثلة معلّقة | لا | `try_safety` |
| `NIGHT_MODE` | `"yes"` | `"yes"` | لا | `apply_profile` |
| `NIGHT_START` | `"22:00"` | `"22:00"` | نعم: HH:MM | `apply_profile` |
| `NIGHT_END` | `"06:00"` | `"06:00"` | نعم: HH:MM | `apply_profile` |
| `NIGHT_MIN_UP_KBPS` | `200` | `200` | نعم: رقم | `apply_profile` |
| `NIGHT_GAIN_PCT` | `300` | `300` | نعم: رقم | `apply_profile` |
| `NIGHT_DANCE_COOLDOWN` | `2400` | `2400` | نعم: رقم | `apply_profile` |
| `STEALTH_MODE` | `"no"` | `"no"` | لا | `enable_stealth` |
| `DEBUG` | `"${AWACS_DEBUG:-yes}"` | `"yes"` | لا | `dbg` |
| `LOG_FILE` | `/var/log/awacs.log` | `/var/log/awacs.log` | لا | `log` |
| `LOG_CAP` | `1500` | `1500` | نعم: رقم | `log` |
| `RUN_DIR` | `/run/awacs` | `/run/awacs` | نعم: مسار مطلق | `install_tools`, `(المستوى الأعلى)` |
| `SCAN_TTL` | `30` | `30` | نعم: رقم | `scan`, `cli` |
| `SPOOL_CAP` | `60` | `60` | نعم: رقم | `site_log`, `flush_spool` |
| `STREAM_MIN_KBPS` | `50` | `50` | نعم: رقم | `main` |

_المصدر: tools/gen-config-table.sh قرأ awacs.sh (2046 سطراً، sha256 859525312b2b…) وawacs.conf.example._
<!-- END GENERATED TABLE -->

## إعادة توليد الجدول

```sh
tools/gen-config-table.sh --write docs/en/config-reference.md
tools/gen-config-table.sh --lang ar --write docs/ar/config-reference.md
```

شغّل الأمرين بعد أي تغيير في `awacs.sh` أو `awacs.conf.example`. تقرأ الأداة كتلة الإعدادات في السكربت وحلقة الفحص الرقمي وفحصَي الصيغة وأجسام الدوال، ولا تحتاج إلا bash وawk وgrep وsed وsha256sum. الخياران `--script` و`--example` يوجّهانها إلى ملفات خارج جذر المستودع.
