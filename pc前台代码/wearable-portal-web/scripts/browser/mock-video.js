async (page) => {
  const origin = page.url().split('/').slice(0, 3).join('/'), checks = [], errors = [], forbidden = []
  const check = (ok, text) => { if (!ok) throw new Error(text); checks.push(text) }
  const button = name => page.getByRole('button', { name, exact: true })
  const onError = e => errors.push(e.message), network = r => { if (!r.url().startsWith('blob:') && (!r.url().startsWith(origin + '/') || r.method() !== 'GET' || /\/(api\/portal|dev-api|demo-api)\//.test(r.url()))) forbidden.push(r.url()) }
  page.on('pageerror', onError); page.on('request', network)
  try {
    await page.reload(); await page.getByRole('button', { name: /^(用户菜单|进入系统)$/ }).first().waitFor()
    if (await button('用户菜单').count()) { await button('用户菜单').click(); await page.getByText('退出登录', { exact: true }).click() }
    await page.getByLabel('预置身份', { exact: true }).selectOption('owner'); await button('进入系统').click(); await button('用户菜单').waitFor()
    await page.goto(origin + '/#/video/device-1-1-helmet?siteId=mock-site-1'); await button('播放本地视频').waitFor()
    const media = page.getByLabel('本地视频画面', { exact: true })
    check(await media.evaluate(v => !v.getAttribute('src') && v.paused), '进入不自动播放')
    await button('播放本地视频').click(); await page.locator('.video-tag').getByText('播放中', { exact: true }).waitFor()
    check(await media.evaluate(v => v.currentTime > 0 && v.videoWidth === 640), '本地合成视频真实画面推进')
    for (const [width, height] of [[1440, 900], [1672, 941]]) {
      await page.setViewportSize({ width, height }); check(!await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), '单路无横向溢出' + width)
      await page.screenshot({ path: 'output/playwright/v23-video-' + width + '.png' })
    }
    await button('预置抓拍').click(); await page.getByLabel('待保存媒体').waitFor(); await button('保存为现场资料').click(); await page.getByRole('link', { name: '查看生成资料' }).waitFor()
    await page.getByRole('link', { name: '查看生成资料' }).click(); await button('预览所选资料').waitFor(); await page.waitForTimeout(600); await button('预览所选资料').click()
    const preview = page.getByRole('dialog', { name: '本地内存资料预览' }); await preview.locator('img').waitFor()
    check(await preview.locator('img').evaluate(i => i.complete && i.naturalWidth === 640), '抓拍保存后资料可真实预览')
    await page.keyboard.press('Escape'); await preview.waitFor({ state: 'hidden' })
    check((await page.locator('.s2-detail').innerText()).includes('历史归属未知'), '未继承当前佩戴人')
    await page.goto(origin + '/#/video/device-1-1-helmet?siteId=mock-site-1'); await button('播放本地视频').click(); await page.locator('.video-tag').getByText('播放中', { exact: true }).waitFor()
    await button('开始预置录像').click(); await page.waitForTimeout(1700); await button('停止录像').click(); await page.getByLabel('待保存媒体').waitFor()
    check((await page.getByLabel('待保存媒体').innerText()).includes('尚未保存'), '录像停止不自动保存')
    await button('保存为现场资料').click(); await page.getByRole('link', { name: '查看生成资料' }).click(); await page.waitForTimeout(600); await button('预览所选资料').click(); await preview.locator('video').waitFor()
    await preview.locator('video').evaluate(v => v.play()); await page.waitForTimeout(400)
    check(await preview.locator('video').evaluate(v => v.currentTime > 0), '录像经资料服务保存并实际播放')
    await page.keyboard.press('Escape'); await preview.waitFor({ state: 'hidden' })
    await page.goto(origin + '/#/video/device-1-1-helmet?siteId=mock-site-1'); await button('播放本地视频').click(); await page.locator('.video-tag').getByText('播放中', { exact: true }).waitFor()
    await button('本地隐私上报：开启').click(); await button('本地隐私上报：关闭').waitFor()
    check(await button('播放本地视频').isDisabled() && await media.evaluate(v => !v.getAttribute('src')), '隐私开启停止播放与禁用')
    await button('本地隐私上报：关闭').click(); await button('本地隐私上报：开启').waitFor()
    check(await media.evaluate(v => !v.getAttribute('src') && v.paused), '关闭隐私不自动播放')
    await page.goto(origin + '/#/video?siteId=mock-site-1')
    for (const name of ['1+7', '2×4', '3×3']) { await button(name).click(); await page.waitForTimeout(650); const ids = await page.locator('.video-slot-select').allTextContents(); check(new Set(ids).size === ids.length, name + '设备不重复'); check(await page.locator('video[src]').count() === 0, name + '切换无自动播放') }
    check(errors.length === 0, '无脚本错误：' + errors.join(';')); check(forbidden.length === 0, '无真实接口媒体或RTC：' + forbidden.join(';'))
    return checks
  } finally { page.off('pageerror', onError); page.off('request', network) }
}
