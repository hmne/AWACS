#!/usr/bin/env bash
#
# awacs.sh — AWACS 1.0 (Advanced WiFi Auto Connection System)
# Successor to aasw.sh v7.9.1 with full feature parity: every aasw capability lives
# here, kept, improved, or replaced by a documented superior; the only two divergences
# are deliberate (no reboot for ISP outages, no routine download tests). Auto-install
# of missing tools: right package names, background, once per boot, no exec-restart.
# Mission: FIGHT for internet until connected. Network choice follows MEASURED UPLOAD
#   speed (the device uploads; download is irrelevant) — never signal strength alone.
# Role: SD-resident daemon (/usr/local/bin), launched from rc.local or a systemd unit
#   BEFORE the workload — it must work with no internet, so it is never fetched remotely.
# Platform: DUAL-STACK. Legacy Pi OS (dhcpcd +
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
#   export DEVICE_ID="<device-id>"
#   ( while :; do /usr/local/bin/awacs.sh; sleep 10; done ) >/dev/null 2>&1 &
#
# Manual toolbox (runs BESIDE the daemon, read-only except `speed`):
#   awacs.sh status | networks | evaluate | scan | speed | check | help
# Compat flags (old aasw launch lines keep working): -d self-daemonizes, -q is a no-op
# (logging is file-only by design), -h prints help.
#
# Site commands (the site's Wi-Fi menu: scan, switch, join): capture.sh writes one line to
#   /run/awacs/cmd and sends SIGUSR1; the main loop's top consumes it and answers through the
#   site's tmp/wifi_state.tmp. Passwords joined from the site live in /etc/awacs.networks and
#   the key that opens a typed password in /etc/awacs.key (both root 600, never logged).
#-------------------------------------------------------------------------------
set -uo pipefail
IFS=$'\n\t'
umask 077   # every runtime file (log/cache/spool/pid/probe) lands root-only — SSID lists are location data

# ------------------------------- configuration --------------------------------
# DEFAULTS ONLY — the isolated settings file /etc/awacs.conf (PLAIN bash
# assignments ONLY, e.g. MIN_UP_KBPS=250 or SAFETY_NET["MyPhone"]="pass" — a
# readonly/declare line there is unsupported and would void the typo safety-net)
# OVERRIDES any of them, then everything is sealed readonly. One file to tune.
VERSION="1.0"
TICK=10              # main-loop cadence: cheap checks only (1 ping, no downloads)
NET_FAIL_TICKS=3     # failed checks in a row before the fight starts (40-63 s with TICK=10)
ASSOC_WAIT=25        # seconds to wait for association + DHCP after a connect
PROBE_KB=200         # UPLOAD probe size — DECISION moments only, sent to OUR site
MIN_UP_KBPS=400      # DAY upload floor; sustained slower-while-active = look around
UP_STRIKES=3         # low-upload strikes before considering a switch (hysteresis)
SWITCH_GAIN_PCT=150  # DAY: challenger must beat the incumbent by >=150% (never-break law)
DANCE_COOLDOWN=1200  # DAY seconds between comparison dances — a dance disrupts, ration it
PREF_CHECK=600       # preferred-network look every 10min (a scan, no internet traffic)
REBOOT_AFTER_MIN=30  # ME-problem persisting this long -> reboot; a SURVIVING wedge
                     # earns another after the next full streak (~40min apart, never tight)
OPEN_NETWORKS="yes"  # last-resort passwordless networks — delete the word yes to disable
# --- Reporting site: all optional. Empty SITE_URL = the
# daemon works LOCAL-ONLY (log file only, no probes, network choice by signal).
SITE_URL=""          # base URL of the reporting site; AWACS talks to $SITE_URL/$DEVICE_ID/$SITE_API
SITE_API="receiver.php"  # endpoint file name under that path (the shipped receiver); your site's own name here
LOG_TARGET="local"   # local | both | remote — both/remote need SITE_URL; remote keeps only WARN/ERROR locally
PROBE_URL=""         # upload-speed probe target (any URL accepting a POST body); default = the site's endpoint
REPORT_WIFI="auto"   # publish the Wi-Fi cell (kbps,visible,total,band,SSID) to the site: auto | yes | no
SITE_TZ=""           # time zone stamped on SITE log lines (e.g. Asia/Kuwait); empty = the device's own zone
LOG_LANG="en"        # language of the LOCAL log's story lines: en | ar (DEBUG diagnostics stay English)
SITE_LANG="en"       # language of the lines sent to the site: en | ar — independent of LOG_LANG
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
DEBUG="${AWACS_DEBUG:-no}"  # decision-trace lines in the LOCAL log; opt-in. Measured with
                            # yes: 1517 trace lines to 6 story lines, the story unreadable.
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

