import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    // Configuration from DankMaterialShell plugin settings
    property string customNipeDir: pluginData.customNipeDir || ""
    property int refreshIntervalSec: Math.max(5, parseInt(pluginData.refreshInterval || "15", 10))

    // State properties
    property bool nipeActive: false
    property string ipAddress: "Unknown"
    property string statusText: "Checking..."
    property string errorMessage: ""
    property string nipeDir: ""
    property bool isLoading: false
    property string rawJsonOutput: ""

    function getHelperPath() {
        return (Quickshell.env("HOME") || "/home") + "/.local/bin/nipe-widget.sh";
    }

    function refreshStatus() {
        if (statusProcess.running) return;
        root.rawJsonOutput = "";
        root.isLoading = true;
        statusProcess.command = [getHelperPath(), "json-status"];
        statusProcess.running = true;
    }

    function executeControl(action) {
        if (controlProcess.running) return;
        root.isLoading = true;
        if (action === "start") {
            root.statusText = "Starting...";
        } else if (action === "stop") {
            root.statusText = "Stopping...";
        } else if (action === "restart") {
            root.statusText = "Restarting...";
        }
        controlProcess.command = [getHelperPath(), action];
        controlProcess.running = true;
    }

    function copyIpToClipboard() {
        if (root.ipAddress && root.ipAddress !== "Unknown" && root.ipAddress !== "N/A") {
            Quickshell.execDetached([
                "sh", "-c",
                "printf '%s' '" + root.ipAddress + "' | wl-copy 2>/dev/null || printf '%s' '" + root.ipAddress + "' | xclip -selection clipboard 2>/dev/null"
            ]);
            Quickshell.execDetached([
                "notify-send", "-a", "Nipe Control",
                "IP Copied", "Copied " + root.ipAddress + " to clipboard."
            ]);
        }
    }

    Process {
        id: statusProcess
        command: []
        running: false

        stdout: SplitParser {
            onRead: data => {
                root.rawJsonOutput += data;
            }
        }

        onRunningChanged: {
            if (!running) {
                root.isLoading = false;
                try {
                    if (root.rawJsonOutput.trim().length > 0) {
                        const parsed = JSON.parse(root.rawJsonOutput.trim());
                        root.nipeActive = !!parsed.active;
                        root.ipAddress = parsed.ip || "Unknown";
                        root.errorMessage = parsed.error || "";
                        root.nipeDir = parsed.nipe_dir || "";

                        if (root.errorMessage) {
                            root.statusText = "Error";
                        } else if (root.nipeActive) {
                            root.statusText = "Active";
                        } else {
                            root.statusText = "Inactive";
                        }
                    }
                } catch (e) {
                    console.warn("NipeControl JSON parse error: " + e);
                    root.errorMessage = "Failed to parse status response.";
                    root.statusText = "Error";
                }
            }
        }
    }

    Process {
        id: controlProcess
        command: []
        running: false

        onRunningChanged: {
            if (!running) {
                // Wait 1.5s after start/stop before refreshing status to allow Tor to route
                afterControlTimer.restart();
            }
        }
    }

    Timer {
        id: afterControlTimer
        interval: 1500
        repeat: false
        onTriggered: root.refreshStatus()
    }

    Timer {
        id: autoRefreshTimer
        interval: root.refreshIntervalSec * 1000
        repeat: true
        running: true
        onTriggered: root.refreshStatus()
    }

    Timer {
        id: initTimer
        interval: 300
        repeat: false
        running: true
        onTriggered: root.refreshStatus()
    }

    // Bar Pill Layouts
    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                name: root.errorMessage !== "" ? "warning" : (root.nipeActive ? "shield" : "security")
                size: Theme.iconSize - 6
                color: root.errorMessage !== "" ? Theme.error : (root.nipeActive ? Theme.primary : Theme.surfaceVariantText)
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: {
                    if (root.isLoading && root.statusText.endsWith("...")) return root.statusText;
                    if (root.errorMessage !== "") return "Nipe Error";
                    if (root.nipeActive) return root.ipAddress !== "Unknown" ? root.ipAddress : "Active";
                    return "Nipe Off";
                }
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: root.nipeActive ? Theme.primary : Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            DankIcon {
                name: root.errorMessage !== "" ? "warning" : (root.nipeActive ? "shield" : "security")
                size: Theme.iconSize - 6
                color: root.errorMessage !== "" ? Theme.error : (root.nipeActive ? Theme.primary : Theme.surfaceVariantText)
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: root.nipeActive ? "ON" : "OFF"
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: root.nipeActive ? Theme.primary : Theme.surfaceVariantText
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // Popout Component Card
    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: "Nipe Tor Control"
            detailsText: {
                if (root.errorMessage !== "") return "Status: Configuration / Permission Error";
                if (root.nipeActive) return "Tor Gateway: Enabled • IP: " + root.ipAddress;
                return "Tor Gateway: Disabled";
            }
            showCloseButton: true

            Column {
                width: parent.width
                spacing: Theme.spacingM

                // Status Banner Card
                StyledRect {
                    width: parent.width
                    height: statusBannerColumn.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: root.nipeActive ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : Theme.surfaceContainerHigh

                    Column {
                        id: statusBannerColumn
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        Row {
                            width: parent.width
                            spacing: Theme.spacingM

                            DankIcon {
                                name: root.nipeActive ? "verified_user" : "security"
                                size: 36
                                color: root.nipeActive ? Theme.primary : Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 50

                                StyledText {
                                    text: root.nipeActive ? "Tor Gateway Active" : "Tor Gateway Inactive"
                                    font.pixelSize: Theme.fontSizeLarge
                                    font.weight: Font.Bold
                                    color: root.nipeActive ? Theme.primary : Theme.surfaceText
                                }

                                StyledText {
                                    text: root.nipeActive ? "All system traffic is routed through Tor" : "Traffic is routed directly (Default Gateway)"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    wrapMode: Text.WordWrap
                                    width: parent.width
                                }
                            }
                        }

                        // IP Address Row with Copy Button
                        StyledRect {
                            width: parent.width
                            height: 44
                            radius: Theme.cornerRadiusSmall
                            color: Theme.surfaceContainerHighest

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacingM
                                anchors.rightMargin: Theme.spacingS
                                spacing: Theme.spacingM

                                DankIcon {
                                    name: "lan"
                                    size: Theme.iconSize - 2
                                    color: Theme.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 90

                                    StyledText {
                                        text: "Current External IP"
                                        font.pixelSize: 10
                                        color: Theme.surfaceVariantText
                                    }

                                    StyledText {
                                        text: root.ipAddress
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.Bold
                                        color: Theme.surfaceText
                                        elide: Text.ElideRight
                                    }
                                }

                                DankButton {
                                    text: "Copy"
                                    iconName: "content_copy"
                                    anchors.verticalCenter: parent.verticalCenter
                                    onClicked: root.copyIpToClipboard()
                                    enabled: root.ipAddress !== "Unknown" && root.ipAddress !== "N/A"
                                }
                            }
                        }
                    }
                }

                // Error / Warning Display if applicable
                StyledRect {
                    width: parent.width
                    height: errorColumn.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.15)
                    visible: root.errorMessage !== ""

                    Column {
                        id: errorColumn
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingXS

                        Row {
                            spacing: Theme.spacingS

                            DankIcon {
                                name: "error"
                                size: Theme.iconSize
                                color: Theme.error
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: "Attention Required"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Bold
                                color: Theme.error
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        StyledText {
                            text: root.errorMessage
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                            wrapMode: Text.WordWrap
                            width: parent.width
                        }
                    }
                }

                // Control Action Buttons
                Column {
                    width: parent.width
                    spacing: Theme.spacingS

                    StyledText {
                        text: "Gateway Controls"
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Medium
                        color: Theme.surfaceVariantText
                    }

                    Row {
                        id: actionRow
                        width: parent.width
                        spacing: Theme.spacingS
                        property real btnWidth: (width - spacing * 2) / 3

                        DankButton {
                            text: "Start"
                            iconName: "play_arrow"
                            width: actionRow.btnWidth
                            enabled: !root.isLoading && !root.nipeActive
                            onClicked: root.executeControl("start")
                        }

                        DankButton {
                            text: "Stop"
                            iconName: "stop"
                            width: actionRow.btnWidth
                            enabled: !root.isLoading && root.nipeActive
                            onClicked: root.executeControl("stop")
                        }

                        DankButton {
                            text: "Restart"
                            iconName: "refresh"
                            width: actionRow.btnWidth
                            enabled: !root.isLoading
                            onClicked: root.executeControl("restart")
                        }
                    }
                }

                // Bottom Status Bar & Directory Path
                Row {
                    width: parent.width

                    StyledText {
                        text: root.nipeDir ? "Nipe: " + root.nipeDir : "Nipe Directory Not Found"
                        font.pixelSize: Theme.fontSizeSmall - 2
                        color: Theme.surfaceVariantText
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideMiddle
                        width: parent.width - 40
                    }

                    DankButton {
                        iconName: "refresh"
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        onClicked: root.refreshStatus()
                        enabled: !root.isLoading
                    }
                }
            }
        }
    }
}
