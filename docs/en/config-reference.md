# Configuration reference

AWACS reads one settings file: `/etc/awacs.conf`. This page lists every knob, its default in the script and in the shipped `awacs.conf.example`, whether the script validates it, and which functions read it. The table is generated from the code by `tools/gen-config-table.sh`. Do not edit the table by hand.

## How the file is loaded

- Path: `/etc/awacs.conf`. The environment variable `AWACS_CONF` points the script at another file (used by tests).
- The file is read only when the script runs as root. The rootless words `awacs.sh check` and `awacs.sh help` run on the built-in defaults.
- The file must be owned by root and carry no permission bits for group or others (`chmod 600`). Otherwise the script ignores it and prints one of these lines on stderr:
  - `awacs: IGNORING /etc/awacs.conf (not owned by root — chown root: it)`
  - `awacs: IGNORING /etc/awacs.conf (group/world can access it — chmod 600 it)`
- The file is sourced by bash, so it must contain plain `KEY=value` assignments and `SAFETY_NET["name"]="password"` entries only. A `readonly` or `declare` line there stops the validation below from repairing a bad value.
- After loading, every knob is sealed `readonly`. Nothing changes it at run time except the day/night copies described below.

## Validation

- Numeric knobs must match `^0*[1-9][0-9]{0,6}$`: a whole number from 1 to 9999999. Leading zeros are accepted and normalised (`08` becomes `8`). Zero, an empty value, a negative number or text falls back to the default. The reason is safety: a bad number inside bash arithmetic would crash the daemon into a respawn loop, and a zero `TICK` would spin the loop.
- `NIGHT_START` and `NIGHT_END` must be `H:MM` or `HH:MM` between `00:00` and `23:59`; otherwise `22:00` and `06:00` are used.
- `RUN_DIR` must start with `/`; otherwise `/run/awacs` is used. The lock file, scan cache, spool, temporary-profile marker and probe file all live under it, so an override moves all of them together.
- String knobs (`OPEN_NETWORKS`, `NIGHT_MODE`, `STEALTH_MODE`, `DEBUG`) are compared with the word `yes`. Any other value means off.

## Day and night

`MIN_UP_KBPS`, `SWITCH_GAIN_PCT` and `DANCE_COOLDOWN` are copied into `CUR_MIN_UP`, `CUR_GAIN` and `CUR_COOLDOWN` when the script starts. Inside the night window `apply_profile` replaces them with `NIGHT_MIN_UP_KBPS`, `NIGHT_GAIN_PCT` and `NIGHT_DANCE_COOLDOWN`, and puts the day values back in the morning. The decision code (`main`, `best_by_upload`) reads only the `CUR_*` copies. That is why the table lists the six knobs under `apply_profile` and `(top level)` rather than under the functions that act on them.

## Reporting knobs (public edition)

These knobs decide where the device reports. They are documented against the public-edition interface; a dash in the script columns of the table means the `awacs.sh` the table was generated from did not carry the knob yet. Regenerate after updating the script.

| Knob | Meaning |
| --- | --- |
| `SITE_URL` | Base URL of a reporting site. The script talks to `${SITE_URL}/${DEVICE_ID}/device_api.php`. Empty = local-only operation. |
| `LOG_TARGET` | `local`, `both` or `remote`. `both` and `remote` need `SITE_URL`. `remote` keeps only WARN and ERROR lines in the local file. |
| `PROBE_URL` | Target of the upload-speed probe (a POST body). Empty with `SITE_URL` set = the site's `device_api.php`. Empty without `SITE_URL` = no upload probes; networks are chosen by signal order ("signal mode"). |
| `REPORT_WIFI` | Publish the WiFi cell `kbps,visible,total,band,SSID` to the site as `tmp/wifi.tmp`. `auto` = on when `SITE_URL` is set. |
| `DEVICE_ID` | Not a conf knob. Read from the daemon's environment (`export DEVICE_ID=` in rc.local, or `Environment=` in a systemd unit). Letters, digits, `_` and `-`, 1 to 32 characters; anything else falls back to `cam1`. |

## Environment variables the script reads

| Variable | Effect |
| --- | --- |
| `DEVICE_ID` | Device identifier (see above). If unset, the first non-blank line of `/tmp/device_id` is tried, then `cam1`. |
| `AWACS_CONF` | Path of the settings file (default `/etc/awacs.conf`). |
| `AWACS_IF` | WiFi interface. Default: the first connected interface, else the first one that is up, else the first present, else `wlan0`. |
| `AWACS_DEBUG` | Default for `DEBUG` when the conf does not set it (`yes` when absent). |
| `AWACS_TEST_KBPS`, `AWACS_TEST_SCAN` | Test hooks: a fixed upload number instead of a probe; reuse of the scan cache instead of a radio scan. Not for production. |

