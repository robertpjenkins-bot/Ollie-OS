#!/usr/bin/env python3
"""Finds the official download link of a Windows 10 or 11 ISO (64-bit,
English), from Microsoft's own download page, the way its web page gets it:
the newest release's edition, a session, the language's SKU, then the link
(it works for about 24 hours). Prints the link; on a problem, says why on
stderr and exits 1 (Microsoft sometimes refuses automatic downloads: then
download the ISO in a browser and pick the file instead).

    get-windows.py 10|11 [LANGUAGE]     (LANGUAGE: "English (United States)")
"""
import json
import re
import sys
import time
import urllib.parse
import urllib.request
import uuid

UA = "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"
PROFILE = "606624d44113"
API = "https://www.microsoft.com/software-download-connector/api/"


def get(url, referer=None):
    headers = {"User-Agent": UA, "Accept": "*/*"}
    if referer:
        headers["Referer"] = referer
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=60) as r:
        return r.read(2_000_000).decode("utf-8", "replace")


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("10", "11"):
        sys.exit(__doc__)
    version = sys.argv[1]
    language = sys.argv[2] if len(sys.argv) > 2 else "English (United States)"
    page = "https://www.microsoft.com/en-us/software-download/windows" + ("11" if version == "11" else "10ISO")

    html = get(page)
    # The newest release is the first edition offered.
    m = re.search(r'<option value="([0-9]+)">Windows', html)
    if not m:
        sys.exit("Microsoft's download page did not offer a Windows " + version + " ISO.")
    edition = m.group(1)

    session = str(uuid.uuid4())
    try:  # lets the session ask for links (the page does this too)
        get("https://vlscppe.microsoft.com/tags?org_id=y6jn8c31&session_id=" + session, page)
    except OSError as e:
        print("(note: Microsoft's session check was not reached: " + str(e) + ")", file=sys.stderr)

    q = {"profile": PROFILE, "ProductEditionId": edition, "SKU": "undefined",
         "friendlyFileName": "undefined", "Locale": "en-US", "sessionID": session}
    skus = json.loads(get(API + "getskuinformationbyproductedition?" + urllib.parse.urlencode(q), page)).get("Skus", [])
    sku = next((s["Id"] for s in skus if language in (s.get("LocalizedLanguage"), s.get("Language"))), None)
    if not sku:
        sku = next((s["Id"] for s in skus if (s.get("Language") or "").startswith("English")), None)
    if not sku:
        sys.exit("Microsoft's download page has no " + language + " Windows " + version + ".")

    q = {"profile": PROFILE, "productEditionId": "undefined", "SKU": sku,
         "friendlyFileName": "undefined", "Locale": "en-US", "sessionID": session}
    text = get(API + "GetProductDownloadLinksBySku?" + urllib.parse.urlencode(q), page)
    if "Sentinel marked this request as rejected" in text or not text.strip():
        sys.exit("Microsoft refused the automatic download from this internet connection.")
    links = [o.get("Uri", "") for o in json.loads(text).get("ProductDownloadOptions", [])]
    links = [u for u in links if u.startswith("https://")]
    link = next((u for u in links if "x64" in u.lower()), links[0] if links else "")
    if not link:
        errors = json.loads(text).get("Errors") or []
        sys.exit("Microsoft gave no download link" + (": " + errors[0].get("Value", "") if errors else "."))
    print(link)


if __name__ == "__main__":
    # Microsoft sometimes turns a first try away ("rejected"): wait, and ask again
    # with a new session (up to 3 tries).
    for attempt in range(3):
        try:
            main()
            break
        except SystemExit as e:
            if attempt < 2 and "refused" in str(e.code):
                print("Microsoft said no; trying again in a few seconds...", file=sys.stderr)
                time.sleep(6)
                continue
            raise
        except (OSError, ValueError) as e:
            sys.exit("Could not reach Microsoft's download page: " + str(e))
