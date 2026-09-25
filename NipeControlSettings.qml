import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "nipeControl"

    Column {
        width: parent.width
        spacing: Theme.spacingXS

        StyledText {
            width: parent.width
            text: "Nipe Control Settings"
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Bold
            color: Theme.surfaceText
        }

        StyledText {
            width: parent.width
            text: "Manage the Tor gateway integration: routing status, exit country, notifications and startup behavior."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }
    }

    // ===================================================================
    // General Configuration
    // ===================================================================
    StyledRect {
        width: parent.width
        height: generalColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: generalColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            Row {
                verticalAlignment: Text.AlignVCenter
                spacing: Theme.spacingS

                DankIcon {
                    name: "tune"
                    size: Theme.iconSize
                    color: Theme.primary
                }

                StyledText {
                    text: "General Configuration"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                }
            }

            StringSetting {
                settingKey: "customNipeDir"
                label: "Custom Nipe Directory Path"
                description: "Path to your cloned Nipe repository. Leave blank to use NIPE_DIR from ~/.config/nipeControl/config, then auto-detect (~/nipe). An explicit path that has no nipe.pl is reported instead of falling back."
                placeholder: "/home/username/nipe"
                defaultValue: ""
            }

            StringSetting {
                settingKey: "refreshInterval"
                label: "Status Refresh Interval (seconds)"
                description: "How often to check Nipe status and external IP (minimum 5s)"
                placeholder: "15"
                defaultValue: "15"
            }

            StringSetting {
                settingKey: "ipInfoApiEndpoint"
                label: "IP Info API Endpoint"
                description: "Base URL used for IP and country verification (expects ipinfo.io-like JSON)"
                placeholder: "https://ipinfo.io"
                defaultValue: "https://ipinfo.io"
            }
        }
    }

    // ===================================================================
    // Behavior & Display Options
    // ===================================================================
    StyledRect {
        width: parent.width
        height: behaviorColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: behaviorColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            Row {
                verticalAlignment: Text.AlignVCenter
                spacing: Theme.spacingS

                DankIcon {
                    name: "toggle_on"
                    size: Theme.iconSize
                    color: Theme.primary
                }

                StyledText {
                    text: "Behavior & Display"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                }
            }

            ToggleSetting {
                settingKey: "showCountry"
                label: "Show Country Code"
                description: "Display the Tor exit node country flag/code in the bar widget"
                defaultValue: true
            }

            ToggleSetting {
                settingKey: "enableNotifications"
                label: "Enable Notifications"
                description: "Desktop alerts when Nipe starts, stops or restarts"
                defaultValue: true
            }

            ToggleSetting {
                settingKey: "autoStart"
                label: "Auto-start on Login"
                description: "Activate the Tor gateway once when the shell starts, after the first status read (asks for root with a polkit dialog)"
                defaultValue: false
            }
        }
    }

    // ===================================================================
    // How Permissions Work
    // ===================================================================
    StyledRect {
        width: parent.width
        height: sudoColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: sudoColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            Row {
                verticalAlignment: Text.AlignVCenter
                spacing: Theme.spacingS

                DankIcon {
                    name: "verified_user"
                    size: Theme.iconSize
                    color: Theme.primary
                }

                StyledText {
                    text: "How Permissions Work"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                }
            }

            StyledText {
                text: "Nipe needs root to reconfigure iptables and the default route, so Start, Stop and Restart run nipe.pl through pkexec. That raises a polkit dialog asking for your password, which is the only place a prompt appears. No sudoers rule and no passwordless root is required or installed."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
                width: parent.width
                lineHeight: 1.4
            }

            StyledRect {
                width: parent.width
                height: codeCol.implicitHeight + Theme.spacingM * 2
                radius: Theme.cornerRadiusSmall
                color: Theme.surfaceContainerHighest

                Column {
                    id: codeCol
                    anchors.fill: parent
                    anchors.margins: Theme.spacingM
                    spacing: Theme.spacingXS

                    StyledText {
                        text: "Reading the status never asks for anything:"
                        font.pixelSize: Theme.fontSizeSmall - 2
                        color: Theme.surfaceVariantText
                    }

                    StyledText {
                        text: "curl --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip"
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: "monospace"
                        font.weight: Font.Medium
                        color: Theme.primary
                        width: parent.width
                        wrapMode: Text.WrapAnywhere
                    }

                    StyledText {
                        text: "The helper asks the Tor Project whether the current connection is a Tor circuit and which exit node it is. If the local Tor instance answers, the gateway is up; if it is silent, a direct request decides whether Tor is down or the network is broken. That is the whole status check, and it is why the bar can refresh on a timer without interrupting you."
                        font.pixelSize: Theme.fontSizeSmall - 2
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }
                }
            }

            StyledText {
                text: "If a polkit dialog never appears, install polkit and make sure your session can ask for authentication."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
                width: parent.width
            }
        }
    }

    // ===================================================================
    // Helpful Tips
    // ===================================================================
    StyledRect {
        width: parent.width
        height: tipsColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: tipsColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            Row {
                verticalAlignment: Text.AlignVCenter
                spacing: Theme.spacingS

                DankIcon {
                    name: "lightbulb"
                    size: Theme.iconSize
                    color: Theme.warning
                }

                StyledText {
                    text: "Tips & Troubleshooting"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                }
            }

            StyledText {
                text: "• Status reads are silent and unprivileged, so the refresh interval can be as low as 5s without a prompt storm.\n\n• Exit node lookups are cached per IP for 6 hours, and a failing endpoint is backed off for 15 minutes, so a blocked or rate-limited API does not get hammered.\n\n• The helper must be installed at ~/.local/bin/nipe-widget-py. Run it with no arguments to see the commands it accepts.\n\n• Auto-start only activates once per session, and only after a clean status read, so a failed start is not retried in a loop.\n\n• Logs go to ~/.local/share/nipeControl/nipe-widget-py.log."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
                width: parent.width
                lineHeight: 1.4
            }
        }
    }

    // ===================================================================
    // Additional Dependencies
    // ===================================================================
    StyledRect {
        width: parent.width
        height: depsColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: depsColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            Row {
                verticalAlignment: Text.AlignVCenter
                spacing: Theme.spacingS

                DankIcon {
                    name: "extension"
                    size: Theme.iconSize
                    color: Theme.primary
                }

                StyledText {
                    text: "Additional Dependencies"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                }
            }

            StyledText {
                text: "Required:\n\n• perl with Config::Simple, JSON, Readonly, Try::Tiny, IO::Socket::SSL and Net::SSLeay — run by nipe.pl\n• curl — the status probe and the exit node lookup\n• pkexec (polkit) — only for Start, Stop and Restart\n\nOptional:\n\n• notify-send (libnotify) — desktop notifications\n• wl-copy or xclip (or dms) — the copy IP button\n\nRun ~/.local/bin/nipe-widget-py check-deps for the current state. The result is cached for a day, and missing optional tools are reported without affecting the status read."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
                width: parent.width
                lineHeight: 1.4
            }
        }
    }
}