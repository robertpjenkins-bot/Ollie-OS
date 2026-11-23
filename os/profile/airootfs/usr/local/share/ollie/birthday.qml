// Happy birthday! (ollie-seasons, on your birthday): a cake, confetti again
// and again, and Ollie singing along.
// Argument: name= (yours).
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: win
    width: 760
    height: 520
    visible: true
    title: "Happy birthday!"
    // (An ordinary window: it must not stay on top of what opens after it.
    // Enter, Space or Escape closes it like the button does.)
    Shortcut { sequences: ["Return", "Enter", "Space", "Escape"]; onActivated: Qt.quit() }

    function arg(n) {
        const a = Qt.application.arguments;
        for (let i = 0; i < a.length; i++)
            if (a[i].indexOf(n + "=") === 0)
                return a[i].substring(n.length + 1);
        return "";
    }
    Rectangle { anchors.fill: parent; color: "#FFF6E9" }
    Repeater { // stripes along the top and the bottom
        model: 12
        Rectangle {
            required property int index
            x: index * win.width / 12; width: win.width / 12; height: 18
            y: index % 2 ? 0 : win.height - 18
            color: ["#C8473D", "#E07A2F", "#D9A021", "#4F8A45", "#336B9E", "#6A4E9C"][index % 6]
        }
    }
    ColumnLayout {
        anchors.centerIn: parent
        spacing: 14
        Label { text: "Happy birthday" + (win.arg("name") ? ",\n" + win.arg("name") : ""); color: "#22252B"; font.family: "Noto Serif"; font.pixelSize: 52; font.bold: true; horizontalAlignment: Text.AlignHCenter; Layout.alignment: Qt.AlignHCenter }
        Label { text: "Have a great day. From Ollie and Ollie OS."; color: "#6B6F78"; font.pixelSize: 20; Layout.alignment: Qt.AlignHCenter }
        Button { text: "Thank you"; font.pixelSize: 18; highlighted: true; Layout.alignment: Qt.AlignHCenter; onClicked: Qt.quit() }
    }
    Confetti { id: confetti }
    Timer { interval: 2500; running: true; repeat: true; triggeredOnStart: true; onTriggered: confetti.burst() }
}
