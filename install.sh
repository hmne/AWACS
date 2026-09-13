#!/usr/bin/env bash
#
# install.sh — AWACS setup wizard (install, update, uninstall).
#
# What it does, in order:
#   1. language (English / Arabic)        6. boot method: systemd unit OR rc.local line
#   2. missing tools via apt                  (and offers to disable the old aasw.sh)
#   3. device id                          7. awacs.sh -> /usr/local/bin (sha256-verified
#   4. log target, site URL, probe URL,      when downloaded)
#      site time zone                     
#   5. emergency networks (SAFETY_NET)    8. `awacs.sh check`
#                                         9. summary
#
# Usage:
#   sudo ./install.sh                       interactive (whiptail when present)
#   sudo ./install.sh --yes --device-id device1 --log local   unattended (see --help)
#   sudo ./install.sh --dry-run ...         print every action, change nothing
#   sudo ./install.sh --uninstall [--purge]
#   curl -fsSL <release-url>/install.sh | sudo bash -s -- --yes --device-id device1
#
# Rules this file keeps:
#   - it never edits /etc/wpa_supplicant/wpa_supplicant.conf or a NetworkManager profile
#   - it installs stock Debian packages only, and only after showing them
#   - re-runs update what is there instead of duplicating it (unit OR rc.local, never both);
#     the reporting values of an existing /etc/awacs.conf are the defaults of the re-run
#   - /etc/awacs.conf is written root:root 0600 with plain KEY=value lines only
#
# Safety mode: this is a run-once setup script, so `set -euo pipefail` is enabled for
# real. Every command that may legitimately fail carries an explicit `|| :` or `if`.
set -euo pipefail

readonly WIZARD_VERSION="1.0"
readonly BIN_DST="/usr/local/bin/awacs.sh"
readonly CONF="/etc/awacs.conf"
readonly UNIT="/etc/systemd/system/awacs.service"
readonly UNIT_DROPIN_DIR="/etc/systemd/system/awacs.service.d"
readonly UNIT_DROPIN="${UNIT_DROPIN_DIR}/10-device-id.conf"
readonly RC_LOCAL="/etc/rc.local"
readonly LOG_FILE="/var/log/awacs.log"
readonly RUN_DIR="/run/awacs"
readonly AASW_BIN="/usr/local/bin/aasw.sh"
readonly AASW_UNIT="/etc/systemd/system/aasw.service"
readonly RC_MARK_START="# >>> awacs (managed by install.sh) >>>"
readonly RC_MARK_END="# <<< awacs <<<"
readonly CONF_MARK="# awacs install.sh"
# Release files (awacs.sh + SHA256SUMS) for the curl|bash path. Override with
# --release-url or the AWACS_RELEASE_URL environment variable.
RELEASE_BASE_URL="${AWACS_RELEASE_URL:-https://raw.githubusercontent.com/hmne/AWACS/main}"

# ------------------------------- options -----------------------------------------
UI_LANG=""          # en | ar
LOG_TARGET=""       # local | both | remote
SITE_URL=""
PROBE_URL=""
REPORT_WIFI=""      # auto | yes | no  (written only when given)
SITE_TZ=""          # time zone of the site log stamps (written only when given)
EX_LOG_TARGET="" EX_SITE_URL="" EX_PROBE_URL="" EX_REPORT_WIFI="" EX_SITE_TZ=""  # from an existing conf
DEVICE_ID=""
SERVICE=""          # systemd | rc.local
ASSUME_YES=0
DRY_RUN=0
MODE="install"      # install | uninstall
PURGE=0
SKIP_SAFETY=0
declare -a SAFETY_SSIDS=()
declare -a SAFETY_PSKS=()
declare -a WRITTEN=()
SCRIPT_DIR=""
TTY=""
BACKEND="wpa"       # wpa | nm  (mirrors awacs.sh detect_backend without the boot wait)
OS_NAME="unknown"
HAVE_APT=0
HAVE_SYSTEMD=0

