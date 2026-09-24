# Nipe Control Plugin for DankMaterialShell

**Nipe Control** integrates [Nipe](https://github.com/htbridge/nipe) with DankMaterialShell. It lets you start/stop/restart the Tor gateway, show your exit IP and country, and get desktop notifications — all from the shell bar widget.

---

## Features

- **Live widget**: Real-time status, external IP, exit country.
- **Controls**: Start / Stop / Restart with one click.
- **Copy IP** to clipboard (`wl-copy` / `xclip`).
- **Notifications**: Desktop alerts on status changes.
- **Python helper** (`nipe-widget-py`): No bash script, no sudoers file needed — uses `pkexec` to show a desktop auth popup.

---

## Requirements

- Nipe (`~/nipe` or custom path)
- Perl 5.30+
- `tor`
- `curl`, `jq`
- `notify-send` (from `libnotify`)
- Clipboard tool (`wl-copy` or `xclip`)
- `pkexec` (polkit) — for the auth popup

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

```bash
mkdir -p ~/.local/bin
cp nipe-widget-py ~/.local/bin/
chmod +x ~/.local/bin/nipe-widget-py
```

The `NipeControl.qml` widget points to `~/.local/bin/nipe-widget-py`.

---

## Enable Plugin

1. Open DankMaterialShell settings (`Super` + `,`).
2. Go to **Plugins**, enable **Nipe Control**.
3. In settings, configure:
   - **Custom Nipe Directory** (if not `~/nipe`)
   - **Refresh Interval** (default `15` sec)
   - **Show Country**, **Notifications**, **Auto-start**, **IP API endpoint**

---

## Helper Usage (Python)

```bash
~/.local/bin/nipe-widget-py check-deps
~/.local/bin/nipe-widget-py json-status
~/.local/bin/nipe-widget-py start
~/.local/bin/nipe-widget-py status
~/.local/bin/nipe-widget-py path
```

Pass a custom API URL: `~/.local/bin/nipe-widget-py json-status https://api.example.com`

---

## Permissions Note

No `/etc/sudoers.d/nipe` required. The Python script tries direct execution; if root is needed, it runs through `pkexec`, which opens a graphical password dialog. You can enable **Auto-start on Login** — it will trigger the same auth popup when DMS starts.

---

## Troubleshooting

- **"Nipe directory not found"**: Set `NIPE_DIR=/path/to/nipe` in `~/.config/nipeControl/config` or use plugin settings.
- **"Root permissions required"**: `pkexec` should handle this. If it fails, make sure `polkit` is installed and your user can authorize.
- **Missing dependencies**: Run `~/.local/bin/nipe-widget-py check-deps` to see which Perl module or tool is missing.
- **No leak test**: The leak-test feature was removed per request.
- **Custom directory**: Specify in `NipeControlSettings.qml` or via `NIPE_DIR` config.

---

MIT License.
