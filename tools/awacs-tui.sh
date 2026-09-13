#!/usr/bin/env bash
#
# awacs-tui.sh — read-only terminal dashboard for AWACS.
#
# Pure bash + tput: no dialog, no whiptail, no python. The screen redraws every
# 2 seconds. Every panel is built from the same read-only sources awacs.sh uses
# for its own `status`, `networks` and `evaluate` words:
#   - iw / ip for the link (SSID, band, signal, address, default route)
#   - the lock file in RUN_DIR plus /proc for the daemon pid (PID reuse checked)
#   - wpa_cli list_networks (wpa) or nmcli connection show (nm) for stored networks
#   - the daemon's scan cache (wpa) or NetworkManager's own cache (nm) for the
#     "visible" mark — this dashboard never triggers a radio scan itself
#   - the log file for the tail
# It never takes the daemon's lock and never connects to anything. The one key
# that generates network traffic is `s` (runs `awacs.sh speed`), on demand only.
#
# Keys   q quit   r redraw now   s awacs.sh speed   e awacs.sh evaluate
#        l toggle label language (en/ar) — values are shown as they are
# Flags  --plain          no tput, no escape codes: one full frame per refresh
#        --once           draw one frame and exit (with --plain: a text dump)
#        --lang en|ar     initial label language (default en)
#        --interval N     seconds between redraws (default 2)
# Env    AWACS_CONF       settings file to read LOG_FILE / RUN_DIR / SITE_URL from
#                         (default /etc/awacs.conf; read as plain KEY=value, never sourced)
#        AWACS_IF         interface (default: the connected > up > present ladder of awacs.sh)
#        AWACS_BIN        path to awacs.sh (default: awacs.sh on PATH, then /usr/local/bin)
#        NO_COLOR         set to anything to disable colour
#        COLUMNS, LINES   terminal size when tput cannot report it (plain mode, pipes)
#
# Root: the wpa_cli control socket, RUN_DIR and the log are root-only, so run
# with sudo for the full picture. Without root it still runs and marks what it
# cannot read. Needs bash 5 (EPOCHSECONDS). Minimum terminal: 80x24.
set -uo pipefail
IFS=$'\n\t'
umask 077

PLAIN=0 ONCE=0 INTERVAL=2 UI=en
NET_EVERY=5            # seconds between gateway/internet checks (background)
SLOW_EVERY=5           # redraws between stored-network and backend refreshes
STATE=""               # private temp dir holding the background checker's verdict
WORKER=""              # its pid
CONF=${AWACS_CONF:-/etc/awacs.conf}
LOG_FILE=/var/log/awacs.log
RUN_DIR=/run/awacs
SITE_URL=""
IF=""
BACKEND=wpa
ROWS=24 W=79           # terminal rows and usable width (columns - 1)
B="" N="" G="" R="" Y="" C=""
LBL="" PAD="" BYTES=0 NOTICE="" PSSID=""
LINK_SSID="" LINK_SIG="" LINK_FREQ=""
DEVID="" DEVID_DEFAULT=0
TX_PREV=0 TX_PREV_T=0 TX_RATE="-"
NET_G=- NET_N=- NET_GW=- NET_AGE=-
KNOWN_INFO=""
declare -a FRAME=()
declare -a KNOWN=()

usage() {
  cat <<'USAGE'
usage: awacs-tui.sh [--plain] [--once] [--lang en|ar] [--interval N]
  read-only AWACS dashboard; keys: q quit, r refresh, s speed, e evaluate, l labels en/ar
  لوحة مراقبة للقراءة فقط؛ المفاتيح: q خروج، r تحديث، s قياس السرعة، e التقييم، l لغة العناوين
USAGE
}

while (( $# )); do
  case $1 in
    --plain)    PLAIN=1 ;;
    --once)     ONCE=1 ;;
    --lang)     UI=${2:-en}; shift ;;
    --lang=*)   UI=${1#--lang=} ;;
    --interval) INTERVAL=${2:-2}; shift ;;
    -h|--help)  usage; exit 0 ;;
    *)          usage >&2; exit 1 ;;
  esac
  shift || break
