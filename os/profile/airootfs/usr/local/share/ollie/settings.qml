// Ollie OS Settings (ollie-settings). Each change is said on the console as
// OLLIE-ACTION ... for ollie-settings to make:
//   steam|fps|boost|sound on|off     colours dark|light teal|purple|red|gold [bg]
//   screen-time MINUTES   extra MINUTES   scanner on|off   pin NEWPIN   notes   recovery
//   pad-mouse on|off   pad-setup   seasons on|off   birthday MM-DD
//   bedtime school|weekend HH:MM|off   wake HH:MM   easyread on|off   language CODE   screensaver MINUTES|off
// Arguments (what is on now): steam= fps= boost= sound= mode= colour=
// screentime= scanner= pin= (the PIN's check sum) left= (minutes left today)
// gold=on|off (the secret Ollie Gold colour, once found in Ollie Finder)
// firefox=on|off (whether Firefox has a password; firefox-password set|remove).
// The grown-ups' part opens with the parent PIN; without one, a grown-up
// makes one first.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: win
    width: 640
    height: 760
    visible: true
    title: "Ollie OS Settings"

    function arg(name) {
        const a = Qt.application.arguments;
        for (let i = 0; i < a.length; i++)
            if (a[i].indexOf(name + "=") === 0)
                return a[i].substring(name.length + 1);
        return "";
    }
    function act(what) { console.log("OLLIE-ACTION " + what) }
    function md5(pin) { return Qt.md5("ollie-os:" + pin) }

    property string mode: arg("mode") || "dark"
    property string colour: arg("colour") || "teal"
    property string pinSum: arg("pin")
    property bool unlocked: false
    property string left: arg("left")
    property string firefox: arg("firefox")
    readonly property var limits: [
        { text: "No limit", min: 0 }, { text: "30 minutes a day", min: 30 }, { text: "1 hour a day", min: 60 },
        { text: "1 hour 30 minutes a day", min: 90 }, { text: "2 hours a day", min: 120 },
        { text: "3 hours a day", min: 180 }, { text: "4 hours a day", min: 240 }
    ]
    readonly property var languages: [["en", "English"], ["es", "Español"], ["fr", "Français"], ["de", "Deutsch"], ["pt", "Português"], ["it", "Italiano"],
                                      ["nl", "Nederlands"], ["pl", "Polski"], ["sv", "Svenska"], ["ja", "日本語"], ["zh", "中文"]]
    readonly property var bedtimes: ["Off", "19:00", "19:30", "20:00", "20:30", "21:00", "21:30", "22:00", "22:30", "23:00"]
    readonly property var wakes: ["06:00", "06:30", "07:00", "07:30", "08:00", "08:30", "09:00"]
    function setBirthday() {
        if (bMonth.currentIndex > 0 && bDay.currentIndex > 0)
            act("birthday " + String(bMonth.currentIndex).padStart(2, "0") + "-" + String(bDay.currentIndex).padStart(2, "0"));
    }
    function applyColours() { act("colours " + mode + " " + colour + (bgToo.checked ? " bg" : "")) }

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth

        ColumnLayout {
            width: parent.width
            spacing: 14
            anchors.margins: 18

            Item { height: 4 }

            GroupBox {
                title: "Games"
                Layout.fillWidth: true
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                ColumnLayout {
                    anchors.fill: parent
                    Switch {
                        text: "Steam opens in Game Mode (big screen, like a Steam Machine)"
                        checked: win.arg("steam") !== "off"
                        onToggled: win.act("steam " + (checked ? "on" : "off"))
                    }
                    RowLayout {
                        Label { text: "In games, show:" }
                        ComboBox {
                            Layout.preferredWidth: 330
                            model: ["Nothing", "FPS counter", "Game Overlay (time, battery, FPS, temperatures, your pet)"]
                            currentIndex: ["off", "fps", "full"].indexOf(win.arg("overlay") || "fps")
                            onActivated: i => win.act("overlay " + ["off", "fps", "full"][i])
                        }
                    }
                    Label { text: " (Right Shift + F12 hides and shows it in a game)"; opacity: 0.7 }
                    Switch {
                        text: "Speed Boost: full power while a game runs"
                        checked: win.arg("boost") !== "off"
                        onToggled: win.act("boost " + (checked ? "on" : "off"))
                    }
                    Switch {
                        text: "Update Checker: tells me about new Ollie OS updates"
                        checked: win.arg("updates") === "on"
                        onToggled: win.act("updates " + (checked ? "on" : "off"))
                    }
                    Switch {
                        text: "Start-up sound"
                        checked: win.arg("sound") !== "off"
                        onToggled: win.act("sound " + (checked ? "on" : "off"))
                    }
                    Switch {
                        text: "Controller as a mouse on the desktop"
                        checked: win.arg("padmouse") !== "off"
                        onToggled: win.act("pad-mouse " + (checked ? "on" : "off"))
                    }
                    Button {
                        text: "Choose the controller button that opens the Game Hub"
                        onClicked: win.act("pad-setup")
                    }
                    Button {
                        text: "Recovery Mode: put a newer Ollie OS on from an ISO file"
                        onClicked: win.act("recovery")
                    }
                }
            }

            GroupBox {
                title: "Colours"
                Layout.fillWidth: true
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 10
                    RowLayout {
                        Button {
                            text: "Dark"
                            highlighted: win.mode === "dark"
                            onClicked: { win.mode = "dark"; win.applyColours() }
                        }
                        Button {
                            text: "Light"
                            highlighted: win.mode === "light"
                            onClicked: { win.mode = "light"; win.applyColours() }
                        }
                    }
                    RowLayout {
                        spacing: 12
                        Repeater {
                            model: [{ name: "teal", label: "Teal", c: "#14b8a6" }, { name: "purple", label: "Purple", c: "#a855f7" }, { name: "red", label: "Red", c: "#f43f5e" }]
                                .concat(win.arg("gold") === "on" ? [{ name: "gold", label: "Gold", c: "#f59e0b" }] : [])
                            delegate: ColumnLayout {
                                required property var modelData
                                Rectangle {
                                    width: 64
                                    height: 64
                                    radius: 32
                                    color: modelData.c
                                    border.width: win.colour === modelData.name ? 5 : 1
                                    border.color: win.colour === modelData.name ? palette.text : "#40000000"
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { win.colour = modelData.name; win.applyColours() }
                                    }
                                }
                                Label { text: modelData.label; Layout.alignment: Qt.AlignHCenter }
                            }
                        }
                    }
                    CheckBox { id: bgToo; text: "Change the background to match"; checked: true }
                    Switch {
                        text: "Seasonal themes: Halloween, winter and your birthday"
                        checked: win.arg("seasons") !== "off"
                        onToggled: win.act("seasons " + (checked ? "on" : "off"))
                    }
                    RowLayout {
                        spacing: 8
                        Label { text: "My birthday:" }
                        ComboBox {
                            id: bMonth
                            model: ["Month", "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
                            currentIndex: win.arg("birthday") ? parseInt(win.arg("birthday").split("-")[0]) : 11
                            onActivated: win.setBirthday()
                        }
                        ComboBox {
                            id: bDay
                            model: ["Day"].concat(Array.from({ length: 31 }, (_, i) => String(i + 1)))
                            currentIndex: win.arg("birthday") ? parseInt(win.arg("birthday").split("-")[1]) : 23
                            onActivated: win.setBirthday()
                        }
                    }
                }
            }

            GroupBox {
                title: "Language, reading and the screensaver"
                Layout.fillWidth: true
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 8
                    Switch {
                        text: "Easy reading: bigger text, an easy-to-read font and a bigger mouse pointer"
                        checked: win.arg("easyread") === "on"
                        onToggled: win.act("easyread " + (checked ? "on" : "off"))
                    }
                    RowLayout {
                        spacing: 8
                        Label { text: "Language:" }
                        ComboBox {
                            Layout.preferredWidth: 220
                            model: win.languages.map(l => l[1])
                            currentIndex: Math.max(0, win.languages.findIndex(l => l[0] === (win.arg("language") || "en")))
                            onActivated: index => { win.act("language " + win.languages[index][0]); langNote.visible = true; }
                        }
                        Label { id: langNote; visible: false; text: "From the next time you log in."; opacity: 0.8 }
                    }
                    Label { text: "(The desktop, Firefox and most apps change; Ollie OS's own apps stay in English for now.)"; opacity: 0.7; font.pixelSize: 12 }
                    RowLayout {
                        spacing: 8
                        Label { text: "Ollie screensaver:" }
                        ComboBox {
                            Layout.preferredWidth: 220
                            model: ["After 3 minutes", "After 5 minutes", "After 10 minutes", "Off"]
                            currentIndex: ({ "3": 0, "5": 1, "10": 2, "off": 3 })[win.arg("screensaver") || "5"] ?? 1
                            onActivated: index => win.act("screensaver " + ["3", "5", "10", "off"][index])
                        }
                    }
                }
            }

            GroupBox {
                title: "For grown-ups"
                Layout.fillWidth: true
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                Layout.bottomMargin: 18

                ColumnLayout {
                    anchors.fill: parent

                    // No PIN yet: a grown-up makes one.
                    ColumnLayout {
                        visible: win.pinSum === ""
                        Label {
                            text: "Screen Time and the Typing Scanner are kept safe with a parent PIN.\nGrown-up: choose a PIN (4 to 8 numbers)."
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                        RowLayout {
                            TextField { id: new1; placeholderText: "PIN"; echoMode: TextInput.Password; inputMethodHints: Qt.ImhDigitsOnly; validator: RegularExpressionValidator { regularExpression: /[0-9]{0,8}/ } }
                            TextField { id: new2; placeholderText: "Same PIN again"; echoMode: TextInput.Password; inputMethodHints: Qt.ImhDigitsOnly; validator: RegularExpressionValidator { regularExpression: /[0-9]{0,8}/ } }
                            Button {
                                text: "Set PIN"
                                enabled: new1.text.length >= 4 && new1.text === new2.text
                                onClicked: {
                                    win.act("pin " + new1.text);
                                    win.pinSum = win.md5(new1.text);
                                    win.unlocked = true;
                                    new1.text = new2.text = "";
                                }
                            }
                        }
                    }

                    // Locked.
                    ColumnLayout {
                        visible: win.pinSum !== "" && !win.unlocked
                        Label { text: "Grown-up: type the parent PIN to change Screen Time and the Typing Scanner." ; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        RowLayout {
                            TextField {
                                id: pinField
                                placeholderText: "Parent PIN"
                                echoMode: TextInput.Password
                                inputMethodHints: Qt.ImhDigitsOnly
                                onAccepted: unlockButton.clicked()
                            }
                            Button {
                                id: unlockButton
                                text: "Unlock"
                                onClicked: {
                                    if (win.md5(pinField.text) === win.pinSum)
                                        win.unlocked = true;
                                    else
                                        wrongPin.visible = true;
                                    pinField.text = "";
                                }
                            }
                            Label { id: wrongPin; text: "That is not the PIN."; color: "#ef4444"; visible: false }
                        }
                    }

                    // Unlocked.
                    ColumnLayout {
                        visible: win.pinSum !== "" && win.unlocked
                        spacing: 10
                        Label { text: "Screen Time"; font.bold: true }
                        RowLayout {
                            ComboBox {
                                id: limitBox
                                Layout.preferredWidth: 260
                                model: win.limits.map(l => l.text)
                                currentIndex: Math.max(0, win.limits.findIndex(l => String(l.min) === (win.arg("screentime") || "0")))
                                onActivated: index => {
                                    win.act("screen-time " + win.limits[index].min);
                                    win.left = win.limits[index].min === 0 ? "off" : win.left;
                                }
                            }
                            Button {
                                text: "+30 minutes today"
                                enabled: limitBox.currentIndex > 0
                                onClicked: { win.act("extra 30"); if (win.left !== "off" && win.left !== "") win.left = String(Number(win.left) + 30) }
                            }
                        }
                        Label {
                            visible: limitBox.currentIndex > 0
                            text: win.left === "off" || win.left === "" ? "The limit starts counting now." : "Left today: " + win.left + " minutes"
                            opacity: 0.8
                        }
                        Label {
                            text: "When the time is up, games close (with warnings 10, 5 and 1 minutes before) and the screen says to come back tomorrow, unless a grown-up types the PIN for more time."
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                            opacity: 0.8
                        }

                        Label { text: "Bedtime"; font.bold: true; Layout.topMargin: 8 }
                        GridLayout {
                            columns: 2
                            columnSpacing: 10
                            Label { text: "School nights (Sunday to Thursday):" }
                            ComboBox {
                                model: win.bedtimes
                                currentIndex: Math.max(0, win.bedtimes.indexOf(win.arg("bedschool") || "Off"))
                                onActivated: index => win.act("bedtime school " + (index === 0 ? "off" : win.bedtimes[index]))
                            }
                            Label { text: "Weekends (Friday and Saturday):" }
                            ComboBox {
                                model: win.bedtimes
                                currentIndex: Math.max(0, win.bedtimes.indexOf(win.arg("bedweekend") || "Off"))
                                onActivated: index => win.act("bedtime weekend " + (index === 0 ? "off" : win.bedtimes[index]))
                            }
                            Label { text: "Wake-up time (bedtime ends):" }
                            ComboBox {
                                model: win.wakes
                                currentIndex: Math.max(0, win.wakes.indexOf(win.arg("wake") || "07:00"))
                                onActivated: index => win.act("wake " + win.wakes[index])
                            }
                        }
                        Label {
                            text: "At bedtime, games close (with warnings 10, 5 and 1 minutes before) and the screen says goodnight until the morning, unless a grown-up types the PIN for a later bedtime tonight."
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                            opacity: 0.8
                        }

                        Label { text: "Inappropriate Typing Scanner"; font.bold: true; Layout.topMargin: 8 }
                        Switch {
                            text: "On: notes bad words that are typed"
                            checked: win.arg("scanner") === "on"
                            onToggled: win.act("scanner " + (checked ? "on" : "off"))
                        }
                        Label {
                            text: "It notes the time and the bad word. The notes open only with the parent PIN (\"Typing Scanner notes\" on the desktop, or here). Nothing else that is typed is kept, and nothing is sent anywhere."
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                            opacity: 0.8
                        }
                        Button { text: "Open the notes"; onClicked: win.act("notes") }

                        Label { text: "Firefox password"; font.bold: true; Layout.topMargin: 8 }
                        Label {
                            text: win.firefox === "on" ? "Firefox opens only when its password is typed." : "Firefox has no password."
                            opacity: 0.8
                        }
                        RowLayout {
                            Button {
                                text: win.firefox === "on" ? "Change the password" : "Give Firefox a password"
                                onClicked: { win.act("firefox-password set"); win.firefox = "on" }
                            }
                            Button {
                                text: "No password"
                                visible: win.firefox === "on"
                                onClicked: { win.act("firefox-password remove"); win.firefox = "off" }
                            }
                        }

                        RowLayout {
                            Layout.topMargin: 8
                            Item { Layout.fillWidth: true }
                            Button { text: "Change the PIN"; onClicked: { win.pinSum = ""; win.unlocked = false } }
                            Button { text: "Lock"; onClicked: win.unlocked = false }
                        }
                    }
                }
            }
        }
    }
}
