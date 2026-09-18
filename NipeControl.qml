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
    property int refreshIntervalSec: parseInt(pluginData.refreshInterval, 10) || 15
    property bool showCountry: pluginData.showCountry ?? true
    property bool enableNotifications: pluginData.enableNotifications ?? true
    property bool autoStartEnabled: pluginData.autoStart ?? false
    property string ipInfoApiEndpoint: pluginData.ipInfoApiEndpoint || "https://ipinfo.io"

    // ---- Helper state ----
    property bool nipeDirValid: false

    // ---- State properties ----
    property bool nipeActive: false
    property string ipAddress: "Unknown"
    property string statusText: "Checking..."
    property string errorMessage: ""
    property string nipeDir: ""
    property string countryCode: ""
    property string countryName: ""
    property string city: ""
    property string region: ""
    property string org: ""
    property bool isActionRunning: false
    property bool isManualRefreshing: false
    property bool isBackgroundChecking: false
    readonly property bool isLoading: isActionRunning || isManualRefreshing || isBackgroundChecking
    property string rawJsonOutput: ""

    // ---- Notifications / auto-start bookkeeping ----
    property bool prevActive: false
    property bool hasInitialStatus: false
    property bool autoStartAttempted: false

    // ---- Leak test state ----
    property string leakTestState: "idle"   // idle | testing | ok | leak | error
    property string leakTestError: ""
    property bool leakIp: false
    property bool leakDns: false
    property string leakExitIp: ""
    property string leakExitCountryCode: ""
    property string leakExitCountry: ""

    function flagEmoji(code) {
        if (!code || code.length !== 2) return "";
        var base = 0x1F1E6;
        var s = code.toUpperCase();
        return String.fromCodePoint(base + s.charCodeAt(0) - 65, base + s.charCodeAt(1) - 65);
    }

    function getHelperPath() {
        return (Quickshell.env("HOME") || "/home") + "/.local/bin/nipe-widget.sh";
    }

    function sendNotification(title, body) {
        if (!root.enableNotifications) return;
        Quickshell.execDetached([
            "notify-send", "-a", "Nipe Control", "-i", "security",
            title, body
        ]);
    }

    function refreshStatus(manual) {
        if (statusProcess.running) return;
        root.rawJsonOutput = "";
        if (manual) {
            root.isManualRefreshing = true;
        } else {
            root.isBackgroundChecking = true;
        }
        statusProcess.command = [getHelperPath(), "json-status", root.ipInfoApiEndpoint];
        statusProcess.running = true;
    }

    function executeControl(action) {
        if (controlProcess.running) return;
        root.isActionRunning = true;
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

    function runLeakTest() {
        if (leakTestProcess.running) return;
        root.leakTestState = "testing";
        root.leakTestError = "";
        root.leakIp = false;
        root.leakDns = false;
        root.leakExitIp = "";
        root.leakExitCountryCode = "";
        root.leakExitCountry = "";
        root.leakTestRaw = "";
        leakTestProcess.command = [getHelperPath(), "leak-test", root.ipInfoApiEndpoint];
        leakTestProcess.running = true;
    }

    property bool ipCopiedJustNow: false
    Timer {
        id: copiedResetTimer
        interval: 2000
        repeat: false
        onTriggered: root.ipCopiedJustNow = false
    }

    function copyIpToClipboard() {
        if (root.ipAddress && root.ipAddress !== "Unknown" && root.ipAddress !== "N/A") {
            Quickshell.execDetached([
                "sh", "-c",
                "dms cl copy \"$1\" 2>/dev/null || printf '%s' \"$1\" | wl-copy 2>/dev/null || printf '%s' \"$1\" | xclip -selection clipboard 2>/dev/null",
                "sh", root.ipAddress
            ]);
            root.ipCopiedJustNow = true;
            copiedResetTimer.restart();
            if (typeof ToastService !== "undefined" && ToastService.showInfo) {
                ToastService.showInfo("Copied " + root.ipAddress + " to clipboard");
            } else {
                sendNotification("IP Copied", "Copied " + root.ipAddress + " to clipboard.");
            }
        }
    }

    function leakStateColor() {
        if (root.leakTestState === "ok") return Theme.success;
        if (root.leakTestState === "leak") return Theme.error;
        if (root.leakTestState === "testing") return Theme.warning;
        return Theme.surfaceVariantText;
    }

    function leakStateLabel() {
        if (root.leakTestState === "ok") return "No DNS or IP leaks detected";
        if (root.leakTestState === "leak") {
            var parts = [];
            if (root.leakDns) parts.push("DNS leak");
            if (root.leakIp) parts.push("IP leak");
            return "Detected: " + parts.join(" & ");
        }
        if (root.leakTestState === "testing") return "Running leak test…";
        if (root.leakTestState === "error") return "Leak test failed";
        return "Not run yet";
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
                root.isManualRefreshing = false;
                root.isBackgroundChecking = false;
                root.isActionRunning = false;
                try {
                    const trimmed = root.rawJsonOutput.trim();
                    if (trimmed.length > 0) {
                        const parsed = JSON.parse(trimmed);
                        if (!parsed) throw new Error("Empty JSON result");
                        const newActive = !!parsed.active;
                        root.nipeActive = newActive;
                        root.ipAddress = parsed.ip || "Unknown";
                        root.errorMessage = parsed.error || "";
                        root.nipeDir = parsed.nipe_dir || "";
                        root.countryCode = parsed.country_code || "";
                        root.countryName = parsed.country || root.countryCode;
                        root.city = parsed.city || "";
                        root.region = parsed.region || "";
                        root.org = parsed.org || "";

                        if (root.errorMessage) {
                            root.statusText = "Error";
                        } else if (newActive) {
                            root.statusText = "Active";
                        } else {
                            root.statusText = "Inactive";
                        }

                        // Status change notifications
                        if (root.hasInitialStatus && root.enableNotifications) {
                            if (newActive && !root.prevActive) {
                                sendNotification("Nipe Started", "Tor gateway is now active. Exit IP: " + root.ipAddress);
                            } else if (!newActive && root.prevActive) {
                                sendNotification("Nipe Stopped", "Tor gateway is now inactive. Traffic routed directly.");
                            }
                        }
                        root.prevActive = newActive;
                        root.hasInitialStatus = true;

                        // Auto-start on boot/login (once per session, only after the
                        // first successful status check so we know the real state)
                        if (root.autoStartEnabled && !root.autoStartAttempted) {
                            root.autoStartAttempted = true;
                            if (!newActive && !root.errorMessage) {
                                root.executeControl("start");
                            }
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
                // Wait a bit after start/stop before refreshing to let Tor route
                afterControlTimer.restart();
            }
        }
    }

    property string leakTestRaw: ""

    Process {
        id: leakTestProcess
        command: []
        running: false

        stdout: SplitParser {
            onRead: data => {
                root.leakTestRaw += data;
            }
        }

        onRunningChanged: {
            if (!running) {
                try {
                    const parsed = JSON.parse(root.leakTestRaw.trim());
                    root.leakIp = (parsed.ip_result === "fail" || !!parsed.ip_leak);
                    root.leakDns = (parsed.dns_result === "fail" || !!parsed.dns_leak);
                    root.leakExitIp = parsed.exit_ip || "";
                    root.leakExitCountryCode = parsed.exit_country_code || "";
                    root.leakExitCountry = parsed.exit_country || root.leakExitCountryCode;
                    root.leakTestError = parsed.error || "";

                    if (root.leakTestError) {
                        root.leakTestState = "error";
                    } else if (!root.leakIp && !root.leakDns) {
                        root.leakTestState = "ok";
                    } else {
                        root.leakTestState = "leak";
                    }
                } catch (e) {
                    console.warn("NipeControl leak test parse error: " + e);
                    root.leakTestState = "error";
                    root.leakTestError = "Failed to parse leak test result.";
                }
            }
        }
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
            id: hPill
            spacing: Theme.spacingXS

            DankSpinner {
                size: Theme.iconSize - 6
                running: root.isActionRunning || root.isManualRefreshing
                visible: running
                anchors.verticalCenter: parent.verticalCenter
            }

            DankIcon {
                name: root.errorMessage !== "" ? "warning" : (root.nipeActive ? "shield" : "security")
                size: Theme.iconSize - 6
                visible: !root.isActionRunning && !root.isManualRefreshing
                color: root.errorMessage !== "" ? Theme.error : (root.nipeActive ? Theme.primary : Theme.surfaceVariantText)
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: {
                    if (root.isActionRunning) return root.statusText;
                    if (root.errorMessage !== "") return "Nipe Error";
                    if (root.nipeActive) {
                        var t = root.ipAddress !== "Unknown" ? root.ipAddress : "Active";
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
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // =====================================================================
    // Vertical Bar Pill
    // =====================================================================
    verticalBarPill: Component {
        Column {
            id: vPill
            spacing: Theme.spacingXS

            DankSpinner {
                size: Theme.iconSize - 8
                running: root.isActionRunning || root.isManualRefreshing
                visible: running
                anchors.horizontalCenter: parent.horizontalCenter
            }

            DankIcon {
                name: root.errorMessage !== "" ? "warning" : (root.nipeActive ? "shield" : "security")
                size: Theme.iconSize - 8
                visible: !root.isActionRunning && !root.isManualRefreshing
                color: root.errorMessage !== "" ? Theme.error : (root.nipeActive ? Theme.primary : Theme.surfaceVariantText)
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: root.isActionRunning ? "…" : (root.errorMessage !== "" ? "!" : (root.nipeActive ? "ON" : "OFF"))
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: root.errorMessage !== "" ? Theme.error : (root.nipeActive ? Theme.primary : Theme.surfaceVariantText)
                anchors.horizontalCenter: parent.horizontalCenter
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
                if (root.errorMessage !== "") return "Status: Configuration / Permission Error";
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
                            id: statusHeaderRow
                            width: parent.width
                            spacing: Theme.spacingM

                            DankSpinner {
                                id: bannerSpinner
                                size: 36
                                running: root.isActionRunning
                                visible: running
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            DankIcon {
                                id: bannerIcon
                                name: root.nipeActive ? "verified_user" : (root.errorMessage !== "" ? "error" : "security")
                                size: 36
                                visible: !root.isActionRunning
                                color: root.errorMessage !== "" ? Theme.error : (root.nipeActive ? Theme.primary : Theme.surfaceVariantText)
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Column {
                                id: bannerTextCol
                                anchors.verticalCenter: parent.verticalCenter
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
                                    text: root.errorMessage !== "" ? "There is a problem with the Nipe setup" : (root.nipeActive ? "All system traffic is routed through Tor" : "Traffic is routed directly (Default Gateway)")
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
                                anchors.verticalCenter: parent.verticalCenter

                                Row {
                                    id: chipRow
                                    anchors.centerIn: parent
                                    spacing: Theme.spacingXS

                                    Rectangle {
                                        width: 8
                                        height: 8
                                        radius: 4
                                        color: root.nipeActive ? Theme.success : Theme.surfaceVariantText
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    StyledText {
                                        text: root.nipeActive ? "LIVE" : "IDLE"
                                        font.pixelSize: Theme.fontSizeSmall - 2
                                        font.weight: Font.Bold
                                        color: root.nipeActive ? Theme.success : Theme.surfaceVariantText
                                        anchors.verticalCenter: parent.verticalCenter
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

                                DankIcon {
                                    id: lanIcon
                                    name: "lan"
                                    size: Theme.iconSize - 2
                                    color: Theme.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - lanIcon.width - copyBtn.width - connRow.spacing * 2
                                    spacing: Theme.spacingXS

                                    StyledText {
                                        text: "Current External IP"
                                        font.pixelSize: Theme.fontSizeSmall - 2
                                        color: Theme.surfaceVariantText
                                    }

                                    StyledText {
                                        text: root.ipAddress
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.Bold
                                        color: Theme.surfaceText
                                        elide: Text.ElideRight
                                        width: parent.width
                                    }

                                    StyledText {
                                        text: (root.showCountry && root.countryCode)
                                              ? (root.flagEmoji(root.countryCode) + "  " + (root.countryName || root.countryCode))
                                              : ""
                                        font.pixelSize: Theme.fontSizeSmall - 2
                                        color: Theme.surfaceVariantText
                                        visible: text !== ""
                                    }
                                }

                                DankButton {
                                    id: copyBtn
                                    text: root.ipCopiedJustNow ? "Copied" : "Copy"
                                    iconName: root.ipCopiedJustNow ? "check" : "content_copy"
                                    anchors.verticalCenter: parent.verticalCenter
                                    onClicked: root.copyIpToClipboard()
                                    enabled: root.ipAddress !== "Unknown" && root.ipAddress !== "N/A"
                                }
                            }
                        }
                    }
                }

                // ---- Geo / Network info ----
                StyledRect {
                    width: parent.width
                    height: geoColumn.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    visible: root.nipeActive && (root.countryCode !== "" || root.city !== "" || root.org !== "")
                    color: Theme.surfaceContainerHigh

                    Column {
                        id: geoColumn
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        Row {
                            spacing: Theme.spacingS
                            width: parent.width

                            DankIcon {
                                name: "public"
                                size: Theme.iconSize - 2
                                color: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: "Exit Node Location"
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                                color: Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Grid {
                            id: geoGrid
                            columns: 2
                            columnSpacing: Theme.spacingM
                            rowSpacing: Theme.spacingS
                            width: parent.width
                            property real colWidth: (width - columnSpacing) / 2

                            Column {
                                width: geoGrid.colWidth
                                spacing: Theme.spacingXS
                                visible: root.countryCode !== ""

                                StyledText {
                                    text: "Country"
                                    font.pixelSize: Theme.fontSizeSmall - 2
                                    color: Theme.surfaceVariantText
                                }

                                StyledText {
                                    text: root.flagEmoji(root.countryCode) + "  " + (root.countryName || root.countryCode)
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceText
                                    font.weight: Font.Medium
                                    width: parent.width
                                    elide: Text.ElideRight
                                }
                            }

                            Column {
                                width: geoGrid.colWidth
                                spacing: Theme.spacingXS
                                visible: root.city !== "" || root.region !== ""

                                StyledText {
                                    text: "City / Region"
                                    font.pixelSize: Theme.fontSizeSmall - 2
                                    color: Theme.surfaceVariantText
                                }

                                StyledText {
                                    text: [root.city, root.region].filter(Boolean).join(", ")
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceText
                                    width: parent.width
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        Column {
                            width: parent.width
                            spacing: Theme.spacingXS
                            visible: root.org !== ""

                            StyledText {
                                text: "Network / ASN"
                                font.pixelSize: Theme.fontSizeSmall - 2
                                color: Theme.surfaceVariantText
                            }

                            StyledText {
                                text: root.org
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }
                    }
                }

                // ---- Leak Test ----
                StyledRect {
                    width: parent.width
                    height: leakColumn.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    visible: root.nipeActive
                    color: Theme.surfaceContainerHigh

                    Column {
                        id: leakColumn
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        Row {
                            width: parent.width
                            spacing: Theme.spacingM

                            Column {
                                width: parent.width - leakBtn.width - Theme.spacingM
                                spacing: Theme.spacingXS
                                anchors.verticalCenter: parent.verticalCenter

                                StyledText {
                                    text: "Leak Test"
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Bold
                                    color: Theme.surfaceText
                                }

                                StyledText {
                                    text: "Verify DNS and IP routing through Tor"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    wrapMode: Text.WordWrap
                                    width: parent.width
                                }
                            }

                            DankButton {
                                id: leakBtn
                                text: root.leakTestState === "testing" ? "Testing…" : "Run Leak Test"
                                iconName: root.leakTestState === "testing" ? "hourglass_top" : "fact_check"
                                anchors.verticalCenter: parent.verticalCenter
                                onClicked: root.runLeakTest()
                                enabled: !root.isActionRunning && root.leakTestState !== "testing"
                            }
                        }

                        // Leak result container
                        StyledRect {
                            width: parent.width
                            height: leakResultRow.implicitHeight + Theme.spacingS * 2
                            radius: Theme.cornerRadiusSmall
                            visible: root.leakTestState !== "idle"
                            color: root.leakTestState === "ok"
                                   ? Theme.withAlpha(Theme.success, 0.12)
                                   : (root.leakTestState === "leak"
                                      ? Theme.withAlpha(Theme.error, 0.12)
                                      : (root.leakTestState === "testing"
                                         ? Theme.withAlpha(Theme.warning, 0.12)
                                         : Theme.surfaceContainerHighest))

                            Row {
                                id: leakResultRow
                                anchors.fill: parent
                                anchors.margins: Theme.spacingS
                                spacing: Theme.spacingS

                                DankSpinner {
                                    id: leakSpinner
                                    size: 20
                                    running: root.leakTestState === "testing"
                                    visible: running
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                DankIcon {
                                    id: leakIcon
                                    name: {
                                        if (root.leakTestState === "ok") return "verified_user";
                                        if (root.leakTestState === "leak") return "gpp_bad";
                                        if (root.leakTestState === "error") return "report";
                                        return "utilities";
                                    }
                                    size: 20
                                    visible: root.leakTestState !== "testing"
                                    color: root.leakStateColor()
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Column {
                                    width: parent.width - 20 - Theme.spacingS
                                    spacing: Theme.spacingXS
                                    anchors.verticalCenter: parent.verticalCenter

                                    StyledText {
                                        text: root.leakStateLabel()
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: Font.Medium
                                        color: root.leakStateColor()
                                        width: parent.width
                                        wrapMode: Text.WordWrap
                                    }

                                    StyledText {
                                        visible: (root.leakTestState === "ok" || root.leakTestState === "leak") && root.leakExitIp !== ""
                                        text: "Verified exit node: " + root.leakExitIp +
                                              (root.leakExitCountryCode !== "" ? " (" + root.flagEmoji(root.leakExitCountryCode) + " " + (root.leakExitCountry || root.leakExitCountryCode) + ")" : "")
                                        font.pixelSize: Theme.fontSizeSmall - 2
                                        color: Theme.surfaceVariantText
                                        width: parent.width
                                        wrapMode: Text.WordWrap
                                    }

                                    StyledText {
                                        visible: root.leakTestState === "error" && root.leakTestError !== ""
                                        text: root.leakTestError
                                        font.pixelSize: Theme.fontSizeSmall - 2
                                        color: Theme.error
                                        width: parent.width
                                        wrapMode: Text.WordWrap
                                    }
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
                            enabled: !root.isActionRunning && !root.nipeActive
                            onClicked: root.executeControl("start")
                        }

                        DankButton {
                            text: root.isActionRunning && root.statusText === "Stopping..." ? "Stopping…" : "Stop"
                            iconName: "stop"
                            width: actionRow.btnWidth
                            enabled: !root.isActionRunning && root.nipeActive
                            onClicked: root.executeControl("stop")
                        }

                        DankButton {
                            text: root.isActionRunning && root.statusText === "Restarting..." ? "Restarting…" : "Restart"
                            iconName: "refresh"
                            width: actionRow.btnWidth
                            enabled: !root.isActionRunning
                            onClicked: root.executeControl("restart")
                        }
                    }
                }

                // ---- Footer: dir path + refresh ----
                Row {
                    id: footerRow
                    width: parent.width
                    spacing: Theme.spacingS

                    DankIcon {
                        id: folderIcon
                        name: "folder"
                        size: Theme.iconSize - 6
                        color: root.nipeDir ? Theme.primary : Theme.surfaceVariantText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: root.nipeDir ? "Nipe: " + root.nipeDir : "Nipe Directory Not Found"
                        font.pixelSize: Theme.fontSizeSmall - 2
                        color: Theme.surfaceVariantText
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideMiddle
                        width: parent.width - folderIcon.width - refreshBtn.width - (footerSpinner.visible ? (footerSpinner.width + footerRow.spacing) : 0) - footerRow.spacing * 2
                    }

                    DankSpinner {
                        id: footerSpinner
                        size: 14
                        running: root.isManualRefreshing
                        visible: running
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    DankButton {
                        id: refreshBtn
                        iconName: "refresh"
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: root.refreshStatus(true)
                        enabled: !root.isActionRunning && !root.isManualRefreshing
                    }
                }
            }
        }
    }
}