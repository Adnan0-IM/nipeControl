# `nipe-widget-py` — Full Walkthrough

Path: `plugins/nipeControl/nipe-widget-py` (566 lines, Python 3, `chmod +x`).
Installed as `~/.local/bin/nipe-widget-py` — a symlink to the file in the plugin
directory, so the repo stays the single source of truth.

It drives [nipe](https://github.com/htbridge/nipe), a Perl Tor gateway, and prints
machine-readable JSON that the DankMaterialShell panel widget (`NipeControl.qml`)
consumes. Elevated actions go through **polkit** (`pkexec`), so the user gets a
graphical auth prompt and **no sudoers rule is needed**.

---

## 0. The one idea worth knowing first

**Reading the status never needs root.** `nipe.pl` refuses to run *any* subcommand
as a non-root user (`nipe.pl:21-23`), which is why the previous version of this
helper ran `pkexec sh -c "… nipe.pl status"` on every poll — a polkit dialog every
10-15 seconds.

But the only thing `nipe.pl status` does is ask the Tor Project check endpoint
whether the current connection is a Tor circuit (`lib/Nipe/Component/Utils/Status.pm`):

```perl
my $api_check = 'https://check.torproject.org/api/ip';
my $request  = HTTP::Tiny -> new -> get($api_check);
```

Nothing privileged at all. So this helper asks the same endpoint itself, over the
local SOCKS port (`probe_tor`, 341-368). `pkexec` is now reserved for the four
subcommands that genuinely need root: `start`, `stop`, `restart`, and `status`
when a human runs it for debugging.

---

## 1. Command surface (496-562)

| Command | Elevates | Output |
|---|---|---|
| `json-status [--api URL] [--nipe-dir DIR] [--socks-port N] [--check-url URL]` | no | one JSON object on stdout, always |
| `start` / `stop` / `restart` | **polkit** | `{"action":…,"ok":bool,"message":str}`, exit 1 on failure |
| `status` | **polkit** | raw nipe output as text |
| `check-deps` | no | `OK` or `MISSING:…`, plus an `optional not found: …` line |
| `path` | no | the resolved Nipe directory, or `not_found` |

`json-status` also accepts a bare positional URL for backwards compatibility with
the previous CLI (`json-status https://ipapi.co`).

**Invariant:** `json-status` always prints a parseable JSON object, even when it
explodes — the `except` at 554-557 turns any unexpected exception into
`{"error": "…"}`. The widget can therefore treat empty or unparseable stdout as a
crash of the helper itself, which is exactly how it is treated in `NipeControl.qml`.

---

## 2. Module map

| Lines | What |
|---|---|
| 1-28 | shebang + module docstring (the design contract) |
| 30-40 | imports — all used |
| 42-74 | constants: paths, TTLs, search paths, dependency lists |
| 77-105 | data dir creation + logging setup |
| 108-144 | small helpers: `_truthy`, JSON file read/write, `_clean_output` |
| 147-155 | `NipeConfig` |
| 158-173 | `NipeStatus` + `to_json` |
| 176-182 | `NipeWidgetPy.__init__` |
| 188-238 | configuration overlay + Nipe directory resolution |
| 244-288 | dependency check (cached) + Perl module probe |
| 294-339 | `_curl_json` — every network call in the file |
| 341-368 | `probe_tor` — the unprivileged status read |
| 370-406 | `geolocate` — ipinfo.io-style lookup, cached per IP |
| 408-434 | `get_json_status` — assembles the widget's payload |
| 440-489 | `run_nipe_cmd` — the only place root is requested |
| 492-566 | `_emit` + `main` (argparse) |

---

## 3. Logging setup (77-105)

`_ensure_data_dir()` runs at **import time** and the `FileHandler` is attached
only if that succeeded, with its own `try/except OSError`. The previous version
opened `~/.local/share/nipeControl/nipe-widget-py.log` unconditionally from
`logging.basicConfig` while `main()` created the directory fifty lines later — a
fresh install died on import. Now the failure mode is "no log file", never a crash.

Handlers: `FileHandler` (if available) + `StreamHandler(sys.stderr)`. stderr is
deliberate: the widget captures the process's stderr and surfaces it when stdout
is empty, so a traceback is not invisible.

---

## 4. Data models

### `NipeConfig` (147-155)
| Field | Default | Meaning |
|---|---|---|
| `nipe_dir` | `""` | explicit path; empty means auto-detect |
| `ip_info_api` | `https://ipinfo.io` | geolocation base URL |
| `tor_check_url` | `https://check.torproject.org/api/ip` | the Tor Project check endpoint |
| `tor_socks_port` | `9050` | local Tor SOCKS port |
| `config_file` | `~/.config/nipeControl/config` | `KEY=VALUE` config file |

### `NipeStatus` (158-173) — the widget contract
| Field | Default | Meaning |
|---|---|---|
| `active` | `False` | a Tor circuit carries the traffic |
| `ip` | `""` | exit IP; **empty when inactive** so the panel never retains the real IP |
| `error` | `None` | `None` → JSON `null`; otherwise a plain message |
| `nipe_dir` | `""` | resolved checkout, `""` when not found |
| `country`, `country_code`, `city`, `region` | `""` | exit node geolocation |
| `source` | `""` | how the state was determined |

`to_json` (172-173) is `json.dumps(asdict(self), indent=2)`. Because `error` is
`Optional[str]` and `asdict` is used, the emitted JSON is a real `null`:

```json
{ "active": false, "ip": "", "error": null, "nipe_dir": "/home/u/nipe", … }
```

The previous version stored errors as `'"Missing dependencies: …"'` (quotes baked
into the string) and defaulted `error` to the four-character string `"null"`. The
widget's `parsed.error || ""` therefore saw a truthy value on every single run,
which is why the panel used to sit permanently in its error state.

---

## 5. Configuration (188-238)

`__init__` (179-182) applies the config file **first**, then resolves the Nipe
directory. The old code did the opposite, so `NIPE_DIR` from the file was only
honoured when it happened to coincide with a hard-coded search path.

`_apply_config_file` (188-219) is a minimal reader: skip blanks and `#` comments,
split on the first `=`, strip surrounding quotes. A key is only applied when the
current value is still the dataclass default, which is what makes the precedence
**command line → config file → default** work without any explicit "was it set?"
flag. `TOR_SOCKS_PORT` is coerced to `int` and a bad value is logged and ignored
rather than crashing.

Recognised keys: `NIPE_DIR`, `IP_INFO_API`, `TOR_CHECK_URL`, `TOR_SOCKS_PORT`.

`_find_nipe_dir` (221-235): if the user named a directory, it is used *or* the
result is `""` — there is no fallback to another checkout. Silently controlling a
different install than the one the user pointed at is worse than telling them it
is missing, and the widget renders `nipe_dir == ""` as a red "Nipe Directory Not
Found" in its footer. Only when nothing is explicit does it scan
`NIPE_SEARCH_PATHS` (57-63).

---

## 6. Dependency check (244-288)

Returns `(missing, optional_missing)`.

- **Required:** `perl`, `curl`, and the Perl modules nipe.pl loads
  (`Config::Simple`, `JSON`, `Readonly`, `Try::Tiny`, `IO::Socket::SSL`,
  `Net::SSLeay`) — 65-73.
- **Optional:** `pkexec`, `notify-send`, `wl-copy`, `xclip`, `dms` (74). These
  never block anything; they are reported so a human can see why a button or a
  notification did nothing. `jq` is gone: nothing in the helper ever used it, and
  the old version failed a status read over a tool it did not call.

`_perl_modules_ok` (275-288) builds one `perl -e 'use A (); use B (); … 1;'` and
runs it **once** instead of starting an interpreter per module. Only if that fails
does it re-probe module by module, so a healthy system pays one spawn and a broken
one still gets a precise list.

The verdict is cached in `~/.local/share/nipeControl/deps.json` for 24 h
(`DEP_CACHE_TTL`, 51). The answer only changes when the user installs something.

`get_json_status` (412-416) calls it but only lets `curl` block, because that is
the only dependency the status path uses. `run_nipe_cmd` (447-449) uses the full
list, so a missing Perl module is reported *before* the user is asked for a
password.

---

## 7. `probe_tor` — the unprivileged status read (341-368)

```python
data, socks_error = self._curl_json(url, socks_host="127.0.0.1:9050")
if data is not None:
    if _truthy(data.get("IsTor")):
        return True, str(data.get("IP") or ""), None
    return False, "", None

data, direct_error = self._curl_json(url)
if data is not None:
    return False, "", None          # reachable, and it cannot be a Tor circuit
return False, "", "Tor check endpoint unreachable (…)"
```

The reasoning that makes this safe: a SOCKS answer is **authoritative**. If the
local Tor instance answers at all, Tor is running, and `IsTor`/`IP` describe the
exit node. The direct fallback can never report a Tor circuit, so a reachable
endpoint on that path means "Tor is down". Both paths failing means the network
itself is unreachable, which is the one case worth an error message — a wrong
answer would be worse than an honest "I don't know".

`_curl_json` (294-339) is the only network code in the file: `curl -sS --fail
--max-time N` with an optional `--socks5-hostname`, a 5-second curl budget, a
`max_time + 5` subprocess timeout, and a `(data, error)` return instead of
raising. The URL is passed as a list element, never through a shell.

---

## 8. `geolocate` (370-406)

`{api}/{ip}/json`, i.e. the ipinfo.io shape — the same shape the plugin setting
documents. A bare positional/`--api` override now genuinely takes effect; in the
previous version the argument was threaded into `_parse_status_output`, which
ignored it, so the setting was a no-op.

`country` is the two-letter code. `country_name`/`name` are used when an API
supplies them and otherwise the code is repeated in `country`; the widget
(`locationLabel()`) prefers city and region, which ipinfo.io *does* return, and
falls back to the name.

Caching, in `~/.local/share/nipeControl/geo.json`:
- a hit younger than 6 h returns immediately (an entry per IP — Tor circuits do
  churn, but a stable circuit stops the requests entirely);
- a **negative** entry blocks retries for 15 min, so a blocked or rate-limited
  endpoint is not hammered every 10 seconds;
- the file is capped at 128 entries, oldest-inserted dropped first.

---

## 9. `run_nipe_cmd` — the privilege boundary (440-489)

Guards, in order: no Nipe directory → clear message; missing dependencies →
clear message, *before* any prompt; no `perl`; no `pkexec`.

```sh
cd <quoted nipe_dir> && <quoted perl> <quoted nipe.pl> <quoted action>
```

run as `[pkexec, "sh", "-c", inner]`. The `cd` is essential: `pkexec` resets the
working directory and `nipe.pl:6` does `use lib './lib/'`, so without it the
elevated run dies with a "Can't locate …/lib/…" error. All three interpolated
values go through `shlex.quote()`.

Timeout is 180 s, generous because `start`/`stop` reconfigure the firewall and
restart Tor.

Result mapping:
- `returncode == 0` → `(True, stdout)`;
- `126`/`127` or `"not authorized"` in stderr → "Authorization was cancelled.
  The polkit dialog was dismissed." (that is exactly what pkexec returns when the
  user closes the dialog);