# --- Isolation: the settings file. Sourced as ROOT, so it must BE root's:
# refuse a conf not owned by us or writable by group/others (a loose conf = a backdoor).
AWACS_CONF="${AWACS_CONF:-/etc/awacs.conf}"
# EUID gate: the rootless fast lanes (check/help) run on DEFAULTS by design — and
# [[ -O ]] tests the RUNNER's uid, so without this gate a rootless run would falsely
# accuse a correctly root-owned conf ("chown root: it") in every cron mail.
# The verdict on the settings file is kept for main(): the stderr prints below reach nobody
# under the launcher, so the start says the verdict again in the log and on the site.
CONF_STATE=""   # applied | missing | mode | owner ("" = a rootless run that never sources it)
CONF_MODE=""    # the refused mode, for the "mode" verdict
if [[ -f $AWACS_CONF ]] && (( EUID == 0 )); then
  if [[ -O $AWACS_CONF ]]; then
    _cp=$(stat -c '%a' "$AWACS_CONF" 2>/dev/null || echo 777)
    # 066 mask: no WRITE and no READ for group/others — the conf carries hotspot
    # PASSWORDS, so a world-readable 644 is as much a leak as a writable one.
    if (( (8#$_cp & 8#066) == 0 )); then
      # shellcheck source=/dev/null
      source "$AWACS_CONF"
      CONF_STATE=applied
    else
      printf 'awacs: IGNORING %s (group/world can access it — chmod 600 it)\n' "$AWACS_CONF" >&2
      CONF_STATE=mode; CONF_MODE=$_cp
    fi
    unset _cp
  else
    # Refusal must never be SILENT — a wrong-owner conf (restored from a backup as
    # pi) would otherwise just... stop applying, with nobody the wiser.
    printf 'awacs: IGNORING %s (not owned by root — chown root: it)\n' "$AWACS_CONF" >&2
    CONF_STATE=owner
  fi
elif (( EUID == 0 )); then
  CONF_STATE=missing
fi
# Every knob that fails validation below falls back to its default AND is named here (names
# only, never values): main() says the list once, so a changed value that did not apply is
# never a silent mystery.
FALLEN_KNOBS=""
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
  else eval "$_kv"; FALLEN_KNOBS+="${_k} "; fi
done
unset _kv _k
# The two clock knobs are HH:MM strings — a malformed one would crash apply_profile's
# base-10 arithmetic every tick; validate the shape, fall back to the defaults.
[[ ${NIGHT_START:-} =~ ^([01]?[0-9]|2[0-3]):[0-5][0-9]$ ]] || { NIGHT_START="22:00"; FALLEN_KNOBS+="NIGHT_START "; }
[[ ${NIGHT_END:-}   =~ ^([01]?[0-9]|2[0-3]):[0-5][0-9]$ ]] || { NIGHT_END="06:00"; FALLEN_KNOBS+="NIGHT_END "; }
# Reporting knobs: enums fall back, URLs must be plain http(s) (they land in curl argv),
# a remote target without a site is downgraded to local — and SAID once in the log.
case ${LOG_TARGET:-} in local|both|remote) ;; *) LOG_TARGET=local; FALLEN_KNOBS+="LOG_TARGET " ;; esac
case ${REPORT_WIFI:-} in auto|yes|no) ;; *) REPORT_WIFI=auto; FALLEN_KNOBS+="REPORT_WIFI " ;; esac
case ${LOG_LANG:-}  in en|ar) ;; *) LOG_LANG=en; FALLEN_KNOBS+="LOG_LANG " ;; esac
case ${SITE_LANG:-} in en|ar) ;; *) SITE_LANG=en; FALLEN_KNOBS+="SITE_LANG " ;; esac
# The three optional strings: empty is a choice, not a fault; a non-empty value that fails is.
SITE_URL=${SITE_URL:-}; PROBE_URL=${PROBE_URL:-}; SITE_TZ=${SITE_TZ:-}
[[ -z $SITE_URL  || $SITE_URL  =~ ^https?://[^[:space:]/]+(/[^[:space:]]*)?$ ]] || { SITE_URL="";  FALLEN_KNOBS+="SITE_URL "; }
[[ -z $PROBE_URL || $PROBE_URL =~ ^https?://[^[:space:]]+$ ]] || { PROBE_URL=""; FALLEN_KNOBS+="PROBE_URL "; }
[[ $SITE_TZ =~ ^[A-Za-z0-9/_+-]{0,64}$ ]] || { SITE_TZ=""; FALLEN_KNOBS+="SITE_TZ "; }
[[ ${SITE_API:-}  =~ ^[A-Za-z0-9_][A-Za-z0-9_./-]{0,63}$ && ${SITE_API:-} != *..* ]] || { SITE_API="receiver.php"; FALLEN_KNOBS+="SITE_API "; }
LT_DOWNGRADED=0
[[ -n $SITE_URL || $LOG_TARGET == local ]] || { LOG_TARGET=local; LT_DOWNGRADED=1; }
# Derived AFTER the conf so a RUN_DIR override carries all five files with it.
[[ ${RUN_DIR:-} == /* ]] || RUN_DIR=/run/awacs   # relative/empty override = nonsense
LOCK=$RUN_DIR/lock          # flock authority; also stores the daemon PID (display-only)
SCAN_CACHE=$RUN_DIR/scan
SCAN_EMPTY=$RUN_DIR/scan.empty  # consecutive fresh scans that heard NOTHING (deaf-radio tell)
SCAN_DEAF=3                     # that many in a row = the stale picture is dropped (not a knob)
SCAN_AT=$RUN_DIR/scan.at        # unix time of the last scan that really hit the radio: the scan
                                # list the site shows is published once per such scan
SPOOL=$RUN_DIR/spool        # site-log lines the outage swallowed; drained after proven health
OPEN_ID_FILE=$RUN_DIR/open_id  # crash-proof crutch marker: a respawn reaps its predecessor's
PROBE_FILE=$RUN_DIR/probe      # wget fallback needs a real file to POST
PROBE_FAIL=$RUN_DIR/probe.fail # the last upload probe accepted no bytes: up_kbps runs in a
                               # subshell, so a marker carries the verdict beside the printed 0
TRIAL_PROBE=$RUN_DIR/trial.kbps # a manual trial's probe runs in the background inside the
                                # owner's window; its kbps comes back through this file
STARTS_FILE=$RUN_DIR/starts    # starts of this boot, counted by the lock winner (tmpfs: per boot)
# The reporting channels' own state. Files, not variables: the senders run in background
# children (the live line, the wifi cell), and a child cannot carry an edge back to the loop.
SITE_DOWN=$RUN_DIR/site.down       # the site refused or did not answer a live line; the flush that delivers closes it
WIFI_DOWN=$RUN_DIR/wifi.down       # the site refused the wifi cell; the next accepted cell closes it
SCAN_DOWN=$RUN_DIR/scan.down       # the site refused the wifi scan list; the next accepted list closes it
LOG_DOWN=$RUN_DIR/log.down         # the local log could not be appended; the next successful append closes it
SPOOL_DROP=$RUN_DIR/spool.dropped  # lines the spool cap dropped since the story last went out in full
# The site's Wi-Fi menu (scan, switch, join): capture.sh relays one command line into CMD_FILE
# and sends USR1; the main loop consumes it at one point only. CMD_READY tells capture.sh the
# trap is armed (created after the lock, removed at exit); CMD_LAST dedupes a redelivered
# command by its epoch; CMD_ANSWER holds the latest answer until the site takes it (2xx);
# JOIN_ID_FILE marks a join in progress so a respawn removes an unfinished one.
CMD_FILE=$RUN_DIR/cmd
CMD_READY=$RUN_DIR/cmd.ready
CMD_LAST=$RUN_DIR/cmd.last
CMD_ANSWER=$RUN_DIR/cmd.answer
JOIN_ID_FILE=$RUN_DIR/join_id
# The device key that opens a password typed on the site (64 hex, root 600, made once with
# openssl rand) and the networks joined from the site (<hexssid>\t<psk>, root 600): both on the
# SD card, outside wpa_supplicant.conf and NetworkManager's /etc store, so the NO-BLOCK law holds.
KEY_FILE=/etc/awacs.key
NETS_FILE=/etc/awacs.networks
# Self-reboot memory lives beside the log on the SD card, because RUN_DIR is tmpfs and dies
# with the reboot: the marker says a reboot was ordered, the saved spool carries the outage
# story across it, the counter numbers the reboots of one fault.
REBOOT_MARK=${LOG_FILE}.reboot
REBOOT_SPOOL=${LOG_FILE}.spool
REBOOT_COUNT=${LOG_FILE}.reboots
readonly VERSION TICK NET_FAIL_TICKS ASSOC_WAIT PROBE_KB MIN_UP_KBPS UP_STRIKES \
         SWITCH_GAIN_PCT DANCE_COOLDOWN PREF_CHECK REBOOT_AFTER_MIN OPEN_NETWORKS \
         NIGHT_MODE NIGHT_START NIGHT_END NIGHT_MIN_UP_KBPS NIGHT_GAIN_PCT \
         NIGHT_DANCE_COOLDOWN STEALTH_MODE DEBUG LOG_FILE LOG_CAP RUN_DIR LOCK \
         SCAN_CACHE SCAN_EMPTY SCAN_DEAF SCAN_AT SCAN_TTL SPOOL SPOOL_CAP OPEN_ID_FILE PROBE_FILE PROBE_FAIL TRIAL_PROBE SAFETY_NET \
         STREAM_MIN_KBPS SITE_URL LOG_TARGET PROBE_URL REPORT_WIFI SITE_TZ SITE_API \
         LOG_LANG SITE_LANG STARTS_FILE REBOOT_MARK REBOOT_SPOOL REBOOT_COUNT \
         SITE_DOWN WIFI_DOWN SCAN_DOWN LOG_DOWN SPOOL_DROP \
         CMD_FILE CMD_READY CMD_LAST CMD_ANSWER JOIN_ID_FILE KEY_FILE NETS_FILE
# Outage-verdict patience (internal, sealed after the conf so no typo can reach them).
# A loaded uplink answers LATE, not never: a saturated upload on a slow hotspot holds
# ICMP and small HTTP replies past the quick ladder's 2-3 s. NET_ALIVE_BYTES: bytes the
# device ITSELF SENT while the quick ladder was failing (7-10 s) - about 13-19 kbps, far
# above the ladder's own packets (under 4 KB) and untouched by incoming LAN chatter; an
# upload's ACK stream alone clears it. Only then is a failed quick check excused by one
# patient look: 3 pings 0.3 s apart per target (a bloated queue drops single packets).
readonly NET_PATIENT_PING_W=5 NET_PATIENT_HTTP=8 NET_PATIENT_PINGS=3 NET_ALIVE_BYTES=16384
WIFI_CMD=0       # a site command waits in CMD_FILE: set by the USR1 trap alone, read at the loop top
LOCK_WON=0       # this process holds the lock: only it may create and remove CMD_READY
FIGHT_STREAK=0   # fights entered since the last healthy tick (the loop and the boot path count)
PATIENT_FAILED=0 # a patient look already failed in this streak - never pay for it twice
DELIBERATE_EXIT=0  # set before every exit AWACS means (the goodbye, the lock loser, the nm_lame
                   # restart): the EXIT trap then stays quiet
REBOOTING=0        # set by reboot_memory_save: the TERM that follows `reboot` is not a stop

# Day/night mutables (apply_profile switches them; consumers read only CUR_*)
CUR_MIN_UP=$MIN_UP_KBPS
CUR_GAIN=$SWITCH_GAIN_PCT
CUR_COOLDOWN=$DANCE_COOLDOWN
PROFILE=""

# ------------------------------- identity -------------------------------------
require_root() {
  (( EUID == 0 )) && return 0
  # The terminal box below is kept exactly as it is: its spacing is tuned for real
  # Arabic+emoji terminal rendering, so do not reflow it.
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
device_id() {  # resolved LAZILY: a boot script may write /tmp/device_id AFTER we launch.
  # grep -m1 .: an empty or blank-first-line file falls through to the hostname.
  # VALIDATED before use: the file lives in world-writable /tmp and its bytes land in
  # a root terminal and an outbound URL — only a plain slug passes.
  local d
  d="${DEVICE_ID:-$(grep -m1 . /tmp/device_id 2>/dev/null)}"
  [[ $d =~ ^[A-Za-z0-9_-]{1,32}$ ]] || d=$(hostname -s 2>/dev/null)
  [[ $d =~ ^[A-Za-z0-9_-]{1,32}$ ]] || d=device
  echo "$d"
}
site()      { echo "${SITE_URL%/}/$(device_id)"; }   # meaningful only when SITE_URL is set
api_url()   { echo "$(site)/${SITE_API}"; }          # the endpoint every site request targets
remote_on() { [[ -n $SITE_URL && $LOG_TARGET != local ]]; }   # story lines + Wi-Fi cell go to the site
probe_url() {  # where upload probes POST to; empty = no measurement possible (signal mode)
  if [[ -n $PROBE_URL ]]; then echo "$PROBE_URL"
  elif [[ -n $SITE_URL ]]; then api_url; fi
}
probe_on()  { [[ -n $PROBE_URL || -n $SITE_URL ]]; }
# SIGNAL MODE (probe_on false): the measured-upload law has nothing to measure with, so
# the daemon is a connectivity supervisor only — fight when the internet is lost (the
# strongest visible known network that delivers wins), go home when home is visible;
# no QA strikes, no dance, no "too slow" veto. The story lines say so instead of "0 kbps".
up_words()    { if probe_on; then echo "upload $1 kbps"; else echo "signal mode"; fi; }
up_words_ar() { if probe_on; then echo "رفع $1 كيلوبت/ث"; else echo "وضع الإشارة"; fi; }
stamp()     { if [[ -n $SITE_TZ ]]; then TZ=$SITE_TZ date "$@"; else date "$@"; fi; }
# ts - the one timestamp for every line, local and remote: RFC 3339 with the UTC offset, in
# SITE_TZ. The same shape the camera scripts write, so one log page reads both.
ts()        { stamp '+%Y-%m-%dT%H:%M:%S%:z'; }

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
log() { log_at "$(ts)" "$@"; }   # LEVEL MSG - local file, rotated; never blocks on the network
log_at() {  # STAMP LEVEL MSG - log() with the stamp supplied, so a line bound for the site
  # too carries one instant to both sinks. A missing message is written empty, never an error.
  # A failed append raises the log.down marker (a file: log_at also runs inside the wifi-cell
  # and install children) and log_down_check says it to the site from the main loop; the next
  # append that succeeds lowers it. The logger itself never speaks, so nothing can recurse.
  if printf '%s [%s] %s\n' "${1:-}" "${2:-}" "${3:-}" 2>/dev/null >>"$LOG_FILE"; then   # 2> first: a
    [[ -e $LOG_DOWN ]] && rm -f "$LOG_DOWN" 2>/dev/null                                    # dead file must not print
  else
    [[ -e $LOG_DOWN ]] || : 2>/dev/null >"$LOG_DOWN" || :
  fi
  local n; n=$(wc -l 2>/dev/null <"$LOG_FILE" || echo 0)
  if (( n > LOG_CAP + 200 )); then
    tail -n "$LOG_CAP" "$LOG_FILE" >"${LOG_FILE}.t" 2>/dev/null && mv -f "${LOG_FILE}.t" "$LOG_FILE"
  fi
}
dbg() { [[ $DEBUG == yes ]] && log DEBUG "$1"; return 0; }  # return 0: a false && must never trip callers

net_up=0  # last verdict; connect_id/fight set it the moment internet is verified

# A recovery runs again every tick while the internet is down, and each run repeats the same
# steps: the same candidates tried and refused for the same reason, the same verdict on the
# outage. Each step is said the first time it happens in an outage and counted after that;
# when the internet is back, one line per step says how many more times it happened. Nothing
# is left unsaid, and a long outage cannot bury its own opening under a hundred repeats.
declare -A ONCE_SAID=() ONCE_MORE=() ONCE_EN=() ONCE_AR=() ONCE_LAST=()
say_once() {  # KEY LEVEL EN_MSG AR_MSG — the first time in this outage speaks; the rest count
  if [[ -z ${ONCE_SAID[$1]:-} ]]; then
    ONCE_SAID[$1]=1; ONCE_EN[$1]=$3; ONCE_AR[$1]=$4
    site_log "$2" "$3" "$4"
  else
    ONCE_MORE[$1]=$(( ${ONCE_MORE[$1]:-0} + 1 )); ONCE_LAST[$1]=$(stamp +%H:%M)
  fi
}
once_report() {  # the outage is over: say the counts with the last time each step repeated,
  # then forget the outage (a step that stopped repeating hours ago reads differently from one
  # that lasted to the end)
  local k en ar
  for k in "${!ONCE_MORE[@]}"; do
    en=${ONCE_EN[$k]}; ar=${ONCE_AR[$k]}
    en=${en// (round [0-9])/}; ar=${ar// (جولة [0-9])/}   # the count spans rounds
    site_log INFO "repeated ${ONCE_MORE[$k]} more times during the outage (last at ${ONCE_LAST[$k]:-?}): ${en}" \
                  "تكرر ${ONCE_MORE[$k]} مرة زيادة خلال الانقطاع (آخرها ${ONCE_LAST[$k]:-?}): ${ar}"
  done
  ONCE_SAID=(); ONCE_MORE=(); ONCE_EN=(); ONCE_AR=(); ONCE_LAST=()
}
llog() {  # LEVEL EN_MSG AR_MSG — a LOCAL-ONLY story line in the language LOG_LANG asks for
  if [[ $LOG_LANG == ar ]]; then log "$1" "$3"; else log "$1" "$2"; fi
}

site_log() {  # LEVEL EN_MSG [AR_MSG] — one story line, two audiences: the local file in
  # LOG_LANG and the site in SITE_LANG (a line with no Arabic text falls back to English).
  # A failed live send self-spools; offline lines spool directly — the outage's own story
  # reaches the site after recovery, in order, nothing lost.
  # LOG_TARGET=remote: the local file keeps only the alarming levels (WARN/ERROR)
  local en=$2 ar=${3:-$2} local_txt site_txt now
  if [[ $LOG_LANG == ar ]]; then local_txt=$ar; else local_txt=$en; fi
  if [[ $SITE_LANG == ar ]]; then site_txt=$ar; else site_txt=$en; fi
  now=$(ts)   # one stamp for both sinks
  if [[ $LOG_TARGET != remote || $1 == WARN || $1 == ERROR ]]; then log_at "$now" "$1" "$local_txt"; fi
  remote_on || return 0   # local-only deployment: the story stays in the local log
  # Same shape as the camera scripts: stamp, level, source tag, text. The log page groups by
  # the tag, so these lines land under WiFi and align in the time column.
  local line
  line="${now} [$1][awacs] ${site_txt}"
  # SITE_MODE, set by the two wrappers below (auto otherwise): hold = the line waits in the
  # spool whatever net_up says (the refusal notice rides with the refused line); now = sent
  # in the foreground and never held (the flush's own lines cannot chase themselves).
  if [[ ${SITE_MODE:-auto} == now ]]; then
    site_send "$line" || :
  elif [[ ${SITE_MODE:-auto} == hold ]] || (( ! net_up )); then
    spool_put "$line"
  else
    # Group-level >/dev/null: the async child must not inherit a caller's command-
    # substitution pipe, or $(scan) waits up to 4s for this sender to exit (proven).
    { site_live "$line"; } >/dev/null 2>&1 9>&- &
  fi
}
site_hold() { SITE_MODE=hold site_log "$@"; }   # LEVEL EN [AR]: held for the next flush
site_now()  { SITE_MODE=now  site_log "$@"; }   # LEVEL EN [AR]: sent in the foreground, never held

SITE_CODE=000 HTTP_EN="" HTTP_AR=""
site_send() {  # $1 = one site line: the POST every sender shares. SITE_CODE <- the reply
  # (000 = no reply within the 4 s limit); true on the replies the old -f accepted (under 400).
  SITE_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 --data-urlencode "file=log/log.txt" \
                --data-urlencode "data=$1" "$(api_url)" 2>/dev/null) || SITE_CODE=000
  [[ $SITE_CODE =~ ^[23][0-9][0-9]$ ]]
}
http_words() {  # HTTP_EN/HTTP_AR <- one reply in words: "http 500", or no reply at all (curl's 000)
  if [[ ${1:-000} == 000 ]]; then HTTP_EN="no reply in 4 s"; HTTP_AR="لا جواب خلال 4 ثوانٍ"
  else HTTP_EN="http $1"; HTTP_AR="http $1"; fi
}
site_live() {  # $1 = one site line, inside the background child site_log forks: sent now, or
  # held in the spool for the next flush. The first refusal of an episode is said once.
  site_send "$1" && return 0
  spool_put "$1"
  site_refused
}
site_refused() {  # the site refused or did not answer a line while the internet was up: said once
  # per episode through a marker (the sender is usually a background child, so a variable
  # cannot carry the edge). The notice waits with the refused line; the flush that delivers
  # them closes the episode and removes the marker.
  [[ -e $SITE_DOWN ]] && return 0
  : >"$SITE_DOWN" 2>/dev/null || :
  http_words "$SITE_CODE"
  local m=$(( TICK * 30 / 60 )); (( m < 1 )) && m=1   # the flush cadence: every 30 healthy ticks
  site_hold WARN "site did not take the log line (${HTTP_EN}) - holding lines, delivery retried about every ${m} min" \
                 "الموقع ما استلم سطر السجل (${HTTP_AR}) - نحتفظ بالأسطر ونعيد الإرسال كل ${m} دقائق تقريباً"
}
spool_put() {  # $1 = one site line -> the spool. The cap runs in the main shell only: a background
  # child (the live sender, the wifi cell) appends and leaves, so no trim can race the flush's
  # snapshot, and every dropped line is counted for the "outage story trimmed" line.
  printf '%s\n' "$1" >>"$SPOOL" 2>/dev/null || :
  (( BASHPID == $$ )) || return 0
  local n; n=$(wc -l <"$SPOOL" 2>/dev/null || echo 0)
  if (( n > SPOOL_CAP )); then
    # PIN line 1: the outage's opening banner carries the "when it began" stamp —
    # a capped story keeps its head AND its newest tail (middle chatter is what
    # rolls off). head+tail can never duplicate: tail starts at line 3 or later.
    spool_drop_add $(( n - SPOOL_CAP ))
    { head -n 1 "$SPOOL"; tail -n $(( SPOOL_CAP - 1 )) "$SPOOL"; } >"${SPOOL}.t" 2>/dev/null \
      && mv -f "${SPOOL}.t" "$SPOOL"
  fi
}
spool_drop_add() {  # $1 = lines this trim dropped, added to the counter file (it outlives a respawn,
  # whose first flush delivers the predecessor's story and says its drops too)
  local n=0
  read -r n 2>/dev/null <"$SPOOL_DROP" || n=0
  [[ $n =~ ^[0-9]+$ ]] || n=0
  printf '%d\n' "$(( n + $1 ))" >"$SPOOL_DROP" 2>/dev/null || :
}

readonly STOP_DRAIN_LINES=6 STOP_DRAIN_SECS=20   # the stop's drain budget: 6 lines or 20 s (curl waits
                                                 # up to 4 s each) inside the unit's TimeoutStopSec of 40 s
flush_spool() {  # $1 = quiet (the stop's own flush: the plain delivery line is skipped, the drain is
  # bounded by the budget above) | start (the boot flush of a start with no story to deliver: the
  # plain line is skipped, nothing is bounded). The line that closes a refusal episode is never
  # skipped. Deliver the outage story in order, duplicate-proof:
  # SNAPSHOT via atomic mv (async appenders start a fresh spool untouched), count what was sent,
  # merge only the UNSENT remainder back IN FRONT of new lines, capped. Honest limit:
  # an append landing in the final merge instant can be lost — one log line, accepted;
  # a lock here would let a hung flush block the fight, and reachability outranks logs.
  # The page shows file order, so the held lines land with older stamps under newer live ones:
  # the delivery is then said in the foreground, after them, naming how many and from when.
  remote_on || return 0
  [[ -s $SPOOL ]] || { rm -f "$SITE_DOWN" 2>/dev/null; return 0; }   # nothing held: no episode open
  mv -f "$SPOOL" "${SPOOL}.sending" 2>/dev/null || return 0
  local l sent=0 all=1 first="" last="" closing=0 bounded=0 t0=$SECONDS
  [[ ${1:-} == quiet ]] && bounded=1
  [[ -e $SITE_DOWN ]] && closing=1   # read before the loop: a refusal inside it must not close itself
  while IFS= read -r l; do
    # The stop's drain must end inside TimeoutStopSec: past the budget the rest stays held (all=0
    # keeps the refusal episode open and the trim count unsaid) and the next start delivers it.
    if (( bounded && (sent >= STOP_DRAIN_LINES || SECONDS - t0 >= STOP_DRAIN_SECS) )); then
      all=0
      llog INFO "stop drain reached its budget - the remaining held lines wait for the next start" \
                "تفريغ الإيقاف وصل حدّه - بقية الأسطر المحفوظة تنتظر التشغيل القادم"
      break
    fi
    if site_send "$l"; then
      (( ++sent == 1 )) && first=${l:11:5}   # HH:MM of the RFC 3339 stamp every spool line opens with
      last=${l:11:5}
    else
      all=0; site_refused; break
    fi
  done <"${SPOOL}.sending"
  { tail -n +$(( sent + 1 )) "${SPOOL}.sending" 2>/dev/null; cat "$SPOOL" 2>/dev/null; } >"${SPOOL}.t" || :
  if [[ -s ${SPOOL}.t ]]; then
    local n; n=$(wc -l <"${SPOOL}.t" 2>/dev/null || echo 0)
    if (( n > SPOOL_CAP )); then  # same head-pin as site_log's cap: keep the opening line
      spool_drop_add $(( n - SPOOL_CAP ))
      { head -n 1 "${SPOOL}.t"; tail -n $(( SPOOL_CAP - 1 )) "${SPOOL}.t"; } >"$SPOOL" 2>/dev/null || :
    else
      cat "${SPOOL}.t" >"$SPOOL" 2>/dev/null || :
    fi
  fi
  rm -f "${SPOOL}.sending" "${SPOOL}.t"
  (( all && closing )) && rm -f "$SITE_DOWN" 2>/dev/null
  (( sent )) && say_delivered "$sent" "$first" "$last" "$(( all && closing ))" "${1:-}"
  (( all )) && say_trimmed
  return 0
}
say_delivered() {  # $1 = lines delivered, $2/$3 = HH:MM of the first and the last, $4 = 1 when the
  # delivery ends a site refusal episode, $5 = quiet (the plain line is skipped). Sent in the
  # foreground after the lines it counts, so they stand above it on the page.
  local first=$2 last=$3 held held_ar where where_ar
  [[ $first =~ ^[0-9]{2}:[0-9]{2}$ ]] || first="?"
  [[ $last  =~ ^[0-9]{2}:[0-9]{2}$ ]] || last="?"
  if (( $1 == 1 )); then
    held="1 held line stamped ${first}"; held_ar="سطراً واحداً محفوظاً بطابع ${first}"
    where="it stands above this line with its own time"; where_ar="يظهر فوق هذا السطر بوقته"
  else
    held="$1 held lines stamped ${first} to ${last}"; held_ar="$1 سطراً محفوظاً بطوابع من ${first} إلى ${last}"
    where="they stand above this line with their own times"; where_ar="تظهر فوق هذا السطر بأوقاتها"
  fi
  if (( $4 )); then
    site_now OK "site reachable again - delivered ${held}, ${where}" \
                "الموقع رجع يستلم - أرسلنا ${held_ar}، ${where_ar}"
  elif [[ -z ${5:-} ]]; then
    site_now INFO "delivered ${held} - ${where}" \
                  "أرسلنا ${held_ar} - ${where_ar}"
  fi
}
say_trimmed() {  # the story is out in full: the lines the cap dropped on the way, said once, forgotten
  local n=0
  [[ -e $SPOOL_DROP ]] || return 0
  read -r n 2>/dev/null <"$SPOOL_DROP" || n=0
  rm -f "$SPOOL_DROP" 2>/dev/null || :
  [[ $n =~ ^[1-9][0-9]*$ ]] || return 0
  site_now WARN "outage story trimmed - ${n} lines dropped from its middle (the spool keeps ${SPOOL_CAP})" \
                "قُصّت قصة الانقطاع - سقط ${n} سطر من وسطها (المخزن يحفظ ${SPOOL_CAP})"
}
LOG_DOWN_SAID=0
log_down_check() {  # a healthy tick: the local file's state, said on the change only. log_at raises
  # the marker and cannot speak (it is the logger); this says it to the site once per failure
  # streak, and says the recovery once when an append succeeds again.
  if [[ -e $LOG_DOWN ]]; then
    (( LOG_DOWN_SAID )) && return 0
    LOG_DOWN_SAID=1
    site_log WARN "local log ${LOG_FILE} not writable - SD card read-only? the site keeps the story" \
                  "سجل الجهاز ${LOG_FILE} غير قابل للكتابة - بطاقة SD للقراءة فقط؟ الموقع يحفظ القصة"
  elif (( LOG_DOWN_SAID )); then
    LOG_DOWN_SAID=0
    site_log OK "local log ${LOG_FILE} writable again" \
                "سجل الجهاز ${LOG_FILE} رجع يقبل الكتابة"
  fi
}

# ------------------------------- start-up story --------------------------------
# Small tellers the start block and the loop share. Each speaks once per start, once per
# state change or once per step; none of them runs per tick without a change to report.
dur_words() {  # $1 = seconds -> "45 s" | "3 min" | "2 h 15 min" | "3 d 4 h"
  local s=$1
  [[ $s =~ ^[0-9]+$ ]] || s=0
  if (( s < 60 )); then printf '%d s' "$s"
  elif (( s < 3600 )); then printf '%d min' "$(( s / 60 ))"
  elif (( s < 86400 )); then printf '%d h %d min' "$(( s / 3600 ))" "$(( s % 3600 / 60 ))"
  else printf '%d d %d h' "$(( s / 86400 ))" "$(( s % 86400 / 3600 ))"; fi
}
dur_words_ar() {  # the Arabic twin of dur_words
  local s=$1
  [[ $s =~ ^[0-9]+$ ]] || s=0
  if (( s < 60 )); then printf '%d ثانية' "$s"
  elif (( s < 3600 )); then printf '%d دقيقة' "$(( s / 60 ))"
  elif (( s < 86400 )); then printf '%d ساعة %d دقيقة' "$(( s / 3600 ))" "$(( s % 3600 / 60 ))"
  else printf '%d يوم %d ساعة' "$(( s / 86400 ))" "$(( s % 86400 / 3600 ))"; fi
}
uptime_s() {  # whole seconds since boot (builtin read; /proc/uptime is space-separated)
  local u=0
  IFS=' ' read -r u _ 2>/dev/null </proc/uptime || u=0
  u=${u%%.*}; [[ $u =~ ^[0-9]+$ ]] || u=0
  printf '%s' "$u"
}
router_tell() {  # ROUTER_EN/ROUTER_AR <- what the router does at a loss: it still answers (the
  # outage is upstream), it is silent too, or there is no association at all
  if link_alive; then ROUTER_EN="still answers"; ROUTER_AR="يرد"
  elif [[ -n $(assoc_ssid) ]]; then ROUTER_EN="silent too"; ROUTER_AR="لا يرد أيضاً"
  else ROUTER_EN="none (not associated)"; ROUTER_AR="لا يوجد (غير مرتبط)"; fi
}

say_start() {  # the first line of every start: the documented head, then the backend and whether
  # this is the boot's first start (a "restart" three days into uptime means the daemon died
  # and the launcher brought it back). START_N is counted at the lock, so a loser never counts.
  local be tail_en tail_ar n=${START_N:-1}
  if [[ $BACKEND == wpa ]]; then be=wpa; else be=NetworkManager; fi
  if (( n <= 1 )); then
    tail_en="first start of this boot, up $(dur_words "$(uptime_s)")"
    tail_ar="أول تشغيل في هذا الإقلاع، الجهاز شغال منذ $(dur_words_ar "$(uptime_s)")"
  else
    tail_en="restart $(( n - 1 )) of this boot"
    tail_ar="إعادة تشغيل رقم $(( n - 1 )) في هذا الإقلاع"
  fi
  site_log INFO "AWACS ${VERSION} starting on ${IF} (device $(device_id)) - ${be} backend, ${tail_en}" \
                "أواكس ${VERSION} بدأ العمل على ${IF} - الخلفية ${be}، ${tail_ar}"
}

say_settings() {  # once per start, after the local "reporting:" line: the settings file verdict
  # and the knobs that fell back (names only), the cell asked for without a site, the time
  # zone, the device id, then the "running with" summary that explains every later line.
  # Numbers, enum words and counts only: no URL, no name from SAFETY_NET, no password.
  local -a fl=()
  local fallen n
  case $CONF_STATE in
    missing) site_log WARN "settings file ${AWACS_CONF} not found - running on built-in defaults (no site, no emergency networks)" \
                           "ملف الإعدادات ${AWACS_CONF} غير موجود - نعمل على القيم الافتراضية (بلا موقع ولا شبكات طوارئ)" ;;
    mode)    site_log WARN "settings file ${AWACS_CONF} ignored: mode ${CONF_MODE}, chmod 600 it - running on built-in defaults (no site, no emergency networks)" \
                           "ملف الإعدادات ${AWACS_CONF} مُهمَل: الوضع ${CONF_MODE}، اضبطه 600 - نعمل على القيم الافتراضية (بلا موقع ولا شبكات طوارئ)" ;;
    owner)   site_log WARN "settings file ${AWACS_CONF} ignored: not owned by root, chown root: it - running on built-in defaults (no site, no emergency networks)" \
                           "ملف الإعدادات ${AWACS_CONF} مُهمَل: ليس مملوكاً للجذر، اجعله للجذر - نعمل على القيم الافتراضية (بلا موقع ولا شبكات طوارئ)" ;;
  esac
  if [[ -n $FALLEN_KNOBS ]]; then
    IFS=' ' read -r -a fl <<<"$FALLEN_KNOBS"
    n=${#fl[@]}; fallen=${FALLEN_KNOBS% }; fallen=${fallen// /, }
    site_log WARN "settings file ${AWACS_CONF} applied, but ${n} values failed validation and use their defaults: ${fallen}" \
                  "طُبّق ملف الإعدادات ${AWACS_CONF} لكن ${n} قيمة فشلت في التحقق واستُخدمت قيمها الافتراضية: ${fallen}"
  fi
  [[ $REPORT_WIFI == yes && -z $SITE_URL ]] \
    && site_log WARN "wifi cell asked for (REPORT_WIFI=yes) but SITE_URL is empty - nothing to publish to" \
                     "طُلبت خانة الواي فاي (REPORT_WIFI=yes) لكن SITE_URL فارغ - لا مكان للنشر"
  say_tz_check
  say_devid_check
  say_running_with
}

say_tz_check() {  # SITE_TZ passed the shape check but names a zone this device does not have:
  # glibc then stamps UTC without a word. Area/City names only (a POSIX string such as
  # KST-3 needs no file), and a missing zoneinfo tree means tzdata itself is absent.
  [[ -n $SITE_TZ && $SITE_TZ == */* ]] || return 0
  local why_en why_ar
  if [[ ! -d /usr/share/zoneinfo ]]; then why_en="tzdata not installed"; why_ar="tzdata غير منزّلة"
  elif [[ ! -f /usr/share/zoneinfo/$SITE_TZ ]]; then why_en="no such zone"; why_ar="لا توجد منطقة بهذا الاسم"
  else return 0; fi
  site_log WARN "time zone ${SITE_TZ} is unknown on this device (${why_en}) - stamps fall back to UTC" \
                "المنطقة الزمنية ${SITE_TZ} غير معروفة على الجهاز (${why_ar}) - الطوابع تصير بتوقيت UTC"
}

DEVID_SEEN=""   # the id the story reports under, remembered so a change mid-run is said once
say_devid_check() {  # a device id that is PRESENT but fails the slug check falls to the hostname
  # in silence today (an absent id is the documented design and stays silent). Source and
  # value are named, control bytes stripped and 40 characters kept: /tmp is world-writable.
  local raw="" src=""
  if [[ -n ${DEVICE_ID:-} ]]; then raw=$DEVICE_ID; src=DEVICE_ID
  else raw=$(grep -m1 . /tmp/device_id 2>/dev/null) || raw=""; [[ -n $raw ]] && src=/tmp/device_id; fi
  DEVID_SEEN=$(device_id)
  [[ -n $src && ! $raw =~ ^[A-Za-z0-9_-]{1,32}$ ]] || return 0
  raw=$(printf '%s' "$raw" | tr -d '\000-\037\177'); raw=${raw:0:40}
  site_log WARN "device id not usable (${src}: ${raw}) - reporting as ${DEVID_SEEN}" \
                "معرّف الجهاز غير صالح (${src}: ${raw}) - نبلّغ باسم ${DEVID_SEEN}"
}
devid_change_check() {  # the cell cadence: a boot script may write /tmp/device_id after launch
  # (the documented late-write case) and the story then lands in another folder - say which
  local d; d=$(device_id)
  [[ $d == "$DEVID_SEEN" ]] && return 0
  site_log INFO "device id changed: ${DEVID_SEEN} -> ${d} - reporting under ${d} from now" \
                "تغيّر معرّف الجهاز: ${DEVID_SEEN} -> ${d} - نبلّغ تحت ${d} من الآن"
  DEVID_SEEN=$d
}

say_running_with() {  # the effective settings in one INFO line, measured or signal mode
  local cell cell_ar open open_ar zone zone_ar stored emerg floors floors_ar cool
  stored=$(known_ids | cut -f1 | sort -u | grep -c .) || stored=0
  emerg=${#SAFETY_NET[@]}
  if [[ $OPEN_NETWORKS == yes ]]; then open=yes; open_ar=نعم; else open=no; open_ar=لا; fi
  if [[ $REPORT_WIFI == no ]]; then cell="off (REPORT_WIFI=no)"; cell_ar="معطّلة (REPORT_WIFI=no)"
  elif [[ -z $SITE_URL ]]; then cell="off (no SITE_URL)"; cell_ar="معطّلة (بلا SITE_URL)"
  elif [[ $REPORT_WIFI == auto ]] && ! remote_on; then cell="off (auto with LOG_TARGET local)"; cell_ar="معطّلة (auto مع LOG_TARGET محلي)"
  else cell=on; cell_ar=مفعّلة; fi
  zone=${SITE_TZ:-the device zone}; zone_ar=${SITE_TZ:-توقيت الجهاز}
  if probe_on; then
    if [[ $NIGHT_MODE == yes ]]; then
      floors="floor ${MIN_UP_KBPS}/${NIGHT_MIN_UP_KBPS} kbps day/night (night ${NIGHT_START}-${NIGHT_END})"
      floors_ar="حد الرفع ${MIN_UP_KBPS}/${NIGHT_MIN_UP_KBPS} كيلوبت/ث نهاراً/ليلاً (الليل ${NIGHT_START}-${NIGHT_END})"
    else
      floors="floor ${MIN_UP_KBPS} kbps (night profile off)"
      floors_ar="حد الرفع ${MIN_UP_KBPS} كيلوبت/ث (الوضع الليلي معطّل)"
    fi
    cool=$(( (DANCE_COOLDOWN + 59) / 60 ))
    site_log INFO "running with: measured mode, ${floors}, switch gain ${SWITCH_GAIN_PCT}%, one evaluation per ${cool} min, reboot after ${REBOOT_AFTER_MIN} min wedged, wifi cell ${cell}, ${stored} stored networks, ${emerg} emergency, open networks ${open}, stamps in ${zone}" \
                  "نعمل بـ: وضع القياس، ${floors_ar}، ربح التبديل ${SWITCH_GAIN_PCT}%، تقييم واحد كل ${cool} دقيقة، إعادة تشغيل بعد ${REBOOT_AFTER_MIN} دقيقة تعطّل، خانة الواي فاي ${cell_ar}، ${stored} شبكة مخزنة، ${emerg} طوارئ، الشبكات المفتوحة ${open_ar}، التوقيت ${zone_ar}"
  else
    site_log INFO "running with: signal mode (no probe target - networks chosen by signal), reboot after ${REBOOT_AFTER_MIN} min wedged, wifi cell ${cell}, ${stored} stored networks, ${emerg} emergency, open networks ${open}, stamps in ${zone}" \
                  "نعمل بـ: وضع الإشارة (لا هدف للقياس - نختار الشبكة بقوة الإشارة)، إعادة تشغيل بعد ${REBOOT_AFTER_MIN} دقيقة تعطّل، خانة الواي فاي ${cell_ar}، ${stored} شبكة مخزنة، ${emerg} طوارئ، الشبكات المفتوحة ${open_ar}، التوقيت ${zone_ar}"
  fi
}

say_rfkill() {  # a radio that boots blocked: the soft block is lifted here, as before, and now
  # said once (its cause is an unset WLAN country or a saved rfkill state, both fixable for
  # good); a hard block is a switch on the hardware that no command can move.
  local list; list=$(rfkill list wifi 2>/dev/null) || list=""
  rfkill unblock wifi 2>/dev/null || :  # a box that BOOTS soft-blocked must not wait a fight cycle
  [[ $BACKEND != wpa ]] && { nmcli radio wifi on >/dev/null 2>&1 || :; }  # NM owns soft-rfkill
  [[ $list == *"Soft blocked: yes"* ]] \
    && site_log WARN "wifi radio was soft-blocked at start - unblocked (a WLAN country not set, or a saved rfkill state)" \
                     "راديو الواي فاي كان محجوباً برمجياً عند البدء - رفعنا الحجب (بلد الواي فاي غير مضبوط، أو حالة rfkill محفوظة)"
  [[ $list == *"Hard blocked: yes"* ]] \
    && site_log WARN "wifi radio is hard-blocked - a hardware switch, AWACS cannot unblock it" \
                     "راديو الواي فاي محجوب عتادياً - مفتاح في الجهاز، أواكس ما يقدر يرفعه"
  return 0
}

CLK_WALL=0 CLK_MONO=0
clock_step_check() {  # one tick: the wall clock against the monotonic clock. A Pi has no RTC, so
  # the first time sync of a boot steps the clock by the time the box was off, and every line
  # before it carries the old time. A step is a gap beyond 60 s between two ticks; said once.
  local wall mono diff dir_en dir_ar
  wall=$(date +%s); mono=$(uptime_s)
  [[ $wall =~ ^[0-9]+$ ]] || return 0
  if (( CLK_WALL > 0 )); then
    diff=$(( (wall - CLK_WALL) - (mono - CLK_MONO) ))
    if (( diff > 60 || diff < -60 )); then
      if (( diff > 0 )); then dir_en=forward; dir_ar=للأمام; else dir_en=back; dir_ar=للخلف; diff=$(( -diff )); fi
      site_log INFO "clock set ${dir_en} $(dur_words "$diff") by time sync - the lines above carry the old time" \
                    "ضُبطت الساعة ${dir_ar} $(dur_words_ar "$diff") بمزامنة الوقت - الأسطر أعلاه تحمل الوقت القديم"
    fi
  fi
  CLK_WALL=$wall; CLK_MONO=$mono
}

# ------------------------------- self-reboot memory ----------------------------
# fight() reboots the device after REBOOT_AFTER_MIN of device-side evidence. The outage story
# sits in the tmpfs spool (net_up=0) and would die with the reboot, and the next start would
# read like a power cut. reboot_memory_save writes the ERROR line, the marker, the fault's
# reboot count and a copy of the spool to the SD card; reboot_memory_restore puts the story
# back in front of the next start's lines and say_after_reboot names the reboot as AWACS's.
TELL_EN="" TELL_AR=""
wedge_tell() {  # TELL_EN/TELL_AR <- which device-side tell holds at the reboot moment
  local names="" id ssid n
  if [[ -z $(scan) ]]; then
    TELL_EN="the radio hears no network at all"; TELL_AR="الراديو ما يسمع أي شبكة"
  elif [[ -z $(known_ids) ]]; then
    TELL_EN="the stored network list reads empty"; TELL_AR="قائمة الشبكات المحفوظة فاضية"
  else
    while IFS=$'\t' read -r id ssid; do
      [[ -n $id ]] || continue
      n=$(disp_ssid "$id" "$ssid"); names+="${names:+, }${n:-$id}"
    done < <(visible_known_ids)
    TELL_EN="${names:-stored networks} on the air but this device cannot join"
    TELL_AR="${names:-الشبكات المحفوظة} ظاهرة بس الجهاز ما يقدر يرتبط بها"
  fi
}
reboot_memory_save() {  # the last act before `reboot`: the caller runs sync; sleep 2; reboot
  local n=0 stamp bid
  wedge_tell
  read -r n 2>/dev/null <"$REBOOT_COUNT" || n=0   # 2> first: a missing file must not print
  [[ $n =~ ^[0-9]+$ ]] || n=0
  n=$(( n + 1 ))
  REBOOTING=1
  net_up=0   # the net is down; the line must spool so the saved copy carries it
  site_log ERROR "rebooting now: wedged ${REBOOT_AFTER_MIN} min (${TELL_EN}) - reboot ${n} for this fault, the story continues after the boot" \
                 "إعادة تشغيل الآن: متعطّل ${REBOOT_AFTER_MIN} دقيقة (${TELL_AR}) - إعادة التشغيل رقم ${n} لهذا العطل، والقصة تكمل بعد الإقلاع"
  stamp=$(stamp '+%Y-%m-%d %H:%M'); bid=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null) || bid=""
  # Still alive 60 s from now = the reboot command failed: the loop's reboot_failed_check
  # says so and releases REBOOTING (the same check a respawn in the same boot runs).
  # A grace already running keeps its stamp and its start: restarting it at every losing
  # fight kept the failure line from ever coming.
  (( RB_SAME )) || { RB_STAMP=$stamp; RB_SAME=1; RB_AT=$(uptime_s); }
  { printf '%s\n' "$n" >"$REBOOT_COUNT"
    printf '%s\t%s\t%s\t%s\t%s\n' "$stamp" "$FIGHT_STREAK" "$bid" "$TELL_EN" "$TELL_AR" >"$REBOOT_MARK"
    cat "${SPOOL}.sending" "$SPOOL" 2>/dev/null >"$REBOOT_SPOOL"
  } 2>/dev/null || :
}
reboot_memory_clear() { [[ -e $REBOOT_COUNT ]] && rm -f "$REBOOT_COUNT" 2>/dev/null; return 0; }  # a healthy tick ends the fault
RB_STAMP="" RB_RUNS=0 RB_SAME=0 RB_AT=0 RB_TELL_EN="" RB_TELL_AR=""   # RB_AT: uptime second the grace began
reboot_memory_restore() {  # first act of main(): a marker means the previous daemon ordered a
  # reboot. A new boot_id: the saved story goes in front of the spool. The same boot_id: the
  # tmpfs spool still holds the story (no duplicate restored) and reboot_failed_check decides
  # after 60 s alive whether the reboot command failed.
  [[ -s $REBOOT_MARK ]] || { rm -f "$REBOOT_SPOOL" 2>/dev/null; return 0; }
  local bid
  IFS=$'\t' read -r RB_STAMP RB_RUNS bid RB_TELL_EN RB_TELL_AR <"$REBOOT_MARK" || :
  [[ $RB_RUNS =~ ^[0-9]+$ ]] || RB_RUNS=0
  if [[ -n $bid && $bid == "$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)" ]]; then RB_SAME=1; RB_AT=$(uptime_s); return 0; fi
  if [[ -s $REBOOT_SPOOL ]]; then
    # Two cats: after a real reboot the tmpfs spool does not exist yet, and one cat over both
    # files exits 1 on the missing one, which skipped the mv and lost the saved story.
    { cat "$REBOOT_SPOOL"; cat "$SPOOL" 2>/dev/null; } >"${SPOOL}.t" 2>/dev/null
    mv -f "${SPOOL}.t" "$SPOOL" 2>/dev/null || :
  fi
  rm -f "$REBOOT_MARK" "$REBOOT_SPOOL" 2>/dev/null || :
}
say_after_reboot() {  # after the start line: this start follows AWACS's own reboot
  [[ -n $RB_STAMP ]] && (( ! RB_SAME )) || return 0
  site_log WARN "starting after the reboot AWACS ordered at ${RB_STAMP} - wedged ${REBOOT_AFTER_MIN} min (${RB_TELL_EN}), ${RB_RUNS} recovery runs before it" \
                "بدأنا بعد إعادة التشغيل التي أمر بها أواكس في ${RB_STAMP} - تعطّل ${REBOOT_AFTER_MIN} دقيقة (${RB_TELL_AR})، ${RB_RUNS} محاولة إنعاش قبلها"
}
reboot_failed_check() {  # each tick while RB_SAME: alive 60 s in the boot that should have ended.
  # The 60 s are read from the monotonic clock, not counted in ticks: an offline tick runs a
  # whole fight (three rounds with 20 s pauses), so six ticks took many minutes.
  (( $(uptime_s) - RB_AT < 60 )) && return 0
  RB_SAME=0; REBOOTING=0
  rm -f "$REBOOT_MARK" "$REBOOT_SPOOL" 2>/dev/null || :
  site_log ERROR "the reboot AWACS ordered at ${RB_STAMP} did not happen - the reboot command failed, check the device" \
                 "إعادة التشغيل التي أمر بها أواكس في ${RB_STAMP} لم تحدث - أمر إعادة التشغيل فشل، افحص الجهاز"
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

install_tools() {  # DESIGN DECISION (reverses the old report-only stance for
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

net_check() {  # $1 = ping wait (s), $2 = HTTP limit (s), $3 = pings per target: the ladder, ANY rung passing = online;
  # TWO http rungs, both exact: gstatic must answer 204, our own endpoint must answer
  # 400. Known accepted blind spot: ping-alive-but-DNS-dead reads ONLINE (aasw's ladder
  # had the same short-circuit) — the device's own watchdog owns that story.
  ping -c "$3" -i 0.3 -W "$1" 8.8.8.8 >/dev/null 2>&1 && return 0   # any reply = exit 0
  ping -c "$3" -i 0.3 -W "$1" 1.1.1.1 >/dev/null 2>&1 && return 0
  # portal's 302/200 splash must read as OFFLINE or the fight ends on fake victory.
  [[ $(curl -s -o /dev/null -w '%{http_code}' --max-time "$2" \
       "http://connectivitycheck.gstatic.com/generate_204" 2>/dev/null) == "204" ]] && return 0
  # Last rung — OUR OWN API answering its SIGNATURE reply: the endpoint returns
  # 400 "no operation" by contract, a code no captive-portal splash fabricates
  # (portals answer 200/302/511). This rescues the ICMP-eaten/204-mangled carrier
  # network WITHOUT the false victory a bare any-status probe would hand a portal.
  [[ -n $SITE_URL ]] || return 1   # no site configured = this rung does not exist
  [[ $(curl -s -o /dev/null -w '%{http_code}' --max-time "$2" \
       --data-urlencode "probe=1" "$(api_url)" 2>/dev/null) == "400" ]]
}
have_net()    { net_check 2 3 1; }   # the QUICK ladder: one tick's cheap question (unchanged cost)
net_patient() { net_check "$NET_PATIENT_PING_W" "$NET_PATIENT_HTTP" "$NET_PATIENT_PINGS"; }   # the second look
tx_now() {  # $1 = variable name <- TX bytes the interface has sent (builtin read, no fork;
  # 0 when the netdev is gone or reborn, so a vanished interface reads as no traffic)
  local v=0
  read -r v <"/sys/class/net/$IF/statistics/tx_bytes" 2>/dev/null || v=0
  [[ $v =~ ^[0-9]+$ ]] || v=0
  printf -v "$1" '%s' "$v"
}
net_verdict() {  # the daemon's own question, one tick: the quick ladder; a failure while the
  # device itself kept sending (TX bytes across the failed ladder) earns ONE patient look,
  # once per streak. A dead link sends nothing during the ladder, and a link whose patient
  # look already failed is not asked again, so a real outage costs one patient look at most.
  local a b sent=0
  tx_now a
  have_net && { PATIENT_FAILED=0; return 0; }
  # Asked patiently once in this streak and got nothing? The answer does not change
  # every ten seconds, and a real outage must not pay 26 s per tick to re-hear it.
  (( PATIENT_FAILED )) && return 1
  tx_now b; (( b > a )) && sent=$(( b - a ))
  (( sent >= NET_ALIVE_BYTES )) || return 1
  if net_patient; then
    dbg "quick check timed out under load (sent ${sent} B during it) - patient check passed"
    late_note; return 0
  fi
  PATIENT_FAILED=1   # asked patiently and got nothing: the streak does not get a second bill
  dbg "sent ${sent} B during the failed quick check, the patient check failed too - counting it"
  return 1
}
net_ok() {  # the fight's credit sites: a heal under load must be CREDITED, not fought.
  # Quick first; then a 2 s look at what the device sent (a dead candidate sends nothing:
  # 2 s and out); only real outgoing traffic earns the patient ladder.
  local a b
  have_net && return 0
  tx_now a; sleep 2; tx_now b
  (( b > a && b - a >= NET_ALIVE_BYTES / 5 )) || return 1
  net_patient && { dbg "quick check timed out under load (sent $(( b - a )) B in 2 s) - patient check passed"; return 0; }
  return 1
}
link_alive() {  # read-only: the LINK to the router works, so an outage is upstream. The
  # gateway's ping answer, or - under a load that delays even that - the kernel's neighbour
  # cache saying REACHABLE (two-way traffic confirmed lately, no packet sent to ask).
  local gw; gw=$(ip -4 route show default dev "$IF" 2>/dev/null | awk '{print $3; exit}')
  [[ -n $gw ]] || return 1
  ping -c 1 -W 2 "$gw" >/dev/null 2>&1 && return 0
  ip -4 neigh show dev "$IF" "$gw" 2>/dev/null | grep -q REACHABLE
}

gw_ok() {  # gateway answers = the LINK is fine, the outage is upstream (ISP) — never reboot for that
  local gw; gw=$(ip -4 route show default dev "$IF" 2>/dev/null | awk '{print $3; exit}')
  [[ -n $gw ]] && ping -c 1 -W 2 "$gw" >/dev/null 2>&1
}

wpa_auth_failing() {  # wrong password ≠ wedge: the supplicant marks such networks TEMP-DISABLED.
  wpa list_networks | grep -q 'TEMP-DISABLED'
}

up_kbps() {  # REAL UPLOAD speed to OUR OWN site — decision moments only. Target is
  # the endpoint (tiny error reply), not a page: response time would deflate the number.
  # No ||-clobber: on --max-time expiry curl still prints the honest partial average.
  # A probe whose bytes were never accepted prints 0 like a dead link would; the PROBE_FAIL
  # marker tells the two apart for the caller (a site outage is not a WiFi outage).
  rm -f "$PROBE_FAIL" 2>/dev/null
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
    probe_failed_mark; printf '0'; return 0
  fi
  printf '%d' "$(awk -v b="${bps:-0}" 'BEGIN { printf "%d", b * 8 / 1000 }')"
}

up_kbps_wget() {  # measurement must survive one dead tool (aasw's method fallback)
  local t0 t1 dt rc
  head -c $((PROBE_KB * 1024)) /dev/zero >"$PROBE_FILE" 2>/dev/null || { probe_failed_mark; printf '0'; return 0; }
  t0=$(date +%s%N)
  timeout 20 wget -q -O /dev/null -T 15 --post-file="$PROBE_FILE" "$1" 2>/dev/null
  rc=$?
  t1=$(date +%s%N)
  rm -f "$PROBE_FILE"
  # wget exit 8 = the server ANSWERED 4xx/5xx after the upload — our endpoint replies
  # 400 'no operation' by design, so 8 is success-of-transport. Anything else (4=network,
  # 124=timeout, ...) means the bytes never traveled: a fast failure must read as an
  # honest 0, never as a lightning-fast upload (proven 1638-16000 kbps phantom).
  (( rc != 0 && rc != 8 )) && { probe_failed_mark; printf '0'; return 0; }
  dt=$(( t1 - t0 ))
  (( dt <= 0 )) && { printf '0'; return 0; }
  printf '%d' $(( PROBE_KB * 1024 * 8 * 1000000 / dt ))  # bits * 1e6 / ns = kbps
}

probe_failed_mark() { : >"$PROBE_FAIL" 2>/dev/null || :; }   # inside up_kbps's subshell
probe_failed()      { [[ -e $PROBE_FAIL ]]; }                 # read by the caller after $(up_kbps)
say_probe_fail() {  # $1 = the network the probe ran on: the line that replaces "measured 0 kbps"
  # at every decision moment (evaluation, candidate, preferred arrival) when the probe
  # target took nothing. The decision still counts it as 0; the owner learns why.
  site_log WARN "upload probe failed on $1 - the probe target accepted nothing (site or endpoint down?), counting it as 0 kbps" \
                "فشل قياس الرفع على $1 - هدف القياس ما قبل شيء (الموقع أو الواجهة واقف؟)، نعتبره 0 كيلوبت/ث"
}

tx_kbps() {  # passive upload meter from kernel counters — zero traffic, 3s sample
  [[ -n ${AWACS_TEST_KBPS:-} ]] && { printf '%d' "$AWACS_TEST_KBPS"; return 0; }
  local a b f=/sys/class/net/$IF/statistics/tx_bytes
  a=$(cat "$f" 2>/dev/null || echo 0); sleep 3; b=$(cat "$f" 2>/dev/null || echo 0)
  printf '%d' $(( (b - a) * 8 / 3000 ))
}

streaming() {  # REAL TRAFFIC is its own upload meter — never probe or dance under it.
  # Four moments covered: a live web stream (live_raw), a preview shot (preview.jpg),
  # a still capture (capture.jpg — the 1-3s shot-to-upload gap is a collision window),
  # and an in-flight upload (curl upfile=@).
  pgrep -f 'raspistill.*(live_raw|preview\.jpg|capture\.jpg)' >/dev/null 2>&1 && return 0
  pgrep -f 'curl.*upfile=@' >/dev/null 2>&1
}

LAST_KBPS=0     # the incumbent's last ACTIVE upload measurement (decision moments only)
LAST_KBPS_ID="" # ...and WHICH network it belongs to — the site cell must never pair one
                # network's number with another's name (proven on veto/crutch paths)
LAST_KBPS_AT=0  # uptime second of that measurement: a manual trial reuses it while fresh
note_kbps() {  # $1 = kbps just measured on the network the device rides now: the cell's pair and
  # the scan list's memory (a probe the target refused is no measurement of the network)
  LAST_KBPS=$1; LAST_KBPS_ID=$(current_id); LAST_KBPS_AT=$(uptime_s)
  probe_failed || net_kbps_note "$(cur_key)" "$1"
}
report_wifi() {  # tmp/wifi.tmp -> the site's WiFi cell, riding the BATTERY pattern:
  # fresh file = cell shows, stale/absent = cell vanishes — a device without AWACS
  # renders the page unchanged (the modularity rule). PASSIVE by design:
  # the known/visible counts ride the existing scan CACHE — zero radio traffic.
  case $REPORT_WIFI in no) return 0 ;; auto) remote_on || return 0 ;; esac
  [[ -n $SITE_URL ]] || return 0   # "yes" without a site has nowhere to publish
  local tot=0 vis=0 id ssid cache s cid seen=$'\n' vseen=$'\n'
  if [[ $BACKEND != wpa ]]; then
    cache=$(nm_wifi_list no | cut -f1)   # --rescan no: NM's own cache, zero radio
  elif [[ -e $SCAN_CACHE ]]; then
    cache=$(cat "$SCAN_CACHE" 2>/dev/null)   # an EMPTY file is the deaf-radio verdict and stands
  else
    cache=$(scan_backend)   # no picture yet this boot: the supplicant's own table, zero radio
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
  s=$(dssid); cid=$(current_id)
  # Associated to a stored network = at least that one is on the air: a count of 0 here
  # (no scan yet, a dropped picture) read as a radio fault on the page.
  [[ -n $s && -n $cid ]] && (( vis < 1 && tot >= 1 )) && vis=1
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
  [[ -n $LAST_KBPS_ID && $cid == "$LAST_KBPS_ID" ]] || k=0
  # Format: kbps,visible,total,band,SSID — SSID LAST so its own commas survive (the
  # site splits with a 5-field limit). Sent via the existing endpoint channel.
  # The reply decides a refusal episode: the POST repeats every minute, so the marker keeps
  # it to one WARN per episode and one OK when the site takes the cell again.
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 --data-urlencode "file=tmp/wifi.tmp" \
    --data-urlencode "data=${k},${vis},${tot},${band},${s:--}" \
    "$(api_url)" 2>/dev/null) || code=000
  if [[ $code =~ ^[23][0-9][0-9]$ ]]; then
    [[ -e $WIFI_DOWN ]] || return 0
    rm -f "$WIFI_DOWN" 2>/dev/null || :
    site_log OK "wifi cell accepted again" "الموقع رجع يقبل خانة الواي فاي"
  elif [[ ! -e $WIFI_DOWN ]]; then
    : >"$WIFI_DOWN" 2>/dev/null || :
    http_words "$code"
    site_log WARN "wifi cell not accepted by the site (${HTTP_EN}) - the page drops the cell when it goes stale" \
                  "الموقع ما قبل خانة الواي فاي (${HTTP_AR}) - الصفحة تُسقط الخانة عندما تقدم"
  fi
}

# The scan list behind the site's WiFi box: the networks the radio heard, strongest first, each
# with the upload it measured while this process ran. The memory is keyed by the SSID's hex on
# both backends: iw's \xNN-escaped text and the iwlist fallback's raw UTF-8 name are the same
# bytes, so a row joins its number whichever tool drew the picture, without a profile lookup,
# and a temporary network keeps its number after its id is removed.
declare -A NET_KBPS=() NET_KBPS_AT=()
cur_key() {  # the memory key of the network the device rides now (empty when not associated):
  # the hex of iw's escaped SSID, on both backends
  local s; s=$(assoc_ssid)
  [[ -n $s ]] || return 0
  iw2hex "$s"
}
net_kbps_note() {  # $1 = memory key (SSID hex), $2 = measured upload kbps: remembered for the scan list
  [[ -n $1 && $2 =~ ^[0-9]+$ ]] || return 0
  NET_KBPS[$1]=$2; NET_KBPS_AT[$1]=$(date +%s)
}
hex_disp() {  # display form of an SSID given as hex (nm's air key): bytes decoded, control bytes out
  local h=$1 esc="" i
  for (( i = 0; i < ${#h}; i += 2 )); do esc+="\\x${h:i:2}"; done
  pssid "$esc"
}
SCAN_LIST_AT=0 SCAN_LIST_SCAN="" SCAN_NM_ROWS="" SCAN_NM_AT=0
readonly SCAN_LIST_ROWS=12 SCAN_LIST_EVERY=60
report_scan() {  # tmp/wifi_scan.tmp -> the list behind the site's WiFi box. The cell's gate, online
  # only, at most once per SCAN_LIST_EVERY seconds, and only for a scan that really hit the radio:
  # on wpa the picture scan() wrote (stamped in SCAN_AT), on nm NetworkManager's own last picture
  # read without a rescan and stamped when it changes. No radio traffic here. The POST runs in the
  # background; a refused list is retried every minute until the site takes it again.
  # Format: line 1 the scan's unix time; then one line per network, tab-separated: display name,
  # signal in dBm, measured upload kbps (empty: never measured), unix time of that measurement,
  # known (1 = a stored network, 0 = not), key (the SSID as lowercase hex). The site's menu offers
  # a switch for a known row and a join for an unknown one, and names the network by the key.
  # $1 = now: a site command asked; the POST runs in the foreground so the list lands before the
  # command's answer.
  [[ -n ${AWACS_CLI:-} ]] && return 0
  case $REPORT_WIFI in no) return 0 ;; auto) remote_on || return 0 ;; esac
  [[ -n $SITE_URL ]] || return 0
  (( net_up )) || return 0
  local now scan_at rows key mkey sig _sec n=0 body name known kid kssid kset=$'\n'
  now=$(date +%s)
  (( now - SCAN_LIST_AT >= SCAN_LIST_EVERY )) || return 0
  if [[ $BACKEND != wpa ]]; then
    rows=$(nm_wifi_list no | sort -t$'\t' -k2,2gr)   # --rescan no: NM's own cache, zero radio
    [[ $rows == "$SCAN_NM_ROWS" ]] || { SCAN_NM_ROWS=$rows; SCAN_NM_AT=$now; }
    scan_at=$SCAN_NM_AT
  else
    read -r scan_at 2>/dev/null <"$SCAN_AT" || scan_at=""
    [[ $scan_at =~ ^[0-9]+$ ]] || return 0   # no scan has hit the radio yet this boot
    rows=$(cat "$SCAN_CACHE" 2>/dev/null)     # scan() writes it strongest first
  fi
  [[ $scan_at != "$SCAN_LIST_SCAN" || -e $SCAN_DOWN ]] || return 0   # already published, and not refused
  SCAN_LIST_AT=$now; SCAN_LIST_SCAN=$scan_at
  while IFS=$'\t' read -r kid kssid; do   # the stored set, keyed like the rows below
    [[ -n $kid ]] || continue
    if [[ $BACKEND != wpa ]]; then kset+="${kssid}"$'\n'; else kset+="$(iw2hex "$kssid")"$'\n'; fi
  done < <(known_ids)
  body=$scan_at
  while IFS=$'\t' read -r key sig _sec; do
    [[ -n $key ]] || continue
    (( ++n <= SCAN_LIST_ROWS )) || break
    if [[ $BACKEND != wpa ]]; then
      name=$(hex_disp "$key"); mkey=$key   # nm's rows are hex already
      # nmcli reports percent on NetworkManager's scale (100% at -40 dBm, 0% at -100): an estimate
      if [[ $sig =~ ^[0-9]+$ ]]; then (( sig > 100 )) && sig=100; sig=$(( -40 - (100 - sig) * 3 / 5 )); else sig=0; fi
    else
      # The cache holds iw's \xNN text, or the iwlist fallback's raw UTF-8 name; %b leaves raw
      # bytes alone, so both forms of one name reach the same key as cur_key wrote.
      name=$(pssid "$key"); mkey=$(iw2hex "$key"); sig=${sig%%.*}
      [[ -n $mkey ]] || mkey=$key   # a raw name %b swallows whole (a literal \c): an empty subscript is a bash error
      [[ $sig =~ ^-?[0-9]+$ ]] || sig=0
    fi
    if [[ $kset == *$'\n'"${mkey}"$'\n'* ]]; then known=1; else known=0; fi
    body+=$'\n'"${name}"$'\t'"${sig}"$'\t'"${NET_KBPS[$mkey]:-}"$'\t'"${NET_KBPS_AT[$mkey]:-}"$'\t'"${known}"$'\t'"${mkey}"
  done <<<"$rows"
  if [[ ${1:-} == now ]]; then scan_post "$body" >/dev/null 2>&1 || :
  else { scan_post "$body"; } >/dev/null 2>&1 9>&- & fi
}
scan_post() {  # $1 = the list text: the cell's POST shape. This runs in a background child, so the
  # refusal episode lives in a marker: one WARN when the site first refuses, one OK when it takes
  # the list again.
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 --data-urlencode "file=tmp/wifi_scan.tmp" \
    --data-urlencode "data=$1" "$(api_url)" 2>/dev/null) || code=000
  if [[ $code =~ ^[23][0-9][0-9]$ ]]; then
    [[ -e $SCAN_DOWN ]] || return 0
    rm -f "$SCAN_DOWN" 2>/dev/null || :
    site_log OK "wifi scan list accepted again" "الموقع رجع يقبل قائمة مسح الواي فاي"
  elif [[ ! -e $SCAN_DOWN ]]; then
    : >"$SCAN_DOWN" 2>/dev/null || :
    http_words "$code"
    site_log WARN "wifi scan list not accepted by the site (${HTTP_EN}) - the list behind the WiFi box will not show" \
                  "الموقع ما قبل قائمة مسح الواي فاي (${HTTP_AR}) - القائمة خلف خانة الواي فاي ما راح تظهر"
  fi
}

# ------------------------------- radio -----------------------------------------
scan_stamp() {  # $1 = unix time: the radio answered and the cache holds its picture; report_scan
  # reads the stamp to publish each real scan once (a served cache is not a scan)
  printf '%s\n' "$1" >"$SCAN_AT" 2>/dev/null || :
}
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
      scan_stamp "$now"
      cat "$SCAN_CACHE"; return 0
    fi
    # Every source came back empty after every retry. ONCE is a hiccup: stale results
    # beat no results (aasw told the same story), and the cache's mtime is refreshed so
    # a silent radio is asked again once per SCAN_TTL — not once per caller. SCAN_DEAF
    # times IN A ROW is no hiccup, it is the picture: a radio that hears NOTHING. The
    # stale cache is dropped then, so fight()'s "radio sees NOTHING" tell and every
    # visible-known reader see the truth — seen on NetworkManager: a deaf radio hid behind
    # a 37-minute-old cache, the fight called it external and the valve never armed.
    local empties; empties=$(cat "$SCAN_EMPTY" 2>/dev/null)
    [[ $empties =~ ^[0-9]{1,6}$ ]] || empties=0
    empties=$(( empties + 1 ))
    printf '%d\n' "$empties" >"$SCAN_EMPTY"
    if (( empties >= SCAN_DEAF )); then
      if [[ -s $SCAN_CACHE ]]; then   # said once, at the moment the picture is dropped
        if [[ -n ${AWACS_CLI:-} ]]; then
          llog WARN "radio heard nothing on ${empties} scans in a row - previous results dropped" \
                    "الراديو لم يسمع أي شبكة في ${empties} مسوحات متتالية - أُسقطت النتائج السابقة"
        else
          site_log WARN "radio heard nothing on ${empties} scans in a row - previous results dropped" \
                        "الراديو لم يسمع أي شبكة في ${empties} مسوحات متتالية - أُسقطت النتائج السابقة"
        fi
      fi
      : >"$SCAN_CACHE"   # empty AND fresh: "nothing" is the answer for the next SCAN_TTL
      scan_stamp "$now"  # a real answer too: the published list is then empty
      return 0
    fi
    # Toolbox runs stay local-only: a hand-run scan is not the daemon's story.
    if [[ -n ${AWACS_CLI:-} ]]; then
      llog WARN "scan failed - using previous results (if any)" \
                "فشل مسح الشبكات - نستخدم نتائج سابقة إن وجدت"
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
    scan_stamp "$now"
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
NM_AUTH_SSID=""                  # the network whose activation carried the credentials text
NM_L3_SPENT=0                    # this streak already tried L3's NetworkManager restart
NM_RC8=0                         # sticky per streak: nmcli itself unreachable (exit 8)
NM_SAW_BUSY=0                    # a connecting-band sample was seen since the last check
NM_SETTLED_SEEN=0                # consecutive settled (30/120) classifications
NM_LAME_REASON=""                # nocli | "" (unmanaged) — decides whether the park may exit
# Documented limit: NM device state 20 "unavailable" (e.g. a
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
    if (( rc == 8 )); then (( NM_RC8 )) || say_nm_rc8; NM_RC8=1; fi
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
  # An armed clock was announced, so its clearing is said too.
  (( ME_SINCE > 0 )) && say_clock_clear
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
  # profile must still be ONE candidate, never two con-ups)
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
  # Four classes of our own: crutch and safety (a fight's), join (a site join's trial) and
  # joined (a stored network joined from the site, persistent across reaps).
  [[ $name =~ ^awacs-(crutch|safety|join)-[0-9]+-[0-9]+$ || $name =~ ^awacs-joined-[0-9a-f]+$ ]] || {
    log ERROR "REFUSING delete: '$name' is not an awacs profile"; return 1; }
  [[ $file == /run/NetworkManager/system-connections/awacs-* ]] || {
    log ERROR "REFUSING delete: '$name' lives outside /run (owner file?)"; return 1; }
  nmcli connection down uuid "$1" >/dev/null 2>&1 || :
  nmcli connection delete uuid "$1" >/dev/null 2>&1 || :
}

nm_add_crutch() {  # $1=hexssid $2=psk-or-empty $3=hidden(yes/no) -> prints UUID.
  # NEVER `nmcli device wifi connect` (it PERSISTS an autoconnect profile in /etc —
  # the accumulation trap the NO-BLOCK law bans). One /run keyfile, boot-only.
  local name
  if [[ -n $2 ]]; then name="awacs-safety-$(date +%s)-$$"
  else name="awacs-crutch-$(date +%s)-$$"; fi
  nm_write_profile "$1" "$2" "$3" "$name" false
}
nm_write_profile() {  # $1=hexssid $2=psk-or-empty $3=hidden(yes/no) $4=profile name $5=autoconnect
  # (true/false) -> prints UUID. The one keyfile writer of the nm arm: crutches, a site join's
  # trial and the persistent joined class all pass through here, always under /run.
  local hex=$1 psk=$2 hidden=$3 name=$4 auto=$5 uuid path
  uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null) || return 1
  path="/run/NetworkManager/system-connections/${name}.nmconnection"
  install -d -m 700 /run/NetworkManager/system-connections 2>/dev/null || :
  {
    printf '[connection]\nid=%s\nuuid=%s\ntype=wifi\nautoconnect=%s\n' "$name" "$uuid" "$auto"
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
  local uuid name marked=""
  if [[ -s $OPEN_ID_FILE ]]; then
    marked=$(head -1 "$OPEN_ID_FILE")
    # Named before the delete (the only moment the name exists); a profile already gone is
    # not a removal worth a line.
    [[ -n $(nmcli -e no -g connection.id connection show uuid "$marked" 2>/dev/null) ]] && say_reaped "$marked"
    nm_del_own "$marked" || :
    rm -f "$OPEN_ID_FILE"
  fi
  while IFS=: read -r uuid name; do
    if [[ $name == awacs-* && $name != awacs-joined-* ]]; then   # a joined network is stored, not a crutch
      [[ $uuid == "$marked" ]] || say_reaped "$uuid"
      nm_del_own "$uuid" || :
    fi
  done < <(nmcli -t -f UUID,NAME connection show 2>/dev/null)
  nm_run_sweep
  nmcli connection reload >/dev/null 2>&1 || :
}
nm_run_sweep() {  # the /run glob belt: every keyfile of ours except the joined class, which the
  # owner's join made persistent (load_joined re-adds a missing one)
  local f
  for f in /run/NetworkManager/system-connections/awacs-*.nmconnection; do
    [[ $f == */awacs-joined-* ]] && continue
    rm -f "$f" 2>/dev/null || :
  done
}

nm_recover() {  # NM-side ladder: cooperative only — NEVER ip link down/up on a managed
  # device (double-authority loop, proven), never dhcpcd.
  case "$1" in
    1) say_once rung1 WARN "recover L1: radio bounce" "إنعاش م1: نطفي الواي فاي ونشغله"
       # Bounce OUR interface's own killswitch, never the whole WLAN type: `nmcli radio
       # wifi off` soft-blocks EVERY wireless radio on the box (a second dongle, or an
       # access point hosted on the same box: every activation then dies with
       # ssid-not-found). nmcli's switch stays as the fallback for drivers
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
    2) say_once rung2 WARN "recover L2: re-kick NetworkManager on ${IF}" "إنعاش م2: نعيد ضبط الاتصال"
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
    3) say_once rung3 WARN "recover L3: restart NetworkManager + reload WiFi firmware" \
                           "إنعاش م3: نعيد تشغيل مدير الشبكة وتعريف الشريحة"
       NM_L3_SPENT=1
       # The two load-bearing commands are checked: a rung whose cure did not run must not
       # read as a cure that ran. The unload is judged only where the driver was loaded.
       local had_mod=0; [[ -d /sys/module/brcmfmac ]] && had_mod=1
       systemctl restart NetworkManager 2>/dev/null \
         || say_once rung3-nm-fail WARN "recover L3 did not complete: NetworkManager refused to restart - firmware reload follows" \
                                        "الإنعاش م3 ما تمّ: مدير الشبكة رفض إعادة التشغيل - يليها إعادة تحميل التعريف"
       sleep 8
       if ! modprobe -r brcmfmac 2>/dev/null; then
         (( had_mod )) && say_once rung3-fail WARN "recover L3 did not complete: brcmfmac would not unload - firmware not reloaded" \
                                                   "الإنعاش م3 ما تمّ: تعريف brcmfmac ما انفكّ - ما أُعيد تحميل التعريف"
       fi
       sleep 2
       modprobe brcmfmac 2>/dev/null || :; sleep 8
       iw dev "$IF" set power_save off 2>/dev/null || :
       # Reap BELT: do NOT assume the restart wiped our /run keyfiles (not contractual;
       # tmpfs files outlive the service and NM re-reads the dir at startup).
       nm_run_sweep
       nmcli connection reload >/dev/null 2>&1 || :
       load_joined   # a restart can lose a runtime profile exactly when it is the one that works
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
reassociate() {  # fight's gentle open: ask the base layer to try. On wpa this re-associates
  # even a LIVE association (a few seconds of link loss), which is why fight() skips it
  # while the link is provably alive; on nm it acts only on a disconnected/failed device.
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
ACT_WHY_EN="" ACT_WHY_AR=""   # why be_activate failed: fixed phrases, or NetworkManager's own
                               # message cleaned (nmcli's stderr carries reasons, never a key)
act_why_wait() {  # the reason wait_ip leaves behind: the link never formed, or formed without a lease
  if [[ $WAIT_WHY == addr ]]; then ACT_WHY_EN="associated but got no address"; ACT_WHY_AR="ارتبط بس ما أخذ عنوان"
  else ACT_WHY_EN="never associated"; ACT_WHY_AR="ما ارتبط أبداً"; fi
}
nm_err_text() {  # NetworkManager's message: one line, its fixed prefix dropped, control bytes out, 100 chars
  local m=${NM_ERR%%$'\n'*}
  m=${m#Error: Connection activation failed: }
  m=$(printf '%s' "$m" | tr -d '\000-\037\177'); m=${m:0:100}
  printf '%s' "$m"
}
be_activate() {  # raw activation of ID $1 (association + DHCP proof); ACT_WHY_* says why it failed
  ACT_WHY_EN="no association or no address"; ACT_WHY_AR="ما ارتبط ولا أخذ عنوان"
  # Already riding $1 with an address? Re-activating it would only bounce a live
  # association (nm deactivates then activates, wpa re-selects) - prove it as it stands.
  if [[ $1 == "$(current_id)" && -n $(ip -4 addr show dev "$IF" scope global 2>/dev/null) ]]; then
    wait_ip && return 0
    act_why_wait; return 1
  fi
  if [[ $BACKEND != wpa ]]; then
    nm_wait_settled   # never issue con up mid-transition (100 counts as settled)
    NM_ERR=$(nmcli -w "$ASSOC_BUDGET" connection up uuid "$1" 2>&1 >/dev/null); NM_RC=$?
    if (( NM_RC == 8 )); then (( NM_RC8 )) || say_nm_rc8; NM_RC8=1; else NM_RC8=0; fi
    if (( NM_RC == 3 || NM_RC == 4 )) && nm_auth_sig "$NM_ERR"; then
      NM_AUTH=1   # sticky for the whole fight: a later timeout on another candidate
                  # must not erase a credentials sighting (wpa's TEMP-DISABLED parity)
      NM_AUTH_SSID=$(disp_ssid "$1" "")
      ACT_WHY_EN="refused - wrong password?"; ACT_WHY_AR="رُفض - كلمة سر خاطئة؟"
      return 1
    fi
    if (( NM_RC != 0 )); then
      # nmcli's exit codes: 3 timed out, 4 activation failed, 8 NM not running, 10 no such
      # network; NM's message is quoted only when no fixed phrase fits.
      local m
      if (( NM_RC == 8 )); then ACT_WHY_EN="NetworkManager not answering"; ACT_WHY_AR="مدير الشبكة ما يرد"
      elif (( NM_RC == 10 )) || [[ $NM_ERR == *"not found"* || $NM_ERR == *"not be found"* || $NM_ERR == *"No suitable"* ]]; then
        ACT_WHY_EN="not found on the air"; ACT_WHY_AR="غير موجودة على الهواء"
      elif (( NM_RC == 3 )); then ACT_WHY_EN="timed out after ${ASSOC_BUDGET} s"; ACT_WHY_AR="انتهت المهلة بعد ${ASSOC_BUDGET} ث"
      else m=$(nm_err_text); ACT_WHY_EN="NetworkManager: ${m:-nmcli exit ${NM_RC}}"; ACT_WHY_AR="مدير الشبكة: ${m:-nmcli exit ${NM_RC}}"; fi
      return 1
    fi
    wait_ip || { act_why_wait; return 1; }   # belt: nmcli said up — confirm the lease/carrier like wpa does
  else
    wpa select_network "$1" >/dev/null
    wait_ip "$1" || {
      act_why_wait
      # The supplicant marks a network whose handshake keeps failing TEMP-DISABLED: wait_ip
      # sampled the target's own row and latched a sighting (a wrong key ends as associated
      # without an address, so WAIT_WHY says nothing here); a row still marked after a never-
      # associated wait says the same. A weak link earns the mark too, hence the question mark.
      if (( WAIT_TD )) || { [[ $WAIT_WHY != addr ]] && wpa list_networks | awk -F'\t' -v id="$1" '$1 == id && /TEMP-DISABLED/ { f = 1 } END { exit !f }'; }; then
        ACT_WHY_EN="refused - wrong password?"; ACT_WHY_AR="رُفض - كلمة سر خاطئة؟"
      fi
      return 1
    }
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
name_of_id() {  # owner-facing name for stored network ID $1 when the caller holds only the
  # id: nm reads the profile itself, wpa needs the row text from the stored list. An id
  # that is no longer stored is named by the id, the only name left.
  local id ssid n
  if [[ $BACKEND != wpa ]]; then n=$(disp_ssid "$1" ""); printf '%s' "${n:-$1}"; return 0; fi
  while IFS=$'\t' read -r id ssid; do
    [[ $id == "$1" ]] && { pssid "$ssid"; return 0; }
  done < <(wpa_known_ids)
  printf '%s' "$1"
}
say_reaped() {  # $1 = the temporary network id about to be removed at start. Named before the
  # delete (the only moment the name exists). When the device still rides it, the delete IS
  # the outage that follows, and the line says so.
  local name
  name=$(name_of_id "$1")
  if [[ $1 == "$(current_id)" ]]; then
    site_log WARN "removed the temporary network ${name} left by the previous run - the device was still on it, recovery follows" \
                  "أزلنا الشبكة المؤقتة ${name} التي تركها التشغيل السابق - كان الجهاز لا يزال عليها، يتبعها إنعاش"
  else
    site_log INFO "removed the temporary network ${name} left by the previous run" \
                  "أزلنا الشبكة المؤقتة ${name} التي تركها التشغيل السابق"
  fi
}
reap_crutches() {  # startup: predecessor's crutch must not survive the crash
  local id
  reap_join   # an unfinished site join first, with its own line; the sweeps below then find nothing of it
  if [[ $BACKEND != wpa ]]; then
    nm_reap
  else
    if [[ -s $OPEN_ID_FILE ]]; then
      id=$(head -1 "$OPEN_ID_FILE")
      say_reaped "$id"
      wpa remove_network "$id" >/dev/null 2>&1 || :
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

WAIT_WHY=""   # which of wait_ip's two tests failed last: assoc (never associated) | addr (no lease)
WAIT_TD=0     # wpa: the target's row read TEMP-DISABLED at least once while wait_ip watched
ASSOC_BUDGET=$ASSOC_WAIT   # seconds the activation in progress may take: ASSOC_WAIT, or a manual
                           # trial's TRIAL_ASSOC_WAIT while connect_id runs its one connect
wait_ip() {  # association alone is not a connection — demand an IPv4 lease too
  # $1 (wpa, optional) = the network id being activated: its row is sampled once a second for
  # the whole budget, so a wrong key is told from a network out of reach whenever the mark shows.
  local i td_first=-1
  WAIT_WHY=""; WAIT_TD=0
  for (( i = 0; i < ASSOC_BUDGET; i++ )); do
    [[ -n $(ip -4 addr show dev "$IF" scope global 2>/dev/null) ]] \
      && iw dev "$IF" link 2>/dev/null | grep -q '^Connected' && return 0
    # A wrong key associates, fails the 4-way handshake and ends without an address, and the
    # supplicant's TEMP-DISABLED mark flickers with every retry: one read at the end can miss
    # it, so the row is sampled every second and a single sighting is kept for the verdict. The
    # supplicant parks a failed network for about 10 s and tries again; a mark seen again 10 s or
    # more after the first sighting means that retry failed too, a wrong key rather than a weak
    # link, and the wait ends there instead of at the budget's end (about 15 s sooner on a 45 s
    # trial). A right key on a weak link that makes it on the retry is still taken above.
    if [[ -n ${1:-} && $BACKEND == wpa ]]; then
      if wpa list_networks | awk -F'\t' -v id="$1" '$1 == id && /TEMP-DISABLED/ { f = 1 } END { exit !f }'; then
        WAIT_TD=1
        (( td_first < 0 )) && td_first=$i
        (( i - td_first >= 10 )) && break
      fi
    fi
    sleep 1
  done
  if iw dev "$IF" link 2>/dev/null | grep -q '^Connected'; then WAIT_WHY=addr; else WAIT_WHY=assoc; fi
  return 1
}

CONNECT_WHY="" CONNECT_WHY_AR=""   # why the last connect_id failed, in both languages, for the
                                   # site's story; empty after a success. A reason is never a key.
connect_id() {  # activate network ID $1 (wpa numeric id / nm profile UUID) — SHARED body,
  # same crediting doctrine on both backends. $2 (optional) = a longer association budget in
  # seconds for this one connect (a manual trial's TRIAL_ASSOC_WAIT); never below ASSOC_WAIT,
  # and ASSOC_WAIT again the moment the activation ends, so the recovery's own waits keep it.
  local rc
  dbg "connect_id: activating $1 (backend $BACKEND)"
  CONNECT_WHY=""; CONNECT_WHY_AR=""
  ASSOC_BUDGET=${2:-$ASSOC_WAIT}
  (( ASSOC_BUDGET < ASSOC_WAIT )) && ASSOC_BUDGET=$ASSOC_WAIT
  be_activate "$1"; rc=$?
  ASSOC_BUDGET=$ASSOC_WAIT
  (( rc == 0 )) || { CONNECT_WHY=$ACT_WHY_EN; CONNECT_WHY_AR=$ACT_WHY_AR; return 1; }
  LINK_OK=1   # association + DHCP succeeded this round — the LINK layer is provably fine
  LINK_OK_NAME=$(name_of_id "$1")   # the network that linked, for the external verdict
  have_net || { CONNECT_WHY="linked but no internet"; CONNECT_WHY_AR="مرتبط بس بدون إنترنت"; return 1; }
  # Verified internet — site_log may speak from this moment on. ME_SINCE clears
  # HERE too: the tick path only credits health it SEES, and a crutch that lives
  # less than one tick left a stale wedge streak that later rebooted a box which
  # provably had working internet 97s earlier (proven). Credit the moment itself.
  net_up=1; ME_SINCE=0
}
return_to() {  # $1 = stored network id, $2 = its owner-facing name: the way back after a try
  # elsewhere failed. A failed return is said on the site with its reason; the caller
  # says what a success means to it. A link that forms but finds no internet is the
  # upstream outage itself (INFO: the device is back home, the ISP is not); a link that
  # never forms is a real failure (WARN). Once per outage per network and reason: a losing
  # fight walks home up to three times and is entered again on the next tick.
  connect_id "$1" && return 0
  if [[ $CONNECT_WHY == "linked but no internet" ]]; then
    if (( FIGHT_STREAK > 0 )); then
      say_once "return:$1:${CONNECT_WHY}" INFO "back on $2 - linked but still no internet, recovery continues" \
                                              "رجعنا على $2 - مرتبط بس لسا بدون إنترنت، الإنعاش مستمر"
    else
      say_once "return:$1:${CONNECT_WHY}" INFO "back on $2 - linked but still no internet" \
                                              "رجعنا على $2 - مرتبط بس لسا بدون إنترنت"
    fi
  else
    say_once "return:$1:${CONNECT_WHY}" WARN "could not return to $2: ${CONNECT_WHY}" "ما قدرنا نرجع على $2: ${CONNECT_WHY_AR}"
  fi
  return 1
}

wpa_enable_all() { wpa enable_network all >/dev/null || :; }
# select_network disables every other network in the LIVE supplicant. EVERY winning
# path below re-enables all (proven not to break the current association) so the
# supplicant keeps its autonomous fallback and a dead AWACS can never strand the box.
#
# THE NO-BLOCK LAW (learned the hard way: an earlier watchdog
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
    1) say_once rung1 WARN "recover L1: radio bounce" "إنعاش م1: إعادة تشغيل الراديو"
       rfkill unblock wifi 2>/dev/null || :
       ip link set "$IF" down; sleep 2
       # The load-bearing command of each rung is checked: a cure that did not run is said.
       ip link set "$IF" up 2>/dev/null \
         || say_once rung1-fail WARN "recover L1 did not complete: ${IF} would not come back up - radio not bounced" \
                                     "الإنعاش م1 ما تمّ: ${IF} ما رجعت تشتغل - الراديو ما انعاد تشغيله"
       sleep 3 ;;
    2) say_once rung2 WARN "recover L2: restart dhcpcd (respawns the REAL per-interface supplicant)" \
                           "إنعاش م2: إعادة تشغيل مدير الشبكة"
       systemctl restart dhcpcd 2>/dev/null || systemctl restart wpa_supplicant 2>/dev/null \
         || say_once rung2-fail WARN "recover L2 did not complete: dhcpcd and wpa_supplicant both refused to restart - supplicant not respawned" \
                                     "الإنعاش م2 ما تمّ: dhcpcd وwpa_supplicant رفضوا إعادة التشغيل - المشغّل ما انعاد"
       sleep 8; arm_hidden; load_joined   # a fresh supplicant knows only wpa_supplicant.conf
       iw dev "$IF" set power_save off 2>/dev/null || : ;;  # a fresh supplicant re-enables it
    3) say_once rung3 WARN "recover L3: reload brcmfmac firmware (the 3-second cure a wedge needs)" \
                           "إنعاش م3: إعادة تحميل تعريف شريحة الواي فاي"
       local had_mod=0; [[ -d /sys/module/brcmfmac ]] && had_mod=1   # judged only where the driver was loaded
       if ! modprobe -r brcmfmac 2>/dev/null; then
         (( had_mod )) && say_once rung3-fail WARN "recover L3 did not complete: brcmfmac would not unload - firmware not reloaded" \
                                                   "الإنعاش م3 ما تمّ: تعريف brcmfmac ما انفكّ - ما أُعيد تحميل التعريف"
       fi
       sleep 2
       modprobe brcmfmac 2>/dev/null || :; sleep 8; arm_hidden; load_joined
       iw dev "$IF" set power_save off 2>/dev/null || : ;;  # a rebuilt netdev re-enables it
  esac
}

