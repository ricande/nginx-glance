import QtQuick
import QtQuick.Layouts
import QtCore
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5S
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // Home: StandardPaths is reliable on Plasma 6; Qt.environment.HOME is fallback only.
    readonly property string homePath: {
        const homeUrl = StandardPaths.writableLocation(StandardPaths.HomeLocation)
        if (homeUrl) {
            const path = homeUrl.toString().replace(/^file:\/\//, "")
            if (path.length > 0)
                return path
        }
        return Qt.environment.HOME || ""
    }
    readonly property string commandSource: homePath + "/bin/nginx-glance.sh --json"
    readonly property int refreshMs: 30000

    property var statusData: ({})
    property string errorMessage: ""
    property bool scriptMissing: false
    property bool refreshRunning: false

    readonly property bool hasData: root.statusData.summary !== undefined
        && root.errorMessage.length === 0
        && !root.scriptMissing
    readonly property bool isBusy: root.refreshRunning
        || (!root.hasData && !root.scriptMissing && root.errorMessage.length === 0)

    function statusDotColor(): color {
        if (root.scriptMissing || root.errorMessage.length > 0)
            return Kirigami.Theme.negativeTextColor
        if (root.isBusy)
            return Kirigami.Theme.disabledTextColor
        return boolColor(root.statusData.nginx && root.statusData.nginx.ok)
    }

    function levelColor(level: string): color {
        switch (level) {
        case "ok": return Kirigami.Theme.positiveTextColor
        case "warn": return Kirigami.Theme.neutralTextColor
        default: return Kirigami.Theme.negativeTextColor
        }
    }

    function boolColor(ok: bool): color {
        return ok ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
    }

    function compactTimestampText(): string {
        const ts = root.statusData.timestamp || ""
        if (ts.length === 0)
            return ""
        const space = ts.indexOf(" ")
        return space > 0 ? ts.substring(space + 1) : ts
    }

    function finishRefresh() {
        root.refreshRunning = false
    }

    function refreshStatus() {
        if (root.refreshRunning)
            return
        if (execSource.data[root.commandSource] !== undefined)
            execSource.disconnectSource(root.commandSource)
        root.refreshRunning = true
        execSource.connectSource(root.commandSource)
    }

    function parseStdout(stdout: string) {
        if (!stdout || stdout.trim().length === 0) {
            root.errorMessage = qsTr("Empty response from nginx-glance.sh")
            return
        }
        try {
            root.statusData = JSON.parse(stdout)
            root.errorMessage = ""
        } catch (e) {
            root.statusData = ({})
            root.errorMessage = qsTr("Invalid JSON from nginx-glance.sh")
        }
    }

    function handleBackendResult(exitCode: int, stdout: string) {
        root.scriptMissing = false

        if (root.homePath.length === 0) {
            root.scriptMissing = true
            root.errorMessage = qsTr("Cannot resolve home directory for nginx-glance.sh.")
            return
        }

        if (exitCode === 127) {
            root.scriptMissing = true
            root.errorMessage = qsTr("Script not found. Run: ./install.sh from the project folder.")
            return
        }

        if (exitCode !== 0) {
            root.errorMessage = qsTr("nginx-glance.sh failed (exit %1)").arg(exitCode)
            return
        }

        root.parseStdout(stdout)
    }

    Component.onCompleted: {
        if (root.homePath.length > 0)
            refreshStatus()
        else
            handleBackendResult(127, "")
    }

    Timer {
        interval: root.refreshMs
        running: !root.scriptMissing
        repeat: true
        triggeredOnStart: false
        onTriggered: {
            if (!root.refreshRunning)
                root.refreshStatus()
        }
    }

    P5S.DataSource {
        id: execSource
        engine: "executable"
        connectedSources: []

        onNewData: function(sourceName, data) {
            if (sourceName !== root.commandSource)
                return
            const exitCode = data["exit code"]
            const stdout = data["stdout"] || ""
            root.handleBackendResult(exitCode, stdout)
            root.finishRefresh()
        }
    }

    // Inline assignments only — avoid duplicate root children that stack at (0,0).
    compactRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 12
        Layout.minimumHeight: Kirigami.Units.gridUnit * 10

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Rectangle {
                    width: Kirigami.Units.iconSizes.medium
                    height: width
                    radius: width / 2
                    color: root.statusDotColor()
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    PC.Label {
                        text: "Nginx Glance"
                        font.bold: true
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    PC.Label {
                        visible: root.scriptMissing || root.errorMessage.length > 0
                        text: root.scriptMissing ? qsTr("Install: ./install.sh") : root.errorMessage
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        color: Kirigami.Theme.negativeTextColor
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                    }

                    PC.Label {
                        visible: root.isBusy && root.errorMessage.length === 0 && !root.scriptMissing
                        text: qsTr("Loading…")
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        opacity: 0.85
                        color: Kirigami.Theme.disabledTextColor
                    }

                    PC.Label {
                        visible: root.hasData
                        text: qsTr("Domains %1/%2 · Ports %3 · Backends %4")
                            .arg(root.statusData.summary.domains_healthy)
                            .arg(root.statusData.summary.domains_total)
                            .arg(root.statusData.summary.ports_listening)
                            .arg(root.statusData.summary.backends_ok)
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                    }

                    PC.Label {
                        visible: root.hasData && root.statusData.timestamp
                        text: qsTr("Updated %1").arg(root.compactTimestampText())
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        opacity: 0.65
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        color: Kirigami.Theme.disabledTextColor
                    }
                }
            }
        }
    }

    fullRepresentation: PlasmaExtras.Representation {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 22
        Layout.minimumHeight: Kirigami.Units.gridUnit * 18
        collapseMarginsHint: true

        Flickable {
            id: detailsFlickable
            anchors.fill: parent
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: detailsColumn.height

            Column {
                id: detailsColumn
                width: detailsFlickable.width
                spacing: Kirigami.Units.mediumSpacing
                topPadding: Kirigami.Units.smallSpacing
                bottomPadding: Kirigami.Units.smallSpacing

                Row {
                    width: parent.width
                    spacing: Kirigami.Units.smallSpacing
                    Rectangle {
                        width: Kirigami.Units.iconSizes.smallMedium
                        height: width
                        radius: width / 2
                        color: root.statusDotColor()
                    }
                    Kirigami.Heading {
                        level: 2
                        text: "Nginx Glance"
                        width: parent.width - Kirigami.Units.iconSizes.smallMedium - parent.spacing
                    }
                }

                PC.Label {
                    width: parent.width
                    visible: root.isBusy && !root.scriptMissing && root.errorMessage.length === 0
                    text: qsTr("Loading status…")
                    opacity: 0.85
                    color: Kirigami.Theme.disabledTextColor
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }

                PC.Label {
                    width: parent.width
                    visible: root.scriptMissing || root.errorMessage.length > 0
                    text: root.scriptMissing
                        ? qsTr("Cannot find backend. From the project folder run: ./install.sh")
                        : root.errorMessage
                    wrapMode: Text.WordWrap
                    color: Kirigami.Theme.negativeTextColor
                }

                PC.Label {
                    width: parent.width
                    visible: root.hasData
                    text: qsTr("%1 of %2 domains healthy · %3 ports up · %4 backends up")
                        .arg(root.statusData.summary.domains_healthy)
                        .arg(root.statusData.summary.domains_total)
                        .arg(root.statusData.summary.ports_listening)
                        .arg(root.statusData.summary.backends_ok)
                    wrapMode: Text.WordWrap
                    opacity: 0.9
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }

                Item {
                    width: parent.width
                    height: nginxRow.implicitHeight
                    visible: root.hasData
                    RowLayout {
                        id: nginxRow
                        anchors.fill: parent
                        PC.Label { text: qsTr("nginx.service"); Layout.fillWidth: true }
                        PC.Label {
                            text: root.statusData.nginx ? root.statusData.nginx.status : "—"
                            color: boolColor(root.statusData.nginx && root.statusData.nginx.ok)
                            font.bold: true
                        }
                    }
                }

                Kirigami.Separator {
                    width: parent.width
                    visible: root.hasData
                }

                Kirigami.Heading {
                    level: 3
                    width: parent.width
                    text: qsTr("Domains")
                    visible: root.hasData
                }

                Repeater {
                    model: root.hasData ? (root.statusData.domains || []) : []
                    delegate: Item {
                        required property var modelData
                        width: detailsColumn.width
                        height: domainBlock.implicitHeight

                        ColumnLayout {
                            id: domainBlock
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: Kirigami.Units.smallSpacing

                            PC.Label {
                                text: modelData.name
                                font.bold: true
                                Layout.fillWidth: true
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                PC.Label {
                                    text: "HTTP"
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                                    opacity: 0.8
                                }
                                PC.Label {
                                    text: modelData.http.level === "ok"
                                        ? qsTr("OK")
                                        : (modelData.http.line || modelData.http.level)
                                    color: levelColor(modelData.http.level)
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                PC.Label {
                                    text: "HTTPS"
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                                    opacity: 0.8
                                }
                                PC.Label {
                                    text: modelData.https.level === "ok"
                                        ? qsTr("OK")
                                        : (modelData.https.line || modelData.https.level)
                                    color: levelColor(modelData.https.level)
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }
                            }
                            Kirigami.Separator { Layout.fillWidth: true }
                        }
                    }
                }

                Kirigami.Heading {
                    level: 3
                    width: parent.width
                    text: qsTr("Ports")
                    visible: root.hasData && (root.statusData.ports || []).length > 0
                }

                Repeater {
                    model: root.hasData ? (root.statusData.ports || []) : []
                    delegate: Item {
                        required property var modelData
                        width: detailsColumn.width
                        height: portRow.implicitHeight
                        visible: height > 0

                        RowLayout {
                            id: portRow
                            anchors.fill: parent
                            PC.Label {
                                text: qsTr("port %1").arg(modelData.port)
                                Layout.fillWidth: true
                            }
                            PC.Label {
                                text: modelData.listening ? qsTr("listening") : qsTr("not listening")
                                color: boolColor(modelData.listening)
                            }
                        }
                    }
                }

                Kirigami.Heading {
                    level: 3
                    width: parent.width
                    text: qsTr("Backends")
                    visible: root.hasData && (root.statusData.backends || []).length > 0
                }

                Repeater {
                    model: root.hasData ? (root.statusData.backends || []) : []
                    delegate: Item {
                        required property var modelData
                        width: detailsColumn.width
                        height: backendRow.implicitHeight

                        RowLayout {
                            id: backendRow
                            anchors.fill: parent
                            PC.Label {
                                text: modelData.target
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                            PC.Label {
                                text: modelData.listening ? qsTr("up") : qsTr("down")
                                color: boolColor(modelData.listening)
                            }
                        }
                    }
                }

                Kirigami.Separator {
                    width: parent.width
                    visible: root.hasData
                }

                PC.Label {
                    width: parent.width
                    visible: root.hasData && root.statusData.system
                    text: qsTr("CPU %1 · %2 · Disk %3")
                        .arg(root.statusData.system.cpu_load)
                        .arg(root.statusData.system.memory)
                        .arg(root.statusData.system.disk_root)
                    wrapMode: Text.WordWrap
                    opacity: 0.85
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }

                PC.Label {
                    width: parent.width
                    visible: root.hasData
                    text: (root.statusData.host || "") + " · " + (root.statusData.timestamp || "")
                    opacity: 0.65
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
            }
        }
    }
}