- anything else → `(False, cleaned stderr or stdout)`.

Note that `nipe.pl` catches its own exceptions and still exits 0, printing
`[!] ERROR: this command could not be run.` — the widget therefore treats an
`[!]` marker in the output as a failure even on exit code 0
(`NipeControl.qml`, `evaluateResult`).

---

## 10. CLI (496-562)

`argparse` with a required subcommand. Overrides are applied to a `NipeConfig`
built from the defaults, then handed to the class, which overlays the config file
on top. The whole dispatch is wrapped in one `try/except` that returns a non-zero
exit code and still prints JSON for `json-status`.

---

## 11. Data flow

```
nipe-widget-py json-status
   ├─ NipeConfig (CLI)  ──▶ _apply_config_file  ──▶ _find_nipe_dir
   ├─ check_dependencies()        (cached 24 h; only curl can block)
   ├─ probe_tor()                 curl --socks5-hostname 127.0.0.1:9050 …/api/ip
   │     ├─ answered + IsTor      → active, exit IP
   │     └─ silent                → one direct request decides "down" vs "no network"
   ├─ geolocate(ip)               cached 6 h per IP
   └─ NipeStatus.to_json()  ──▶ stdout ──▶ NipeControl.qml

nipe-widget-py start | stop | restart
   └─ check_dependencies() ──▶ pkexec sh -c "cd … && perl nipe.pl <action>"   ← polkit
```

