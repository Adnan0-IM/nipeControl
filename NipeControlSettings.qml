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
            text: "Manage the Tor gateway integration: routing status, exit country, leak testing, notifications and startup behavior."
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
                spacing: Theme.spacingS

                DankIcon {
                    name: "tune"
                    size: Theme.iconSize
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: "General Configuration"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            StringSetting {
                settingKey: "customNipeDir"
                label: "Custom Nipe Directory Path"
                description: "Path to your cloned Nipe repository (leave blank to auto-detect e.g., ~/nipe)"
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
                description: "Base URL used for IP, country and leak verification (expects ipinfo.io-like JSON and /ip endpoint)"
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
                spacing: Theme.spacingS

                DankIcon {
                    name: "toggle_on"
                    size: Theme.iconSize
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: "Behavior & Display"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
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
                description: "Automatically activate the Tor gateway when the shell starts (requires passwordless sudoers rule)"
                defaultValue: false
            }
        }
    }

    // ===================================================================
    // Sudoers & Permissions Setup
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
                spacing: Theme.spacingS

                DankIcon {
                    name: "verified_user"
                    size: Theme.iconSize
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: "Sudoers & Permissions Setup"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            StyledText {
                text: "Nipe requires root privileges to manage iptables and Tor routing.\n\nTo allow seamless status checks and widget controls without password prompts, add a sudoers rule:"
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
                        text: "Create file /etc/sudoers.d/nipe with content (replace /path/to/nipe with your actual Nipe path):"
                        font.pixelSize: Theme.fontSizeSmall - 2
                        color: Theme.surfaceVariantText
                    }

                    StyledText {
                        text: "%wheel ALL=(ALL) NOPASSWD: /usr/bin/perl /path/to/nipe/nipe.pl *"
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: "monospace"
                        font.weight: Font.Medium
                        color: Theme.primary
                        width: parent.width
                        wrapMode: Text.WrapAnywhere
                    }
                }
            }

            StyledText {
                text: "Refer to the plugin README.md for complete details."
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
                spacing: Theme.spacingS

                DankIcon {
                    name: "lightbulb"
                    size: Theme.iconSize
                    color: Theme.warning
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: "Tips & Troubleshooting"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            StyledText {
                text: "• Leak Test requires an active Nipe connection and internet access to ipinfo.io (or your custom endpoint).\n\n• If the bar shows 'Nipe Error', run `nipe-widget.sh check-deps` from a terminal to find missing dependencies.\n\n• Country detection falls back gracefully: if the IP API is unreachable, only the IP address is shown.\n\n• The DMS plugin must be installed at ~/.local/bin/nipe-widget.sh for auto-start to work.\n\n• Auto-start only activates once per session to avoid infinite retry loops if Nipe fails to start.\n\n• Use a custom IP API endpoint if ipinfo.io is blocked or rate-limited in your network."
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
                spacing: Theme.spacingS

                DankIcon {
                    name: "extension"
                    size: Theme.iconSize
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: "Additional Dependencies"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            StyledText {
                text: "Country detection, leak tests and notifications require:\n\n• curl  — HTTP lookups and leak checks\n• jq    — JSON parsing\n• notify-send (libnotify) — desktop notifications\n\nThese are checked automatically by the helper script on every status refresh."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
                width: parent.width
                lineHeight: 1.4
            }
        }
    }
}