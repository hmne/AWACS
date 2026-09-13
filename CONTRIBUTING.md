# Contributing

Thank you for looking at the code. A few rules keep it safe to run on other people's devices.

## The no-block law is not negotiable

AWACS never edits the owner's network configuration. Concretely, a change is rejected if it adds any of:

- `wpa_cli save_config`, `disable_network`, `remove_network` on anything but AWACS's own temporary id, or a write to `/etc/wpa_supplicant/wpa_supplicant.conf`;
- `nmcli connection modify`, `nmcli device wifi connect`, `connection delete`/`down` on anything not named `awacs-crutch-*`/`awacs-safety-*` and located under `/run/NetworkManager/system-connections/`, or a write under `/etc/NetworkManager/`;
- `ip link set … down/up` or a `dhcpcd` restart on the NetworkManager backend.

Every exit path of a fight (win, loss, shutdown) must keep `enable_all`. A dead AWACS may never leave the box worse than a box without AWACS.

The reboot valve may only be armed by the device's own wedge. An ISP outage, a wrong password, or NetworkManager still trying must never lead to a reboot.

## Bash rules

- `shellcheck -x` with zero findings, and `bash -n`. CI (`.github/workflows/shellcheck.yml`) runs both on every `*.sh`, rejects CRLF line endings, checks that `install.sh --selftest` passes (every wizard string exists in both languages), that `install.sh --print-unit` equals `systemd/awacs.service`, and that both receivers parse.
- Google Shell Style Guide. Two-space indent, `local` for function variables, quote everything.
- `set -uo pipefail` as the script does; no `set -e` (a failing probe is data, not a crash).
- LF line endings.
- No new dependencies beyond stock Raspberry Pi OS / Debian. `mawk` is the default awk there: `[[:space:]]`, never `\s`.
- Credentials never in argv.
- Nothing may block the main loop on the network: every `curl` has `--max-time`, every long tool runs under `timeout`.

## Trace, do not just read

Before changing a decision path, trace it: which variables it reads, who sets them, which exit paths clear them. Most past bugs were a flag set in a subshell, a clear that never ran, or a teardown that ran before a diagnosis. The comments in the script name the proven cases; do not remove them.

## The lab

A change to `fight`, `recover`, classification, the valve, the spool or any `nmcli`/`wpa_cli` call must be run through the lab (`lab/`, see [docs/en/testing.md](docs/en/testing.md)) on both profiles. Attach the `RESULT.txt` files and the argv logs to the pull request. The no-block checks (byte-identical owner files, clean argv) must pass in every scenario.

For decision-only changes, the sandbox hooks (`AWACS_TEST_KBPS`, `AWACS_TEST_SCAN`, `AWACS_CONF`, `AWACS_IF`) plus the shims under `lab/guest/` are enough for a first pass.

## Documentation

Every feature statement in `README.md` and `docs/` must be true of the code. If you change behaviour, change the page that describes it, in both languages. Style: plain, short sentences, no marketing adjectives, no emoji.

## Pull requests

- One change per pull request.
- Describe what was proven and how (lab scenario, argv log, log lines).
- Keep the changelog entry factual and dated.
