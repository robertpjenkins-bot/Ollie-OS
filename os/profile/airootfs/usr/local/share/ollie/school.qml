// School Planner (ollie-school): your school week (P.E., swimming, music,
// library...), and with the weather for your town, what to wear and what to
// pack, today and tomorrow. The weather comes from Open-Meteo (free, no account).
// Says on the console:
//   OLLIE-ACTION save JSON            the planner, to keep (the wrapper writes it)
//   OLLIE-ACTION notify TITLE|BODY    (morning=1) the morning reminder, then quits
// Arguments: data=JSON (what was saved), morning=1 (no window: the reminder),
// weather=URL and places=URL (tests: a forecast / a town search, as files).
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: win
    width: 1120
    height: 780
    visible: arg("morning") !== "1"
    title: "School Planner"
    color: paper

    readonly property color paper: "#F4EFE6"
    readonly property color ink: "#22252B"
    readonly property color soft: "#6B6F78"
    readonly property color navy: "#283A63"
    readonly property color bus: "#E9B13A"
    readonly property color line: "#DDD5C6"

    function arg(n) {
        const a = Qt.application.arguments;
        for (let i = 0; i < a.length; i++)
            if (a[i].indexOf(n + "=") === 0)
                return a[i].substring(n.length + 1);
        return "";
    }

    // --- What is kept ---
    property var plan: ({ town: "", lat: 0, lon: 0, unit: "", reminder: true, days: {} })
    property int page: 0              // 0 today, 1 tomorrow, 2 my week, 3 settings
    property var forecast: null
    property string weatherNote: ""
    property int changes: 0           // so bindings see a changed plan
    function save() { changes++; saveTimer.restart(); }
    function saveNow() { saveTimer.stop(); console.log("OLLIE-ACTION save " + JSON.stringify(win.plan)); }
    Timer { id: saveTimer; interval: 400; onTriggered: win.saveNow() }
    onClosing: if (saveTimer.running) saveNow() // a change just before closing is kept too
    property string savedNote: ""
    Timer { id: savedNoteTimer; interval: 4000; onTriggered: win.savedNote = "" }
    function pressSave(text) { saveNow(); savedNote = text || "Saved."; savedNoteTimer.restart(); }

    readonly property var dayNames: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    readonly property var weekOrder: [1, 2, 3, 4, 5, 6, 0]

    // The activities to pick from: what to wear for them, what to bring.
    readonly property var presets: [
        { kind: "pe", name: "P.E.", wear: ["Sneakers (real shoes, not sandals or boots)", "Socks", "Clothes you can run in"], bring: ["Water bottle"] },
        { kind: "swim", name: "Swimming", wear: [], bring: ["Swimsuit", "Towel", "Goggles"] },
        { kind: "music", name: "Music", wear: [], bring: ["Your instrument", "Music folder"] },
        { kind: "art", name: "Art", wear: [], bring: ["An old shirt for painting"] },
        { kind: "library", name: "Library", wear: [], bring: ["Library books to give back"] },
        { kind: "show", name: "Show and tell", wear: [], bring: ["Something to show"] },
        { kind: "computer", name: "Computer lab", wear: [], bring: ["Headphones"] },
        { kind: "trip", name: "Field trip", wear: ["Comfy walking shoes"], bring: ["Signed permission slip", "Packed lunch"] },
        { kind: "sports", name: "Sports practice", wear: [], bring: ["Sports clothes", "Water bottle"] },
        { kind: "dance", name: "Dance", wear: [], bring: ["Dance clothes and shoes"] },
        { kind: "piano", name: "Piano lesson", wear: [], bring: ["Piano book"] }
    ]
    function preset(kind) {
        for (let i = 0; i < presets.length; i++)
            if (presets[i].kind === kind) return presets[i];
        return null;
    }
    function activities(day) { return (plan.days && plan.days[day]) || []; }
    function addActivity(day, a) {
        const d = plan.days || {};
        d[day] = activities(day).concat([a]);
        plan.days = d; save();
    }
    function removeActivity(day, i) {
        const list = activities(day).slice();
        list.splice(i, 1);
        plan.days[day] = list; save();
    }

    // --- Temperatures ---
    function unit() { return plan.unit || (Qt.locale().measurementSystem === Locale.ImperialUSSystem ? "F" : "C"); }
    function temp(c) {
        if (c === undefined || c === null || isNaN(c)) return "";
        return unit() === "F" ? Math.round(c * 9 / 5 + 32) + "°F" : Math.round(c) + "°C";
    }

    // --- The weather ---
    function getJSON(url, done) { // done(json or null, HTTP status: 0 = no connection)
        const x = new XMLHttpRequest();
        x.onreadystatechange = function () {
            if (x.readyState !== XMLHttpRequest.DONE) return;
            let j = null;
            try { j = JSON.parse(x.responseText); } catch (e) { j = null; }
            done(j, x.status);
        };
        x.open("GET", url);
        x.send();
    }

    // --- Finding your town ---
    // The town service knows place names only: "Seattle, WA" or "Seattle
    // Washington" find nothing. So the name is searched (dropping words from the
    // end until something is found), and the rest picks among the places found.
    readonly property var usStates: ({ AL: "Alabama", AK: "Alaska", AZ: "Arizona", AR: "Arkansas", CA: "California", CO: "Colorado",
        CT: "Connecticut", DE: "Delaware", DC: "District of Columbia", FL: "Florida", GA: "Georgia", HI: "Hawaii", ID: "Idaho",
        IL: "Illinois", IN: "Indiana", IA: "Iowa", KS: "Kansas", KY: "Kentucky", LA: "Louisiana", ME: "Maine", MD: "Maryland",
        MA: "Massachusetts", MI: "Michigan", MN: "Minnesota", MS: "Mississippi", MO: "Missouri", MT: "Montana", NE: "Nebraska",
        NV: "Nevada", NH: "New Hampshire", NJ: "New Jersey", NM: "New Mexico", NY: "New York", NC: "North Carolina",
        ND: "North Dakota", OH: "Ohio", OK: "Oklahoma", OR: "Oregon", PA: "Pennsylvania", RI: "Rhode Island", SC: "South Carolina",
        SD: "South Dakota", TN: "Tennessee", TX: "Texas", UT: "Utah", VT: "Vermont", VA: "Virginia", WA: "Washington",
        WV: "West Virginia", WI: "Wisconsin", WY: "Wyoming" })
    // Town names to fix spelling slips with ("sacreamento" is Sacramento):
    // state capitals, big towns, and a few cities in other countries.
    readonly property var knownTowns: "Montgomery|Juneau|Phoenix|Little Rock|Sacramento|Denver|Hartford|Dover|Tallahassee|Atlanta|Honolulu|Boise|Springfield|Indianapolis|Des Moines|Topeka|Frankfort|Baton Rouge|Augusta|Annapolis|Boston|Lansing|Saint Paul|Jackson|Jefferson City|Helena|Lincoln|Carson City|Concord|Trenton|Santa Fe|Albany|Raleigh|Bismarck|Columbus|Oklahoma City|Salem|Harrisburg|Providence|Columbia|Pierre|Nashville|Austin|Salt Lake City|Montpelier|Richmond|Olympia|Charleston|Madison|Cheyenne|New York|Los Angeles|Chicago|Houston|Philadelphia|San Antonio|San Diego|Dallas|San Jose|Jacksonville|Fort Worth|Charlotte|San Francisco|Seattle|Washington|El Paso|Detroit|Memphis|Portland|Louisville|Baltimore|Milwaukee|Albuquerque|Tucson|Fresno|Mesa|Kansas City|Omaha|Colorado Springs|Miami|Long Beach|Virginia Beach|Oakland|Minneapolis|Tulsa|Tampa|Arlington|New Orleans|Wichita|Bakersfield|Cleveland|Aurora|Anaheim|Riverside|Santa Ana|Corpus Christi|Lexington|Henderson|Stockton|Pittsburgh|Saint Louis|Cincinnati|Anchorage|Greensboro|Plano|Newark|Toledo|Orlando|Chula Vista|Irvine|Fort Wayne|Jersey City|Durham|Laredo|Buffalo|Gilbert|Glendale|Reno|Chandler|Scottsdale|Norfolk|Fremont|Spokane|Modesto|Fontana|Moreno Valley|Santa Clarita|Oxnard|Huntington Beach|Elk Grove|Roseville|Folsom|Davis|Rancho Cordova|Citrus Heights|Vacaville|Santa Rosa|Berkeley|Palo Alto|Pasadena|Sunnyvale|Santa Barbara|Salinas|Visalia|Redding|Chico|Eureka|San Bernardino|Ontario|Torrance|Burbank|Santa Monica|Escondido|Oceanside|Carlsbad|Temecula|Palm Springs|Lodi|Merced|Tracy|Manteca|Petaluma|Napa|Hayward|Walnut Creek|Livermore|Pleasanton|Grand Rapids|Ann Arbor|Rochester|Syracuse|Knoxville|Chattanooga|Birmingham|Savannah|Provo|Ogden|Flagstaff|Yuma|Las Vegas|Eugene|Tacoma|Bellevue|Everett|Vancouver|Boulder|Fort Collins|Lubbock|Amarillo|Waco|McAllen|Brownsville|Fargo|Sioux Falls|Billings|Missoula|Bozeman|Burlington|Manchester|Worcester|Cambridge|Stamford|New Haven|Wilmington|Allentown|Erie|Akron|Dayton|Evansville|Peoria|Rockford|Green Bay|Duluth|Shreveport|Mobile|Huntsville|Fayetteville|Orange|Irving|Garland|Hialeah|Lakeland|Clearwater|Gainesville|Pensacola|Naples|Asheville|Greenville|Myrtle Beach|Toronto|Montreal|Ottawa|Calgary|Edmonton|London|Paris|Berlin|Madrid|Rome|Dublin|Sydney|Melbourne|Auckland|Mexico City|Tokyo".split("|")
    function distance(a, b) { // how many letters to change to get from a to b
        const d = [];
        for (let i = 0; i <= a.length; i++) d.push([i]);
        for (let j = 1; j <= b.length; j++) d[0][j] = j;
        for (let i = 1; i <= a.length; i++)
            for (let j = 1; j <= b.length; j++)
                d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
        return d[a.length][b.length];
    }
    function closest(word, list) { // the name in list nearest to word: 1 or 2 letters wrong at most
        const w = word.toLowerCase(), most = w.length <= 4 ? 1 : 2;
        let best = "", bestD = most + 1;
        for (let i = 0; i < list.length; i++) {
            const dd = distance(w, list[i].toLowerCase());
            if (dd < bestD) { best = list[i]; bestD = dd; }
        }
        return best;
    }
    function searchPlaces(name, done) { // done(results, error text)
        const test = arg("places"); // tests: a folder with NAME.json files
        const url = test ? test + "/" + encodeURIComponent(name.toLowerCase()) + ".json"
            : "https://geocoding-api.open-meteo.com/v1/search?count=10&language=en&format=json&name=" + encodeURIComponent(name);
        getJSON(url, function (j, status) {
            if (j) done(j.results || [], "");
            else if (test) done([], "");
            else if (!status) done([], "Can't reach the town finder. Is the internet on?");
            else done([], "The town finder isn't working right now (error " + status + "). Try again later.");
        });
    }
    function rankPlaces(found, hint) {
        hint = hint.replace(/[.,]/g, " ").trim();
        if (!hint) return found;
        const words = [hint.toLowerCase()];
        if (usStates[hint.toUpperCase()]) words.push(usStates[hint.toUpperCase()].toLowerCase());
        else if (hint.length >= 4) { // a state, maybe spelt a bit wrong ("calinfonia")
            const st = closest(hint, Object.keys(usStates).map(k => usStates[k]));
            if (st) words.push(st.toLowerCase());
        }
        const fits = r => [r.admin1, r.admin2, r.country, r.country_code].some(v => v && words.some(w => v.toLowerCase() === w || v.toLowerCase().indexOf(w) === 0));
        const good = found.filter(fits);
        return good.concat(found.filter(r => !fits(r)));
    }
    function findTown(text, done) { // done(places, error text, the name used if it was spelt differently)
        text = text.trim();
        const comma = text.indexOf(",");
        let name = comma < 0 ? text : text.substring(0, comma).trim(), hint = comma < 0 ? "" : text.substring(comma + 1).trim();
        const fixed = {};
        const step = function () {
            searchPlaces(name, function (found, error) {
                if (error) return done([], error, "");
                if (found.length) return done(rankPlaces(found, hint), "", fixed[name] ? name : "");
                // Not found: a spelling slip? Then the word or two before the state?
                const better = closest(name, knownTowns);
                if (better && better.toLowerCase() !== name.toLowerCase() && !fixed[better]) {
                    fixed[better] = true;
                    name = better;
                    return step();
                }
                const words = name.split(/\s+/);
                if (words.length < 2) return done([], "", "");
                hint = (words.pop() + " " + hint).trim();
                name = words.join(" ");
                step();
            });
        };
        if (name.length < 2) return done([], "", "");
        step();
    }
    function loadWeather() {
        if (!arg("weather") && !plan.town) { forecast = null; weatherNote = "Pick your town in Settings to see the weather."; weatherDone(); return; }
        weatherNote = "Getting the weather...";
        const url = arg("weather") || ("https://api.open-meteo.com/v1/forecast?latitude=" + plan.lat + "&longitude=" + plan.lon
            + "&hourly=temperature_2m,precipitation_probability,weather_code"
            + "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,uv_index_max"
            + "&timezone=auto&forecast_days=3");
        getJSON(url, function (j) {
            if (j && j.hourly && j.daily) { forecast = j; weatherNote = ""; }
            else { forecast = null; weatherNote = "No weather right now (is the internet on?). Here is what your activities need."; }
            weatherDone();
        });
    }
    function weatherDone() { changes++; if (arg("morning") === "1") remind(); }
    Timer { interval: 30 * 60 * 1000; running: win.visible; repeat: true; onTriggered: win.loadWeather() }

    function ymd(d) { const two = n => (n < 10 ? "0" : "") + n; return d.getFullYear() + "-" + two(d.getMonth() + 1) + "-" + two(d.getDate()); }
    function dayDate(n) { const d = new Date(); d.setHours(12, 0, 0, 0); d.setDate(d.getDate() + n); return d; }

    // The weather on day N (0 today), for the school day (7:00 to 16:00).
    function weatherOn(n) {
        if (!forecast) return null;
        const key = ymd(dayDate(n)), h = forecast.hourly, w = { codes: [], rain: 0, t8: null, t15: null, uv: 0, max: null, min: null };
        for (let i = 0; i < h.time.length; i++) {
            if (h.time[i].indexOf(key) !== 0) continue;
            const hour = parseInt(h.time[i].substring(11, 13));
            if (hour === 8) w.t8 = h.temperature_2m[i];
            if (hour === 15) w.t15 = h.temperature_2m[i];
            if (hour >= 7 && hour <= 16) {
                w.codes.push(h.weather_code[i]);
                w.rain = Math.max(w.rain, h.precipitation_probability[i] || 0);
            }
        }
        const di = forecast.daily.time.indexOf(key);
        if (di < 0 && w.t8 === null) return null;
        if (di >= 0) {
            w.max = forecast.daily.temperature_2m_max[di];
            w.min = forecast.daily.temperature_2m_min[di];
            w.uv = (forecast.daily.uv_index_max || [])[di] || 0;
            w.rain = Math.max(w.rain, (forecast.daily.precipitation_probability_max || [])[di] || 0);
            if (!w.codes.length) w.codes.push(forecast.daily.weather_code[di]);
        }
        if (w.t8 === null) w.t8 = w.min !== null ? w.min + (w.max - w.min) * 0.3 : null;
        if (w.t15 === null) w.t15 = w.max;
        // The kind of day: the worst weather in school hours.
        const has = test => w.codes.some(test);
        w.kind = has(c => c >= 95) ? "storm"
            : has(c => (c >= 71 && c <= 77) || c === 85 || c === 86) ? "snow"
            : (has(c => (c >= 51 && c <= 67) || (c >= 80 && c <= 82)) || w.rain >= 50) ? "rain"
            : has(c => c === 45 || c === 48) ? "fog"
            : has(c => c === 2 || c === 3) ? "cloudy"
            : has(c => c === 1) ? "partly" : "sunny";
        return w;
    }

    // What to wear and pack on day N: { title, summary, wear, pack, acts, w }.
    function advice(n) {
        changes; // (bindings: again when the plan or the weather changes)
        const date = dayDate(n), day = date.getDay(), acts = activities(day), w = weatherOn(n);
        const wear = [], pack = [], say = [];
        const add = (list, t) => { if (list.indexOf(t) < 0) list.push(t); };
        const school = day >= 1 && day <= 5;
        let boots = false;
        if (w) {
            const t = w.t8;
            const words = { storm: "Stormy", snow: "Snowy", rain: "Rainy", fog: "Foggy", cloudy: "Cloudy", partly: "Some sun", sunny: "Sunny" };
            say.push(words[w.kind] + " and " + temp(t) + " in the morning.");
            if (w.kind === "snow") {
                ["Snow boots", "Winter coat", "Hat", "Gloves"].forEach(x => add(wear, x));
                boots = true;
                say.push("Wear your snow boots and winter coat.");
            } else if (w.kind === "rain" || w.kind === "storm") {
                ["Rain boots", "Raincoat with a hood"].forEach(x => add(wear, x));
                add(pack, "Umbrella");
                boots = true;
                say.push("Wear your rain boots and raincoat.");
            }
            if (t !== null) {
                if (t < 0) ["Winter coat", "Hat", "Gloves", "Warm socks"].forEach(x => add(wear, x));
                else if (t < 8) ["Warm coat", "Hat"].forEach(x => add(wear, x));
                else if (t < 14) add(wear, "Jacket");
                else if (t < 20) add(wear, "Hoodie or sweater");
                else if (t < 26) add(wear, "T-shirt");
                else { add(wear, "Shorts and a T-shirt"); add(pack, "Water bottle"); }
                if (w.kind !== "snow" && t < 0) say.push("It's freezing: wear a winter coat, a hat and gloves.");
                else if (w.kind !== "snow" && w.kind !== "rain" && w.kind !== "storm" && t < 8) say.push("It's cold: wear a warm coat.");
                if (t >= 26) say.push("It's hot: wear shorts and bring water.");
                if (w.t15 !== null && w.t15 - t >= 8) {
                    add(wear, "Layers you can take off");
                    say.push("It gets warmer, " + temp(w.t15) + " after school: wear layers.");
                }
            }
            if ((w.kind === "sunny" || w.kind === "partly") && w.uv >= 6) { add(pack, "Sunscreen"); add(wear, "Sun hat"); }
        }
        for (let i = 0; i < acts.length; i++) {
            const a = acts[i], p = preset(a.kind);
            if (a.kind === "pe") {
                if (boots) {
                    ["Sneakers", "Dry socks"].forEach(x => add(pack, x));
                    say.push("You have P.E.: pack sneakers and socks in your bag.");
                } else {
                    p.wear.forEach(x => add(wear, x));
                    say.push("You have P.E.: wear sneakers and socks.");
                }
                p.bring.forEach(x => add(pack, x));
            } else if (p) {
                p.wear.forEach(x => add(wear, x));
                p.bring.forEach(x => add(pack, x));
                if (p.bring.length) say.push(p.name + ": bring " + p.bring[0].charAt(0).toLowerCase() + p.bring[0].substring(1) + ".");
            } else if (a.bring) {
                add(pack, a.bring.charAt(0).toUpperCase() + a.bring.substring(1));
                say.push(a.name + ": bring " + a.bring + ".");
            }
        }
        if (school) add(pack, "Homework folder");
        if (!school && !acts.length) say.push("No school.");
        return {
            title: (n === 0 ? "Today, " : n === 1 ? "Tomorrow, " : "") + dayNames[day],
            summary: say.join(" "), wear: wear, pack: pack, acts: acts, w: w, school: school
        };
    }

    // --- The morning reminder (morning=1): today, or tomorrow after school ---
    function remind() {
        const n = new Date().getHours() >= 15 ? 1 : 0, a = advice(n);
        if (plan.reminder !== false && (a.school || a.acts.length))
            console.log("OLLIE-ACTION notify " + a.title + "|" + (a.summary || "Have a good day.").replace(/\n/g, " "));
        Qt.quit();
    }
    Timer { interval: 20000; running: win.arg("morning") === "1"; onTriggered: { win.forecast = null; win.remind(); } }

    Component.onCompleted: {
        try { const d = JSON.parse(arg("data")); if (d && typeof d === "object") plan = Object.assign(plan, d); } catch (e) {}
        if (!plan.days) plan.days = {};
        loadWeather();
    }

    // --- Pieces ---
    component Btn: Rectangle {
        id: b
        property string text
        property bool on: false
        property bool strong: false
        signal clicked
        implicitWidth: lab.implicitWidth + 32
        implicitHeight: 40
        radius: 6
        color: on || strong ? win.navy : area.containsMouse ? "#EAE3D6" : "white"
        border.color: on || strong ? win.navy : win.line
        opacity: enabled ? 1 : 0.45
        Label { id: lab; anchors.centerIn: parent; text: b.text; color: b.on || b.strong ? "white" : win.ink; font.pixelSize: 15; font.bold: b.strong }
        MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
    }
    component Card: Rectangle { color: "white"; radius: 10; border.color: win.line }
    component ListOf: ColumnLayout { // a list with a coloured mark for each line
        id: lo
        property string heading
        property var items: []
        property color mark: win.bus
        spacing: 8
        Label { text: lo.heading; color: win.navy; font.pixelSize: 18; font.bold: true }
        Repeater {
            model: lo.items
            delegate: RowLayout {
                required property string modelData
                spacing: 10
                Rectangle { width: 12; height: 12; radius: 3; color: lo.mark }
                Label { text: modelData; color: win.ink; font.pixelSize: 16; wrapMode: Text.Wrap; Layout.fillWidth: true }
            }
        }
        Label { visible: !lo.items.length; text: "Nothing special."; color: win.soft; font.pixelSize: 15 }
    }

    // A drawing of the weather.
    component Sky: Canvas {
        id: sky
        property string kind: "sunny"
        onKindChanged: requestPaint()
        onPaint: {
            const c = getContext("2d"), s = width / 100;
            c.reset();
            c.lineCap = "round"; c.lineJoin = "round";
            function sun(x, y, r) {
                c.fillStyle = "#E9B13A"; c.strokeStyle = "#E9B13A"; c.lineWidth = 4 * s;
                c.beginPath(); c.arc(x * s, y * s, r * s, 0, 2 * Math.PI); c.fill();
                for (let i = 0; i < 8; i++) {
                    const a = i * Math.PI / 4;
                    c.beginPath(); c.moveTo((x + Math.cos(a) * (r + 6)) * s, (y + Math.sin(a) * (r + 6)) * s);
                    c.lineTo((x + Math.cos(a) * (r + 13)) * s, (y + Math.sin(a) * (r + 13)) * s); c.stroke();
                }
            }
            function cloud(x, y, col) { // three puffs and a flat bottom, each filled on its own
                c.fillStyle = col;
                [[x - 16, y + 4, 13], [x + 2, y - 6, 18], [x + 20, y + 4, 13]].forEach(p => {
                    c.beginPath(); c.arc(p[0] * s, p[1] * s, p[2] * s, 0, 2 * Math.PI); c.fill();
                });
                c.fillRect((x - 16) * s, (y + 4) * s, 36 * s, 13 * s);
            }
            const k = sky.kind;
            if (k === "sunny") sun(50, 50, 20);
            if (k === "partly") { sun(62, 38, 15); cloud(44, 58, "#C9CED6"); }
            if (k === "cloudy" || k === "fog") { cloud(56, 40, "#B4BAC4"); cloud(42, 56, "#C9CED6"); }
            if (k === "fog") { c.strokeStyle = "#9AA0AA"; c.lineWidth = 4 * s; [78, 88].forEach(y => { c.beginPath(); c.moveTo(22 * s, y * s); c.lineTo(78 * s, y * s); c.stroke(); }); }
            if (k === "rain" || k === "storm" || k === "snow") cloud(50, 40, k === "storm" ? "#7D8592" : "#9AA3B0");
            if (k === "rain" || k === "storm") {
                c.strokeStyle = "#336B9E"; c.lineWidth = 4 * s;
                [[34, 66], [50, 70], [66, 66], [42, 82], [58, 86]].forEach(p => { c.beginPath(); c.moveTo(p[0] * s, p[1] * s); c.lineTo((p[0] - 4) * s, (p[1] + 9) * s); c.stroke(); });
            }
            if (k === "storm") {
                c.fillStyle = "#E9B13A"; c.beginPath();
                c.moveTo(54 * s, 56 * s); c.lineTo(42 * s, 76 * s); c.lineTo(51 * s, 76 * s); c.lineTo(45 * s, 94 * s); c.lineTo(62 * s, 70 * s); c.lineTo(53 * s, 70 * s); c.closePath(); c.fill();
            }
            if (k === "snow") {
                c.fillStyle = "#8FB7DD";
                [[34, 70], [50, 76], [66, 70], [42, 88], [58, 90]].forEach(p => { c.beginPath(); c.arc(p[0] * s, p[1] * s, 4 * s, 0, 2 * Math.PI); c.fill(); });
            }
        }
    }

    // --- The window ---
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle { // the top bar
            Layout.fillWidth: true
            Layout.preferredHeight: 76
            color: win.navy
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 24; anchors.rightMargin: 24
                spacing: 10
                Image { source: "file:///usr/share/icons/hicolor/64x64/apps/ollie-school.png"; sourceSize: Qt.size(40, 40) }
                ColumnLayout {
                    spacing: 0
                    Label { text: "School Planner"; color: "white"; font.pixelSize: 24; font.bold: true }
                    Label { text: (win.changes, win.plan.town) ? "Weather for " + win.plan.town : "Your school week, and what to wear"; color: "#C9D3E6"; font.pixelSize: 13 }
                }
                Item { Layout.fillWidth: true }
                Repeater {
                    model: ["Today", "Tomorrow", "My week", "Settings"]
                    delegate: Rectangle {
                        required property string modelData
                        required property int index
                        width: tl.implicitWidth + 30; height: 40; radius: 6
                        color: win.page === index ? win.bus : tabArea.containsMouse ? "#35497A" : "transparent"
                        Label { id: tl; anchors.centerIn: parent; text: modelData; font.pixelSize: 16; font.bold: win.page === index; color: win.page === index ? win.ink : "white" }
                        MouseArea { id: tabArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.page = index }
                    }
                }
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: win.page === 1 ? 0 : win.page === 0 ? 0 : win.page - 1

            // Today / Tomorrow
            Item {
                id: dayPage
                readonly property var a: win.advice(win.page === 1 ? 1 : 0)
                RowLayout {
                    anchors.fill: parent; anchors.margins: 24
                    spacing: 20
                    Card {
                        Layout.preferredWidth: 360
                        Layout.fillHeight: true
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 22
                            spacing: 10
                            Label { text: dayPage.a.title; color: win.navy; font.pixelSize: 26; font.bold: true }
                            Sky {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth: 170; Layout.preferredHeight: 170
                                visible: dayPage.a.w !== null
                                kind: dayPage.a.w ? dayPage.a.w.kind : "sunny"
                            }
                            Label {
                                visible: dayPage.a.w !== null
                                text: dayPage.a.w ? "Morning " + win.temp(dayPage.a.w.t8) + "     After school " + win.temp(dayPage.a.w.t15) : ""
                                color: win.ink; font.pixelSize: 17; Layout.alignment: Qt.AlignHCenter
                            }
                            Label {
                                visible: dayPage.a.w !== null
                                text: dayPage.a.w ? "Chance of rain " + Math.round(dayPage.a.w.rain) + "%" : ""
                                color: win.soft; font.pixelSize: 15; Layout.alignment: Qt.AlignHCenter
                            }
                            Label {
                                visible: win.weatherNote !== ""
                                text: win.weatherNote; color: win.soft; font.pixelSize: 15
                                wrapMode: Text.Wrap; Layout.fillWidth: true
                            }
                            Rectangle { Layout.fillWidth: true; height: 1; color: win.line }
                            Label { text: dayPage.a.school ? "At school" : "Activities"; color: win.navy; font.pixelSize: 18; font.bold: true }
                            Flow {
                                Layout.fillWidth: true
                                spacing: 8
                                Repeater {
                                    model: dayPage.a.acts
                                    delegate: Rectangle {
                                        required property var modelData
                                        width: an.implicitWidth + 24; height: 34; radius: 17; color: "#FBEFD2"; border.color: win.bus
                                        Label { id: an; anchors.centerIn: parent; text: modelData.name; color: win.ink; font.pixelSize: 15 }
                                    }
                                }
                            }
                            Label {
                                visible: !dayPage.a.acts.length
                                text: dayPage.a.school ? "Nothing special. Add activities in My week." : "No school."
                                color: win.soft; font.pixelSize: 15; wrapMode: Text.Wrap; Layout.fillWidth: true
                            }
                            Item { Layout.fillHeight: true }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 20
                        Rectangle { // the plan for the day, in a sentence or three
                            Layout.fillWidth: true
                            Layout.preferredHeight: sumText.implicitHeight + 40
                            color: "#FBEFD2"; radius: 10; border.color: win.bus
                            Label {
                                id: sumText
                                anchors.fill: parent; anchors.margins: 20
                                text: dayPage.a.summary || "Have a good day."
                                color: win.ink; font.pixelSize: 20; wrapMode: Text.Wrap
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 20
                            Card {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                ListOf { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 22; heading: "Wear"; items: dayPage.a.wear; mark: "#336B9E" }
                            }
                            Card {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                ListOf { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 22; heading: "Pack in your bag"; items: dayPage.a.pack; mark: "#4F8A45" }
                            }
                        }
                    }
                }
            }

            // My week
            Item {
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 24
                    spacing: 14
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14
                        Label { text: "Add what you do each day. The planner tells you what you need."; color: win.ink; font.pixelSize: 17 }
                        Item { Layout.fillWidth: true }
                        Label { text: win.savedNote; color: "#4F8A45"; font.pixelSize: 16; font.bold: true }
                        Btn { text: "Save"; strong: true; implicitWidth: 120; onClicked: win.pressSave("Saved.") }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 10
                        Repeater {
                            model: win.weekOrder
                            delegate: Card {
                                id: dayCard
                                required property int modelData
                                readonly property bool today: new Date().getDay() === modelData
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                color: modelData === 0 || modelData === 6 ? "#FAF7F1" : "white"
                                border.color: today ? win.bus : win.line
                                border.width: today ? 3 : 1
                                ColumnLayout {
                                    anchors.fill: parent; anchors.margins: 10
                                    spacing: 6
                                    Label { text: win.dayNames[dayCard.modelData].substring(0, 3); color: win.navy; font.pixelSize: 18; font.bold: true; Layout.alignment: Qt.AlignHCenter }
                                    Label { text: dayCard.today ? "today" : " "; color: win.soft; font.pixelSize: 12; Layout.alignment: Qt.AlignHCenter }
                                    Repeater {
                                        model: { win.changes; return win.activities(dayCard.modelData); }
                                        delegate: Rectangle {
                                            required property var modelData
                                            required property int index
                                            Layout.fillWidth: true
                                            height: 36; radius: 6; color: "#FBEFD2"; border.color: win.bus
                                            Label { anchors.left: parent.left; anchors.leftMargin: 8; anchors.right: x.left; anchors.verticalCenter: parent.verticalCenter
                                                text: modelData.name; color: win.ink; font.pixelSize: 14; elide: Text.ElideRight }
                                            Label {
                                                id: x
                                                anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                                                text: "×"; color: win.soft; font.pixelSize: 20
                                                MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: win.removeActivity(dayCard.modelData, index) }
                                            }
                                        }
                                    }
                                    Btn { text: "+ Add"; Layout.fillWidth: true; onClicked: { picker.day = dayCard.modelData; picker.open(); } }
                                    Item { Layout.fillHeight: true }
                                }
                            }
                        }
                    }
                }
            }

            // Settings
            Item {
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 24
                    spacing: 16
                    Card {
                        Layout.fillWidth: true
                        Layout.preferredHeight: townCol.implicitHeight + 40
                        ColumnLayout {
                            id: townCol
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 20
                            spacing: 10
                            Label { text: "Your town"; color: win.navy; font.pixelSize: 18; font.bold: true }
                            Label { text: (win.changes, win.plan.town) ? "Now: " + win.plan.town : "Type your town, then Find."; color: win.ink; font.pixelSize: 15 }
                            RowLayout {
                                spacing: 10
                                TextField {
                                    id: townField
                                    Layout.preferredWidth: 360
                                    placeholderText: "Town, like Seattle or Seattle, WA"
                                    font.pixelSize: 16
                                    color: win.ink
                                    implicitHeight: 40; leftPadding: 10
                                    background: Rectangle { color: "white"; radius: 6; border.color: win.line }
                                    onAccepted: findBtn.clicked()
                                }
                                Btn {
                                    id: findBtn; text: "Find"; strong: true
                                    onClicked: {
                                        if (!townField.text.trim()) return;
                                        places.text = "Looking...";
                                        places.found = [];
                                        win.findTown(townField.text, function (found, error, spelt) {
                                            places.found = found.slice(0, 8);
                                            places.text = error || (found.length ? (spelt ? "Did you mean " + spelt + "? " : "") + "Which one? Click your town."
                                                : "No town called that. Type only the town's name, like Springfield, or its ZIP code.");
                                        });
                                    }
                                }
                            }
                            Label { id: places; property var found: []; text: ""; visible: text !== ""; color: win.soft; font.pixelSize: 15 }
                            Repeater {
                                model: places.found
                                delegate: Btn {
                                    required property var modelData
                                    text: [modelData.name, modelData.admin1, modelData.country].filter(s => s).join(", ")
                                    onClicked: {
                                        win.plan.town = modelData.name + (modelData.admin1 ? ", " + modelData.admin1 : "");
                                        win.plan.lat = modelData.latitude; win.plan.lon = modelData.longitude;
                                        places.found = []; places.text = ""; townField.text = "";
                                        win.loadWeather(); win.pressSave("Saved: " + win.plan.town); win.changes++;
                                    }
                                }
                            }
                        }
                    }
                    Card {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 130
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 20
                            spacing: 10
                            Label { text: "Temperatures in"; color: win.navy; font.pixelSize: 18; font.bold: true }
                            RowLayout {
                                spacing: 10
                                Btn { text: "°F (Fahrenheit)"; on: win.changes >= 0 && win.unit() === "F"; onClicked: { win.plan.unit = "F"; win.save(); } }
                                Btn { text: "°C (Celsius)"; on: win.changes >= 0 && win.unit() === "C"; onClicked: { win.plan.unit = "C"; win.save(); } }
                            }
                        }
                    }
                    Card {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 110
                        RowLayout {
                            anchors.fill: parent; anchors.margins: 20
                            spacing: 12
                            CheckBox { id: remindBox; checked: win.changes >= 0 && win.plan.reminder !== false; onToggled: { win.plan.reminder = checked; win.save(); } }
                            ColumnLayout {
                                spacing: 2
                                Label { text: "Tell me in the morning"; color: win.ink; font.pixelSize: 17; font.bold: true
                                    MouseArea { anchors.fill: parent; onClicked: { win.plan.reminder = !remindBox.checked; win.save(); } } }
                                Label { text: "When you log in on a school day, a note says what to wear and pack. After 3 pm, it is for tomorrow."; color: win.soft; font.pixelSize: 14 }
                            }
                            Item { Layout.fillWidth: true }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14
                        Label { text: "Weather by Open-Meteo.com"; color: win.soft; font.pixelSize: 12 }
                        Item { Layout.fillWidth: true }
                        Label { text: win.savedNote; color: "#4F8A45"; font.pixelSize: 16; font.bold: true }
                        Btn {
                            text: "Save"; strong: true; implicitWidth: 120
                            onClicked: {
                                const typed = townField.text.trim();
                                if (!typed) { win.pressSave("Saved."); return; }
                                // A town typed but not clicked: the best one for it.
                                win.savedNote = "Looking for " + typed + "...";
                                win.findTown(typed, function (found, error) {
                                    if (!found.length) { win.savedNote = ""; places.text = error || "No town called that. Type only the town's name, like Springfield, or its ZIP code."; return; }
                                    const t = found[0];
                                    win.plan.town = t.name + (t.admin1 ? ", " + t.admin1 : "");
                                    win.plan.lat = t.latitude; win.plan.lon = t.longitude;
                                    places.found = []; places.text = ""; townField.text = "";
                                    win.changes++; win.loadWeather();
                                    win.pressSave("Saved: " + win.plan.town);
                                });
                            }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
            }
        }
    }

    // Adding an activity to a day.
    Popup {
        id: picker
        property int day: 1
        anchors.centerIn: parent
        width: 640; modal: true; padding: 24
        background: Rectangle { color: win.paper; radius: 12; border.color: win.line }
        onOpened: customName.text = customBring.text = ""
        ColumnLayout {
            anchors.left: parent.left; anchors.right: parent.right
            spacing: 14
            Label { text: "Add to " + win.dayNames[picker.day]; color: win.navy; font.pixelSize: 22; font.bold: true }
            Flow {
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: win.presets
                    delegate: Btn {
                        required property var modelData
                        text: modelData.name
                        onClicked: { win.addActivity(picker.day, { kind: modelData.kind, name: modelData.name }); picker.close(); }
                    }
                }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: win.line }
            Label { text: "Something else"; color: win.navy; font.pixelSize: 17; font.bold: true }
            RowLayout {
                spacing: 10
                TextField { id: customName; placeholderText: "What is it?"; Layout.preferredWidth: 200; color: win.ink; font.pixelSize: 15
                    implicitHeight: 40; leftPadding: 10
                                    background: Rectangle { color: "white"; radius: 6; border.color: win.line } }
                TextField { id: customBring; placeholderText: "What to bring (if anything)"; Layout.fillWidth: true; color: win.ink; font.pixelSize: 15
                    implicitHeight: 40; leftPadding: 10
                                    background: Rectangle { color: "white"; radius: 6; border.color: win.line } }
                Btn {
                    text: "Add"; strong: true; enabled: customName.text.trim() !== ""
                    onClicked: { win.addActivity(picker.day, { kind: "custom", name: customName.text.trim(), bring: customBring.text.trim() }); picker.close(); }
                }
            }
        }
    }
}