# ------------------------------- crutches --------------------------------------
OPEN_ID=""  # temp network id currently parked in the live supplicant (crutch, not family)
mark_crutch() {  # crash-proof: a respawned daemon reaps its dead predecessor's crutch
  OPEN_ID="$1"
  printf '%s\n' "$1" >"$OPEN_ID_FILE" 2>/dev/null || :
}
drop_open() {  # $1 = why: home (a stored network carries the device again, OK line) | failed
  # (the crutch stopped delivering, said once per outage) | empty (silent). The name is read
  # before the delete, the only moment it exists. Each call is an edge: OPEN_ID empties here.
  local name
  if [[ -n $OPEN_ID ]]; then
    name=$(name_of_id "$OPEN_ID")
    del_own "$OPEN_ID" || :; OPEN_ID=""
    case ${1:-} in
      home)   site_log OK "back on a stored network: $(dssid) - temporary network ${name} removed" \
                          "رجعنا على شبكة مخزنة: $(dssid) - أزلنا الشبكة المؤقتة ${name}" ;;
      failed) say_once crutch-drop INFO "dropping temporary network ${name} - it stopped delivering" \
                                        "نحذف الشبكة المؤقتة ${name} - ما عادت توصّل" ;;
    esac
  fi
  rm -f "$OPEN_ID_FILE"
}

