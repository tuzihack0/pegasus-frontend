// Pegasus Frontend
import QtQuick 2.6

FocusScope {
    id: root
    property var game: null

    // ★ 外部可传入配置目录（如主题已知自己的配置路径）
    property string configDir: ""    // 例如："/storage/emulated/0/pegasus-frontend"

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
    // 修复点：增加 nameMapRev，作为依赖触发器，解决偶发不刷新问题
    property var nameMap: ({})
    property int nameMapRev: 0

    property string resolvedConfigDir: ""
    // 修复点：默认使用 .csv；后续会做 .csv/.cvs 互换重试
    property string resolvedMapFileName: "arcade.csv"

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

        // 2) Android 常见位置（你当前版本的精简列表）
        candidates.push("/storage/emulated/0/pegasus-frontend")

        // 3) 通用兜底（不写盘符）
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
        xhr.open("GET", url) // 用 GET，避免某些平台 HEAD 不可用
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
                    // arcade_map=arcade.csv / arcade_map : arcade_zh.csv
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

    // ★ 键与值规范化工具：小写、NFC、去空格、URL 解码
    function norm(s) {
        if (!s) return ""
        s = String(s)
        try { s = decodeURIComponent(s) } catch(e) {} // 容错 %20 等
        try { s = s.normalize("NFC") } catch(e) {}
        return s.trim().toLowerCase()
    }

    function baseName(p) {
        var s = String(p || "")
        try { s = decodeURIComponent(s) } catch(e) {}
        var parts = s.split(/[\\/]/)
        s = parts[parts.length-1] || s
        return s
    }

    // ★ 仅无扩展名键（cvs 内不含扩展名）
    function stemNoExt(p) {
        var b = baseName(p)
        var dot = b.lastIndexOf(".")
        return norm(dot > 0 ? b.slice(0, dot) : b)
    }

    function loadArcadeCsv() {
        if (!resolvedConfigDir) { nameMap = ({}); nameMapRev++; return }

        function tryLoad(fname, next) {
            var url = "file:///" + resolvedConfigDir.replace(/\\/g,"/") + "/" + fname
            var xhr = new XMLHttpRequest()
            xhr.onreadystatechange = function () {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if ((xhr.status === 0 || xhr.status === 200) && (xhr.responseText !== undefined && xhr.responseText !== null)) {
                        var text = xhr.responseText
                        if (text && text.length) {
                            nameMap = parseCsvToMap(text)
                            nameMapRev++   // ★ 强制依赖重算
                            return
                        }
                    }
                    next && next() // 失败则进入下一重试
                }
            }
            xhr.open("GET", url)
            xhr.send()
        }

        // 先按设置/默认的文件名加载，失败则尝试 .csv/.cvs 互换
        var triedAlt = false
        tryLoad(resolvedMapFileName, function () {
            if (triedAlt) {
                console.warn("Arcade map not found:", resolvedMapFileName)
                nameMap = ({})
                nameMapRev++     // ★ 失败也要触发一次重算
                return
            }
            triedAlt = true
            var alt = resolvedMapFileName.match(/\.cvs$/i)
                ? resolvedMapFileName.replace(/\.cvs$/i, ".csv")
                : resolvedMapFileName.replace(/\.csv$/i, ".cvs")
            tryLoad(alt, function () {
                console.warn("Arcade map not found:", resolvedMapFileName, "and", alt)
                nameMap = ({})
                nameMapRev++
            })
        })
    }

    function parseCsvToMap(text) {
        if (!text) return ({})
        // 处理 UTF-8 BOM
        if (text.charAt(0) === "\uFEFF") text = text.slice(1)

        var map = {}
        var lines = text.split(/\r?\n/)
        for (var i=0; i<lines.length; i++) {
            var raw = lines[i]
            if (!raw) continue
            var line = raw.trim()
            if (!line || line.charAt(0) === '#') continue

            var parts = line.split("|")
            if (parts.length < 2) continue
            var rawKey = parts[0].trim()
            var val = parts.slice(1).join("|").trim()

            // 去除特殊不可见空格（如 NO-BREAK SPACE），以防 csv 来源不同编辑器
            rawKey = rawKey.replace(/\u00A0/g, " ")
            val = val.replace(/\u00A0/g, " ")

            // 跳过表头：第一列为 "name"（不区分大小写）
            if (i === 0 && norm(rawKey) === "name") continue

            // ★ 仅写无扩展名键
            var noExt = stemNoExt(rawKey)
            if (noExt) map[noExt] = val
        }
        return map
    }

    function displayNameFor(anyPathOrName /* , rev 占位触发重算 */) {
        // ★ 依赖 nameMapRev：调用处会传入它来强制重算绑定
        var k = stemNoExt(anyPathOrName)
        if (nameMap && nameMap.hasOwnProperty(k)) return nameMap[k]

        // 友好回退：显示“文件名（无扩展名）”而非绝对路径
        var b = baseName(anyPathOrName)
        var dot = b.lastIndexOf(".")
        if (dot > 0) b = b.slice(0, dot)
        return b || String(anyPathOrName || "")
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
                // ★ 兼容 model.count / model.length 两种模型
                readonly property int countCompat: (model && model.count !== undefined) ? model.count
                                               : (model && model.length !== undefined) ? model.length : 0
                readonly property int fullHeight: countCompat * itemHeight

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
                        // ★ 带上 nameMapRev 触发重算；同时支持 path/name 两种来源
                        text: displayNameFor(modelData.path || modelData.name, nameMapRev)
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
