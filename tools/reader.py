"""A reader who stays: signs in, reads, then either sleeps (offline, the page
frozen) or holds the page open, tapping a link every few seconds, while the
server goes away and comes back. What SOAK_LOG.md's real-use entries were
measured with.

    uv run --with playwright python tools/reader.py BASE sleep SECONDS [--phone]
    uv run --with playwright python tools/reader.py BASE hold SECONDS [--phone]

The password is UNOTES_PASSWORD from the environment, never an argument, and
never printed. `--phone` is Chrome's Pixel 7 emulation (viewport, touch,
user agent): an emulated phone, not a phone. Every line is stamped with UTC,
to be read beside `fly logs`.
"""

import os
import sys
import time
from datetime import datetime, timezone

from playwright.sync_api import sync_playwright

base, mode, seconds = sys.argv[1].rstrip("/"), sys.argv[2], float(sys.argv[3])
phone = "--phone" in sys.argv
password = os.environ["UNOTES_PASSWORD"]
user = os.environ.get("UNOTES_USER", "reader")
t0 = time.monotonic()


def say(*parts):
    now = datetime.now(timezone.utc).strftime("%H:%M:%S.%f")[:-3]
    print(f"{now} +{time.monotonic() - t0:7.1f}s", *parts, flush=True)


def path(pg):
    return pg.url.replace(base, "") or "/"


def seen(pg):
    """What the reader is looking at, in a few words."""
    if pg.locator("section#unotes").count() == 0:
        return "NO FRAGMENT: " + pg.inner_text("body")[:80].replace("\n", " ")
    if pg.locator("form.login").count():
        alert = pg.locator("[role=alert]")
        return "login form" + (": " + alert.inner_text() if alert.count() else "")
    if pg.locator("div.note").count():
        return pg.inner_text("h1")
    if pg.locator("p.count").count():
        return "list: " + pg.inner_text("p.count").split(" · scanned")[0]
    if pg.locator("ul.facet").count():
        return "keywords"
    if pg.locator("ol li").count():
        return "themes"
    return "other: " + pg.inner_text("section#unotes")[:80].replace("\n", " ")


events = []  # (kind, status or failure, path, when) for every swap and navigation


def on_response(r):
    if r.request.resource_type in ("document", "fetch", "xhr") and r.url.startswith(base):
        events.append(("answer", r.status, r.url.replace(base, ""), time.monotonic()))


def on_failed(r):
    if r.url.startswith(base):
        events.append(("failed", r.failure, r.url.replace(base, ""), time.monotonic()))


def settle(pg, before, timeout=20.0):
    """Wait for the answer (or the failure) to whatever was just done, then
    for the swap to land. Returns the new events."""
    end = time.monotonic() + timeout
    while len(events) == before and time.monotonic() < end:
        pg.wait_for_timeout(50)
    pg.wait_for_timeout(250)
    return events[before:]


def sign_in(pg):
    pg.fill("input[name=user]", user)
    pg.fill("input[name=password]", password)
    before = len(events)
    pg.click("form.login button")
    pg.wait_for_load_state()
    settle(pg, before)


def act(pg, label, do):
    before = len(events)
    started = time.monotonic()
    try:
        do()
    except Exception as e:  # a tap on a page that has lost its links
        say(f"{label}: could not: {str(e).splitlines()[0]}")
        return
    got = settle(pg, before)
    # To the first answer or failure, not to the settle after it.
    took = f"{(got[0][3] - started) * 1000:.0f} ms" if got else "no answer in 20 s"
    answers = ", ".join(f"{s} {p}" for kind, s, p, _ in got)
    say(f"{label}: [{answers}] {took} -> {path(pg)} | {seen(pg)}")


with sync_playwright() as p:
    browser = p.chromium.launch(channel="chrome")
    context = browser.new_context(**p.devices["Pixel 7"]) if phone else browser.new_context()
    pg = context.new_page()
    pg.on("response", on_response)
    pg.on("requestfailed", on_failed)
    say(f"{'emulated phone' if phone else 'desktop'} reader on {base}, {mode} {seconds:g} s")

    pg.goto(base + "/notes")
    sign_in(pg)
    say("signed in ->", path(pg), "|", seen(pg))

    if mode == "sleep":
        pg.fill("input[name=q]", "football")
        act(pg, "filter football", lambda: pg.click("form.filter button"))
        act(pg, "open a note", lambda: pg.click("ul.notes li a >> nth=0"))
        cdp = context.new_cdp_session(pg)
        context.set_offline(True)
        cdp.send("Page.setWebLifecycleState", {"state": "frozen"})
        say(f"asleep: offline, page frozen, for {seconds:g} s")
        time.sleep(seconds)
        cdp.send("Page.setWebLifecycleState", {"state": "active"})
        context.set_offline(False)
        say("awake ->", path(pg), "|", seen(pg))
        act(pg, "tap Themes", lambda: pg.click("nav a >> text=Themes"))
        act(pg, "back", lambda: pg.go_back())
        act(pg, "reload", lambda: pg.reload())
        if pg.locator("form.login").count():
            was = path(pg)
            act(pg, "sign in again", lambda: sign_in(pg))
            say(f"was at {was}, signed in at {path(pg)}")

    elif mode == "hold":
        targets = ["Keywords", "Themes", "Notes"]
        taps = recovered = 0
        while time.monotonic() - t0 < seconds:
            if pg.locator("nav a").count() == 0:
                # What a person does when the links are gone: reload.
                recovered += 1
                act(pg, "reader reloads", lambda: pg.reload())
                if pg.locator("form.login").count():
                    act(pg, "sign in again", lambda: sign_in(pg))
                continue
            target = targets[taps % len(targets)]
            taps += 1
            act(pg, f"tap {target}", lambda: pg.click(f"nav a >> text={target}"))
            pg.wait_for_timeout(2000)
        say(f"held: {taps} taps, {recovered} reloads by the reader")

    failed = [e for e in events if e[0] == "failed"]
    errors = [e for e in events if e[0] == "answer" and e[1] >= 400]
    say(f"{len(events)} requests; {len(failed)} failed, {len(errors)} answered >= 400")
    for e in failed + errors:
        say("  ", *e[:3])
    browser.close()