try_safety() {  # aasw's SAFETY_NET made real: owner-listed emergency networks WITH
  # passwords, tried BEFORE open strangers. Attempted even when not visible in scan
  # (hotspots are often just-enabled or hidden; wait_ip bounds each try at ASSOC_WAIT s).
  # Every entry's fate is said once per outage: skipped (a settings fault the owner must fix),
  # uncreatable, refused with the reason, then the closing count. Names only, never a password.
  (( ${#SAFETY_NET[@]} )) || return 1
  say_once safety INFO "trying emergency networks (${#SAFETY_NET[@]} listed)" \
                       "نحاول شبكات الطوارئ"
  local ssid id ok psk tried=0 skipped=0
  for ssid in "${!SAFETY_NET[@]}"; do
    psk=${SAFETY_NET[$ssid]}
    if [[ $BACKEND != wpa ]]; then
      # Keyfile byte-arrays carry ANY name/psk byte (the wpa-era backslash/quote
      # skip disappears here); only psk length sanity gates (8-63, or 64 hex).
      if [[ -n $psk ]] \
         && ! { (( ${#psk} >= 8 && ${#psk} <= 63 )) || [[ $psk =~ ^[0-9a-fA-F]{64}$ ]]; }; then
        (( ++skipped ))
        say_once "sskip:${ssid}" ERROR "emergency network ${ssid} skipped: password must be 8-63 characters or 64 hex digits" \
                                       "شبكة الطوارئ $(pssid "$ssid") متجاوَزة: كلمة السر لازم تكون 8-63 حرفاً أو 64 خانة ست عشرية"
        continue
      fi
      { id=$(nm_add_crutch "$(text2hex "$ssid")" "$psk" no) && [[ -n $id ]]; } || {
        (( ++skipped ))
        say_once "smk:${ssid}" WARN "could not create the temporary entry for ${ssid} - skipping it" \
                                    "ما قدرنا ننشئ الإدخال المؤقت لـ $(pssid "$ssid") - نتجاوزها"
        continue; }
      printf '%s\n' "$id" >"$OPEN_ID_FILE" 2>/dev/null || :   # pre-mark (crash window)
      (( ++tried ))
      if connect_id "$id"; then
        mark_crutch "$id"
        enable_all
        say_crutch_win EMERGENCY "$ssid" "$(pssid "$ssid")"
        return 0
      fi
      say_once "sfail:${ssid}:${CONNECT_WHY}" WARN "emergency network ${ssid} refused: ${CONNECT_WHY} - trying the next" \
                                                   "شبكة الطوارئ $(pssid "$ssid") رفضت: ${CONNECT_WHY_AR} - نجرب اللي بعدها"
      del_own "$id" || :
      rm -f "$OPEN_ID_FILE"
      continue
    fi
    # Skip names/passwords the supplicant's quoted parser cannot carry (backslash
    # or a literal double-quote would malform the set_network line) — clean skip.
    if [[ $ssid == *"\\"* || $ssid == *'"'* || ${SAFETY_NET[$ssid]} == *'"'* ]]; then
      (( ++skipped ))
      say_once "sskip:${ssid}" ERROR "emergency network ${ssid} skipped: name or password carries a quote or backslash the supplicant cannot take" \
                                     "شبكة الطوارئ $(pssid "$ssid") متجاوَزة: الاسم أو كلمة السر فيها علامة تنصيص أو شرطة مائلة ما يقبلها المشغّل"
      continue
    fi
    { id=$(wpa add_network) && [[ $id =~ ^[0-9]+$ ]]; } || {
      (( ++skipped ))
      say_once "smk:${ssid}" WARN "could not create the temporary entry for ${ssid} - skipping it" \
                                  "ما قدرنا ننشئ الإدخال المؤقت لـ $(pssid "$ssid") - نتجاوزها"
      continue; }
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
    if (( ! ok )); then
      (( ++skipped ))
      say_once "smk:${ssid}" WARN "could not create the temporary entry for ${ssid} - skipping it" \
                                  "ما قدرنا ننشئ الإدخال المؤقت لـ $(pssid "$ssid") - نتجاوزها"
    else
      (( ++tried ))
      if connect_id "$id"; then
        mark_crutch "$id"
        enable_all
        say_crutch_win EMERGENCY "$ssid" "$(pssid "$ssid")"
        return 0
      fi
      say_once "sfail:${ssid}:${CONNECT_WHY}" WARN "emergency network ${ssid} refused: ${CONNECT_WHY} - trying the next" \
                                                   "شبكة الطوارئ $(pssid "$ssid") رفضت: ${CONNECT_WHY_AR} - نجرب اللي بعدها"
    fi
    wpa remove_network "$id" >/dev/null || :
    rm -f "$OPEN_ID_FILE"   # attempt failed and the id is gone — clear the pre-mark
  done
  say_once snone INFO "no emergency network delivered (${tried} tried, ${skipped} skipped)" \
                      "ولا شبكة طوارئ وصّلت (جرّبنا ${tried} وتجاوزنا ${skipped})"
  return 1
}

try_open() {  # last resort: truly-open APs, temp ID, never saved to disk.
  # Dedupe multi-BSS SSIDs (a dual-band AP is ONE attempt) and skip hopeless signals
  # (<-80dBm, open strangers only — KNOWN networks are always attempted, however weak).
  # The opener carries how many open networks the list holds; a network that links but
  # forwards nothing (a portal) is named once per outage; the closing line counts the walk.
  # A stranger refusing a stranger is no owner action: those failures are counted, not said.
  [[ $OPEN_NETWORKS == "yes" ]] || return 1
  local ssid sig sec id s seen=$'\n' list heard=0 tried=0 portals=0 name
  if [[ $BACKEND != wpa ]]; then list=$(nm_wifi_list auto); else list=$(scan); fi
  heard=$(awk -F'\t' '$3 == "open" { n++ } END { print n + 0 }' <<<"$list")
  say_once open INFO "trying open networks as last resort (${heard} open networks heard)" \
                     "نحاول الشبكات المفتوحة كخيار أخير (سمعنا ${heard} شبكة مفتوحة)"
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
      (( ++tried ))
      name=$(disp_ssid "$id" "")
      if connect_id "$id"; then
        mark_crutch "$id"
        enable_all
        say_crutch_win OPEN "$name" "$name"
        return 0
      fi
      if [[ $CONNECT_WHY == "linked but no internet" ]]; then
        (( ++portals ))
        say_once "oportal:${name}" WARN "open network ${name} linked but no internet (captive portal?) - trying the next" \
                                        "الشبكة المفتوحة ${name} ارتبطت بس بدون إنترنت (صفحة دخول؟) - نجرب اللي بعدها"
      fi
      del_own "$id" || :
      rm -f "$OPEN_ID_FILE"
    done <<<"$list"
    say_once onone INFO "no open network delivered internet (${heard} heard, ${tried} tried, ${portals} linked without internet)" \
                        "ولا شبكة مفتوحة وصّلت إنترنت (سمعنا ${heard} وجرّبنا ${tried} و${portals} ارتبطت بدون إنترنت)"
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
    (( ++tried )); CONNECT_WHY=""
    if wpa set_network "$id" ssid "\"$ssid\"" | grep -q OK \
       && wpa set_network "$id" key_mgmt NONE | grep -q OK \
       && connect_id "$id"; then
      mark_crutch "$id"
      enable_all  # the winning-path law: stored networks stay armed so the supplicant
                  # can carry us HOME by itself when a real network returns (proven trap)
      say_crutch_win OPEN "$ssid" "$(pssid "$ssid")"
      return 0
    fi
    if [[ $CONNECT_WHY == "linked but no internet" ]]; then
      (( ++portals )); name=$(pssid "$ssid")
      say_once "oportal:${name}" WARN "open network ${name} linked but no internet (captive portal?) - trying the next" \
                                      "الشبكة المفتوحة ${name} ارتبطت بس بدون إنترنت (صفحة دخول؟) - نجرب اللي بعدها"
    fi
    wpa remove_network "$id" >/dev/null || :
    rm -f "$OPEN_ID_FILE"   # attempt failed and the id is gone — clear the pre-mark
  done <<<"$list"
  say_once onone INFO "no open network delivered internet (${heard} heard, ${tried} tried, ${portals} linked without internet)" \
                      "ولا شبكة مفتوحة وصّلت إنترنت (سمعنا ${heard} وجرّبنا ${tried} و${portals} ارتبطت بدون إنترنت)"
  return 1
}

# say_scan - one line per evaluation naming what the radio heard (strongest first, signal in
# dBm, at most SCAN_SAY names), which of those networks this device knows, and which stored
# networks it did not hear (out of range or off - not the same as never stored), so an
# evaluation can be followed from the site. Names only: no key ever passes through here.
# $1 = once: a recovery walks the candidates every round of every fight, so there the line
# goes through say_once keyed on the visible-known picture - said when the picture changes,
# counted by once_report while it stays the same.
readonly SCAN_SAY=10
say_scan() {
  local mode=${1:-} all=0 known=0 absent_n=0 heard="" mine="" absent="" more_en="" more_ar="" \
        ssid sig _sec id vis=$'\n' gone=$'\n' en ar
  while IFS=$'\t' read -r ssid sig _sec; do
    [[ -n $ssid ]] || continue
    (( ++all <= SCAN_SAY )) || continue
    heard+="${heard:+, }$(pssid "$ssid") ${sig%%.*}"
  done < <(scan)
  while IFS=$'\t' read -r id ssid; do
    [[ -n $id ]] || continue
    vis+="${id}"$'\n'
    (( ++known <= SCAN_SAY )) || continue
    mine+="${mine:+, }$(disp_ssid "$id" "$ssid")"
  done < <(visible_known_by_signal)
  while IFS=$'\t' read -r id ssid; do
    [[ -n $id ]] || continue
    [[ $vis == *$'\n'"${id}"$'\n'* ]] && continue
    [[ $gone == *$'\n'"${id}"$'\n'* ]] && continue   # one row per profile (an ambiguous 0x nm profile has two keys)
    gone+="${id}"$'\n'
    (( ++absent_n <= SCAN_SAY )) || continue
    absent+="${absent:+, }$(disp_ssid "$id" "$ssid")"
  done < <(known_ids)
  if (( all > SCAN_SAY )); then
    more_en=" and $(( all - SCAN_SAY )) more"; more_ar=" و$(( all - SCAN_SAY )) غيرها"
  fi
  if (( known > SCAN_SAY )); then
    mine+=" and $(( known - SCAN_SAY )) more"
  fi
  if (( absent_n > SCAN_SAY )); then
    absent+=" and $(( absent_n - SCAN_SAY )) more"
  fi
  en="scan heard ${all} networks${heard:+: ${heard}${more_en}} | known on the air: ${mine:-none} | stored, not heard: ${absent:-none}"
  ar="المسح سمع ${all} شبكة${heard:+: ${heard}${more_ar}} | المعروفة على الهواء: ${mine:-لا شيء} | مخزنة غير مسموعة: ${absent:-لا شيء}"
  if [[ $mode == once ]]; then say_once "scan:${mine}" INFO "$en" "$ar"; else site_log INFO "$en" "$ar"; fi
}

# ------------------------------- decisions -------------------------------------
say_stay() {  # $1 = candidates tried, $2 = best kbps (-1: none measured), $3 = its name, $4 = the bar,
  # $5 = the incumbent's measurement (empty inside a recovery): the way a comparison that ends
  # at home is said. Three states of one verdict, because "no challenger beat the incumbent"
  # after a walk in which nobody was measured claimed a comparison that never happened.
  local s; s=$(dssid)
  if (( $1 == 0 )); then
    site_log OK "no other known network on the air - staying on ${s}${5:+ at $5 kbps}" \
                "لا شبكة معروفة أخرى على الهواء - باقون على ${s}${5:+ بـ $5 كيلوبت/ث}"
  elif (( $2 < 0 && $1 == 1 )); then
    site_log OK "the only candidate did not deliver internet - staying on ${s}${5:+ at $5 kbps}" \
                "المرشح الوحيد ما وصل للإنترنت - باقون على ${s}${5:+ بـ $5 كيلوبت/ث}"
  elif (( $2 < 0 )); then
    site_log OK "none of the $1 candidates delivered internet - staying on ${s}${5:+ at $5 kbps}" \
                "ولا مرشح من $1 وصل للإنترنت - باقون على ${s}${5:+ بـ $5 كيلوبت/ث}"
  elif [[ -n $5 ]]; then
    site_log OK "no challenger beat the incumbent - staying on ${s} (best was $3 at $2 kbps, needed $4)" \
                "لم تتفوق أي شبكة - باقون على ${s} (الأقرب $3 بـ $2 كيلوبت/ث، والمطلوب $4)"
  else
    site_log OK "no challenger beat the incumbent - staying on ${s}" "لم تتفوق أي شبكة - باقون على ${s}"
  fi
}

best_by_upload() {  # the blueprint's heart: among working candidates, MEASURED upload decides.
  # $1 = kbps floor a challenger must beat (never-break law); $2 = incumbent id to go home to;
  # $3 = the incumbent's own measurement, for the story (empty inside a recovery: not measured).
  # best starts at -1: a working-but-very-slow candidate still beats having nothing (proven
  # that 0-init rejected all sub-107kbps networks and parked the box arbitrarily).
  # Every step is said on the site: what the radio heard (a recovery says it here, once per
  # picture), which network is tried, why one failed, which one wins and against what, why a
  # losing candidate is taken anyway, and how the way back went. The device is headless; the
  # log is the console.
  local floor="${1:-0}" home="${2:-}" here="${3:-}" home_name="" best_id="" best_ssid="" best_name="" \
        best_kbps=-1 id ssid name kbps tried=0 stopped_early=0 fallback=0 why="" why_ar="" tail_en="" tail_ar=""
  [[ -n $home ]] && home_name=$(name_of_id "$home")
  [[ -z $here ]] && say_scan once   # an evaluation said its scan already; a recovery says it here
  if ! probe_on; then
    # SIGNAL MODE (no probe target configured): measurement needs somewhere to upload
    # to; without it the strongest visible known network that DELIVERS internet wins.
    while IFS=$'\t' read -r id ssid; do
      [[ -n $home && $id == "$home" ]] && continue
      name=$(disp_ssid "$id" "$ssid")
      (( ++tried ))
      say_once "try:${id}" INFO "trying ${name}" "نجرب ${name}"
      connect_id "$id" || { say_once "fail:${id}:${CONNECT_WHY}" WARN \
                                     "could not connect to ${name}: ${CONNECT_WHY} - trying the next" \
                                     "ما قدرنا نتصل بشبكة ${name}: ${CONNECT_WHY_AR} - نجرب اللي بعدها"
                            continue; }
      enable_all
      site_log OK "connected: $(assoc_ssid) (signal mode - no upload probe target configured)" \
                  "اتصل بشبكة: $(dssid) (وضع الإشارة - لا هدف لقياس الرفع)"
      return 0
    done < <(visible_known_by_signal)
    if [[ -n $home ]] && return_to "$home" "$home_name"; then enable_all; say_stay "$tried" -1 "" 0 ""; return 0; fi
    return 1
  fi
  while IFS=$'\t' read -r id ssid; do
    # The incumbent was measured moments ago (that number IS the floor) — probing
    # it again buys nothing and costs a redundant ~15s of churn.
    [[ -n $home && $id == "$home" ]] && continue
    name=$(disp_ssid "$id" "$ssid")
    (( ++tried ))
    say_once "try:${id}" INFO "trying ${name}" "نجرب ${name}"
    connect_id "$id" || { say_once "fail:${id}:${CONNECT_WHY}" WARN \
                                   "could not connect to ${name}: ${CONNECT_WHY} - trying the next" \
                                   "ما قدرنا نتصل بشبكة ${name}: ${CONNECT_WHY_AR} - نجرب اللي بعدها"
                          continue; }
    kbps=$(up_kbps)
    if probe_failed; then
      say_probe_fail "$name"
    else
      site_log INFO "candidate [$id] ${name} uploads at ${kbps} kbps" \
                    "مرشح ${name} يرفع بسرعة ${kbps} كيلوبت/ث"
      net_kbps_note "$(cur_key)" "$kbps"   # the scan list remembers every candidate's number
    fi
    if (( kbps > best_kbps )); then best_id=$id; best_ssid=$ssid; best_name=$name; best_kbps=$kbps; fi
    (( kbps >= CUR_MIN_UP * 4 )) && { stopped_early=1; break; }  # plainly fast — stop burning probe traffic
  done < <(visible_known_ids)
  # A 0-kbps challenger must never displace a live incumbent even when the floor
  # collapsed to 0 (site down while internet up) — hence the second clause.
  if [[ -n $home ]] && (( best_kbps < floor || best_kbps <= 0 )); then
    # Nobody beat the incumbent — go home, and SAY so: a dance that opens with
    # "evaluating networks" and ends in silence reads as a hang on the dashboard.
    # A failed way home is said too (return_to); the best candidate is then taken below,
    # and the switching line says that it lost and why home is out.
    if return_to "$home" "$home_name"; then
      enable_all
      say_stay "$tried" "$best_kbps" "$best_name" "$floor" "$here"
      return 0
    fi
    fallback=1; why=$CONNECT_WHY; why_ar=$CONNECT_WHY_AR
  fi
  [[ -n $best_id ]] || return 1
  name=$(disp_ssid "$best_id" "$best_ssid")
  if (( fallback )); then
    if [[ -n $here ]]; then
      site_log INFO "switching to ${name} (${best_kbps} kbps, below the ${floor} kbps bar) - the best left, ${home_name}: ${why}" \
                    "نبدل على ${name} (${best_kbps} كيلوبت/ث، تحت الحد ${floor}) - الأفضل المتاح، ${home_name}: ${why_ar}"
    else
      site_log INFO "switching to ${name} (${best_kbps} kbps) - it delivered internet, ${home_name}: ${why}" \
                    "نبدل على ${name} (${best_kbps} كيلوبت/ث) - وصلت للإنترنت، ${home_name}: ${why_ar}"
    fi
  else
    if (( stopped_early )); then
      tail_en=" - plainly fast, over 4x the ${CUR_MIN_UP} kbps floor, probing stopped at it"
      tail_ar=" - سريعة بوضوح، فوق 4 أضعاف الحد ${CUR_MIN_UP} كيلوبت/ث، وقفنا القياس عندها"
    fi
    if [[ -n $here ]]; then
      site_log INFO "switching to ${name} (${best_kbps} kbps against ${here} kbps here)${tail_en}" \
                    "نبدل على ${name} (${best_kbps} كيلوبت/ث مقابل ${here} كيلوبت/ث هنا)${tail_ar}"
    else
      site_log INFO "switching to ${name} (${best_kbps} kbps, the fastest candidate)${tail_en}" \
                    "نبدل على ${name} (${best_kbps} كيلوبت/ث، أسرع المرشحين)${tail_ar}"
    fi
  fi
  if ! connect_id "$best_id"; then
    if [[ -z $home ]]; then
      site_log WARN "switching to ${name} failed: ${CONNECT_WHY}" \
                    "فشل التبديل على ${name}: ${CONNECT_WHY_AR}"
      return 1
    fi
    site_log WARN "switching to ${name} failed: ${CONNECT_WHY} - going back to ${home_name}" \
                  "فشل التبديل على ${name}: ${CONNECT_WHY_AR} - نرجع على ${home_name}"
    return_to "$home" "$home_name" || return 1
    enable_all
    site_log OK "back on ${home_name}" "رجعنا على ${home_name}"
    return 0
  fi
  enable_all
  note_kbps "$best_kbps"   # the site cell must pair the NEW network with ITS number
  site_log OK "switched to $(assoc_ssid) (upload ${best_kbps} kbps)" \
              "بدلنا على $(dssid) (سرعة الرفع ${best_kbps} كيلوبت/ث)"
}

evaluate_here() {  # the evaluation proper, once the slow-upload warning is out: name what the
  # radio hears, measure the incumbent and say the number with the bar a challenger must
  # clear; below the floor the comparison runs with the incumbent as home, otherwise the
  # probe cleared the alarm and that is said. A comparison that ends nowhere is said with
  # where the device is now: enable_all alone left the last line "could not return".
  local here home_id bar s now_ssid
  say_scan
  here=$(up_kbps); note_kbps "$here"   # honest baseline BEFORE leaving the incumbent
  s=$(dssid)
  if (( here < CUR_MIN_UP )); then
    bar=$(( here * CUR_GAIN / 100 ))
    if probe_failed; then
      say_probe_fail "$s"
    else
      site_log INFO "measured ${here} kbps on ${s} - under the ${CUR_MIN_UP} kbps floor, a challenger must beat ${bar} kbps" \
                    "قسنا ${here} كيلوبت/ث على ${s} - تحت الحد ${CUR_MIN_UP} كيلوبت/ث، المنافس لازم يتجاوز ${bar} كيلوبت/ث"
    fi
    home_id=$(current_id)
    if ! best_by_upload "$bar" "${home_id:-}" "$here"; then
      enable_all
      now_ssid=$(dssid)
      site_log WARN "evaluation ended with no working network - on ${now_ssid:-nothing} now, the next check decides and recovery follows if the internet is gone" \
                    "انتهى التقييم بدون شبكة شغالة - الآن على ${now_ssid:-لا شيء}، الفحص التالي يقرر والإنعاش يبدأ إن غاب الإنترنت"
    fi
  else
    site_log INFO "measured ${here} kbps on ${s} - above the ${CUR_MIN_UP} kbps floor, staying" \
                  "قسنا ${here} كيلوبت/ث على ${s} - فوق الحد ${CUR_MIN_UP} كيلوبت/ث، باقون عليها"
  fi
  return 0
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
    site_log INFO "night profile active until ${NIGHT_END} - floor ${NIGHT_MIN_UP_KBPS} kbps, a challenger must reach ${NIGHT_GAIN_PCT}% of the incumbent, evaluations $(( (NIGHT_DANCE_COOLDOWN + 59) / 60 )) min apart" \
                  "الوضع الليلي مفعل حتى ${NIGHT_END} - الحد ${NIGHT_MIN_UP_KBPS} كيلوبت/ث، المنافس لازم يوصل ${NIGHT_GAIN_PCT}% من سرعة الحالية، التقييمات كل $(( (NIGHT_DANCE_COOLDOWN + 59) / 60 )) دقيقة"
  else
    CUR_MIN_UP=$MIN_UP_KBPS; CUR_GAIN=$SWITCH_GAIN_PCT; CUR_COOLDOWN=$DANCE_COOLDOWN
    site_log INFO "day profile active until ${NIGHT_START} - floor ${MIN_UP_KBPS} kbps, a challenger must reach ${SWITCH_GAIN_PCT}% of the incumbent, evaluations $(( (DANCE_COOLDOWN + 59) / 60 )) min apart" \
                  "الوضع النهاري مفعل حتى ${NIGHT_START} - الحد ${MIN_UP_KBPS} كيلوبت/ث، المنافس لازم يوصل ${SWITCH_GAIN_PCT}% من سرعة الحالية، التقييمات كل $(( (DANCE_COOLDOWN + 59) / 60 )) دقيقة"
  fi
}

enable_stealth() {  # optional low observability; INPUT chain (aasw dropped its OWN
  # outgoing pings by mistake); -C first: rc.local respawns must not stack rules.
  # aasw's third leg (DHCP hostname hiding via dhclient.conf) is DROPPED: these
  # images use dhcpcd, not dhclient — mask the hostname in /etc/dhcpcd.conf if wanted.
  [[ $STEALTH_MODE == "yes" ]] || return 0
  # Each leg is checked, not assumed: a missing iptables or a refused rule leaves the device
  # answering pings, and avahi still active means it still announces itself.
  local bad_en="" bad_ar=""
  if ! command -v iptables >/dev/null 2>&1; then
    bad_en="iptables missing - pings still answered"; bad_ar="iptables غير موجود - الجهاز ما زال يرد على ping"
  elif ! { iptables -C INPUT -i "$IF" -p icmp --icmp-type echo-request -j DROP 2>/dev/null \
           || iptables -I INPUT -i "$IF" -p icmp --icmp-type echo-request -j DROP 2>/dev/null; }; then
    bad_en="ping rule could not be added - pings still answered"; bad_ar="ما قدرنا نضيف قاعدة حجب ping - الجهاز ما زال يرد على ping"
  fi
  systemctl stop avahi-daemon 2>/dev/null || :
  if systemctl is-active --quiet avahi-daemon 2>/dev/null; then
    bad_en+="${bad_en:+, }avahi could not be stopped"; bad_ar+="${bad_ar:+، }ما قدرنا نوقف avahi"
  fi
  if [[ -z $bad_en ]]; then
    site_log INFO "stealth mode active (icmp hidden, avahi stopped)" \
                  "وضع التخفي مفعل"
  else
    site_log WARN "stealth mode partly active: ${bad_en}" \
                  "وضع التخفي مفعل جزئياً: ${bad_ar}"
  fi
}

# ------------------------------- the fight --------------------------------------
ME_SINCE=0     # epoch when a ME-side wedge was first seen; healthy ticks clear it
LINK_OK=0      # set by connect_id when association+DHCP worked THIS round — evidence
               # gathered BEFORE any open-network teardown can poison the diagnosis
LINK_OK_NAME="" # the last network that linked with an address this round (LINK_OK's name)
LOST_AT=0      # /proc/uptime seconds at the loss line, for the restored line's duration (a Pi
               # without an RTC steps its clock at the first time sync: never date +%s here)
# Tellers of the fight: each speaks through say_once (once per outage, the rest counted after
# "internet restored") or on an edge, so a fight per tick never repeats a line.
say_nm_rc8() {  # nmcli exit 8: NetworkManager itself is not answering (the supervisor lost its hands)
  say_once nm-rc8 ERROR "NetworkManager is not answering nmcli (exit 8) - stored networks cannot be tried until it is restarted (recover L3)" \
                        "مدير الشبكة ما يرد على nmcli (رمز 8) - ما نقدر نجرب الشبكات المحفوظة حتى يعاد تشغيله (الإنعاش م3)"
}
say_clock_armed() {  # the 0 -> set edge of ME_SINCE: the deadline, in the site's zone. The valve
  # fires at the end of the first losing fight after it, hence "after", not "at".
  local at; at=$(stamp -d "@$(( ME_SINCE + REBOOT_AFTER_MIN * 60 ))" '+%H:%M' 2>/dev/null) || at="?"
  say_once armed WARN "reboot clock armed - the device reboots after ${at} unless the internet returns or the fault reads external" \
                      "بدأ عدّاد الريبوت - الجهاز يعيد تشغيل نفسه بعد الساعة ${at} إلا إذا رجع الإنترنت أو صار العطل خارجياً"
}
say_clock_clear() {  # nm only: NM showed a connecting or readable state after the clock was armed
  say_once clock-clear INFO "reboot clock cleared - NetworkManager picked the device up again" \
                            "انصفر عدّاد الريبوت - مدير الشبكة رجع يشتغل على الجهاز"
}
IF_SEEN=0
if_check() {  # the interface can vanish mid-run (a USB dongle unplugged, a netdev gone after a
  # firmware crash): said once per outage at every fight start, counted after that. Only an
  # interface that was seen alive can vanish; one absent from the start has its own start line.
  if iw dev "$IF" info >/dev/null 2>&1; then IF_SEEN=1; return 0; fi
  (( IF_SEEN )) || return 0
  say_once if-gone ERROR "interface ${IF} has vanished - WiFi hardware or driver gone, rung L3 reloads the driver (a USB dongle needs replugging)" \
                         "واجهة ${IF} اختفت - عتاد الواي فاي أو تعريفه ضاع، الإنعاش م3 يعيد تحميل التعريف (وصلة USB تحتاج فصلاً وتوصيلاً)"
}
auth_names() {  # the networks refusing association: wpa's TEMP-DISABLED rows (the supplicant's
  # own mark), or the nm candidate whose activation carried the credentials text
  local id ssid rest names=""
  if [[ $BACKEND != wpa ]]; then printf '%s' "$NM_AUTH_SSID"; return 0; fi
  while IFS=$'\t' read -r id ssid rest; do
    [[ $rest == *TEMP-DISABLED* ]] || continue
    names+="${names:+, }$(pssid "$ssid")"
  done < <(wpa list_networks | tail -n +2)
  printf '%s' "$names"
}
ME_KEY="" ME_EN="" ME_AR=""
me_tell() {  # $1 = the visible stored rows already read this round: which device-side tell holds,
  # in the order the classification tests them. Names capped at SCAN_SAY, never a key.
  local id ssid n names="" c=0
  if [[ -n $1 ]]; then
    while IFS=$'\t' read -r id ssid; do
      [[ -n $id ]] || continue
      (( ++c <= SCAN_SAY )) || continue
      n=$(disp_ssid "$id" "$ssid"); names+="${names:+, }${n:-$id}"
    done <<<"$1"
    ME_KEY=cannot-join
    ME_EN="${names}$( (( c > SCAN_SAY )) && printf ' and %d more' "$(( c - SCAN_SAY ))" ) on the air but this device cannot join"
    ME_AR="${names}$( (( c > SCAN_SAY )) && printf ' و%d غيرها' "$(( c - SCAN_SAY ))" ) ظاهرة بس الجهاز ما يقدر يرتبط بها"
  elif [[ -z $(scan) ]]; then
    ME_KEY=deaf; ME_EN="the radio hears no network at all"; ME_AR="الراديو ما يسمع أي شبكة"
  elif (( NM_RC8 )); then
    ME_KEY=unread; ME_EN="the stored network list cannot be read"; ME_AR="قائمة الشبكات المحفوظة ما تنقرأ"
  else
    ME_KEY=empty; ME_EN="the stored network list reads empty"; ME_AR="قائمة الشبكات المحفوظة فاضية"
  fi
}
say_crutch_win() {  # $1 = EMERGENCY | OPEN, $2 = the name for the English line, $3 = for the Arabic
  # one: a temporary network delivered internet and the fight ends on it. One probe measures
  # it (the cell pairs the number with the crutch); signal mode says so instead of a number.
  local kbps=0
  if probe_on; then kbps=$(up_kbps); note_kbps "$kbps"; fi
  if [[ $1 == EMERGENCY ]]; then
    site_log OK "connected to EMERGENCY network: $2 ($(up_words "$kbps")) - stored networks stay armed, home again when one returns" \
                "اتصل بشبكة الطوارئ: $3 ($(up_words_ar "$kbps")) - الشبكات المحفوظة تبقى مفعّلة ونرجع لها أول ما ترجع"
  else
    site_log OK "connected to OPEN network: $2 ($(up_words "$kbps")) - stored networks stay armed, home again when one returns" \
                "اتصل بشبكة مفتوحة: $3 ($(up_words_ar "$kbps")) - الشبكات المحفوظة تبقى مفعّلة ونرجع لها أول ما ترجع"
  fi
}
say_restored() {  # $1 = recovery runs of the outage: the documented head, then how long the
  # internet was down (from /proc/uptime) and how many recoveries it took
  local s down_en="" down_ar="" runs_en=runs
  s=$(dssid); s=${s:-$IF}
  (( $1 == 1 )) && runs_en=run
  if (( LOST_AT > 0 )); then
    down_en="down $(dur_words "$(( $(uptime_s) - LOST_AT ))"), "
    down_ar="انقطع $(dur_words_ar "$(( $(uptime_s) - LOST_AT ))")، "
  fi
  site_log OK "internet restored: ${s} - ${down_en}$1 recovery ${runs_en}" \
              "رجع الانترنت عبر: ${s} - ${down_ar}$1 محاولة إنعاش"
  LOST_AT=0
}
PREF_VETO_ID="" PREF_VETO_UNTIL=0  # a preferred network that measured too slow is
               # benched for 3 cooldowns — ends the pref-vs-dance switch war (proven)
# Reporting doctrine: AWACS reports AS RICHLY as aasw did — every
# meaningful event goes local AND to the site (Arabic), per event, not per streak;
# offline events spool (SPOOL_CAP deep) and the whole story lands after recovery.

fight() {  # no internet: escalate calmly, measure honestly, reboot only for OUR OWN wedge
  local round nm_working=0 st alive=0 home_id="" home_name="" gw=0 me=0 vis="" k n names auth_now=0 armed_now=0
  if_check           # a vanished interface is the first fact of the fight
  drop_open failed   # yesterday's crutch must not shadow today's real networks
  enable_all
  arm_hidden   # an EXTERNAL supplicant restart strips runtime scan_ssid — re-arm every engagement
  if [[ $BACKEND != wpa ]]; then
    NM_ERR=""; NM_RC=0; NM_AUTH=0   # fresh activation evidence for THIS fight
    nm_wait_settled                  # never act while NM is mid-transition
  fi
  # A link whose gateway is reachable is ALIVE: the outage is upstream and a reassociate
  # would only drop a working association (uploads, streams, LAN viewers) for nothing.
  # Remember that network as HOME: the rounds still evaluate the others (a hotspot on
  # another uplink may deliver), but failed tries end back on it. The skip is bounded to
  # the streak's first fight - a router that answers ping yet forwards nothing for this
  # station is cured by a fresh association, so the second fight performs it once.
  if link_alive; then alive=1; home_id=$(current_id); home_name=$(name_of_id "$home_id"); home_name=${home_name:-$IF}; fi
  # What the router does decides the opening, and the opening is said once per outage: the
  # alive link is kept (the round tries the OTHER stored networks around it), the second wpa
  # fight reassociates anyway, a dead link waits for the base layer. On nm reassociate acts
  # only on a disconnected device, so the alive line is the truth in every fight there.
  if (( alive && FIGHT_STREAK <= 1 )); then
    dbg "gentle open skipped: the link is alive (gateway reachable) - the outage is upstream"
    say_once open:alive INFO "router answers on ${home_name} - keeping the link, trying the other stored networks first" \
                             "الراوتر يرد على ${home_name} - نحافظ على الوصلة ونجرب باقي الشبكات المحفوظة أولاً"
  else
    if (( alive )) && [[ $BACKEND == wpa ]]; then
      say_once open:alive-retry INFO "router answers on ${home_name} but forwards nothing - reassociating anyway this time" \
                                     "الراوتر يرد على ${home_name} بس ما يوصّل - نعيد الارتباط هذي المرة"
    elif (( alive )); then
      say_once open:alive INFO "router answers on ${home_name} - keeping the link, trying the other stored networks first" \
                               "الراوتر يرد على ${home_name} - نحافظ على الوصلة ونجرب باقي الشبكات المحفوظة أولاً"
    else
      say_once open:dead INFO "router not answering - waiting up to ${ASSOC_WAIT} s for ${IF} to reconnect" \
                              "الراوتر ما يرد - ننتظر حتى ${ASSOC_WAIT} ث ترجع ${IF} تتصل"
    fi
    reassociate
  fi
  # Credit the verified moment (connect_id's doctrine, same words): a gentle heal
  # that dies sub-tick must not leave a stale wedge streak for the reboot valve —
  # this was the LAST net_up=1 site that could carry an uncredited stale stamp.
  wait_ip && net_ok && { net_up=1; ME_SINCE=0; return 0; }

  for round in 1 2 3; do
    nm_working=0
    if [[ $BACKEND != wpa ]]; then
      # NM healed mid-fight (its autoconnect won while we slept/probed)? CREDIT AND
      # EXIT with zero further overrides — an override here would stomp its success.
      nm_wait_settled
      net_ok && { net_up=1; ME_SINCE=0; return 0; }
      # Deference is decided BEFORE any candidate probe: a con-up must never race a
      # NM that is actively working the device (proven con-ups inside the band).
      if nm_busy; then
        nm_working=1
        say_once nm-wait INFO "NM is still trying - waiting it out" \
                              "مدير الشبكة يحاول يتصل - ننتظره ولا نتدخل"
      fi
      # A busy sighting ANYWHERE in the streak means "still retrying" — never a
      # wedge: the clock and the settled count start over from that moment.
      if (( NM_SAW_BUSY )); then (( ME_SINCE > 0 )) && say_clock_clear; ME_SINCE=0; NM_SETTLED_SEEN=0; NM_SAW_BUSY=0; fi
    fi
    LINK_OK=0
    if (( ! nm_working )); then
      best_by_upload 0 "$home_id" && return 0   # home set = the incumbent is excluded and returned to
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
    # The tells are gathered once (gw_ok pings, visible_known_ids scans) and kept: the verdict
    # lines below name which tell decided, on either side. Same tests, same order as before.
    me=0; gw=0; vis=""; auth_now=0
    if (( ! nm_working )); then
      gw_ok && gw=1
      if (( ! gw && ! LINK_OK )); then
        vis=$(visible_known_ids)
        if [[ -n $vis ]] || [[ -z $(scan) ]] || [[ -z $(known_ids) ]]; then me=1; me_tell "$vis"; fi
      fi
    fi
    if (( me )); then
      if auth_failing; then
        # Wrong password rides the SAME evidence signature as a wedge. The LADDER
        # still runs (a real wedge can coincide with one stale hotspot password —
        # skipping recovery entirely was a proven starvation), but the reboot clock
        # stays UNARMED: no reboot on earth fixes credentials.
        auth_now=1; names=$(auth_names)
        if [[ -n $names ]]; then
          say_once "auth:${names}" ERROR "association refused by ${names} - wrong password? (recovery continues, reboot stays off)" \
                                        "${names} رفضت الارتباط - كلمة سر خاطئة؟ (الإنعاش مستمر والريبوت ممنوع)"
        else
          say_once auth ERROR "association refused - wrong password? (recovery continues, reboot stays off)" \
                              "الشبكة رفضت الاتصال - كلمة سر خاطئة؟ (الإنعاش مستمر والريبوت ممنوع)"
        fi
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
          if (( ME_SINCE == 0 )); then
            ME_SINCE=$(date +%s)
            # wpa: the verdict line below comes first and the clock line follows it. nm says it
            # here, because its branches below can leave the round before the verdict.
            if [[ $BACKEND == wpa ]]; then armed_now=1; else say_clock_armed; fi
          fi
        fi
      fi
      dbg "fight round $round: ME evidence (LINK_OK=0, gw unreachable, auth_failing=$(auth_failing && echo 1 || echo 0))"
      # RUNG BOUNDARY (seen live in NetworkManager's journal): the evidence above takes
      # ~12 s to gather; inside that window NM's own autoconnect had already ACTIVATED
      # the home network, and L1 bounced the radio 5 s after "Activation: successful"
      # — a needless outage of NM's own win (N13/§6 at the rung boundary). Let NM
      # settle, credit a heal, and never fire a rung at a device NM reports connected.
      if [[ $BACKEND != wpa ]]; then
        nm_wait_settled
        net_ok && { enable_all; net_up=1; ME_SINCE=0; return 0; }
        st=$(nm_dev_state); nm_note_state "$st"
        if (( (st >= 40 && st <= 90) || st == 110 )); then
          # NM picked the device up again WHILE the evidence was gathered (a con-up
          # that outlived -w, or its own autoconnect): the round-top rule applies here
          # too — its activation finishes or fails on its own, never under a rung.
          say_once nm-wait INFO "NM is still trying - waiting it out" \
                                "مدير الشبكة يحاول يتصل - ننتظره ولا نتدخل"
          sleep 20; continue
        fi
        if (( st >= 100 && st < 110 )); then
          # associated with an IP but no internet = the router's problem, not ours
          ME_SINCE=0
          say_once nm-router INFO "NetworkManager is connected, internet is not (round $round) — router-side, no rung" \
                                  "NetworkManager متصل والإنترنت مقطوع (جولة $round) — المشكلة عند الراوتر، لا إنعاش"
          { try_safety || try_open; } && return 0
          sleep 20; continue
        fi
      fi
      # The verdict, right before the rung so "recovery follows" is true on both backends (the
      # nm branches above continue without one). The credentials line carries its own verdict.
      (( auth_now )) || say_once "me:${ME_KEY}" WARN "fault looks on the device: ${ME_EN} - recovery follows" \
                                                     "العطل يبدو في الجهاز: ${ME_AR} - يليها الإنعاش"
      (( armed_now )) && { armed_now=0; say_clock_armed; }   # wpa: the clock, after the verdict
      recover "$round"
      # Credit a heal the rung ITSELF produced — without this the same round hunted
      # a crutch and parked the box on an open stranger beside the user's own healthy
      # network, reporting it as a win (needed on both backends).
      net_ok && { enable_all; net_up=1; ME_SINCE=0; return 0; }   # enable_all: the win law
      { try_safety || try_open; } && return 0
      enable_all   # a failed crutch must not leave the supplicant with zero enabled networks
    else
      ME_SINCE=0
      # Which tell made it external, in the classification's own order: NM busy (its line just
      # above explains it, the text stays), the router answering, a network that linked without
      # internet, or no stored network on the air. The round stays in the text and out of the
      # key, so once_report's count spans rounds as before.
      if (( nm_working )); then
        say_once external INFO "outage looks external (round $round) — waiting, not rebooting" \
                               "الانقطاع يبدو خارجياً (جولة $round) — ننتظر بلا إعادة تشغيل"
      elif (( gw )); then
        say_once external:gw INFO "outage looks external: the router answers, the fault is upstream (round $round) — waiting, not rebooting" \
                                  "الانقطاع يبدو خارجياً: الراوتر يرد والعطل عند المزود (جولة $round) — ننتظر بلا إعادة تشغيل"
      elif (( LINK_OK )); then
        say_once external:linked INFO "outage looks external: ${LINK_OK_NAME:-a stored network} linked but no internet, the fault is behind that network (round $round) — waiting, not rebooting" \
                                      "الانقطاع يبدو خارجياً: ${LINK_OK_NAME:-شبكة مخزنة} ارتبطت بس بدون إنترنت والعطل وراها (جولة $round) — ننتظر بلا إعادة تشغيل"
      else
        k=$(known_ids | cut -f1 | sort -u | grep -c .) || k=0
        n=$(scan | grep -c .) || n=0
        say_once external:absent INFO "outage looks external: none of your ${k} stored networks is on the air, ${n} others heard (round $round) — waiting, not rebooting" \
                                      "الانقطاع يبدو خارجياً: ولا واحدة من شبكاتك الـ${k} ظاهرة وسمعنا ${n} غيرها (جولة $round) — ننتظر بلا إعادة تشغيل"
      fi
      net_ok && { enable_all; net_up=1; return 0; }   # healed meanwhile — re-arm all, then leave
      { try_safety || try_open; } && return 0
      # Failed tries end back HOME (the live link), never parked on a stranger or with
      # zero enabled networks through the wait: the upstream may return any second.
      # A failed way back is said once per outage - unless connect_id never left home (no
      # crutch configured: be_activate's already-riding shortcut) and failed on the internet
      # test, which is the external outage itself, not a failed return.
      if [[ -n $home_id ]] && ! connect_id "$home_id" >/dev/null 2>&1 \
         && [[ $CONNECT_WHY != "linked but no internet" ]]; then
        say_once home-fail WARN "could not return to ${home_name}: ${CONNECT_WHY} - stored networks re-enabled, waiting 20 s" \
                                "ما قدرنا نرجع على ${home_name}: ${CONNECT_WHY_AR} - أعدنا تفعيل الشبكات المحفوظة وننتظر 20 ث"
      fi
      enable_all
      sleep 20
    fi
  done

  # Not while REBOOTING: a reboot already ordered is waiting on its 60 s grace (reboot_failed_check);
  # ordering another would restart that grace and hide a reboot command that fails.
  if (( ! REBOOTING && ME_SINCE > 0 && $(date +%s) - ME_SINCE >= REBOOT_AFTER_MIN * 60 )) \
     && { [[ $BACKEND == wpa ]] || nm_me_settled; }; then
    # The net is down, so the line spools; reboot_memory_save copies the spool and a marker
    # to the SD card, and the next start restores the story and names this reboot as ours.
    reboot_memory_save
    sync; sleep 2; reboot
  fi
  # A LOSING fight's last act was a crutch teardown that left the supplicant with
  # zero enabled networks — hand it back its full autonomy before returning, so a
  # dead-AWACS window between engagements can never strand the box (proven gap).
  enable_all
  return 1
}

# ------------------------------- late answers ----------------------------------
# A loaded uplink answers late, not never: the quick ladder times out, the patient look passes
# and the tick counts healthy. That is a decision NOT to engage, said as an episode rather than
# per tick (the raw line recurs every 40-60 s under sustained load): an opener at the first late
# pass, a count line at most once an hour while the episode lasts, a closer after 30 quick passes
# in a row (about 5 min). A new episode opens no sooner than 30 min after the last closer; the
# late passes inside that quiet window are folded into the next opener's span and count.
LATE_TICK=0 LATE_OPEN=0 LATE_N=0 LATE_SAID=0 LATE_SINCE=0 LATE_QUICK=0 LATE_CLOSED=0 LATE_REPORT=0
late_note() {  # one late pass (the patient look passed after the quick ladder timed out)
  local now; now=$(uptime_s)
  LATE_TICK=1; LATE_QUICK=0
  (( LATE_N == 0 )) && LATE_SINCE=$now
  (( ++LATE_N ))
  if (( ! LATE_OPEN )) && (( LATE_CLOSED == 0 || now - LATE_CLOSED >= 1800 )); then
    LATE_OPEN=1; LATE_REPORT=$now; LATE_SAID=$LATE_N
    site_log INFO "uplink answering late on $(dssid) - ${NET_FAIL_TICKS} quick checks timed out, the patient check passed, no recovery" \
                  "الوصلة تجيب متأخراً على $(dssid) - ${NET_FAIL_TICKS} فحوصات سريعة انتهت مهلتها، الفحص الصبور نجح، لا إنعاش"
  fi
}
late_tick() {  # every healthy tick: the closer after 30 quick passes in a row, else the hourly count
  local now; now=$(uptime_s)
  (( LATE_TICK )) || (( ++LATE_QUICK ))
  if (( ! LATE_OPEN )); then (( LATE_QUICK >= 30 )) && LATE_N=0; return 0; fi   # the quiet window's fold expires
  if (( LATE_QUICK >= 30 )); then
    site_log INFO "uplink answers normally again on $(dssid) - answered late ${LATE_N} times over $(dur_words "$(( now - LATE_SINCE ))")" \
                  "الوصلة ترد طبيعياً مرة أخرى على $(dssid) - تأخرت ${LATE_N} مرة خلال $(dur_words_ar "$(( now - LATE_SINCE ))")"
    LATE_OPEN=0; LATE_N=0; LATE_SAID=0; LATE_QUICK=0; LATE_CLOSED=$now
    return 0
  fi
  if (( now - LATE_REPORT >= 3600 && LATE_N > LATE_SAID )); then
    site_log INFO "internet answered late $(( LATE_N - LATE_SAID )) more times in the last hour on $(dssid) - slow link, no recovery" \
                  "الإنترنت تأخر $(( LATE_N - LATE_SAID )) مرة زيادة في الساعة الأخيرة على $(dssid) - الوصلة بطيئة، لا حاجة للإنعاش"
    LATE_SAID=$LATE_N; LATE_REPORT=$now
  fi
}
late_loss() {  # $1 = the network lost: the loss ends an open episode, its uncounted passes said with it
  if (( LATE_OPEN && LATE_N > LATE_SAID )); then
    site_log INFO "internet answered late $(( LATE_N - LATE_SAID )) more times before this loss on $1 - slow link" \
                  "الإنترنت تأخر $(( LATE_N - LATE_SAID )) مرة زيادة قبل هذا الانقطاع على $1 - الوصلة بطيئة"
  fi
  LATE_OPEN=0; LATE_N=0; LATE_SAID=0; LATE_QUICK=0; LATE_CLOSED=0
}

# ------------------------------- site commands ---------------------------------
# The owner's Wi-Fi menu on the site: scan now, switch to a stored network, join a new one
# with a password typed there. capture.sh relays each command into CMD_FILE and wakes the
# loop with USR1; the loop top is the ONE consumer (never a fight, never an evaluation), so a
# command can never re-enter the radio logic between two supplicant calls. Every answer is a
# data line the site words itself; every step is a site line in AWACS's voice; no password,
# key, ciphertext or blob ever reaches a log or a site line (SSIDs may).
readonly CMD_TTL=60           # a command older than this by uptime waited behind a recovery: answered expired
readonly TRIAL_WAIT=15        # the owner's number: a manual trial holds the network this long, then measures
readonly TRIAL_HEAD=5         # the trying answer stands alone this long before the measuring answer, so the site's polls see it
readonly TRIAL_POST_GAP=2     # the probe waits this long at most for the trying answer's child to leave the uplink
readonly TRIAL_ASSOC_WAIT=45  # a manual trial's association budget: a new or far network scans 7 to 23 s before it
                              # authenticates (lab, hwsim), and the 25 s of ASSOC_WAIT answered such networks out_of_reach
readonly ORIGIN_KBPS_AGE=120  # the origin's last measurement counts as fresh this long, else one probe
readonly HOLD_MAX=86400       # the longest hold a switch may ask for: one day (the site asks 1800)
CMD_EPOCH=0                   # the site's epoch of the command being answered (its id on the site)
KEY_SENT=0                    # the key reached the site this boot (2xx): later sends are skipped
CMD_STUCK=0                   # the consumer could not remove the command file: the served-now guard stands down
KEY_REFUSED_SAID=0            # the site holds another key: said once per boot
ORIGIN_ID="" ORIGIN_NAME="" ORIGIN_KBPS=0   # where a trial leaves from, for the way back
TRIAL_AT=0                    # unix time of the last manual trial: the loop counts it as a dance
HOLD_UNTIL=0 HOLD_NAME=""     # the owner's hold from the menu: the uptime it ends (0 = none) and the
                              # network's name. Memory only: a restart forgets it.
HOLD_EVAL_SAID=0              # the evaluation vetoed by a hold is said once per hold
TRIAL_HOLD_PID="" TRIAL_HEAD_PID="" TRIAL_PROBE_PID=""   # the trial's window sleep, head sleep and probe child while they run: on_shutdown ends them
TRIAL_POST_PID=""   # the child carrying a trial's mid-way answer to the site; the trial waits for it only where it is idle anyway
TRIAL_TIMER_PID=""  # wait_first's timer child while it runs: on_shutdown ends it too

cmd_ready_drop() {  # the lock winner's exit: capture.sh must not signal a PID that no longer traps
  (( LOCK_WON )) && rm -f "$CMD_READY" 2>/dev/null
  return 0
}

cmd_answer() {  # STATE [FIELD...]: the latest answer, kept in CMD_ANSWER and sent now in the
  # foreground; cmd_answer_send re-sends it on every healthy tick until the site takes it. A
  # fire-and-forget POST from a trial network without internet would lose the very answer
  # the owner waits for. A trial's mid-way answers go through trial_post instead.
  cmd_answer_put "$@"
  cmd_answer_send
}
cmd_answer_put() {  # STATE [FIELD...] -> CMD_ANSWER: the line every sender reads. Written by the
  # main shell only, and never while a trial's answer child still runs, so no two senders ever
  # race over the one file.
  local line=$1 f
  line="$(date +%s)"$'\t'"${CMD_EPOCH}"$'\t'"${line}"
  shift
  for f in "$@"; do line+=$'\t'"${f//[[:cntrl:]]/ }"; done   # a field never carries the separators
  printf '%s\n' "$line" >"$CMD_ANSWER" 2>/dev/null || :
}
cmd_answer_send() {  # CMD_ANSWER -> tmp/wifi_state.tmp through the device write channel; gone on 2xx
  [[ -s $CMD_ANSWER ]] || return 0
  [[ -n $SITE_URL ]] || { rm -f "$CMD_ANSWER" 2>/dev/null; return 0; }   # no site: nobody asked
  local line code
  IFS= read -r line <"$CMD_ANSWER" || return 0
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 --data-urlencode "file=tmp/wifi_state.tmp" \
    --data-urlencode "data=${line}" "$(api_url)" 2>/dev/null) || code=000
  [[ $code =~ ^2[0-9][0-9]$ ]] && rm -f "$CMD_ANSWER" 2>/dev/null
  return 0
}

# The hold. A switch may carry hold=<seconds> in its fifth field: the owner wants to stay on the
# chosen network that long. The trial runs as always; a verdict that would return to the origin
# is skipped while the network has internet. For the hold's seconds (uptime clock) the
# preferred-network look and the evaluation do not run, since both can leave the network. The
# fight is untouched: a real outage ends the hold (reachability first), so does a new command,
# and the hold expires by itself. Nothing is written to disk: a restart forgets the hold.
hold_start() {  # $1 = name, $2 = seconds
  HOLD_NAME=$1; HOLD_UNTIL=$(( $(uptime_s) + $2 )); HOLD_EVAL_SAID=0
  site_log INFO "hold on $1 for $(dur_words "$2") - no preferred-network return and no evaluation leaves it; an internet loss or a new command ends it" \
                "تثبيت على $1 لمدة $(dur_words_ar "$2") - لا رجوع لشبكة مفضلة ولا تقييم يتركها؛ ينتهي بانقطاع الإنترنت أو بأمر جديد"
}
hold_on() {  # the hold stands: asked, and its uptime not yet reached
  (( HOLD_UNTIL > 0 && $(uptime_s) < HOLD_UNTIL ))
}
hold_end() {  # $1 = why (en), $2 = why (ar): said once, then forgotten. Silent when no hold stands.
  (( HOLD_UNTIL > 0 )) || return 0
  site_log INFO "hold on ${HOLD_NAME} ended - $1" "انتهى التثبيت على ${HOLD_NAME} - $2"
  HOLD_UNTIL=0; HOLD_NAME=""
  return 0
}
hold_check() {  # the loop top: a hold whose time has passed ends with its line, nothing else happens
  (( HOLD_UNTIL > 0 )) || return 0
  (( $(uptime_s) >= HOLD_UNTIL )) && hold_end "back to its own judgement" "رجعنا لحكم أواكس"
  return 0
}
hold_eval_veto() {  # $1 = flow kbps, $2 = floor: under a hold the evaluation does not run (it could
  # leave the held network); said once per hold with when the hold ends. Returns 0 when vetoed.
  hold_on || return 1
  if (( ! HOLD_EVAL_SAID )); then
    HOLD_EVAL_SAID=1
    site_log INFO "upload slow on ${HOLD_NAME} ($1 kbps, floor $2) - held from the menu, no evaluation until the hold ends in $(dur_words "$(( HOLD_UNTIL - $(uptime_s) ))")" \
                  "الرفع بطيء على ${HOLD_NAME} ($1 كيلوبت/ث، الحد $2) - مثبّتة من القائمة، لا تقييم حتى ينتهي التثبيت بعد $(dur_words_ar "$(( HOLD_UNTIL - $(uptime_s) ))")"
  fi
  return 0
}

cmd_reason() {  # connect_id's CONNECT_WHY -> the answer's reason token (the HUD's word)
  case $1 in
    "refused - wrong password?") printf 'wrong_password' ;;
    "linked but no internet")    printf 'no_internet' ;;
    *)                           printf 'out_of_reach' ;;   # never associated, not found, no address, timed out
  esac
}

wifi_cmd_check() {  # $1 = engaged (the loop's fight flag): the one consumer, at the loop top. Reads,
  # validates, dedupes and ages the command, answers taken and hands it to its handler. The file
  # goes before anything else runs, so a crash inside a handler cannot replay the command.
  local line up epoch cmd key blob last="" now hold=0
  (( WIFI_CMD )) || [[ -s $CMD_FILE ]] || return 0
  WIFI_CMD=0
  [[ -s $CMD_FILE ]] || return 0
  IFS= read -r line <"$CMD_FILE" || line=""
  rm -f "$CMD_FILE" 2>/dev/null || { CMD_STUCK=1
    llog WARN "site command file could not be removed - site commands are off until the next start" "تعذّر حذف ملف أمر الموقع - أوامر الموقع متوقفة حتى التشغيل القادم"; }
  IFS=$'\t' read -r up epoch cmd key blob <<<"$line"
  [[ $up =~ ^[0-9]{1,9}$ && $epoch =~ ^[0-9]{1,12}$ && $cmd =~ ^(scan|switch|join)$ ]] || {
    llog INFO "site command dropped - unreadable line" "أُسقط أمر الموقع - سطر غير مقروء"; return 0; }
  read -r last 2>/dev/null <"$CMD_LAST" || last=""
  [[ $epoch == "$last" ]] && { llog INFO "site command ${cmd} delivered twice (epoch ${epoch}) - already handled" \
                                         "أمر الموقع ${cmd} وصل مرتين (${epoch}) - سبق تنفيذه"; return 0; }
  printf '%s\n' "$epoch" >"$CMD_LAST" 2>/dev/null || :
  CMD_EPOCH=$epoch
  now=$(uptime_s)
  if (( up > now || now - up > CMD_TTL )); then   # a stamp from the future can only be another boot's
    site_log INFO "site command ${cmd} expired - it waited $(dur_words "$(( now - up ))") behind a recovery, tap again" \
                  "انتهى أمر الموقع ${cmd} - انتظر $(dur_words_ar "$(( now - up ))") خلف الإنعاش، اضغط مرة ثانية"
    cmd_answer failed expired; return 0
  fi
  if (( ${1:-0} )); then
    site_log INFO "site command ${cmd} refused - a recovery is running, tap again when the internet is back" \
                  "رُفض أمر الموقع ${cmd} - الإنعاش شغال، اضغط مرة ثانية بعد رجوع الإنترنت"
    cmd_answer failed busy; return 0
  fi
  hold_end "a new command from the site" "وصل أمر جديد من الموقع"   # any served command ends a standing hold; a held switch starts its own
  case $cmd in
    scan)   cmd_answer taken; wifi_cmd_scan ;;
    switch) [[ $key =~ ^([0-9a-f]{2}){1,32}$ ]] || {
              llog INFO "site switch dropped - no network key" "أُسقط أمر التبديل - بلا مفتاح شبكة"
              cmd_answer failed out_of_reach; return 0; }
            # The fifth field, a join's blob slot, may carry hold=<seconds> on a switch (the site
            # sends 1800). Anything else there is not a hold and the switch runs without one.
            if [[ $blob =~ ^hold=([1-9][0-9]{0,5})$ ]] && (( BASH_REMATCH[1] <= HOLD_MAX )); then hold=${BASH_REMATCH[1]}
            elif [[ -n $blob ]]; then
              llog INFO "site switch: the fifth field is not a hold - switching without one" "أمر التبديل: الحقل الخامس ليس تثبيتاً - نبدّل بدون تثبيت"
            fi
            cmd_answer taken; wifi_cmd_switch "$key" "$hold" ;;
    join)   [[ $key =~ ^([0-9a-f]{2}){1,32}$ && -n $blob ]] || {
              llog INFO "site join dropped - no network key or no password" "أُسقط أمر الانضمام - بلا مفتاح شبكة أو بلا كلمة سر"
              cmd_answer failed key_changed; return 0; }
            cmd_answer taken; wifi_cmd_join "$key" "$blob" ;;
  esac
  return 0
}