---

## 12. Files and environment it touches

| Path | Role |
|---|---|
| `~/.config/nipeControl/config` | reads `NIPE_DIR`, `IP_INFO_API`, `TOR_CHECK_URL`, `TOR_SOCKS_PORT` |
| `~/.local/share/nipeControl/` | created at import; holds the log, `deps.json`, `geo.json` |
| `~/.local/share/nipeControl/nipe-widget-py.log` | INFO and up |
| `<nipe_dir>/nipe.pl` | executed as root, only for start/stop/restart/status |
| `pkexec` → polkit | the privilege boundary |
| network | `check.torproject.org` (every poll), `<ip_info_api>` (cached) |

Nothing is written outside `~/.local/share/nipeControl` and the two config paths.

---

## 13. Runtime characteristics

A background poll is one `curl` (or two, only when SOCKS is silent and the direct
fallback runs) plus one `curl` for geolocation on a cache miss. No interpreter
start, no polkit dialog, no firewall work. A cached read is ~0.1 s. A control
action is one polkit dialog plus nipe.pl's own work.

---

## 14. Design decisions and why

- **Split read from write.** The only reason the old widget prompted constantly was
  reusing the privileged path for a read. Nothing else justifies it.
- **`error` is `None` or a message.** It is the field the widget branches on, so it
  has to be a real nullable value; stringly-typed sentinels are how the permanent
  error state happened.
