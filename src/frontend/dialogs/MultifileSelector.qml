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

    property real minDialogWidth: root.height * 0.66
    // 上限 = 屏幕 90%
    property real maxDialogWidth: root.width * 0.90
    // 动态计算结果
    property real autoDialogWidth: 0

    // 下一帧触发，避免初次创建时尺寸未就绪
    Timer {
        id: recomputeTimer
        interval: 0
        repeat: false
        onTriggered: recomputeDialogWidth()
    }

    // 打开时设置状态 + 重新计算宽度
    onActiveFocusChanged: {
        state = activeFocus ? "open" : ""
        if (activeFocus) recomputeTimer.restart()
    }

    // CSV 名称映射变化时，可能影响 label 文本 => 重新测量
    onNameMapRevChanged: recomputeTimer.restart()

    function recomputeDialogWidth() {
        // 标题需要的宽（implicitWidth + padding*2）
        var needTitle = (titleText ? (titleText.implicitWidth + titleText.padding * 2) : 0)

        // 列表可见项里最长文本的宽（使用 delegate 的 label.implicitWidth）
        var maxVisible = 0
        var kids = entryList.contentItem ? entryList.contentItem.children : []
        for (var i = 0; i < kids.length; ++i) {
            var d = kids[i]
            if (d && d.label && d.label.implicitWidth && d.label.implicitWidth > maxVisible)
                maxVisible = d.label.implicitWidth
        }
        // 给列表左右留一点空白
        var needList = maxVisible + vpx(40)

        var need = Math.max(needTitle, needList)
        autoDialogWidth = Math.min(Math.max(minDialogWidth, Math.ceil(need)), maxDialogWidth)
    }

    // （可选）在进入 open 状态后再刷新一次，防止异步创建导致第一次测量偏小
    Timer {
        interval: 50
        running: state === "open"
        repeat: false
        onTriggered: recomputeTimer.restart()
    }
    // === 自适应宽度结束 ===

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
                // CSV 可能刚加载完成，补一次计算
                recomputeTimer.restart()
            })
        })
    }

    function resolveConfigDir(done) {
        var candidates = []
        if (configDir && configDir.length) candidates.push(String(configDir))
        candidates.push("/storage/emulated/0/pegasus-frontend")
        candidates.push("/Pegasus/config")
        var seen = {}, uniq = []
        for (var i=0;i<candidates.length;i++) {
            var p = String(candidates[i] || "").trim()
            if (!p) continue
            p = p.replace(/^file:\/\//, "")
            if (!seen[p]) { seen[p] = true; uniq.push(p) }
        }
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

    function norm(s) {
        if (!s) return ""
        s = String(s)
        try { s = decodeURIComponent(s) } catch(e) {}
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
                    next && next()
                }
            }
            xhr.open("GET", url)
            xhr.send()
        }

        var triedAlt = false
        tryLoad(resolvedMapFileName, function () {
            if (triedAlt) {
                console.warn("Arcade map not found:", resolvedMapFileName)
                nameMap = ({})
                nameMapRev++
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

            rawKey = rawKey.replace(/\u00A0/g, " ")
            val = val.replace(/\u00A0/g, " ")

            if (i === 0 && norm(rawKey) === "name") continue

            var noExt = stemNoExt(rawKey)
            if (noExt) map[noExt] = val
        }
        return map
    }

    function displayNameFor(anyPathOrName /* , rev 占位触发重算 */) {
        var k = stemNoExt(anyPathOrName)
        if (nameMap && nameMap.hasOwnProperty(k)) return nameMap[k]
        var b = baseName(anyPathOrName)
        var dot = b.lastIndexOf(".")
        if (dot > 0) b = b.slice(0, dot)
        return b || String(anyPathOrName || "")
    }
    // ==================== ★ 映射 CSV 支持 结束 ====================

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
        width: autoDialogWidth > 0 ? autoDialogWidth : minDialogWidth
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
                width: dialogBox.width
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
                        text: displayNameFor(modelData.path || modelData.name, nameMapRev)
                        color: "#eee"
                        font { pixelSize: root.textSize; family: globalFonts.sans }
                        elide: Text.ElideRight 
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
