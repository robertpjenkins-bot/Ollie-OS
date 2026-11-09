// A picture of the Ollie OS desktop with its newest apps (docs/ollie-os-desktop.png),
// put together from real parts: Ollie OS's background, the apps' own windows
// (docs/screenshots), their icons, the Ollie Pet, and a bar like Ollie OS's.
import QtQuick

Window {
    id: desk
    width: 1920
    height: 1080
    visible: true
    color: "black"
    readonly property string root: Qt.resolvedUrl("../../../")
    readonly property string icons: root + "os/profile/airootfs/usr/share/icons/hicolor/128x128/apps/"
    readonly property string shots: root + "docs/screenshots/"
    property string wallpaper: ""

    Image { anchors.fill: parent; source: desk.wallpaper; fillMode: Image.PreserveAspectCrop }

    // Desktop icons.
    Column {
        x: 22; y: 22
        spacing: 14
        Repeater {
            model: [["games", "Games"], ["gamehub", "Game Hub"], ["school", "School Planner"], ["paint", "Ollie Paint"],
                    ["mouse", "Mouse Maker"], ["pet", "Ollie Pet"], ["mathquest", "Math Quest"], ["appcenter", "App Center"]]
            delegate: Column {
                required property var modelData
                width: 104
                spacing: 3
                Image { source: desk.icons + "ollie-" + modelData[0] + ".png"; width: 68; height: 68; anchors.horizontalCenter: parent.horizontalCenter }
                Text { text: modelData[1]; color: "white"; font.pixelSize: 14; width: parent.width; horizontalAlignment: Text.AlignHCenter
                    style: Text.Outline; styleColor: "#80000000" }
            }
        }
    }

    // A window: a dark Breeze-style title bar over the app's real screenshot.
    component Win: Item {
        id: w
        property string title
        property string icon
        property string shot
        property bool active: false
        Rectangle { // shadow
            x: 6; y: 10; width: w.width; height: w.height; radius: 10
            color: w.active ? "#90000000" : "#60000000"
        }
        Rectangle {
            anchors.fill: parent; radius: 8; clip: true
            color: "#202326"
            border.color: w.active ? "#14b8a6" : "#33383c"; border.width: 1
            Rectangle {
                id: bar
                width: parent.width; height: 36; color: w.active ? "#2a2e32" : "#232629"
                Image { x: 10; anchors.verticalCenter: parent.verticalCenter; source: desk.icons + "ollie-" + w.icon + ".png"; width: 22; height: 22 }
                Text { anchors.centerIn: parent; text: w.title; color: w.active ? "white" : "#a0a4a8"; font.pixelSize: 15; font.bold: w.active }
                Row {
                    anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                    spacing: 14
                    Text { text: "–"; color: "#c0c4c8"; font.pixelSize: 18 }
                    Text { text: "□"; color: "#c0c4c8"; font.pixelSize: 16 }
                    Rectangle { width: 18; height: 18; radius: 9; color: w.active ? "#da4453" : "#4d5257"
                        Text { anchors.centerIn: parent; text: "×"; color: "white"; font.pixelSize: 15 } }
                }
            }
            Image { y: bar.height; width: parent.width; height: parent.height - bar.height; source: desk.shots + w.shot + ".png"; fillMode: Image.Stretch; smooth: true; mipmap: true }
        }
    }

    // Two windows side by side, each the shape of its screenshot (+ the title bar).
    // (Together they cover the background's cube and name, so nothing peeks out.)
    Win { x: 176; y: 150; width: 860; height: 36 + 860 * 780 / 1120; title: "School Planner"; icon: "school"; shot: "school" }
    Win { x: 1000; y: 212; width: 860; height: 36 + 860 * 760 / 1200; title: "Ollie Paint"; icon: "paint"; shot: "paint"; active: true }

    // The pet walking along the bottom of the screen.
    Loader {
        x: 250; y: 1080 - 56 - 112
        source: desk.root + "os/profile/airootfs/usr/local/share/ollie/PetBody.qml"
        onLoaded: { item.stage = 2; item.scale = 0.8; item.mood = "happy" }
    }
    Rectangle {
        x: 372; y: 1080 - 56 - 150; width: 150; height: 40; radius: 16
        color: "white"; border.color: "#0b4f4a"; border.width: 2
        Text { anchors.centerIn: parent; text: "Let's play"; color: "#0b4f4a"; font.pixelSize: 17 }
    }

    // The bar along the bottom.
    Rectangle {
        y: parent.height - 56; width: parent.width; height: 56
        color: "#e61b1e20"
        Rectangle { width: parent.width; height: 1; color: "#40ffffff" }
        Image { x: 12; anchors.verticalCenter: parent.verticalCenter; source: desk.root + "os/art/ollie-os.svg"; sourceSize.width: 40; sourceSize.height: 40 }
        Rectangle {
            x: 66; anchors.verticalCenter: parent.verticalCenter; width: 380; height: 38; radius: 19
            color: "white"
            Rectangle { x: 16; anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: -2; width: 13; height: 13; radius: 7; color: "transparent"; border.color: "#6b7280"; border.width: 2
                Rectangle { x: 10; y: 11; width: 7; height: 2; rotation: 45; color: "#6b7280" } }
            Text { x: 40; anchors.verticalCenter: parent.verticalCenter; text: "Search Google..."; color: "#6b7280"; font.pixelSize: 16 }
        }
        Row {
            anchors.centerIn: parent; anchors.horizontalCenterOffset: 120
            spacing: 10
            Repeater {
                model: ["games", "gamehub", "school", "paint", "mouse", "pet", "mathquest", "codequest", "music", "appcenter", "trophies", "finder"]
                delegate: Item {
                    required property string modelData
                    width: 46; height: 56
                    readonly property bool open: ["school", "paint"].includes(modelData)
                    Rectangle { anchors.fill: parent; anchors.margins: 2; radius: 6; color: modelData === "paint" ? "#3314b8a6" : "transparent" }
                    Image { anchors.centerIn: parent; source: desk.icons + "ollie-" + modelData + ".png"; width: 38; height: 38 }
                    Rectangle { visible: parent.open; anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
                        width: modelData === "paint" ? 34 : 14; height: 3; radius: 1.5; color: "#14b8a6" }
                }
            }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 18; anchors.verticalCenter: parent.verticalCenter
            spacing: 18
            Column {
                Text { text: "4:20 PM"; color: "white"; font.pixelSize: 16; anchors.right: parent.right }
                Text { text: "Thursday"; color: "#c0c4c8"; font.pixelSize: 13; anchors.right: parent.right }
            }
        }
    }
}
