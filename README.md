# Nipe Control Plugin for DankMaterialShell

**Nipe Control** is a feature-rich, robust widget plugin for [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell). It provides seamless integration with [Nipe](https://github.com/htbridge/nipe)—an engine that makes the Tor network your default gateway—allowing you to start, stop, restart, and monitor your connection state, external IP address, country, and run leak tests directly from your shell bar.

---

## 🚀 Features

- **Live Bar Widget**: Displays real-time Nipe status, external IP address, and country code in your top bar.
- **Interactive Popout Dashboard**:
  - One-click **Start**, **Stop**, and **Restart** controls.
  - Live external IP display with a **Copy IP** button (supports `wl-copy` & `xclip`).
  - **Country detection**: Showing exit node location with flag/code.
  - **IP Leak Test** button to verify no IP leaks when Tor is active.
  - Connection status badge and active routing indicator.
  - Detailed error reporting (sudoers warnings, missing dependencies, unreadable status).
- **Status Change Notifications**: Desktop notifications when Nipe starts/stops.
- **Non-Blocking Helper Script**: `nipe-widget.sh` handles status queries in JSON without blocking the UI or hanging on sudo password prompts.
- **Integrated Settings**: Configurable Nipe installation path, auto-refresh intervals, country display, notifications, and IP API endpoint via DankMaterialShell plugin settings.
- **Loading Indicators**: Visual feedback during status checks and control operations.
- **Tooltips**: Hover the bar widget for detailed status info.

---

## 📋 Prerequisites & Dependencies

To use this plugin, you must have **Nipe** installed alongside its required Perl dependencies.

### 1. System Requirements & Core Packages

- **Nipe** (cloned engine repository)
- **Tor service** (`tor`)
- **Perl** (5.30 or newer)
- **Clipboard Utility** (Optional, for Copy IP feature): `wl-copy` (Wayland) or `xclip` (X11)
- **curl** (for IP/leak checks)
- **notify-send** (for desktop notifications, usually from `libnotify`)

### 2. Perl Dependencies

Nipe requires the following Perl modules:

- `perl-config-simple` (`Config::Simple`)
- `perl-json` (`JSON`)
- `perl-readonly` (`Readonly`)
- `perl-io-socket-ssl` (`IO::Socket::SSL`)
- `perl-net-ssleay` (`Net::SSLeay`)
- `Try::Tiny`
- `HTTP::Tiny`

---

## 🛠️ Installation Guide

### Step 1: Install Dependencies

Select the command corresponding to your Linux distribution:

#### **Arch Linux / Manjaro**

```bash
sudo pacman -S perl perl-config-simple perl-json perl-readonly perl-io-socket-ssl perl-net-ssleay tor wl-clipboard curl libnotify
```

#### **Debian / Ubuntu / Kali Linux / Linux Mint**

```bash
sudo apt update
sudo apt install -y perl libconfig-simple-perl libjson-perl libreadonly-perl libio-socket-ssl-perl libnet-ssleay-perl tor wl-clipboard curl libnotify-bin
```

#### **Fedora / RHEL**

```bash
sudo dnf install perl perl-Config-Simple perl-JSON perl-Readonly perl-IO-Socket-SSL perl-Net-SSLeay tor wl-clipboard curl libnotify
```

#### **Universal CPAN Method (Alternative)**

If any Perl package is unavailable in your distribution's repositories, install them using CPAN:

```bash
sudo cpan install Config::Simple JSON Readonly IO::Socket::SSL Net::SSLeay Try::Tiny
```

---

### Step 2: Install Nipe

Clone the official Nipe repository into your home directory (or custom directory):

```bash
git clone https://github.com/htbridge/nipe ~/nipe
cd ~/nipe
sudo perl nipe.pl install
```

> **Note**: Nipe will download and set up default Tor service rules during `install`.

---

### Step 3: Configure Sudoers Permissions (Crucial)

Nipe requires root privileges to configure `iptables` rules and check connection status. To allow the background widget to query status and toggle Nipe without blocking on interactive password prompts:

1. Create a sudoers file for Nipe:

   ```bash
   sudo visudo /etc/sudoers.d/nipe
   ```

2. Add the following rule (replace `username` with your Linux username or use `%wheel` / `%sudo` group):

   ```sudoers
   # Allow user to run Nipe script as root without password prompt
   username ALL=(ALL) NOPASSWD: /usr/bin/perl /home/username/nipe/nipe.pl *
   ```

3. Save and set proper permissions:
   ```bash
   sudo chmod 0440 /etc/sudoers.d/nipe
   ```

---

### Step 4: Install the Helper Script

Ensure `nipe-widget.sh` is placed in `~/.local/bin/` and made executable:

```bash
mkdir -p ~/.local/bin
cp nipe-widget.sh ~/.local/bin/
chmod +x ~/.local/bin/nipe-widget.sh
```

You can test the helper script from your terminal:

```bash
# Check perl dependencies
~/.local/bin/nipe-widget.sh check-deps

# Output JSON status
~/.local/bin/nipe-widget.sh json-status

# Run leak test (requires Nipe to be active)
~/.local/bin/nipe-widget.sh leak-test
```

Expected output of `json-status`:

```json
{
  "active": false,
  "ip": "Unknown",
  "error": null,
  "nipe_dir": "/home/username/nipe"
}
```

---

### Step 5: Enable Plugin in DankMaterialShell

1. Open DankMaterialShell Settings (`Super` + `,` or via launcher).
2. Navigate to **Plugins** section.
3. Enable **Nipe Control**.
4. Configure options under **Nipe Control Settings**:
   - **Custom Nipe Directory**: Specify path if Nipe is installed outside `~/nipe`.
   - **Refresh Interval**: Set status refresh rate (default `15` seconds).
   - **Show Country Code**: Display country code/name alongside IP.
   - **Enable Notifications**: Get desktop alerts on status changes.
   - **Auto-start on Login**: Automatically enable Tor gateway when DMS starts.
   - **IP Info API Endpoint**: Customize API for IP/country lookup.

---

## 🛠️ Helper Script Usage (`nipe-widget.sh`)

The helper script can also be executed directly from the terminal for debugging:

| Command                      | Description                                   |
| :--------------------------- | :-------------------------------------------- |
| `nipe-widget.sh start`       | Starts Nipe Tor gateway                       |
| `nipe-widget.sh stop`        | Stops Nipe Tor gateway                        |
| `nipe-widget.sh restart`     | Restarts Nipe Tor gateway                     |
| `nipe-widget.sh status`      | Prints raw Nipe status output                 |
| `nipe-widget.sh json-status` | Returns structured JSON status for UI widgets |
| `nipe-widget.sh check-deps`  | Verifies required Perl + system modules       |
| `nipe-widget.sh leak-test`   | Runs IP leak test (requires active Nipe)  |
| `nipe-widget.sh path`        | Displays detected Nipe installation path      |

Optionally pass a custom IP API base URL as a second argument, e.g.:

```bash
~/.local/bin/nipe-widget.sh json-status https://api.example.com
~/.local/bin/nipe-widget.sh leak-test https://api.example.com
```

---

## 🔍 Troubleshooting

- **Error: "Sudo password required"**:
  Ensure `/etc/sudoers.d/nipe` is created and correctly references the full path to `perl` and `nipe.pl`.
- **Error: "Missing dependencies"**:
  Run `nipe-widget.sh check-deps` in terminal to identify missing Perl packages.
- **Nipe fails to start**:
  Verify the Tor service is running: `sudo systemctl status tor`.
- **IP leak test shows false positives**:
  The IP leak check compares your live exit IP against the Tor gateway IP (via your IP API). If the API is blocked or unreachable, the test may report a leak or an error.
- **Country not showing**:
  Ensure `curl` and `jq` are installed. Check IP API endpoint in settings (default: ipinfo.io).
- **Custom Directory**:
  If Nipe is located in a non-standard directory (e.g. `/opt/nipe`), specify the path in `NipeControlSettings.qml` or set `NIPE_DIR=/your/path` in `~/.config/nipeControl/config`.

---

## 📜 License

MIT License - feel free to modify and distribute.
