import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC
import org.kde.plasma.plasma5support as P5S
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    readonly property string scriptPath: Qt.environment.HOME + "/bin/nginx-glance.sh"
    readonly property int refreshMs: 30000

    property var statusData: ({})
    property string errorMessage: ""
    property bool scriptMissing: false

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

    function refreshStatus() {
        if (execSource.data[root.scriptPath] !== undefined)
            execSource.disconnectSource(root.scriptPath)
        execSource.connectSource(root.scriptPath, ["--json"])
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

    Component.onCompleted: refreshStatus()

    Timer {
        interval: root.refreshMs
        running: !root.scriptMissing
        repeat: true
        triggeredOnStart: false
        onTriggered: root.refreshStatus()
    }

    P5S.DataSource {
        id: execSource
        engine: "executable"
        onNewData: function(sourceName, data) {
            if (sourceName !== root.scriptPath)
                return
            const exitCode = data["exit code"]
            const stdout = data["stdout"] || ""
            if (exitCode === 127 || (exitCode !== 0 && stdout.length === 0)) {
                root.scriptMissing = true
                root.errorMessage = qsTr("Script not found. Run: ./install.sh from the project folder.")
                return
            }
            if (exitCode !== 0 && stdout.length === 0) {
                root.errorMessage = qsTr("nginx-glance.sh failed (exit %1)").arg(exitCode)
                return
            }
            root.scriptMissing = false
            root.parseStdout(stdout)
        }
    }

    compactRepresentation: compactView
    fullRepresentation: fullView

    // --- Compact panel ---
    Item {
        id: compactView
        Layout.minimumWidth: Kirigami.Units.gridUnit * 12
        Layout.minimumHeight: Kirigami.Units.gridUnit * 10

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                PC.Label {
                    text: "Nginx Glance"
                    font.bold: true
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                Rectangle {
                    width: Kirigami.Units.iconSizes.smallMedium
                    height: width
                    radius: width / 2
                    color: root.scriptMissing || root.errorMessage.length > 0
                        ? Kirigami.Theme.negativeTextColor
                        : boolColor(root.statusData.nginx && root.statusData.nginx.ok)
                }
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
                visible: !root.scriptMissing && root.errorMessage.length === 0
                text: root.statusData.summary
                    ? qsTr("Domains %1/%2 · Ports %3 · Backends %4")
                        .arg(root.statusData.summary.domains_healthy)
                        .arg(root.statusData.summary.domains_total)
                        .arg(root.statusData.summary.ports_listening)
                        .arg(root.statusData.summary.backends_ok)
                    : qsTr("Loading…")
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }

            PC.Label {
                visible: root.statusData.timestamp
                text: root.statusData.timestamp || ""
                opacity: 0.75
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }
    }

    // --- Expanded view ---
    ScrollView {
        id: fullView
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumWidth: Kirigami.Units.gridUnit * 22
        Layout.minimumHeight: Kirigami.Units.gridUnit * 18
        clip: true

        ColumnLayout {
            width: fullView.availableWidth
            spacing: Kirigami.Units.mediumSpacing

            Kirigami.Heading {
                level: 2
                text: "Nginx Glance"
            }

            PC.Label {
                visible: root.scriptMissing || root.errorMessage.length > 0
                text: root.scriptMissing
                    ? qsTr("Cannot find %1. From the project folder run: ./install.sh").arg(root.scriptPath)
                    : root.errorMessage
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                color: Kirigami.Theme.negativeTextColor
            }

            RowLayout {
                visible: !root.scriptMissing && root.errorMessage.length === 0
                Layout.fillWidth: true
                PC.Label { text: qsTr("nginx.service"); Layout.fillWidth: true }
                PC.Label {
                    text: root.statusData.nginx ? root.statusData.nginx.status : "—"
                    color: boolColor(root.statusData.nginx && root.statusData.nginx.ok)
                }
            }

            Kirigami.Separator { Layout.fillWidth: true }

            Kirigami.Heading {
                level: 3
                text: qsTr("Domains")
            }

            Repeater {
                model: root.statusData.domains || []
                delegate: ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    PC.Label {
                        text: modelData.name
                        font.bold: true
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        PC.Label { text: "HTTP"; Layout.preferredWidth: Kirigami.Units.gridUnit * 4 }
                        PC.Label {
                            text: modelData.http.line || modelData.http.level
                            color: levelColor(modelData.http.level)
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        PC.Label { text: "HTTPS"; Layout.preferredWidth: Kirigami.Units.gridUnit * 4 }
                        PC.Label {
                            text: modelData.https.line || modelData.https.level
                            color: levelColor(modelData.https.level)
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                        }
                    }
                    Kirigami.Separator { Layout.fillWidth: true }
                }
            }

            Kirigami.Heading {
                level: 3
                text: qsTr("Ports")
                visible: (root.statusData.ports || []).length > 0
            }

            Repeater {
                model: root.statusData.ports || []
                delegate: RowLayout {
                    Layout.fillWidth: true
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

            Kirigami.Heading {
                level: 3
                text: qsTr("Backends")
                visible: (root.statusData.backends || []).length > 0
            }

            Repeater {
                model: root.statusData.backends || []
                delegate: RowLayout {
                    Layout.fillWidth: true
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

            Kirigami.Separator { Layout.fillWidth: true }

            PC.Label {
                text: root.statusData.system
                    ? qsTr("CPU %1 · %2 · Disk %3")
                        .arg(root.statusData.system.cpu_load)
                        .arg(root.statusData.system.memory)
                        .arg(root.statusData.system.disk_root)
                    : ""
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                opacity: 0.85
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }

            PC.Label {
                text: (root.statusData.host || "") + " · " + (root.statusData.timestamp || "")
                opacity: 0.65
                Layout.fillWidth: true
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }
    }
}
