import sys
from playwright.sync_api import sync_playwright
base = sys.argv[1]
with sync_playwright() as p:
    b = p.chromium.launch(channel="chrome"); pg = b.new_page()
    errs = []; reqs = []
    pg.on("console", lambda m: errs.append(m.text) if m.type in ("error", "warning") else None)
    pg.on("pageerror", lambda e: errs.append("PAGEERROR " + str(e)))
    pg.on("request", lambda r: reqs.append((r.method, r.url.replace(base, ""), r.headers.get("hx-request-type", "-"))))
    pg.goto(base + "/"); print("1 landed", pg.url.replace(base, ""))
    pg.fill("input[name=user]", "reader"); pg.fill("input[name=password]", "wrong"); pg.click("form.login button")
    pg.wait_for_selector("[role=alert]"); print("2 wrong pw:", pg.inner_text("[role=alert]"), "| url", pg.url.replace(base, ""))
    pg.fill("input[name=user]", "reader"); pg.fill("input[name=password]", "probe-pass"); pg.click("form.login button")
    pg.wait_for_selector("p.count"); print("3 signed in:", pg.inner_text("p.count"), "| url", pg.url.replace(base, ""))
    pg.fill("input[name=q]", "football"); pg.select_option("select[name=era]", "1890s"); pg.click("form.filter button")
    pg.wait_for_function("document.querySelector('p.count').innerText.includes(' of 535') && !document.querySelector('p.count').innerText.startsWith('535')")
    print("4 filtered:", pg.inner_text("p.count"), "| url", pg.url.replace(base, ""))
    pg.click("ul.notes li a >> nth=0"); pg.wait_for_selector("div.note"); print("5 note:", pg.inner_text("h1"), "| url", pg.url.replace(base, ""))
    pg.go_back(); pg.wait_for_selector("p.count"); print("6 back:", pg.inner_text("p.count"), "| url", pg.url.replace(base, ""), "| q field:", pg.input_value("input[name=q]"))
    pg.click("nav a >> text=Themes"); pg.wait_for_selector("ol li"); print("7 themes:", pg.locator("ol li").count(), "| url", pg.url.replace(base, ""))
    pg.click("ol li a >> nth=6"); pg.wait_for_selector("ul.notes"); print("8 theme:", pg.inner_text("h1")[:50], "|", pg.inner_text("p.count"), "| url", pg.url.replace(base, ""))
    pg.goto(base + "/notes?q=chapel&era=1930s"); pg.wait_for_selector("p.count"); print("9 deep link:", pg.inner_text("p.count"))
    pg.click("nav button"); pg.wait_for_selector("form.login"); print("10 signed out | url", pg.url.replace(base, ""))
    pg.goto(base + "/notes"); print("11 after logout:", pg.url.replace(base, ""))
    print("sections in DOM:", pg.locator("section#unotes").count())
    print("console:", errs[:6])
    print("partial requests:", sum(1 for r in reqs if r[2] == "partial"), "of", len(reqs))
    b.close()
