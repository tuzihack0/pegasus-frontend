// Pegasus Frontend
import QtQuick 2.6

FocusScope {
    id: root
    property var game: null

    // ★ 新增：外部可传入配置目录（如主题已知自己的配置路径）
    property string configDir: ""    // 例如外层可传：configDir: "/storage/emulated/0/pegasus-frontend"

    readonly property int textSize: vpx(16)
    readonly property int titleTextSize: vpx(18)

    signal accept()
    signal cancel()

    focus: true
    anchors.fill: parent
    visible: shade.opacity > 0

    onActiveFocusChanged: state = activeFocus ? "open" : ""

    Keys.onPressed: {
        if (api.keys.isCancel(event) && !event.isAutoRepeat) {
            event.accepted = true;
            root.cancel();
        }
    }

    // ==================== ★ 映射 CSV 支持（无 Qt.labs.platform 版本） 开始 ====================
    property var nameMap: ({})
    property string resolvedConfigDir: ""
    property string resolvedMapFileName: "arcade.cvs"

    Component.onCompleted: {
        resolveConfigDir(function () {
            parseArcadeMapNameFromSettings(function () {
                loadArcadeCsv()
            })
        })
    }

    // 解析配置目录：优先用外部传入的 configDir；否则在常见路径中探测
    function resolveConfigDir(done) {
        var candidates = []

        // 1) 若外部传入，则第一优先
        if (configDir && configDir.length) candidates.push(String(configDir))

        // 2) Android 常见位置
        candidates.push("/storage/emulated/0/pegasus-frontend")
        candidates.push("/storage/emulated/0/Pegasus")
        candidates.push("/sdcard/pegasus-frontend")
        candidates.push("/sdcard/Pegasus")

        // 3) 通用兜底（不写盘符）
        candidates.push("/Pegasus")
        candidates.push("/Pegasus/config")

        // 去重 & 清洗
        var seen = {}, uniq = []
        for (var i=0;i<candidates.length;i++) {
            var p = String(candidates[i] || "").trim()
            if (!p) continue
            p = p.replace(/^file:\/\//, "")
            if (!seen[p]) { seen[p] = true; uniq.push(p) }
        }

        // 有 settings.txt 或 game_dirs.txt 的就认为是配置目录；否则用第一个
        var idx = 0
        function tryNext() {
            if (idx >= uniq.length) {
                resolvedConfigDir = uniq.length ? uniq[0] : ""
                done && done()
                return
            }
            var dir = uniq[idx++]
            fileExists(dir, "settings.txt", function (ok1) {
                if (ok1) { resolvedConfigDir = dir; done && done(); }
                else fileExists(dir, "game_dirs.txt", function (ok2) {
                    if (ok2) { resolvedConfigDir = dir; done && done(); }
                    else tryNext()
                })
            })
        }
        tryNext()
    }

    function fileExists(dir, name, cb) {
        var url = "file:///" + dir.replace(/\\/g,"/") + "/" + name
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE)
                cb(xhr.status === 0 || xhr.status === 200)
        }
        // 用 GET，避免某些平台 HEAD 不可用
        xhr.open("GET", url)
        xhr.send()
    }

    function parseArcadeMapNameFromSettings(done) {
        if (!resolvedConfigDir) { done && done(); return }
        var url = "file:///" + resolvedConfigDir.replace(/\\/g,"/") + "/settings.txt"
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 0 || xhr.status === 200) {
                    var txt = xhr.responseText || ""
                    // arcade_map=arcade.cvs / arcade_map : arcade_zh.cvs
                    var m = txt.match(/^\s*arcade_map\s*[:=]\s*(.+?)\s*$/mi)
                    if (m && m[1]) {
                        var fname = m[1].trim().replace(/^"+|"+$/g, "")
                        if (fname) resolvedMapFileName = fname
                    }
                }
                done && done()
            }
        }
        xhr.open("GET", url)
        xhr.send()
    }

    function loadArcadeCsv() {
        if (!resolvedConfigDir) { nameMap = ({}); return }
        var url = "file:///" + resolvedConfigDir.replace(/\\/g,"/") + "/" + resolvedMapFileName
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 0 || xhr.status === 200) {
                    nameMap = parseCsvToMap(xhr.responseText)
                } else {
                    console.warn("Arcade map not found:", url, "status:", xhr.status)
                    nameMap = ({})
                }
            }
        }
        xhr.open("GET", url)
        xhr.send()
    }

    function parseCsvToMap(text) {
        if (!text) return ({})
        // 处理 UTF-8 BOM
        if (text.charAt(0) === "\uFEFF") text = text.slice(1)

        var map = {}
        var lines = text.split(/\r?\n/)
        for (var i=0; i<lines.length; i++) {
            var line = lines[i].trim()
            if (!line || line.charAt(0) === '#') continue
            if (i === 0 && line.charAt(0) === "\uFEFF") line = line.slice(1)

            var parts = line.split("|")
            if (parts.length < 2) continue
            var key = parts[0].trim()
            var val = parts.slice(1).join("|").trim()
            if (i === 0 && key.toLowerCase() === "name") continue // 表头
            if (key) map[key.toLowerCase()] = val
        }
        return map
    }

    function keyFromFileName(anyPath) {
        if (!anyPath) return ""
        var base = String(anyPath).split(/[\\/]/).pop()
        var dot = base.lastIndexOf(".")
        if (dot > 0) base = base.slice(0, dot)
        return base.toLowerCase()
    }

    function displayNameFor(anyPathOrName) {
        var k = keyFromFileName(anyPathOrName)
        if (k && nameMap && nameMap.hasOwnProperty(k)) return nameMap[k]
        return String(anyPathOrName || "")
    }
    // ==================== ★ 映射 CSV 支持（无 Qt.labs.platform 版本） 结束 ====================

    Shade {
        id: shade
        onCancel: root.cancel()
    }

    MouseArea {
        anchors.centerIn: parent
        width: dialogBox.width
        height: dialogBox.height
    }

    Column {
        id: dialogBox
        width: parent.height * 0.66
        anchors.centerIn: parent
        scale: 0.5
        Behavior on scale { NumberAnimation { duration: 125 } }

        Rectangle {
            id: titleBar
            width: parent.width
            height: titleText.height
            color: "#444"

            Text {
                id: titleText
                width: parent.width
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("This game has multiple entries, which one would you like to launch?") + api.tr
                color: "#eee"
                font.pixelSize: root.titleTextSize
                font.family: globalFonts.sans
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.WordWrap
                padding: font.pixelSize
            }
        }

        Rectangle {
            width: parent.width
            height: Math.min(entryList.fullHeight, root.height * 0.5)
            color: "#333"

            ListView {
                id: entryList
                readonly property int itemHeight: root.textSize * 3
                readonly property int fullHeight: model.count * itemHeight

                anchors.fill: parent
                clip: true
                focus: true
                highlightRangeMode: ListView.ApplyRange
                preferredHighlightBegin: height * 0.5 - itemHeight * 0.5
                preferredHighlightEnd: height * 0.5 + itemHeight * 0.5

                model: game.files
                delegate: Rectangle {
                    readonly property bool highlighted: ListView.view.focus
                        && (ListView.isCurrentItem || mouseArea.containsMouse)

                    function launchEntry() {
                        modelData.launch()
                        root.accept()
                    }

                    width: dialogBox.width
                    height: entryList.itemHeight
                    color: highlighted ? "#585858" : "transparent"

                    Keys.onPressed: {
                        if (api.keys.isAccept(event) && !event.isAutoRepeat) {
                            event.accepted = true;
                            launchEntry();
                        }
                    }

                    Text {
                        id: label
                        anchors.centerIn: parent
                        // ★ 用映射名显示；fallback 到原名（有的构建 modelData.name 可能就是裸名）
                        text: displayNameFor(modelData.path || modelData.name)
                        color: "#eee"
                        font { pixelSize: root.textSize; family: globalFonts.sans }
                    }

                    MouseArea {
                        id: mouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: launchEntry()
                    }
                }
            }
        }
    }

    states: [
        State {
            name: "open"
            PropertyChanges { target: shade; opacity: 0.8 }
            PropertyChanges { target: dialogBox; scale: 1 }
        }
    ]
}
