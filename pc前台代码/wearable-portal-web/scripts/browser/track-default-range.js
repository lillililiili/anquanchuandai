async page => {
 await page.goto('http://127.0.0.1:5179/#/location?tab=tracks&siteId=mock-site-1&deviceId=device-1-8-helmet');
 await page.waitForFunction(() => document.querySelectorAll('.s2-segment').length > 0);
 const range = await page.locator('input[type=datetime-local]').evaluateAll(es=>es.map(e=>e.value));
 if(range.some(v=>!v)) throw new Error('Missing default range');
 await page.waitForFunction(() => document.querySelector('.amap-scene')?.__vueParentComponent.setupState.pointOverlays.length > 0);
 await page.getByRole('button',{name:'播放',exact:true}).click();
 await page.waitForTimeout(1300);
 if (!(await page.locator('.s2-playback').innerText()).includes('2 / 6')) throw new Error('Playback did not advance');
 await page.getByRole('button',{name:'暂停',exact:true}).click();
 await page.screenshot({path:'output/playwright/track-default-range.png'});
 const explicitFrom = '2020-01-01T00:00:00.000Z', explicitTo = '2020-01-02T00:00:00.000Z';
 await page.goto('http://127.0.0.1:5179/#/location?tab=tracks&siteId=mock-site-1&deviceId=device-1-8-helmet&from='+encodeURIComponent(explicitFrom)+'&to='+encodeURIComponent(explicitTo));
 await page.getByText('该时段暂无轨迹记录',{exact:true}).waitFor();
 if ((await page.locator('input[type=datetime-local]').first().inputValue()) !== '2020-01-01T00:00') throw new Error('Explicit range overwritten');
 await page.goto('http://127.0.0.1:5179/#/location?tab=live&siteId=mock-site-1');
 await page.locator('.s2-list-row').nth(7).click();
 await page.getByRole('button',{name:'历史轨迹',exact:true}).click();
 await page.waitForFunction(() => document.querySelectorAll('.s2-segment').length > 0);
 if (!page.url().includes('device-1-8-helmet')) throw new Error('Wrong device');
 return {range, segments:await page.locator('.s2-segment').count(), personEntry:page.url()};
}
