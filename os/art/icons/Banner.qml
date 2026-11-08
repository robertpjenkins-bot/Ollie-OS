// Ollie OS's banner (docs/ollie-os-banner.png), for the GitHub page and the
// release notes: the Ollie cube, its name and version, and its app icons.
import QtQuick

Window {
    width: 1600
    height: 560
    visible: true
    color: "#22252B"
    readonly property string icons: Qt.resolvedUrl("../../profile/airootfs/usr/share/icons/hicolor/128x128/apps/")
    Row { // a band of the icons' colours along the bottom
        anchors.bottom: parent.bottom
        Repeater {
            model: ["#C8473D", "#E07A2F", "#D9A021", "#4F8A45", "#257A78", "#336B9E", "#6A4E9C", "#D0587E"]
            Rectangle { required property string modelData; width: 200; height: 10; color: modelData }
        }
    }
    Image {
        x: 90; y: 90
        source: "../ollie-os.svg"
        sourceSize.width: 250; sourceSize.height: 250
    }
    Column {
        x: 390; y: 92
        spacing: 6
        Row {
            spacing: 18
            Text { text: "Ollie OS"; color: "white"; font.pixelSize: 108; font.bold: true }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: v.width + 36; height: 64; radius: 8; color: "#D9A021"
                Text { id: v; anchors.centerIn: parent; text: "1.7"; font.pixelSize: 40; font.bold: true; color: "#22252B" }
            }
        }
        Text { text: "The fun gaming computer, made by biobro"; color: "#F4EFE6"; font.family: "Noto Serif"; font.pixelSize: 40 }
        Text { text: "Steam · Minecraft · retro games · Ollie Pet · Coding Quest · Math Quest · and more"; color: "#A9ABB2"; font.pixelSize: 26; topPadding: 6 }
    }
    Row {
        x: 92; y: 400
        spacing: 22
        Repeater {
            model: ["games", "gamehub", "pet", "coop", "appcenter", "codequest", "mathquest", "typing", "music", "comic", "photobooth", "trophies"]
            delegate: Image {
                required property string modelData
                source: icons + "ollie-" + modelData + ".png"
                width: 96; height: 96
            }
        }
    }
}