# ------------------------------- wizard strings ------------------------------------
# Every key exists in BOTH arrays. `t KEY` prints the current language, `msg KEY A B`
# substitutes {1} {2}. `--selftest` proves the two key sets are identical.
# shellcheck disable=SC2034  # read through a nameref in t()
declare -A MSG_EN=(
  [default]="default"
  [choose]="Choice"
  [yn_hint]="y/n"
  [cancelled]="Cancelled. Nothing was changed."
  [need_tty]="No terminal to ask questions on. Run from a terminal, or pass --yes with the options you want."
  [need_root]="This installer needs root. Restarting with sudo."
  [need_root_nosudo]="This installer needs root and sudo is not available. Run it as root."
  [need_root_pipe]="This installer needs root. Pipe it into sudo:  curl -fsSL <url>/install.sh | sudo bash -s -- [options]"
  [dry_note]="Dry run: nothing was changed."
  [never_touch]="This installer never edits wpa_supplicant.conf or NetworkManager profiles."
  [step]="[{1}/9] {2}"
  [lang_title]="Language"
  [lang_chosen]="Wizard language: English"
  [os_line]="System: {1}"
  [backend_nm]="Network backend: NetworkManager (active or enabled). awacs.sh will supervise it."
  [backend_wpa]="Network backend: dhcpcd + wpa_supplicant."
  [backend_nmcli_missing]="NetworkManager is enabled but nmcli is missing. The network-manager package will be reinstalled."
  [no_apt]="apt-get not found. Packages cannot be installed here; the tool check is shown for information only."
  [pkgs_title]="Tools"
  [pkgs_missing]="Missing tools: {1}. Packages to install: {2}"
  [pkgs_ok]="All required tools are present."
  [pkgs_ask]="Install these packages now?"
  [pkgs_skipped]="Skipped. awacs.sh makes one install attempt by itself after it is online."
  [pkgs_installing]="Installing: {1}"
  [devid_title]="Device id"
  [devid_ask]="Device id (letters, digits, _ or -, up to 32 characters). It names this device on the site."
  [devid_bad]="Invalid device id: {1}"
  [log_title]="Log target"
  [log_ask]="Where should the log go?"
  [log_local]="local file /var/log/awacs.log only"
  [log_both]="local file and the reporting site"
  [log_remote]="site; the local file keeps WARN and ERROR only"
  [site_required]="--log {1} needs --site URL."
  [site_ask]="Site base URL. The script posts to <URL>/<device id>/device_api.php"
  [site_bad]="The URL must start with http:// or https:// and contain no spaces, quotes, backslashes or \$."
  [site_selfhost]="No site yet? server/receiver.php or server/receiver.py in this repository is a small receiver you can host yourself (server/README.md)."
  [site_check]="Checking {1} ..."
  [site_ok]="The site answered HTTP 400 as the contract requires. It is reachable."
  [site_fail]="Expected HTTP 400, got '{1}'. The site is unreachable or does not speak the device_api contract."
  [site_fail_ask]="What next?"
  [site_retry]="enter another URL"
  [site_keep]="keep this URL anyway"
  [site_local]="fall back to local logging"
  [probe_ask]="Upload-speed probe URL (optional). Empty without a site = signal mode: no upload probes, the fight rides the strongest visible stored network that delivers internet, and the slow-upload evaluation stays off."
  [probe_bad]="The probe URL must start with http:// or https:// and contain no spaces, quotes, backslashes or \$."
  [probe_unreach]="No HTTP answer from the probe URL. It is saved anyway; the script measures 0 kbps until it answers."
  [tz_ask]="Time zone for the stamps on the site's log lines (e.g. Europe/Berlin). Empty = the device's own zone."
  [tz_bad]="The time zone may contain letters, digits, / _ + - only, up to 64 characters."
  [reuse_note]="Existing /etc/awacs.conf found: its reporting values are the defaults below."
  [safety_title]="Emergency networks"
  [safety_intro]="Emergency networks are tried after every known network fails and before any open network. Name and password are stored in /etc/awacs.conf (root only, mode 600)."
  [safety_ask]="Add an emergency network?"
  [safety_more]="Add another one?"
  [safety_ssid]="Network name (SSID)"
  [safety_pass]="Password (leave empty for an open hotspot)"
  [safety_bad_ssid]="Name rejected: 1 to 32 bytes, without quotes, backslash, \$ or backtick."
  [safety_bad_pass]="Password rejected: 8 to 63 characters, or 64 hex digits, or empty. No quotes, backslash, \$ or backtick."
  [safety_added]="Added: {1}"
  [safety_none]="No emergency network added. You can add lines later in /etc/awacs.conf."
  [conf_title]="Settings file"
  [conf_written]="Settings written to {1} (root:root, mode 600)."
  [service_title]="Start at boot"
  [service_ask]="How should the daemon start at boot?"
  [service_systemd]="systemd unit awacs.service (recommended)"
  [service_rclocal]="a line in /etc/rc.local"
  [service_no_systemd]="systemctl not found; the rc.local method is used."
  [unit_written]="Unit written: {1} (device id in {2})."
  [rclocal_written]="rc.local line written. rc-local.service runs it at boot when /etc/rc.local is executable."
  [rclocal_devid_differs]="rc.local already exports DEVICE_ID={1}; the line was kept. The chosen id {2} is NOT applied there."
  [both_removed_rclocal]="The awacs line was removed from rc.local: one boot method only."
  [both_removed_unit]="awacs.service was disabled and removed: one boot method only."
  [aasw_found]="The old aasw.sh was found:"
  [aasw_why]="Two WiFi authorities on one radio fight: each undoes the other's connection. Only one may run."
  [aasw_ask]="Disable aasw.sh now? (rc.local line commented out, file renamed to aasw.sh.disabled, running process stopped)"
  [aasw_disabled]="aasw.sh disabled."
  [aasw_kept]="aasw.sh left as is. awacs.sh warns about it in its log while both run."
  [bin_title]="Install awacs.sh"
  [bin_src_local]="Source: {1}"
  [bin_download]="Downloading {1}"
  [bin_dl_fail]="Download failed: {1}"
  [bin_sha_missing]="SHA256SUMS has no entry for awacs.sh. Stopping."
  [bin_sha_bad]="sha256 mismatch: the file is not the published one. Stopping."
  [bin_sha_ok]="sha256 verified."
  [bin_bad]="{1} does not look like awacs.sh (header or bash -n failed). Stopping."
  [bin_installed]="Installed {1} (root:root, mode 755)."
  [daemon_restarted]="Daemon restarted (systemctl restart awacs.service)."
  [daemon_signalled]="Running daemon stopped; the rc.local loop respawns it within 10 seconds."
  [daemon_started]="Daemon started in the background (rc.local style loop). It starts by itself at the next boot."
  [check_title]="Check"
  [check_run]="Running: awacs.sh check"
  [summary_title]="Done"
  [summary_files]="Files written:"
  [summary_logs]="Log:        sudo tail -f /var/log/awacs.log    (service messages: journalctl -u awacs)"
  [summary_status]="Status:     sudo awacs.sh status     |  sudo awacs.sh help"
  [summary_uninstall]="Uninstall:  sudo ./install.sh --uninstall    (--purge also removes the settings and the log)"
  [uninst_title]="Uninstall"
  [uninst_stopped]="Service stopped and disabled."
  [uninst_removed]="Removed: {1}"
  [uninst_kept]="Kept: {1}  (use --purge to remove them too)"
  [uninst_loop_note]="An rc.local respawn loop from the current boot may still be alive; it ends at the next reboot."
)
# shellcheck disable=SC2034  # read through a nameref in t()
declare -A MSG_AR=(
  [default]="الافتراضي"
  [choose]="الاختيار"
  [yn_hint]="ن/ل"
  [cancelled]="أُلغي. لم يتغيّر شيء."
  [need_tty]="لا توجد طرفية لطرح الأسئلة. شغّل المثبّت من طرفية، أو أضف --yes مع الخيارات التي تريدها."
  [need_root]="يحتاج المثبّت صلاحيات root. يُعاد تشغيله عبر sudo."
  [need_root_nosudo]="يحتاج المثبّت صلاحيات root ولا يوجد sudo. شغّله بحساب root."
  [need_root_pipe]="يحتاج المثبّت صلاحيات root. مرّره إلى sudo:  curl -fsSL <url>/install.sh | sudo bash -s -- [الخيارات]"
  [dry_note]="تشغيل تجريبي: لم يتغيّر شيء."
  [never_touch]="هذا المثبّت لا يعدّل wpa_supplicant.conf ولا ملفات NetworkManager أبداً."
  [step]="[{1}/9] {2}"
  [lang_title]="اللغة"
  [lang_chosen]="لغة المعالج: العربية"
  [os_line]="النظام: {1}"
  [backend_nm]="نظام الشبكة: NetworkManager (يعمل أو مفعّل). سيشرف عليه awacs.sh."
  [backend_wpa]="نظام الشبكة: dhcpcd + wpa_supplicant."
  [backend_nmcli_missing]="NetworkManager مفعّل لكن nmcli غير موجود. ستُعاد تهيئة حزمة network-manager."
  [no_apt]="لا يوجد apt-get. لا يمكن تثبيت الحزم هنا؛ فحص الأدوات للعلم فقط."
  [pkgs_title]="الأدوات"
  [pkgs_missing]="أدوات ناقصة: {1}. الحزم التي ستُثبَّت: {2}"
  [pkgs_ok]="كل الأدوات المطلوبة موجودة."
  [pkgs_ask]="تثبيت هذه الحزم الآن؟"
  [pkgs_skipped]="تم التجاوز. سيحاول awacs.sh تثبيتها مرة واحدة بنفسه بعد اتصاله بالإنترنت."
  [pkgs_installing]="جارٍ التثبيت: {1}"
  [devid_title]="معرّف الجهاز"
  [devid_ask]="معرّف الجهاز (حروف وأرقام و _ و -، حتى 32 حرفاً). يُعرّف هذا الجهاز على الموقع."
  [devid_bad]="معرّف جهاز غير صالح: {1}"
  [log_title]="وجهة اللوق"
  [log_ask]="إلى أين يذهب اللوق؟"
  [log_local]="الملف المحلي /var/log/awacs.log فقط"
  [log_both]="الملف المحلي والموقع معاً"
  [log_remote]="الموقع؛ ويحتفظ الملف المحلي بسطور WARN وERROR فقط"
  [site_required]="الخيار --log {1} يحتاج --site مع العنوان."
  [site_ask]="عنوان الموقع الأساسي. يرسل السكربت إلى <URL>/<معرّف الجهاز>/device_api.php"
  [site_bad]="يجب أن يبدأ العنوان بـ http:// أو https:// وألا يحوي مسافات أو علامات تنصيص أو \\ أو \$."
  [site_selfhost]="لا موقع لديك؟ في هذا المستودع ملفا server/receiver.php وserver/receiver.py كمستقبِل صغير تستضيفه بنفسك (server/README.md)."
  [site_check]="فحص {1} ..."
  [site_ok]="ردّ الموقع بـ HTTP 400 كما يقتضي العقد. الموقع متاح."
  [site_fail]="المتوقع HTTP 400 لكن الردّ كان '{1}'. الموقع غير متاح أو لا يتبع عقد device_api."
  [site_fail_ask]="ماذا الآن؟"
  [site_retry]="إدخال عنوان آخر"
  [site_keep]="الإبقاء على هذا العنوان"
  [site_local]="الرجوع إلى اللوق المحلي"
  [probe_ask]="عنوان فحص سرعة الرفع (اختياري). فارغ بلا موقع = وضع الإشارة: لا فحص للرفع، والقتال يركب أقوى شبكة مخزنة ظاهرة تعطي إنترنت، وتقييم الرفع البطيء معطّل."
  [probe_bad]="يجب أن يبدأ عنوان الفحص بـ http:// أو https:// وألا يحوي مسافات أو علامات تنصيص أو \\ أو \$."
  [probe_unreach]="لا ردّ HTTP من عنوان الفحص. حُفظ على أي حال؛ يقيس السكربت 0 كيلوبت/ث حتى يردّ."
  [tz_ask]="المنطقة الزمنية لأختام سطور لوق الموقع (مثل Europe/Berlin). فارغ = منطقة الجهاز نفسه."
  [tz_bad]="المنطقة الزمنية تحوي حروفاً وأرقاماً و / _ + - فقط، حتى 64 حرفاً."
  [reuse_note]="وُجد /etc/awacs.conf سابق: قيم التقارير فيه هي الافتراضيات أدناه."
  [safety_title]="شبكات الطوارئ"
  [safety_intro]="تُجرَّب شبكات الطوارئ بعد فشل كل الشبكات المعروفة وقبل أي شبكة مفتوحة. يُحفظ الاسم وكلمة السر في /etc/awacs.conf (للـ root فقط، صلاحية 600)."
  [safety_ask]="إضافة شبكة طوارئ؟"
  [safety_more]="إضافة شبكة أخرى؟"
  [safety_ssid]="اسم الشبكة (SSID)"
  [safety_pass]="كلمة السر (اتركها فارغة لهوتسبوت مفتوح)"
  [safety_bad_ssid]="رُفض الاسم: من 1 إلى 32 بايت، بلا علامات تنصيص أو \\ أو \$ أو \`."
  [safety_bad_pass]="رُفضت كلمة السر: من 8 إلى 63 حرفاً، أو 64 رقماً سداسياً، أو فارغة. بلا علامات تنصيص أو \\ أو \$ أو \`."
  [safety_added]="أُضيفت: {1}"
  [safety_none]="لم تُضَف شبكة طوارئ. يمكنك إضافة سطور لاحقاً في /etc/awacs.conf."
  [conf_title]="ملف الإعدادات"
  [conf_written]="كُتبت الإعدادات في {1} (root:root، صلاحية 600)."
  [service_title]="التشغيل عند الإقلاع"
  [service_ask]="كيف يبدأ الحارس عند الإقلاع؟"
  [service_systemd]="وحدة systemd باسم awacs.service (مستحسن)"
  [service_rclocal]="سطر في /etc/rc.local"
  [service_no_systemd]="لا يوجد systemctl؛ ستُستخدم طريقة rc.local."
  [unit_written]="كُتبت الوحدة: {1} (معرّف الجهاز في {2})."
  [rclocal_written]="كُتب سطر rc.local. تشغّله خدمة rc-local.service عند الإقلاع ما دام /etc/rc.local قابلاً للتنفيذ."
  [rclocal_devid_differs]="يصدّر rc.local أصلاً DEVICE_ID={1}؛ أُبقي السطر كما هو. المعرّف المختار {2} لم يُطبَّق هناك."
  [both_removed_rclocal]="حُذف سطر awacs من rc.local: طريقة إقلاع واحدة فقط."
  [both_removed_unit]="عُطّلت awacs.service وحُذفت: طريقة إقلاع واحدة فقط."
  [aasw_found]="وُجد aasw.sh القديم:"
  [aasw_why]="سلطتان للواي فاي على راديو واحد تتصارعان: كل واحدة تُسقط اتصال الأخرى. يجب أن تعمل واحدة فقط."
  [aasw_ask]="تعطيل aasw.sh الآن؟ (يُعلَّق سطره في rc.local، ويُعاد تسمية الملف إلى aasw.sh.disabled، وتُوقَف العملية العاملة)"
  [aasw_disabled]="عُطّل aasw.sh."
  [aasw_kept]="أُبقي aasw.sh كما هو. سيحذّر awacs.sh منه في اللوق ما داما يعملان معاً."
  [bin_title]="تثبيت awacs.sh"
  [bin_src_local]="المصدر: {1}"
  [bin_download]="جارٍ تنزيل {1}"
  [bin_dl_fail]="فشل التنزيل: {1}"
  [bin_sha_missing]="لا يوجد سطر لـ awacs.sh في SHA256SUMS. توقف."
  [bin_sha_bad]="اختلاف sha256: الملف ليس هو المنشور. توقف."
  [bin_sha_ok]="تحقق sha256 ناجح."
  [bin_bad]="الملف {1} لا يبدو awacs.sh (الترويسة أو bash -n فشلا). توقف."
  [bin_installed]="ثُبّت {1} (root:root، صلاحية 755)."
  [daemon_restarted]="أُعيد تشغيل الحارس (systemctl restart awacs.service)."
  [daemon_signalled]="أُوقف الحارس العامل؛ تعيد حلقة rc.local تشغيله خلال 10 ثوانٍ."
  [daemon_started]="بدأ الحارس في الخلفية (حلقة على نمط rc.local). يبدأ بنفسه عند الإقلاع التالي."
  [check_title]="الفحص"
  [check_run]="تشغيل: awacs.sh check"
  [summary_title]="تمّ"
  [summary_files]="الملفات المكتوبة:"
  [summary_logs]="اللوق:      sudo tail -f /var/log/awacs.log    (رسائل الخدمة: journalctl -u awacs)"
  [summary_status]="الحالة:     sudo awacs.sh status     |  sudo awacs.sh help"
  [summary_uninstall]="الإزالة:    sudo ./install.sh --uninstall    (ومع --purge تُحذف الإعدادات واللوق أيضاً)"
  [uninst_title]="الإزالة"
  [uninst_stopped]="أُوقفت الخدمة وعُطّلت."
  [uninst_removed]="حُذف: {1}"
  [uninst_kept]="أُبقي: {1}  (استعمل --purge لحذفهما أيضاً)"
  [uninst_loop_note]="قد تبقى حلقة rc.local من الإقلاع الحالي حيّة؛ تنتهي عند إعادة التشغيل التالية."
)

