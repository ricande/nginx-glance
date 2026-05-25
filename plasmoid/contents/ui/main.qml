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
    readonly property string fullCommandSource: homePath + "/bin/nginx-glance.sh --json"
    readonly property string sampleCommandSource: homePath + "/bin/nginx-glance.sh --sample-json"
    readonly property int fullRefreshMs: 20000
    readonly property int sampleMs: 500
    readonly property int waveformCapacity: 120
    readonly property int domainWaveCapacity: 80
    // Left column reserved for domain name + HTTP/HTTPS; waveform uses the rest (to the right).
    readonly property real domainTextSlotRatio: 0.38

    property var statusData: ({})
    property var waveformSamples: []
    property var domainWaveforms: ({})
    property string errorMessage: ""
    property bool scriptMissing: false
    property bool refreshRunning: false
    property bool sampleRunning: false
    property real liveHealthScore: 0
    property string liveState: ""

    readonly property bool hasData: root.statusData.summary !== undefined
        && root.errorMessage.length === 0
        && !root.scriptMissing
    readonly property bool isBusy: root.refreshRunning
        || (!root.hasData && !root.scriptMissing && root.errorMessage.length === 0)

    function waveformLineColor(): color {
        if (root.liveState === "error")
            return Kirigami.Theme.negativeTextColor
        if (root.liveState === "degraded")
            return Kirigami.Theme.neutralTextColor
        if (root.liveState === "ok")
            return Kirigami.Theme.positiveTextColor
        return Kirigami.Theme.disabledTextColor
    }

    function statusDotColor(): color {
        if (root.scriptMissing || root.errorMessage.length > 0)
            return Kirigami.Theme.negativeTextColor
        if (root.isBusy)
            return Kirigami.Theme.disabledTextColor
        if (root.liveState === "error")
            return Kirigami.Theme.negativeTextColor
        if (root.liveState === "degraded")
            return Kirigami.Theme.neutralTextColor
        if (root.liveState === "ok")
            return Kirigami.Theme.positiveTextColor
        return boolColor(root.statusData.nginx && root.statusData.nginx.ok)
    }

    function pushWaveformSample(score: real, state: string) {
        var list = root.waveformSamples.slice()
        list.push({ score: score, state: state })
        if (list.length > root.waveformCapacity)
            list = list.slice(list.length - root.waveformCapacity)
        root.waveformSamples = list
        root.liveHealthScore = score
        root.liveState = state
    }

    function waveformRange(): object {
        var min = 100, max = 0, i, s
        for (i = 0; i < root.waveformSamples.length; i++) {
            s = root.waveformSamples[i].score
            min = Math.min(min, s)
            max = Math.max(max, s)
        }
        if (root.waveformSamples.length === 0) {
            min = 0
            max = 100
        } else if (max - min < 3) {
            var mid = (min + max) / 2
            min = Math.max(0, mid - 8)
            max = Math.min(100, mid + 8)
        }
        return { min: min, max: max, span: Math.max(1, max - min) }
    }

    function waveformNormalize(score: real): real {
        var r = root.waveformRange()
        return (score - r.min) / r.span
    }

    function waveformIsFlat(): bool {
        var r = root.waveformRange()
        return root.waveformSamples.length > 2 && (r.max - r.min) < 3
    }

    function domainWaveformSamples(name: string): var {
        if (!name || !root.domainWaveforms)
            return []
        return root.domainWaveforms[name] || []
    }

    function pushDomainWaveform(name: string, activity: real) {
        if (!name)
            return
        var map = Object.assign({}, root.domainWaveforms)
        var list = (map[name] || []).slice()
        list.push({ activity: activity })
        if (list.length > root.domainWaveCapacity)
            list = list.slice(list.length - root.domainWaveCapacity)
        map[name] = list
        root.domainWaveforms = map
    }

    function domainActivityColor(activity: real): color {
        if (activity >= 70)
            return Kirigami.Theme.positiveTextColor
        if (activity >= 35)
            return Kirigami.Theme.neutralTextColor
        return Kirigami.Theme.negativeTextColor
    }

    function domainWaveNormalize(samples: var, score: real): real {
        var min = 100, max = 0, i, s
        for (i = 0; i < samples.length; i++) {
            s = samples[i].activity
            min = Math.min(min, s)
            max = Math.max(max, s)
        }
        if (samples.length === 0)
            return score / 100
        if (max - min < 3) {
            var mid = (min + max) / 2
            min = Math.max(0, mid - 8)
            max = Math.min(100, mid + 8)
        }
        return (score - min) / Math.max(1, max - min)
    }

    function syncDomainWaveformKeys() {
        var map = Object.assign({}, root.domainWaveforms)
        var domains = root.statusData.domains || []
        var i, name
        for (i = 0; i < domains.length; i++) {
            name = domains[i].name
            if (!name)
                continue
            if (!map[name])
                map[name] = []
        }
        root.domainWaveforms = map
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

    function refreshFull() {
        if (root.refreshRunning)
            return
        if (execSource.data[root.fullCommandSource] !== undefined)
            execSource.disconnectSource(root.fullCommandSource)
        root.refreshRunning = true
        execSource.connectSource(root.fullCommandSource)
    }

    function refreshSample() {
        if (root.sampleRunning || root.scriptMissing || !root.hasData)
            return
        if (execSource.data[root.sampleCommandSource] !== undefined)
            execSource.disconnectSource(root.sampleCommandSource)
        root.sampleRunning = true
        execSource.connectSource(root.sampleCommandSource)
    }

    function parseStdout(stdout: string) {
        if (!stdout || stdout.trim().length === 0) {
            root.errorMessage = qsTr("Empty response from nginx-glance.sh")
            return
        }
        try {
            root.statusData = JSON.parse(stdout)
            root.errorMessage = ""
            root.syncDomainWaveformKeys()
            if (root.statusData.health_score !== undefined)
                root.pushWaveformSample(root.statusData.health_score, root.statusData.state || "")
        } catch (e) {
            root.statusData = ({})
            root.errorMessage = qsTr("Invalid JSON from nginx-glance.sh")
        }
    }

    function handleSampleResult(exitCode: int, stdout: string) {
        if (exitCode !== 0 || !stdout || stdout.trim().length === 0)
            return
        try {
            const sample = JSON.parse(stdout)
            if (sample.mode !== "sample")
                return
            const score = sample.health_score !== undefined ? sample.health_score : 0
            root.pushWaveformSample(score, sample.state || "")
            const acts = sample.domain_activity || []
            for (let i = 0; i < acts.length; i++)
                root.pushDomainWaveform(acts[i].name, acts[i].activity)
        } catch (e) {
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
            root.refreshFull()
        else
            root.handleBackendResult(127, "")
    }

    Timer {
        interval: root.fullRefreshMs
        running: !root.scriptMissing
        repeat: true
        triggeredOnStart: false
        onTriggered: {
            if (!root.refreshRunning)
                root.refreshFull()
        }
    }

    Timer {
        interval: root.sampleMs
        running: root.hasData && !root.scriptMissing
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshSample()
    }

    P5S.DataSource {
        id: execSource
        engine: "executable"
        connectedSources: []

        onNewData: function(sourceName, data) {
            const exitCode = data["exit code"]
            const stdout = data["stdout"] || ""
            if (sourceName === root.fullCommandSource) {
                root.handleBackendResult(exitCode, stdout)
                root.finishRefresh()
                if (root.hasData)
                    root.refreshSample()
                return
            }
            if (sourceName === root.sampleCommandSource) {
                root.handleSampleResult(exitCode, stdout)
                root.sampleRunning = false
                if (execSource.data[root.sampleCommandSource] !== undefined)
                    execSource.disconnectSource(root.sampleCommandSource)
            }
        }
    }

    Timer {
        interval: 2000
        running: root.sampleRunning
        repeat: true
        onTriggered: root.sampleRunning = false
    }

    // Inline assignments only — avoid duplicate root children that stack at (0,0).
    compactRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.minimumHeight: Kirigami.Units.gridUnit * 16

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
                        visible: root.hasData
                        text: root.waveformIsFlat()
                            ? qsTr("Health %1% · steady").arg(Math.round(root.liveHealthScore))
                            : qsTr("Health %1%").arg(Math.round(root.liveHealthScore))
                        Layout.fillWidth: true
                        opacity: 0.85
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        color: root.waveformLineColor()
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

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                visible: root.hasData

                PC.Label {
                    text: qsTr("Health trend (not network traffic)")
                    opacity: 0.55
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    Layout.fillWidth: true
                }

                Item {
                    id: waveformArea
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 3

                    Rectangle {
                        anchors.fill: parent
                        radius: Kirigami.Units.smallSpacing
                        color: Kirigami.Theme.backgroundColor
                        opacity: 0.35
                        border.width: 1
                        border.color: Kirigami.Theme.disabledTextColor
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 1
                        color: Kirigami.Theme.disabledTextColor
                        opacity: 0.4
                    }

                    Row {
                        id: waveformRow
                        anchors.fill: parent
                        anchors.margins: 3
                        spacing: 1
                        bottomPadding: 0

                        Repeater {
                            model: root.waveformSamples
                            delegate: Rectangle {
                                required property var modelData
                                property real norm: root.waveformNormalize(modelData.score)

                                width: Math.max(2, (waveformRow.width
                                    - (root.waveformSamples.length - 1) * waveformRow.spacing)
                                    / Math.max(1, root.waveformSamples.length))
                                height: Math.max(2, waveformRow.height * (0.15 + 0.85 * norm))
                                anchors.bottom: parent.bottom
                                radius: 1
                                color: root.waveformLineColor()
                                opacity: 0.85
                            }
                        }
                    }

                    PC.Label {
                        anchors.centerIn: parent
                        visible: root.waveformSamples.length === 0
                        text: qsTr("Collecting…")
                        opacity: 0.5
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
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
                        id: domainRowItem
                        required property var modelData
                        width: detailsColumn.width
                        height: domainColumn.implicitHeight

                        ColumnLayout {
                            id: domainColumn
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: Kirigami.Units.smallSpacing

                        RowLayout {
                            id: domainRow
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            ColumnLayout {
                                id: domainTextSlot
                                Layout.preferredWidth: Math.max(
                                    Kirigami.Units.gridUnit * 10,
                                    detailsColumn.width * root.domainTextSlotRatio)
                                Layout.maximumWidth: detailsColumn.width * root.domainTextSlotRatio
                                spacing: Kirigami.Units.smallSpacing

                                PC.Label {
                                    text: modelData.name
                                    font.bold: true
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
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
                            }

                            Item {
                                id: domainWaveSlot
                                Layout.fillWidth: true
                                Layout.minimumWidth: Kirigami.Units.gridUnit * 5
                                Layout.preferredHeight: domainTextSlot.implicitHeight
                                clip: true

                                Rectangle {
                                    anchors.left: parent.left
                                    width: 1
                                    height: parent.height
                                    color: Kirigami.Theme.disabledTextColor
                                    opacity: 0.4
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.leftMargin: 1
                                    radius: Kirigami.Units.smallSpacing
                                    color: Kirigami.Theme.backgroundColor
                                    opacity: 0.25
                                }

                                Row {
                                    id: domainWaveRow
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    anchors.margins: 3
                                    spacing: 1

                                    Repeater {
                                        model: root.domainWaveformSamples(domainRowItem.modelData.name)
                                        delegate: Rectangle {
                                            required property var modelData
                                            property var samples: root.domainWaveformSamples(domainRowItem.modelData.name)
                                            property real norm: root.domainWaveNormalize(
                                                samples, modelData.activity)

                                            width: Math.max(2, (domainWaveRow.width
                                                - Math.max(0, samples.length - 1) * domainWaveRow.spacing)
                                                / Math.max(1, samples.length))
                                            height: Math.max(
                                                2, domainWaveRow.height * (0.12 + 0.88 * norm))
                                            anchors.bottom: parent.bottom
                                            radius: 1
                                            color: root.domainActivityColor(modelData.activity)
                                            opacity: 0.9
                                        }
                                    }
                                }

                                PC.Label {
                                    anchors.centerIn: parent
                                    visible: root.domainWaveformSamples(domainRowItem.modelData.name).length === 0
                                    text: qsTr("…")
                                    opacity: 0.45
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                }
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

                        ColumnLayout {
                            id: backendRow
                            anchors.fill: parent
                            spacing: 2
                            width: parent.width

                            PC.Label {
                                text: modelData.name && modelData.name.length > 0
                                    ? modelData.name
                                    : modelData.target
                                font.bold: modelData.name && modelData.name.length > 0
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                PC.Label {
                                    text: {
                                        var parts = [modelData.target]
                                        if (modelData.service && modelData.service.length > 0)
                                            parts.push(modelData.service)
                                        return parts.join(" · ")
                                    }
                                    opacity: 0.85
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                }
                                PC.Label {
                                    text: modelData.listening ? qsTr("up") : qsTr("down")
                                    color: boolColor(modelData.listening)
                                }
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