## The knob table

Column meaning:

- **Default in awacs.sh** — the value assigned in the configuration block at the top of the script.
- **Default in awacs.conf.example** — the value on the first `# KEY=` line of the example. A line left commented out keeps that default.
- **Validated** — `yes: number` means the knob is in the script's numeric check loop; `yes: HH:MM` and `yes: absolute path` are the two shape checks; `no` means the value is taken as written.
- **Used in** — the functions whose bodies mention the knob, in order of first appearance. `(top level)` is code outside any function that runs after the knobs are sealed.

<!-- BEGIN GENERATED TABLE -->
| Knob | Default in awacs.sh | Default in awacs.conf.example | Validated | Used in |
| --- | --- | --- | --- | --- |
| `TICK` | `10` | `10` | yes: number | `main` |
| `NET_FAIL_TICKS` | `3` | `3` | yes: number | `main` |
| `ASSOC_WAIT` | `25` | `25` | yes: number | `nm_wait_settled`, `be_activate`, `wait_ip` |
| `PROBE_KB` | `200` | `200` | yes: number | `up_kbps`, `up_kbps_wget`, `cli` |
| `MIN_UP_KBPS` | `400` | `400` | yes: number | `(top level)`, `apply_profile` |
| `UP_STRIKES` | `3` | `3` | yes: number | `main` |
| `SWITCH_GAIN_PCT` | `150` | `150` | yes: number | `(top level)`, `apply_profile` |
| `DANCE_COOLDOWN` | `1200` | `1200` | yes: number | `(top level)`, `apply_profile` |
| `PREF_CHECK` | `600` | `600` | yes: number | `main` |
| `REBOOT_AFTER_MIN` | `30` | `30` | yes: number | `fight` |
| `OPEN_NETWORKS` | `"yes"` | `"yes"` | no | `try_open` |
| `SITE_URL` | `""` | `""` | yes: shape | `site`, `remote_on`, `probe_url`, `probe_on`, `have_net`, `report_wifi`, `main`, `cli` |
| `LOG_TARGET` | `"local"` | `"local"` | yes: one of local / both / remote | `remote_on`, `site_log`, `main` |
| `PROBE_URL` | `""` | `""` | yes: shape | `probe_url`, `probe_on`, `cli` |
| `REPORT_WIFI` | `"auto"` | `"auto"` | yes: one of auto / yes / no | `report_wifi`, `main` |
| `SITE_TZ` | `""` | `""` | yes: shape | `stamp` |
| `SAFETY_NET` | (empty) | commented examples | no | `try_safety` |
| `NIGHT_MODE` | `"yes"` | `"yes"` | no | `apply_profile` |
| `NIGHT_START` | `"22:00"` | `"22:00"` | yes: HH:MM | `apply_profile` |
| `NIGHT_END` | `"06:00"` | `"06:00"` | yes: HH:MM | `apply_profile` |
| `NIGHT_MIN_UP_KBPS` | `200` | `200` | yes: number | `apply_profile` |
| `NIGHT_GAIN_PCT` | `300` | `300` | yes: number | `apply_profile` |
| `NIGHT_DANCE_COOLDOWN` | `2400` | `2400` | yes: number | `apply_profile` |
| `STEALTH_MODE` | `"no"` | `"no"` | no | `enable_stealth` |
| `DEBUG` | `"${AWACS_DEBUG:-yes}"` | `"yes"` | no | `dbg` |
| `LOG_FILE` | `/var/log/awacs.log` | `/var/log/awacs.log` | no | `log` |
| `LOG_CAP` | `1500` | `1500` | yes: number | `log` |
| `RUN_DIR` | `/run/awacs` | `/run/awacs` | yes: absolute path | `install_tools`, `(top level)` |
| `SCAN_TTL` | `30` | `30` | yes: number | `scan`, `cli` |
| `SPOOL_CAP` | `60` | `60` | yes: number | `site_log`, `flush_spool` |
| `STREAM_MIN_KBPS` | `50` | `50` | yes: number | `main` |

_Source: tools/gen-config-table.sh read awacs.sh (2046 lines, sha256 859525312b2b…) and awacs.conf.example._
<!-- END GENERATED TABLE -->

## Regenerating the table

```sh
tools/gen-config-table.sh --write docs/en/config-reference.md
tools/gen-config-table.sh --lang ar --write docs/ar/config-reference.md
```

Run both after any change to `awacs.sh` or `awacs.conf.example`. The generator reads the script's configuration block, its numeric check loop, its shape checks and its function bodies; it needs only bash, awk, grep, sed and sha256sum. Pass `--script` and `--example` to point it at files outside the repository root.