t() {  # KEY -> text in the current language (falls back to the key itself)
  local lang=${UI_LANG:-en}
  local -n _m="MSG_${lang^^}"
  printf '%s' "${_m[$1]-$1}"
}
t_in() {  # LANG KEY -> text in a given language (the few lines shown before a choice exists)
  local UI_LANG=$1
  t "$2"
}
msg() {  # KEY [ARG...] -> text with {1} {2} ... substituted
  local s i=0 a
  s=$(t "$1"); shift
  for a in "$@"; do
    i=$(( i + 1 ))
    s=${s//"{$i}"/$a}
  done
  printf '%s' "$s"
}
say()  { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }
die()  { warn "$*"; exit 1; }
step()   { printf '\n%s\n' "$(msg step "$1" "$(t "$2")")"; }
header() { printf '\n%s\n' "$(t "$1")"; }

# ------------------------------- dry-run wrappers ------------------------------------
run() {  # execute, or print under --dry-run
  if (( DRY_RUN )); then
    say "[dry-run] $*"
    return 0
  fi
  "$@"
}
write_file() {  # DST MODE ; content on stdin. Atomic: temp in the same dir, then mv.
  local dst=$1 mode=$2 content dir tmp
  content=$(cat)
  WRITTEN+=("$dst")
  if (( DRY_RUN )); then
    say "[dry-run] write ${dst} (mode ${mode}, root:root):"
    # passwords never reach the terminal, even in a dry run
    printf '%s\n' "$content" | sed -E 's/^(SAFETY_NET\[.*\]=").*"/\1********"/; s/^/    | /'
    return 0
  fi
  dir=$(dirname "$dst")
  mkdir -p "$dir"
  tmp=$(mktemp "${dir}/.awacs.XXXXXX")
  printf '%s\n' "$content" >"$tmp"
  chmod "$mode" "$tmp"
  chown root:root "$tmp"
  mv -f "$tmp" "$dst"
}

# ------------------------------- prompts ---------------------------------------------
find_tty() {
  if [[ -t 0 ]]; then
    TTY=/dev/stdin
  elif { : </dev/tty; } 2>/dev/null; then
    TTY=/dev/tty     # curl | bash: stdin is the pipe, the terminal is still there
  else
    TTY=""
  fi
}
use_whiptail() {
  [[ -n $TTY ]] && command -v whiptail >/dev/null 2>&1
}
ui_menu() {  # TITLE TEXT DEFAULT tag label [tag label ...] -> prints the chosen tag
  local title=$1 text=$2 def=$3 out ans i n
  shift 3
  local -a items=("$@")
  if (( ASSUME_YES )) || [[ -z $TTY ]]; then
    printf '%s' "$def"
    return 0
  fi
  if use_whiptail; then
    out=$(whiptail --title "$title" --default-item "$def" --menu "$text" 20 76 8 \
            "${items[@]}" 3>&1 1>&2 2>&3 <"$TTY") || die "$(t cancelled)"
    printf '%s' "$out"
    return 0
  fi
  n=$(( ${#items[@]} / 2 ))
  while :; do
    printf '\n%s\n%s\n' "$title" "$text" >&2
    for (( i = 0; i < n; i++ )); do
      if [[ ${items[i * 2]} == "$def" ]]; then
        printf '  %d) %-10s %s  [%s]\n' "$(( i + 1 ))" "${items[i * 2]}" "${items[i * 2 + 1]}" "$(t default)" >&2
      else
        printf '  %d) %-10s %s\n' "$(( i + 1 ))" "${items[i * 2]}" "${items[i * 2 + 1]}" >&2
      fi
    done
    printf '%s [%s]: ' "$(t choose)" "$def" >&2
    IFS= read -r ans <"$TTY" || ans=""
    if [[ -z $ans ]]; then
      printf '%s' "$def"
      return 0
    fi
    for (( i = 0; i < n; i++ )); do
      if [[ $ans == "$(( i + 1 ))" || $ans == "${items[i * 2]}" ]]; then
        printf '%s' "${items[i * 2]}"
        return 0
      fi
    done
  done
}
ui_input() {  # TITLE TEXT DEFAULT -> prints the answer
  local title=$1 text=$2 def=$3 out
  if (( ASSUME_YES )) || [[ -z $TTY ]]; then
    printf '%s' "$def"
    return 0
  fi
  if use_whiptail; then
    out=$(whiptail --title "$title" --inputbox "$text" 12 76 "$def" 3>&1 1>&2 2>&3 <"$TTY") \
      || die "$(t cancelled)"
    printf '%s' "$out"
    return 0
  fi
  printf '\n%s\n%s [%s]: ' "$title" "$text" "$def" >&2
  IFS= read -r out <"$TTY" || out=""
  printf '%s' "${out:-$def}"
}
ui_secret() {  # TITLE TEXT -> prints the answer (not echoed)
  local title=$1 text=$2 out
  if (( ASSUME_YES )) || [[ -z $TTY ]]; then
    printf ''
    return 0
  fi
  if use_whiptail; then
    out=$(whiptail --title "$title" --passwordbox "$text" 12 76 3>&1 1>&2 2>&3 <"$TTY") \
      || die "$(t cancelled)"
    printf '%s' "$out"
    return 0
  fi
  printf '\n%s\n%s: ' "$title" "$text" >&2
  IFS= read -r -s out <"$TTY" || out=""
  printf '\n' >&2
  printf '%s' "$out"
}
ui_yesno() {  # TITLE TEXT DEFAULT(yes|no) -> exit 0 for yes
  local title=$1 text=$2 def=$3 ans
  local -a flag=()
  if (( ASSUME_YES )) || [[ -z $TTY ]]; then
    [[ $def == yes ]]
    return
  fi
  if use_whiptail; then
    [[ $def == no ]] && flag=(--defaultno)
    if whiptail --title "$title" "${flag[@]}" --yesno "$text" 14 76 <"$TTY"; then return 0; fi
    return 1
  fi
  while :; do
    printf '\n%s\n%s (%s) [%s]: ' "$title" "$text" "$(t yn_hint)" "$def" >&2
    IFS= read -r ans <"$TTY" || ans=""
    ans=${ans,,}
    [[ -z $ans ]] && ans=$def
    case $ans in
      y|yes|ن|نعم) return 0 ;;
      n|no|ل|لا)   return 1 ;;
    esac
  done
}
# ------------------------------- detection -----------------------------------------
detect_os() {
  local id="" like="" pretty=""
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    IFS=$'\n' read -r -d '' id like pretty < <(
      . /etc/os-release 2>/dev/null || :
      printf '%s\n%s\n%s\n' "${ID:-}" "${ID_LIKE:-}" "${PRETTY_NAME:-}"
    ) || :
  fi
  if [[ -f /etc/rpi-issue || $id == raspbian ]]; then
    OS_NAME="Raspberry Pi OS (${pretty:-Debian})"
  elif [[ $id == debian ]]; then
    OS_NAME="${pretty:-Debian}"
  elif [[ $id == ubuntu ]]; then
    OS_NAME="${pretty:-Ubuntu}"
  elif [[ $like == *debian* ]]; then
    OS_NAME="${pretty:-Debian-based} (Debian family)"
  else
    OS_NAME="${pretty:-unknown}"
  fi
  command -v apt-get >/dev/null 2>&1 && HAVE_APT=1
  command -v systemctl >/dev/null 2>&1 && HAVE_SYSTEMD=1
  return 0
}
detect_backend() {  # same verdict rule as awacs.sh: enabled OR active NetworkManager = nm
  BACKEND="wpa"
  if (( HAVE_SYSTEMD )); then
    if systemctl is-active --quiet NetworkManager 2>/dev/null \
       || systemctl is-enabled --quiet NetworkManager 2>/dev/null; then
      BACKEND="nm"
    fi
  fi
}
show_detection() {
  say "$(msg os_line "$OS_NAME")"
  if [[ $BACKEND == nm ]]; then
    say "$(t backend_nm)"
    command -v nmcli >/dev/null 2>&1 || say "$(t backend_nmcli_missing)"
  else
    say "$(t backend_wpa)"
  fi
}

# ------------------------------- step 2: tools -----------------------------------------
pkg_for() {  # tool -> Debian package (the same table awacs.sh uses in install_tools)
  case $1 in
    wpa_cli)           printf 'wpasupplicant' ;;
    nmcli)             printf 'network-manager' ;;
    ip)                printf 'iproute2' ;;
    ping)              printf 'iputils-ping' ;;
    awk)               printf 'mawk' ;;
    pgrep)             printf 'procps' ;;
    flock)             printf 'util-linux' ;;
    timeout|stat|date) printf 'coreutils' ;;
    modprobe)          printf 'kmod' ;;
    *)                 printf '%s' "$1" ;;
  esac
}
step_tools() {
  step 2 pkgs_title
  local -a tools=(iw ip ping curl awk sed grep pgrep rfkill flock timeout stat date modprobe)
  local -a missing=() pkgs=()
  local t p reinstall=0
  if [[ $BACKEND == nm ]]; then tools+=(nmcli); else tools+=(wpa_cli); fi
  for t in "${tools[@]}"; do
    command -v "$t" >/dev/null 2>&1 && continue
    missing+=("$t")
    p=$(pkg_for "$t")
    [[ $t == nmcli ]] && reinstall=1   # NM present, CLI gone = a broken package: reinstall
    [[ " ${pkgs[*]} " == *" ${p} "* ]] || pkgs+=("$p")
  done
  if (( ${#missing[@]} == 0 )); then
    say "$(t pkgs_ok)"
    return 0
  fi
  say "$(msg pkgs_missing "${missing[*]}" "${pkgs[*]}")"
  if (( ! HAVE_APT )); then
    warn "$(t no_apt)"
    return 0
  fi
  if ! ui_yesno "$(t pkgs_title)" "$(msg pkgs_missing "${missing[*]}" "${pkgs[*]}")"$'\n'"$(t pkgs_ask)" yes; then
    say "$(t pkgs_skipped)"
    return 0
  fi
  say "$(msg pkgs_installing "${pkgs[*]}")"
  run env DEBIAN_FRONTEND=noninteractive apt-get update -q
  if (( reinstall )); then
    run env DEBIAN_FRONTEND=noninteractive apt-get install -y -q --reinstall "${pkgs[@]}"
  else
    run env DEBIAN_FRONTEND=noninteractive apt-get install -y -q "${pkgs[@]}"
  fi
}

# ------------------------------- step 3: device id ------------------------------------
valid_device_id() { [[ $1 =~ ^[A-Za-z0-9_-]{1,32}$ ]]; }
current_device_id() {  # what an earlier install left behind, if anything
  local v=""
  if [[ -r $UNIT_DROPIN ]]; then
    v=$(sed -n 's/^Environment=DEVICE_ID=//p' "$UNIT_DROPIN" | head -1)
  fi
  if [[ -z $v && -r $RC_LOCAL ]]; then
    v=$(sed -n -E 's/^[[:space:]]*export DEVICE_ID="?([A-Za-z0-9_-]{1,32})"?.*/\1/p' "$RC_LOCAL" | head -1)
  fi
  if [[ -z $v ]]; then   # awacs.sh's own fallback order: hostname -s, then "device"
    v=$(hostname -s 2>/dev/null || :)
    valid_device_id "$v" || v=device
  fi
  printf '%s' "$v"
}
step_device_id() {
  step 3 devid_title
  local def ans
  def=$(current_device_id)
  if [[ -n $DEVICE_ID ]]; then
    valid_device_id "$DEVICE_ID" || die "$(msg devid_bad "$DEVICE_ID")"
    say "DEVICE_ID=${DEVICE_ID}"
    return 0
  fi
  while :; do
    ans=$(ui_input "$(t devid_title)" "$(t devid_ask)" "$def")
    if valid_device_id "$ans"; then
      DEVICE_ID=$ans
      break
    fi
    warn "$(msg devid_bad "$ans")"
    (( ASSUME_YES )) && exit 1
  done
  say "DEVICE_ID=${DEVICE_ID}"
}

# ------------------------------- step 4: log target -----------------------------------
# Values land inside "..." in a file that awacs.sh SOURCES: a quote, backslash, $ or
# backtick would change the meaning, so none of them is accepted anywhere.
readonly URL_RE='^https?://[^[:space:]"\\$`]+$'
readonly BAD_CHARS='*["\\$`]*'
valid_url() { [[ $1 =~ $URL_RE ]]; }
valid_tz()  { [[ $1 =~ ^[A-Za-z0-9/_+-]{1,64}$ ]]; }   # awacs.sh's own SITE_TZ shape check
load_existing_conf() {  # the reporting values of an existing conf become the re-run's defaults
  local k v
  [[ -r $CONF ]] || return 0
  while IFS='=' read -r k v; do
    v=${v%%[[:space:]]#*}; v=${v%\"}; v=${v#\"}
    case $k in
      LOG_TARGET)  EX_LOG_TARGET=$v ;;
      SITE_URL)    EX_SITE_URL=${v%/} ;;
      PROBE_URL)   EX_PROBE_URL=$v ;;
      REPORT_WIFI) EX_REPORT_WIFI=$v ;;
      SITE_TZ)     EX_SITE_TZ=$v ;;
    esac
  done < <(grep -E '^(LOG_TARGET|SITE_URL|PROBE_URL|REPORT_WIFI|SITE_TZ)=' "$CONF" 2>/dev/null || :)
  [[ $EX_LOG_TARGET =~ ^(local|both|remote)$ ]] || EX_LOG_TARGET=""
  [[ $EX_REPORT_WIFI =~ ^(auto|yes|no)$ ]]     || EX_REPORT_WIFI=""
  [[ -z $EX_SITE_URL ]]  || valid_url "$EX_SITE_URL"  || EX_SITE_URL=""
  [[ -z $EX_PROBE_URL ]] || valid_url "$EX_PROBE_URL" || EX_PROBE_URL=""
  [[ -z $EX_SITE_TZ ]]   || valid_tz "$EX_SITE_TZ"    || EX_SITE_TZ=""
  [[ -n $EX_LOG_TARGET$EX_SITE_URL$EX_PROBE_URL$EX_REPORT_WIFI$EX_SITE_TZ ]] && say "$(t reuse_note)"
  return 0
}
http_code() {  # URL [curl data option...] -> the HTTP code, 000 when nothing answered
  local url=$1 code=""
  shift
  command -v curl >/dev/null 2>&1 || { printf '000'; return 0; }
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "$@" "$url" 2>/dev/null) || :
  printf '%s' "${code:-000}"
}
site_signature() {  # the contract probe: a reachable site answers 400 "Error: no operation"
  http_code "${1}/${DEVICE_ID}/device_api.php" --data-urlencode "probe=1"
}
ask_site_url() {
  local ans code choice
  say "$(t site_selfhost)"
  while :; do
    ans=$(ui_input "$(t log_title)" "$(t site_ask)" "${SITE_URL}")
    ans=${ans%/}
    if ! valid_url "$ans"; then
      warn "$(t site_bad)"
      (( ASSUME_YES )) && exit 1
      continue
    fi
    say "$(msg site_check "${ans}/${DEVICE_ID}/device_api.php")"
    code=$(site_signature "$ans")
    if [[ $code == 400 ]]; then
      say "$(t site_ok)"
      SITE_URL=$ans
      return 0
    fi
    warn "$(msg site_fail "$code")"
    if (( ASSUME_YES )); then
      SITE_URL=$ans     # unattended: the box may simply be offline right now; the daemon spools
      return 0
    fi
    choice=$(ui_menu "$(t log_title)" "$(msg site_fail "$code")"$'\n'"$(t site_fail_ask)" retry \
               retry "$(t site_retry)" keep "$(t site_keep)" local "$(t site_local)")
    case $choice in
      keep)  SITE_URL=$ans; return 0 ;;
      local) SITE_URL=""; LOG_TARGET="local"; return 0 ;;
      *)     continue ;;
    esac
  done
}
ask_probe_url() {
  local ans code
  while :; do
    ans=$(ui_input "$(t log_title)" "$(t probe_ask)" "${PROBE_URL}")
    [[ -z $ans ]] && return 0
    if ! valid_url "$ans"; then
      warn "$(t probe_bad)"
      (( ASSUME_YES )) && exit 1
      continue
    fi
    code=$(http_code "$ans" --data "probe=1")
    [[ $code == 000 ]] && warn "$(t probe_unreach)"
    PROBE_URL=$ans
    return 0
  done
}
ask_tz() {
  local ans
  while :; do
    ans=$(ui_input "$(t log_title)" "$(t tz_ask)" "${SITE_TZ}")
    [[ -z $ans ]] && { SITE_TZ=""; return 0; }
    if valid_tz "$ans"; then SITE_TZ=$ans; return 0; fi
    warn "$(t tz_bad)"
    (( ASSUME_YES )) && exit 1
  done
}
step_log_target() {
  step 4 log_title
  load_existing_conf
  # command line first, then the existing conf, then the built-in defaults
  [[ -n $SITE_URL ]]    || SITE_URL=$EX_SITE_URL
  [[ -n $PROBE_URL ]]   || PROBE_URL=$EX_PROBE_URL
  [[ -n $REPORT_WIFI ]] || REPORT_WIFI=$EX_REPORT_WIFI
  [[ -n $SITE_TZ ]]     || SITE_TZ=$EX_SITE_TZ
  if [[ -z $LOG_TARGET ]]; then
    LOG_TARGET=$(ui_menu "$(t log_title)" "$(t log_ask)" "${EX_LOG_TARGET:-local}" \
                   local "$(t log_local)" both "$(t log_both)" remote "$(t log_remote)")
  fi
  if [[ $LOG_TARGET != local && -z $SITE_URL ]] && (( ASSUME_YES )); then
    die "$(msg site_required "$LOG_TARGET")"   # an unattended re-run cannot invent a site
  fi
  if [[ $LOG_TARGET != local ]]; then
    if [[ -n $SITE_URL ]] && (( ASSUME_YES )); then
      local code
      SITE_URL=${SITE_URL%/}
      valid_url "$SITE_URL" || die "$(t site_bad)"
      say "$(msg site_check "${SITE_URL}/${DEVICE_ID}/device_api.php")"
      code=$(site_signature "$SITE_URL")
      if [[ $code == 400 ]]; then say "$(t site_ok)"; else warn "$(msg site_fail "$code")"; fi
    else
      ask_site_url
    fi
  fi
  if [[ -n $PROBE_URL ]]; then
    valid_url "$PROBE_URL" || die "$(t probe_bad)"
  elif [[ -z $SITE_URL ]] && (( ! ASSUME_YES )); then
    ask_probe_url     # with a site, the probe target defaults to the site itself
  fi
  if [[ -n $SITE_TZ ]]; then
    valid_tz "$SITE_TZ" || die "$(t tz_bad)"
  elif [[ -n $SITE_URL ]] && (( ! ASSUME_YES )); then
    ask_tz            # stamps matter only for lines that reach a site
  fi
  say "LOG_TARGET=${LOG_TARGET}  SITE_URL=${SITE_URL:-(empty)}  PROBE_URL=${PROBE_URL:-(default)}  SITE_TZ=${SITE_TZ:-(device)}"
}

