// Pegasus Frontend
// Copyright (C) ...
import QtQuick 2.6
import Qt.labs.platform 1.1    // ★ 用于 StandardPaths 跨平台定位配置目录

FocusScope {
    id: root

    property var game: null

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

    // =========================== ★ 新增：外部映射（CSV/TXT）支持 开始 ===========================
    // 解析后得到的映射表：{ "1941": "1941: 反击战 (世界版 900227)", ... }
    property var nameMap: ({})
    // 解析出的最终配置目录（调试可打印）
    property string resolvedConfigDir: ""
    // 解析出的最终映射文件名（默认 arcade.cvs，可被 settings.txt 的 arcade_map= 覆盖）
    property string resolvedMapFileName: "arcade.cvs"

    Component.onCompleted: {
        // 1) 解析配置目录（跨平台）→ 2) 从 settings.txt 解析映射文件名 → 3) 读取 CSV
        resolveConfigDir(function() {
            parseArcadeMapNameFromSettings(function() {
                loadArcadeCsv()
            })
        })
    }

    // —— 第一步：跨平台定位配置目录（优先 AppConfig/ConfigLocation；其次兜底路径） ——
    function resolveConfigDir(done) {
        var candidates = []

        function pushAll(arr) { for (var i=0;i<arr.length;i++) if (arr[i]) candidates.push(arr[i]) }
        var wr
        wr = StandardPaths.writableLocation(StandardPaths.AppConfigLocation); if (wr) candidates.push(wr)
        wr = StandardPaths.writableLocation(StandardPaths.ConfigLocation);   if (wr) candidates.push(wr)
        pushAll(StandardPaths.standardLocations(StandardPaths.AppConfigLocation))
        pushAll(StandardPaths.standardLocations(StandardPaths.ConfigLocation))

        // Windows 的一个常见兜底（不影响其他平台）
        if (Qt.platform.os === "windows" || Qt.platform.os === "linux" || Qt.platform.os === "osx")
            candidates.push("/Pegasus/config")

        // 去重与格式化（把 file:/// 开头转成本地路径）
        var seen = {}, uniq = []
        for (var i=0;i<candidates.length;i++) {
            var p = String(candidates[i] || "").trim()
            if (!p) continue
            p = p.replace(/^file:\/\//, "")
            if (!seen[p]) { seen[p]=true; uniq.push(p) }
        }

        // 在候选目录里探测是否存在 settings.txt 或 game_dirs.txt，命中则采用
        var i = 0
        function tryNext() {
            if (i >= uniq.length) {
                resolvedConfigDir = uniq.length ? uniq[0] : ""
                done && done()
                return
            }
            var dir = uniq[i++]
            // 只要有 settings.txt 或 game_dirs.txt 任一即可判定为配置目录
            fileExists(dir, "settings.txt", function(ok1) {
                if (ok1) { resolvedConfigDir = dir; done && done(); }
                else fileExists(dir, "game_dirs.txt", function(ok2) {
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
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE)
                cb(xhr.status === 0 || xhr.status === 200)
        }
        // 有些平台 HEAD 不一定可用，直接 GET 也很轻量
        xhr.open("GET", url)
        xhr.send()
    }

    // —— 第二步：若 settings.txt 里有 arcade_map=xxx.cvs，则覆盖默认映射名 ——
    function parseArcadeMapNameFromSettings(done) {
        if (!resolvedConfigDir) { done && done(); return }
        var url = "file:///" + resolvedConfigDir.replace(/\\/g,"/") + "/settings.txt"
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 0 || xhr.status === 200) {
                    var txt = xhr.responseText || ""
                    // 支持：arcade_map=arcade.cvs 或 arcade_map : arcade_zh.cvs
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

    // —— 第三步：读取 CSV/TXT 并解析成映射表 ——（首行可为 name|游戏版本 表头）
    function loadArcadeCsv() {
        if (!resolvedConfigDir) { nameMap = ({}); return }
        var url = "file:///" + resolvedConfigDir.replace(/\\/g,"/") + "/" + resolvedMapFileName
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
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
        // 处理行首 BOM（极少数编辑器会只在首行保留）
        if (i === 0 && line.charAt(0) === "\uFEFF") line = line.slice(1)

        var parts = line.split("|")
        if (parts.length < 2) continue

        var key = parts[0].trim()
        var val = parts.slice(1).join("|").trim()

        if (i === 0 && key.toLowerCase() === "name") continue // 跳过表头
        if (key) map[key.toLowerCase()] = val
    }
    return map
}

    // —— 工具：将模型给的文件名/路径转为映射 key（去路径、去扩展名、小写） ——
    function keyFromFileName(anyPath) {
        if (!anyPath) return ""
        var base = String(anyPath).split(/[\\/]/).pop()
        var dot = base.lastIndexOf(".")
        if (dot > 0) base = base.slice(0, dot)
        return base.toLowerCase()
    }

    // —— 对外：供 delegate 显示文本使用 ——（找不到映射则回退原名，不影响启动）
    function displayNameFor(anyPathOrName) {
        var k = keyFromFileName(anyPathOrName)
        if (k && nameMap && nameMap.hasOwnProperty(k)) return nameMap[k]
        return String(anyPathOrName || "")
    }
    // =========================== ★ 新增：外部映射（CSV/TXT）支持 结束 ===========================

    Shade {
        id: shade
        onCancel: root.cancel()
    }

    // actual dialog
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

        // title bar
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

        // content area
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
                        modelData.launch(); // 保持原启动逻辑不变
                        root.accept();
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
                        // ★ 改这里：用映射名称显示；找不到则显示原本的 modelData.name
                        text: displayNameFor(modelData.name)
                        color: "#eee"
                        font {
                            pixelSize: root.textSize
                            family: globalFonts.sans
                        }
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
