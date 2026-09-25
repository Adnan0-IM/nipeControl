import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    // ---- Configuration from DankMaterialShell plugin settings ----
    property string customNipeDir: pluginData.customNipeDir || ""
    property int refreshIntervalSec: Math.max(5, parseInt(pluginData.refreshInterval, 10) || 15)
    property bool showCountry: pluginData.showCountry ?? true
    property bool enableNotifications: pluginData.enableNotifications ?? true
    property bool autoStartEnabled: pluginData.autoStart ?? false
    property string ipInfoApiEndpoint: pluginData.ipInfoApiEndpoint || "https://ipinfo.io"

    // ---- Helper state ----
    property string statusStderr: ""
    property string controlStderr: ""
    property string controlStdout: ""

    // ---- State properties ----
    property bool nipeActive: false
    property string ipAddress: ""
    property string statusText: "Checking..."
    property string errorMessage: ""
    property string nipeDir: ""
    property string countryCode: ""
    property string countryName: ""
    property string city: ""
    property string region: ""
    property bool isActionRunning: false
    property bool isManualRefreshing: false
    property bool ipCopiedJustNow: false
    property bool pendingManualRefresh: false

    // Start / Stop / Restart are pointless without a resolved Nipe checkout.
    readonly property bool nipeReady: nipeDir !== ""

    // ---- Notifications / auto-start bookkeeping ----
    property bool prevActive: false
    property bool hasInitialStatus: false
    property bool autoStartAttempted: false

    function flagEmoji(code) {
        if (!code || code.length !== 2) return "";
        var base = 0x1F1E6;
        var s = code.toUpperCase();
        return String.fromCodePoint(base + s.charCodeAt(0) - 65, base + s.charCodeAt(1) - 65);
    }

    // ipinfo.io has no country name, only the code, so the city and region are
    // what make the line readable; fall back to the name when an API supplies one.
    function locationLabel() {
        if (!root.showCountry || !root.countryCode) return "";
        var parts = [];
        if (root.city) parts.push(root.city);
        if (root.region && root.region !== root.city) parts.push(root.region);
        if (parts.length === 0) parts.push(root.countryName || root.countryCode);
        return root.flagEmoji(root.countryCode) + "  " + parts.join(", ");
    }

    function getHelperPath() {
        return (Quickshell.env("HOME") || "/home") + "/.local/bin/nipe-widget-py";
    }

    function sendNotification(title, body) {
        if (!root.enableNotifications) return;
        Quickshell.execDetached([
            "notify-send", "-a", "Nipe Control", "-i", "security",
            title, body
        ]);
    }

    function showToast(title, body) {
        if (typeof ToastService !== "undefined" && ToastService.showInfo) {
            ToastService.showInfo(title, body);
        } else {
            sendNotification(title, body);
        }
    }

    function showErrorToast(title, body) {
        if (typeof ToastService !== "undefined" && ToastService.showError) {
            ToastService.showError(title, body);
        } else {
            sendNotification(title, body);
        }
    }

    function firstLine(text) {
        var lines = String(text).split("\n").filter(function (line) {
            return line.trim().length > 0;
        });
        var joined = lines.join(" ").replace(/\s+/g, " ").trim();
        return joined.length > 300 ? joined.substring(0, 299) + "…" : joined;
    }

    // The helper only ever prints one JSON object, and it never writes a
    // problem to stdout, so an unparseable payload is always a crash or a
    // truncated pipe. stderr is the fallback source for that case.
    function applyStatusPayload() {
        var trimmed = root.statusStdout.trim();
        if (trimmed.length === 0) {
            var detail = root.firstLine(root.statusStderr);
            root.errorMessage = detail || "The Nipe helper produced no output.";
            root.statusText = "Error";
            return;
        }

        var parsed;
        try {
            parsed = JSON.parse(trimmed);
        } catch (e) {
            console.warn("NipeControl JSON parse error: " + e);
            root.errorMessage = "Unreadable response from the Nipe helper.";
            root.statusText = "Error";
            return;
        }

        var newActive = !!parsed.active;
        root.nipeActive = newActive;
        root.ipAddress = parsed.ip || "";
        root.nipeDir = parsed.nipe_dir || "";
        root.countryCode = parsed.country_code || "";
        root.countryName = parsed.country || root.countryCode;
        root.city = parsed.city || "";
        root.region = parsed.region || "";
        root.errorMessage = parsed.error ? String(parsed.error) : "";

        if (root.errorMessage !== "") {
            root.statusText = "Error";
        } else {
            root.statusText = newActive ? "Active" : "Inactive";
        }

        if (root.hasInitialStatus && root.enableNotifications) {
            if (newActive && !root.prevActive) {
                sendNotification("Nipe Started", "Tor gateway is now active. Exit IP: " + root.ipAddress);
            } else if (!newActive && root.prevActive) {
                sendNotification("Nipe Stopped", "Tor gateway is now inactive. Traffic routed directly.");
            }
        }
        root.prevActive = newActive;
        root.hasInitialStatus = true;

        if (root.autoStartEnabled && !root.autoStartAttempted) {
            root.autoStartAttempted = true;
            if (!newActive && root.errorMessage === "" && root.nipeReady) {
                root.executeControl("start");
            }
        }
    }

    function refreshStatus(manual) {
        if (statusProcess.running || root.isActionRunning) {
            if (manual) root.pendingManualRefresh = true;
            return;
        }
        root.statusStdout = "";
        root.statusStderr = "";
        if (manual) root.isManualRefreshing = true;
        var command = [getHelperPath(), "json-status"];
        if (root.customNipeDir !== "") command.push("--nipe-dir", root.customNipeDir);
        if (root.ipInfoApiEndpoint !== "") command.push("--api", root.ipInfoApiEndpoint);
        statusProcess.command = command;
        statusProcess.running = true;
    }

    function executeControl(action) {
        if (controlProcess.running || !root.nipeReady) return;
        root.isActionRunning = true;
        root.errorMessage = "";
        root.controlStdout = "";
        root.controlStderr = "";
        if (action === "start") {
            root.statusText = "Starting...";
        } else if (action === "stop") {
            root.statusText = "Stopping...";
        } else if (action === "restart") {
            root.statusText = "Restarting...";
        }
        var command = [getHelperPath(), action];
        if (root.customNipeDir !== "") command.push("--nipe-dir", root.customNipeDir);
        controlProcess.command = command;
        controlProcess.running = true;
    }

    Timer {
        id: copiedResetTimer
        interval: 2000
        repeat: false
        onTriggered: root.ipCopiedJustNow = false
    }

    function copyIpToClipboard() {
        if (root.ipAddress) {
            Quickshell.execDetached([
                "sh", "-c",
                "dms cl copy \"$1\" 2>/dev/null || printf '%s' \"$1\" | wl-copy 2>/dev/null || printf '%s' \"$1\" | xclip -selection clipboard 2>/dev/null",
                "sh", root.ipAddress
            ]);
            root.ipCopiedJustNow = true;
            copiedResetTimer.restart();
            showToast("IP Copied", "Copied " + root.ipAddress + " to clipboard");
        }
    }

    Process {
        id: statusProcess
        command: []
        running: false

        stdout: SplitParser {
            onRead: data => {
                root.statusStdout += data;
            }
        }

        stderr: SplitParser {
            onRead: data => {
                root.statusStderr += data;
            }
        }

        onRunningChanged: {
            if (!running) {
                root.isManualRefreshing = false;
                root.applyStatusPayload();
                if (root.pendingManualRefresh) {
                    root.pendingManualRefresh = false;
                    root.refreshStatus(true);
                }
            }
        }
    }

    Process {
        id: controlProcess
        command: []
        running: false

        stdout: SplitParser {
            onRead: data => {
                root.controlStdout += data;
            }
        }

        stderr: SplitParser {
            onRead: data => {
                root.controlStderr += data;
            }
        }

        onRunningChanged: {
            if (!running) {
                root.isActionRunning = false;
                root.evaluateResult();
            }
        }
    }

    // nipe.pl swallows its own exceptions and still exits 0, so a failure is
    // whatever the helper reported or an [!] marker in its output. The toast
    // carries it: errorMessage belongs to the status read, and the refresh that
    // follows an action would clear it a second and a half later.
    function evaluateResult() {
        var message = "";
        try {
            var parsed = JSON.parse(root.controlStdout.trim());
            if (parsed && parsed.ok === false) {
                message = parsed.message || "";
            }
        } catch (e) {
            if (/\[\!\]/.test(root.controlStdout)) {
                message = root.firstLine(root.controlStdout);
            }
        }
        if (message === "") {
            message = root.firstLine(root.controlStderr);
        }
        if (message !== "") {
            showErrorToast("Nipe Control", message);
        }
        afterControlTimer.restart();
    }

    Timer {
        id: afterControlTimer
        interval: 1500
        repeat: false
        onTriggered: root.refreshStatus(true)
    }

    Timer {
        id: autoRefreshTimer
        interval: root.refreshIntervalSec * 1000
        repeat: true
        running: true
        onTriggered: root.refreshStatus(false)
    }

    Timer {
        id: initTimer
        interval: 300
        repeat: false
        running: true
        onTriggered: root.refreshStatus(false)
    }

    // =====================================================================
    // Horizontal Bar Pill
    // =====================================================================
    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS
            verticalAlignment: Text.AlignVCenter

            DankSpinner {
                size: Theme.iconSize - 6
                running: root.isActionRunning || root.isManualRefreshing
                visible: running
            }

            DankIcon {
                name: root.errorMessage !== "" ? "warning" : (root.nipeActive ? "shield" : "security")
                size: Theme.iconSize - 6
                visible: !root.isActionRunning && !root.isManualRefreshing
                color: root.errorMessage !== "" ? Theme.error : (root.nipeActive ? Theme.primary : Theme.surfaceVariantText)
            }

            StyledText {
                text: {
                    if (root.isActionRunning) return root.statusText;
                    if (root.errorMessage !== "" && !root.nipeActive) return "Nipe Error";
                    if (root.nipeActive) {
                        var t = root.ipAddress || "Active";
                        if (root.showCountry && root.countryCode) {
                            t += "  " + root.flagEmoji(root.countryCode) + " " + root.countryCode;
                        }
                        return t;
                    }
                    return "Nipe Off";
                }
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: root.errorMessage !== "" ? Theme.error : (root.nipeActive ? Theme.primary : Theme.surfaceVariantText)
            }
        }
    }

    // =====================================================================
    // Vertical Bar Pill
    // =====================================================================
    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS
            horizontalAlignment: Text.AlignHCenter

            DankSpinner {
                size: Theme.iconSize - 8
                running: root.isActionRunning || root.isManualRefreshing
                visible: running
            }

            DankIcon {
                name: root.errorMessage !== "" ? "warning" : (root.nipeActive ? "shield" : "security")
                size: Theme.iconSize - 8
                visible: !root.isActionRunning && !root.isManualRefreshing
                color: root.errorMessage !== "" ? Theme.error : (root.nipeActive ? Theme.primary : Theme.surfaceVariantText)
            }

            StyledText {
                text: root.isActionRunning ? "…" : (root.errorMessage !== "" ? "!" : (root.nipeActive ? "ON" : "OFF"))
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: root.errorMessage !== "" ? Theme.error : (root.nipeActive ? Theme.primary : Theme.surfaceVariantText)
            }
        }
    }

    // =====================================================================
    // Popout Dashboard
    // =====================================================================
    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: "Nipe Tor Control"
            detailsText: {
                if (root.errorMessage !== "") return "Status: Helper Error";
                if (root.nipeActive) return "Tor Gateway: Enabled • IP: " + root.ipAddress;
                return "Tor Gateway: Disabled";
            }
            showCloseButton: true

            headerActions: Component {
                Row {
                    spacing: Theme.spacingXS

                    DankActionButton {
                        iconName: "refresh"
                        iconColor: Theme.surfaceVariantText
                        buttonSize: 28
                        tooltipText: "Refresh status"
                        tooltipSide: "bottom"
                        enabled: !root.isActionRunning && !root.isManualRefreshing
                        onClicked: root.refreshStatus(true)
                    }
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacingM

                // ---- Status Banner ----
                StyledRect {
                    width: parent.width
                    height: statusBannerColumn.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: root.nipeActive ? Theme.withAlpha(Theme.primary, 0.14)
                                          : (root.errorMessage !== "" ? Theme.withAlpha(Theme.error, 0.14)
                                                                      : Theme.surfaceContainerHigh)

                    Rectangle {
                        width: parent.width
                        height: 3
                        radius: Theme.cornerRadiusSmall
                        visible: root.nipeActive || root.errorMessage !== ""
                        color: root.errorMessage !== "" ? Theme.error : Theme.primary
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Column {
                        id: statusBannerColumn
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        Row {
                            width: parent.width
                            spacing: Theme.spacingM
                            verticalAlignment: Text.AlignVCenter

                            DankSpinner {
                                size: 36
                                running: root.isActionRunning
                                visible: running
                            }

                            DankIcon {
                                name: root.nipeActive ? "verified_user" : (root.errorMessage !== "" ? "error" : "security")
                                size: 36
                                visible: !root.isActionRunning
                                color: root.errorMessage !== "" ? Theme.error : (root.nipeActive ? Theme.primary : Theme.surfaceVariantText)
                            }

                            Column {
                                width: parent.width - 36 - Theme.spacingM - (liveChip.visible ? (liveChip.width + Theme.spacingM) : 0)
                                spacing: Theme.spacingXS

                                StyledText {
                                    text: root.isActionRunning ? root.statusText : (root.nipeActive ? "Tor Gateway Active" : (root.errorMessage !== "" ? "Attention Required" : "Tor Gateway Inactive"))
                                    font.pixelSize: Theme.fontSizeLarge
                                    font.weight: Font.Bold
                                    color: root.errorMessage !== "" ? Theme.error : (root.nipeActive ? Theme.primary : Theme.surfaceText)
                                    elide: Text.ElideRight
                                    width: parent.width
                                }

                                StyledText {
                                    text: root.errorMessage !== "" ? "The helper could not read the gateway state" : (root.nipeActive ? "All system traffic is routed through Tor" : "Traffic is routed directly (Default Gateway)")
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    wrapMode: Text.WordWrap
                                    width: parent.width
                                }
                            }

                            // Live status chip
                            StyledRect {
                                id: liveChip
                                width: chipRow.implicitWidth + Theme.spacingM * 2
                                height: 24
                                radius: height / 2
                                visible: !root.isActionRunning && root.errorMessage === ""
                                color: root.nipeActive ? Theme.withAlpha(Theme.success, 0.18) : Theme.surfaceContainer

                                Row {
                                    id: chipRow
                                    anchors.centerIn: parent
                                    spacing: Theme.spacingXS
                                    verticalAlignment: Text.AlignVCenter

                                    Rectangle {
                                        width: 8
                                        height: 8
                                        radius: 4
                                        color: root.nipeActive ? Theme.success : Theme.surfaceVariantText
                                    }

                                    StyledText {
                                        text: root.nipeActive ? "LIVE" : "IDLE"
                                        font.pixelSize: Theme.fontSizeSmall - 2
                                        font.weight: Font.Bold
                                        color: root.nipeActive ? Theme.success : Theme.surfaceVariantText
                                    }
                                }
                            }
                        }

                        // Connection details row
                        StyledRect {
                            width: parent.width
                            height: connRow.implicitHeight + Theme.spacingS * 2
                            radius: Theme.cornerRadiusSmall
                            color: Theme.surfaceContainerHighest
                            visible: root.nipeActive

                            Row {
                                id: connRow
                                anchors.fill: parent
                                anchors.margins: Theme.spacingS
                                spacing: Theme.spacingS
                                verticalAlignment: Text.AlignVCenter

                                DankIcon {
                                    id: lanIcon
                                    name: "lan"
                                    size: Theme.iconSize - 2
                                    color: Theme.primary
                                }

                                Column {
                                    width: parent.width - lanIcon.width - copyBtn.width - connRow.spacing * 2
                                    spacing: Theme.spacingXS

                                    StyledText {
                                        text: "Current External IP"
                                        font.pixelSize: Theme.fontSizeSmall - 2
                                        color: Theme.surfaceVariantText
                                    }

                                    StyledText {
                                        text: root.ipAddress || "Unknown"
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.Bold
                                        color: Theme.surfaceText
                                        elide: Text.ElideRight
                                        width: parent.width
                                    }

                                    StyledText {
                                        text: root.locationLabel()
                                        font.pixelSize: Theme.fontSizeSmall - 2
                                        color: Theme.surfaceVariantText
                                        elide: Text.ElideRight
                                        width: parent.width
                                        visible: text !== ""
                                    }
                                }

                                DankButton {
                                    id: copyBtn
                                    text: root.ipCopiedJustNow ? "Copied" : "Copy"
                                    iconName: root.ipCopiedJustNow ? "check" : "content_copy"
                                    onClicked: root.copyIpToClipboard()
                                    enabled: root.ipAddress !== ""
                                }
                            }
                        }
                    }
                }

                // ---- Error / Warning Card ----
                StyledRect {
                    width: parent.width
                    height: errorColumn.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    visible: root.errorMessage !== ""
                    color: Theme.withAlpha(Theme.error, 0.14)

                    Column {
                        id: errorColumn
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        Row {
                            spacing: Theme.spacingS
                            verticalAlignment: Text.AlignVCenter

                            DankIcon {
                                name: "error"
                                size: Theme.iconSize
                                color: Theme.error
                            }

                            StyledText {
                                text: "Attention Required"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Bold
                                color: Theme.error
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

                // ---- Control Actions ----
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
                            text: root.isActionRunning && root.statusText === "Starting..." ? "Starting…" : "Start"
                            iconName: "play_arrow"
                            width: actionRow.btnWidth
                            enabled: root.nipeReady && !root.isActionRunning && !root.nipeActive
                            onClicked: root.executeControl("start")
                        }

                        DankButton {
                            text: root.isActionRunning && root.statusText === "Stopping..." ? "Stopping…" : "Stop"
                            iconName: "stop"
                            width: actionRow.btnWidth
                            enabled: root.nipeReady && !root.isActionRunning && root.nipeActive
                            onClicked: root.executeControl("stop")
                        }

                        DankButton {
                            text: root.isActionRunning && root.statusText === "Restarting..." ? "Restarting…" : "Restart"
                            iconName: "refresh"
                            width: actionRow.btnWidth
                            enabled: root.nipeReady && !root.isActionRunning
                            onClicked: root.executeControl("restart")
                        }
                    }
                }

                // ---- Footer: dir path + refresh ----
                Row {
                    id: footerRow
                    width: parent.width
                    spacing: Theme.spacingS
                    verticalAlignment: Text.AlignVCenter

                    DankIcon {
                        id: folderIcon
                        name: root.nipeReady ? "folder" : "warning"
                        size: Theme.iconSize - 6
                        color: root.nipeReady ? Theme.primary : Theme.error
                    }

                    StyledText {
                        text: root.nipeReady ? "Nipe: " + root.nipeDir : "Nipe Directory Not Found"
                        font.pixelSize: Theme.fontSizeSmall - 2
                        color: root.nipeReady ? Theme.surfaceVariantText : Theme.error
                        elide: Text.ElideMiddle
                        width: parent.width - folderIcon.width - refreshBtn.width - (footerSpinner.visible ? (footerSpinner.width + footerRow.spacing) : 0) - footerRow.spacing * 2
                    }

                    DankSpinner {
                        id: footerSpinner
                        size: 14
                        running: root.isManualRefreshing
                        visible: running
                    }

                    DankButton {
                        id: refreshBtn
                        iconName: "refresh"
                        onClicked: root.refreshStatus(true)
                        enabled: !root.isActionRunning && !root.isManualRefreshing
                    }
                }
            }
        }
    }
}