done
[[ $UI == ar ]] || UI=en
[[ $INTERVAL =~ ^[1-9][0-9]?$ ]] || INTERVAL=2

# ------------------------------- labels ----------------------------------------
lbl() {  # sets LBL to the label for key $1 in the current UI language
  if [[ $UI == ar ]]; then
    case $1 in
      title)     LBL='AWACS' ;;
      device)    LBL='الجهاز' ;;
      default)   LBL='افتراضي' ;;
      backend)   LBL='النظام' ;;
      daemon)    LBL='الحارس' ;;
      running)   LBL='يعمل' ;;
      stopped)   LBL='متوقف' ;;
      site)      LBL='الموقع' ;;
      local)     LBL='محلي فقط' ;;
      network)   LBL='الشبكة' ;;
      band)      LBL='الحزمة' ;;
      signal)    LBL='الإشارة' ;;
      tx)        LBL='الرفع' ;;
      ip)        LBL='العنوان' ;;
      gateway)   LBL='الراوتر' ;;
      internet)  LBL='الإنترنت' ;;
      gw_ok)     LBL='يرد' ;;
      gw_bad)    LBL='لا يرد' ;;
      gw_none)   LBL='لا مسار' ;;
      net_ok)    LBL='متصل' ;;
      net_bad)   LBL='مقطوع' ;;
      pending)   LBL='جارٍ الفحص' ;;
      ago)       LBL='قبل %s ث' ;;
      known)     LBL='الشبكات المخزنة' ;;
      legend)    LBL='* الحالية  v ظاهرة  on/off مفعّلة' ;;
      scan_age)  LBL='المسح قبل %s ث' ;;
      scan_min)  LBL='المسح قبل %s د' ;;
      scan_none) LBL='لا مسح مخزن' ;;
      nm_cache)  LBL='كاش NM' ;;
      c_id)      LBL='المعرف' ;;
      c_prio)    LBL='الأولوية' ;;
      c_en)      LBL='الحالة' ;;
      c_sig)     LBL='الإشارة' ;;
      c_ssid)    LBL='الاسم' ;;
      more)      LBL='و%s أخرى (تظهر في طرفية أطول)' ;;
      none)      LBL='(لا شبكات مخزنة، أو لا يمكن قراءتها — شغّل الأداة بـ sudo)' ;;
      log)       LBL='السجل' ;;
      last)      LBL='آخر %s سطراً' ;;
      nolog)     LBL='(لا يمكن قراءة السجل: %s)' ;;
      keys)      LBL='q خروج   r تحديث   s قياس السرعة   e التقييم   l English' ;;
      anykey)    LBL='اضغط أي مفتاح للعودة إلى اللوحة' ;;
      noroot)    LBL='ليس root: بعض اللوحات لا تُقرأ' ;;
      nobin)     LBL='awacs.sh غير موجود — حدد AWACS_BIN' ;;
      *)         LBL=$1 ;;
    esac
  else
    case $1 in
      title)     LBL='AWACS' ;;
      device)    LBL='device' ;;
      default)   LBL='default' ;;
      backend)   LBL='backend' ;;
      daemon)    LBL='daemon' ;;
      running)   LBL='running' ;;
      stopped)   LBL='stopped' ;;
      site)      LBL='site' ;;
      local)     LBL='local-only' ;;
      network)   LBL='network' ;;
      band)      LBL='band' ;;
      signal)    LBL='signal' ;;
      tx)        LBL='tx' ;;
      ip)        LBL='ip' ;;
      gateway)   LBL='gateway' ;;
      internet)  LBL='internet' ;;
      gw_ok)     LBL='reachable' ;;
      gw_bad)    LBL='no reply' ;;
      gw_none)   LBL='no route' ;;
      net_ok)    LBL='online' ;;
      net_bad)   LBL='OFFLINE' ;;
      pending)   LBL='checking' ;;
      ago)       LBL='%s s ago' ;;
      known)     LBL='stored networks' ;;
      legend)    LBL='* current  v visible  on/off enabled' ;;
      scan_age)  LBL='scan %s s old' ;;
      scan_min)  LBL='scan %s min old' ;;
      scan_none) LBL='no scan cache' ;;
      nm_cache)  LBL='NM cache' ;;
      c_id)      LBL='ID' ;;
      c_prio)    LBL='PRIO' ;;
      c_en)      LBL='EN' ;;
      c_sig)     LBL='SIG' ;;
      c_ssid)    LBL='SSID' ;;
      more)      LBL='+%s more (a taller terminal shows them)' ;;
      none)      LBL='(no stored networks, or not readable - run with sudo)' ;;
      log)       LBL='log' ;;
      last)      LBL='last %s lines' ;;
      nolog)     LBL='(log not readable: %s)' ;;
      keys)      LBL='q quit   r refresh   s speed probe   e evaluate   l عربي' ;;
      anykey)    LBL='press any key to return to the dashboard' ;;
      noroot)    LBL='not root: some panels cannot be read' ;;
      nobin)     LBL='awacs.sh not found - set AWACS_BIN' ;;
      *)         LBL=$1 ;;
    esac
  fi
}

