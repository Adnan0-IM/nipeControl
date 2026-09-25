# Nipe Control Plugin for DankMaterialShell

**Nipe Control** integrates [Nipe](https://github.com/htbridge/nipe) with DankMaterialShell. It lets you start/stop/restart the Tor gateway, show your exit IP and country, and get desktop notifications — all from the shell bar widget.

---

## Features

- **Live widget**: Real-time status, external IP, exit city and country.
- **Controls**: Start / Stop / Restart with one click.
- **Copy IP** to clipboard (`wl-copy` / `xclip` / `dms`).
- **Notifications**: Desktop alerts on status changes.
- **Silent polling**: reading the status is unprivileged, so the refresh timer never interrupts you.
- **Python helper** (`nipe-widget-py`): no bash script and no sudoers file — `pkexec` shows a desktop auth popup for the actions that need root.

---

## Requirements

- Nipe (`~/nipe` or custom path)
- Perl 5.30+ with `Config::Simple`, `JSON`, `Readonly`, `Try::Tiny`, `IO::Socket::SSL`, `Net::SSLeay`
- `tor`
- `curl` — the status probe and the exit node lookup
- `pkexec` (polkit) — only for Start / Stop / Restart
- Optional: `notify-send` (from `libnotify`) for notifications, `wl-copy` / `xclip` / `dms` for the copy button

---

## Install Dependencies

### Arch / Manjaro
```bash
sudo pacman -S perl perl-config-simple perl-json perl-readonly perl-io-socket-ssl perl-net-ssleay tor wl-clipboard curl libnotify pkexec
```

### Debian / Ubuntu / Mint
```bash
sudo apt update
sudo apt install -y perl libconfig-simple-perl libjson-perl libreadonly-perl libio-socket-ssl-perl libnet-ssleay-perl tor wl-clipboard curl libnotify-bin policykit-1
```

### Fedora / RHEL
```bash
sudo dnf install perl perl-Config-Simple perl-JSON perl-Readonly perl-IO-Socket-SSL perl-Net-SSLeay tor wl-clipboard curl libnotify polkit
```

### CPAN (if packages missing)
```bash
sudo cpan install Config::Simple JSON Readonly IO::Socket::SSL Net::SSLeay Try::Tiny
```

---

## Install Nipe

```bash
git clone https://github.com/htbridge/nipe ~/nipe
cd ~/nipe
sudo perl nipe.pl install
```

> Nipe requires root to configure `iptables`. The Python helper uses `pkexec` to ask for it — no sudoers file needed.

---

## Install Plugin Helper

`NipeControl.qml` runs `$HOME/.local/bin/nipe-widget-py`. The canonical copy is
the `nipe-widget-py` file in this plugin directory, so link it and keep a single
source of truth:

```bash
mkdir -p ~/.local/bin
ln -s "$(pwd)/nipe-widget-py" ~/.local/bin/nipe-widget-py
```

Copying works too, if you would rather not depend on the plugin folder staying
put:

```bash
cp ./nipe-widget-py ~/.local/bin/ && chmod +x ~/.local/bin/nipe-widget-py
```

Verify before enabling the plugin:

```bash
~/.local/bin/nipe-widget-py json-status
```

A single JSON object means the helper is healthy. With Tor off it reports
`"active": false` and `"error": null`.

---

## Enable Plugin

1. Open DankMaterialShell settings (`Super` + `,`).
2. Go to **Plugins**, enable **Nipe Control**.
3. In settings, configure:
   - **Custom Nipe Directory** — if not `~/nipe`; takes precedence over `NIPE_DIR` and over auto-detection
   - **Refresh Interval** (default `15` sec, minimum `5` sec)
   - **Show Country**, **Notifications**, **Auto-start**, **IP API endpoint**

---

## Helper Usage (Python)

```
nipe-widget-py json-status [--api URL] [--nipe-dir DIR] [--socks-port N] [--check-url URL]
nipe-widget-py start | stop | restart | status [--nipe-dir DIR]
nipe-widget-py check-deps [--nipe-dir DIR]
nipe-widget-py path [--nipe-dir DIR]
```

```bash
~/.local/bin/nipe-widget-py json-status
~/.local/bin/nipe-widget-py json-status --api https://ipapi.co
~/.local/bin/nipe-widget-py path --nipe-dir /opt/nipe
~/.local/bin/nipe-widget-py check-deps
```

`json-status` never elevates. `start`, `stop`, `restart` and `status` run `nipe.pl` as
root through `pkexec` and print a single JSON result object.

`json-status` payload:

| Key | Meaning |
|---|---|
| `active` | whether a Tor circuit carries the traffic |
| `ip` | Tor exit IP, empty when inactive |
| `error` | `null`, or a plain message for the widget to render |
| `nipe_dir` | resolved Nipe checkout, empty when not found |
| `country`, `country_code`, `city`, `region` | exit node geolocation |
| `source` | how the state was determined |

Config file `~/.config/nipeControl/config` (all optional, `KEY=VALUE`):

```
NIPE_DIR=/home/user/nipe
IP_INFO_API=https://ipinfo.io
TOR_CHECK_URL=https://check.torproject.org/api/ip
TOR_SOCKS_PORT=9050
```

Precedence is command line, then this file, then the defaults.

---

## How Permissions Work

`nipe.pl` refuses to run as a non-root user, even for `status`, so anything that
shells out to it needs root. Only Start, Stop, Restart and the `status` debug
command do: those go through `pkexec`, which opens a graphical polkit dialog.
No `/etc/sudoers.d/nipe` is created or needed.

The widget's own status refresh does not use `nipe.pl` at all. `nipe.pl status`
only asks the Tor Project whether the connection is a Tor circuit, so the helper
asks the same endpoint directly through the local SOCKS port:

```bash
curl --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip
```

If the local Tor instance answers, the gateway is up and the reply carries the
exit IP. If SOCKS is silent, one direct request decides whether Tor is down or
the network itself is unreachable. Nothing here needs root, so the refresh timer
can run as often as you like without a single prompt.

**Auto-start on Login** raises the usual polkit dialog once, because it runs
`nipe.pl start`.

---

## Troubleshooting

- **"Nipe Directory Not Found" in the footer**: the helper could not find
  `nipe.pl`. Set the **Custom Nipe Directory** setting, or `NIPE_DIR=` in
  `~/.config/nipeControl/config`. An explicit path that turns out to be wrong is
  reported rather than silently replaced by another checkout.
- **"Tor check endpoint unreachable"**: neither the SOCKS nor the direct request
  worked, so the widget cannot tell whether Tor is up. Usually a broken network
  or a blocked `check.torproject.org`.
- **Widget stuck in an error state with no message**: the helper printed nothing
  on stdout. Run it by hand; the traceback is in
  `~/.local/share/nipeControl/nipe-widget-py.log`.
- **No polkit dialog on Start/Stop**: install `polkit` and make sure your session
  can ask for authentication.
- **Missing dependencies**: `~/.local/bin/nipe-widget-py check-deps` lists what
  is missing; the result is cached for a day. Optional tools are reported
  separately and do not affect the status read.
- **Country never appears**: the endpoint is blocked or rate-limited. The lookup
  is cached per IP for 6 hours and a failing endpoint is backed off for 15
  minutes. Point **IP API endpoint** at another provider if needed.
- **Logs**: `~/.local/share/nipeControl/nipe-widget-py.log`.

---

MIT License.