# ------------------------------- step 5: emergency networks -----------------------------
valid_ssid() {  # 1..32 bytes; nothing that breaks a sourced "..." value
  local s=$1
  # shellcheck disable=SC2053  # BAD_CHARS is a glob on purpose
  [[ -n $s && $s != $BAD_CHARS && $s != *[[:cntrl:]]* ]] || return 1
  (( $(printf '%s' "$s" | wc -c) <= 32 ))
}
valid_psk() {
  local p=$1
  # shellcheck disable=SC2053  # BAD_CHARS is a glob on purpose
  [[ $p != $BAD_CHARS && $p != *[[:cntrl:]]* ]] || return 1
  [[ -z $p ]] && return 0
  [[ $p =~ ^[0-9a-fA-F]{64}$ ]] && return 0
  (( ${#p} >= 8 && ${#p} <= 63 ))
}
add_safety() {  # SSID PSK — replaces an earlier entry with the same name
  local i
  for i in "${!SAFETY_SSIDS[@]}"; do
    if [[ ${SAFETY_SSIDS[i]} == "$1" ]]; then
      SAFETY_PSKS[i]=$2
      return 0
    fi
  done
  SAFETY_SSIDS+=("$1")
  SAFETY_PSKS+=("$2")
}
step_safety_net() {
  step 5 safety_title
  local ssid psk q=safety_ask
  say "$(t safety_intro)"
  if (( SKIP_SAFETY )) || (( ASSUME_YES )); then
    if (( ${#SAFETY_SSIDS[@]} )); then
      for ssid in "${SAFETY_SSIDS[@]}"; do say "$(msg safety_added "$ssid")"; done
    else
      say "$(t safety_none)"
    fi
    return 0
  fi
  while ui_yesno "$(t safety_title)" "$(t "$q")" no; do
    q=safety_more
    ssid=$(ui_input "$(t safety_title)" "$(t safety_ssid)" "")
    if ! valid_ssid "$ssid"; then
      warn "$(t safety_bad_ssid)"
      continue
    fi
    psk=$(ui_secret "$(t safety_title)" "$(t safety_pass)")
    if ! valid_psk "$psk"; then
      warn "$(t safety_bad_pass)"
      continue
    fi
    add_safety "$ssid" "$psk"
    say "$(msg safety_added "$ssid")"
  done
  (( ${#SAFETY_SSIDS[@]} )) || say "$(t safety_none)"
}

# ------------------------------- write /etc/awacs.conf ------------------------------------
ssid_listed() {
  local s
  for s in "${SAFETY_SSIDS[@]}"; do [[ $s == "$1" ]] && return 0; done
  return 1
}
render_conf() {  # prints the new conf: existing lines kept, managed keys replaced
  local existing="" line name i
  if [[ -r $CONF ]]; then existing=$(cat "$CONF"); fi
  if [[ -z $existing ]]; then
    printf '%s\n' \
      "# /etc/awacs.conf - AWACS settings. Plain KEY=value lines only (awacs.sh sources this file)." \
      "# Root-only, mode 600: emergency-network passwords live here in plain text." \
      "# Every knob and its default: awacs.conf.example in the repository." \
      ""
  else
    while IFS= read -r line; do
      case $line in
        SITE_URL=*|LOG_TARGET=*|PROBE_URL=*|REPORT_WIFI=*|SITE_TZ=*) continue ;;
        "${CONF_MARK}"*) continue ;;
        'SAFETY_NET["'*)
          name=${line#SAFETY_NET[\"}
          name=${name%%\"]=*}
          ssid_listed "$name" && continue ;;
      esac
      printf '%s\n' "$line"
    done <<<"$existing"
  fi
  printf '%s %s\n' "$CONF_MARK" "$(date '+%Y-%m-%d %H:%M')"
  printf 'LOG_TARGET="%s"\n' "$LOG_TARGET"
  printf 'SITE_URL="%s"\n' "$SITE_URL"
  [[ -n $PROBE_URL ]]   && printf 'PROBE_URL="%s"\n' "$PROBE_URL"
  [[ -n $REPORT_WIFI ]] && printf 'REPORT_WIFI="%s"\n' "$REPORT_WIFI"
  [[ -n $SITE_TZ ]]     && printf 'SITE_TZ="%s"\n' "$SITE_TZ"
  for i in "${!SAFETY_SSIDS[@]}"; do
    printf 'SAFETY_NET["%s"]="%s"\n' "${SAFETY_SSIDS[i]}" "${SAFETY_PSKS[i]}"
  done
}
step_write_conf() {  # second half of step 5: the answers land in /etc/awacs.conf
  local content
  content=$(render_conf)
  write_file "$CONF" 600 <<<"$content"   # here-string, not a pipe: WRITTEN must survive
  say "$(msg conf_written "$CONF")"
}

# ------------------------------- step 6: boot method -----------------------------------------
unit_text() {  # byte-identical to systemd/awacs.service in the repository (CI diffs them)
  cat <<'EOF'
# /etc/systemd/system/awacs.service — AWACS daemon.
#
# This unit is the rc.local contract written as a service:
#     ( while :; do /usr/local/bin/awacs.sh; sleep 10; done ) >/dev/null 2>&1 &
# Restart=always + RestartSec=10 is that loop. StartLimitIntervalSec=0 keeps systemd from
# giving up after a burst of quick exits (the rc.local loop never gives up either).
#
# The daemon's job is to make the network work, so it must not wait for network-online:
# it starts right after the early network setup (network-pre.target) and waits for
# NetworkManager itself when that is the backend (up to about 60 s, inside awacs.sh).
#
# DEVICE_ID names the device on the reporting site. install.sh overrides the example
# below in awacs.service.d/10-device-id.conf; edit that file, not this one. Without the
# variable awacs.sh uses the short hostname.
#
# On stop, systemd sends SIGTERM to the daemon and its helpers; awacs.sh traps it,
# hands the network layer back its full autonomy (enable_all) and exits 0.

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
EOF
}
rclocal_render() {  # $1 = current rc.local text, $2 = add|remove -> prints the new text
  local text=$1 action=$2
  [[ -n $text ]] || text=$'#!/bin/sh -e\n\nexit 0'
  printf '%s\n' "$text" | awk -v ms="$RC_MARK_START" -v me="$RC_MARK_END" \
      -v id="$DEVICE_ID" -v action="$action" '
    $0 == ms { skip = 1; next }
    $0 == me { skip = 0; next }
    skip { next }
    /\/usr\/local\/bin\/awacs\.sh/ && $0 !~ /^[[:space:]]*#/ { next }   # a stray hand-made line
    { lines[++n] = $0 }
    END {
      if (action == "remove") { for (i = 1; i <= n; i++) print lines[i]; exit }
      pos = 0; have_export = 0
      for (i = 1; i <= n; i++)
        if (lines[i] ~ /^[[:space:]]*export DEVICE_ID=/) { pos = i; have_export = 1 }
      if (pos == 0) {
        pos = n
        for (i = n; i >= 1; i--)
          if (lines[i] ~ /^[[:space:]]*exit 0[[:space:]]*$/) { pos = i - 1; break }
      }
      for (i = 1; i <= pos; i++) print lines[i]
      print ms
      if (!have_export) print "export DEVICE_ID=\"" id "\""
      print "( while :; do /usr/local/bin/awacs.sh; sleep 10; done ) >/dev/null 2>&1 &"
      print me
      for (i = pos + 1; i <= n; i++) print lines[i]
    }'
}
rclocal_has_awacs() {
  [[ -r $RC_LOCAL ]] || return 1
  grep -qE '^[^#]*/usr/local/bin/awacs\.sh' "$RC_LOCAL" || grep -qFx -- "$RC_MARK_START" "$RC_LOCAL"
}
remove_rclocal_block() {
  local content
  rclocal_has_awacs || return 0
  content=$(rclocal_render "$(cat "$RC_LOCAL")" remove)
  write_file "$RC_LOCAL" 755 <<<"$content"
  say "$(t both_removed_rclocal)"
}
remove_systemd_unit() {
  [[ -e $UNIT || -e $UNIT_DROPIN ]] || return 0
  if (( HAVE_SYSTEMD )); then
    run systemctl disable --now awacs.service 2>/dev/null || :
  fi
  run rm -f "$UNIT" "$UNIT_DROPIN"
  run rmdir "$UNIT_DROPIN_DIR" 2>/dev/null || :
  (( HAVE_SYSTEMD )) && { run systemctl daemon-reload || :; }
  say "$(t both_removed_unit)"
}
install_systemd() {
  local unit dropin
  unit=$(unit_text)
  dropin=$(printf '[Service]\nEnvironment=DEVICE_ID=%s\n' "$DEVICE_ID")
  write_file "$UNIT" 644 <<<"$unit"
  write_file "$UNIT_DROPIN" 644 <<<"$dropin"
  remove_rclocal_block
  run systemctl daemon-reload
  run systemctl enable awacs.service
  say "$(msg unit_written "$UNIT" "$UNIT_DROPIN")"
}
install_rclocal() {
  local cur="" have
  remove_systemd_unit
  [[ -r $RC_LOCAL ]] && cur=$(cat "$RC_LOCAL")
  have=$(printf '%s\n' "$cur" | sed -n -E 's/^[[:space:]]*export DEVICE_ID="?([^" ]*)"?.*/\1/p' | head -1)
  if [[ -n $have && $have != "$DEVICE_ID" ]]; then
    warn "$(msg rclocal_devid_differs "$have" "$DEVICE_ID")"
  fi
  local content
  content=$(rclocal_render "$cur" add)
  write_file "$RC_LOCAL" 755 <<<"$content"
  say "$(t rclocal_written)"
}
detect_aasw() {  # prints one finding per line; empty = nothing found
  local pids
  if [[ -r $RC_LOCAL ]]; then
    grep -nE '^[^#]*aasw\.sh' "$RC_LOCAL" 2>/dev/null | sed 's|^|  rc.local:|' || :
  fi
  [[ -e $AASW_BIN ]] && say "  ${AASW_BIN}"
  [[ -e $AASW_UNIT ]] && say "  ${AASW_UNIT}"
  pids=$(pgrep -f '/usr/local/bin/aasw' 2>/dev/null || :)
  [[ -n $pids ]] && say "  running: pid ${pids//$'\n'/ }"
  return 0
}
disable_aasw() {
  local content
  if [[ -r $RC_LOCAL ]] && grep -qE '^[^#]*aasw\.sh' "$RC_LOCAL"; then
    content=$(sed -E 's|^([^#]*aasw\.sh.*)$|# disabled by awacs install.sh: \1|' "$RC_LOCAL")
    write_file "$RC_LOCAL" 755 <<<"$content"
  fi
  if [[ -e $AASW_UNIT ]] && (( HAVE_SYSTEMD )); then
    run systemctl disable --now aasw.service 2>/dev/null || :
  fi
  [[ -e $AASW_BIN ]] && run mv -f "$AASW_BIN" "${AASW_BIN}.disabled"
  run pkill -TERM -f '/usr/local/bin/aasw' 2>/dev/null || :
  say "$(t aasw_disabled)"
}
step_service() {
  step 6 service_title
  local findings
  findings=$(detect_aasw)
  if [[ -n $findings ]]; then
    say "$(t aasw_found)"
    say "$findings"
    say "$(t aasw_why)"
    if ui_yesno "$(t service_title)" "$(t aasw_found)"$'\n'"${findings}"$'\n\n'"$(t aasw_why)"$'\n'"$(t aasw_ask)" yes; then
      disable_aasw
    else
      say "$(t aasw_kept)"
    fi
  fi
  if [[ -z $SERVICE ]]; then
    if (( HAVE_SYSTEMD )); then
      SERVICE=$(ui_menu "$(t service_title)" "$(t service_ask)" systemd \
                  systemd "$(t service_systemd)" rc.local "$(t service_rclocal)")
    else
      say "$(t service_no_systemd)"
      SERVICE="rc.local"
    fi
  elif [[ $SERVICE == systemd ]] && (( ! HAVE_SYSTEMD )); then
    say "$(t service_no_systemd)"
    SERVICE="rc.local"
  fi
  if [[ $SERVICE == systemd ]]; then install_systemd; else install_rclocal; fi
}

# ------------------------------- step 7: the binary -----------------------------------------
looks_like_awacs() {  # header + syntax gate before anything lands in /usr/local/bin
  local f=$1
  head -1 "$f" | grep -q 'bash' || return 1
  head -5 "$f" | grep -q 'AWACS' || return 1
  bash -n "$f" 2>/dev/null
}
verify_sha256() {  # FILE SUMSFILE
  local want have
  want=$(awk '$2 ~ /(^|\/|\*)awacs\.sh$/ { print $1; exit }' "$2")
  [[ -n $want ]] || die "$(t bin_sha_missing)"
  have=$(sha256sum "$1" | awk '{ print $1 }')
  [[ $want == "$have" ]] || die "$(t bin_sha_bad)"
  say "$(t bin_sha_ok)"
}
daemon_pid() {  # the running daemon's pid from its lock file, verified by its cmdline
  local p=""
  if [[ -s $RUN_DIR/lock ]]; then
    read -r p <"$RUN_DIR/lock" 2>/dev/null || p=""
  fi
  if [[ $p =~ ^[0-9]+$ && -d /proc/$p ]] && grep -aq awacs "/proc/$p/cmdline" 2>/dev/null; then
    printf '%s' "$p"
  fi
}
start_or_restart() {
  local old new i
  if [[ $SERVICE == systemd ]]; then
    run systemctl restart awacs.service
    say "$(t daemon_restarted)"
    return 0
  fi
  old=$(daemon_pid)
  if [[ -n $old ]]; then
    run kill -TERM "$old"
    say "$(t daemon_signalled)"
    (( DRY_RUN )) && return 0
    for (( i = 0; i < 15; i++ )); do   # the rc.local loop respawns within ~10 s
      sleep 1
      new=$(daemon_pid)
      [[ -n $new && $new != "$old" ]] && return 0
    done
  fi
  # no loop alive (fresh install): start one that survives this shell, as rc.local would
  run setsid bash -c "export DEVICE_ID='${DEVICE_ID}'; ( while :; do ${BIN_DST}; sleep 10; done ) >/dev/null 2>&1 </dev/null &"
  say "$(t daemon_started)"
}
step_binary() {
  step 7 bin_title
  local src="" tmpd=""
  if [[ -n $SCRIPT_DIR && -f $SCRIPT_DIR/awacs.sh ]]; then
    src="${SCRIPT_DIR}/awacs.sh"
    say "$(msg bin_src_local "$src")"
    [[ -f $SCRIPT_DIR/SHA256SUMS ]] && verify_sha256 "$src" "${SCRIPT_DIR}/SHA256SUMS"
  else
    say "$(msg bin_download "${RELEASE_BASE_URL}/awacs.sh")"
    if (( DRY_RUN )); then
      say "[dry-run] curl -fsSL --max-time 60 -o <tmp>/awacs.sh ${RELEASE_BASE_URL}/awacs.sh"
      say "[dry-run] curl -fsSL --max-time 30 -o <tmp>/SHA256SUMS ${RELEASE_BASE_URL}/SHA256SUMS"
      say "[dry-run] sha256sum -c (awacs.sh line of SHA256SUMS)"
    else
      tmpd=$(mktemp -d)
      curl -fsSL --max-time 60 -o "${tmpd}/awacs.sh" "${RELEASE_BASE_URL}/awacs.sh" \
        || die "$(msg bin_dl_fail "${RELEASE_BASE_URL}/awacs.sh")"
      curl -fsSL --max-time 30 -o "${tmpd}/SHA256SUMS" "${RELEASE_BASE_URL}/SHA256SUMS" \
        || die "$(msg bin_dl_fail "${RELEASE_BASE_URL}/SHA256SUMS")"
      verify_sha256 "${tmpd}/awacs.sh" "${tmpd}/SHA256SUMS"
      src="${tmpd}/awacs.sh"
    fi
  fi
  if [[ -n $src ]]; then
    looks_like_awacs "$src" || die "$(msg bin_bad "$src")"
    if (( DRY_RUN )); then
      say "[dry-run] install -m 755 -o root -g root ${src} ${BIN_DST}"
    else
      local tmp
      tmp=$(mktemp /usr/local/bin/.awacs.XXXXXX)
      cp "$src" "$tmp"
      chmod 755 "$tmp"
      chown root:root "$tmp"
      mv -f "$tmp" "$BIN_DST"     # atomic: a running daemon keeps its old inode
    fi
    WRITTEN+=("$BIN_DST")
    say "$(msg bin_installed "$BIN_DST")"
  fi
  [[ -n $tmpd ]] && rm -rf "$tmpd"
  start_or_restart
}

# ------------------------------- steps 8 and 9 -----------------------------------------
step_check() {
  step 8 check_title
  say "$(t check_run)"
  if (( DRY_RUN )); then
    say "[dry-run] ${BIN_DST} check"
    return 0
  fi
  local out rc=0
  out=$("$BIN_DST" check 2>&1) || rc=$?
  say "  ${out}  (exit ${rc})"
}
step_summary() {
  step 9 summary_title
  local f
  say "$(t summary_files)"
  for f in "${WRITTEN[@]}"; do say "  ${f}"; done
  say ""
  say "$(t summary_logs)"
  say "$(t summary_status)"
  say "$(t summary_uninstall)"
  say "$(t never_touch)"
  (( DRY_RUN )) && say "$(t dry_note)"
  return 0
}

# ------------------------------- uninstall -----------------------------------------
do_uninstall() {
  header uninst_title
  local p
  if [[ -e $UNIT || -e $UNIT_DROPIN ]]; then
    remove_systemd_unit
    say "$(t uninst_stopped)"
  fi
  remove_rclocal_block
  p=$(daemon_pid)
  [[ -n $p ]] && { run kill -TERM "$p" || :; }
  run pkill -TERM -f "${BIN_DST}" 2>/dev/null || :
  if [[ -e $BIN_DST ]]; then
    run rm -f "$BIN_DST"
    say "$(msg uninst_removed "$BIN_DST")"
  fi
  if (( PURGE )); then
    run rm -f "$CONF" "$LOG_FILE" "${LOG_FILE}.t"
    run rm -rf "$RUN_DIR"
    say "$(msg uninst_removed "${CONF} ${LOG_FILE}")"
  else
    say "$(msg uninst_kept "${CONF} ${LOG_FILE}")"
  fi
  say "$(t uninst_loop_note)"
  (( DRY_RUN )) && say "$(t dry_note)"
  return 0
}

# ------------------------------- self checks (CI) -----------------------------------------
selftest_strings() {  # both arrays must carry exactly the same keys
  local k rc=0
  for k in "${!MSG_EN[@]}"; do
    [[ -v MSG_AR[$k] ]] || { warn "missing in MSG_AR: ${k}"; rc=1; }
  done
  for k in "${!MSG_AR[@]}"; do
    [[ -v MSG_EN[$k] ]] || { warn "missing in MSG_EN: ${k}"; rc=1; }
  done
  # the lookup path itself, in both languages (a wrong array name would pass the key test)
  [[ $(t_in en lang_title) == "Language" ]] || { warn "t() cannot resolve MSG_EN"; rc=1; }
  [[ $(t_in ar lang_title) == "اللغة" ]]    || { warn "t() cannot resolve MSG_AR"; rc=1; }
  [[ $(msg step 3 x) == "[3/9] x" ]] || { warn "msg() substitution broken"; rc=1; }
  (( rc == 0 )) && say "strings: ${#MSG_EN[@]} keys, both languages complete, lookup OK"
  return "$rc"
}

# ------------------------------- arguments -----------------------------------------
usage() {
  cat <<EOF
install.sh ${WIZARD_VERSION} — AWACS setup wizard / معالج إعداد AWACS

  sudo ./install.sh [options]          install or update (interactive when no --yes)
  sudo ./install.sh --uninstall        remove service + binary, keep settings and log
  sudo ./install.sh --uninstall --purge   ... and remove /etc/awacs.conf and the log too

Options / الخيارات:
  --lang en|ar             wizard language / لغة المعالج
  --device-id ID           device id, [A-Za-z0-9_-]{1,32} / معرّف الجهاز
  --log local|both|remote  log target / وجهة اللوق (both and remote need --site)
  --site URL               reporting site base URL / عنوان الموقع
  --probe URL              upload-speed probe target / عنوان فحص سرعة الرفع
  --report-wifi auto|yes|no  publish the WiFi cell to the site / نشر خانة الواي فاي
  --tz ZONE                time zone of the site log stamps, e.g. Europe/Berlin / المنطقة الزمنية لسطور الموقع
  --safety 'SSID=password' emergency network, repeatable / شبكة طوارئ (تتكرر)
  --no-safety              skip the emergency-network step / تجاوز خطوة شبكات الطوارئ
  --service systemd|rc.local  boot method / طريقة الإقلاع
  --release-url URL        where awacs.sh and SHA256SUMS are downloaded from (curl|bash path)
  --yes                    no questions: defaults plus the options above / بلا أسئلة
  --dry-run                print every action, change nothing / عرض الخطوات دون تنفيذ
  --help                   this text / هذا النص

Files / الملفات: ${BIN_DST}  ${CONF}  ${UNIT}  ${RC_LOCAL}  ${LOG_FILE}
EOF
}
parse_args() {
  local a v
  while (( $# )); do
    a=$1
    case $a in
      --*=*) v=${a#*=}; a=${a%%=*}; set -- "$a" "$v" "${@:2}" ;;
    esac
    case $a in
      --lang|--device-id|--log|--site|--probe|--report-wifi|--tz|--safety|--service|--release-url)
        [[ $# -ge 2 ]] || die "missing value for ${a}" ;;
    esac
    case $a in
      --lang)        UI_LANG=$2; shift 2 ;;
      --device-id)   DEVICE_ID=$2; shift 2 ;;
      --log)         LOG_TARGET=$2; shift 2 ;;
      --site)        SITE_URL=${2%/}; shift 2 ;;
      --probe)       PROBE_URL=$2; shift 2 ;;
      --report-wifi) REPORT_WIFI=$2; shift 2 ;;
      --tz)          SITE_TZ=$2; shift 2 ;;
      --safety)
        v=$2
        [[ $v == *=* ]] || die "--safety needs SSID=password"
        valid_ssid "${v%%=*}" || die "$(t safety_bad_ssid)"
        valid_psk "${v#*=}"   || die "$(t safety_bad_pass)"
        add_safety "${v%%=*}" "${v#*=}"
        shift 2 ;;
      --no-safety)   SKIP_SAFETY=1; shift ;;
      --service)     SERVICE=$2; [[ $SERVICE == rclocal ]] && SERVICE="rc.local"; shift 2 ;;
      --release-url) RELEASE_BASE_URL=${2%/}; shift 2 ;;
      --yes|-y)      ASSUME_YES=1; shift ;;
      --dry-run)     DRY_RUN=1; shift ;;
      --uninstall)   MODE="uninstall"; shift ;;
      --purge)       PURGE=1; shift ;;
      --selftest)    UI_LANG=${UI_LANG:-en}; if selftest_strings; then exit 0; else exit 1; fi ;;
      --print-unit)  unit_text; exit 0 ;;
      --help|-h)     usage; exit 0 ;;
      *)             usage >&2; die "unknown option: ${a}" ;;
    esac
  done
  [[ -z $UI_LANG || $UI_LANG == en || $UI_LANG == ar ]] || die "--lang must be en or ar"
  [[ -z $LOG_TARGET || $LOG_TARGET =~ ^(local|both|remote)$ ]] || die "--log must be local, both or remote"
  [[ -z $SERVICE || $SERVICE =~ ^(systemd|rc\.local)$ ]] || die "--service must be systemd or rc.local"
  [[ -z $REPORT_WIFI || $REPORT_WIFI =~ ^(auto|yes|no)$ ]] || die "--report-wifi must be auto, yes or no"
  if [[ -n $DEVICE_ID ]] && ! valid_device_id "$DEVICE_ID"; then die "$(msg devid_bad "$DEVICE_ID")"; fi
  if [[ -n $SITE_URL ]] && ! valid_url "$SITE_URL"; then die "$(t site_bad)"; fi
  if [[ -n $PROBE_URL ]] && ! valid_url "$PROBE_URL"; then die "$(t probe_bad)"; fi
  if [[ -n $SITE_TZ ]] && ! valid_tz "$SITE_TZ"; then die "$(t tz_bad)"; fi
  # --log both/remote without --site: decided in step_log_target, after an existing conf
  # (whose SITE_URL is the default of a re-run) has been read.
}
ensure_root() {
  (( EUID == 0 )) && return 0
  if (( DRY_RUN )); then
    warn "(dry run as a normal user: detection is limited, nothing is written)"
    return 0
  fi
  if [[ -r $0 && $0 != bash && $0 != -bash && $0 != sh && $0 != -sh ]]; then
    command -v sudo >/dev/null 2>&1 || die "$(t need_root_nosudo) / $(t_in ar need_root_nosudo)"
    say "$(t need_root) / $(t_in ar need_root)"
    exec sudo bash "$0" "$@"
  fi
  die "$(t need_root_pipe)"$'\n'"$(t_in ar need_root_pipe)"
}
step_language() {  # the one screen shown before a language exists carries both
  if [[ -z $UI_LANG ]]; then
    UI_LANG=en
    UI_LANG=$(ui_menu "Language / اللغة" "Choose the wizard language / اختر لغة المعالج" en \
                en "English" ar "العربية")
  fi
  step 1 lang_title
  say "$(t lang_chosen)"
}

main() {
  parse_args "$@"
  if [[ -r $0 && $0 != bash && $0 != -bash && $0 != sh && $0 != -sh ]]; then
    SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
  fi
  find_tty
  ensure_root "$@"
  if [[ -z $TTY ]] && (( ! ASSUME_YES )); then
    die "$(t need_tty)"$'\n'"$(t_in ar need_tty)"
  fi
  step_language
  say ""
  say "AWACS install.sh ${WIZARD_VERSION}"
  detect_os
  detect_backend
  show_detection
  if [[ $MODE == uninstall ]]; then
    do_uninstall
    return 0
  fi
  step_tools
  step_device_id
  step_log_target
  step_safety_net
  step_write_conf
  step_service
  step_binary
  step_check
  step_summary
}

main "$@"
