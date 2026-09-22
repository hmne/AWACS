# Contributing

## Rules that are not negotiable

AWACS never edits the stored network configuration of the system. A change is rejected if it adds any of:

- `wpa_cli save_config`, `disable_network`, or `remove_network` on anything but the daemon's own temporary id, or a write to `/etc/wpa_supplicant/wpa_supplicant.conf`;
- `nmcli connection modify`, `nmcli device wifi connect`, or `connection delete`/`down` on anything not named `awacs-crutch-*` or `awacs-safety-*` and located under `/run/NetworkManager/system-connections/`, or a write under `/etc/NetworkManager/`;
- `ip link set ... down/up` or a `dhcpcd` restart on the NetworkManager backend.

Every exit path of a recovery (win, loss, shutdown) must keep `enable_all`. A dead daemon may never leave the device worse off than a device without it.

A reboot may be triggered only by evidence that the fault is on the device. An ISP outage, a wrong password, or a NetworkManager that is still trying must never lead to a reboot.

## Bash rules

- `shellcheck -x` with zero findings, and `bash -n`. CI (`.github/workflows/shellcheck.yml`) runs both on every `*.sh`, rejects CRLF line endings, checks that `install.sh --selftest` passes (every wizard string exists in both languages), that `install.sh --print-unit` equals `systemd/awacs.service`, and that both receivers parse.
- Google Shell Style Guide: two-space indent, `local` for function variables, quote everything.
- `set -uo pipefail` as the script does; no `set -e` (a failing probe is data, not a crash).
- LF line endings.
- No new dependencies beyond stock Raspberry Pi OS and Debian. `mawk` is the default awk there: `[[:space:]]`, never `\s`.
- Credentials never in argv.
- Nothing may block the main loop on the network: every `curl` has `--max-time`, every long-running tool runs under `timeout`.

## Before changing a decision path

Trace it: which variables it reads, who sets them, and which exit paths clear them. The comments in the script name the case each guard exists for; do not remove them.

## Testing a change

Test on both backends: an image with dhcpcd and wpa_supplicant, and a NetworkManager image. For a change to recovery, outage classification, the reboot condition, the spool or any `nmcli` or `wpa_cli` call, attach log excerpts from both, and show `md5sum /etc/wpa_supplicant/wpa_supplicant.conf` or `ls -l /etc/NetworkManager/system-connections` before and after the run: nothing may change.

The environment variables `AWACS_CONF`, `AWACS_IF`, `AWACS_TEST_KBPS` (a fixed upload number instead of a probe) and `AWACS_TEST_SCAN` (reuse of the scan cache instead of a radio scan) allow a first pass of a decision-only change on a machine without a radio.

## Documentation

Every statement in `README.md` and `docs/` must be true of the code. If you change behaviour, change the page that describes it, in both languages. Style: plain short sentences, no marketing adjectives, no emoji.

## Pull requests

- One change per pull request.
- Describe how you verified the change: backend, commands run, relevant log lines.
- Keep the changelog entry factual.