wifi_cmd_scan() {  # a real radio scan now, past the SCAN_TTL cache and the publish gate; the list
  # goes out before the answer, so the menu reads fresh rows the moment the HUD says done
  local n=0 now
  (( net_up )) || {
    site_log INFO "scan asked from the site while offline - the list cannot be published until the internet is back" \
                  "طُلب مسح من الموقع والإنترنت مقطوع - القائمة ما تنشر حتى يرجع الإنترنت"
    cmd_answer failed offline; return 0; }
  streaming && site_log INFO "scan asked from the site under a live stream - a few seconds of stutter" \
                             "طُلب مسح من الموقع أثناء بث مباشر - ثوانٍ من التقطيع"
  cmd_answer scanning
  now=$(date +%s)
  if [[ $BACKEND != wpa ]]; then
    nmcli device wifi rescan ifname "$IF" >/dev/null 2>&1 || :   # NM's own radio scan: no iw EBUSY
    nm_wifi_list yes >/dev/null                                   # --rescan yes waits for that scan's picture
    n=$(nm_wifi_list no | grep -c .) || n=0
    SCAN_NM_AT=$now   # the footer's stamp, even when the air did not change
  else
    rm -f "$SCAN_CACHE" 2>/dev/null || :   # past the cache: the radio is asked now
    scan >/dev/null
    n=$(grep -c . "$SCAN_CACHE" 2>/dev/null) || n=0
  fi
  SCAN_LIST_AT=0; SCAN_LIST_SCAN=""   # past the publish gate: the list and its footer refresh
  report_scan now
  site_log INFO "scan from the site heard ${n} networks - list published" \
                "المسح المطلوب من الموقع سمع ${n} شبكة - نُشرت القائمة"
  cmd_answer 'done' "$n"
}

