#!/usr/bin/env bash
#
# gen-config-table.sh — build the knob table of docs/*/config-reference.md from
# awacs.sh and awacs.conf.example, so the table cannot drift from the code.
#
# Columns
#   knob                    every KEY assigned in the configuration block at the top
#                           of awacs.sh (before the conf is sourced), then any KEY the
#                           example documents that the script does not have
#   default in awacs.sh     the value assigned there; a dash = not in this build
#   default in the example  the FIRST `KEY=value` or `# KEY=value` line for that KEY
#                           in awacs.conf.example (the defaults come before the
#                           deployment shapes, so the first hit is the default)
#   validated               number: listed in the script's numeric check loop
#                           (`for _kv in ...`); HH:MM, absolute path and shape: the
#                           `[[ ${KEY:-} ... ]]` checks right after it; one of: a
#                           `case ${KEY:-} in a|b|c)` enum check; no: taken as written
#   used in                 functions whose bodies mention the knob, in order of first
#                           appearance; "(top level)" = code outside any function that
#                           runs after the knobs are sealed readonly
#
# usage: gen-config-table.sh [--script FILE] [--example FILE] [--lang en|ar] [--write DOC]
#   Without --write the markdown table goes to stdout. With --write the block between
#   <!-- BEGIN GENERATED TABLE --> and <!-- END GENERATED TABLE --> in DOC is replaced.
#   Defaults: awacs.sh and awacs.conf.example in the repository root (the parent of
#   this tools/ directory); language en.
# Needs only stock tools: bash, awk, grep, sed, sha256sum, wc.
set -uo pipefail
IFS=$'\n\t'

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="$here/../awacs.sh"
EXAMPLE="$here/../awacs.conf.example"
LANG_OUT=en
DOC=""

usage() { echo 'usage: gen-config-table.sh [--script FILE] [--example FILE] [--lang en|ar] [--write DOC]'; }

while (( $# )); do
  case $1 in
    --script)  SCRIPT=${2:-}; shift ;;
    --example) EXAMPLE=${2:-}; shift ;;
    --lang)    LANG_OUT=${2:-en}; shift ;;
    --write)   DOC=${2:-}; shift ;;
    -h|--help) usage; exit 0 ;;
    *)         usage >&2; exit 1 ;;
  esac
  shift || break
done
[[ -r $SCRIPT ]]  || { echo "gen-config-table: cannot read script: $SCRIPT" >&2; exit 1; }
[[ -r $EXAMPLE ]] || { echo "gen-config-table: cannot read example: $EXAMPLE" >&2; exit 1; }
[[ $LANG_OUT == ar ]] || LANG_OUT=en

declare -A SDEF=() EDEF=() VAL=() USED=() SEEN=()
declare -a KNOBS=()

