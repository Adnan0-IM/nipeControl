import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "nipeControl"

    StyledText {
        width: parent.width
        text: "Nipe Control Settings"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Configure Nipe Tor Gateway integration and update intervals."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StyledRect {
        width: parent.width
        height: configColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: configColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: "General Configuration"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
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
        }
    }

    StyledRect {
        width: parent.width
        height: infoColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surface

        Column {
            id: infoColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            Row {
                spacing: Theme.spacingM

                DankIcon {
                    name: "info"
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
                text: "Nipe requires root privileges to manage iptables and Tor routing.\n\nTo allow seamless status checks and widget controls without password prompts, add a sudoers rule:\n\nCreate file `/etc/sudoers.d/nipe` with content:\n`%wheel ALL=(ALL) NOPASSWD: /usr/bin/perl */nipe.pl *`\n\nRefer to the plugin README.md for complete details."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
                width: parent.width
                lineHeight: 1.4
            }
        }
    }
}
