// Pegasus Frontend
import QtQuick 2.6

FocusScope {
    id: root
    property var game: null

    // 外部可传入配置目录（如主题已知自己的配置路径）
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

    // ==================== 映射 CSV 支持（无 Qt.labs.platform 版本） ====================
    // 修复点：增加 nameMapRev，作为依赖触发器，解决偶发不刷新问题
    property var nameMap: ({})
    property int nameMapRev: 0

    property string resolvedConfigDir: ""
    // 默认使用 .csv；会做 .csv/.cvs 互换重试
    property string resolvedMapFileName: "arcade.csv"

    Component.onCompleted: {
        resolveConfigDir(function () {
            parseArcadeMapNameFromSettings(function () {
                loadArcadeCsv()
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
                            nameMapRev++
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

    function displayNameFor(anyPathOrName) {
        var k = stemNoExt(anyPathOrName)
        if (nameMap && nameMap.hasOwnProperty(k)) return nameMap[k]

        var b = baseName(anyPathOrName)
        var dot = b.lastIndexOf(".")
        if (dot > 0) b = b.slice(0, dot)
        return b || String(anyPathOrName || "")
    }
    // ==================== /映射 CSV 支持 ====================


    // ==================== ★ 动态宽度：根据文本长度自适应 ====================
    // 最小宽度 = 原来比例；最大宽度 = 屏幕宽度 90%
    property real minDialogWidth: root.height * 0.66
    property real maxDialogWidth: root.width * 0.90
    property real autoDialogWidth: 0

    // 用于测量文字宽度（标题与列表项）
    FontMetrics { id: titleFontMetrics; font.pixelSize: root.titleTextSize; font.family: globalFonts.sans }
    FontMetrics { id: listFontMetrics;  font.pixelSize: root.textSize;      font.family: globalFonts.sans }

    // 触发计算：弹窗打开、映射更新、模型数量变化
    Timer {
        id: recomputeTimer
        interval: 0
        repeat: false
        onTriggered: recomputeDialogWidth()
    }
    onActiveFocusChanged: if (activeFocus) recomputeTimer.restart()
    onStateChanged: if (state === "open") recomputeTimer.restart()
    onNameMapRevChanged: recomputeTimer.restart()

    // 当列表条目数量变化时也重算（兼容 count / length）
    Connections {
        target: entryList
        onCountCompatChanged: recomputeTimer.restart()
    }

    function recomputeDialogWidth() {
        // 左右留白（用于条目文字视觉空间）
        var listPadding = vpx(40)
        var titlePadding = titleText ? titleText.padding * 2 : vpx(24)

        // 标题需要的宽度（单行宽度），标题 Text 已开启 wrap，当超过 max 会自动换行
        var needTitle = 0
        if (titleText && titleText.text && titleText.text.length) {
            needTitle = titleFontMetrics.advanceWidth(titleText.text) + titlePadding
        }

        // 列表项中最长的一条的宽度
        var needList = longestEntryTextWidth() + listPadding

        var need = Math.max(needTitle, needList)
        autoDialogWidth = Math.min(Math.max(minDialogWidth, Math.ceil(need)), maxDialogWidth)
    }

    function longestEntryTextWidth() {
        var m = entryList.model
        var maxw = 0
        var count = 0

        // 优先：完整遍历模型（若支持 get(i)）
        if (m && typeof m.count === "number") count = m.count
        else if (m && typeof m.length === "number") count = m.length

        if (m && typeof m.get === "function" && count > 0) {
            for (var i = 0; i < count; ++i) {
                var it = m.get(i)
                var txt = displayNameFor((it && (it.path || it.name)) || "")
                var w = listFontMetrics.advanceWidth(txt)
                if (w > maxw) maxw = w
            }
            return maxw
        }

        // 退化：扫描已创建的 delegate（只覆盖可见项）
        var kids = entryList.contentItem ? entryList.contentItem.children : []
        for (var j = 0; j < kids.length; ++j) {
            var child = kids[j]
            if (child && child.label && child.label.implicitWidth) {
                if (child.label.implicitWidth > maxw)
                    maxw = child.label.implicitWidth
            }
        }
        return maxw
    }
    // ==================== /动态宽度 ====================


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

        // ★ 核心：宽度取 min(max(最小宽度, 文字需求), 最大宽度)
        width: autoDialogWidth > 0 ? autoDialogWidth : Math.min(Math.max(minDialogWidth, root.width * 0.5), maxDialogWidth)

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
                // ★ 让标题宽度跟随对话框，从而在达到上限时自动换行
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

        // content area
        Rectangle {
            width: parent.width
            height: Math.min(entryList.fullHeight, root.height * 0.5)
            color: "#333"

            ListView {
                id: entryList
                readonly property int itemHeight: root.textSize * 3
                // 兼容 model.count / model.length
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
                        // 带上 nameMapRev 触发重算；同时支持 path/name 两种来源
                        text: displayNameFor(modelData.path || modelData.name, nameMapRev)
                        color: "#eee"
                        font { pixelSize: root.textSize; family: globalFonts.sans }
                        // 保持单行展示；如果你想列表项也可换行，可设 wrapMode，且配合 itemHeight 自适应
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