strip_comment() {  # STRIPPED = $1 without a trailing "  # comment" (whitespace before #)
  STRIPPED=$1
  if [[ $STRIPPED =~ ^(.*[^[:space:]])[[:space:]]+#.*$ ]]; then STRIPPED=${BASH_REMATCH[1]}; fi
}

# 1. the script's configuration block: header line to the AWACS_CONF line
block=$(awk '/^# -+ configuration -+/ { on = 1; next } /^AWACS_CONF=/ { exit } on' "$SCRIPT")
while IFS= read -r line; do
  if [[ $line =~ ^declare\ -A\ ([A-Z][A-Z0-9_]*)= ]]; then
    k=${BASH_REMATCH[1]}; v='(empty)'
  elif [[ $line =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]]; then
    k=${BASH_REMATCH[1]}; strip_comment "${BASH_REMATCH[2]}"; v=$STRIPPED
  else
    continue
  fi
  [[ $k == VERSION || $k == AWACS_CONF ]] && continue
  [[ -n ${SEEN[$k]:-} ]] && continue
  SEEN[$k]=1; KNOBS+=("$k"); SDEF[$k]=$v
done <<<"$block"

# 2. the example's defaults: first `KEY=` or `# KEY=` line per key
while IFS= read -r line; do
  if [[ $line =~ ^#?[[:space:]]*([A-Z][A-Z0-9_]*)(\[[^]]*\])?=(.*)$ ]]; then
    k=${BASH_REMATCH[1]}
    [[ -n ${EDEF[$k]:-} ]] && continue
    if [[ -n ${BASH_REMATCH[2]} ]]; then EDEF[$k]='(examples)'
    else strip_comment "${BASH_REMATCH[3]}"; EDEF[$k]=$STRIPPED; fi
    [[ -n ${SEEN[$k]:-} ]] || { SEEN[$k]=1; KNOBS+=("$k"); }
  fi
done <"$EXAMPLE"

# 3. validation: the numeric loop, then the shape checks written as [[ ${KEY:-} ... ]]
while IFS= read -r k; do
  [[ -n $k ]] && VAL[$k]=number
done < <(awk '/^for _kv in /, /; do[[:space:]]*$/' "$SCRIPT" | grep -oE '[A-Z][A-Z0-9_]*=[0-9]+' | cut -d= -f1)
re='^\[\[ \$\{([A-Z][A-Z0-9_]*):-\}[[:space:]]+(=~|==) (.*) \]\]'
while IFS= read -r line; do
  if [[ $line =~ $re ]]; then
    k=${BASH_REMATCH[1]}
    [[ -n ${VAL[$k]:-} ]] && continue
    if [[ ${BASH_REMATCH[2]} == '=~' ]]; then
      if [[ ${BASH_REMATCH[3]} == *'[0-5][0-9]'* ]]; then VAL[$k]=hhmm; else VAL[$k]=shape; fi
    elif [[ ${BASH_REMATCH[3]} == '/*' ]]; then
      VAL[$k]=path
    fi
  fi
done < <(grep '^\[\[ [$]{[A-Z]' "$SCRIPT")
# enum checks written as `case ${KEY:-} in a|b|c) ;; *) KEY=default ;; esac`
re_case='^case \$\{([A-Z][A-Z0-9_]*):-\} in ([a-z|]+)\)'
while IFS= read -r line; do
  if [[ $line =~ $re_case ]]; then
    k=${BASH_REMATCH[1]}
    [[ -n ${VAL[$k]:-} ]] || VAL[$k]="enum:${BASH_REMATCH[2]//|/ / }"
  fi
done < <(grep '^case [$]{[A-Z]' "$SCRIPT")

# 4. where used: function bodies (and top-level code after the readonly seal — the
#    seal statement itself spans several backslash-continued lines; skip all of them)
seal=$(awk '/^readonly VERSION/ { on = 1 } on { if ($0 !~ /\\$/) { print NR; exit } }' "$SCRIPT")
[[ $seal =~ ^[0-9]+$ ]] || seal=0
knoblist=$(IFS=' '; printf '%s' "${KNOBS[*]}")
while IFS=$'\t' read -r k where; do
  [[ -n $k ]] && USED[$k]=$where
done < <(awk -v knobs="$knoblist" -v seal="$seal" '
  BEGIN { n = split(knobs, a, " "); for (i = 1; i <= n; i++) want[a[i]] = 1; fn = "" }
  function scan(l, where,   i, m, t) {
    sub(/(^|[[:space:]])#.*$/, "", l)          # drop comments (not the 10# base marker)
    m = split(l, t, /[^A-Za-z0-9_]+/)
    for (i = 1; i <= m; i++) if (t[i] in want) {
      if (!((t[i], where) in seen)) {
        seen[t[i], where] = 1
        out[t[i]] = (t[i] in out) ? out[t[i]] ", " where : where
      }
    }
  }
  /^[a-z_][a-z0-9_]*\(\)[[:space:]]*\{/ {
    name = $0; sub(/\(\).*/, "", name)
    if ($0 ~ /\}[[:space:]]*$/) { scan($0, name); next }   # one-line function
    fn = name; scan($0, name); next
  }
  /^\}/ { fn = ""; next }
  { if (fn != "") scan($0, fn); else if (NR > seal) scan($0, "(top level)") }
  END { for (k in out) print k "\t" out[k] }' "$SCRIPT")

# 5. render
if [[ $LANG_OUT == ar ]]; then
  hdr='| المفتاح | الافتراضي في awacs.sh | الافتراضي في awacs.conf.example | يُفحص؟ | يُستخدم في |'
  t_number='نعم: رقم' t_hhmm='نعم: HH:MM' t_path='نعم: مسار مطلق' t_shape='نعم: صيغة' t_no='لا' t_enum='نعم: أحد'
  t_top='(المستوى الأعلى)' t_dash='—' t_examples='أمثلة معلّقة' t_empty='(فارغ)'
  t_foot='المصدر: tools/gen-config-table.sh قرأ awacs.sh (%s سطراً، sha256 %s…) وawacs.conf.example.'
else
  hdr='| Knob | Default in awacs.sh | Default in awacs.conf.example | Validated | Used in |'
  t_number='yes: number' t_hhmm='yes: HH:MM' t_path='yes: absolute path' t_shape='yes: shape' t_no='no' t_enum='yes: one of'
  t_top='(top level)' t_dash='—' t_examples='commented examples' t_empty='(empty)'
  t_foot='Source: tools/gen-config-table.sh read awacs.sh (%s lines, sha256 %s…) and awacs.conf.example.'
fi
cell() {  # CELL = value for the table: backticks around real values, words for the rest
  case ${1:-} in
    '')          CELL=$t_dash ;;
    '(empty)')   CELL=$t_empty ;;
    '(examples)') CELL=$t_examples ;;
    *)           CELL="\`${1//|/\\|}\`" ;;
  esac
}
table="$hdr"$'\n''| --- | --- | --- | --- | --- |'
for k in "${KNOBS[@]}"; do
  cell "${SDEF[$k]:-}"; s=$CELL
  cell "${EDEF[$k]:-}"; e=$CELL
  case ${VAL[$k]:-no} in
    number) v=$t_number ;; hhmm) v=$t_hhmm ;; path) v=$t_path ;; shape) v=$t_shape ;;
    enum:*) v="$t_enum ${VAL[$k]#enum:}" ;; *) v=$t_no ;;
  esac
  [[ -n ${SDEF[$k]:-} ]] || v=$t_dash          # nothing to validate in this build
  u=${USED[$k]:-}
  if [[ -n $u ]]; then u=${u//(top level)/$t_top}; u="\`${u//, /\`, \`}\`"; else u=$t_dash; fi
  table+=$'\n'"| \`$k\` | $s | $e | $v | $u |"
done
lines=$(wc -l <"$SCRIPT" | tr -d ' ')
sum=$(sha256sum "$SCRIPT" 2>/dev/null | cut -c1-12)
# shellcheck disable=SC2059  # t_foot is one of two fixed strings defined above
printf -v foot "$t_foot" "$lines" "${sum:-?}"
table+=$'\n\n'"_${foot}_"

if [[ -z $DOC ]]; then
  printf '%s\n' "$table"
  exit 0
fi
[[ -r $DOC ]] || { echo "gen-config-table: cannot read doc: $DOC" >&2; exit 1; }
if ! grep -q 'BEGIN GENERATED TABLE' "$DOC" || ! grep -q 'END GENERATED TABLE' "$DOC"; then
  echo "gen-config-table: $DOC lacks the BEGIN/END GENERATED TABLE markers" >&2; exit 1
fi
tmp=$(mktemp "$(dirname "$DOC")/.config-reference.XXXXXX") || exit 1
{
  sed -n '1,/BEGIN GENERATED TABLE/p' "$DOC"
  printf '%s\n' "$table"
  sed -n '/END GENERATED TABLE/,$p' "$DOC"
} >"$tmp"
# never swap in a half-built page: both markers must have survived the assembly
if grep -q 'BEGIN GENERATED TABLE' "$tmp" && grep -q 'END GENERATED TABLE' "$tmp"; then
  cat "$tmp" >"$DOC" && rm -f "$tmp"
  echo "gen-config-table: wrote ${#KNOBS[@]} rows into $DOC"
else
  rm -f "$tmp"
  echo "gen-config-table: assembly of $DOC lost a marker - file left untouched" >&2
  exit 1
fi
