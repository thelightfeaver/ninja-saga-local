#!/usr/bin/env python3
"""Load a SWF in Ruffle, click to start, capture console output + screenshot(s)."""
import sys, os, json, time, urllib.parse
from playwright.sync_api import sync_playwright

ROOT = os.path.dirname(os.path.abspath(__file__))
swf = sys.argv[1]
wait_ms = int(sys.argv[2]) if len(sys.argv) > 2 else 10000
out = sys.argv[3] if len(sys.argv) > 3 else "/tmp/shot.png"
w = int(sys.argv[4]) if len(sys.argv) > 4 else 1100
h = int(sys.argv[5]) if len(sys.argv) > 5 else 800
clicks = sys.argv[6] if len(sys.argv) > 6 else "center"

url = "http://127.0.0.1:8123/arcade/player.html?swf=" + urllib.parse.quote(swf) + f"&w={w}&h={h}"
msgs = []

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True, args=["--use-gl=angle", "--use-angle=swiftshader", "--enable-webgl", "--autoplay-policy=no-user-gesture-required"])
    page = browser.new_page(viewport={"width": w, "height": h}, device_scale_factor=1)
    page.on("console", lambda m: msgs.append(f"[{m.type}] {m.text}"))
    page.on("pageerror", lambda e: msgs.append(f"[pageerror] {e}"))
    page.on("requestfailed", lambda r: msgs.append(f"[reqfail] {r.url} {r.failure}"))
    page.goto(url)
    page.wait_for_timeout(5000)
    if clicks == "center":
        page.mouse.click(w // 2, h // 2)
        page.wait_for_timeout(wait_ms)
    page.screenshot(path=out)
    try:
        info = page.evaluate("""() => {
          const pl = document.querySelector('ruffle-player');
          if (!pl) return null;
          const sr = pl.shadowRoot;
          const c = sr ? sr.querySelector('canvas') : null;
          return {canvas: !!c, cw: c ? c.width : null, ch: c ? c.height : null};
        }""")
    except Exception as e:
        info = str(e)
    browser.close()

print("URL:", url)
print("INFO:", json.dumps(info, indent=1) if isinstance(info, dict) else info)
print("MESSAGES:")
for m in msgs[-120:]:
    print(" ", m[:400])
