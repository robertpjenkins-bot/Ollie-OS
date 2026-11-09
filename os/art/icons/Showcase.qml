// Ollie OS's showcase (docs/ollie-os-showcase.jpg), for the top of the release
// notes: the banner, then four big screenshots of what is new, with a line on
// each. Remake it after the banner and screenshots (docs/screenshots):
//   qml6 os/art/icons/Showcase.qml, then save the window (1600 wide).
import QtQuick

Window {
    id: w
    width: 1600
    height: col.height
    visible: true
    color: "#22252B"
    readonly property string docs: Qt.resolvedUrl("../../../docs/")
    readonly property var shots: [
        ["school", "School Planner", "Your week, and what to wear for the weather"],
        ["paint", "Ollie Paint", "Draw with the mouse: brushes, shapes, fill"],
        ["mouse", "Mouse Maker", "Draw your own mouse pointer and use it"],
        ["welcome", "Welcome", "Everything one click away"]
    ]

    Column {
        id: col
        width: parent.width
        Image { source: w.docs + "ollie-os-banner.png"; width: 1600; height: 560 }
        Grid {
            x: 48
            columns: 2
            columnSpacing: 48
            rowSpacing: 40
            topPadding: 24
            bottomPadding: 56
            Repeater {
                model: w.shots
                delegate: Column {
                    required property var modelData
                    spacing: 16
                    width: 728
                    Rectangle { // the screenshot, on a card
                        width: 728; height: 500; radius: 14
                        color: "#2E323B"
                        Image {
                            anchors.fill: parent; anchors.margins: 10
                            source: w.docs + "screenshots/" + modelData[0] + ".png"
                            fillMode: Image.PreserveAspectFit
                            smooth: true; mipmap: true
                        }
                    }
                    Text { text: modelData[1]; color: "white"; font.pixelSize: 34; font.bold: true }
                    Text { text: modelData[2]; color: "#B9BEC8"; font.pixelSize: 24; topPadding: -8 }
                }
            }
        }
    }
}
