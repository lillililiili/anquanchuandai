import base64
import json
import os
import subprocess
import time
import urllib.request
from pathlib import Path

import requests
import websocket

CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
PORT = 9333
USER_DIR = Path(os.environ["TEMP"]) / "melhat-logo-verify-chrome"
OUT = Path(r"E:\沉积岩\分体式安全帽代码\pc前端代码\melhat_pc-main") / "scripts" / "logo-verify"
BASE = "http://127.0.0.1:5175"
OUT.mkdir(parents=True, exist_ok=True)


class Cdp:
    def __init__(self, url):
        self.ws = websocket.create_connection(url, timeout=20)
        self.id = 0

    def call(self, method, **params):
        self.id += 1
        msg_id = self.id
        self.ws.send(json.dumps({"id": msg_id, "method": method, "params": params}))
        deadline = time.time() + 30
        while time.time() < deadline:
            raw = self.ws.recv()
            data = json.loads(raw)
            if data.get("id") == msg_id:
                if "error" in data:
                    raise RuntimeError(f"{method}: {data['error']}")
                return data.get("result", {})
        raise TimeoutError(method)

    def eval(self, expression):
        result = self.call(
            "Runtime.evaluate",
            expression=expression,
            returnByValue=True,
            awaitPromise=True,
        )
        return result.get("result", {}).get("value")

    def wait_expr(self, expression, timeout=20):
        deadline = time.time() + timeout
        last = None
        while time.time() < deadline:
            try:
                last = self.eval(expression)
                if last:
                    return last
            except Exception:
                last = None
            time.sleep(0.25)
        return last

    def screenshot(self, name):
        data = self.call("Page.captureScreenshot", format="png", fromSurface=True)
        path = OUT / name
        path.write_bytes(base64.b64decode(data["data"]))
        print("saved", path)
        return path


def wait_page():
    deadline = time.time() + 20
    last_err = None
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{PORT}/json/list", timeout=1) as resp:
                pages = json.load(resp)
            for page in pages:
                if page.get("type") == "page" and page.get("webSocketDebuggerUrl"):
                    return page
        except Exception as exc:
            last_err = exc
        time.sleep(0.2)
    raise RuntimeError(f"cdp page not up: {last_err}")


def main():
    proc = subprocess.Popen(
        [
            CHROME,
            "--headless=new",
            "--disable-gpu",
            f"--remote-debugging-port={PORT}",
            f"--user-data-dir={USER_DIR}",
            "--window-size=1440,900",
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-extensions",
            "--hide-crash-restore-bubble",
            "--remote-allow-origins=*",
            "about:blank",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        page = wait_page()
        cdp = Cdp(page["webSocketDebuggerUrl"])
        cdp.call("Page.enable")
        cdp.call("Runtime.enable")
        cdp.call("Emulation.setDeviceMetricsOverride", width=1440, height=900, deviceScaleFactor=1, mobile=False)

        cdp.call("Page.navigate", url=f"{BASE}/login")
        cdp.wait_expr("document.querySelector('.brand-mark img')", timeout=15)
        time.sleep(0.8)

        login_info = cdp.eval(
            """(() => {
              const img = document.querySelector('.brand-mark img');
              const icons = [...document.querySelectorAll('link[rel~="icon"]')].map(l => ({
                rel: l.rel, href: l.href, type: l.type || ''
              }));
              return {
                title: document.title,
                favicons: icons,
                logoSrc: img && img.currentSrc,
                complete: img && img.complete,
                naturalWidth: img && img.naturalWidth,
                naturalHeight: img && img.naturalHeight,
                display: img && getComputedStyle(img).display,
                box: img && img.getBoundingClientRect().toJSON()
              };
            })()"""
        )
        print("LOGIN", json.dumps(login_info, ensure_ascii=False, indent=2))
        cdp.screenshot("login.png")

        token = None
        try:
            resp = requests.post(
                "http://127.0.0.1:18084/login",
                json={"username": "admin", "password": "admin123"},
                timeout=8,
            )
            body = resp.json()
            print("API login", body.get("code"), body.get("msg"))
            if body.get("code") == 200:
                token = body.get("token")
        except Exception as exc:
            print("API login failed", exc)

        if token:
            cdp.eval(f"sessionStorage.setItem('Admin-Token', {json.dumps(token)})")
            cdp.call("Page.navigate", url=f"{BASE}/")
        else:
            cdp.eval(
                """(() => {
                  const user = document.querySelector('#login-username');
                  const pass = document.querySelector('#login-password');
                  const setVal = (el, value) => {
                    const input = el.tagName === 'INPUT' ? el : el.querySelector('input');
                    const desc = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
                    desc.set.call(input, value);
                    input.dispatchEvent(new Event('input', { bubbles: true }));
                  };
                  setVal(user, 'admin');
                  setVal(pass, 'admin123');
                  const btn = [...document.querySelectorAll('button')].find(b => b.textContent.includes('登录'));
                  btn && btn.click();
                })()"""
            )

        cdp.wait_expr("document.querySelector('.sidebar-logo-icon')", timeout=25)
        time.sleep(1.2)
        sidebar_info = cdp.eval(
            """(() => {
              const img = document.querySelector('.sidebar-logo-icon');
              const icons = [...document.querySelectorAll('link[rel~="icon"]')].map(l => ({
                rel: l.rel, href: l.href
              }));
              return {
                path: location.pathname,
                title: document.title,
                favicons: icons,
                logoSrc: img && img.currentSrc,
                complete: img && img.complete,
                naturalWidth: img && img.naturalWidth,
                box: img && img.getBoundingClientRect().toJSON()
              };
            })()"""
        )
        print("SIDEBAR", json.dumps(sidebar_info, ensure_ascii=False, indent=2))
        cdp.screenshot("sidebar.png")

        ico = requests.get(f"{BASE}/favicon.ico", timeout=5)
        png = requests.get(f"{BASE}/favicon.png", timeout=5)
        print("favicon.ico", ico.status_code, ico.headers.get("content-type"), len(ico.content))
        print("favicon.png", png.status_code, png.headers.get("content-type"), len(png.content))
        (OUT / "favicon.ico").write_bytes(ico.content)
        (OUT / "favicon.png").write_bytes(png.content)
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except Exception:
            proc.kill()


if __name__ == "__main__":
    main()
