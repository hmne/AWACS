#!/usr/bin/env bash
#
# awacs.sh — AWACS 1.0 (Advanced WiFi Auto Connection System)
# Successor to aasw.sh v7.9.1 — TOTAL feature parity by owner decree ("لا تتهاون بأي ميزة"):
# every aasw capability lives here, kept, improved, or replaced by a documented superior;
# the only two divergences are constitutional (no reboot for ISP outages, no routine
# download tests). Auto-install of missing tools EXISTS (owner decree 2026-09-06) —
# rebuilt correctly: right package names, background, once per boot, no exec-restart.
# Mission: FIGHT for internet until connected. Network choice follows MEASURED UPLOAD
#   speed (the camera uploads; download is irrelevant) — never signal strength alone.
# Role: SD-resident daemon (/usr/local/bin), launched from rc.local BEFORE the camera
#   stack — it must work with no internet, so it is never fetched from the site.
# Platform: DUAL-STACK (owner decree 2026-09-06). Legacy Pi OS (dhcpcd +
#   wpa_supplicant) = the wpa backend, byte-for-byte the proven pillar. NetworkManager
#   images (Bookworm default) = the nm backend: AWACS SUPERVISES NM — it observes,
#   defers to NM's own autonomy, and intervenes cooperatively (nmcli only) after NM
#   provably fails. Monitor-only remains solely for unmanaged/broken-nmcli images.
# IDs: wpa numeric network ids on legacy; profile UUIDs on nm. Matching: raw escaped
#   text on wpa; LOWERCASE HEX BYTES on nm — Arabic/emoji/symbol SSIDs all survive.
# Known limitations (wpa backend ONLY — the nm hex path has none of these): OPEN
#   networks with non-ASCII names are skipped (the supplicant's quoted parser cannot
#   take iw's escaped form); and KNOWN names containing a literal backslash,
#   double-quote, TAB/LF/CR/ESC or edge space never match visibility — every sane
#   name works.
#
# rc.local contract (ORDER MATTERS — after the DEVICE_ID export; REPLACES aasw.sh:
# delete the old aasw.sh line AND /usr/local/bin/aasw.sh, two WiFi authorities fight):
#   export DEVICE_ID="cam1"
#   ( while :; do /usr/local/bin/awacs.sh; sleep 10; done ) >/dev/null 2>&1 &
#
# Manual toolbox (runs BESIDE the daemon, read-only except `speed`):
#   awacs.sh status | networks | evaluate | scan | speed | check | help
# Compat flags (old aasw launch lines keep working): -d self-daemonizes, -q is a no-op
# (logging is file-only by design), -h prints help.
#-------------------------------------------------------------------------------
set -uo pipefail
IFS=$'\n\t'
umask 077   # every runtime file (log/cache/spool/pid/probe) lands root-only — SSID lists are location data

# ------------------------------- configuration --------------------------------
# DEFAULTS ONLY — the owner's isolated settings file /etc/awacs.conf (PLAIN bash
# assignments ONLY, e.g. MIN_UP_KBPS=250 or SAFETY_NET["MyPhone"]="pass" — a
# readonly/declare line there is unsupported and would void the typo safety-net)
# OVERRIDES any of them, then everything is sealed readonly. One file to tune.
VERSION="1.0"
TICK=10              # main-loop cadence: cheap checks only (1 ping, no downloads)
NET_FAIL_TICKS=3     # ticks without internet before the fight starts (~30s)
ASSOC_WAIT=25        # seconds to wait for association + DHCP after a connect
PROBE_KB=200         # UPLOAD probe size — DECISION moments only, sent to OUR site
MIN_UP_KBPS=400      # DAY upload floor; sustained slower-while-active = look around
UP_STRIKES=3         # low-upload strikes before considering a switch (hysteresis)
SWITCH_GAIN_PCT=150  # DAY: challenger must beat the incumbent by >=150% (never-break law)
DANCE_COOLDOWN=1200  # DAY seconds between comparison dances — a dance disrupts, ration it
PREF_CHECK=600       # preferred-network look every 10min (zero traffic: one cache read)
REBOOT_AFTER_MIN=30  # ME-problem persisting this long -> reboot; a SURVIVING wedge
                     # earns another after the next full streak (~40min apart, never tight)
OPEN_NETWORKS="yes"  # last-resort passwordless networks — delete the word yes to disable
# --- Reporting site (public edition, 2026-09-13): all optional. Empty SITE_URL = the
# daemon works LOCAL-ONLY (log file only, no probes, network choice by signal).
SITE_URL=""          # base URL of the reporting site; AWACS talks to $SITE_URL/$DEVICE_ID/device_api.php
LOG_TARGET="local"   # local | both | remote — both/remote need SITE_URL; remote keeps only WARN/ERROR locally
PROBE_URL=""         # upload-speed probe target (any URL accepting a POST body); default = the site's device_api
REPORT_WIFI="auto"   # publish the Wi-Fi cell (kbps,visible,total,band,SSID) to the site: auto | yes | no
SITE_TZ=""           # time zone stamped on SITE log lines (e.g. Asia/Kuwait); empty = the device's own zone
# Emergency networks WITH passwords (aasw's SAFETY_NET, now real): tried after known
# networks fail, BEFORE open strangers. Populate in /etc/awacs.conf, NOT here —
# passwords are plain text and this script file gets shared/uploaded (OPSEC).
declare -A SAFETY_NET=(
  # ["MyPhoneHotspot"]="password"   # example — real entries belong in /etc/awacs.conf
)
# Night profile (aasw's night mode in the upload-kbps world): tolerate slower links,
# switch far more reluctantly, stay stable while everyone sleeps. TICK stays 10s —
# the loop is already night-cheap (aasw throttled its HEAVY 5s checks; ours are 1 ping).
NIGHT_MODE="yes"
NIGHT_START="22:00"
NIGHT_END="06:00"
NIGHT_MIN_UP_KBPS=200
NIGHT_GAIN_PCT=300
NIGHT_DANCE_COOLDOWN=2400
STEALTH_MODE="no"    # hide from casual LAN discovery (INPUT-chain icmp drop + no avahi);
                     # FIXES aasw's OUTPUT-chain bug that broke its own probes
DEBUG="${AWACS_DEBUG:-yes}" # decision-trace lines in the LOCAL log (aasw logged its
                            # reasoning ALWAYS — parity default; conf/env can silence)
LOG_FILE=/var/log/awacs.log
LOG_CAP=1500         # rotation keeps this many lines
# State lives in a PRIVATE root-owned dir, not bare /tmp: in shared /tmp (and /var/lock)
# any local user could pre-create/squat these names and root would write through them —
# /run/awacs (0700, root) closes squatting AND the lock-squat availability hole.
# (The five files under it are DERIVED after the conf is sourced, so a conf that
# moves RUN_DIR moves everything with it — a half-applied override once left the
# lock at the default path and the daemon silently never started.)
RUN_DIR=/run/awacs
SCAN_TTL=30          # scans hit the radio (off-channel) — cache and throttle them
SPOOL_CAP=60         # outage-story depth (aasw kept 500; 60 covers a long fight's tail)
STREAM_MIN_KBPS=50   # live-stream STARVING floor: below this the stream itself is the
                     # (free) meter saying the link suffers — evaluation becomes allowed

