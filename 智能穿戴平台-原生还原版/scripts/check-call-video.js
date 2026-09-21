// Browser integration check, isolated from the user's local data.
async (page) => {
  const context = await page.context().browser().newContext({viewport: {width: 1920, height: 1080}});
  await context.addInitScript(() => sessionStorage.setItem("rolling-session", "admin"));
  const testPage = await context.newPage();
  const errors = [];
  testPage.on("pageerror", error => errors.push(error.message));
  const assert = (value, message) => { if (!value) throw new Error(message); };
  const playing = () => testPage.waitForFunction(() => {
    const videos = [...document.querySelectorAll("video[data-call-video]")];
    return videos.length && videos.every(v => v.readyState >= 2 && !v.paused && v.currentTime > 0.1);
  });
  try {
    await testPage.goto("http://127.0.0.1:5191/#/dispatch");
    await testPage.getByRole("heading", {name: "当前通话：未发起"}).waitFor();
    await testPage.getByRole("checkbox", {name: "全选", exact: true}).check();
    await testPage.getByRole("checkbox", {name: "全选", exact: true}).uncheck();
    await testPage.locator('[data-member="P2"]').check();
    await testPage.getByRole("button", {name: "单呼", exact: true}).click();
    await playing();
    assert(await testPage.locator("video[data-call-video]").count() === 1, "Single call should show one video");
    assert(await testPage.getByText("等待接听 · 画面预览", {exact: true}).count() === 1, "Dialing preview status missing");
    const before = await testPage.locator("video[data-call-video]").evaluate(v => v.currentTime);
    await testPage.waitForFunction(time => document.querySelector("video[data-call-video]").currentTime > time + 0.5, before);
    await testPage.getByRole("button", {name: "模拟接通", exact: true}).click();
    await playing();
    await testPage.getByRole("button", {name: "静音", exact: true}).click();
    await playing();
    assert(await testPage.getByRole("button", {name: "取消静音", exact: true}).count() === 1, "Mute state not retained");
    await testPage.evaluate(() => {
      window.callLooped = false;
      const video = document.querySelector("video[data-call-video]");
      let previous = video.currentTime;
      video.addEventListener("timeupdate", () => {
        if (previous > 6 && video.currentTime < 2) window.callLooped = true;
        previous = video.currentTime;
      });
    });
    await testPage.waitForFunction(() => window.callLooped, {timeout: 15000});
    await testPage.screenshot({path: "output/playwright/call-video-single.png", fullPage: true});
    const oldVideo = await testPage.locator("video[data-call-video]").elementHandle();
    await testPage.getByRole("button", {name: "结束通话", exact: true}).click();
    assert(await testPage.locator("video[data-call-video]").count() === 0, "Ended video remains mounted");
    assert(await oldVideo.evaluate(v => v.paused && !v.getAttribute("src")), "Ended video was not released");
    await testPage.locator('[data-member="P2"]').uncheck();
    for (const pid of ["P1", "P4", "P5", "P6", "P7", "P8"]) {
      await testPage.locator(`[data-member="${pid}"]`).check();
    }
    await testPage.getByRole("button", {name: "发起群呼", exact: true}).click();
    await playing();
    assert(await testPage.locator(".call-video-tile").count() === 6, "Group participant videos missing");
    assert(await testPage.locator(".call-video-unavailable").count() === 2, "Unavailable channels must not show live video");
    const sources = await testPage.locator("video[data-call-video]").evaluateAll(vs => vs.map(v => v.getAttribute("src")));
    assert(new Set(sources).size === 4, "Area videos were not mapped correctly");
    for (const width of [1920, 1672, 1366]) {
      await testPage.setViewportSize({width, height: 1080});
      const fits = await testPage.locator(".call-videos").evaluate(el => el.scrollWidth <= el.clientWidth + 1);
      assert(fits, `Group video horizontal overflow at ${width}`);
    }
    await testPage.getByRole("button", {name: "模拟接通", exact: true}).click();
    await playing();
    await testPage.setViewportSize({width: 1920, height: 1080});
    await testPage.screenshot({path: "output/playwright/call-video-group.png", fullPage: true});
    await testPage.getByRole("button", {name: "结束通话", exact: true}).click();
    await testPage.locator('[data-member="P1"]').check();
    await testPage.getByRole("checkbox", {name: "全选", exact: true}).check();
    await testPage.getByRole("checkbox", {name: "全选", exact: true}).uncheck();
    await testPage.locator('[data-member="P2"]').check();
    await testPage.getByRole("button", {name: "单呼", exact: true}).click();
    await playing();
    await testPage.getByRole("button", {name: "取消呼叫", exact: true}).click();
    assert(await testPage.locator("video[data-call-video]").count() === 0, "Canceled video remains mounted");
    assert(!errors.length, errors.join("\n"));
    return {singlePreview: true, connected: true, muted: true, looped: true, ended: true, canceled: true, groupChannels: 6, areaClips: 4, unavailableChannels: 2, pageErrors: errors};
  } finally {
    await context.close();
  }
}