- **stdout is the contract, stderr is diagnostics.** The widget can rely on stdout
  being one JSON object, and can fall back to stderr when it is not.
- **Caches are per-IP and per-tool, with TTLs and a negative backoff.** Tor exits
  and third-party rate limits are the two things that make naive polling expensive;
  both are handled without configuration.
- **Deleted:** the no-op `daemon` (`while True: sleep(60)`), `send_notification`
  and `copy_ip_to_clipboard` (the QML does both, and the Python clipboard helper
  used `shell=True` with an interpolated IP), the `DependencyStatus` dataclass, the
  never-populated `exit_ip`/`exit_country*` fields, and the `shell=True` copy path.

---

## 15. Known limitations (deliberate)

1. **No leak detection.** Removed from the UI in an earlier commit; the docstring
   used to claim it. The status answer is about the Tor circuit, not about whether
   DNS/WebRTC leak. `probe_tor` has the direct request in hand if that is ever
   wanted again.
2. **No REST API / daemon.** The "API" is the `json-status` stdout contract. The
   QML owns the timer; a daemon would only add a second source of truth.
3. **The poll trusts `check.torproject.org`.** If the endpoint is blocked, the
   widget reports an error rather than guessing. nipe.pl's own `status` has the
   same dependency.
4. **The status read cannot see firewall state.** If Tor runs but nipe's iptables
   rules are gone, the SOCKS probe still says "active" while traffic leaks. Reading
   the rules needs root, which is exactly what the old design paid for on every
   poll.
5. **Country name needs a different provider.** ipinfo.io returns only the code.
6. **The helper must live at `~/.local/bin/nipe-widget-py`.** It is a symlink into
   the plugin directory here; on another machine either copy it or re-create the
   symlink.

---

## 16. Verifying a change

```bash
nipe-widget-py check-deps            # OK / MISSING:…, plus optional tools
nipe-widget-py path                  # resolved Nipe checkout
nipe-widget-py json-status           # one JSON object, error: null
nipe-widget-py json-status --api http://127.0.0.1:18081 --socks-port 19050 \
                           --check-url http://127.0.0.1:18081/api/ip
```

The last form is how the "Tor is up" branch gets exercised without touching the
real network: point a SOCKS5 proxy at a local HTTP server that returns
`{"IsTor": true, "IP": "1.2.3.3"}` and an ipinfo-shaped document for
`/1.2.3.3/json`. A helper with no data directory still works — the log file and
both caches are optional, and the status read never touches them on a warm cache.
