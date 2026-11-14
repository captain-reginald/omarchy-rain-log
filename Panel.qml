import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "rainlog"
  ipcTarget: "rainlog"
  manageIpc: true

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property var entries: ({})

  property bool historyMode: false
  property bool settingsMode: false
  property bool editingCustom: false

  function setting(name, fallback) {
    var value = (root.settings ? root.settings[name] : undefined)
    return value === undefined || value === null ? fallback : value
  }

  readonly property string dataPath: String(root.setting("dataPath", Quickshell.env("HOME") + "/Documents/rainlog.json"))
  readonly property int customDays: {
    var v = parseInt(root.setting("customDays", 14), 10)
    return isNaN(v) || v < 1 ? 14 : v
  }

  FileView {
    id: dataFile
    path: root.dataPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadText(text())
    onLoadFailed: {
      root.entries = ({})
      Qt.callLater(function() { root.save() })
    }
  }

  function loadText(text) {
    try {
      var parsed = JSON.parse(String(text || "{}"))
      if (parsed && parsed.entries && typeof parsed.entries === "object") root.entries = parsed.entries
      else root.entries = ({})
    } catch (e) {
      root.entries = ({})
    }
  }

  function save() {
    try {
      dataFile.setText(JSON.stringify({ entries: root.entries }, null, 2))
    } catch (e) {
      console.warn("rainlog save failed", e)
    }
  }

  function updateSetting(key, value) {
    var entry = { id: root.moduleName }
    if (root.settings) for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
    entry[key] = value
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function todayKey() { return Model.dateKey(new Date()) }

  function adjustOffset(key, delta) {
    if (key === "24") root.off24 = Math.max(0, root.off24 + delta)
    else if (key === "72") root.off72 = Math.max(0, root.off72 + delta)
    else if (key === "week") root.offWeek = Math.max(0, root.offWeek + delta)
    else if (key === "month") root.offMonth = Math.max(0, root.offMonth + delta)
    else if (key === "season") root.offSeason = Math.max(0, root.offSeason + delta)
    else if (key === "custom") root.offCustom = Math.max(0, root.offCustom + delta)
  }

  property int off24: 0
  property int off72: 0
  property int offWeek: 0
  property int offMonth: 0
  property int offSeason: 0
  property int offCustom: 0

  function sumWindowDays(n, offset) {
    var today = new Date()
    today.setHours(12, 0, 0, 0)
    var end = Model.addDays(today, -offset * n)
    var start = Model.addDays(end, -(n - 1))
    return Model.sumEntries(root.entries, start, end)
  }

  function monthWindow(offset) {
    var ref = new Date()
    ref.setDate(1)
    ref.setMonth(ref.getMonth() - offset)
    var start = new Date(ref.getFullYear(), ref.getMonth(), 1, 12)
    var end = new Date(ref.getFullYear(), ref.getMonth() + 1, 0, 12)
    return { start: start, end: end }
  }

  function seasonWindow(offset) {
    var ref = new Date()
    ref.setMonth(ref.getMonth() - offset * 3)
    var start = Model.seasonStart(ref)
    var end = new Date(start.getTime())
    end.setMonth(end.getMonth() + 3)
    end.setDate(end.getDate() - 1)
    end.setHours(12, 0, 0, 0)
    return { start: start, end: end, name: Model.seasonName(start) }
  }

  readonly property int total24: sumWindowDays(1, off24)
  readonly property int total72: sumWindowDays(3, off72)
  readonly property int totalWeek: sumWindowDays(7, offWeek)
  readonly property int totalCustom: sumWindowDays(root.customDays, offCustom)

  // The bar always reports today, even while the popup is scrolled back.
  readonly property int todayTotal: sumWindowDays(1, 0)

  // Bar count settings: hidden by default, and the chosen range always uses
  // the current period rather than the popup's scrolled view.
  readonly property bool showBarCount: root.setting("showBarCount", false) === true
  readonly property string barCountRange: {
    var v = String(root.setting("barCountRange", "day"))
    return ["day", "week", "month", "season", "year"].indexOf(v) >= 0 ? v : "day"
  }
  readonly property int barCountTotal: {
    if (barCountRange === "week") return sumWindowDays(7, 0)
    if (barCountRange === "month") {
      var m = monthWindow(0)
      return Model.sumEntries(root.entries, m.start, m.end)
    }
    if (barCountRange === "season") {
      var s = seasonWindow(0)
      return Model.sumEntries(root.entries, s.start, s.end)
    }
    if (barCountRange === "year") {
      var y = new Date().getFullYear()
      return Model.sumEntries(root.entries, new Date(y, 0, 1, 12), new Date(y, 11, 31, 12))
    }
    return todayTotal
  }
  readonly property string barLabel: root.showBarCount ? Model.tenthsToInches(barCountTotal) + " in" : ""

  readonly property var monthWin: monthWindow(offMonth)
  readonly property int totalMonth: Model.sumEntries(root.entries, monthWin.start, monthWin.end)

  readonly property var seasonWin: seasonWindow(offSeason)
  readonly property int totalSeason: Model.sumEntries(root.entries, seasonWin.start, seasonWin.end)

  function setEntry(key, tenths) {
    var e = ({})
    for (var k in root.entries) e[k] = root.entries[k]
    if (tenths === null || isNaN(tenths) || tenths <= 0) delete e[key]
    else e[key] = tenths
    root.entries = e
    root.save()
  }

  function refresh() {
    dataFile.reload()
  }

  function open() { controller.show() }
  function close() { controller.hide() }
  function toggle() { opened ? close() : open() }

  onOpenedChanged: if (opened) dataFile.reload()

  function recentRainySlots() {
    var keys = Object.keys(root.entries).filter(function(k) { return (root.entries[k] || 0) > 0 })
    keys.sort()
    keys.reverse()
    var out = []
    for (var i = 0; i < 5; i++) {
      if (i < keys.length) out.push({ date: keys[i], amount: root.entries[keys[i]] })
      else out.push(null)
    }
    return out
  }

  function monthName(d) {
    var names = ["January","February","March","April","May","June","July","August","September","October","November","December"]
    return names[d.getMonth()]
  }

  // Daily total for the calendar: one decimal place, or "-" when that day
  // has no recorded rainfall.
  function dayAmount(key) {
    var v = root.entries[key]
    if (v === undefined || v === null) return "-"
    return Model.tenthsToInches(v)
  }

  // Date label for a single-day window: offset 0 is today, higher offsets
  // step backwards one day at a time.
  function dayLabel(offset) {
    var d = new Date()
    d.setHours(12, 0, 0, 0)
    d = Model.addDays(d, -offset)
    return root.monthName(d) + " " + d.getDate() + ", " + d.getFullYear()
  }

  function calendarCells() {
    var cells = []
    var first = new Date(root.viewYear, root.viewMonth, 1).getDay()
    var dim = new Date(root.viewYear, root.viewMonth + 1, 0).getDate()
    for (var i = 0; i < first; i++) cells.push(null)
    for (var d = 1; d <= dim; d++) cells.push(new Date(root.viewYear, root.viewMonth, d))
    while (cells.length < 42) cells.push(null)
    return cells
  }

  property int viewYear: new Date().getFullYear()
  property int viewMonth: new Date().getMonth()
  property string selectedHistoryDate: Model.dateKey(new Date())


  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      id: keyCatcher
      // The column is the source of truth for the popup height. Anything else
      // (summing named children, counting rows) goes stale and either clips the
      // content or leaves dead space at the bottom.
      //
      // The title's line box carries more air above it than the last recent
      // row does below, so the main view gets a little extra at the bottom to
      // keep the card's top and bottom margins visually even.
      readonly property int bottomPad: root.historyMode || root.settingsMode ? 0 : Style.space(6)
      implicitHeight: contentColumn.implicitHeight + bottomPad
      anchors.fill: parent
      // Let the range dropdown own the keyboard while its list is open.
      blocked: barCountDropdown.popupOpen
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight + keyCatcher.bottomPad
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: contentColumn
          width: flick.width
          spacing: Style.space(12)

          // Header ---------------------------------------------------------
          // A RowLayout, not a Row: the "Edit History" label, the Back button
          // and the gear have intrinsic widths that used to overflow the panel
          // and get clipped by the Flickable. The spacer takes whatever is
          // left, so the buttons are always inside the popup.
          RowLayout {
            id: headerRow
            width: parent.width
            spacing: Style.space(8)

            Text {
              textFormat: Text.PlainText
              text: "Rain Log"
              color: Commons.Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
              Layout.alignment: Qt.AlignVCenter
            }

            Button {
              text: "⚙"
              tooltipText: "Settings"
              Layout.alignment: Qt.AlignVCenter
              onClicked: {
                root.historyMode = false
                root.settingsMode = !root.settingsMode
              }
            }

            Item { Layout.fillWidth: true }

            Button {
              text: "Edit History"
              visible: !root.historyMode && !root.settingsMode
              // Sit the label flush with the content edge so the gap after it
              // matches the panel padding before the title.
              horizontalPadding: 0
              Layout.alignment: Qt.AlignVCenter
              onClicked: {
                root.settingsMode = false
                root.historyMode = true
              }
            }

            Button {
              text: "Back"
              visible: root.historyMode
              horizontalPadding: 0
              Layout.alignment: Qt.AlignVCenter
              onClicked: root.historyMode = false
            }
          }

          // Main view ------------------------------------------------------
          Column {
            id: mainColumn
            visible: !root.historyMode && !root.settingsMode
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.space(10)
            spacing: Style.space(12)

            // Today's entry. Only today is editable here; older days are
            // edited from the calendar.
            RowLayout {
              id: todayRow
              width: parent.width
              spacing: Style.space(8)

              Text {
                textFormat: Text.PlainText
                text: "Today (tenths of an inch)"
                color: Commons.Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                elide: Text.ElideRight
              }

              TextField {
                id: todayField
                Layout.preferredWidth: Style.space(90)
                Layout.alignment: Qt.AlignVCenter
                text: root.entries[root.todayKey()] !== undefined ? String(root.entries[root.todayKey()]) : ""
                placeholderText: "0"
                onEditingFinished: {
                  var v = parseInt(text, 10)
                  root.setEntry(root.todayKey(), isNaN(v) ? 0 : v)
                }
              }
            }

            // Rolling totals, each with its own backward/forward scroll.
            Column {
              id: totalsColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: ["24", "72", "week", "month", "season", "custom"]

                delegate: RowLayout {
                  id: totalRow
                  width: totalsColumn.width
                  spacing: Style.space(6)

                  readonly property string key: modelData
                  readonly property int off: key === "24" ? root.off24
                    : key === "72" ? root.off72
                    : key === "week" ? root.offWeek
                    : key === "month" ? root.offMonth
                    : key === "season" ? root.offSeason
                    : root.offCustom
                  readonly property int total: key === "24" ? root.total24
                    : key === "72" ? root.total72
                    : key === "week" ? root.totalWeek
                    : key === "month" ? root.totalMonth
                    : key === "season" ? root.totalSeason
                    : root.totalCustom
                  readonly property string label: key === "24" ? "24 hours"
                    : key === "72" ? "72 hours"
                    : key === "week" ? "Week"
                    : key === "month" ? "Month"
                    : key === "season" ? "Season"
                    : "Custom (" + root.customDays + "d)"
                  readonly property string windowName: {
                    if (key === "24") return root.dayLabel(root.off24)
                    if (key === "month") return root.monthName(root.monthWin.start) + " " + root.monthWin.start.getFullYear()
                    if (key === "season") return root.seasonWin.name + " " + root.seasonWin.start.getFullYear()
                    return ""
                  }

                  Button {
                    text: "◀"
                    tooltipText: "Earlier"
                    Layout.alignment: Qt.AlignVCenter
                    onClicked: root.adjustOffset(key, 1)
                  }

                  Column {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 0

                    // The custom interval keeps its own editor: the pencil
                    // (and the day field while it is open) sit immediately
                    // after the label they edit, not beside the total.
                    RowLayout {
                      spacing: Style.space(2)

                      Text {
                        textFormat: Text.PlainText
                        text: totalRow.label
                        color: Commons.Color.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                        font.bold: true
                        Layout.alignment: Qt.AlignVCenter
                        elide: Text.ElideRight
                      }

                      Button {
                        text: "✎"
                        tooltipText: "Set custom range"
                        visible: totalRow.key === "custom"
                        horizontalPadding: Style.space(2)
                        Layout.alignment: Qt.AlignVCenter
                        onClicked: root.editingCustom = !root.editingCustom
                      }

                      TextField {
                        id: customDaysField
                        visible: totalRow.key === "custom" && root.editingCustom
                        Layout.preferredWidth: Style.space(70)
                        Layout.alignment: Qt.AlignVCenter
                        text: String(root.customDays)
                        placeholderText: "14"
                        onEditingFinished: {
                          var v = parseInt(text, 10)
                          if (!isNaN(v) && v > 0) root.updateSetting("customDays", v)
                          root.editingCustom = false
                        }
                      }
                    }

                    Text {
                      visible: text !== ""
                      textFormat: Text.PlainText
                      text: totalRow.windowName
                      color: Commons.Color.foreground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                    }
                  }

                  // Forward scroll stays with the interval it changes; the
                  // inch reading has no controls beside it.
                  Button {
                    text: "▶"
                    tooltipText: "Later"
                    enabled: off > 0
                    Layout.alignment: Qt.AlignVCenter
                    onClicked: root.adjustOffset(key, -1)
                  }

                  Item { Layout.fillWidth: true }

                  Text {
                    textFormat: Text.PlainText
                    text: Model.tenthsToInches(total) + " in"
                    color: Commons.Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    // Match the inset the arrow glyphs get from their button
                    // padding on the left edge.
                    Layout.rightMargin: Style.spacing.controlPaddingX + Style.space(8)
                    Layout.alignment: Qt.AlignVCenter
                  }
                }
              }
            }

            // Recent rainy days --------------------------------------------
            Text {
              id: recentLabel
              textFormat: Text.PlainText
              text: "Recent rainy days"
              color: Commons.Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }

            Column {
              id: recentColumn
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: root.recentRainySlots()

                delegate: RowLayout {
                  width: recentColumn.width
                  spacing: Style.space(8)

                  // Indent the rows under the "Recent rainy days" heading.
                  Item { Layout.preferredWidth: Style.space(12) }

                  Text {
                    textFormat: Text.PlainText
                    text: modelData ? modelData.date : "--no data--"
                    color: Commons.Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    Layout.preferredWidth: Style.space(120)
                    elide: Text.ElideRight
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: modelData ? (Model.tenthsToInches(modelData.amount) + " in") : ""
                    color: Commons.Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    // Share the totals' value column: right-aligned with the
                    // same inset used by the interval totals above.
                    Layout.fillWidth: true
                    Layout.rightMargin: Style.spacing.controlPaddingX + Style.space(8)
                    horizontalAlignment: Text.AlignRight
                  }
                }
              }
            }
          }

          // Settings view ---------------------------------------------------
          Column {
            id: settingsColumn
            visible: root.settingsMode
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.space(10)
            spacing: Style.space(10)

            Text {
              textFormat: Text.PlainText
              text: "Settings"
              color: Commons.Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              text: "Data file path"
              color: Commons.Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            TextField {
              id: pathField
              width: parent.width
              text: root.dataPath
              onEditingFinished: {
                var p = text.trim()
                if (p !== "") root.updateSetting("dataPath", p)
              }
            }

            PanelSeparator {
              width: parent.width
            }

            PanelSectionHeader {
              text: "Bar"
            }

            Toggle {
              width: parent.width
              label: "Show rain count"
              description: "Show the selected total next to the raindrop"
              checked: root.showBarCount
              onClicked: root.updateSetting("showBarCount", !root.showBarCount)
            }

            Dropdown {
              id: barCountDropdown
              width: parent.width
              label: "Count total"
              value: root.barCountRange
              enabled: root.showBarCount
              opacity: root.showBarCount ? 1 : 0.55
              options: [
                { value: "day", label: "Daily" },
                { value: "week", label: "Weekly" },
                { value: "month", label: "Monthly" },
                { value: "season", label: "Seasonal" },
                { value: "year", label: "Yearly" }
              ]
              onChanged: function(v) { root.updateSetting("barCountRange", v) }
            }

            Button {
              text: "Back"
              // Align the label with the "Settings" heading instead of being
              // inset by the button's own control padding.
              horizontalPadding: 0
              onClicked: root.settingsMode = false
            }
          }

          // History view ----------------------------------------------------
          Column {
            id: historyColumn
            visible: root.historyMode
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 0
            spacing: Style.space(8)

            RowLayout {
              id: historyHeader
              width: parent.width
              spacing: Style.space(8)

              Button {
                text: "◀"
                tooltipText: "Previous month"
                Layout.alignment: Qt.AlignVCenter
                onClicked: {
                  if (root.viewMonth === 0) { root.viewMonth = 11; root.viewYear -= 1 }
                  else root.viewMonth -= 1
                }
              }
              Text {
                textFormat: Text.PlainText
                text: root.monthName(new Date(root.viewYear, root.viewMonth, 1)) + " " + root.viewYear
                color: Commons.Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                Layout.alignment: Qt.AlignVCenter
              }
              Item { Layout.fillWidth: true }
              Button {
                text: "▶"
                tooltipText: "Next month"
                Layout.alignment: Qt.AlignVCenter
                onClicked: {
                  if (root.viewMonth === 11) { root.viewMonth = 0; root.viewYear += 1 }
                  else root.viewMonth += 1
                }
              }
            }

            Grid {
              id: calendarGrid
              columns: 7
              columnSpacing: Style.space(4)
              rowSpacing: Style.space(4)
              width: parent.width
              height: 6 * Style.space(40) + 5 * Style.space(4)

              Repeater {
                model: root.calendarCells()

                delegate: Rectangle {
                  width: (calendarGrid.width - 6 * calendarGrid.columnSpacing) / 7
                  height: Style.space(40)
                  color: modelData && Model.dateKey(modelData) === root.selectedHistoryDate ? Commons.Color.accent : "transparent"
                  border.color: Commons.Color.popups.border
                  border.width: 1
                  radius: 4

                  Column {
                    anchors.centerIn: parent
                    spacing: 0

                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      textFormat: Text.PlainText
                      text: modelData ? modelData.getDate() : ""
                      color: modelData ? Commons.Color.foreground : "transparent"
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                    }

                    // Daily total: "n.n" in tenths-of-an-inch formatted to one
                    // decimal, or "-" when nothing was recorded that day.
                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      textFormat: Text.PlainText
                      text: modelData ? root.dayAmount(Model.dateKey(modelData)) : ""
                      color: !modelData ? "transparent"
                        : (Model.dateKey(modelData) === root.selectedHistoryDate ? Commons.Color.foreground : Commons.Color.muted)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    enabled: modelData !== null
                    onClicked: {
                      if (modelData) root.selectedHistoryDate = Model.dateKey(modelData)
                    }
                  }
                }
              }
            }

            RowLayout {
              id: historyInputRow
              width: parent.width
              spacing: Style.space(8)

              Text {
                textFormat: Text.PlainText
                text: root.selectedHistoryDate
                color: Commons.Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                Layout.alignment: Qt.AlignVCenter
              }
              TextField {
                id: historyField
                Layout.preferredWidth: Style.space(90)
                Layout.alignment: Qt.AlignVCenter
                text: root.entries[root.selectedHistoryDate] !== undefined ? String(root.entries[root.selectedHistoryDate]) : ""
                placeholderText: "0"
                onEditingFinished: {
                  var v = parseInt(text, 10)
                  root.setEntry(root.selectedHistoryDate, isNaN(v) ? 0 : v)
                }
              }
              Text {
                textFormat: Text.PlainText
                text: "(tenths)"
                color: Commons.Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                Layout.alignment: Qt.AlignVCenter
              }
              Item { Layout.fillWidth: true }
            }
          }
        }
      }
    }
  }
}
