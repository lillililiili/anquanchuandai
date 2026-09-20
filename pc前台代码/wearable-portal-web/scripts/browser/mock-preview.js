async (page) => {
  const errors = [], bad = [], checks = [], origin = 'http://127.0.0.1:5180';
  const onError = e => errors.push(e.message), onResponse = r => { if (r.status() >= 400) bad.push(r.url()); };
  const requests = [], onRequest = r => { if (!r.url().startsWith(origin + '/') || /\/(api|prod-api|mock-disabled)\//.test(r.url()) || r.method() !== 'GET') requests.push(r.url()); };
  page.on('pageerror', onError); page.on('response', onResponse); page.on('request', onRequest);
  try {
    await page.goto(origin + '/#/personnel');
    await page.getByRole('button', { name: '进入系统', exact: true }).click();
    await page.getByText('共 25 人', { exact: true }).waitFor(); checks.push('Production mock bundle login and personnel');
    for (const name of ['现场监看', '查询分析', '人员装备', '事件处置', '安全总览', '作业监护', '调度协同']) { await page.getByRole('link', { name, exact: true }).click(); await page.waitForTimeout(500); checks.push('Production route: ' + name); }
    if (errors.length || bad.length || requests.length) throw new Error(JSON.stringify({ errors, bad, requests }));
    return { checks, errors, failedAssets: bad, unexpectedRequests: requests };
  } finally { page.off('pageerror', onError); page.off('response', onResponse); page.off('request', onRequest); }
}
