// Pegasus Frontend
import QtQuick 2.6

FocusScope {
    id: root
    property var game: null

    // ★ 可选：外部传入配置目录
    property string configDir: ""

    readonly property int textSize: vpx(16)
    readonly property int titleTextSize: vpx(18)

    signal accept()
    signal cancel()

    focus: true
    anchors.fill: parent
    visible: shade.opacity > 0

    // 打开时动画
    onActiveFocusChanged: state = activeFocus ? "open" : ""

    Keys.onPressed: {
        if (api.keys.isCancel(event) && !event.isAutoRepeat) {
            event.accepted = true;
            root.cancel();
        }
    }

    // 下限：沿用原来的 0.66 * root.height
    readonly property real minDialogWidth: root.height * 0.66
    // 上限：屏幕 90%
    readonly property real maxDialogWidth: root.width  * 0.90

    // ==================== ★ 映射 CSV 支持（保持你原来的实现） ====================
    property var nameMap: ({})
    property int nameMapRev: 0

    property string resolvedConfigDir: ""
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
            if (idx >= uniq.length) { resolvedConfigDir = uniq.length ? uniq[0] : ""; done && done(); return }
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
            if (triedAlt) { nameMap = ({}); nameMapRev++; return }
            triedAlt = true
            var alt = resolvedMapFileName.match(/\.cvs$/i)
                ? resolvedMapFileName.replace(/\.cvs$/i, ".csv")
                : resolvedMapFileName.replace(/\.csv$/i, ".cvs")
            tryLoad(alt, function () { nameMap = ({}); nameMapRev++; })
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

    Shade { id: shade; onCancel: root.cancel() }

    MouseArea {
        anchors.centerIn: parent
        width: dialogBox.width
        height: dialogBox.height
    }

    Column {
        id: dialogBox

        // ★★ 宽度= max(标题需求, 列表最长文本+左右留白) 夹在 [min, max] 内
        width: {
            var needTitle = titleText.implicitWidth + titleText.padding * 2
            var needList  = entryList.maxLabelWidth + vpx(40)
            var need = Math.max(needTitle, needList)
            Math.min(Math.max(minDialogWidth, Math.ceil(need)), maxDialogWidth)
        }

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

                // ★★ 用来接收隐藏测量器给出的“最长文本宽度”
                property int maxLabelWidth: 0

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

                    function launchEntry() { modelData.launch(); root.accept() }

                    width: dialogBox.width
                    height: entryList.itemHeight
                    color: highlighted ? "#585858" : "transparent"

                    Keys.onPressed: {
                        if (api.keys.isAccept(event) && !event.isAutoRepeat) {
                            event.accepted = true; launchEntry();
                        }
                    }

                    Text {
                        id: label
                        // 为了“超过上限90%时自动换行”，显示用 Text 限宽 + WordWrap
                        width: dialogBox.width - vpx(40)
                        anchors.centerIn: parent
                        text: displayNameFor(modelData.path || modelData.name, nameMapRev)
                        color: "#eee"
                        font { pixelSize: root.textSize; family: globalFonts.sans }
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
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

    // ★★ 隐藏测量器：不显示、只负责计算最长 implicitWidth
    // 放在 dialogBox 外/内均可，这里放在 root 下
    Repeater {
        id: widthMeasurer
        model: game.files
        delegate: Text {
            visible: false                 // 不可见，不参与排版
            // 量“自然宽”，所以不要设 width，只看 implicitWidth
            text: displayNameFor(modelData.path || modelData.name, nameMapRev)
            font.pixelSize: root.textSize
            font.family: globalFonts.sans

            // 初次创建和文本变化时更新最大值
            function update() {
                if (implicitWidth > entryList.maxLabelWidth)
                    entryList.maxLabelWidth = implicitWidth
            }
            Component.onCompleted: update()
            onImplicitWidthChanged: update()
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