wifi_id_by_key() {  # $1 = SSID hex -> the stored id for it, a visible one first; nothing when not
  # stored. Exact bytes, never the display name: the site names a network by this key.
  local id ssid k first="" vis
  vis=$'\n'"$(visible_known_ids)"$'\n'
  while IFS=$'\t' read -r id ssid; do
    [[ -n $id ]] || continue
    if [[ $BACKEND != wpa ]]; then k=$ssid; else k=$(iw2hex "$ssid"); fi
    [[ $k == "$1" ]] || continue
    [[ $vis == *$'\n'"${id}"$'\t'* ]] && { printf '%s' "$id"; return 0; }
    first=${first:-$id}
  done < <(known_ids)
  printf '%s' "$first"
}

wifi_cmd_switch() {  # $1 = SSID hex of a stored network, $2 = hold seconds (0 = none): the
  # challenger's trial, answered switched; with a hold the verdict keeps the network either way
  local id name k=0 reason hold=${2:-0}
  (( net_up )) || {
    site_log INFO "switch asked from the site while offline - recovery decides the network until the internet is back" \
                  "طُلب تبديل من الموقع والإنترنت مقطوع - الإنعاش يقرر الشبكة حتى يرجع الإنترنت"
    cmd_answer failed offline; return 0; }
  id=$(wifi_id_by_key "$1")
  [[ -n $id ]] || {
    site_log WARN "switch asked from the site to $(hex_disp "$1") - not a stored network, nothing to try" \
                  "طُلب تبديل من الموقع إلى $(hex_disp "$1") - ليست شبكة مخزنة، لا شيء نجربه"
    cmd_answer failed out_of_reach; return 0; }
  name=$(name_of_id "$id")
  if [[ $id == "$(current_id)" ]]; then
    [[ $LAST_KBPS_ID == "$id" ]] && k=$LAST_KBPS
    if (( hold > 0 )); then   # the owner's "keep me here": no trial, the hold starts now
      site_log INFO "switch asked from the site to ${name} - already on it, holding it" \
                    "طُلب تبديل من الموقع إلى ${name} - نحن عليها أصلاً، نثبّت عليها"
      hold_start "$name" "$hold"
      cmd_answer switched "$name" "$k" "hold=${hold}"; return 0
    fi
    site_log INFO "switch asked from the site to ${name} - already on it" "طُلب تبديل من الموقع إلى ${name} - نحن عليها أصلاً"
    cmd_answer switched "$name" "$k"; return 0
  fi
  wifi_trial_origin "$name" "$hold"
  if ! connect_id "$id" "$TRIAL_ASSOC_WAIT"; then
    reason=$(cmd_reason "$CONNECT_WHY")
    site_log WARN "manual trial: ${name} ${CONNECT_WHY} - going back to ${ORIGIN_NAME}" \
                  "التجربة اليدوية: ${name} ${CONNECT_WHY_AR} - نرجع على ${ORIGIN_NAME}"
    wifi_trial_back || :
    cmd_answer failed "$reason"; return 1
  fi
  wifi_trial_run "$id" "$name" switched "$hold"
}

wifi_trial_origin() {  # $1 = the challenger's name, $2 = hold seconds (0 = none): where the device
  # leaves from, kept for the way back (id, name, its measurement when fresh, else one probe).
  # The opening line names the bar, and the hold when one was asked.
  ORIGIN_ID=$(current_id); ORIGIN_NAME=$(name_of_id "$ORIGIN_ID"); ORIGIN_NAME=${ORIGIN_NAME:-$IF}
  if [[ -n $ORIGIN_ID && $LAST_KBPS_ID == "$ORIGIN_ID" ]] && (( $(uptime_s) - LAST_KBPS_AT < ORIGIN_KBPS_AGE )); then
    ORIGIN_KBPS=$LAST_KBPS
  else
    ORIGIN_KBPS=$(up_kbps)
    if probe_failed; then say_probe_fail "$ORIGIN_NAME"; else note_kbps "$ORIGIN_KBPS"; fi
  fi
  TRIAL_AT=$(date +%s)
  streaming && site_log INFO "manual trial under a live stream - the viewer stutters while the network changes" \
                             "تجربة يدوية أثناء بث مباشر - المشاهد يتقطع عليه أثناء تغيير الشبكة"
  if (( ${2:-0} > 0 )); then
    site_log INFO "manual trial: $1 for ${TRIAL_WAIT} s, leaving ${ORIGIN_NAME} (${ORIGIN_KBPS} kbps) - the bar is $(( ORIGIN_KBPS * CUR_GAIN / 100 )) kbps, and it stays for $(dur_words "$2") either way while it has internet" \
                  "تجربة يدوية: $1 لمدة ${TRIAL_WAIT} ث، نترك ${ORIGIN_NAME} (${ORIGIN_KBPS} كيلوبت/ث) - الحد $(( ORIGIN_KBPS * CUR_GAIN / 100 )) كيلوبت/ث، وتبقى $(dur_words_ar "$2") على أي حال ما دام فيها إنترنت"
    return 0
  fi
  site_log INFO "manual trial: $1 for ${TRIAL_WAIT} s, leaving ${ORIGIN_NAME} (${ORIGIN_KBPS} kbps) - it stays only at $(( ORIGIN_KBPS * CUR_GAIN / 100 )) kbps or more" \
                "تجربة يدوية: $1 لمدة ${TRIAL_WAIT} ث، نترك ${ORIGIN_NAME} (${ORIGIN_KBPS} كيلوبت/ث) - تبقى فقط إذا وصلت $(( ORIGIN_KBPS * CUR_GAIN / 100 )) كيلوبت/ث أو أكثر"
}

wait_pid() {  # $1 = a background child of this shell: wait until it has really ended. A trapped
  # signal (the site's USR1 landing during a trial) makes wait return early with the trap's
  # status while the child still runs, so the wait is repeated; the flag the trap set stays
  # for the loop top, which is the one consumer of commands.
  while kill -0 "$1" 2>/dev/null; do wait "$1" 2>/dev/null || :; done
}
wait_first() {  # $1 = a background child, $2 = seconds: wait until the child has ended or the
  # seconds have passed, whichever first. A timer child marks the seconds and wait -n blocks
  # until some child ends (never a poll; a trapped USR1 returns early, so the check repeats);
  # whatever ended is reaped, and the timer is ended when the child won. The timer's pid sits
  # in TRIAL_TIMER_PID so a shutdown landing inside the wait ends it with the other children.
  sleep "$2" 9>&- & TRIAL_TIMER_PID=$!
  while kill -0 "$1" 2>/dev/null && kill -0 "$TRIAL_TIMER_PID" 2>/dev/null; do wait -n 2>/dev/null || :; done
  kill "$TRIAL_TIMER_PID" 2>/dev/null || :
  TRIAL_TIMER_PID=""
}
trial_post() {  # $1 = cell | none, then STATE [FIELD...]: a trial's mid-way answer (trying, measuring),
  # written now and carried to the site by a background child the trial does not wait for at
  # that moment (each POST is 1 to 2 s on the owner's uplink; off the window's critical path);
  # with cell the child republishes the WiFi cell after the answer. The trial waits for the
  # child before it writes the next answer, so the site reads them in order, and the verdict's
  # answer stays foreground (cmd_answer): a shutdown cannot lose it.
  local cell=$1; shift
  cmd_answer_put "$@"
  { cmd_answer_send; [[ $cell == cell ]] && report_wifi; } >/dev/null 2>&1 9>&- &
  TRIAL_POST_PID=$!
}

wifi_trial_run() {  # $1 = id (linked, internet proven), $2 = its name, $3 = the answer when it stays
  # (switched | joined), $4 = hold seconds (0 = none; a switch only). The challenger's trial: the
  # owner's TRIAL_WAIT window opens the moment
  # the link delivers. The trying answer and the cell leave from a background child; the one
  # upload probe starts when that child has left the uplink or TRIAL_POST_GAP s have passed,
  # whichever first, and runs inside the window. A child still running at the cap overlaps the
  # probe with the cell's POST, under 1 KB against the probe's 200 KB: a number the probe can
  # carry. The measuring answer follows at TRIAL_HEAD s, once the trying child has ended: the
  # site polls every 2 s, an answer replaced 92 ms later (round 1, measured) never reached it,
  # and the answers must arrive in order. The verdict comes at the later of the window and the
  # probe's end (a 200 KB probe takes 2-8 s on the owner's uplinks, so the network is held the
  # full 15 s and the probe's seconds add nothing to them); its answer is the one POST the trial
  # waits for. Then the never-break bar (CUR_GAIN of the origin) decides: stay, or return_to the
  # origin. Never the ordinary evaluation or fight(): they treat the incumbent as home, and this
  # network is a challenger. enable_all on every exit. Signal mode keeps any network that delivers.
  # With a hold the network stays under the bar as well, as long as it has internet (the probe
  # carried bytes, or the quick check passes now); without internet the way back runs as always.
  local trial_kbps="" bar hold=${4:-0} stay=0
  enable_all
  sleep "$TRIAL_WAIT" 9>&- & TRIAL_HOLD_PID=$!   # the window; 9>&- so the child never holds the lock
  sleep "$TRIAL_HEAD" 9>&- & TRIAL_HEAD_PID=$!   # the head: the measuring answer waits for it
  trial_post cell trying "$2"   # the answer, then the cell follows the network now, not at the next minute
  wait_first "$TRIAL_POST_PID" "$TRIAL_POST_GAP"   # the probe never shares the uplink with the trying POST
  rm -f "$TRIAL_PROBE" 2>/dev/null
  { up_kbps >"$TRIAL_PROBE" 2>/dev/null; } 9>&- & TRIAL_PROBE_PID=$!
  wait_pid "$TRIAL_HEAD_PID"; TRIAL_HEAD_PID=""
  wait_pid "$TRIAL_POST_PID"   # trying has left before measuring is written: the site reads them in order
  trial_post none measuring "$2"
  wait_pid "$TRIAL_PROBE_PID"; TRIAL_PROBE_PID=""
  IFS= read -r trial_kbps <"$TRIAL_PROBE" 2>/dev/null || :   # up_kbps prints no newline: read still assigns
  rm -f "$TRIAL_PROBE" 2>/dev/null
  if [[ ! $trial_kbps =~ ^[0-9]{1,9}$ ]]; then
    # No number came back. A PROBE_FAIL marker means the target refused the bytes (said below);
    # without one the result file itself failed, and the owner hears which file before 0 applies.
    probe_failed || site_log WARN "manual trial: the probe's result file ${TRIAL_PROBE} could not be read - counting $2 as 0 kbps" \
                                  "التجربة اليدوية: ملف نتيجة القياس ${TRIAL_PROBE} ما انقرأ - نحسب $2 على 0 كيلوبت/ث"
    trial_kbps=0
  fi
  note_kbps "$trial_kbps"
  probe_failed && say_probe_fail "$2"
  wait_pid "$TRIAL_HOLD_PID"; TRIAL_HOLD_PID=""   # the network is held for the owner's full window whatever the probe took
  wait_pid "$TRIAL_POST_PID"; TRIAL_POST_PID=""   # measuring has left before the verdict's answer is written
  bar=$(( ORIGIN_KBPS * CUR_GAIN / 100 ))
  if ! probe_on || [[ -z $ORIGIN_ID ]] || (( trial_kbps > 0 && trial_kbps >= bar )); then
    stay=1
    site_log OK "manual trial: $2 $(up_words "$trial_kbps"), the ${bar} kbps bar met - staying on it" \
                "التجربة اليدوية: $2 $(up_words_ar "$trial_kbps")، تجاوزت الحد ${bar} كيلوبت/ث - باقون عليها"
  elif (( hold > 0 )) && { (( trial_kbps > 0 )) || have_net; }; then
    stay=1
    site_log INFO "manual trial: $2 uploads at ${trial_kbps} kbps, under the ${bar} kbps bar (${ORIGIN_NAME} ${ORIGIN_KBPS} kbps at ${CUR_GAIN}%) - staying anyway, held from the menu" \
                  "التجربة اليدوية: $2 ترفع ${trial_kbps} كيلوبت/ث، تحت الحد ${bar} كيلوبت/ث (${ORIGIN_NAME} ${ORIGIN_KBPS} كيلوبت/ث عند ${CUR_GAIN}%) - باقون عليها على أي حال، تثبيت من القائمة"
  elif (( hold > 0 )); then
    site_log INFO "manual trial: $2 measured 0 kbps and fails the internet check - the hold is not taken, going back to ${ORIGIN_NAME}" \
                  "التجربة اليدوية: $2 قاست 0 كيلوبت/ث وما نجحت في فحص الإنترنت - ما نثبّت عليها، نرجع على ${ORIGIN_NAME}"
  fi
  if (( stay )); then
    if (( hold > 0 )); then
      hold_start "$2" "$hold"
      cmd_answer "$3" "$2" "$trial_kbps" "hold=${hold}"   # foreground: the verdict is the one answer a shutdown must not lose
    else
      cmd_answer "$3" "$2" "$trial_kbps"
    fi
    report_wifi
    return 0
  fi
  (( hold > 0 )) || site_log INFO "manual trial: $2 uploads at ${trial_kbps} kbps, under the ${bar} kbps bar (${ORIGIN_NAME} ${ORIGIN_KBPS} kbps at ${CUR_GAIN}%) - going back" \
                "التجربة اليدوية: $2 ترفع ${trial_kbps} كيلوبت/ث، تحت الحد ${bar} كيلوبت/ث (${ORIGIN_NAME} ${ORIGIN_KBPS} كيلوبت/ث عند ${CUR_GAIN}%) - نرجع"
  if wifi_trial_back; then
    cmd_answer returned "$ORIGIN_NAME" "$ORIGIN_KBPS" "$2" "$trial_kbps"
  else
    cmd_answer failed return_failed
  fi
  report_wifi
  return 1
}