# --- الع­زل: the owner's settings file. Sourced as ROOT, so it must BE root's:
# refuse a conf not owned by us or writable by group/others (a loose conf = a backdoor).
AWACS_CONF="${AWACS_CONF:-/etc/awacs.conf}"
# EUID gate: the rootless fast lanes (check/help) run on DEFAULTS by design — and
# [[ -O ]] tests the RUNNER's uid, so without this gate a rootless run would falsely
# accuse a correctly root-owned conf ("chown root: it") in every cron mail.
if [[ -f $AWACS_CONF ]] && (( EUID == 0 )); then
  if [[ -O $AWACS_CONF ]]; then
    _cp=$(stat -c '%a' "$AWACS_CONF" 2>/dev/null || echo 777)
    # 066 mask: no WRITE and no READ for group/others — the conf carries hotspot
    # PASSWORDS, so a world-readable 644 is as much a leak as a writable one.
    if (( (8#$_cp & 8#066) == 0 )); then
      # shellcheck source=/dev/null
      source "$AWACS_CONF"
    else
      printf 'awacs: IGNORING %s (group/world can access it — chmod 600 it)\n' "$AWACS_CONF" >&2
    fi
    unset _cp
  else
    # Refusal must never be SILENT — a wrong-owner conf (restored from a backup as
    # pi) would otherwise just... stop applying, with the owner none the wiser.
    printf 'awacs: IGNORING %s (not owned by root — chown root: it)\n' "$AWACS_CONF" >&2
  fi
fi
# A hand-edited conf can hold typos; a bad NUMBER inside (( )) would crash the daemon
# into a silent respawn loop — validate every numeric knob, fall back to sane defaults.
for _kv in TICK=10 NET_FAIL_TICKS=3 ASSOC_WAIT=25 PROBE_KB=200 MIN_UP_KBPS=400 \
           UP_STRIKES=3 SWITCH_GAIN_PCT=150 DANCE_COOLDOWN=1200 PREF_CHECK=600 \
           REBOOT_AFTER_MIN=30 NIGHT_MIN_UP_KBPS=200 NIGHT_GAIN_PCT=300 \
           NIGHT_DANCE_COOLDOWN=2400 LOG_CAP=1500 SPOOL_CAP=60 SCAN_TTL=30 \
           STREAM_MIN_KBPS=50; do
  _k=${_kv%%=*}
  # :- guard: a conf that UNSETS a knob must fall back, not die unbound pre-logging.
  # 10# normalize: 08/09 pass the digits regex but are octal-illegal at every bare
  # (( )) site — proven to silently disable the fight; store the decimal value.
  # NONZERO, max 7 significant digits: every legitimate knob fits; 0 is nonsense
  # for ALL of them (TICK=0 hot-spins the loop, SPOOL_CAP=0 breaks the head-pin
  # math) and a 19-digit typo would 64-bit-wrap into a NEGATIVE sleep (hot-spin)
  # or an eternal one (alive-but-asleep silent wedge).
  if [[ ${!_k:-} =~ ^0*[1-9][0-9]{0,6}$ ]]; then printf -v "$_k" '%d' "$(( 10#${!_k} ))"
  else eval "$_kv"; fi
done
unset _kv _k
# The two clock knobs are HH:MM strings — a malformed one would crash apply_profile's
# base-10 arithmetic every tick; validate the shape, fall back to the defaults.
[[ ${NIGHT_START:-} =~ ^([01]?[0-9]|2[0-3]):[0-5][0-9]$ ]] || NIGHT_START="22:00"
[[ ${NIGHT_END:-}   =~ ^([01]?[0-9]|2[0-3]):[0-5][0-9]$ ]] || NIGHT_END="06:00"
# Reporting knobs: enums fall back, URLs must be plain http(s) (they land in curl argv),
# a remote target without a site is downgraded to local — and SAID once in the log.
case ${LOG_TARGET:-} in local|both|remote) ;; *) LOG_TARGET=local ;; esac
case ${REPORT_WIFI:-} in auto|yes|no) ;; *) REPORT_WIFI=auto ;; esac
[[ ${SITE_URL:-}  =~ ^https?://[^[:space:]/]+(/[^[:space:]]*)?$ ]] || SITE_URL=""
[[ ${PROBE_URL:-} =~ ^https?://[^[:space:]]+$ ]] || PROBE_URL=""
[[ ${SITE_TZ:-}   =~ ^[A-Za-z0-9/_+-]{0,64}$ ]] || SITE_TZ=""
LT_DOWNGRADED=0
[[ -n $SITE_URL || $LOG_TARGET == local ]] || { LOG_TARGET=local; LT_DOWNGRADED=1; }
# Derived AFTER the conf so a RUN_DIR override carries all five files with it.
[[ ${RUN_DIR:-} == /* ]] || RUN_DIR=/run/awacs   # relative/empty override = nonsense
LOCK=$RUN_DIR/lock          # flock authority; also stores the daemon PID (display-only)
SCAN_CACHE=$RUN_DIR/scan
SCAN_EMPTY=$RUN_DIR/scan.empty  # consecutive fresh scans that heard NOTHING (deaf-radio tell)
SCAN_DEAF=3                     # that many in a row = the stale picture is dropped (not a knob)
SPOOL=$RUN_DIR/spool        # site-log lines the outage swallowed; drained after proven health
OPEN_ID_FILE=$RUN_DIR/open_id  # crash-proof crutch marker: a respawn reaps its predecessor's
PROBE_FILE=$RUN_DIR/probe      # wget fallback needs a real file to POST
readonly VERSION TICK NET_FAIL_TICKS ASSOC_WAIT PROBE_KB MIN_UP_KBPS UP_STRIKES \
         SWITCH_GAIN_PCT DANCE_COOLDOWN PREF_CHECK REBOOT_AFTER_MIN OPEN_NETWORKS \
         NIGHT_MODE NIGHT_START NIGHT_END NIGHT_MIN_UP_KBPS NIGHT_GAIN_PCT \
         NIGHT_DANCE_COOLDOWN STEALTH_MODE DEBUG LOG_FILE LOG_CAP RUN_DIR LOCK \
         SCAN_CACHE SCAN_EMPTY SCAN_DEAF SCAN_TTL SPOOL SPOOL_CAP OPEN_ID_FILE PROBE_FILE SAFETY_NET \
         STREAM_MIN_KBPS SITE_URL LOG_TARGET PROBE_URL REPORT_WIFI SITE_TZ

# Day/night mutables (apply_profile switches them; consumers read only CUR_*)
CUR_MIN_UP=$MIN_UP_KBPS
CUR_GAIN=$SWITCH_GAIN_PCT
CUR_COOLDOWN=$DANCE_COOLDOWN
PROFILE=""

# ------------------------------- identity -------------------------------------
require_root() {
  (( EUID == 0 )) && return 0
  # aasw's hand-calibrated terminal box — transplanted VERBATIM by script (owner
  # decree: the spacing is tuned for real Arabic+emoji terminal rendering; NEVER retouch).
    echo
    echo -e "\033[1;37m┌─────────────────────────────────────────────┐\033[0m"
    echo -e "\033[1;37m│\033[1;41m ROOT ACCESS REQUIRED | مطلوب صلاحيات الجذر  \033[0;37m│\033[0m"
    echo -e "\033[1;37m├─────────────────────────────────────────────┤\033[0m"
    echo -e "\033[1;37m│ \033[1;33m⚠️  EN: \033[0mThis script needs root privileges   \033[1;37m │\033[0m"
    echo -e "\033[1;37m│ \033[1;33m⚠️  AR: \033[0mيجب تشغيل هذا السكربت بصلاحيات الجذر \033[1;37m│\033[0m"
    echo -e "\033[1;37m├─────────────────────────────────────────────┤\033[0m"
    echo -e "\033[1;37m│ \033[1;32m✓  \033[0mRun: \033[1;36msudo bash $0\033[1;37m    │\033[0m"
    echo -e "\033[1;37m└─────────────────────────────────────────────┘\033[0m"
    echo
  exit 1
}
device_id() {  # resolved LAZILY: /tmp/device_id is written by start.sh AFTER we launch.
  # grep -m1 . (the camera's own idiom): an empty or blank-first-line file falls
  # through to cam1. VALIDATED before use: the file lives in world-writable /tmp and
  # its bytes land in a root terminal and an outbound URL — only a plain slug passes.
  local d
  d="${DEVICE_ID:-$(grep -m1 . /tmp/device_id 2>/dev/null)}"
  [[ $d =~ ^[A-Za-z0-9_-]{1,32}$ ]] || d=$(hostname -s 2>/dev/null)
  [[ $d =~ ^[A-Za-z0-9_-]{1,32}$ ]] || d=device
  echo "$d"
}
site()      { echo "${SITE_URL%/}/$(device_id)"; }   # meaningful only when SITE_URL is set
remote_on() { [[ -n $SITE_URL && $LOG_TARGET != local ]]; }   # story lines + Wi-Fi cell go to the site
probe_url() {  # where upload probes POST to; empty = no measurement possible (signal mode)
  if [[ -n $PROBE_URL ]]; then echo "$PROBE_URL"
  elif [[ -n $SITE_URL ]]; then echo "$(site)/device_api.php"; fi
}
probe_on()  { [[ -n $PROBE_URL || -n $SITE_URL ]]; }
# SIGNAL MODE (probe_on false): the measured-upload law has nothing to measure with, so
# the daemon is a connectivity supervisor only — fight when the internet is lost (the
# strongest visible known network that delivers wins), go home when home is visible;
# no QA strikes, no dance, no "too slow" veto. The story lines say so instead of "0 kbps".
up_words()    { if probe_on; then echo "upload $1 kbps"; else echo "signal mode"; fi; }
up_words_ar() { if probe_on; then echo "رفع $1 كيلوبت/ث"; else echo "وضع الإشارة"; fi; }
stamp()     { if [[ -n $SITE_TZ ]]; then TZ=$SITE_TZ date "$@"; else date "$@"; fi; }

detect_if() {  # aasw's best-interface ladder: connected > up > present; env AWACS_IF overrides
  local best="" state=0 i s
  for i in $(iw dev 2>/dev/null | awk '$1 == "Interface" { print $2 }'); do
    s=0
    ip link show "$i" 2>/dev/null | grep -q ' UP' && s=1
    (( s == 1 )) && iw dev "$i" link 2>/dev/null | grep -q '^Connected' && s=2
    (( s == 2 )) && { best=$i; break; }   # never steal an associated radio — it wins outright
    (( s > state )) && { best=$i; state=$s; }
    [[ -z $best ]] && best=$i
  done
  [[ -n $best ]] && iw dev "$best" info >/dev/null 2>&1 || best=wlan0
  printf '%s' "$best"
}

# ------------------------------- logging --------------------------------------
log() {  # LEVEL MSG — local file, rotated; never blocks on the network
  printf '[%s][%s] %s\n' "$1" "$(date '+%d/%m %H:%M:%S')" "$2" >>"$LOG_FILE" 2>/dev/null || :
  local n; n=$(wc -l <"$LOG_FILE" 2>/dev/null || echo 0)
  if (( n > LOG_CAP + 200 )); then
    tail -n "$LOG_CAP" "$LOG_FILE" >"${LOG_FILE}.t" 2>/dev/null && mv -f "${LOG_FILE}.t" "$LOG_FILE"
  fi
}
dbg() { [[ $DEBUG == yes ]] && log DEBUG "$1"; return 0; }  # return 0: a false && must never trip callers

net_up=0  # last verdict; connect_id/fight set it the moment internet is verified
site_log() {  # LEVEL EN_MSG [AR_MSG] — the v3 site log, Arabic surface when provided
  # (aasw's bilingual split: local log stays English/technical, the owner's dashboard
  # reads Arabic). A failed live send self-spools; offline lines spool directly — the
  # outage's own story reaches the site after recovery, in order, nothing lost.
  # LOG_TARGET=remote: the local file keeps only the alarming levels (WARN/ERROR)
  if [[ $LOG_TARGET != remote || $1 == WARN || $1 == ERROR ]]; then log "$1" "$2"; fi
  remote_on || return 0   # local-only deployment: the story stays in the local log
  local line
  line="[$1] AWACS: ${3:-$2}, $(stamp '+%d/%m/%Y %I:%M:%S %p')."
  if (( net_up )); then
    # Group-level >/dev/null: the async child must not inherit a caller's command-
    # substitution pipe, or $(scan) waits up to 4s for this sender to exit (proven).
    { curl -sf --max-time 4 --data-urlencode "file=log/log.txt" \
        --data-urlencode "data=$line" "$(site)/device_api.php" \
      || printf '%s\n' "$line" >>"$SPOOL"; } >/dev/null 2>&1 9>&- &
  else
    printf '%s\n' "$line" >>"$SPOOL" 2>/dev/null || :
    local _n; _n=$(wc -l <"$SPOOL" 2>/dev/null || echo 0)
    if (( _n > SPOOL_CAP )); then
      # PIN line 1: the outage's opening banner carries the "when it began" stamp —
      # a capped story keeps its head AND its newest tail (middle chatter is what
      # rolls off). head+tail can never duplicate: tail starts at line 3 or later.
      { head -n 1 "$SPOOL"; tail -n $(( SPOOL_CAP - 1 )) "$SPOOL"; } >"${SPOOL}.t" 2>/dev/null \
        && mv -f "${SPOOL}.t" "$SPOOL"
    fi
  fi
}

flush_spool() {  # deliver the outage story in order, duplicate-proof: SNAPSHOT via
  # atomic mv (async appenders start a fresh spool untouched), count what was sent,
  # merge only the UNSENT remainder back IN FRONT of new lines, capped. Honest limit:
  # an append landing in the final merge instant can be lost — one log line, accepted;
  # a lock here would let a hung flush block the fight, and reachability outranks logs.
  remote_on || return 0
  [[ -s $SPOOL ]] || return 0
  mv -f "$SPOOL" "${SPOOL}.sending" 2>/dev/null || return 0
  local l sent=0
  while IFS= read -r l; do
    if curl -sf --max-time 4 --data-urlencode "file=log/log.txt" \
         --data-urlencode "data=$l" "$(site)/device_api.php" >/dev/null 2>&1; then
      (( ++sent ))
    else
      break
    fi
  done <"${SPOOL}.sending"
  { tail -n +$(( sent + 1 )) "${SPOOL}.sending" 2>/dev/null; cat "$SPOOL" 2>/dev/null; } >"${SPOOL}.t" || :
  if [[ -s ${SPOOL}.t ]]; then
    local n; n=$(wc -l <"${SPOOL}.t" 2>/dev/null || echo 0)
    if (( n > SPOOL_CAP )); then  # same head-pin as site_log's cap: keep the opening line
      { head -n 1 "${SPOOL}.t"; tail -n $(( SPOOL_CAP - 1 )) "${SPOOL}.t"; } >"$SPOOL" 2>/dev/null || :
    else
      cat "${SPOOL}.t" >"$SPOOL" 2>/dev/null || :
    fi
  fi
  rm -f "${SPOOL}.sending" "${SPOOL}.t"
}

MISSING_TOOLS=""
APT_TRIED=0
check_tools() {  # inventory only — the INSTALL attempt is install_tools(), which the
  # main loop fires once per boot at the first PROVEN-healthy moment (apt needs net).
  local t missing="" tools
  local IFS=' '   # the lists below are SPACE-separated; the global IFS=\n\t would
                  # hand the loop ONE giant token (proven: every boot false-alarmed
                  # "missing tools" and the installer never saw a real tool name)
  # Backend-aware inventory: the nm image needs nmcli, not wpa_cli (and vice versa).
  if [[ $BACKEND != wpa ]]; then
    tools="iw nmcli ip ping curl awk sed grep pgrep rfkill flock timeout stat date modprobe"
  else
    tools="iw wpa_cli ip ping curl awk sed grep pgrep rfkill flock timeout stat date modprobe"
  fi
  for t in $tools; do
    command -v "$t" >/dev/null 2>&1 || missing+="$t "
  done
  MISSING_TOOLS=$missing
  [[ -n $missing ]] && site_log ERROR "missing tools: ${missing}- will try to install once online" \
                                      "أدوات ناقصة بالنظام: ${missing}- سيتم تنزيلها تلقائياً عند توفر النت"
  return 0
}

install_tools() {  # OWNER DECREE 2026-09-06 (reverses the old report-only stance for
  # AWACS's OWN tools): ONE bounded apt attempt per boot, in the BACKGROUND (the
  # fight never waits on apt), with the CORRECT package names — the old aasw used
  # tool names as package names and its exec-restart suicided on its own lock;
  # neither mistake exists here (tools appear in PATH the moment apt finishes).
  [[ -n $MISSING_TOOLS && ! -e $RUN_DIR/apt_tried ]] || return 0
  (( APT_TRIED )) && return 0   # in-process belt: once-per-boot holds even if the
  APT_TRIED=1                   # marker write below ever fails
  { : >"$RUN_DIR/apt_tried"; } 2>/dev/null || :   # suppressor installed FIRST
  command -v apt-get >/dev/null 2>&1 \
    || { site_log WARN "no apt-get on this system - install manually: ${MISSING_TOOLS}" \
                       "لا يوجد apt-get - تحتاج تثبيت يدوي: ${MISSING_TOOLS}"; return 0; }
  local t pkgs=()
  local IFS=' '   # MISSING_TOOLS is space-separated (same trap as check_tools)
  for t in $MISSING_TOOLS; do
    case $t in                       # tool -> Debian package (NOT always the same word)
      wpa_cli)           pkgs+=(wpasupplicant) ;;
      nmcli)             pkgs+=(network-manager) ;;
      ip)                pkgs+=(iproute2) ;;
      ping)              pkgs+=(iputils-ping) ;;
      awk)               pkgs+=(mawk) ;;
      pgrep)             pkgs+=(procps) ;;
      flock)             pkgs+=(util-linux) ;;
      timeout|stat|date) pkgs+=(coreutils) ;;
      modprobe)          pkgs+=(kmod) ;;
      *)                 pkgs+=("$t") ;;
    esac
  done
  site_log INFO "installing missing tools: ${pkgs[*]}" \
                "جاري تنزيل الأدوات الناقصة تلقائياً: ${pkgs[*]}"
  # nmcli missing while NetworkManager itself is present = a CORRUPTED package: a
  # plain install is a no-op ("already newest") — force --reinstall in that case.
  local -a aptflags=(install -y)
  [[ " $MISSING_TOOLS " == *" nmcli "* ]] && aptflags=(install -y --reinstall)
  local missing_snapshot=$MISSING_TOOLS still=""
  { DEBIAN_FRONTEND=noninteractive timeout 600 apt-get "${aptflags[@]}" "${pkgs[@]}" >/dev/null 2>&1 || :
    # Success is judged by the TOOLS appearing, never by apt's exit code (an
    # already-installed package exits 0 while the binary is still absent).
    IFS=' '   # (subshell copy — the function's space IFS, restated for the reader)
    for t in $missing_snapshot; do command -v "$t" >/dev/null 2>&1 || still+="$t "; done
    if [[ -z $still ]]; then
      site_log OK "tools installed: ${pkgs[*]}" "اكتمل تنزيل الأدوات الناقصة"
    else
      site_log ERROR "tool install failed - still missing: ${still}- install manually" \
                     "فشل تنزيل الأدوات - ما زالت ناقصة: ${still}- تحتاج تثبيت يدوي"
    fi; } 9>&- &
}

# ------------------------------- probes ----------------------------------------
wpa() { wpa_cli -i "$IF" "$@" 2>/dev/null; }

assoc_ssid() {  # current SSID via iw (iwgetid is extinct on new images) — display only
  iw dev "$IF" link 2>/dev/null | sed -n 's/^[[:space:]]*SSID: //p' | head -1
}
pssid() {  # DISPLAY form of any escaped SSID: %b decodes iw's \xNN so Arabic names
  # read as Arabic — then every CONTROL byte is stripped, because a neighbor can name
  # an AP with \x1b escape codes and %b would inject them into the root terminal/log.
  # NEVER used for matching — display only.
  printf '%b' "$1" | tr -d '\000-\037\177'
}
dssid() { pssid "$(assoc_ssid)"; }

have_net() {  # cheap ladder, ANY rung passing = online; TWO http rungs, both exact:
  # gstatic must answer 204, our device_api must answer 400. Known accepted blind
  # spot: ping-alive-but-DNS-dead reads ONLINE (aasw's ladder had the same
  # short-circuit) — the camera's own watchdog owns that story.
  ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 && return 0
  ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 && return 0
  # portal's 302/200 splash must read as OFFLINE or the fight ends on fake victory.
  [[ $(curl -s -o /dev/null -w '%{http_code}' --max-time 3 \
       "http://connectivitycheck.gstatic.com/generate_204" 2>/dev/null) == "204" ]] && return 0
  # Last rung — OUR OWN API answering its SIGNATURE reply: device_api.php returns
  # 400 "no operation" by contract, a code no captive-portal splash fabricates
  # (portals answer 200/302/511). This rescues the ICMP-eaten/204-mangled carrier
  # network WITHOUT the false victory a bare any-status probe would hand a portal.
  [[ -n $SITE_URL ]] || return 1   # no site configured = this rung does not exist
  [[ $(curl -s -o /dev/null -w '%{http_code}' --max-time 3 \
       --data-urlencode "probe=1" "$(site)/device_api.php" 2>/dev/null) == "400" ]]
}

gw_ok() {  # gateway answers = the LINK is fine, the outage is upstream (ISP) — never reboot for that
  local gw; gw=$(ip -4 route show default dev "$IF" 2>/dev/null | awk '{print $3; exit}')
  [[ -n $gw ]] && ping -c 1 -W 2 "$gw" >/dev/null 2>&1
}

wpa_auth_failing() {  # wrong password ≠ wedge: the supplicant marks such networks TEMP-DISABLED.
  wpa list_networks | grep -q 'TEMP-DISABLED'
}

up_kbps() {  # REAL UPLOAD speed to OUR OWN site — decision moments only. Target is
  # device_api.php (tiny error reply), not a page: response time would deflate the number.
  # No ||-clobber: on --max-time expiry curl still prints the honest partial average.
  [[ -n ${AWACS_TEST_KBPS:-} ]] && { printf '%d' "$AWACS_TEST_KBPS"; return 0; }
  local bps="" target; target=$(probe_url)
  [[ -n $target ]] || { printf '0'; return 0; }   # nothing to upload to = no measurement
  if command -v curl >/dev/null 2>&1; then
    bps=$(head -c $((PROBE_KB * 1024)) /dev/zero \
          | curl -s -o /dev/null -w '%{speed_upload}' --max-time 15 --data-binary @- \
            "$target" 2>/dev/null)
  fi
  if [[ -z ${bps:-} || $bps == 0 || $bps == "0.000" ]]; then
    command -v wget >/dev/null 2>&1 && { up_kbps_wget "$target"; return 0; }
  fi
  printf '%d' "$(awk -v b="${bps:-0}" 'BEGIN { printf "%d", b * 8 / 1000 }')"
}

up_kbps_wget() {  # measurement must survive one dead tool (aasw's method fallback)
  local t0 t1 dt rc
  head -c $((PROBE_KB * 1024)) /dev/zero >"$PROBE_FILE" 2>/dev/null || { printf '0'; return 0; }
  t0=$(date +%s%N)
  timeout 20 wget -q -O /dev/null -T 15 --post-file="$PROBE_FILE" "$1" 2>/dev/null
  rc=$?
  t1=$(date +%s%N)
  rm -f "$PROBE_FILE"
  # wget exit 8 = the server ANSWERED 4xx/5xx after the upload — our device_api replies
  # 400 'no operation' by design, so 8 is success-of-transport. Anything else (4=network,
  # 124=timeout, ...) means the bytes never traveled: a fast failure must read as an
  # honest 0, never as a lightning-fast upload (proven 1638-16000 kbps phantom).
  (( rc != 0 && rc != 8 )) && { printf '0'; return 0; }
  dt=$(( t1 - t0 ))
  (( dt <= 0 )) && { printf '0'; return 0; }
  printf '%d' $(( PROBE_KB * 1024 * 8 * 1000000 / dt ))  # bits * 1e6 / ns = kbps
}

tx_kbps() {  # passive upload meter from kernel counters — zero traffic, 3s sample
  [[ -n ${AWACS_TEST_KBPS:-} ]] && { printf '%d' "$AWACS_TEST_KBPS"; return 0; }
  local a b f=/sys/class/net/$IF/statistics/tx_bytes
  a=$(cat "$f" 2>/dev/null || echo 0); sleep 3; b=$(cat "$f" 2>/dev/null || echo 0)
  printf '%d' $(( (b - a) * 8 / 3000 ))
}

streaming() {  # REAL TRAFFIC is its own upload meter — never probe or dance under it.
  # Four moments covered: the web stream (live_raw), the tunnel preview (preview.jpg),
  # the capture SHOOT itself (capture.jpg — the 1-3s shot-to-upload gap was a proven
  # collision window), and an in-flight CAPTURE UPLOAD (site_upload's curl upfile=@).
  pgrep -f 'raspistill.*(live_raw|preview\.jpg|capture\.jpg)' >/dev/null 2>&1 && return 0
  pgrep -f 'curl.*upfile=@' >/dev/null 2>&1
}

LAST_KBPS=0     # the incumbent's last ACTIVE upload measurement (decision moments only)
LAST_KBPS_ID="" # ...and WHICH network it belongs to — the site cell must never pair one
                # network's number with another's name (proven on veto/crutch paths)
note_kbps() { LAST_KBPS=$1; LAST_KBPS_ID=$(current_id); }
report_wifi() {  # tmp/wifi.tmp -> the site's WiFi cell, riding the BATTERY pattern:
  # fresh file = cell shows, stale/absent = cell vanishes — a device without AWACS
  # renders the page unchanged (the owner's modularity law). PASSIVE by design:
  # the known/visible counts ride the existing scan CACHE — zero radio traffic.
  case $REPORT_WIFI in no) return 0 ;; auto) remote_on || return 0 ;; esac
  [[ -n $SITE_URL ]] || return 0   # "yes" without a site has nowhere to publish
  local tot=0 vis=0 id ssid cache s seen=$'\n' vseen=$'\n'
  if [[ $BACKEND != wpa ]]; then
    cache=$(nm_wifi_list no | cut -f1)   # --rescan no: NM's own cache, zero radio
  else
    cache=$(cat "$SCAN_CACHE" 2>/dev/null)
  fi
  # counts are per PROFILE (uuid), not per key row: an ambiguous 0x profile emits two
  # key rows on nm and must count once in "total" and at most once in "visible"
  while IFS=$'\t' read -r id ssid; do
    [[ -z $id ]] && continue
    [[ $seen == *$'\n'"$id"$'\n'* ]] || { seen+="$id"$'\n'; (( ++tot )); }
    if [[ -n $cache && $vseen != *$'\n'"$id"$'\n'* ]]; then
      if [[ $BACKEND != wpa ]]; then
        grep -qFx -- "$ssid" <<<"$cache" && { vseen+="$id"$'\n'; (( ++vis )); }
      else
        W="$ssid" awk -F'\t' '$1 == ENVIRON["W"] { f = 1; exit } END { exit !f }' <<<"$cache" \
          && { vseen+="$id"$'\n'; (( ++vis )); }
      fi
    fi
  done < <(known_ids)
  s=$(dssid)
  # Band from the live association (iw works under BOTH backends): 6GHz first
  # (future dongles), then 5GHz, then the 2.4 the Zero 2W actually has.
  local freq band=""
  freq=$(iw dev "$IF" link 2>/dev/null | sed -n 's/^[[:space:]]*freq: //p' | head -1)
  freq=${freq%%.*}
  if [[ $freq =~ ^[0-9]+$ ]]; then
    if   (( freq >= 5925 )); then band="6GHz"
    elif (( freq >= 4900 )); then band="5GHz"
    elif (( freq >= 2400 && freq <= 2500 )); then band="2.4GHz"
    fi
  fi
  # The number is sent ONLY if it was measured on the network we are on now; a
  # network change without a fresh measurement shows the name with no speed
  # rather than another network's speed.
  local k=$LAST_KBPS
  [[ -n $LAST_KBPS_ID && $(current_id) == "$LAST_KBPS_ID" ]] || k=0
  # Format: kbps,visible,total,band,SSID — SSID LAST so its own commas survive (the
  # site splits with a 5-field limit). Sent via the existing device_api channel.
  curl -sf --max-time 4 --data-urlencode "file=tmp/wifi.tmp" \
    --data-urlencode "data=${k},${vis},${tot},${band},${s:--}" \
    "$(site)/device_api.php" >/dev/null 2>&1 || :
}

# ------------------------------- radio -----------------------------------------
scan() {  # cached radio scan: "<escaped-ssid>\t<signal>\t<open|sec>" per line.
  # [[:space:]] (never \s): stock Pi OS awk is mawk, where \s silently matches nothing.
  [[ -n ${AWACS_TEST_SCAN:-} ]] && { cat "$SCAN_CACHE" 2>/dev/null; return 0; }
  local now; now=$(date +%s)
  # -e, not -s: an EMPTY fresh cache is a real answer (a radio that hears nothing) —
  # it is served for SCAN_TTL like any other, never re-asked by every caller in turn.
  if [[ -e $SCAN_CACHE ]] && (( now - $(stat -c%Y "$SCAN_CACHE" 2>/dev/null || echo 0) < SCAN_TTL )); then
    cat "$SCAN_CACHE"; return 0
  fi
  local out="" i tries=3 alt
  # Boot patience (aasw's field lesson): the radio answers scans slowly in the first
  # minutes of uptime — an empty early scan must not be mistaken for empty air.
  (( $(cut -d. -f1 /proc/uptime 2>/dev/null || echo 999) < 180 )) && tries=6
  for (( i = 0; i < tries; i++ )); do  # EBUSY is normal while associated — retry, never spin
    if out=$(timeout 15 iw dev "$IF" scan 2>&1) && [[ -n $out ]]; then break; fi
    # -16 "Device or resource busy" = the supplicant/NM is scanning RIGHT NOW (the real
    # lab: 77 of 107 daemon scans, both backends) — its own table will hold the answer
    # in a moment (scan_backend below); one wait, then read it instead of fighting for
    # the radio three times over.
    [[ $out == *busy* ]] && { out=""; sleep 3; break; }
    out=""; sleep 3
  done
  dbg "scan: $(( i < tries ? i + 1 : tries ))/${tries} tries used"
  if [[ -z ${out:-} ]]; then
    # Tool-level fallbacks: iwlist (aasw's path: some drivers only answer it), then
    # the BACKEND'S OWN scan table — the source iw was busy protecting.
    alt=$(scan_iwlist)
    [[ -n $alt ]] || alt=$(scan_backend)
    if [[ -n $alt ]]; then
      rm -f "$SCAN_EMPTY"
      printf '%s\n' "$alt" | sort -t$'\t' -k2,2gr >"$SCAN_CACHE"
      cat "$SCAN_CACHE"; return 0
    fi
    # Every source came back empty after every retry. ONCE is a hiccup: stale results
    # beat no results (aasw told the same story), and the cache's mtime is refreshed so
    # a silent radio is asked again once per SCAN_TTL — not once per caller. SCAN_DEAF
    # times IN A ROW is no hiccup, it is the picture: a radio that hears NOTHING. The
    # stale cache is dropped then, so fight()'s "radio sees NOTHING" tell and every
    # visible-known reader see the truth — real lab, nm arm: a deaf radio hid behind a
    # 37-minute-old cache, the fight called it external and the valve never armed.
    local empties; empties=$(cat "$SCAN_EMPTY" 2>/dev/null)
    [[ $empties =~ ^[0-9]{1,6}$ ]] || empties=0
    empties=$(( empties + 1 ))
    printf '%d\n' "$empties" >"$SCAN_EMPTY"
    if (( empties >= SCAN_DEAF )); then
      if [[ -s $SCAN_CACHE ]]; then   # said once, at the moment the picture is dropped
        if [[ -n ${AWACS_CLI:-} ]]; then
          log WARN "radio heard nothing on ${empties} scans in a row - previous results dropped"
        else
          site_log WARN "radio heard nothing on ${empties} scans in a row - previous results dropped" \
                        "الراديو لم يسمع أي شبكة في ${empties} مسوحات متتالية - أُسقطت النتائج السابقة"
        fi
      fi
      : >"$SCAN_CACHE"   # empty AND fresh: "nothing" is the answer for the next SCAN_TTL
      return 0
    fi
    # Toolbox runs stay local-only: a hand-run scan is not the daemon's story.
    if [[ -n ${AWACS_CLI:-} ]]; then
      log WARN "scan failed - using previous results (if any)"
    else
      site_log WARN "scan failed - using previous results (if any)" \
                    "فشل مسح الشبكات - نستخدم نتائج سابقة إن وجدت"
    fi
    touch "$SCAN_CACHE" 2>/dev/null || :   # throttle the retry, keep the stale picture
    [[ -s $SCAN_CACHE ]] && cat "$SCAN_CACHE"
    return 0
  fi
  rm -f "$SCAN_EMPTY"   # the radio heard SOMETHING (named or hidden) — the silence streak ends
  # Privacy/RSN/WPA absent => truly OPEN. Length cap 128: iw escapes each non-ASCII
  # byte to \xNN (4 chars), so a legal 32-octet Arabic SSID needs up to 128 chars.
  local parsed
  parsed=$(awk '
    /^BSS /                { if (ssid != "") emit(); sec = 0; sig = "-100"; ssid = "" }
    /capability:.*Privacy/ { sec = 1 }
    /^[[:space:]]*RSN:/ || /^[[:space:]]*WPA:/ { sec = 1 }
    /^[[:space:]]*signal:/ { sig = $2 }
    /^[[:space:]]*SSID: /  { ssid = substr($0, index($0, "SSID: ") + 6) }
    function emit()        { if (length(ssid) > 0 && length(ssid) <= 128)
                               printf "%s\t%s\t%s\n", ssid, sig, (sec ? "sec" : "open") }
    END                    { if (ssid != "") emit() }
  ' <<<"$out" | sort -t$'\t' -k2,2gr)
  # A scan that SUCCEEDED but named nothing (all-hidden air) must not truncate the
  # cache: the wipe made fight()'s "radio sees NOTHING" tell fire beside beaconing
  # BSSes (false ME evidence). Keep the previous picture — the TTL bounds its age.
  if [[ -n $parsed ]]; then
    printf '%s\n' "$parsed" >"$SCAN_CACHE"
    cat "$SCAN_CACHE"
  else
    [[ -s $SCAN_CACHE ]] && cat "$SCAN_CACHE"
  fi
  return 0
}

scan_iwlist() {  # emits the SAME TSV as scan()'s parser; mawk-safe throughout.
  # Signal rule demands a MINUS: the relative form "Signal level=65/100" must fall
  # through to the Quality rule's -70 estimate, not masquerade as +65 dBm (proven
  # regression vs aasw). Final tr: iwlist prints ESSIDs RAW (no \xNN escaping like
  # iw), so control bytes are stripped here — tab and newline survive (TSV framing).
  command -v iwlist >/dev/null 2>&1 || return 0
  timeout 15 iwlist "$IF" scan 2>/dev/null | awk '
    /Cell [0-9]+ - Address:/ { if (ssid != "") emit(); ssid = ""; sig = "-100"; sec = 0 }
    /ESSID:/ {
      q1 = index($0, "\"")
      if (q1) { rest = substr($0, q1 + 1); q2 = index(rest, "\""); if (q2) ssid = substr(rest, 1, q2 - 1) }
    }
    /Signal level=-[0-9]+/ { n = $0; sub(/.*Signal level=/, "", n); sub(/[^0-9-].*/, "", n); if (n != "") sig = n }
    /Quality=[0-9]+\/[0-9]+/ { if (sig == "-100") sig = "-70" }
    /Encryption key:on/ { sec = 1 }
    function emit() { if (length(ssid) > 0 && length(ssid) <= 128)
                        printf "%s\t%s\t%s\n", ssid, sig, (sec ? "sec" : "open") }
    END { if (ssid != "") emit() }' | tr -d '\000-\010\013-\037\177'
}

scan_backend() {  # emits scan()'s TSV from the backend's OWN table (wpa scan_results /
  # NM's list). iw refuses with EBUSY exactly when the supplicant or NM is mid-scan —
  # the disconnected moments AWACS scans most — and that table IS the fresh picture.
  if [[ $BACKEND != wpa ]]; then
    local hex sig sec
    while IFS=$'\t' read -r hex sig sec; do
      [[ -n $hex ]] || continue
      [[ $sig =~ ^[0-9]+$ ]] || sig=0
      # NM reports PERCENT; its own mapping is percent = 2 * (dBm + 100) — invert it so
      # the column stays dBm like iw's; the name goes back to iw's \xNN-escaped text.
      printf '%s\t%s\t%s\n' "$(hex2iw "$hex")" "$(( sig / 2 - 100 ))" "$sec"
    done < <(nm_wifi_list no)
  else
    # scan_results: "bssid\tfreq\tsignal\tflags\tssid" after ONE header line; the
    # supplicant escapes SSIDs the way iw does (\xNN, \\), signal is dBm on nl80211.
    wpa scan_results | tail -n +2 | awk -F'\t' '
      NF >= 5 && length($5) > 0 && length($5) <= 128 {
        printf "%s\t%s\t%s\n", $5, ($3 ~ /^-?[0-9]+$/ ? $3 : "-100"),
               ($4 ~ /WPA|RSN|WEP/ ? "sec" : "open") }'
  fi | sort -t$'\t' -k2,2gr
}

hex2iw() {  # lowercase hex -> iw's escaped text: printable ASCII kept, the rest \xNN
  local h=$1 out="" i b c
  for (( i = 0; i < ${#h}; i += 2 )); do
    b=$(( 16#${h:i:2} ))
    if (( b >= 32 && b <= 126 && b != 92 )); then printf -v c '%b' "\\x${h:i:2}"; out+=$c
    else out+="\\x${h:i:2}"; fi
  done
  printf '%s' "$out"
}

wpa_known_ids() {  # "<id>\t<ssid>"; -i output has ONE header line (aasw dropped id 0)
  wpa list_networks | tail -n +2 | awk -F'\t' 'NF >= 2 { printf "%s\t%s\n", $1, $2 }'
}

wpa_visible_known_ids() {  # stored networks currently on the air (EXACT raw-text match).
  # ENVIRON, never awk -v: -v escape-decodes the \xNN text both tools print for
  # non-ASCII SSIDs, which made every Arabic network invisible (proven).
  local s; s=$(scan) || :
  while IFS=$'\t' read -r id ssid; do
    W="$ssid" awk -F'\t' '$1 == ENVIRON["W"] { f = 1; exit } END { exit !f }' <<<"$s" \
      && printf '%s\t%s\n' "$id" "$ssid"
  done < <(wpa_known_ids)
}

wpa_arm_hidden() {  # hidden SSIDs answer only directed probes: scan_ssid 1 on every known
  # network, runtime-only (never save_config). Re-run after any supplicant restart.
  local id _
  while IFS=$'\t' read -r id _; do
    wpa set_network "$id" scan_ssid 1 >/dev/null || :
  done < <(wpa_known_ids)
}

# ═══════════════════════ NM BACKEND (NetworkManager images) ═══════════════════════
# Doctrine (NM-SPEC.md): on NM images AWACS is a SUPERVISOR over NetworkManager's own
# autonomy — it observes, waits, and only after NM has provably failed does it issue
# cooperative nmcli overrides and boot-only /run crutches. All SSID matching on NM is
# LOWERCASE HEX (locale/escape/colon-proof — Arabic and emoji become first-class).
NM_ERR=""; NM_RC=0; NM_AUTH=0   # per-fight activation evidence (auth latch is STICKY per fight)
NM_L3_SPENT=0                    # this streak already tried L3's NetworkManager restart
NM_RC8=0                         # sticky per streak: nmcli itself unreachable (exit 8)
NM_SAW_BUSY=0                    # a connecting-band sample was seen since the last check
NM_SETTLED_SEEN=0                # consecutive settled (30/120) classifications
NM_LAME_REASON=""                # nocli | "" (unmanaged) — decides whether the park may exit
# Documented limit (owner-visible truth): NM device state 20 "unavailable" (e.g. a
# halted radio firmware) never arms the reboot valve on the nm arm — on wpa the
# empty-scan tell would. Deliberate for now: 20 also covers plain rfkill/no-radio
# states where a reboot cures nothing; revisit only with real-device evidence.

text2hex() {  # VERBATIM text -> lowercase hex (never %b: a literal \x41 stays 4 chars)
  printf %s "$1" | od -An -tx1 | tr -d ' \n'
}
iw2hex() {    # iw's \xNN-escaped text -> the same hex space
  printf %b "$1" | od -An -tx1 | tr -d ' \n'
}
hex2bytes() { # hex -> ";"-separated DECIMAL bytes for the keyfile ssid= byte-array
  local h=$1 out="" i
  for (( i = 0; i < ${#h}; i += 2 )); do
    out+="$(( 16#${h:i:2} ));"
  done
  printf '%s' "$out"
}

nm_dev_state() {  # leading integer of GENERAL.STATE (0 when unreadable)
  local st; st=$(nmcli -g GENERAL.STATE device show "$IF" 2>/dev/null)
  st=${st%% *}
  if [[ $st =~ ^[0-9]+$ ]]; then printf '%s' "$st"; else printf '0'; fi
}

nm_note_state() {  # every state READ feeds the streak's evidence — called in the MAIN
  # shell (a $(...) subshell could never persist these flags): a connecting-band
  # sample marks NM as still working; any readable state proves nmcli reachable.
  local st=$1
  if (( (st >= 40 && st <= 90) || st == 110 )); then NM_SAW_BUSY=1; fi
  if (( st != 0 )); then NM_RC8=0; fi
}

nm_me_settled() {  # may ME evidence arm (and the valve fire) on NM? Only when NM has
  # GIVEN UP (30 disconnected / 120 failed) on TWO consecutive classifications with
  # no busy sighting between them — a single point-sample proved to arm the clock
  # beside a still-cycling NM (proven reboot of a box NM was actively retrying).
  # Anti-strand widening: state UNREADABLE with nmcli itself exiting 8 — probed
  # HERE, so a DEAD service counts even though no candidate ever reaches
  # be_activate (proven unreachable otherwise) — plus L3's NM restart already
  # spent = a hosed NM, a genuine ME wedge whose one remaining cure is the reboot.
  local st rc; st=$(nm_dev_state); nm_note_state "$st"
  if (( st == 0 )); then
    nmcli -t -f UUID,TYPE connection show >/dev/null 2>&1; rc=$?
    (( rc == 8 )) && NM_RC8=1
    if (( NM_L3_SPENT && NM_RC8 )); then return 0; fi
    return 1
  fi
  if (( st == 30 || st == 120 )); then
    if (( ++NM_SETTLED_SEEN >= 2 )); then return 0; fi
    return 1
  fi
  # Readable and NOT given-up (connected/connecting/unmanaged...): the converse of the
  # arming rule — the clock may only stay armed while this function is true, so a
  # good read RESTARTS the evidence (a stale stamp once fired after NM died again).
  NM_SETTLED_SEEN=0; ME_SINCE=0
  return 1
}

nm_busy() {  # NM actively working the device (connecting band 40-90, or 110)
  local st; st=$(nm_dev_state); nm_note_state "$st"
  (( (st >= 40 && st <= 90) || st == 110 ))
}

# shellcheck disable=SC2120  # the bound is an optional override; callers take the default
nm_wait_settled() {  # bounded wait until NM is out of its transition band — never a new
  # polling loop: called ONLY at intervention moments inside existing call sites.
  local i st
  for (( i = 0; i < ${1:-$ASSOC_WAIT}; i++ )); do
    st=$(nm_dev_state); nm_note_state "$st"
    case $st in 10|20|30|100|120) return 0 ;; esac
    sleep 1
  done
  return 0
}

nm_profile_hexssid() {  # saved profile's SSID as lowercase hex (0x form or UTF-8 text)
  # -e no: terse mode otherwise ESCAPES ':' and '\' inside values ("Cafe\:Net"),
  # which would mis-key every colon/backslash SSID (proven class).
  local s; s=$(nmcli -e no -g 802-11-wireless.ssid connection show uuid "$1" 2>/dev/null)
  # nmcli prints the 0x byte form ONLY for names that are not valid UTF-8 — so a
  # 0x string whose bytes DO decode as UTF-8 cannot be that form: it is a network
  # literally named "0xCAFE" (proven mis-keyed before). Disambiguate by decoding.
  # Prints ONE key per line — TWO in the one genuinely ambiguous case: a 0x string
  # whose bytes are NOT valid UTF-8 could be nmcli's byte form OR a network
  # literally named "0xCAFE"; both keys are emitted and the air picks the real one.
  local h esc="" i
  if [[ $s =~ ^0x([0-9a-fA-F]{2})+$ ]]; then
    h=${s#0x}
    for (( i = 0; i < ${#h}; i += 2 )); do esc+="\\x${h:i:2}"; done   # deterministic \xNN
    if ! printf '%b' "$esc" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1; then
      printf '%s\n' "$h" | tr 'A-F' 'a-f'   # byte-form reading
    fi
  fi
  text2hex "$s"; echo                         # literal-text reading (always)
}

nm_known_ids() {  # "UUID\tHEXSSID" of saved wifi profiles (1.42 prints TYPE alias
  # "wifi"; older spells it out — accept both). UUID/TYPE are colon-free by format.
  local uuid type
  while IFS=: read -r uuid type; do
    [[ $type == wifi || $type == 802-11-wireless ]] || continue
    local k
    while IFS= read -r k; do   # one row per key (two only in the 0x-ambiguous case)
      [[ -n $k ]] && printf '%s\t%s\n' "$uuid" "$k"
    done <<<"$(nm_profile_hexssid "$uuid")"
  done < <(nmcli -t -f UUID,TYPE connection show 2>/dev/null)
}

nm_wifi_list() {  # "HEXSSID\tSIGNAL%\topen|sec" per AP; $1=--rescan mode (auto|no).
  # SSID-HEX/SIGNAL/SECURITY are colon-free by format; hex LOWERCASED at the producer
  # (nmcli's case is not contractual — one uppercase would blank every intersection).
  local hex sig sec seen=$'\n'
  while IFS=: read -r hex sig sec; do
    [[ -n $hex ]] || continue                      # hidden AP with no directed answer
    hex=$(printf '%s' "$hex" | tr 'A-F' 'a-f')
    [[ $seen == *$'\n'"$hex"$'\n'* ]] && continue  # dual-band dedupe
    seen+="$hex"$'\n'
    printf '%s\t%s\t%s\n' "$hex" "${sig:-0}" "$([[ -z $sec ]] && echo open || echo sec)"
  done < <(nmcli -t -f SSID-HEX,SIGNAL,SECURITY device wifi list ifname "$IF" \
           --rescan "${1:-auto}" 2>/dev/null)
}

nm_visible_known_ids() {  # known ∩ air, by exact hex equality — ONE row per UUID
  # (an ambiguous 0x profile carries two keys; if both readings are on the air the
  # profile must still be ONE candidate, never two con-ups — R10 finding)
  local list uuid hex seen=$'\n'
  list=$(nm_wifi_list auto | cut -f1)
  while IFS=$'\t' read -r uuid hex; do
    [[ -n $hex ]] || continue
    [[ $seen == *$'\n'"$uuid"$'\n'* ]] && continue
    grep -qFx -- "$hex" <<<"$list" && { seen+="$uuid"$'\n'; printf '%s\t%s\n' "$uuid" "$hex"; }
  done < <(nm_known_ids)
}

nm_auth_sig() {  # does this activation stderr smell like credentials (not a wedge)?
  printf %s "$1" | grep -qiE 'secret|no-secrets|authenticat|802-1X|key.mgmt|pre-shared'
}

nm_del_own() {  # THE ONLY delete/down site on the NM arm — double-guarded, fail-SAFE.
  local name row file
  name=$(nmcli -e no -g connection.id connection show uuid "$1" 2>/dev/null) || name=""
  [[ -n $name ]] || { dbg "del_own: $1 already gone"; return 0; }
  # FILENAME from the LISTING (1.42 has no connection.filename detail property).
  # UUID (colon-free) leads, so a first-colon split is exact; the tail stays escaped
  # but is only PREFIX-tested and our prefix carries no ':' or '\'.
  row=$(nmcli -t -f UUID,FILENAME connection show 2>/dev/null \
        | U="$1" awk -F: '$1 == ENVIRON["U"] { print; exit }')
  file=${row#*:}
  [[ $name =~ ^awacs-(crutch|safety)-[0-9]+-[0-9]+$ ]] || {
    log ERROR "REFUSING delete: '$name' is not an awacs crutch"; return 1; }
  [[ $file == /run/NetworkManager/system-connections/awacs-* ]] || {
    log ERROR "REFUSING delete: '$name' lives outside /run (owner file?)"; return 1; }
  nmcli connection down uuid "$1" >/dev/null 2>&1 || :
  nmcli connection delete uuid "$1" >/dev/null 2>&1 || :
}

nm_add_crutch() {  # $1=hexssid $2=psk-or-empty $3=hidden(yes/no) -> prints UUID.
  # NEVER `nmcli device wifi connect` (it PERSISTS an autoconnect profile in /etc —
  # the accumulation trap the NO-BLOCK law bans). One /run keyfile, boot-only.
  local hex=$1 psk=$2 hidden=$3 uuid name path
  uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null) || return 1
  if [[ -n $psk ]]; then name="awacs-safety-$(date +%s)-$$"
  else name="awacs-crutch-$(date +%s)-$$"; fi
  path="/run/NetworkManager/system-connections/${name}.nmconnection"
  install -d -m 700 /run/NetworkManager/system-connections 2>/dev/null || :
  {
    printf '[connection]\nid=%s\nuuid=%s\ntype=wifi\nautoconnect=false\n' "$name" "$uuid"
    printf '[wifi]\nmode=infrastructure\nhidden=%s\nssid=%s\n' \
           "$([[ $hidden == yes ]] && echo true || echo false)" "$(hex2bytes "$hex")"
    if [[ -n $psk ]]; then
      # keyfile escaping: literal backslash -> \\, and a LEADING space -> \s
      # (GKeyFile strips unescaped leading whitespace = silent wrong-password).
      psk=${psk//\\/\\\\}
      [[ $psk == ' '* ]] && psk="\\s${psk# }"
      printf '[wifi-security]\nkey-mgmt=wpa-psk\npsk=%s\n' "$psk"
    fi
    printf '[ipv4]\nmethod=auto\n[ipv6]\nmethod=auto\n'
  } >"$path" 2>/dev/null || return 1
  chmod 600 "$path" 2>/dev/null || :   # NM REFUSES loose keyfiles — correctness gate
  nmcli connection load "$path" >/dev/null 2>&1 || { rm -f "$path"; return 1; }
  printf '%s' "$uuid"
}

nm_reap() {  # startup belt-and-suspenders: marker, name-prefix sweep, /run glob
  local uuid name
  if [[ -s $OPEN_ID_FILE ]]; then
    nm_del_own "$(head -1 "$OPEN_ID_FILE")" || :
    rm -f "$OPEN_ID_FILE"
  fi
  while IFS=: read -r uuid name; do
    if [[ $name == awacs-* ]]; then nm_del_own "$uuid" || :; fi
  done < <(nmcli -t -f UUID,NAME connection show 2>/dev/null)
  rm -f /run/NetworkManager/system-connections/awacs-*.nmconnection 2>/dev/null || :
  nmcli connection reload >/dev/null 2>&1 || :
}

nm_recover() {  # NM-side ladder: cooperative only — NEVER ip link down/up on a managed
  # device (double-authority loop, proven), never dhcpcd.
  case "$1" in
    1) site_log WARN "recover L1: radio bounce" "إنعاش م1: نطفي الواي فاي ونشغله"
       # Bounce OUR interface's own killswitch, never the whole WLAN type: `nmcli radio
       # wifi off` soft-blocks EVERY wireless radio on the box (a second dongle — or, in
       # the lab, the very access points we needed: proven, 32 of 32 activations then
       # died with ssid-not-found). nmcli's switch stays as the fallback for drivers
       # that expose no rfkill node. Either way NM still resets its autoconnect blocks.
       local rf=""
       for rf in /sys/class/net/"$IF"/phy80211/rfkill*; do break; done   # first match (glob, no ls)
       rf=${rf##*/}   # "rfkill0"; the unmatched literal "rfkill*" fails the regex below
       if [[ $rf =~ ^rfkill([0-9]+)$ ]] && command -v rfkill >/dev/null 2>&1; then
         rfkill block   "${BASH_REMATCH[1]}" 2>/dev/null || :; sleep 2
         rfkill unblock "${BASH_REMATCH[1]}" 2>/dev/null || :
       else
         nmcli radio wifi off 2>/dev/null || :; sleep 2
         nmcli radio wifi on  2>/dev/null || :
       fi
       nm_wait_settled 15 ;;
    2) site_log WARN "recover L2: re-kick NetworkManager on ${IF}" "إنعاش م2: نعيد ضبط الاتصال"
       nmcli device reapply "$IF" >/dev/null 2>&1 || :
       sleep 3
       if ! have_net; then
         # disconnect latches a device-level no-autoconnect until a manual connect —
         # the pair stays back-to-back; -w 5 keeps connect from blocking ~90s (NM
         # keeps activating after nmcli returns; wait_ip/have_net observe). A crash
         # inside the pair heals at the respawn's boot enable_all.
         nmcli device disconnect "$IF" >/dev/null 2>&1 || :
         sleep 1
         nmcli -w 5 device connect "$IF" >/dev/null 2>&1 || :
         sleep 8
       fi
       iw dev "$IF" set power_save off 2>/dev/null || : ;;
    3) site_log WARN "recover L3: restart NetworkManager + reload WiFi firmware" \
                     "إنعاش م3: نعيد تشغيل مدير الشبكة وتعريف الشريحة"
       NM_L3_SPENT=1
       systemctl restart NetworkManager 2>/dev/null || :
       sleep 8
       modprobe -r brcmfmac 2>/dev/null || :; sleep 2
       modprobe brcmfmac 2>/dev/null || :; sleep 8
       iw dev "$IF" set power_save off 2>/dev/null || :
       # Reap BELT: do NOT assume the restart wiped our /run keyfiles (not contractual;
       # tmpfs files outlive the service and NM re-reads the dir at startup).
       rm -f /run/NetworkManager/system-connections/awacs-*.nmconnection 2>/dev/null || :
       nmcli connection reload >/dev/null 2>&1 || :
       OPEN_ID=""; rm -f "$OPEN_ID_FILE" ;;
  esac
}

# ------------------------------ dispatchers -------------------------------------
# Existing public names become thin dispatchers; fight()/main() call ONLY these.
known_ids()         { if [[ $BACKEND != wpa ]]; then nm_known_ids; else wpa_known_ids; fi; }
visible_known_ids() { if [[ $BACKEND != wpa ]]; then nm_visible_known_ids; else wpa_visible_known_ids; fi; }
arm_hidden()        { if [[ $BACKEND != wpa ]]; then :; else wpa_arm_hidden; fi; }
# (nm: hidden probing is the SAVED per-profile property 802-11-wireless.hidden — the
# re-arm chore disappears. Owner caveat, documented: a hidden OWNER profile must carry
# hidden=yes already; AWACS may not write it in — iron law: never modify owner profiles.)
auth_failing()      { if [[ $BACKEND != wpa ]]; then (( NM_AUTH )); else wpa_auth_failing; fi; }
recover()           { if [[ $BACKEND != wpa ]]; then nm_recover "$1"; else wpa_recover "$1"; fi; }
del_own()           { if [[ $BACKEND != wpa ]]; then nm_del_own "$1"; else wpa remove_network "$1" >/dev/null || :; fi; }
current_id() {
  if [[ $BACKEND != wpa ]]; then nmcli -g GENERAL.CON-UUID device show "$IF" 2>/dev/null
  else wpa status | sed -n 's/^id=//p' | head -1; fi
}
get_priority() {
  if [[ $BACKEND != wpa ]]; then nmcli -g connection.autoconnect-priority connection show uuid "$1" 2>/dev/null
  else wpa get_network "$1" priority; fi
}
enable_all() {
  # wpa: re-enable all (select_network disabled the rest). nm: hand NM back its
  # autonomy with a bounded nudge — -w 5 is LOAD-BEARING (default wait ~90s and this
  # runs inside on_shutdown's trap); NEVER `connection modify ... autoconnect`.
  if [[ $BACKEND != wpa ]]; then
    local st; st=$(nm_dev_state)
    if (( st == 30 || st == 120 )); then
      nmcli -w 5 device connect "$IF" >/dev/null 2>&1 || :
    fi
  else
    wpa_enable_all
  fi
}
reassociate() {  # fight's gentle open: ask the base layer to try, tear nothing down
  if [[ $BACKEND != wpa ]]; then
    local st; st=$(nm_dev_state)
    if (( st == 30 || st == 120 )); then
      nmcli -w 5 device connect "$IF" >/dev/null 2>&1 || :
    fi
  else
    wpa reassociate >/dev/null || :
  fi
}
pref_prescan() {  # wpa: supplicant-side directed scan surfaces hidden home networks;
  # nm probes its hidden profiles itself and --rescan auto covers the rest.
  if [[ $BACKEND == wpa ]]; then wpa scan >/dev/null || :; sleep 4; fi
}
be_activate() {  # raw activation of ID $1 (association + DHCP proof)
  if [[ $BACKEND != wpa ]]; then
    nm_wait_settled   # never issue con up mid-transition (100 counts as settled)
    NM_ERR=$(nmcli -w "$ASSOC_WAIT" connection up uuid "$1" 2>&1 >/dev/null); NM_RC=$?
    if (( NM_RC == 8 )); then NM_RC8=1; else NM_RC8=0; fi
    if (( NM_RC == 3 || NM_RC == 4 )) && nm_auth_sig "$NM_ERR"; then
      NM_AUTH=1   # sticky for the whole fight: a later timeout on another candidate
    fi            # must not erase a credentials sighting (wpa's TEMP-DISABLED parity)
    (( NM_RC == 0 )) || return 1
    wait_ip || return 1   # belt: nmcli said up — confirm the lease/carrier like wpa does
  else
    wpa select_network "$1" >/dev/null
    wait_ip || return 1
  fi
}
disp_ssid() {  # OWNER-FACING name for ID $1 (wpa fallback text $2) — hex must never
  # reach a human surface; NM's UTF-8 property renders Arabic directly.
  if [[ $BACKEND != wpa ]]; then
    nmcli -e no -g 802-11-wireless.ssid connection show uuid "$1" 2>/dev/null | tr -d '\000-\037\177'
  else
    pssid "$2"
  fi
}
reap_crutches() {  # startup: predecessor's crutch must not survive the crash
  if [[ $BACKEND != wpa ]]; then
    nm_reap
  else
    if [[ -s $OPEN_ID_FILE ]]; then
      wpa remove_network "$(head -1 "$OPEN_ID_FILE")" >/dev/null 2>&1 || :
      rm -f "$OPEN_ID_FILE"
    fi
  fi
}

BACKEND=wpa
detect_backend() {  # decided once per daemon start; the rc.local respawn re-decides.
  # $1=fast: toolbox runs skip the boot-patience wait (read-only, harmless).
  BACKEND="wpa"
  # Enabled-or-active = this IS an NM image — wait for it, never fight beside it
  # (an early "wpa" verdict would put two authorities on one radio: proven disaster).
  if systemctl is-active --quiet NetworkManager 2>/dev/null \
     || systemctl is-enabled --quiet NetworkManager 2>/dev/null; then
    BACKEND="nm"
    if ! command -v nmcli >/dev/null 2>&1; then
      BACKEND="nm_lame"          # broken install: NM runs, its CLI is gone
      NM_LAME_REASON=nocli       # the park loop may EXIT once auto-install lands nmcli
    else
      local i st
      if [[ ${1:-} != fast ]]; then
        for (( i = 0; i < 12; i++ )); do   # up to ~60s boot patience, then decide
          systemctl is-active --quiet NetworkManager 2>/dev/null && break
          sleep 5
        done
      fi
      st=$(nm_dev_state)
      (( st == 10 )) && BACKEND="nm_lame"    # unmanaged: every con up/down is inert
    fi
  fi
  readonly BACKEND
}
# ═════════════════════════════ end NM backend ════════════════════════════════════

wait_ip() {  # association alone is not a connection — demand an IPv4 lease too
  local i
  for (( i = 0; i < ASSOC_WAIT; i++ )); do
    [[ -n $(ip -4 addr show dev "$IF" scope global 2>/dev/null) ]] \
      && iw dev "$IF" link 2>/dev/null | grep -q '^Connected' && return 0
    sleep 1
  done
  return 1
}

connect_id() {  # activate network ID $1 (wpa numeric id / nm profile UUID) — SHARED body,
  # same crediting doctrine on both backends.
  dbg "connect_id: activating $1 (backend $BACKEND)"
  be_activate "$1" || return 1
  LINK_OK=1   # association + DHCP succeeded this round — the LINK layer is provably fine
  have_net || return 1
  # Verified internet — site_log may speak from this moment on. ME_SINCE clears
  # HERE too: the tick path only credits health it SEES, and a crutch that lives
  # less than one tick left a stale wedge streak that later rebooted a box which
  # provably had working internet 97s earlier (proven). Credit the moment itself.
  net_up=1; ME_SINCE=0
}

wpa_enable_all() { wpa enable_network all >/dev/null || :; }
# select_network disables every other network in the LIVE supplicant. EVERY winning
# path below re-enables all (proven not to break the current association) so the
# supplicant keeps its autonomous fallback and a dead AWACS can never strand the box.
#
# THE NO-BLOCK LAW (owner decree 2026-09-06, born of a real disaster: the old aasw
# left FOUR known networks permanently disabled — banned at different offline
# moments, never unbanned, until only the hotspot and home router could connect):
#   1. This script NEVER writes wpa_supplicant.conf — zero save_config calls exist,
#      so no ban can ever reach the disk.
#   2. This script NEVER calls disable_network — the only network it removes is
#      its OWN temporary crutch (an id it created this boot).
#   3. enable_all runs at startup, at every fight start, after every win, on every
#      losing fight's exit, and at shutdown — so even the supplicant's own runtime
#      TEMP-DISABLED marks are lifted again and again. A permanent block is
#      structurally impossible here.

wpa_recover() {  # escalation ladder — each rung targets a DIFFERENT layer (aasw hit the wrong ones)
  case "$1" in
    1) site_log WARN "recover L1: radio bounce" "إنعاش م1: إعادة تشغيل الراديو"
       rfkill unblock wifi 2>/dev/null || :
       ip link set "$IF" down; sleep 2; ip link set "$IF" up; sleep 3 ;;
    2) site_log WARN "recover L2: restart dhcpcd (respawns the REAL per-interface supplicant)" \
                     "إنعاش م2: إعادة تشغيل مدير الشبكة"
       systemctl restart dhcpcd 2>/dev/null || systemctl restart wpa_supplicant 2>/dev/null || :
       sleep 8; arm_hidden
       iw dev "$IF" set power_save off 2>/dev/null || : ;;  # a fresh supplicant re-enables it
    3) site_log WARN "recover L3: reload brcmfmac firmware (the 3-second cure a wedge needs)" \
                     "إنعاش م3: إعادة تحميل تعريف شريحة الواي فاي"
       modprobe -r brcmfmac 2>/dev/null || :; sleep 2
       modprobe brcmfmac 2>/dev/null || :; sleep 8; arm_hidden
       iw dev "$IF" set power_save off 2>/dev/null || : ;;  # a rebuilt netdev re-enables it
  esac
}

# ------------------------------- crutches --------------------------------------
OPEN_ID=""  # temp network id currently parked in the live supplicant (crutch, not family)
mark_crutch() {  # crash-proof: a respawned daemon reaps its dead predecessor's crutch
  OPEN_ID="$1"
  printf '%s\n' "$1" >"$OPEN_ID_FILE" 2>/dev/null || :
}
drop_open() {
  [[ -n $OPEN_ID ]] && { del_own "$OPEN_ID" || :; OPEN_ID=""; }
  rm -f "$OPEN_ID_FILE"
}

try_safety() {  # aasw's SAFETY_NET made real: owner-listed emergency networks WITH
  # passwords, tried BEFORE open strangers. Attempted even when not visible in scan
  # (hotspots are often just-enabled or hidden; wait_ip bounds each try at 25s).
  (( ${#SAFETY_NET[@]} )) || return 1
  site_log INFO "trying emergency networks (${#SAFETY_NET[@]} listed)" \
                "نحاول شبكات الطوارئ"
  local ssid id ok psk
  for ssid in "${!SAFETY_NET[@]}"; do
    psk=${SAFETY_NET[$ssid]}
    if [[ $BACKEND != wpa ]]; then
      # Keyfile byte-arrays carry ANY name/psk byte (the wpa-era backslash/quote
      # skip disappears here); only psk length sanity gates (8-63, or 64 hex).
      if [[ -n $psk ]] \
         && ! { (( ${#psk} >= 8 && ${#psk} <= 63 )) || [[ $psk =~ ^[0-9a-fA-F]{64}$ ]]; }; then
        continue
      fi
      { id=$(nm_add_crutch "$(text2hex "$ssid")" "$psk" no) && [[ -n $id ]]; } || continue
      printf '%s\n' "$id" >"$OPEN_ID_FILE" 2>/dev/null || :   # pre-mark (crash window)
      if connect_id "$id"; then
        mark_crutch "$id"
        enable_all
        site_log OK "connected to EMERGENCY network: $ssid" \
                    "اتصل بشبكة الطوارئ: $(pssid "$ssid")"
        return 0
      fi
      del_own "$id" || :
      rm -f "$OPEN_ID_FILE"
      continue
    fi
    # Skip names/passwords the supplicant's quoted parser cannot carry (backslash
    # or a literal double-quote would malform the set_network line) — clean skip.
    [[ $ssid == *"\\"* || $ssid == *'"'* || ${SAFETY_NET[$ssid]} == *'"'* ]] && continue
    { id=$(wpa add_network) && [[ $id =~ ^[0-9]+$ ]]; } || continue
    # PRE-mark: a daemon killed inside the 25s attempt window must not orphan this id —
    # the respawn's startup sweep reaps whatever the marker names (nothing untracked parks).
    printf '%s\n' "$id" >"$OPEN_ID_FILE" 2>/dev/null || :
    # psk goes over STDIN, never argv: /proc/PID/cmdline is world-readable and a
    # set_network ... psk argument would flash the password to every local user.
    # An EMPTY value is a deliberately-listed OPEN hotspot -> key_mgmt NONE instead.
    ok=0
    if wpa set_network "$id" ssid "\"$ssid\"" | grep -q OK; then
      if [[ -n ${SAFETY_NET[$ssid]} ]]; then
        printf 'set_network %s psk "%s"\n' "$id" "${SAFETY_NET[$ssid]}" \
          | wpa_cli -i "$IF" 2>/dev/null | grep -q OK && ok=1
      else
        wpa set_network "$id" key_mgmt NONE | grep -q OK && ok=1
      fi
    fi
    if (( ok )) && connect_id "$id"; then
      mark_crutch "$id"
      enable_all
      site_log OK "connected to EMERGENCY network: $ssid" \
                  "اتصل بشبكة الطوارئ: $(pssid "$ssid")"
      return 0
    fi
    wpa remove_network "$id" >/dev/null || :
    rm -f "$OPEN_ID_FILE"   # attempt failed and the id is gone — clear the pre-mark
  done
  return 1
}

try_open() {  # last resort: truly-open APs, temp ID, never saved to disk.
  # Dedupe multi-BSS SSIDs (a dual-band AP is ONE attempt) and skip hopeless signals
  # (<-80dBm, open strangers only — KNOWN networks are always attempted, however weak).
  [[ $OPEN_NETWORKS == "yes" ]] || return 1
  site_log INFO "trying open networks as last resort" \
                "نحاول الشبكات المفتوحة كخيار أخير"
  local ssid sig sec id s seen=$'\n'
  if [[ $BACKEND != wpa ]]; then
    # nm candidates ride nmcli's list: SIGNAL is 0-100 PERCENT (never mix with dBm);
    # <25% ≈ the -80dBm stranger cutoff. Open Arabic/emoji names — skipped forever on
    # the wpa arm — become reachable here (hex + byte-array keyfile carry anything).
    local hex
    while IFS=$'\t' read -r hex sig sec; do
      [[ $sec == open ]] || continue
      [[ $sig =~ ^[0-9]+$ ]] && (( sig < 25 )) && continue
      { id=$(nm_add_crutch "$hex" "" no) && [[ -n $id ]]; } || continue
      printf '%s\n' "$id" >"$OPEN_ID_FILE" 2>/dev/null || :   # pre-mark (crash window)
      if connect_id "$id"; then
        mark_crutch "$id"
        enable_all
        site_log OK "connected to OPEN network: $(disp_ssid "$id" "")" \
                    "اتصل بشبكة مفتوحة: $(disp_ssid "$id" "")"
        return 0
      fi
      del_own "$id" || :
      rm -f "$OPEN_ID_FILE"
    done < <(nm_wifi_list auto)
    return 1
  fi
  while IFS=$'\t' read -r ssid sig sec; do
    [[ $sec == "open" ]] || continue
    [[ $ssid == *"\\"* ]] && continue  # escaped (non-ASCII) name — the supplicant cannot take it
    [[ $seen == *$'\n'"$ssid"$'\n'* ]] && continue
    seen+="$ssid"$'\n'
    s=${sig%%.*}
    # dBm is NEGATIVE by physics; a non-negative reading is driver garbage — treat it
    # as unknown (attempt anyway) rather than "excellent signal".
    [[ $s =~ ^-[0-9]+$ ]] && (( s < -80 )) && continue
    { id=$(wpa add_network) && [[ $id =~ ^[0-9]+$ ]]; } || continue
    printf '%s\n' "$id" >"$OPEN_ID_FILE" 2>/dev/null || :  # pre-mark (crash-proof attempt window)
    if wpa set_network "$id" ssid "\"$ssid\"" | grep -q OK \
       && wpa set_network "$id" key_mgmt NONE | grep -q OK \
       && connect_id "$id"; then
      mark_crutch "$id"
      enable_all  # the winning-path law: stored networks stay armed so the supplicant
                  # can carry us HOME by itself when a real network returns (proven trap)
      site_log OK "connected to OPEN network: $ssid" \
                  "اتصل بشبكة مفتوحة: $(pssid "$ssid")"
      return 0
    fi
    wpa remove_network "$id" >/dev/null || :
    rm -f "$OPEN_ID_FILE"   # attempt failed and the id is gone — clear the pre-mark
  done < <(scan)
  return 1
}

# ------------------------------- decisions -------------------------------------
best_by_upload() {  # the blueprint's heart: among working candidates, MEASURED upload decides.
  # $1 = kbps floor a challenger must beat (never-break law); $2 = incumbent id to go home to.
  # best starts at -1: a working-but-very-slow candidate still beats having nothing (proven
  # that 0-init rejected all sub-107kbps networks and parked the box arbitrarily).
  local floor="${1:-0}" home="${2:-}" best_id="" best_kbps=-1 id ssid kbps
  if ! probe_on; then
    # SIGNAL MODE (no probe target configured): measurement needs somewhere to upload
    # to; without it the strongest visible known network that DELIVERS internet wins.
    while IFS=$'\t' read -r id ssid; do
      [[ -n $home && $id == "$home" ]] && continue
      connect_id "$id" || continue
      enable_all
      site_log OK "connected: $(assoc_ssid) (signal mode - no upload probe target configured)" \
                  "اتصل بشبكة: $(dssid) (وضع الإشارة - لا هدف لقياس الرفع)"
      return 0
    done < <(visible_known_by_signal)
    [[ -n $home ]] && connect_id "$home" && { enable_all; return 0; }
    return 1
  fi
  while IFS=$'\t' read -r id ssid; do
    # The incumbent was measured moments ago (that number IS the floor) — probing
    # it again buys nothing and costs a redundant ~15s of churn.
    [[ -n $home && $id == "$home" ]] && continue
    connect_id "$id" || continue
    kbps=$(up_kbps)
    site_log INFO "candidate [$id] $(disp_ssid "$id" "$ssid") uploads at ${kbps} kbps" \
                  "مرشح $(disp_ssid "$id" "$ssid") يرفع بسرعة ${kbps} كيلوبت/ث"
    if (( kbps > best_kbps )); then best_id=$id; best_kbps=$kbps; fi
    (( kbps >= CUR_MIN_UP * 4 )) && break  # plainly fast — stop burning probe traffic
  done < <(visible_known_ids)
  # A 0-kbps challenger must never displace a live incumbent even when the floor
  # collapsed to 0 (site down while internet up) — hence the second clause.
  if [[ -n $home ]] && (( best_kbps < floor || best_kbps <= 0 )); then
    # Nobody beat the incumbent — go home, and SAY so: a dance that opens with
    # "evaluating networks" and ends in silence reads as a hang on the dashboard.
    connect_id "$home" && { enable_all
      site_log OK "no challenger beat the incumbent - staying on $(dssid)" \
                  "لم تتفوق أي شبكة - باقون على $(dssid)"
      return 0; }
  fi
  [[ -n $best_id ]] || return 1
  connect_id "$best_id" || return 1
  enable_all
  note_kbps "$best_kbps"   # the site cell must pair the NEW network with ITS number
  site_log OK "connected: $(assoc_ssid) (upload ${best_kbps} kbps)" \
              "اتصل بشبكة: $(dssid) (سرعة الرفع ${best_kbps} كيلوبت/ث)"
}

visible_known_by_signal() {  # visible_known_ids rows ordered strongest-air-first (signal mode)
  local vis sssid _sig _sec key kid kssid seen=$'\n'
  vis=$(visible_known_ids)
  [[ -n $vis ]] || return 0
  while IFS=$'\t' read -r sssid _sig _sec; do   # scan() is already sorted by signal
    [[ -n $sssid ]] || continue
    if [[ $BACKEND != wpa ]]; then key=$(iw2hex "$sssid"); else key=$sssid; fi
    while IFS=$'\t' read -r kid kssid; do
      [[ $kssid == "$key" ]] || continue
      [[ $seen == *$'\n'"$kid"$'\n'* ]] && continue   # dual-band AP = one candidate
      seen+="$kid"$'\n'
      printf '%s\t%s\n' "$kid" "$kssid"
    done <<<"$vis"
  done < <(scan)
}

best_pref_id() {  # visible known network with a wpa-conf priority STRICTLY above the
  # current one's; prints nothing when we already sit on the best (or have no data).
  # (Deliberate reduction vs aasw: no cross-boot last-SSID file — the supplicant's
  # SAVED PRIORITIES are the persistent memory; this check + enable_all carry us home.)
  # Visibility = iw scan UNION the supplicant's own scan_results (the latter sees
  # HIDDEN networks thanks to armed scan_ssid — same printf-encoded text, matches raw).
  local cur="$1" cur_p=0 best="" best_p id ssid p vis iwn suppn now nmvis=""
  now=$(date +%s)
  if [[ $BACKEND != wpa ]]; then
    # nm visibility = the hex intersection (NM's own directed probing already surfaces
    # a correctly-configured hidden home; priorities are SIGNED -999..999).
    nmvis=$(nm_visible_known_ids | cut -f1)
  else
    iwn=$(scan | cut -f1)
    suppn=$(wpa scan_results | tail -n +2 | awk -F'\t' 'NF >= 5 { print $5 }')
  fi
  if [[ -n $cur ]]; then
    cur_p=$(get_priority "$cur"); [[ $cur_p =~ ^-?[0-9]+$ ]] || cur_p=0
  fi
  best_p=$cur_p
  while IFS=$'\t' read -r id ssid; do
    [[ $id == "$cur" ]] && continue
    [[ -n $PREF_VETO_ID && $id == "$PREF_VETO_ID" ]] && (( now < PREF_VETO_UNTIL )) && continue
    vis=0
    if [[ $BACKEND != wpa ]]; then
      grep -qFx -- "$id" <<<"$nmvis" && vis=1
    else
      W="$ssid" awk '$0 == ENVIRON["W"] { f = 1; exit } END { exit !f }' <<<"$iwn" && vis=1
      (( vis )) || { W="$ssid" awk '$0 == ENVIRON["W"] { f = 1; exit } END { exit !f }' <<<"$suppn" && vis=1; }
    fi
    (( vis )) || continue
    p=$(get_priority "$id"); [[ $p =~ ^-?[0-9]+$ ]] || p=0
    (( p > best_p )) && { best=$id; best_p=$p; }
  done < <(known_ids)
  dbg "best_pref_id: cur=$cur(p=$cur_p) -> best=${best:-none}(p=$best_p) veto=${PREF_VETO_ID:-none}"
  [[ -n $best ]] && printf '%s' "$best"
  return 0
}

apply_profile() {  # aasw's night mode: one date fork per tick, transition-only logging
  [[ $NIGHT_MODE == "yes" ]] || return 0
  local now s e p
  now=$(( 10#0$(date +%H) * 60 + 10#0$(date +%M) ))  # 10#0: octal trap AND empty-date safe
  s=$(( 10#${NIGHT_START%:*} * 60 + 10#${NIGHT_START#*:} ))
  e=$(( 10#${NIGHT_END%:*} * 60 + 10#${NIGHT_END#*:} ))
  if (( s > e )); then  # window wraps midnight
    if (( now >= s || now < e )); then p=night; else p=day; fi
  else
    if (( now >= s && now < e )); then p=night; else p=day; fi
  fi
  [[ $p == "$PROFILE" ]] && return 0
  PROFILE=$p
  if [[ $p == night ]]; then
    CUR_MIN_UP=$NIGHT_MIN_UP_KBPS; CUR_GAIN=$NIGHT_GAIN_PCT; CUR_COOLDOWN=$NIGHT_DANCE_COOLDOWN
    site_log INFO "night profile active (floor ${NIGHT_MIN_UP_KBPS} kbps)" \
                  "الوضع الليلي مفعل - معايير أهدأ"
  else
    CUR_MIN_UP=$MIN_UP_KBPS; CUR_GAIN=$SWITCH_GAIN_PCT; CUR_COOLDOWN=$DANCE_COOLDOWN
    site_log INFO "day profile active (floor ${MIN_UP_KBPS} kbps)" \
                  "الوضع النهاري مفعل"
  fi
}

enable_stealth() {  # optional low observability; INPUT chain (aasw dropped its OWN
  # outgoing pings by mistake); -C first: rc.local respawns must not stack rules.
  # aasw's third leg (DHCP hostname hiding via dhclient.conf) is DROPPED: these
  # images use dhcpcd, not dhclient — mask the hostname in /etc/dhcpcd.conf if wanted.
  [[ $STEALTH_MODE == "yes" ]] || return 0
  iptables -C INPUT -i "$IF" -p icmp --icmp-type echo-request -j DROP 2>/dev/null \
    || iptables -I INPUT -i "$IF" -p icmp --icmp-type echo-request -j DROP 2>/dev/null || :
  systemctl stop avahi-daemon 2>/dev/null || :
  site_log INFO "stealth mode active (icmp hidden, avahi stopped)" \
                "وضع التخفي مفعل"
}

# ------------------------------- the fight --------------------------------------
ME_SINCE=0     # epoch when a ME-side wedge was first seen; healthy ticks clear it
LINK_OK=0      # set by connect_id when association+DHCP worked THIS round — evidence
               # gathered BEFORE any open-network teardown can poison the diagnosis
PREF_VETO_ID="" PREF_VETO_UNTIL=0  # a preferred network that measured too slow is
               # benched for 3 cooldowns — ends the pref-vs-dance switch war (proven)
# Reporting doctrine (owner decree): AWACS reports AS RICHLY as aasw did — every
# meaningful event goes local AND to the site (Arabic), per event, not per streak;
# offline events spool (SPOOL_CAP deep) and the whole story lands after recovery.

fight() {  # no internet: escalate calmly, measure honestly, reboot only for OUR OWN wedge
  local round nm_working=0 st
  drop_open    # yesterday's crutch must not shadow today's real networks
  enable_all
  arm_hidden   # an EXTERNAL supplicant restart strips runtime scan_ssid — re-arm every engagement
  if [[ $BACKEND != wpa ]]; then
    NM_ERR=""; NM_RC=0; NM_AUTH=0   # fresh activation evidence for THIS fight
    nm_wait_settled                  # never act while NM is mid-transition
  fi
  reassociate
  # Credit the verified moment (connect_id's doctrine, same words): a gentle heal
  # that dies sub-tick must not leave a stale wedge streak for the reboot valve —
  # this was the LAST net_up=1 site that could carry an uncredited stale stamp.
  wait_ip && have_net && { net_up=1; ME_SINCE=0; return 0; }

  for round in 1 2 3; do
    nm_working=0
    if [[ $BACKEND != wpa ]]; then
      # NM healed mid-fight (its autoconnect won while we slept/probed)? CREDIT AND
      # EXIT with zero further overrides — an override here would stomp its success.
      nm_wait_settled
      have_net && { net_up=1; ME_SINCE=0; return 0; }
      # Deference is decided BEFORE any candidate probe: a con-up must never race a
      # NM that is actively working the device (proven con-ups inside the band).
      if nm_busy; then
        nm_working=1
        site_log INFO "NM is still trying - waiting it out" \
                      "مدير الشبكة يحاول يتصل - ننتظره ولا نتدخل"
      fi
      # A busy sighting ANYWHERE in the streak means "still retrying" — never a
      # wedge: the clock and the settled count start over from that moment.
      if (( NM_SAW_BUSY )); then ME_SINCE=0; NM_SETTLED_SEEN=0; NM_SAW_BUSY=0; fi
    fi
    LINK_OK=0
    if (( ! nm_working )); then
      best_by_upload && return 0
    fi
    # CLASSIFY BEFORE the crutches: their teardown (select/remove) drops our route
    # and association, and diagnosing AFTER it framed every pure ISP outage as an
    # internal wedge — a proven ~35min reboot CYCLE. Order is law.
    # ME vs ISP, three tells for OUR side: a known network on the air we provably
    # cannot ride (LINK_OK=0); a radio that sees NOTHING (healthy radios always see
    # neighbors); or a MUTE supplicant (empty known list while the conf holds many —
    # the one organ whose cure, restart dhcpcd, lives on rung L2).
    # (nm_working was decided at the round top: NM owning the device mid-transition
    # must NEVER read as an ME wedge — the anti-reboot-loop clause — so it takes
    # the external branch verbatim.)
    if (( ! nm_working )) && ! gw_ok && (( ! LINK_OK )) \
         && { [[ -n $(visible_known_ids) ]] || [[ -z $(scan) ]] || [[ -z $(known_ids) ]]; }; then
      if auth_failing; then
        # Wrong password rides the SAME evidence signature as a wedge. The LADDER
        # still runs (a real wedge can coincide with one stale hotspot password —
        # skipping recovery entirely was a proven starvation), but the reboot clock
        # stays UNARMED: no reboot on earth fixes credentials.
        site_log ERROR "association refused - wrong password? (recovery continues, reboot stays off)" \
                       "الشبكة رفضت الاتصال - كلمة سر خاطئة؟ (الإنعاش مستمر والريبوت ممنوع)"
        # ACTIVE disarm, not just skip-arming: TEMP-DISABLED is a TIMED flag on a real
        # supplicant (expires between rounds, wiped by an L2/L3 restart), so a no-flag
        # instant could arm the clock and nothing would ever disarm it while the
        # password stays wrong — a PROVEN credentials reboot. Credentials sighted =
        # clock back to zero, every time.
        ME_SINCE=0
      else
        # On NM the clock arms only once NM has provably GIVEN UP (settled 30/120,
        # or the hosed-NM widening) — its own retries deserve the full window.
        if [[ $BACKEND == wpa ]] || nm_me_settled; then
          (( ME_SINCE == 0 )) && ME_SINCE=$(date +%s)
        fi
      fi
      dbg "fight round $round: ME evidence (LINK_OK=0, gw unreachable, auth_failing=$(auth_failing && echo 1 || echo 0))"
      # RUNG BOUNDARY (real lab, live NM journal 2026-09-12): the evidence above takes
      # ~12 s to gather; inside that window NM's own autoconnect had already ACTIVATED
      # the home network, and L1 bounced the radio 5 s after "Activation: successful"
      # — a needless outage of NM's own win (N13/§6 at the rung boundary). Let NM
      # settle, credit a heal, and never fire a rung at a device NM reports connected.
      if [[ $BACKEND != wpa ]]; then
        nm_wait_settled
        have_net && { enable_all; net_up=1; ME_SINCE=0; return 0; }
        st=$(nm_dev_state); nm_note_state "$st"
        if (( (st >= 40 && st <= 90) || st == 110 )); then
          # NM picked the device up again WHILE the evidence was gathered (a con-up
          # that outlived -w, or its own autoconnect): the round-top rule applies here
          # too — its activation finishes or fails on its own, never under a rung.
          site_log INFO "NM is still trying - waiting it out" \
                        "مدير الشبكة يحاول يتصل - ننتظره ولا نتدخل"
          sleep 20; continue
        fi
        if (( st >= 100 && st < 110 )); then
          # associated with an IP but no internet = the router's problem, not ours
          ME_SINCE=0
          site_log INFO "NetworkManager is connected, internet is not (round $round) — router-side, no rung" \
                        "NetworkManager متصل والإنترنت مقطوع (جولة $round) — المشكلة عند الراوتر، لا إنعاش"
          { try_safety || try_open; } && return 0
          sleep 20; continue
        fi
      fi
      recover "$round"
      # Credit a heal the rung ITSELF produced — without this the same round hunted
      # a crutch and parked the box on an open stranger beside the owner's healthy
      # network, reporting it as a win (proven on both backends).
      have_net && { enable_all; net_up=1; ME_SINCE=0; return 0; }   # enable_all: the win law
      { try_safety || try_open; } && return 0
    else
      ME_SINCE=0
      site_log INFO "outage looks external (round $round) — waiting, not rebooting" \
                    "الانقطاع يبدو خارجياً (جولة $round) — ننتظر بلا إعادة تشغيل"
      have_net && { enable_all; net_up=1; return 0; }   # healed meanwhile — re-arm all, then leave
      { try_safety || try_open; } && return 0
      sleep 20
    fi
  done

  if (( ME_SINCE > 0 && $(date +%s) - ME_SINCE >= REBOOT_AFTER_MIN * 60 )) \
     && { [[ $BACKEND == wpa ]] || nm_me_settled; }; then
    # Local-only by physics: the net is down (nothing sends) and a spooled copy would
    # die with the reboot (tmpfs). The site learns of the reboot from the boot story.
    log ERROR "wedged ${REBOOT_AFTER_MIN}min with networks visible — rebooting (repeats per streak until cured)"
    sync; sleep 2; reboot
  fi
  # A LOSING fight's last act was a crutch teardown that left the supplicant with
  # zero enabled networks — hand it back its full autonomy before returning, so a
  # dead-AWACS window between engagements can never strand the box (proven gap).
  enable_all
  return 1
}

# ------------------------------- daemon ----------------------------------------
main() {
  site_log INFO "AWACS ${VERSION} starting on ${IF} (device $(device_id))" \
                "أواكس ${VERSION} بدأ العمل على ${IF}"
  log INFO "reporting: ${LOG_TARGET}${SITE_URL:+ -> ${SITE_URL}} | probe: $(probe_on && probe_url || echo 'none - signal mode') | wifi cell: ${REPORT_WIFI}"
  (( LT_DOWNGRADED )) && log WARN "LOG_TARGET asked for the site but SITE_URL is empty - running local-only"
  # detect_if's wlan0 fallback can name an interface that does not exist (dead radio,
  # unplugged USB dongle) — say so ONCE in the log instead of fighting a ghost silently.
  iw dev "$IF" info >/dev/null 2>&1 \
    || site_log ERROR "interface ${IF} not present - is the WiFi hardware alive?" \
                      "واجهة الواي فاي ${IF} غير موجودة - العتاد سليم؟"
  check_tools

  # Backend verdicts (detect_backend ran at dispatch): wpa = legacy pillar, untouched;
  # nm = full capability as NM's SUPERVISOR; nm_lame = the only monitor-only mode left.
  if [[ $BACKEND == nm_lame ]]; then
    site_log ERROR "NetworkManager image but AWACS cannot drive it (unmanaged/no nmcli) - monitoring only" \
                   "النظام على NetworkManager بس أواكس ما يقدر يتحكم فيه (الكرت خارج الإدارة أو nmcli ناقص) - نراقب بس"
    # Parked, not dead: the boot story must still reach the dashboard (it spooled —
    # nothing had flushed it), and the ONE tool whose absence caused this (nmcli)
    # still gets its single install attempt. Same 300s cadence, no new loop.
    while :; do
      if have_net; then net_up=1; flush_spool; install_tools; fi
      # Lame ONLY because nmcli was missing and the install just landed it? Exit —
      # the rc.local respawn re-detects and comes back as a full nm supervisor.
      # (Never for the unmanaged verdict: nmcli exists there, exiting would cycle.)
      # (only under the rc.local respawn lane: the -d compat lane has no respawner,
      # so exiting there would end the daemon for good)
      if [[ ${NM_LAME_REASON:-} == nocli && -z ${AWACS_DAEMONIZED:-} ]] && command -v nmcli >/dev/null 2>&1; then
        site_log OK "nmcli is now installed - restarting as a full NetworkManager supervisor" \
                    "تم تنزيل nmcli - يعاد التشغيل بكامل القدرات"
        sleep 5; exit 0
      fi
      sleep 300
    done
  fi
  [[ $BACKEND == nm ]] && site_log INFO "NetworkManager backend - AWACS supervises it (full capability)" \
                                        "النظام يستخدم NetworkManager - أواكس يشتغل معه بكامل قدراته"

  rfkill unblock wifi 2>/dev/null || :  # a box that BOOTS soft-blocked must not wait a fight cycle
  [[ $BACKEND != wpa ]] && { nmcli radio wifi on >/dev/null 2>&1 || :; }  # NM owns soft-rfkill
  iw dev "$IF" set power_save off 2>/dev/null || :  # aasw's gift: shaves 100-300ms off camera latency
  enable_stealth
  pgrep -f /usr/local/bin/aasw >/dev/null 2>&1 \
    && site_log WARN "aasw.sh is still running - two WiFi authorities will fight; remove its rc.local line" \
                     "aasw القديم لا يزال يعمل - سلطتان تتصارعان؛ احذف سطره من rc.local"
  # Reap a dead predecessor's crutch: the marker survives the crash (crash-proof
  # lifecycle); the nm arm adds the name-prefix sweep + /run glob belt.
  reap_crutches
  enable_all
  arm_hidden   # the owner HAS hidden networks — without directed probes they never appear

  local fails=0 strikes=0 flow here home_id last_dance=0 last_pref=0 pref_hits=0 \
        cur_id cand_id ok_ticks=0 engaged=0
  # Boot aggression (aasw parity): no internet on arrival = fight NOW, not after the
  # ~30s NET_FAIL_TICKS grace. fight() opens GENTLY (reassociate + wait_ip) so a
  # supplicant mid-association is waited for, never torn down.
  # A predecessor killed MID-FLUSH left its snapshot orphaned — rescue it in front
  # of any fresh lines (a few re-sent lines beat a silently amputated story).
  if [[ -s ${SPOOL}.sending ]]; then
    cat "${SPOOL}.sending" "$SPOOL" 2>/dev/null >"${SPOOL}.t" || :
    mv -f "${SPOOL}.t" "$SPOOL" 2>/dev/null || :
    rm -f "${SPOOL}.sending"
  fi
  if have_net; then net_up=1; flush_spool  # a respawn delivers its predecessor's story
  else fight || engaged=1; fi  # a LOSING boot fight arms the flag: a heal landing
                               # before fails ripens must still say "restored"
  while :; do
    apply_profile
    if have_net; then
      net_up=1; fails=0; ME_SINCE=0
      NM_L3_SPENT=0; NM_RC8=0; NM_SETTLED_SEEN=0; NM_SAW_BUSY=0   # healthy tick = the streak
                                                                  # and ALL its NM evidence die
      # A short outage can heal BETWEEN fights — the recovery must still be told
      # (proven silent path: fight fails, next tick finds the net back, nobody speaks).
      if (( engaged )); then
        engaged=0; strikes=0   # same hysteresis reset as the fight-success join
        site_log OK "internet restored: $(dssid)" "رجع الانترنت عبر: $(dssid)"
      fi
      # Drain the spool after ~30s of PROVEN health — a just-healed link should carry
      # frames before it carries history — then retry every ~5min while lines remain
      # (a site-down-while-internet-up phase must not park the spool forever).
      (( ++ok_ticks == 3 || (ok_ticks > 3 && ok_ticks % 30 == 0) )) && flush_spool
      (( ok_ticks == 3 )) && install_tools   # first PROVEN-healthy moment, once per boot
      # WiFi cell heartbeat every ~60s (battery cadence) — backgrounded, lock-free.
      if (( ok_ticks % 6 == 1 )); then { report_wifi; } 9>&- & fi
      # Back on a real network? The crutch (open or emergency) has served — retire it.
      # cur_id must be NON-EMPTY: a momentarily mute wpa_cli returns "", and "" != id
      # would tear the crutch down while we still ride it (proven false-retire class).
      if [[ -n $OPEN_ID ]]; then
        cur_id=$(current_id)
        [[ -n $cur_id && $cur_id != "$OPEN_ID" ]] && drop_open
      fi
      # Passive upload QA — three gates keep it honest: kernel counters only; NEVER
      # while a live viewer runs (its own rate sits in the band and a probe/dance
      # would stutter it — the stream IS the meter); and a dance cooldown, because
      # every dance disrupts real traffic to measure it. Deliberate reduction vs
      # aasw: no upgrade-hunting while the link is ADEQUATE (aasw jumped to any
      # >1.5x-faster network) — the never-break-a-working-link law forbids that
      # greed; we look around only when provably suffering.
      if streaming; then
        # OPPORTUNISTIC METER (owner doctrine: "the live stream IS a free upload
        # meter"): while real traffic flows, its kernel-counter rate is the
        # measurement — no probe, no extra task, zero cost. A HEALTHY stream
        # (flow >= STREAM_MIN_KBPS) proves the link carries its job: never touch
        # it. A STARVING one is already broken for the viewer — only then does
        # evaluation become allowed, and even then one honest probe (here=) gets
        # the veto before any switch (a small very-low-quality feed reads slow
        # while the link is fine; the probe clears that false alarm).
        flow=$(tx_kbps)
        dbg "QA(stream): flow=${flow} kbps, strikes=${strikes}"
        # probe_on: without a probe target a starving stream cannot be told from a
        # small feed (the probe is what clears that false alarm) — signal mode never dances
        if probe_on && (( flow >= 5 && flow < STREAM_MIN_KBPS )); then
          if (( ++strikes >= UP_STRIKES && $(date +%s) - last_dance >= CUR_COOLDOWN )); then
            strikes=0; last_dance=$(date +%s)
            site_log WARN "live stream starving (${flow} kbps) - evaluating known networks" \
                          "البث يعاني (${flow} كيلوبت/ث) - جاري تقييم الشبكات"
            here=$(up_kbps); note_kbps "$here"
            if (( here < CUR_MIN_UP )); then
              home_id=$(current_id)
              best_by_upload $(( here * CUR_GAIN / 100 )) "${home_id:-}" || enable_all
            fi
          fi
        else
          strikes=0
        fi
      else
        flow=$(tx_kbps)
        dbg "QA: flow=${flow} kbps, strikes=${strikes}, profile=${PROFILE:-day}"
        if probe_on && (( flow >= 20 && flow < CUR_MIN_UP )); then   # signal mode: no QA
          if (( ++strikes >= UP_STRIKES && $(date +%s) - last_dance >= CUR_COOLDOWN )); then
            strikes=0; last_dance=$(date +%s)
            # A committed dance CAN outlast the site's 55s online window — the
            # dashboard may show a brief offline blink. Accepted: the dance only
            # ever runs when uploads are ALREADY suffering, never under a viewer.
            site_log WARN "sustained slow upload (${flow} kbps) - evaluating known networks" \
                          "رفع بطيء مستمر (${flow} كيلوبت/ث) - جاري تقييم الشبكات"
            here=$(up_kbps); note_kbps "$here"  # honest baseline BEFORE leaving the incumbent
            if (( here < CUR_MIN_UP )); then
              home_id=$(current_id)
              best_by_upload $(( here * CUR_GAIN / 100 )) "${home_id:-}" || enable_all
            fi
          fi
        else
          strikes=0
        fi
      fi
      # Preferred-network return (aasw's upgrade-seeking, the metered-hotspot escape):
      # a fight can strand us on a low-priority network (a hotspot burning data) after
      # the home router returns. Every PREF_CHECK, if a strictly higher-priority known
      # network is visible for TWO consecutive checks (20min stability — no flapping),
      # go home; if home does not deliver, fall straight back. Zero traffic to look.
      if ! streaming && (( $(date +%s) - last_pref >= PREF_CHECK )); then
        last_pref=$(date +%s)
        # Supplicant-side scan first: armed scan_ssid makes DIRECTED probes, so a
        # HIDDEN home network becomes visible to the pref check (iw's broadcast scan
        # never shows it — the exact escape this feature exists for was blind to it).
        pref_prescan
        cur_id=$(current_id)
        cand_id=$(best_pref_id "${cur_id:-}")
        if [[ -n $cand_id ]]; then
          if (( ++pref_hits >= 2 )); then
            pref_hits=0
            site_log INFO "higher-priority network visible - trying to go home" \
                          "شبكة أعلى أولوية ظاهرة - نحاول الرجوع للبيت"
            if connect_id "$cand_id"; then
              # MEASURE ON ARRIVAL — priority alone must never overrule the measured-
              # upload law: a slow home gets benched 3 cooldowns and we go straight
              # back (this ended the proven pref-vs-dance 20-minute switch war).
              here=$(up_kbps); probe_on && note_kbps "$here"
              if probe_on && (( here < CUR_MIN_UP )); then
                site_log WARN "preferred network too slow (${here} kbps) - benching it, going back" \
                              "الشبكة المفضلة بطيئة (${here} كيلوبت/ث) - نرجّعها للاحتياط ونعود"
                PREF_VETO_ID=$cand_id; PREF_VETO_UNTIL=$(( $(date +%s) + CUR_COOLDOWN * 3 ))
                { [[ -n ${cur_id:-} ]] && connect_id "$cur_id"; } || :
                enable_all
              else
                enable_all
                site_log OK "returned to preferred network: $(dssid) ($(up_words "$here"))" \
                            "رجع للشبكة المفضلة: $(dssid) ($(up_words_ar "$here"))"
              fi
            else
              { [[ -n ${cur_id:-} ]] && connect_id "$cur_id"; } || :
              enable_all
            fi
          fi
        else
          pref_hits=0
        fi
      fi
    else
      net_up=0; ok_ticks=0
      if (( ++fails >= NET_FAIL_TICKS )); then
        engaged=1
        # Announce the LOSS on the transition tick ONLY — later fights in the same
        # outage tell their own story (rounds, rungs, candidates); re-shouting "lost"
        # per attempt drowned the outage's opening timestamp out of the spool cap.
        (( fails == NET_FAIL_TICKS )) \
          && site_log WARN "internet lost on ${IF} - engaging" \
                           "انقطع الانترنت - بدأ القتال للرجوع"
        fight && { fails=0; engaged=0; strikes=0
                   # strikes=0: a fight usually lands on a DIFFERENT network — old
                   # strikes must not collapse the new link's 3-sample hysteresis.
                   site_log OK "internet restored: $(dssid)" \
                               "رجع الانترنت عبر: $(dssid)"; }
      fi
    fi
    sleep "$TICK"
  done
}

# ------------------------------- toolbox ----------------------------------------
# TUI palette — the owner's aasw visual language (frame 1;37, banner 1;41, warn 1;33,
# ok 1;32, accent 1;36). Closed boxes carry STATIC ASCII titles only (guaranteed
# alignment); dynamic bilingual content rides open-right colored rows — dynamic
# Arabic inside a closed frame misaligns, the exact problem the owner hand-tunes.
readonly C0=$'\033[0m' CW=$'\033[1;37m' CT=$'\033[1;41m' CY=$'\033[1;33m' \
         CG=$'\033[1;32m' CC=$'\033[1;36m' CR=$'\033[1;31m'
tui_hdr() {  # $1 = ASCII title, padded into the owner's 45-column frame
  echo
  echo -e "${CW}┌─────────────────────────────────────────────┐${C0}"
  printf '%b│%b%-45s%b│%b\n' "$CW" "$CT" " $1" "${C0}${CW}" "$C0"
  echo -e "${CW}└─────────────────────────────────────────────┘${C0}"
}
tui_row() { printf '  %b%-9s%b   %s\n' "$CY" "$1" "$C0" "$2"; }  # LABEL VALUE (3-space
# gap = the "✓ "/"✗ " width, so plain values line up with verdict values in one column)
tui_ok()  { printf '  %b%-9s%b %b✓ %s%b\n' "$CY" "$1" "$C0" "$CG" "$2" "$C0"; }
tui_bad() { printf '  %b%-9s%b %b✗ %s%b\n' "$CY" "$1" "$C0" "$CR" "$2" "$C0"; }
dlist() {  # DISPLAY filter: decode the SSID column of tab-separated tool output so
  # the owner's Arabic networks read as Arabic, in FIXED columns (raw tabs jumped in
  # ragged 8-col steps). $1 = stream width: 3+ pads the name and '-' marks a fully
  # empty tail (a belt only — real list_networks always fills bssid); 2 = name is
  # last, no padding. printf pads by BYTES, so the pad width is widened by
  # (bytes - chars) to keep multi-byte Arabic rows in the same column — correct on
  # any UTF-8 terminal (the Pi OS default); a C locale merely falls back to the
  # old ragged view. Display only — matching NEVER sees any of this.
  local mode=${1:-3} a b rest s pad
  while IFS=$'\t' read -r a b rest; do
    s=$(pssid "$b")
    if (( mode >= 3 )); then
      pad=$(( 24 + $(printf %s "$s" | wc -c) - ${#s} ))
      printf "  %-3s %-${pad}s %s\n" "$a" "$s" "${rest:--}"
    else
      printf '  %-3s %s\n' "$a" "$s"
    fi
  done
}

cli() {  # aasw's manual toolbox, reborn — runs BESIDE the daemon (no lock taken)
  local AWACS_CLI=1  # dynamic scope: callees (scan) keep their warnings LOCAL —
                     # a hand-run command must not append to the daemon's site story
  case "$1" in
    status)
      tui_hdr "AWACS ${VERSION} STATUS"
      tui_row ""        "(الفحص حي — لحظات، وقد يصل ~15 ثانية إذا كان النت مقطوعاً)"
      tui_row "device"  "$(device_id) on ${IF}"
      tui_row "backend" "$BACKEND / نظام إدارة الشبكة"
      local dpid=""
      [[ -s $LOCK ]] && read -r dpid <"$LOCK" 2>/dev/null
      # cmdline must actually SAY awacs: after a crash the PID can be reused by any
      # process, and a bare -d check would call a stranger our daemon (PID-reuse lie).
      if [[ $dpid =~ ^[0-9]+$ && -d /proc/$dpid ]] \
         && grep -aq awacs "/proc/$dpid/cmdline" 2>/dev/null; then
        tui_ok  "daemon"  "running (pid $dpid) / الحارس يعمل"
      else
        tui_bad "daemon"  "NOT running / الحارس متوقف"
      fi
      local nssid sig ipa
      nssid=$(dssid)
      tui_row "network" "${nssid:--}"
      sig=$(iw dev "$IF" link 2>/dev/null | sed -n 's/^[[:space:]]*signal: //p' | head -1)
      tui_row "signal"  "${sig:--} / قوة الإشارة"
      ipa=$(ip -4 addr show dev "$IF" scope global 2>/dev/null | awk '/inet /{print $2; exit}')
      tui_row "ip"      "${ipa:--}"
      if gw_ok;     then tui_ok  "gateway"  "reachable / الراوتر يرد"
                    else tui_bad "gateway"  "NOT reachable / الراوتر لا يرد"; fi
      if have_net;  then tui_ok  "internet" "ONLINE / متصل"
                    else tui_bad "internet" "OFFLINE / مقطوع"; fi
      if streaming; then tui_row "viewer"   "live - QA on hold / مشاهد نشط"
                    else tui_row "viewer"   "none / لا مشاهد"; fi
      tui_row "upload"  "$(tx_kbps) kbps flowing (3s kernel sample)"
      echo
      ;;
    networks)
      tui_hdr "STORED NETWORKS"
      local stored visnow
      if [[ $BACKEND != wpa ]]; then
        # SRC labels awacs ONLY via nm_del_own's own double test (name regex AND /run
        # filename) — everything else is owner, so the owner can SEE at a glance that
        # his profiles are untouched, whatever their shape.
        echo -e "  ${CC}المخزنة (uuid / name / prio / auto / src):${C0}"
        local nuuid ntype nname nprio nauto nrow nfile nsrc nlist npad nrows=0
        nlist=$(nmcli -t -f UUID,FILENAME connection show 2>/dev/null)   # listed ONCE
        while IFS=: read -r nuuid ntype; do
          [[ $ntype == wifi || $ntype == 802-11-wireless ]] || continue
          (( ++nrows ))
          nname=$(nmcli -e no -g connection.id connection show uuid "$nuuid" 2>/dev/null | tr -d '\000-\037\177')
          nprio=$(get_priority "$nuuid"); [[ $nprio =~ ^-?[0-9]+$ ]] || nprio=0
          nauto=$(nmcli -g connection.autoconnect connection show uuid "$nuuid" 2>/dev/null)
          nrow=$(U="$nuuid" awk -F: '$1 == ENVIRON["U"] { print; exit }' <<<"$nlist")
          nfile=${nrow#*:}
          nsrc=owner
          if [[ $nname =~ ^awacs-(crutch|safety)-[0-9]+-[0-9]+$ \
                && $nfile == /run/NetworkManager/system-connections/awacs-* ]]; then nsrc=awacs; fi
          # byte-aware pad (dlist's law): printf pads bytes, Arabic names are 2 bytes/char;
          # 32 = the SSID maximum, and our own crutch names (>=25 chars) fit too
          npad=$(( 32 + $(printf %s "$nname" | wc -c) - ${#nname} ))
          printf "  %-8s %-${npad}s %-5s %-4s %s\n" "${nuuid:0:8}" "$nname" "$nprio" "$nauto" "$nsrc"
        done < <(nmcli -t -f UUID,TYPE connection show 2>/dev/null)
        # placeholder keyed on WIFI rows printed (an ethernet-only box has profiles but
        # no wifi ones — the old "$nlist non-empty" test left the section blank)
        (( nrows )) || echo "  (لا شبكات مخزنة)"
        echo -e "  ${CC}المرئية الآن (uuid / name):${C0}"
        visnow=$(visible_known_ids)
        if [[ -n $visnow ]]; then
          while IFS=$'\t' read -r nuuid _; do
            printf '  %-8s %s\n' "${nuuid:0:8}" "$(disp_ssid "$nuuid" "")"
          done <<<"$visnow"
        elif ! command -v nmcli >/dev/null 2>&1 || [[ $BACKEND == nm_lame ]]; then
          echo "  (nmcli غير متوفر أو الكرت خارج إدارة NetworkManager — لا قراءة ممكنة)"
        else
          echo "  (لا شبكة مخزنة ظاهرة الآن — المسح فارغ أو الشبكات بعيدة)"
        fi
        echo
        exit 0
      fi
      stored=$(wpa list_networks | tail -n +2)
      visnow=$(visible_known_ids)
      echo -e "  ${CC}المخزنة (id / name / bssid / flags):${C0}"
      if [[ -n $stored ]]; then dlist 3 <<<"$stored"
      else echo "  (لا شبكات مخزنة)"; fi
      echo -e "  ${CC}المرئية الآن (id / name):${C0}"
      if [[ -n $visnow ]]; then dlist 2 <<<"$visnow"
      else echo "  (لا شبكة مخزنة ظاهرة الآن — المسح فارغ أو الشبكات بعيدة)"; fi
      echo
      ;;
    evaluate)  # ranked view: CUR ID PRIO SIG SEC SSID (no guessed speeds — the
      # owner's doctrine bans signal-to-speed estimation; measured kbps lives in logs)
      tui_hdr "NETWORK EVALUATION"
      echo -e "  ${CC}الشبكات المرئية الآن — الأقوى أولاً / strongest first:${C0}"
      local ssid sig sec id p cur mark ids rows=0 vis inv="" kn air
      cur=$(current_id)
      kn=$(known_ids)          # ONE listing for the whole screen (nm: each call is
                               # (profiles+1) nmcli spawns — per-row calls stalled a Zero)
      air=$(scan)              # ONE radio picture for BOTH halves of the screen
      printf '%-4s %-8s %-5s %-8s %-5s %s\n' "CUR" "ID" "PRIO" "SIGNAL" "SEC" "SSID"
      while IFS=$'\t' read -r ssid sig sec; do
        [[ -n $ssid ]] || continue
        # ALL stored ids for this name (two ids can share one SSID): star + PRIO follow
        # the CURRENT id when it is among them, else the first — display never lies.
        if [[ $BACKEND != wpa ]]; then
          ids=$(W="$(iw2hex "$ssid")" awk -F'\t' '$2 == ENVIRON["W"] { print $1 }' <<<"$kn")
        else
          ids=$(W="$ssid" awk -F'\t' '$2 == ENVIRON["W"] { print $1 }' <<<"$kn")
        fi
        id=""; mark=""; p="-"
        if [[ -n $ids ]]; then
          id=$(head -1 <<<"$ids")
          [[ -n ${cur:-} ]] && grep -qFx "$cur" <<<"$ids" && { mark="*"; id=$cur; }
          p=$(get_priority "$id"); [[ $p =~ ^-?[0-9]+$ ]] || p=0
        fi
        printf '%-4s %-8s %-5s %-8s %-5s %s\n' "$mark" "${id:0:8}" "$p" "$sig" "$sec" "$(pssid "$ssid")"
        (( ++rows ))
      done <<<"$air"
      (( rows )) || echo "  (لا شبكات مرئية — المسح فارغ أو الراديو ما زال يبدأ)"
      # Stored-but-invisible tail: "why is my network unused?" should not need a
      # second command to reveal that it is simply not on the air right now. Built
      # from the SAME picture the table used (nm's own list once contradicted it).
      local gid gvis=$'\n' gall=$'\n'
      if [[ $BACKEND != wpa ]]; then
        vis=$(while IFS=$'\t' read -r ssid _; do [[ -n $ssid ]] && { iw2hex "$ssid"; echo; }; done <<<"$air")
      else
        vis=$(cut -f1 <<<"$air")
      fi
      # per PROFILE: a uuid is "invisible" only when NONE of its key rows is on the air
      # (an ambiguous 0x profile has two rows — the table above may show it via one)
      while IFS=$'\t' read -r gid ssid; do
        [[ -n $gid ]] || continue
        grep -qFx -- "$ssid" <<<"$vis" && gvis+="$gid"$'\n'
      done <<<"$kn"
      while IFS=$'\t' read -r gid ssid; do
        [[ -n $gid ]] || continue
        [[ $gvis == *$'\n'"$gid"$'\n'* || $gall == *$'\n'"$gid"$'\n'* ]] && continue
        gall+="$gid"$'\n'
        inv+="$(disp_ssid "$gid" "$ssid") "
      done <<<"$kn"
      [[ -n $inv ]] && echo -e "  ${CY}مخزنة غير ظاهرة الآن:${C0} $inv"
      echo
      ;;
    scan)
      tui_hdr "RAW SCAN"
      local sout; sout=$(scan)
      if [[ -n $sout ]]; then printf '%s\n' "$sout"
      else echo "  (المسح فارغ أو فشل — الراديو مشغول أو ما زال يبدأ، جرّب بعد لحظات)"; fi
      [[ $BACKEND != wpa ]] && echo "  (nm يمسح لوحده بالتوازي — كاش iw هنا قد يتأخر ثواني، للعرض فقط)"
      echo
      ;;
    speed)
      tui_hdr "UPLOAD SPEED PROBE"
      if probe_on; then
        tui_row "probing" "${PROBE_KB}KB -> $(probe_url) ..."
        local kb; kb=$(up_kbps)
        if (( kb > 0 )); then tui_ok  "upload" "${kb} kbps / سرعة الرفع الفعلية"
        else                  tui_bad "upload" "0 kbps — probe failed / القياس فشل أو الموقع لا يرد"; fi
      else
        tui_bad "upload" "no probe target (signal mode) / لا هدف للقياس: اضبط SITE_URL أو PROBE_URL"
      fi
      echo
      ;;
    check) if have_net; then echo "internet: OK"; exit 0; else echo "internet: DOWN"; exit 1; fi ;;
    help)
      tui_hdr "AWACS ${VERSION} - COMMANDS"
      echo -e "  ${CC}بدون وسيطة = الحارس (يشغّله rc.local) / no argument = the daemon${C0}"
      tui_row "status"   "حالة الشبكة والحارس الآن / live network + daemon state"
      tui_row "networks" "الشبكات المخزنة والمرئية / stored vs visible networks"
      tui_row "evaluate" "جدول مرتب بالقوة والأولوية / ranked network table"
      tui_row "scan"     "مسح خام / raw scan (cached ${SCAN_TTL}s)"
      tui_row "speed"    "قياس سرعة الرفع الفعلية / one real upload probe"
      tui_row "check"    "فحص الإنترنت للسكربتات / exit-coded internet check (plain output)"
      tui_row "-d"       "تشغيل بالخلفية / self-daemonize (compat; -q accepted, no-op)"
      echo
      ;;
    *) echo "usage: awacs.sh [status|networks|evaluate|scan|speed|check|help|-d]   (no argument = daemon)"; exit 1 ;;
  esac
  exit 0
}

# ------------------------------- dispatch ---------------------------------------
# Rootless fast lane: `check` (exit-coded internet probe for scripts/cron) and `help`
# need neither root nor a resolved interface — gating them behind root made check's
# exit 1 mean two different things (proven confusion).
case "${1:-}" in
  check|help|-h|--help) IF=wlan0 cli "${1/#-*/help}" ;;
esac
# A TYPO'D command must not hide behind the ROOT box: validate the word BEFORE the
# root gate, so a forgotten sudo and a misspelled command stay distinguishable.
case "${1:-}" in
  ""|-q|--quiet|-d|--daemon|status|networks|evaluate|scan|speed) : ;;
  *) echo "usage: awacs.sh [status|networks|evaluate|scan|speed|check|help|-d]   (no argument = daemon)"; exit 1 ;;
esac
require_root
IF="${AWACS_IF:-$(detect_if)}"; readonly IF
# The private state dir must exist before ANY runtime file (lock, scan cache, spool):
# /run is tmpfs — recreated every boot, owned root, mode 700 (SSIDs are location data).
install -d -m 700 "$RUN_DIR" 2>/dev/null || { mkdir -p "$RUN_DIR" && chmod 700 "$RUN_DIR"; } 2>/dev/null || :
# Backend verdict (wpa / nm / nm_lame): read-only toolbox WORDS decide FAST (a
# transiently-wrong verdict is harmless there); every daemon launch — bare, -d or
# -q alike — waits out early boot properly (a fast -d once decided nm where the
# rc.local launch decided nm_lame: two verdicts for one box).
# The lane is decided from the WHOLE argv, skipping -q/--quiet, so "-q -d" and
# "-q status" (old launch-line spellings) take the same lane as "-d -q" / "status".
lane=patient
for a in "$@"; do
  case $a in
    -q|--quiet) continue ;;
    status|networks|evaluate|scan|speed) lane=fast ;;
    -d|--daemon) [[ -z ${AWACS_DAEMONIZED:-} ]] && lane=fast ;;  # PARENT only hands off to
  esac                                                            # setsid — the child pays once
  break
done
unset a
if [[ $lane == fast ]]; then detect_backend fast; else detect_backend; fi
# Migration tripwire: under the nm family no code path may reach wpa_cli — a missed
# call site must surface in the log instead of racing NM silently.
if [[ $BACKEND != wpa ]]; then
  wpa() { local IFS=' '; log ERROR "BUG: wpa_cli reached under $BACKEND backend: $*"; return 1; }
  # (local IFS: "$*" joins with the FIRST IFS char — the global \n would split the line)
fi

# Compat flags (old aasw launch lines must keep working). -d self-daemonizes via
# setsid with a recursion guard — and BEFORE fd 9 exists, so no lock inheritance.
while [[ ${1:-} == -* ]]; do
  case "$1" in
    -d|--daemon)
      if [[ -z ${AWACS_DAEMONIZED:-} ]]; then
        AWACS_DAEMONIZED=1 setsid "$0" -d >/dev/null 2>&1 </dev/null &
        exit 0
      fi ;;
    *) : ;;  # -q/--quiet: logging is file-only by design — nothing to quiet
             # (-h and unknown flags never reach here — dispatched/rejected above)
  esac
  shift
done
[[ -n ${1:-} ]] && cli "$1"

# Daemon path only: take the single-instance lock. Append-open (9>>) so a LOSING
# second instance can never truncate the winner's PID; the winner then rewrites it.
exec 9>>"$LOCK"
on_shutdown() {  # the owner's GRACEFUL box — VERBATIM transplant, spacing sacred
  # IGNORE, not reset: a cgroup stop (systemd unit, system shutdown) delivers a second
  # TERM to the group moments after the first — with the trap merely reset it killed
  # the handler before enable_all ran (real lab, 6 of 6 stops). Ignored for the
  # handler's few seconds, the goodbye and the safety both complete; exit 0 ends it.
  trap '' INT TERM QUIT HUP
  # First act, before the goodbye: a Ctrl+C landing MID-FIGHT (after a
  # select_network narrowed the live supplicant) must hand back full autonomy.
  enable_all 2>/dev/null || :
    echo
    echo -e "\033[1;37m┌─────────────────────────────────────────────┐\033[0m"
    echo -e "\033[1;37m│\033[1;44m    GRACEFUL SHUTDOWN | إيقاف تشغيل سلس      \033[0;37m│\033[0m"
    echo -e "\033[1;37m├─────────────────────────────────────────────┤\033[0m"
    echo -e "\033[1;37m│ \033[1;33m    ⚠️  EN: \033[0mReceived interrupt signal       \033[1;37m │\033[0m"
    echo -e "\033[1;37m│ \033[1;33m    ⚠️  AR: \033[0mتم استلام إشارة المقاطعة         \033[1;37m│\033[0m"
    echo -e "\033[1;37m├─────────────────────────────────────────────┤\033[0m"
    echo -e "\033[1;37m│ \033[1;32m ✓  \033[0mExiting gracefully | جاري الخروج بأمان \033[1;37m │\033[0m"
    echo -e "\033[1;37m└─────────────────────────────────────────────┘\033[0m"
    echo
  exit 0
}
trap on_shutdown INT TERM QUIT HUP  # HUP: a closing terminal deserves the same grace
if ! flock -n 9; then
  # The rc.local respawn loop must stay SILENT (contract). A HUMAN double-launch
  # on a terminal gets the owner's INSTANCE box — VERBATIM, spacing sacred.
  if [[ -t 1 ]]; then
    running_pid=$(head -1 "$LOCK" 2>/dev/null || echo "?")
    echo
    echo -e "\033[1;37m┌──────────────────────────────────────────────┐\033[0m"
    echo -e "\033[1;37m│\033[1;43m      INSTANCE ERROR | خطأ في تعدد النسخ      \033[0;37m│\033[0m"
    echo -e "\033[1;37m├──────────────────────────────────────────────┤\033[0m"
    echo -e "\033[1;37m│ \033[1;31m✗  EN: \033[0mAnother instance is already running \033[1;37m  │\033[0m"
    echo -e "\033[1;37m│ \033[1;31m✗  AR: \033[0mهناك نسخة أخرى قيد التشغيل بالفعل    \033[1;37m │\033[0m"
    echo -e "\033[1;37m├──────────────────────────────────────────────┤\033[0m"
    echo -e "\033[1;37m│ \033[1;36mℹ \033[0mPID: $running_pid | يُرجى إنهاء النسخة الأخرى أولاً \033[1;37m│\033[0m"
    echo -e "\033[1;37m└──────────────────────────────────────────────┘\033[0m"
    echo
    exit 1
  fi
  exit 0
fi
printf '%d\n' "$$" >"$LOCK"   # PID is display-only; flock stays the authority
# A human typing bare `awacs.sh` gets the daemon in FOREGROUND — say so once (the
# rc.local respawn has no TTY and must stay silent by contract).
[[ -t 1 ]] && echo -e "${CC}AWACS ${VERSION}${C0}: foreground daemon on ${IF} — Ctrl+C يوقفه بأمان، ${CW}awacs.sh help${C0} لبقية الأوامر"
main
