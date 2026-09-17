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
    property int refreshIntervalSec: Math.max(5, parseInt(pluginData.refreshInterval || "15", 10))
    property bool showCountry: pluginData.showCountry ?? true
    property bool enableNotifications: pluginData.enableNotifications ?? true
    property bool autoStartEnabled: pluginData.autoStart ?? false
    property string ipInfoApiEndpoint: pluginData.ipInfoApiEndpoint || "https://ipinfo.io"

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
    property bool isLoading: false
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

    function refreshStatus() {
        if (statusProcess.running) return;
        root.rawJsonOutput = "";
        root.isLoading = true;
        statusProcess.command = [getHelperPath(), "json-status", root.ipInfoApiEndpoint];
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

    function copyIpToClipboard() {
        if (root.ipAddress && root.ipAddress !== "Unknown" && root.ipAddress !== "N/A") {
            Quickshell.execDetached([
                "sh", "-c",
                "printf '%s' '" + root.ipAddress + "' | wl-copy 2>/dev/null || printf '%s' '" + root.ipAddress + "' | xclip -selection clipboard 2>/dev/null"
            ]);
            sendNotification("IP Copied", "Copied " + root.ipAddress + " to clipboard.");
        }
    }

    function barTooltipText() {
        if (root.isLoading) return "Checking Nipe status…";
        if (root.errorMessage !== "") return "Nipe Control Error\n" + root.errorMessage;
        if (root.nipeActive) {
            var lines = [];
            lines.push("Tor Gateway: Active");
            lines.push("Exit IP: " + root.ipAddress);
            if (root.showCountry && root.countryCode) {
                lines.push("Country: " + flagEmoji(root.countryCode) + " " + (root.countryName || root.countryCode));
            }
            if (root.city || root.region) {
                lines.push("Location: " + [root.city, root.region].filter(Boolean).join(", "));
            }
            if (root.org) lines.push("Network: " + root.org);
            return lines.join("\n");
        }
        return "Tor Gateway: Inactive\nAll traffic is routed directly";
    }

    function leakStateColor() {
        if (root.leakTestState === "ok") return Theme.success;
        if (root.leakTestState === "leak") return Theme.error;
        if (root.leakTestState === "testing") return "#f0c24b";
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
                root.isLoading = false;
                try {
                    if (root.rawJsonOutput.trim().length > 0) {
                        const parsed = JSON.parse(root.rawJsonOutput.trim());
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
                    root.leakIp = !!parsed.ip_leak;
                    root.leakDns = !!parsed.dns_leak;
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

    // =====================================================================
    // Horizontal Bar Pill
    // =====================================================================
    horizontalBarPill: Component {
        Row {
            id: hPill
            spacing: Theme.spacingXS

            BusyIndicator {
                width: 14
                height: 14
                running: root.isLoading
                visible: running
                anchors.verticalCenter: parent.verticalCenter
                contentItem: Spinner {
                    width: 14
                    height: 14
                }
            }

            DankIcon {
                name: root.errorMessage !== "" ? "warning" : (root.nipeActive ? "shield" : "security")
                size: Theme.iconSize - 6
                color: root.errorMessage !== "" ? Theme.error : (root.nipeActive ? Theme.primary : Theme.surfaceVariantText)
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: {
                    if (root.isLoading && root.statusText.endsWith("...")) return root.statusText;
                    if (root.isLoading) return "Refreshing…";
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
                color: root.nipeActive ? Theme.primary : Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }

            HoverHandler {
                id: hPillHover
            }

            ToolTip {
                visible: hPillHover.hovered
                delay: 450
                timeout: 5000
                padding: Theme.spacingM
                contentItem: StyledText {
                    text: root.barTooltipText()
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                }
                background: StyledRect {
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                }
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

            BusyIndicator {
                width: 12
                height: 12
                running: root.isLoading
                visible: running
                anchors.horizontalCenter: parent.horizontalCenter
                contentItem: Spinner {
                    width: 12
                    height: 12
                }
            }

            DankIcon {
                name: root.errorMessage !== "" ? "warning" : (root.nipeActive ? "shield" : "security")
                size: Theme.iconSize - 8
                color: root.errorMessage !== "" ? Theme.error : (root.nipeActive ? Theme.primary : Theme.surfaceVariantText)
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: root.isLoading ? "…" : (root.nipeActive ? "ON" : "OFF")
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: root.nipeActive ? Theme.primary : Theme.surfaceVariantText
                anchors.horizontalCenter: parent.horizontalCenter
            }

            HoverHandler {
                id: vPillHover
            }

            ToolTip {
                visible: vPillHover.hovered
                delay: 450
                timeout: 5000
                padding: Theme.spacingM
                contentItem: StyledText {
                    text: root.barTooltipText()
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                }
                background: StyledRect {
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                }
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

            Column {
                width: parent.width
                spacing: Theme.spacingM

                // ---- Status Banner ----
                StyledRect {
                    width: parent.width
                    height: statusBannerColumn.implicitHeight + Theme.spacingL * 2
                    radius: Theme.cornerRadius
                    color: root.nipeActive ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.16)
                                          : (root.errorMessage !== "" ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.15)
                                                                      : Theme.surfaceContainerHigh)

                    Rectangle {
                        width: parent.width
                        height: 3
                        radius: 2
                        visible: root.nipeActive
                        color: Theme.primary
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Column {
                        id: statusBannerColumn
                        anchors.fill: parent
                        anchors.margins: Theme.spacingL
                        spacing: Theme.spacingS

                        Row {
                            width: parent.width
                            spacing: Theme.spacingM

                            BusyIndicator {
                                width: 36
                                height: 36
                                running: root.isLoading
                                visible: running
                                anchors.verticalCenter: parent.verticalCenter
                                contentItem: Spinner {
                                    width: 30
                                    height: 30
                                }
                            }

                            DankIcon {
                                name: root.nipeActive ? "verified_user" : (root.errorMessage !== "" ? "error" : "security")
                                size: 36
                                visible: !root.isLoading
                                color: root.errorMessage !== "" ? Theme.error : (root.nipeActive ? Theme.primary : Theme.surfaceVariantText)
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 150
                                spacing: 2

                                StyledText {
                                    text: root.isLoading ? "Refreshing…" : (root.nipeActive ? "Tor Gateway Active" : (root.errorMessage !== "" ? "Attention Required" : "Tor Gateway Inactive"))
                                    font.pixelSize: Theme.fontSizeLarge
                                    font.weight: Font.Bold
                                    color: root.errorMessage !== "" ? Theme.error : (root.nipeActive ? Theme.primary : Theme.surfaceText)
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
                                width: chipRow.implicitWidth + Theme.spacingM * 2
                                height: 24
                                radius: 12
                                visible: !root.isLoading && root.errorMessage === ""
                                color: root.nipeActive ? Qt.rgba(Theme.success.r, Theme.success.g, Theme.success.b, 0.18) : Theme.surfaceContainer
                                anchors.verticalCenter: parent.verticalCenter

                                Row {
                                    id: chipRow
                                    anchors.centerIn: parent
                                    spacing: Theme.spacingXS

                                    Rectangle {
                                        width: 7
                                        height: 7
                                        radius: 3.5
                                        color: root.nipeActive ? Theme.success : Theme.surfaceVariantText
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    StyledText {
                                        text: root.nipeActive ? "LIVE" : "IDLE"
                                        font.pixelSize: 10
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
                                anchors.leftMargin: Theme.spacingM
                                anchors.rightMargin: Theme.spacingS
                                spacing: Theme.spacingS

                                DankIcon {
                                    name: "lan"
                                    size: Theme.iconSize - 2
                                    color: Theme.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 120
                                    spacing: 2

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
                            columns: 2
                            columnSpacing: Theme.spacingL
                            rowSpacing: Theme.spacingXS
                            width: parent.width

                            Column {
                                spacing: 1
                                visible: root.countryCode !== ""

                                StyledText {
                                    text: "Country"
                                    font.pixelSize: 10
                                    color: Theme.surfaceVariantText
                                }

                                StyledText {
                                    text: root.flagEmoji(root.countryCode) + "  " + (root.countryName || root.countryCode)
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceText
                                    font.weight: Font.Medium
                                }
                            }

                            Column {
                                spacing: 1
                                visible: root.city !== "" || root.region !== ""

                                StyledText {
                                    text: "City / Region"
                                    font.pixelSize: 10
                                    color: Theme.surfaceVariantText
                                }

                                StyledText {
                                    text: [root.city, root.region].filter(Boolean).join(", ")
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceText
                                }
                            }

                            Column {
                                spacing: 1
                                visible: root.org !== ""

                                StyledText {
                                    text: "Network / ASN"
                                    font.pixelSize: 10
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
                                width: parent.width - 160
                                spacing: 2

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
                                text: root.leakTestState === "testing" ? "Testing…" : "Run Leak Test"
                                iconName: root.leakTestState === "testing" ? "hourglass_top" : "fact_check"
                                anchors.verticalCenter: parent.verticalCenter
                                onClicked: root.runLeakTest()
                                enabled: !root.isLoading && root.leakTestState !== "testing"
                            }
                        }

                        // Leak result row
                        Row {
                            width: parent.width
                            visible: root.leakTestState !== "idle"
                            spacing: Theme.spacingM

                            BusyIndicator {
                                width: 20
                                height: 20
                                running: root.leakTestState === "testing"
                                visible: running
                                anchors.verticalCenter: parent.verticalCenter
                                contentItem: Spinner {
                                    width: 18
                                    height: 18
                                }
                            }

                            DankIcon {
                                name: {
                                    if (root.leakTestState === "ok") return "verified_user";
                                    if (root.leakTestState === "leak") return "gpp_bad";
                                    if (root.leakTestState === "error") return "report";
                                    return "utilities";
                                }
                                size: 18
                                visible: root.leakTestState !== "testing"
                                color: root.leakStateColor()
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Column {
                                width: parent.width - 40
                                spacing: 2
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

                // ---- Error / Warning Card ----
                StyledRect {
                    width: parent.width
                    height: errorColumn.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    visible: root.errorMessage !== ""
                    color: Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.15)

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
                            text: root.isLoading && root.statusText === "Starting..." ? "Starting…" : "Start"
                            iconName: "play_arrow"
                            width: actionRow.btnWidth
                            enabled: !root.isLoading && !root.nipeActive
                            onClicked: root.executeControl("start")
                        }

                        DankButton {
                            text: root.isLoading && root.statusText === "Stopping..." ? "Stopping…" : "Stop"
                            iconName: "stop"
                            width: actionRow.btnWidth
                            enabled: !root.isLoading && root.nipeActive
                            onClicked: root.executeControl("stop")
                        }

                        DankButton {
                            text: root.isLoading && root.statusText === "Restarting..." ? "Restarting…" : "Restart"
                            iconName: "refresh"
                            width: actionRow.btnWidth
                            enabled: !root.isLoading
                            onClicked: root.executeControl("restart")
                        }
                    }
                }

                // ---- Footer: dir path + refresh ----
                Row {
                    width: parent.width
                    spacing: Theme.spacingS

                    DankIcon {
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
                        width: parent.width - 110
                    }

                    Item {
                        width: Theme.spacingS
                        height: 1
                    }

                    DankButton {
                        iconName: "refresh"
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: root.refreshStatus()
                        enabled: !root.isLoading
                    }
                }
            }
        }
    }
}