wifi_trial_back() {  # the way back to the origin after a trial, said either way. A link that forms
  # without internet is the upstream outage (return_to said it, the device is back); a link that
  # never forms is a failure the next check and the fight take over.
  local now_ssid
  [[ -n $ORIGIN_ID ]] || { enable_all; return 1; }   # no stored origin: the supplicant's own choice
  if return_to "$ORIGIN_ID" "$ORIGIN_NAME"; then
    enable_all
    site_log OK "back on ${ORIGIN_NAME}" "رجعنا على ${ORIGIN_NAME}"
    return 0
  fi
  enable_all
  [[ $CONNECT_WHY == "linked but no internet" ]] && return 0
  now_ssid=$(dssid)
  site_log WARN "the way back to ${ORIGIN_NAME} failed - on ${now_ssid:-no network} now, the next check decides and recovery follows if the internet is gone" \
                "الرجوع على ${ORIGIN_NAME} فشل - الآن على ${now_ssid:-لا شبكة}، الفحص التالي يقرر والإنعاش يبدأ إن غاب الإنترنت"
  return 1
}

wifi_cmd_join() {  # $1 = SSID hex, $2 = the blob: MAC check, decrypt, the network added at runtime
  # only (wpa: add_network, never save_config; nm: a trial keyfile in /run), then the trial. A
  # password that delivers internet is kept in NETS_FILE before anything else; one that fails is
  # removed with its entry. The password lives in this shell and the supplicant; nothing prints it.
  local key=$1 name psk id new hexpsk=0 reason
  (( net_up )) || {
    site_log INFO "join asked from the site while offline - recovery decides the network until the internet is back" \
                  "طُلب انضمام من الموقع والإنترنت مقطوع - الإنعاش يقرر الشبكة حتى يرجع الإنترنت"
    cmd_answer failed offline; return 0; }
  name=$(hex_disp "$key")
  psk=$(wifi_decrypt "$2") || {
    site_log WARN "join asked from the site for ${name} - the password could not be opened with this device's key; the site holds another key? open admin/wifi.php?reset_key=1 once and try again" \
                  "طُلب انضمام من الموقع إلى ${name} - ما قدرنا نفتح كلمة السر بمفتاح هذا الجهاز؛ الموقع عنده مفتاح آخر؟ افتح admin/wifi.php?reset_key=1 مرة وحاول من جديد"
    wifi_key_register   # the site may hold an older key: this one is offered again (taken only with proof)
    cmd_answer failed key_changed; return 0; }
  if [[ $psk =~ ^[0-9a-fA-F]{64}$ ]]; then hexpsk=1
  elif (( ${#psk} < 8 || ${#psk} > 63 )) || [[ $psk == *[$'\t\n\r']* ]]; then
    site_log WARN "join asked from the site for ${name} - the password must be 8 to 63 characters or 64 hex digits" \
                  "طُلب انضمام من الموقع إلى ${name} - كلمة السر لازم تكون 8 إلى 63 حرفاً أو 64 خانة ست عشرية"
    cmd_answer failed wrong_password; return 0
  fi
  site_log INFO "join asked from the site: ${name} - adding it at runtime and trying it for ${TRIAL_WAIT} s" \
                "طُلب انضمام من الموقع: ${name} - نضيفها مؤقتاً ونجربها ${TRIAL_WAIT} ث"
  if [[ $BACKEND != wpa ]]; then
    { id=$(nm_write_profile "$key" "$psk" no "awacs-join-$(date +%s)-$$" false) && [[ -n $id ]]; } || {
      site_log WARN "join: could not create the trial entry for ${name} in NetworkManager" \
                    "الانضمام: ما قدرنا ننشئ الإدخال المؤقت لـ ${name} في مدير الشبكة"
      cmd_answer failed out_of_reach; return 0; }
    join_mark "$id" "$key"
  else
    if (( ! hexpsk )) && [[ $psk == *'"'* || $psk == *"\\"* ]]; then
      site_log WARN "join: the supplicant cannot take a quote or backslash in a password - ${name} not added" \
                    "الانضمام: المشغّل ما يقبل علامة تنصيص أو شرطة مائلة في كلمة السر - ${name} ما أُضيفت"
      cmd_answer failed wrong_password; return 0
    fi
    { id=$(wpa add_network) && [[ $id =~ ^[0-9]+$ ]]; } || {
      site_log WARN "join: could not create the entry for ${name} in the supplicant" \
                    "الانضمام: ما قدرنا ننشئ الإدخال لـ ${name} في المشغّل"
      cmd_answer failed out_of_reach; return 0; }
    join_mark "$id" "$key"
    if ! wpa_join_set "$id" "$key" "$psk"; then
      wpa remove_network "$id" >/dev/null || :; rm -f "$JOIN_ID_FILE" 2>/dev/null || :
      site_log WARN "join: the supplicant refused the entry for ${name} - removed" \
                    "الانضمام: المشغّل رفض الإدخال لـ ${name} - أُزيل"
      cmd_answer failed out_of_reach; return 0
    fi
  fi
  wifi_trial_origin "$name"
  if ! connect_id "$id" "$TRIAL_ASSOC_WAIT"; then
    reason=$(cmd_reason "$CONNECT_WHY")
    site_log WARN "join: ${name} ${CONNECT_WHY} - removing it, going back to ${ORIGIN_NAME}" \
                  "الانضمام: ${name} ${CONNECT_WHY_AR} - نزيلها ونرجع على ${ORIGIN_NAME}"
    del_own "$id" || :
    rm -f "$JOIN_ID_FILE" 2>/dev/null || :
    psk=""
    wifi_trial_back || :
    cmd_answer failed "$reason"; return 1
  fi
  # Internet proven: the password is right. The file first, then the marker (a crash between
  # them re-adds, never loses); on nm the persistent class replaces the trial entry.
  if nets_put "$key" "$psk"; then
    rm -f "$JOIN_ID_FILE" 2>/dev/null || :
    site_log OK "joined ${name} - password kept in ${NETS_FILE}, re-added at every start" \
                "انضممنا إلى ${name} - كلمة السر محفوظة في ${NETS_FILE} وتُضاف عند كل تشغيل"
  else
    site_log WARN "joined ${name} but ${NETS_FILE} could not be written - the network lasts until the next start" \
                  "انضممنا إلى ${name} بس ما قدرنا نكتب ${NETS_FILE} - الشبكة تبقى حتى التشغيل القادم"
  fi
  if [[ $BACKEND != wpa ]]; then
    if { new=$(nm_add_joined "$key" "$psk") && [[ -n $new ]]; } && connect_id "$new"; then
      nm_del_own "$id" || :; id=$new
    else
      site_log WARN "join: the stored entry for ${name} could not take over - riding the trial entry until the next start" \
                    "الانضمام: الإدخال الدائم لـ ${name} ما قدر يتولى - نبقى على الإدخال المؤقت حتى التشغيل القادم"
      connect_id "$id" >/dev/null 2>&1 || :
    fi
  fi
  psk=""
  SCAN_LIST_AT=0; SCAN_LIST_SCAN=""; report_scan now   # the row turns known at once
  wifi_trial_run "$id" "$name" joined
}

join_mark() {  # $1 = id, $2 = SSID hex: the crash marker a respawn reads (reap_join), never OPEN_ID_FILE
  printf '%s\t%s\n' "$1" "$2" >"$JOIN_ID_FILE" 2>/dev/null || :
}
reap_join() {  # startup: a join the previous run did not finish is removed with its own line. On wpa
  # the id is per supplicant run, so the entry goes only while it still carries the joined SSID.
  local id hex name ssid
  [[ -s $JOIN_ID_FILE ]] || return 0
  IFS=$'\t' read -r id hex <"$JOIN_ID_FILE" || id=""
  rm -f "$JOIN_ID_FILE" 2>/dev/null || :
  [[ -n $id ]] || return 0
  if [[ $BACKEND == wpa ]]; then
    ssid=$(wpa_known_ids | awk -F'\t' -v id="$id" '$1 == id { print $2; exit }')
    [[ -n $ssid && $(iw2hex "$ssid") == "$hex" ]] || return 0
  fi
  name=$(name_of_id "$id")
  site_log INFO "removed an unfinished join of ${name} left by the previous run" \
                "أزلنا انضماماً غير مكتمل إلى ${name} تركه التشغيل السابق"
  del_own "$id" || :
}

wpa_join_set() {  # $1 = id, $2 = SSID hex, $3 = psk: the ssid as hex bytes (any name survives), the
  # psk over stdin as try_safety does (never argv: /proc/PID/cmdline is world-readable), a 64-hex
  # psk unquoted, scan_ssid armed, the entry enabled. Nothing here prints the password.
  wpa set_network "$1" ssid "$2" | grep -q OK || return 1
  if [[ $3 =~ ^[0-9a-fA-F]{64}$ ]]; then
    printf 'set_network %s psk %s\n' "$1" "$3" | wpa_cli -i "$IF" 2>/dev/null | grep -q OK || return 1
  else
    printf 'set_network %s psk "%s"\n' "$1" "$3" | wpa_cli -i "$IF" 2>/dev/null | grep -q OK || return 1
  fi
  wpa set_network "$1" scan_ssid 1 >/dev/null || :
  wpa enable_network "$1" | grep -q OK
}
nm_add_joined() {  # $1 = SSID hex, $2 = psk -> UUID: the persistent class, autoconnect on, in /run
  nm_write_profile "$1" "$2" no "awacs-joined-$1" true
}

nets_put() {  # $1 = SSID hex, $2 = psk: one line per network in NETS_FILE (root 600); the newest
  # password for a name replaces its older line. Written whole, then renamed.
  { if [[ -s $NETS_FILE ]]; then K="$1" awk -F'\t' '$1 != ENVIRON["K"]' "$NETS_FILE" 2>/dev/null; fi
    printf '%s\t%s\n' "$1" "$2"; } >"${NETS_FILE}.t" 2>/dev/null || { rm -f "${NETS_FILE}.t" 2>/dev/null; return 1; }
  chmod 600 "${NETS_FILE}.t" 2>/dev/null || :
  mv -f "${NETS_FILE}.t" "$NETS_FILE" 2>/dev/null
}

load_joined() {  # NETS_FILE -> the live supplicant / NetworkManager, both arms: every network joined
  # from the site, skipped when a profile with that SSID already exists. Runtime only on wpa
  # (never save_config); on nm the persistent class in /run. Called at start and after the rungs
  # that lose runtime entries (wpa L2/L3 restart the supplicant, nm L3 restarts NetworkManager).
  local hex psk id kid kssid have=$'\n' n=0 names="" name
  [[ -s $NETS_FILE ]] || return 0
  while IFS=$'\t' read -r kid kssid; do
    [[ -n $kid ]] || continue
    if [[ $BACKEND != wpa ]]; then have+="${kssid}"$'\n'; else have+="$(iw2hex "$kssid")"$'\n'; fi
  done < <(known_ids)
  while IFS=$'\t' read -r hex psk; do
    [[ $hex =~ ^([0-9a-f]{2}){1,32}$ && -n $psk ]] || continue
    [[ $have == *$'\n'"${hex}"$'\n'* ]] && continue
    name=$(hex_disp "$hex")
    if [[ $BACKEND != wpa ]]; then
      { id=$(nm_add_joined "$hex" "$psk") && [[ -n $id ]]; } || {
        site_log WARN "joined network ${name} could not be re-added to NetworkManager" \
                      "الشبكة المنضمة ${name} ما قدرنا نعيد إضافتها إلى مدير الشبكة"; continue; }
    else
      { id=$(wpa add_network) && [[ $id =~ ^[0-9]+$ ]]; } || {
        site_log WARN "joined network ${name} could not be re-added to the supplicant" \
                      "الشبكة المنضمة ${name} ما قدرنا نعيد إضافتها إلى المشغّل"; continue; }
      wpa_join_set "$id" "$hex" "$psk" || {
        wpa remove_network "$id" >/dev/null || :
        site_log WARN "joined network ${name} refused by the supplicant - not re-added" \
                      "الشبكة المنضمة ${name} رفضها المشغّل - ما أُعيدت إضافتها"; continue; }
    fi
    (( ++n )); names+="${names:+, }${name}"
  done <"$NETS_FILE"
  psk=""
  (( n )) && site_log INFO "re-added ${n} networks joined from the site: ${names}" \
                           "أعدنا إضافة ${n} شبكة منضمة من الموقع: ${names}"
  return 0
}

wifi_key_ensure() {  # KEY_FILE: 64 hex, root 600, made once with openssl rand; never printed or logged
  local k=""
  read -r k 2>/dev/null <"$KEY_FILE" || k=""
  if [[ $k =~ ^[0-9a-f]{64}$ ]]; then chmod 600 "$KEY_FILE" 2>/dev/null || :; return 0; fi
  command -v openssl >/dev/null 2>&1 || {
    site_log WARN "openssl is missing - a password typed on the site cannot be opened here, join from the menu is off" \
                  "openssl غير موجود - كلمة سر تُكتب على الموقع ما تنفتح هنا، الانضمام من القائمة معطّل"; return 1; }
  k=$(openssl rand -hex 32 2>/dev/null) || k=""
  [[ $k =~ ^[0-9a-f]{64}$ ]] || {
    site_log WARN "could not make the device key (openssl rand failed) - join from the menu is off" \
                  "ما قدرنا ننشئ مفتاح الجهاز (openssl rand فشل) - الانضمام من القائمة معطّل"; return 1; }
  if printf '%s\n' "$k" >"${KEY_FILE}.t" 2>/dev/null && chmod 600 "${KEY_FILE}.t" 2>/dev/null \
     && mv -f "${KEY_FILE}.t" "$KEY_FILE" 2>/dev/null; then
    site_log INFO "device key made for passwords typed on the site (${KEY_FILE})" \
                  "أنشأنا مفتاح الجهاز لكلمات السر التي تُكتب على الموقع (${KEY_FILE})"
    return 0
  fi
  rm -f "${KEY_FILE}.t" 2>/dev/null || :
  site_log WARN "could not write ${KEY_FILE} - join from the menu is off" \
                "ما قدرنا نكتب ${KEY_FILE} - الانضمام من القائمة معطّل"
  return 1
}
wifi_key_register() {  # the key -> the site as file=wifi_key, with proof=HMAC-SHA256(old, new) when
  # KEY_FILE.prev holds the key the site knew; said once, never its value. A 403 means the site
  # holds another key (a reflash): the owner re-pairs once from admin/wifi.php?reset_key=1.
  local k old="" proof="" code
  local -a extra=()
  (( KEY_SENT )) && return 0
  [[ -n $SITE_URL ]] || return 0
  read -r k 2>/dev/null <"$KEY_FILE" || return 0
  [[ $k =~ ^[0-9a-f]{64}$ ]] || return 0
  read -r old 2>/dev/null <"${KEY_FILE}.prev" || old=""
  if [[ $old =~ ^[0-9a-f]{64}$ && $old != "$k" ]]; then
    proof=$(printf '%s' "$k" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:${old}" 2>/dev/null) || proof=""
    proof=${proof##* }
    [[ $proof =~ ^[0-9a-f]{64}$ ]] && extra=(--data-urlencode "proof=${proof}")
  fi
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 --data-urlencode "file=wifi_key" \
    --data-urlencode "data=${k}" "${extra[@]}" "$(api_url)" 2>/dev/null) || code=000
  if [[ $code =~ ^2[0-9][0-9]$ ]]; then
    KEY_SENT=1; rm -f "${KEY_FILE}.prev" 2>/dev/null || :
    site_log INFO "device key registered with the site - a password typed there can be opened here" \
                  "سُجّل مفتاح الجهاز في الموقع - كلمة سر تُكتب هناك تنفتح هنا"
  elif [[ $code == 403 ]]; then
    (( KEY_REFUSED_SAID )) && return 0
    KEY_REFUSED_SAID=1
    site_log WARN "the site holds another key for this camera (a reflash?) - open admin/wifi.php?reset_key=1 once from your phone, then join from the menu works again" \
                  "الموقع عنده مفتاح آخر لهذه الكاميرا (إعادة تثبيت؟) - افتح admin/wifi.php?reset_key=1 مرة من جوالك، وبعدها الانضمام من القائمة يشتغل"
  fi
  return 0   # any other reply: retried at the first proven-healthy tick or the next start
}
wifi_decrypt() {  # $1 = blob "<iv_hex>.<ct_base64>.<mac_hex>" -> the password on stdout; 1 on any fault.
  # Kenc = HMAC-SHA256(K, "enc"), Kmac = HMAC-SHA256(K, "mac"); the MAC over the ASCII text
  # "<iv_hex>.<ct_base64>" is checked before anything is decrypted (AES-256-CBC, PKCS7). The
  # keys ride openssl's argv for the call's duration on this single-user root box: accepted.
  local blob=$1 iv ct mac k kenc kmac calc
  [[ $blob =~ ^([0-9a-f]{32})\.([A-Za-z0-9+/=]+)\.([0-9a-f]{64})$ ]] || return 1
  iv=${BASH_REMATCH[1]}; ct=${BASH_REMATCH[2]}; mac=${BASH_REMATCH[3]}
  read -r k 2>/dev/null <"$KEY_FILE" || return 1
  [[ $k =~ ^[0-9a-f]{64}$ ]] || return 1
  kenc=$(printf '%s' enc | openssl dgst -sha256 -mac HMAC -macopt "hexkey:${k}" 2>/dev/null) || return 1
  kmac=$(printf '%s' mac | openssl dgst -sha256 -mac HMAC -macopt "hexkey:${k}" 2>/dev/null) || return 1
  kenc=${kenc##* }; kmac=${kmac##* }
  [[ $kenc =~ ^[0-9a-f]{64}$ && $kmac =~ ^[0-9a-f]{64}$ ]] || return 1
  calc=$(printf '%s' "${iv}.${ct}" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:${kmac}" 2>/dev/null) || return 1
  calc=${calc##* }
  [[ $calc == "$mac" ]] || return 1
  printf '%s' "$ct" | openssl enc -d -aes-256-cbc -a -A -K "$kenc" -iv "$iv" 2>/dev/null
}

# ------------------------------- daemon ----------------------------------------
main() {
  reboot_memory_restore   # a saved outage story goes in front of everything this start says
  # boot_mode: "start" when nothing was held before this start, empty when a story was (a saved
  # outage story, a predecessor's spool or its orphaned snapshot). The start's own lines spool
  # too, because net_up is unknown yet; the boot flush says "delivered N held lines" only when it
  # carried a story.
  local boot_mode=start
  [[ -s $SPOOL || -s ${SPOOL}.sending ]] && boot_mode=""
  say_start
  say_after_reboot
  log INFO "reporting: ${LOG_TARGET}${SITE_URL:+ -> ${SITE_URL}} | probe: $(probe_on && probe_url || echo 'none - signal mode') | wifi cell: ${REPORT_WIFI} | lang: local ${LOG_LANG}, site ${SITE_LANG}"
  (( LT_DOWNGRADED )) && log WARN "LOG_TARGET asked for the site but SITE_URL is empty - running local-only"
  say_settings
  # detect_if's wlan0 fallback can name an interface that does not exist (dead radio,
  # unplugged USB dongle) — say so ONCE in the log instead of fighting a ghost silently.
  # IF_SEEN: if_check reports a vanished interface only when it was seen alive, so the start
  # check seeds it; without that, an interface present at boot that vanished before the first
  # outage was never reported.
  if iw dev "$IF" info >/dev/null 2>&1; then IF_SEEN=1
  else
    site_log ERROR "interface ${IF} not present - is the WiFi hardware alive?" \
                   "واجهة الواي فاي ${IF} غير موجودة - العتاد سليم؟"
  fi
  check_tools

  # Backend verdicts (detect_backend ran at dispatch): wpa = legacy pillar, untouched;
  # nm = full capability as NM's SUPERVISOR; nm_lame = the only monitor-only mode left.
  if [[ $BACKEND == nm_lame ]]; then
    # The verdict names its reason and the cure: the two differ (wait for the auto-install
    # and the restart, or fix NetworkManager.conf), and only the nmcli case leaves the park
    # by itself, and only under the respawn lane.
    if [[ ${NM_LAME_REASON:-} == nocli ]]; then
      if [[ -n ${AWACS_DAEMONIZED:-} ]]; then
        site_log ERROR "NetworkManager image but AWACS cannot drive it: nmcli is missing - will install it once online, then restart AWACS by hand (started with -d) - monitoring only" \
                       "النظام على NetworkManager بس أواكس ما يقدر يتحكم فيه: nmcli ناقص - ننزّله أول ما يتوفر النت، ثم أعد تشغيل أواكس بنفسك (شُغّل بـ -d) - نراقب بس"
      else
        site_log ERROR "NetworkManager image but AWACS cannot drive it: nmcli is missing - will install it once online and restart - monitoring only" \
                       "النظام على NetworkManager بس أواكس ما يقدر يتحكم فيه: nmcli ناقص - ننزّله أول ما يتوفر النت ونعيد التشغيل - نراقب بس"
      fi
    else
      site_log ERROR "NetworkManager image but AWACS cannot drive it: ${IF} is unmanaged by NetworkManager - fix unmanaged-devices in NetworkManager.conf and restart AWACS - monitoring only" \
                     "النظام على NetworkManager بس أواكس ما يقدر يتحكم فيه: ${IF} خارج إدارة NetworkManager - عدّل unmanaged-devices في NetworkManager.conf وأعد تشغيل أواكس - نراقب بس"
    fi
    # Parked, not dead: the boot story must still reach the dashboard (it spooled —
    # nothing had flushed it), and the ONE tool whose absence caused this (nmcli)
    # still gets its single install attempt. Same 300s cadence, no new loop.
    # A loss and its return are still said, once each, on the change of verdict.
    local park_up=1 back_on
    while :; do
      if have_net; then
        net_up=1
        flush_spool "$boot_mode"; boot_mode=""   # the spooled loss line first, so the site reads the pair in order
        log_down_check
        if (( ! park_up )); then
          park_up=1; back_on=$(dssid)
          site_log OK "internet back on ${back_on:-$IF} - monitoring only" \
                      "رجع الانترنت على ${back_on:-$IF} - نراقب بس"
        fi
        install_tools
      else
        net_up=0
        if (( park_up )); then
          park_up=0; lost_on=$(dssid); lost_on=${lost_on:-$IF}
          site_log WARN "internet lost on ${lost_on} - monitoring only, AWACS cannot recover here" \
                        "انقطع الانترنت عن ${lost_on} - نراقب بس، أواكس ما يقدر ينعش هنا"
          boot_mode=""   # a loss is a story: its delivery is said
        fi
      fi
      # Lame ONLY because nmcli was missing and the install just landed it? Exit —
      # the rc.local respawn re-detects and comes back as a full nm supervisor.
      # (Never for the unmanaged verdict: nmcli exists there, exiting would cycle.)
      # (only under the rc.local respawn lane: the -d compat lane has no respawner,
      # so exiting there would end the daemon for good)
      if [[ ${NM_LAME_REASON:-} == nocli && -z ${AWACS_DAEMONIZED:-} ]] && command -v nmcli >/dev/null 2>&1; then
        site_log OK "nmcli is now installed - restarting as a full NetworkManager supervisor" \
                    "تم تنزيل nmcli - يعاد التشغيل بكامل القدرات"
        DELIBERATE_EXIT=1; sleep 5; exit 0
      fi
      sleep 300
    done
  fi
  [[ $BACKEND == nm ]] && site_log INFO "NetworkManager backend - AWACS supervises it (full capability)" \
                                        "النظام يستخدم NetworkManager - أواكس يشتغل معه بكامل قدراته"

  say_rfkill   # unblock a soft-blocked radio and say it; a hard block is named too
  iw dev "$IF" set power_save off 2>/dev/null || :  # carried over from aasw: shaves 100-300ms off latency
  enable_stealth
  pgrep -f /usr/local/bin/aasw >/dev/null 2>&1 \
    && site_log WARN "aasw.sh is still running - two WiFi authorities will fight; remove its rc.local line" \
                     "aasw القديم لا يزال يعمل - سلطتان تتصارعان؛ احذف سطره من rc.local"
  # Reap a dead predecessor's crutch: the marker survives the crash (crash-proof
  # lifecycle); the nm arm adds the name-prefix sweep + /run glob belt.
  reap_crutches
  enable_all
  arm_hidden   # hidden networks are common — without directed probes they never appear
  load_joined  # networks joined from the site, re-added at every start (runtime only)
  wifi_key_ensure && wifi_key_register   # the site's key for typed passwords; said once, never its value

  local fails=0 strikes=0 flow here last_dance=0 last_pref=0 pref_hits=0 runs=0 \
        cur_id cand_id cur_name cand_name ok_ticks=0 engaged=0 online=0 online_on \
        cd_said=0 left tnow now_ssid why why_ar bench_min old_name seen_en seen_ar \
        last_cand="" pref_flickers=0 flicker_said=0 pref_stay=""
  # cd_said: the dance whose cooldown was already reported (keyed on last_dance, one line per
  # window). pref_*: the flicker memory of the current stay - a higher-priority network seen
  # at one check and gone at the next is said once per stay and counted after that.
  # Boot aggression (aasw parity): no internet on arrival = fight NOW, not after the
  # NET_FAIL_TICKS grace. fight() opens GENTLY (reassociate + wait_ip, skipped while the
  # link is alive) so a supplicant mid-association is waited for, not torn down.
  # A predecessor killed MID-FLUSH left its snapshot orphaned — rescue it in front
  # of any fresh lines (a few re-sent lines beat a silently amputated story).
  if [[ -s ${SPOOL}.sending ]]; then
    cat "${SPOOL}.sending" "$SPOOL" 2>/dev/null >"${SPOOL}.t" || :
    mv -f "${SPOOL}.t" "$SPOOL" 2>/dev/null || :
    rm -f "${SPOOL}.sending"
  fi
  if have_net; then
    net_up=1; flush_spool "$boot_mode"   # a respawn delivers its predecessor's story first, in order
    online_on=$(dssid)
    site_log OK "online at start via ${online_on:-$IF}" "متصل عند البدء عبر ${online_on:-$IF}"
  else
    # The boot fight gets its own opening (the loop's loss line lives on the tick path) with
    # the router's state. engaged=1 BEFORE the fight: a win is then said by the loop's
    # "internet restored" line on the first healthy tick; a loss leaves fails ripe, so the
    # loop never announces this same loss a second time.
    lost_on=$(dssid); lost_on=${lost_on:-$IF}
    router_tell; LOST_AT=$(uptime_s)
    site_log WARN "no internet at start on ${lost_on} - router ${ROUTER_EN}, engaging" \
                  "لا إنترنت عند البدء على ${lost_on} - الراوتر ${ROUTER_AR}، بدأ القتال للرجوع"
    FIGHT_STREAK=1; engaged=1
    fight || fails=$NET_FAIL_TICKS
  fi
  # capture.sh signals only while this exists (the trap is armed and the one consumer runs): armed
  # here, past the nm_lame park above, so a tap under "monitoring only" is answered by the relay
  # (awacs_old) instead of vanishing.
  # A held verdict that never reached the site before a stop is re-sent by the healthy tick,
  # but the hold itself died with the stop: the spooled line loses its hold field so the site
  # never reads "kept" for a hold that no longer stands.
  if [[ -s $CMD_ANSWER ]]; then
    local _sp="" _tab=$'\t'
    IFS= read -r _sp <"$CMD_ANSWER" || _sp=""
    if [[ $_sp == *"${_tab}switched${_tab}"* && $_sp =~ ${_tab}hold=[0-9]+$ ]]; then
      printf '%s\n' "${_sp%"${_tab}"hold=*}" >"$CMD_ANSWER" 2>/dev/null || :
      llog INFO "a held verdict from before the stop is re-sent without its hold - the hold ended with the stop" \
                "حكم مثبَّت من قبل التوقف يُعاد إرساله بلا تثبيت - التثبيت انتهى مع التوقف"
    fi
  fi
  : >"$CMD_READY" 2>/dev/null || :
  while :; do
    clock_step_check
    wifi_cmd_check "$engaged"   # the one consumer of a site command: never inside a fight
    (( TRIAL_AT > last_dance )) && last_dance=$TRIAL_AT   # a manual trial is a dance for the cooldown
    hold_check   # a hold from the menu whose time has passed ends here, said once
    (( RB_SAME )) && reboot_failed_check
    apply_profile
    # THE VERDICT. The quick ladder (one ping on a healthy tick, as always); a failure
    # while the device itself kept sending earns one patient look (net_verdict). On the
    # engagement tick - while the LINK is alive (gateway reachable) and no patient look has
    # already failed in this streak - one more patient look before any teardown: a short
    # upstream blip that just ended must not start a recovery. A dead link (no gateway), and
    # a link that already failed a patient look, engage on the third failed check as before.
    online=0; LATE_TICK=0
    if net_verdict; then online=1
    elif (( fails + 1 == NET_FAIL_TICKS && ! PATIENT_FAILED )) && link_alive && net_patient; then
      online=1; late_note
      llog INFO "internet answers late, not never - slow link, no recovery (${NET_FAIL_TICKS} quick checks timed out)" \
                "الإنترنت يجيب متأخراً لا معدوماً - الوصلة بطيئة، لا حاجة للإنعاش (${NET_FAIL_TICKS} فحوصات سريعة انتهت مهلتها)"
    fi
    if (( online )); then
      runs=$FIGHT_STREAK   # the restored line counts the runs before the streak dies below
      net_up=1; fails=0; ME_SINCE=0; FIGHT_STREAK=0; PATIENT_FAILED=0
      NM_L3_SPENT=0; NM_RC8=0; NM_SETTLED_SEEN=0; NM_SAW_BUSY=0   # healthy tick = the streak
                                                                  # and ALL its NM evidence die
      late_tick
      # A short outage can heal BETWEEN fights — the recovery must still be told
      # (proven silent path: fight fails, next tick finds the net back, nobody speaks).
      if (( engaged )); then
        engaged=0; strikes=0   # same hysteresis reset as the fight-success join
        say_restored "$runs"
      fi
      once_report   # the repeats of the outage that just ended, one counted line each
      reboot_memory_clear   # a healthy tick ends the fault a self-reboot was counting
      log_down_check        # the local file's state, on the change only
      cmd_answer_send       # a site answer the site has not taken yet
      # Drain the spool after ~30s of PROVEN health — a just-healed link should carry
      # frames before it carries history — then retry every ~5min while lines remain
      # (a site-down-while-internet-up phase must not park the spool forever).
      (( ++ok_ticks == 3 || (ok_ticks > 3 && ok_ticks % 30 == 0) )) && flush_spool
      (( ok_ticks == 3 )) && install_tools   # first PROVEN-healthy moment, once per boot
      # The key too: the start often had no internet, and after that once a healthy minute until
      # the site takes it (a site that was down, or the owner's reset after a reflash).
      (( ok_ticks == 3 || (ok_ticks > 3 && ok_ticks % 6 == 1) )) && wifi_key_register
      # WiFi cell heartbeat every ~60s (battery cadence) — backgrounded, lock-free.
      # The scan list rides the same minute: report_scan decides in this shell (a new scan, the
      # rate) and backgrounds only its POST.
      if (( ok_ticks % 6 == 1 )); then devid_change_check; report_scan; { report_wifi; } 9>&- & fi
      # Back on a real network? The crutch (open or emergency) has served — retire it.
      # cur_id must be NON-EMPTY: a momentarily mute wpa_cli returns "", and "" != id
      # would tear the crutch down while we still ride it (proven false-retire class).
      if [[ -n $OPEN_ID ]]; then
        cur_id=$(current_id)
        [[ -n $cur_id && $cur_id != "$OPEN_ID" ]] && drop_open home
      fi
      # Passive upload QA — three gates keep it honest: kernel counters only; NEVER
      # while a live viewer runs (its own rate sits in the band and a probe/dance
      # would stutter it — the stream IS the meter); and a dance cooldown, because
      # every dance disrupts real traffic to measure it. Deliberate reduction vs
      # aasw: no upgrade-hunting while the link is ADEQUATE (aasw jumped to any
      # >1.5x-faster network) — the never-break-a-working-link law forbids that
      # greed; we look around only when provably suffering.
      if streaming; then
        # OPPORTUNISTIC METER (doctrine: "the live stream IS a free upload
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
          tnow=$(date +%s)
          if (( ++strikes >= UP_STRIKES && tnow - last_dance >= CUR_COOLDOWN )); then
            strikes=0
            # A hold from the menu vetoes the evaluation (said once per hold); the strikes count
            # again, so the first evaluation after the hold comes as soon as they ripen.
            if ! hold_eval_veto "$flow" "$STREAM_MIN_KBPS"; then
              last_dance=$tnow
              site_log WARN "live stream starving on $(dssid) (${flow} kbps for ${UP_STRIKES} samples, floor ${STREAM_MIN_KBPS}) - evaluating known networks" \
                            "البث يعاني على $(dssid) (${flow} كيلوبت/ث في ${UP_STRIKES} عينات، الحد ${STREAM_MIN_KBPS}) - جاري تقييم الشبكات"
              evaluate_here
            fi
          elif (( strikes >= UP_STRIKES && cd_said != last_dance )); then
            # The cooldown vetoed a ripe evaluation: said once per window (keyed on the dance
            # that opened it), never per strike - a flow around the floor re-ripens every minute.
            cd_said=$last_dance; left=$(( (CUR_COOLDOWN - (tnow - last_dance) + 59) / 60 ))
            site_log INFO "live stream still starving on $(dssid) (${flow} kbps, floor ${STREAM_MIN_KBPS}) - evaluation on cooldown, next look in ${left} min" \
                          "البث ما زال يعاني على $(dssid) (${flow} كيلوبت/ث، الحد ${STREAM_MIN_KBPS}) - التقييم في فترة تهدئة، النظرة التالية بعد ${left} دقيقة"
          fi
        else
          strikes=0
        fi
      else
        flow=$(tx_kbps)
        dbg "QA: flow=${flow} kbps, strikes=${strikes}, profile=${PROFILE:-day}"
        if probe_on && (( flow >= 20 && flow < CUR_MIN_UP )); then   # signal mode: no QA
          tnow=$(date +%s)
          if (( ++strikes >= UP_STRIKES && tnow - last_dance >= CUR_COOLDOWN )); then
            strikes=0
            # A committed dance CAN outlast the site's 55s online window — the
            # dashboard may show a brief offline blink. Accepted: the dance only
            # ever runs when uploads are ALREADY suffering, never under a viewer.
            # A hold from the menu vetoes it (said once per hold); the strikes count again.
            if ! hold_eval_veto "$flow" "$CUR_MIN_UP"; then
              last_dance=$tnow
              site_log WARN "sustained slow upload on $(dssid) (${flow} kbps for ${UP_STRIKES} samples, floor ${CUR_MIN_UP}) - evaluating known networks" \
                            "رفع بطيء مستمر على $(dssid) (${flow} كيلوبت/ث في ${UP_STRIKES} عينات، الحد ${CUR_MIN_UP}) - جاري تقييم الشبكات"
              evaluate_here
            fi
          elif (( strikes >= UP_STRIKES && cd_said != last_dance )); then
            cd_said=$last_dance; left=$(( (CUR_COOLDOWN - (tnow - last_dance) + 59) / 60 ))
            site_log INFO "upload still slow on $(dssid) (${flow} kbps, floor ${CUR_MIN_UP}) - evaluation on cooldown, next look in ${left} min" \
                          "الرفع ما زال بطيئاً على $(dssid) (${flow} كيلوبت/ث، الحد ${CUR_MIN_UP}) - التقييم في فترة تهدئة، النظرة التالية بعد ${left} دقيقة"
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
      # A hold from the menu skips the look (it exists to leave the network); last_pref stays,
      # so the first look after the hold comes at the next tick.
      if ! streaming && ! hold_on && (( $(date +%s) - last_pref >= PREF_CHECK )); then
        last_pref=$(date +%s)
        # Supplicant-side scan first: armed scan_ssid makes DIRECTED probes, so a
        # HIDDEN home network becomes visible to the pref check (iw's broadcast scan
        # never shows it — the exact escape this feature exists for was blind to it).
        pref_prescan
        cur_id=$(current_id)
        cand_id=$(best_pref_id "${cur_id:-}")
        # A new stay (the device moved) forgets the flicker memory of the old one.
        if [[ $cur_id != "$pref_stay" ]]; then pref_stay=$cur_id; pref_flickers=0; flicker_said=0; fi
        if [[ -n $cand_id ]]; then
          last_cand=$cand_id   # the name survives a vanishing at the next check
          if (( ++pref_hits >= 2 )); then
            pref_hits=0
            # Names for the story, taken BEFORE any move: the current network's from the
            # live association, the candidate's from its stored entry. The flickers this
            # stay saw before the candidate held for two checks ride the line.
            cand_name=$(name_of_id "$cand_id")
            cur_name=$(dssid); cur_name=${cur_name:-$IF}
            seen_en=""; seen_ar=""
            if (( pref_flickers > 0 )); then
              seen_en=" (seen and lost ${pref_flickers} times before)"; seen_ar=" (ظهرت وغابت ${pref_flickers} مرة قبلها)"
            fi
            pref_flickers=0; flicker_said=0
            site_log INFO "higher-priority network ${cand_name} visible twice - leaving ${cur_name} to go home${seen_en}" \
                          "شبكة أعلى أولوية ${cand_name} ظاهرة مرتين - نترك ${cur_name} ونرجع للبيت${seen_ar}"
            if connect_id "$cand_id"; then
              # MEASURE ON ARRIVAL — priority alone must never overrule the measured-
              # upload law: a slow home gets benched 3 cooldowns and we go straight
              # back (this ended the proven pref-vs-dance 20-minute switch war).
              here=$(up_kbps); probe_on && note_kbps "$here"
              if probe_on; then
                if probe_failed; then say_probe_fail "$(dssid)"
                else site_log INFO "measured ${here} kbps on $(dssid)" "قسنا ${here} كيلوبت/ث على $(dssid)"; fi
              fi
              if probe_on && (( here < CUR_MIN_UP )); then
                tnow=$(date +%s); bench_min=$(( CUR_COOLDOWN * 3 / 60 ))
                # One bench at a time: a newer one ends an older one still running, said so.
                old_name=""
                if [[ -n $PREF_VETO_ID && $PREF_VETO_ID != "$cand_id" ]] && (( tnow < PREF_VETO_UNTIL )); then
                  old_name=$(name_of_id "$PREF_VETO_ID")
                fi
                PREF_VETO_ID=$cand_id; PREF_VETO_UNTIL=$(( tnow + CUR_COOLDOWN * 3 ))
                if [[ -n ${cur_id:-} ]]; then
                  site_log WARN "preferred network $(dssid) too slow (${here} kbps, floor ${CUR_MIN_UP}) - benched for ${bench_min} min, going back to ${cur_name}${old_name:+, ends the bench on ${old_name}}" \
                                "الشبكة المفضلة $(dssid) بطيئة (${here} كيلوبت/ث، الحد ${CUR_MIN_UP}) - في الاحتياط ${bench_min} دقيقة، نرجع على ${cur_name}${old_name:+، وينتهي احتياط ${old_name}}"
                  if return_to "$cur_id" "$cur_name"; then
                    site_log OK "back on ${cur_name}" "رجعنا على ${cur_name}"
                  elif [[ $CONNECT_WHY != "linked but no internet" ]]; then
                    # A link that formed without internet was said by return_to (the device IS
                    # back). Otherwise where the device is now is the truth, read after the
                    # attempt: on wpa the supplicant may sit on nothing until enable_all re-arms
                    # it, on nm NM roams by itself.
                    now_ssid=$(dssid)
                    site_log WARN "the way back to ${cur_name} failed - on ${now_ssid:-no network} now, the next check decides" \
                                  "الرجوع على ${cur_name} فشل - الآن على ${now_ssid:-لا شبكة}، الفحص التالي يقرر"
                  fi
                else
                  site_log WARN "preferred network $(dssid) too slow (${here} kbps, floor ${CUR_MIN_UP}) - benched for ${bench_min} min, staying on it${old_name:+, ends the bench on ${old_name}}" \
                                "الشبكة المفضلة $(dssid) بطيئة (${here} كيلوبت/ث، الحد ${CUR_MIN_UP}) - في الاحتياط ${bench_min} دقيقة، باقون عليها${old_name:+، وينتهي احتياط ${old_name}}"
                fi
                enable_all
              else
                enable_all
                site_log OK "returned to preferred network: $(dssid) ($(up_words "$here"))" \
                            "رجع للشبكة المفضلة: $(dssid) ($(up_words_ar "$here"))"
              fi
            else
              # The attempt's reason is kept: return_to's own connect overwrites CONNECT_WHY.
              why=$CONNECT_WHY; why_ar=$CONNECT_WHY_AR
              if [[ -n ${cur_id:-} ]]; then
                site_log WARN "could not reach the preferred network ${cand_name}: ${why} - going back to ${cur_name}" \
                              "ما قدرنا نوصل للشبكة المفضلة ${cand_name}: ${why_ar} - نرجع على ${cur_name}"
                if return_to "$cur_id" "$cur_name"; then
                  site_log OK "back on ${cur_name}" "رجعنا على ${cur_name}"
                elif [[ $CONNECT_WHY != "linked but no internet" ]]; then
                  now_ssid=$(dssid)
                  site_log WARN "the way back to ${cur_name} failed - on ${now_ssid:-no network} now, the next check decides" \
                                "الرجوع على ${cur_name} فشل - الآن على ${now_ssid:-لا شبكة}، الفحص التالي يقرر"
                fi
              else
                site_log WARN "could not reach the preferred network ${cand_name}: ${why} - no stored network to go back to, the next check decides" \
                              "ما قدرنا نوصل للشبكة المفضلة ${cand_name}: ${why_ar} - ما عندنا شبكة مخزنة نرجع لها، الفحص التالي يقرر"
              fi
              enable_all
            fi
          fi
        else
          # Seen at one check, gone at the next: the return never starts. Said once per stay
          # (a flickering home would otherwise speak every 20 min for hours), counted after.
          if (( pref_hits > 0 )); then
            (( ++pref_flickers ))
            if (( ! flicker_said )); then
              flicker_said=1
              cur_name=$(dssid); cur_name=${cur_name:-$IF}
              site_log INFO "preferred network $(name_of_id "$last_cand") was visible at one check and gone at the next - staying on ${cur_name} until it holds for two checks in a row" \
                            "الشبكة المفضلة $(name_of_id "$last_cand") ظهرت بفحص وغابت بالتالي - باقون على ${cur_name} حتى تثبت فحصين متتاليين"
            fi
          fi
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
        # Named by network, not interface: the network is what the owner can act on.
        lost_on=$(dssid); lost_on=${lost_on:-$IF}
        if (( fails == NET_FAIL_TICKS )); then
          # The router's state is the one fact a phone can act on (call the ISP, or have the
          # router power-cycled): one gateway ping on this tick, once per outage. The loss
          # instant is kept for the restored line's duration; an open late-answer episode ends.
          router_tell; LOST_AT=$(uptime_s)
          late_loss "$lost_on"
          site_log WARN "internet lost on ${lost_on} - router ${ROUTER_EN}, engaging" \
                        "انقطع الانترنت عن ${lost_on} - الراوتر ${ROUTER_AR}، بدأ القتال للرجوع"
          hold_end "internet lost" "انقطع الإنترنت"   # reachability first: the fight chooses the network from here
        fi
        (( ++FIGHT_STREAK ))
        fight && { fails=0; engaged=0; strikes=0
                   # strikes=0: a fight usually lands on a DIFFERENT network — old
                   # strikes must not collapse the new link's 3-sample hysteresis.
                   say_restored "$FIGHT_STREAK"; }
      fi
    fi
    # A command that arrived during the tick body is served now, not after the next sleep: the
    # trap only set the flag, so the wait below would have no signal left to be ended by. The
    # tick body itself stays non-interruptible (the one-consumer rule).
    if (( ! CMD_STUCK )) && { (( WIFI_CMD )) || [[ -s $CMD_FILE ]]; }; then continue; fi
    # Interruptible: bash defers a trapped signal until the foreground command ends, and only
    # the builtin wait returns at once. USR1 (a site command) ends the tick here; the orphan
    # sleep is killed. No -e in this script, so wait's >128 return is harmless.
    sleep "$TICK" 9>&- & SLEEP_PID=$!
    wait "$SLEEP_PID" || { kill "$SLEEP_PID" 2>/dev/null || :; }
  done
}

# ------------------------------- toolbox ----------------------------------------
# TUI palette — aasw's visual language (frame 1;37, banner 1;41, warn 1;33,
# ok 1;32, accent 1;36). Closed boxes carry STATIC ASCII titles only (guaranteed
# alignment); dynamic bilingual content rides open-right colored rows — dynamic
# Arabic inside a closed frame misaligns.
readonly C0=$'\033[0m' CW=$'\033[1;37m' CT=$'\033[1;41m' CY=$'\033[1;33m' \
         CG=$'\033[1;32m' CC=$'\033[1;36m' CR=$'\033[1;31m'
tui_hdr() {  # $1 = ASCII title, padded into the 45-column frame
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
  # Arabic network names read as Arabic, in FIXED columns (raw tabs jumped in
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

cli() {  # the manual toolbox — runs BESIDE the daemon (no lock taken)
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
        # filename) — everything else is owner, so the user can SEE at a glance that
        # their profiles are untouched, whatever their shape.
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
          if [[ ( $nname =~ ^awacs-(crutch|safety|join)-[0-9]+-[0-9]+$ || $nname =~ ^awacs-joined-[0-9a-f]+$ ) \
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
      # signal-to-speed estimation is banned by design; measured kbps lives in logs)
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
# The site's command wake-up: capture.sh sends USR1 after writing CMD_FILE. The handler is one
# assignment; the loop top reads the flag. Installed here, before detect_backend's wait of up to
# 60 s: USR1's default action is termination, so no daemon path may run untrapped.
trap 'WIFI_CMD=1' USR1
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
on_exit() {  # EXIT trap: an end nobody ordered (set -u, a failed exec, a stray exit) is said
  # with its status and the last command (unexpanded source text, so no secret travels),
  # then the spool is drained in the foreground: a background sender would die with this
  # process under systemd. The deliberate exits set DELIBERATE_EXIT first and stay quiet.
  local rc=$? cmd=$BASH_COMMAND fn=${FUNCNAME[1]:-main} where="" where_ar="" next_en next_ar
  cmd_ready_drop   # capture.sh must not signal a PID that no longer traps USR1
  (( DELIBERATE_EXIT || REBOOTING )) && return 0
  [[ $fn != main && $fn != source ]] && { where=" in ${fn}"; where_ar=" في ${fn}"; }
  if [[ -n ${AWACS_DAEMONIZED:-} ]]; then
    next_en="no launcher under -d, start it again"; next_ar="لا مشغّل تحت -d، شغّله من جديد"
  else
    next_en="the launcher restarts it in 10 s"; next_ar="المشغّل يعيده خلال 10 ثوانٍ"
  fi
  net_up=0
  site_log ERROR "AWACS exited unexpectedly (status ${rc}, last command${where}: ${cmd}) - ${next_en}" \
                 "أواكس خرج بشكل غير متوقع (الحالة ${rc}، آخر أمر${where_ar}: ${cmd}) - ${next_ar}"
  flush_spool quiet   # the goodbye needs no delivery line of its own
}
trap on_exit EXIT   # before the lock open, so a failed exec 9>> is caught too
exec 9>>"$LOCK"
say_stopping() {  # $1 = signal name: the graceful end, said once, sent in the foreground
  # (net_up=0 spools it, flush_spool drains it synchronously; a background curl would be
  # killed with the control group). No restart is promised: systemctl stop does not restart.
  (( REBOOTING )) && return 0
  local sig_en sig_ar
  case $1 in
    TERM) sig_en="SIGTERM (systemctl stop or shutdown)"; sig_ar="SIGTERM (إيقاف الخدمة أو إطفاء الجهاز)" ;;
    INT)  sig_en="SIGINT (Ctrl+C)"; sig_ar="SIGINT (Ctrl+C)" ;;
    HUP)  sig_en="SIGHUP (terminal closed)"; sig_ar="SIGHUP (أُغلقت الطرفية)" ;;
    *)    sig_en="SIG$1"; sig_ar="SIG$1" ;;
  esac
  net_up=0
  site_log INFO "AWACS stopping on ${sig_en} - stored networks re-enabled, the network layer runs on its own until the next start" \
                "أواكس يتوقف بإشارة ${sig_ar} - أعدنا تفعيل الشبكات المخزنة، طبقة الشبكة تعمل لوحدها حتى التشغيل القادم"
  flush_spool quiet   # the goodbye needs no delivery line of its own
}
on_shutdown() {  # $1 = signal name. The GRACEFUL box — kept exactly as designed, spacing included
  # IGNORE, not reset: a cgroup stop (systemd unit, system shutdown) delivers a second
  # TERM to the group moments after the first — with the trap merely reset it killed
  # the handler before enable_all ran (seen on every systemd stop). Ignored for the
  # handler's few seconds, the goodbye and the safety both complete; exit 0 ends it.
  trap '' INT TERM QUIT HUP
  DELIBERATE_EXIT=1
  # First act, before the goodbye: a Ctrl+C landing MID-FIGHT (after a
  # select_network narrowed the live supplicant) must hand back full autonomy.
  enable_all 2>/dev/null || :
  # A trial's window sleep, head sleep, wait_first timer or probe child would outlive this
  # shell: ended here, so no orphan holds the trial open after the goodbye (the probe's curl
  # still ends by its own 15 s cap). An answer child is left to finish its one bounded POST on
  # a Ctrl+C; a cgroup stop (systemctl stop, a system shutdown) ends it with the group. Either
  # way an answer that did not land waits in its file for the next start's healthy tick.
  [[ -n $TRIAL_HOLD_PID ]] && { kill "$TRIAL_HOLD_PID" 2>/dev/null || :; }
  [[ -n $TRIAL_HEAD_PID ]] && { kill "$TRIAL_HEAD_PID" 2>/dev/null || :; }
  [[ -n $TRIAL_TIMER_PID ]] && { kill "$TRIAL_TIMER_PID" 2>/dev/null || :; }
  [[ -n $TRIAL_PROBE_PID ]] && { kill "$TRIAL_PROBE_PID" 2>/dev/null || :; }
  hold_on && site_log INFO "hold on ${HOLD_NAME} ends with this stop - the next start judges on its own" \
                           "التثبيت على ${HOLD_NAME} ينتهي مع هذا الإيقاف - التشغيل القادم يحكم بنفسه"
  cmd_ready_drop
  say_stopping "${1:-TERM}"
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
# One trap per signal so the goodbye can name it. HUP: a closing terminal deserves the same grace
trap 'on_shutdown INT' INT; trap 'on_shutdown TERM' TERM; trap 'on_shutdown QUIT' QUIT; trap 'on_shutdown HUP' HUP
if ! flock -n 9; then
  DELIBERATE_EXIT=1   # losing the lock is an ordinary end, not a crash
  # The rc.local respawn loop must stay SILENT (contract). A HUMAN double-launch
  # on a terminal gets the INSTANCE box — kept exactly as designed, spacing included.
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
  # No terminal: a second LAUNCHER (the rc.local line and the systemd unit both enabled)
  # loses here every 10 s. Said once per boot through a marker, into the shared spool the
  # winner's next flush delivers; the loop itself stays silent as the contract says.
  if [[ ! -e $RUN_DIR/lock_lost ]]; then
    : >"$RUN_DIR/lock_lost" 2>/dev/null || :
    running_pid=$(head -1 "$LOCK" 2>/dev/null) || running_pid=""
    [[ $running_pid =~ ^[0-9]+$ ]] || running_pid="?"
    site_log WARN "another AWACS already holds the lock (pid ${running_pid}) - two launchers are running it, keep one (the rc.local line or the systemd unit)" \
                  "نسخة أخرى من أواكس تحمل القفل (pid ${running_pid}) - مشغّلان يشغّلانه، أبقِ واحداً (سطر rc.local أو وحدة systemd)"
  fi
  exit 0
fi
printf '%d\n' "$$" >"$LOCK"   # PID is display-only; flock stays the authority
LOCK_WON=1
# A command left by the previous run is NOT deleted here: the one consumer answers it at the
# first loop top (expired by uptime, or served when the respawn was quick), so the HUD is not
# left waiting out its own guard. RUN_DIR is tmpfs: nothing in it predates this boot.
# CMD_READY is armed inside main, past the monitor-only park, so a tap is never signalled into a void.
# Starts of this boot, counted by the lock winner only: the start line tells a first start
# from a respawn (the launcher bringing a dead daemon back).
START_N=0
read -r START_N 2>/dev/null <"$STARTS_FILE" || START_N=0   # 2> first: the first start has no file
[[ $START_N =~ ^[0-9]+$ ]] || START_N=0
START_N=$(( START_N + 1 )); printf '%d\n' "$START_N" >"$STARTS_FILE" 2>/dev/null || :
# A human typing bare `awacs.sh` gets the daemon in FOREGROUND — say so once (the
# rc.local respawn has no TTY and must stay silent by contract).
[[ -t 1 ]] && echo -e "${CC}AWACS ${VERSION}${C0}: foreground daemon on ${IF} — Ctrl+C يوقفه بأمان، ${CW}awacs.sh help${C0} لبقية الأوامر"
main