# ------------------------------- text helpers ----------------------------------
nbytes() { local LC_ALL=C; BYTES=${#1}; }  # byte length even in a UTF-8 locale
padr() {  # PAD = $1 cut/padded to $2 cells. printf pads by BYTES, so the width is
  # widened by (bytes - chars): Arabic text keeps its column on a UTF-8 terminal.
  local s=${1:0:$2}
  nbytes "$s"
  printf -v PAD '%-*s' "$(( $2 + BYTES - ${#s} ))" "$s"
}
pssid() {  # PSSID = display form of iw's escaped SSID: \xNN decoded, control
  # characters stripped (a neighbour can put escape codes in an AP name). Pure bash.
  printf -v PSSID '%b' "$1"
  PSSID=${PSSID//[[:cntrl:]]/}
}
add() { FRAME+=("${1:0:$W}"); }          # one frame line, cut to the usable width
add2() {  # $1 = plain text, $2 = the same text with colour codes: colour only when
  # the plain form fits — cutting a coloured line would cut escape sequences too.
  if (( ${#1} <= W )); then FRAME+=("$2"); else FRAME+=("${1:0:$W}"); fi
}

# ------------------------------- sources ---------------------------------------
read_conf() {  # LOG_FILE / RUN_DIR / SITE_URL from the conf — plain KEY=value only
  [[ -r $CONF ]] || return 0
  local k v
  while IFS='=' read -r k v; do
    k=${k//[[:space:]]/}
    v=${v%%#*}
    v=${v#"${v%%[![:space:]]*}"}; v=${v%"${v##*[![:space:]]}"}
    v=${v#\"}; v=${v%\"}; v=${v#\'}; v=${v%\'}
    case $k in
      LOG_FILE) [[ $v == /* ]] && LOG_FILE=$v ;;
      RUN_DIR)  [[ $v == /* ]] && RUN_DIR=$v ;;   # awacs.sh's rule: relative = ignored
      SITE_URL) SITE_URL=$v ;;
    esac
  done < <(grep -E '^[[:space:]]*(LOG_FILE|RUN_DIR|SITE_URL)[[:space:]]*=' "$CONF" 2>/dev/null)
}

detect_if() {  # awacs.sh's ladder: connected > up > present; wlan0 when nothing answers
  local best="" state=0 i s
  for i in $(iw dev 2>/dev/null | awk '$1 == "Interface" { print $2 }'); do
    s=0
    ip link show "$i" 2>/dev/null | grep -q ' UP' && s=1
    (( s == 1 )) && iw dev "$i" link 2>/dev/null | grep -q '^Connected' && s=2
    (( s == 2 )) && { best=$i; break; }
    (( s > state )) && { best=$i; state=$s; }
    [[ -z $best ]] && best=$i
  done
  [[ -n $best ]] || best=wlan0
  printf '%s' "$best"
}

nm_dev_state() {
  local st; st=$(nmcli -g GENERAL.STATE device show "$IF" 2>/dev/null)
  st=${st%% *}
  if [[ $st =~ ^[0-9]+$ ]]; then printf '%s' "$st"; else printf '0'; fi
}
detect_backend() {  # awacs.sh's verdict, fast form: wpa | nm | nm_lame
  BACKEND=wpa
  if systemctl is-active --quiet NetworkManager 2>/dev/null \
     || systemctl is-enabled --quiet NetworkManager 2>/dev/null; then
    BACKEND="nm"
    if ! command -v nmcli >/dev/null 2>&1; then BACKEND=nm_lame
    elif [[ $(nm_dev_state) == 10 ]]; then BACKEND=nm_lame; fi
  fi
}

daemon_pid() {  # pid from the lock file, accepted only when that process IS awacs
  local p=""
  [[ -s $RUN_DIR/lock ]] && { read -r p <"$RUN_DIR/lock"; } 2>/dev/null
  if [[ $p =~ ^[0-9]+$ && -d /proc/$p ]] && grep -aq awacs "/proc/$p/cmdline" 2>/dev/null; then
    printf '%s' "$p"
  fi
  return 0
}

device_id() {  # env, then /tmp/device_id, then the running daemon's environment
  local d p
  d=${DEVICE_ID:-}
  [[ -n $d ]] || d=$(grep -m1 . /tmp/device_id 2>/dev/null)
  if [[ -z $d ]]; then
    p=$(daemon_pid)
    [[ -n $p ]] && d=$(tr '\0' '\n' <"/proc/$p/environ" 2>/dev/null | sed -n 's/^DEVICE_ID=//p' | head -1)
  fi
  DEVID_DEFAULT=0
  if ! [[ $d =~ ^[A-Za-z0-9_-]{1,32}$ ]]; then   # awacs.sh's own fallback: hostname -s, then "device"
    d=$(hostname -s 2>/dev/null || :); DEVID_DEFAULT=1
    [[ $d =~ ^[A-Za-z0-9_-]{1,32}$ ]] || d=device
  fi
  DEVID=$d
}

link_info() {  # LINK_SSID / LINK_SIG / LINK_FREQ from ONE `iw dev link` call (the same
  # three lines awacs.sh reads); parsed in bash so a redraw costs one spawn here
  local out l
  LINK_SSID="" LINK_SIG="" LINK_FREQ=""
  out=$(iw dev "$IF" link 2>/dev/null) || return 0
  while IFS= read -r l; do
    l=${l#"${l%%[![:space:]]*}"}
    case $l in
      'SSID: '*)   [[ -z $LINK_SSID ]] && LINK_SSID=${l#SSID: } ;;
      'signal: '*) [[ -z $LINK_SIG ]]  && LINK_SIG=${l#signal: } ;;
      'freq: '*)   [[ -z $LINK_FREQ ]] && LINK_FREQ=${l#freq: } ;;
      *) : ;;
    esac
  done <<<"$out"
  return 0
}
band_of() {  # same thresholds as awacs.sh report_wifi
  local f=${1%%.*}
  [[ $f =~ ^[0-9]+$ ]] || { printf '-'; return 0; }
  if   (( f >= 5925 )); then printf '6GHz'
  elif (( f >= 4900 )); then printf '5GHz'
  elif (( f >= 2400 && f <= 2500 )); then printf '2.4GHz'
  else printf '-'; fi
}
tx_sample() {  # passive upload meter from kernel counters between two redraws
  local f=/sys/class/net/$IF/statistics/tx_bytes b t
  b=$(cat "$f" 2>/dev/null) || { TX_RATE="-"; return 0; }
  [[ $b =~ ^[0-9]+$ ]] || { TX_RATE="-"; return 0; }
  t=$EPOCHSECONDS
  if (( TX_PREV_T > 0 && t > TX_PREV_T && b >= TX_PREV )); then
    TX_RATE="$(( (b - TX_PREV) * 8 / ((t - TX_PREV_T) * 1000) )) kbps"
  fi
  TX_PREV=$b TX_PREV_T=$t
}

have_net() {  # awacs.sh's ladder; the site rung only when SITE_URL is set
  ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 && return 0
  ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 && return 0
  [[ $(curl -s -o /dev/null -w '%{http_code}' --max-time 3 \
       "http://connectivitycheck.gstatic.com/generate_204" 2>/dev/null) == "204" ]] && return 0
  [[ -n $SITE_URL ]] || return 1
  [[ $(curl -s -o /dev/null -w '%{http_code}' --max-time 3 --data-urlencode "probe=1" \
       "${SITE_URL%/}/${DEVID}/device_api.php" 2>/dev/null) == "400" ]]
}
net_probe() {  # one gateway + internet check -> $STATE/net (atomic replace)
  local gw g=0 n=0
  gw=$(ip -4 route show default dev "$IF" 2>/dev/null | awk '{print $3; exit}')
  [[ -n $gw ]] && ping -c 1 -W 2 "$gw" >/dev/null 2>&1 && g=1
  have_net && n=1
  printf '%s\t%s\t%s\t%s\n' "$g" "$n" "${gw:--}" "$EPOCHSECONDS" >"$STATE/net.t" 2>/dev/null \
    && mv -f "$STATE/net.t" "$STATE/net" 2>/dev/null
  return 0
}
net_worker() { while :; do net_probe; sleep "$NET_EVERY"; done; }
read_net() {
  local g n gw ts
  NET_G=- NET_N=- NET_GW=- NET_AGE=-
  [[ -s $STATE/net ]] || return 0
  IFS=$'\t' read -r g n gw ts <"$STATE/net" || :
  NET_G=$g NET_N=$n NET_GW=$gw
  [[ $ts =~ ^[0-9]+$ ]] && NET_AGE=$(( EPOCHSECONDS - ts ))
  return 0
}

known_rows_wpa() {  # id \t name \t prio \t enabled \t current \t visible \t signal
  local id ssid _bssid flags p en cur vis sig cache
  cache=$(cat "$RUN_DIR/scan" 2>/dev/null)   # the daemon's cache — never a scan of our own
  while IFS=$'\t' read -r id ssid _bssid flags; do
    [[ $id =~ ^[0-9]+$ ]] || continue
    p=$(wpa_cli -i "$IF" get_network "$id" priority 2>/dev/null); [[ $p =~ ^-?[0-9]+$ ]] || p=0
    cur=0; [[ ${flags:-} == *"[CURRENT]"* ]] && cur=1
    en=on
    [[ ${flags:-} == *"[TEMP-DISABLED]"* ]] && en=temp-off
    [[ ${flags:-} == *"[DISABLED]"* ]] && en=off
    vis=0; sig="-"
    if [[ -n $cache ]]; then   # exact raw-text match, the way awacs.sh matches on wpa
      sig=$(W="$ssid" awk -F'\t' '$1 == ENVIRON["W"] { print $2; exit }' <<<"$cache")
      if [[ -n $sig ]]; then vis=1; sig="${sig} dBm"; else sig="-"; fi
    fi
    pssid "$ssid"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$PSSID" "$p" "$en" "$cur" "$vis" "$sig"
  done < <(wpa_cli -i "$IF" list_networks 2>/dev/null | tail -n +2)
}
known_rows_nm() {  # same columns; visibility = hex SSID in NM's own cache (--rescan no)
  local uuid type auto prio active ssid hex sig air vis cur en
  air=$(nmcli -t -f SSID-HEX,SIGNAL device wifi list ifname "$IF" --rescan no 2>/dev/null | tr 'A-F' 'a-f')
  while IFS=: read -r uuid type auto prio active; do
    [[ $type == wifi || $type == 802-11-wireless ]] || continue
    ssid=$(nmcli -e no -g 802-11-wireless.ssid connection show uuid "$uuid" 2>/dev/null | tr -d '\000-\037\177')
    hex=$(printf '%s' "$ssid" | od -An -tx1 | tr -d ' \n')
    sig=$(S="$hex" awk -F: '$1 == ENVIRON["S"] { print $2; exit }' <<<"$air")
    vis=0
    if [[ -n $sig ]]; then vis=1; sig="${sig}%"; else sig="-"; fi
    cur=0; [[ $active == yes ]] && cur=1
    en=on; [[ $auto == yes ]] || en=off
    [[ $prio =~ ^-?[0-9]+$ ]] || prio=0
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "${uuid:0:8}" "$ssid" "$prio" "$en" "$cur" "$vis" "$sig"
  done < <(nmcli -t -f UUID,TYPE,AUTOCONNECT,AUTOCONNECT-PRIORITY,ACTIVE connection show 2>/dev/null)
}
refresh_known() {
  local line age
  KNOWN=()
  if [[ $BACKEND == wpa ]]; then
    while IFS= read -r line; do [[ -n $line ]] && KNOWN+=("$line"); done < <(known_rows_wpa)
    if [[ -s $RUN_DIR/scan ]]; then
      age=$(( EPOCHSECONDS - $(stat -c %Y "$RUN_DIR/scan" 2>/dev/null || echo "$EPOCHSECONDS") ))
      if (( age >= 120 )); then lbl scan_min; KNOWN_INFO=${LBL//%s/$(( age / 60 ))}
      else lbl scan_age; KNOWN_INFO=${LBL//%s/$age}; fi
    else
      lbl scan_none; KNOWN_INFO=$LBL
    fi
  else
    while IFS= read -r line; do [[ -n $line ]] && KNOWN+=("$line"); done < <(known_rows_nm)
    lbl nm_cache; KNOWN_INFO=$LBL
  fi
}

# ------------------------------- frame -----------------------------------------
build() {
  FRAME=()
  local now ssid band ipa dp plain col gwv netv age i k n id name prio en cur vis ss marks
  local title coloured logrows
  now=$(date '+%H:%M:%S')
  dp=$(daemon_pid)

  # 1. header: title, device, backend, daemon, site
  lbl title; title=$LBL
  lbl device; plain="${title}  ${LBL} ${DEVID}"
  (( DEVID_DEFAULT )) && { lbl default; plain+=" (${LBL})"; }
  lbl backend; plain+="  ${LBL} ${BACKEND}"
  lbl daemon;  plain+="  ${LBL} "
  if [[ -n $dp ]]; then lbl running; plain+="${LBL} (pid ${dp})"; else lbl stopped; plain+="$LBL"; fi
  lbl site
  if [[ -n $SITE_URL ]]; then plain+="  ${LBL} ${SITE_URL#*://}"; else lbl local; plain+="  ${LBL}"; fi
  (( ${#plain} > W )) && [[ -n $dp ]] && plain=${plain/ (pid ${dp})/}   # narrow: drop the pid first
  add2 "$plain" "${B}${title}${N}${plain:${#title}}"

  # 2. current network (two lines)
  link_info
  pssid "$LINK_SSID"; ssid=$PSSID
  band=$(band_of "$LINK_FREQ")
  ipa=$(ip -4 addr show dev "$IF" scope global 2>/dev/null | awk '/inet /{print $2; exit}')
  tx_sample
  lbl network; padr "$LBL" 9; plain="${PAD} ${ssid:0:20}"
  (( ${#ssid} == 0 )) && plain="${PAD} -"
  lbl band;   plain+="  ${LBL} ${band}"
  lbl signal; plain+="  ${LBL} ${LINK_SIG:--}"
  lbl tx;     plain+="  ${LBL} ${TX_RATE}"
  add2 "$plain" "${Y}${plain:0:9}${N}${plain:9}"

  read_net
  lbl ip; padr "$LBL" 9; plain="${PAD} ${ipa:--}"
  lbl gateway; plain+="  ${LBL} "
  case $NET_G in
    1) lbl gw_ok;  gwv=$LBL; col="${G}${gwv}${N}" ;;
    0) if [[ $NET_GW == - ]]; then lbl gw_none; else lbl gw_bad; fi
       gwv=$LBL; col="${R}${gwv}${N}" ;;
    *) lbl pending; gwv=$LBL; col=$gwv ;;
  esac
  coloured="${Y}${plain:0:9}${N}${plain:9}${col}"
  plain+="$gwv"
  lbl internet; plain+="  ${LBL} "; coloured+="  ${LBL} "
  case $NET_N in
    1) lbl net_ok;  netv=$LBL; col="${G}${netv}${N}" ;;
    0) lbl net_bad; netv=$LBL; col="${R}${netv}${N}" ;;
    *) lbl pending; netv=$LBL; col=$netv ;;
  esac
  plain+="$netv"; coloured+="$col"
  if [[ $NET_AGE != - ]]; then
    lbl ago; age=${LBL//%s/$NET_AGE}; plain+=" (${age})"; coloured+=" (${age})"
  fi
  add2 "$plain" "$coloured"

  # 3. stored networks: title, column header, K rows. Fixed rows: header 1 + network 2
  #    + this title and column header 2 + log title 1 + key bar 1 = 7. The list takes
  #    what it needs (at most what leaves the log its 12 lines); the log gets the rest.
  n=${#KNOWN[@]}
  k=$(( n > 0 ? n : 1 ))
  (( k > ROWS - 19 )) && k=$(( ROWS - 19 ))
  (( k < 1 )) && k=1
  logrows=$(( ROWS - 7 - k )); (( logrows < 12 )) && logrows=12
  lbl known;  plain="${LBL} (${n})"
  lbl legend; plain+=" - ${LBL} - ${KNOWN_INFO}"
  add2 "$plain" "${C}${B}${plain}${N}"
  lbl c_id;   padr "$LBL" 8; plain="   ${PAD} "
  lbl c_prio; padr "$LBL" 8; plain+="${PAD} "
  lbl c_en;   padr "$LBL" 8; plain+="${PAD} "
  lbl c_sig;  padr "$LBL" 8; plain+="${PAD} "
  lbl c_ssid; plain+="$LBL"
  add "$plain"
  if (( n == 0 )); then
    lbl none; add "  $LBL"
    for (( i = 1; i < k; i++ )); do add ""; done
  else
    for (( i = 0; i < k && i < n; i++ )); do
      if (( i == k - 1 && n > k )); then
        lbl more; add "  ${LBL//%s/$(( n - i ))}"; break
      fi
      IFS=$'\t' read -r id name prio en cur vis ss <<<"${KNOWN[i]}"
      marks="  "; (( cur )) && marks="* "; (( vis )) && marks="${marks:0:1}v"
      padr "$id" 8;   plain="${marks} ${PAD} "
      padr "$prio" 8; plain+="${PAD} "
      padr "$en" 8;   plain+="${PAD} "
      padr "$ss" 8;   plain+="${PAD} ${name}"
      if (( cur )); then add2 "$plain" "${G}${plain:0:2}${N}${plain:2}"; else add "$plain"; fi
    done
    for (( ; i < k; i++ )); do add ""; done
  fi

  # 4. log tail: title + logrows lines (12 at 80x24; more when the terminal is taller)
  lbl log; plain="${LBL}  ${LOG_FILE}"
  lbl last; plain+="  (${LBL//%s/$logrows})"
  add2 "$plain" "${C}${B}${plain}${N}"
  i=0
  if [[ -r $LOG_FILE ]]; then
    while IFS= read -r plain; do add "$plain"; (( ++i )); done < <(tail -n "$logrows" "$LOG_FILE" 2>/dev/null)
  else
    lbl nolog; add "  ${LBL//%s/$LOG_FILE}"; i=1
  fi
  for (( ; i < logrows; i++ )); do add ""; done

  # 5. key bar on the last row with the clock at the right edge; a notice rides
  #    the row above it
  while (( ${#FRAME[@]} < ROWS - 1 )); do add ""; done
  if (( ${#FRAME[@]} > ROWS - 1 )); then FRAME=("${FRAME[@]:0:$(( ROWS - 1 ))}"); fi
  [[ -n $NOTICE ]] && FRAME[ROWS-2]=${NOTICE:0:$W}
  lbl keys; padr "$LBL" $(( W - 9 ))
  if (( ${#LBL} <= W - 9 )); then add2 "${PAD} ${now}" "${B}${LBL}${N}${PAD:${#LBL}} ${now}"
  else add "${PAD} ${now}"; fi
}

# ------------------------------- screen ----------------------------------------
init_term() {
  if (( ! PLAIN )) && [[ -t 1 && ${TERM:-dumb} != dumb ]] \
     && command -v tput >/dev/null 2>&1 && tput cup 0 0 >/dev/null 2>&1; then
    :
  else
    PLAIN=1
  fi
  if (( ! PLAIN )) && [[ -z ${NO_COLOR:-} ]] && (( $(tput colors 2>/dev/null || echo 0) >= 8 )); then
    B=$(tput bold) N=$(tput sgr0) G=$(tput setaf 2) R=$(tput setaf 1) Y=$(tput setaf 3) C=$(tput setaf 6)
  fi
}
read_size() {
  local c r
  if (( PLAIN )); then c=${COLUMNS:-80}; r=${LINES:-24}
  else c=$(tput cols 2>/dev/null || echo "${COLUMNS:-80}"); r=$(tput lines 2>/dev/null || echo "${LINES:-24}"); fi
  [[ $c =~ ^[0-9]+$ ]] && (( c >= 40 )) || c=80
  [[ $r =~ ^[0-9]+$ ]] && (( r >= 12 )) || r=24
  ROWS=$r W=$(( c - 1 ))
}
enter_screen() { (( PLAIN )) && return 0; tput smcup 2>/dev/null || :; tput civis 2>/dev/null || :; tput clear; }
leave_screen() { (( PLAIN )) && return 0; tput cnorm 2>/dev/null || :; tput rmcup 2>/dev/null || :; }
paint() {
  local i n=${#FRAME[@]}
  if (( PLAIN )); then
    for (( i = 0; i < n; i++ )); do printf '%s\n' "${FRAME[i]}"; done
    (( ONCE )) || printf '\n'
    return 0
  fi
  tput cup 0 0
  for (( i = 0; i < n; i++ )); do
    printf '%s' "${FRAME[i]}"; tput el
    (( i < n - 1 )) && printf '\n'
  done
  tput ed 2>/dev/null || :
}

awacs_bin() {
  if [[ -n ${AWACS_BIN:-} ]]; then printf '%s' "$AWACS_BIN"; return 0; fi
  command -v awacs.sh 2>/dev/null && return 0
  [[ -x /usr/local/bin/awacs.sh ]] && { printf '/usr/local/bin/awacs.sh'; return 0; }
  return 1
}
run_tool() {  # speed | evaluate — the two on-demand awacs.sh words (speed sends traffic)
  local bin
  bin=$(awacs_bin) || { lbl nobin; NOTICE=$LBL; return 0; }
  NOTICE=""
  leave_screen
  printf '\n$ %s %s\n\n' "$bin" "$1"
  "$bin" "$1" || :
  lbl anykey; printf '\n%s\n' "$LBL"
  IFS= read -rsn1 -t 120 _ || :
  enter_screen
}

cleanup() {
  trap - EXIT
  [[ -n $WORKER ]] && kill "$WORKER" 2>/dev/null
  leave_screen
  [[ -n $STATE && -d $STATE ]] && rm -rf -- "$STATE"
}

main() {
  local tick=0 key rc
  init_term
  read_conf
  IF=${AWACS_IF:-$(detect_if)}
  STATE=$(mktemp -d "${TMPDIR:-/tmp}/awacs-tui.XXXXXX") \
    || { echo 'awacs-tui: cannot create a temp dir' >&2; exit 1; }
  trap cleanup EXIT
  trap 'exit 0' INT TERM HUP
  detect_backend
  device_id
  (( EUID == 0 )) || { lbl noroot; NOTICE=$LBL; }
  if (( ONCE )); then net_probe; else net_worker & WORKER=$!; fi
  refresh_known
  enter_screen
  while :; do
    read_size
    (( tick > 0 && tick % SLOW_EVERY == 0 )) && { detect_backend; device_id; refresh_known; }
    build; paint
    (( ONCE )) && break
    key=""
    IFS= read -rsn1 -t "$INTERVAL" key; rc=$?
    if (( rc > 128 )); then :                      # timeout = a plain redraw
    elif (( rc != 0 )); then sleep "$INTERVAL"; fi  # stdin closed: keep the cadence
    case $key in
      q|Q) break ;;
      r|R) detect_backend; device_id; refresh_known ;;
      l|L) if [[ $UI == ar ]]; then UI="en"; else UI="ar"; fi
           refresh_known ;;                        # KNOWN_INFO carries a label
      s|S) run_tool speed ;;
      e|E) run_tool evaluate ;;
      *)   : ;;
    esac
    (( ++tick ))
  done
}
main
