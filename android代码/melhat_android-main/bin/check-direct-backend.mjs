// Read-only device-side HTTP check. Fails when the API still has an adb reverse rule.
// Usage: node bin/check-direct-backend.mjs http://COMPUTER-IP:18084 SERIAL...
import { spawn, execFileSync } from 'node:child_process';
const [address, ...serials] = process.argv.slice(2);
if (!address || !serials.length) throw new Error('Pass backend URL and device serials.');
const url = new URL(address);
if (url.protocol !== 'http:' || !/^[a-zA-Z0-9.-]+$/.test(url.hostname) ||
    ['localhost', '127.0.0.1', '10.0.2.2'].includes(url.hostname)) {
  throw new Error('This local development probe needs a direct HTTP computer address.');
}
const adb = process.env.ADB || 'C:/leidian/LDPlayer14/adb.exe';
const port = url.port || '80';
async function check(serial) {
  const mappings = execFileSync(adb, ['-s', serial, 'reverse', '--list'], { encoding:'utf8' });
  if (mappings.split(/\s+/).includes('tcp:' + port)) {
    return { serial, address, ok:false, reason:'API adb reverse mapping is still present' };
  }
  return new Promise(resolve => {
    const child = spawn(adb, ['-s', serial, 'shell', '-T', 'toybox', 'nc', '-w', '5', '-W', '5', url.hostname, port]);
    let response = '';
    child.stdout.on('data', chunk => response += chunk);
    child.stderr.on('data', chunk => response += chunk);
    child.stdin.on('error', () => {});
    child.stdin.write('GET /actuator/health HTTP/1.0\r\nHost: ' + url.host + '\r\n\r\n');
    const timer = setTimeout(() => child.kill(), 8000);
    child.on('error', error => { clearTimeout(timer); resolve({serial,address,ok:false,reason:error.message}); });
    child.on('close', () => {
      clearTimeout(timer);
      const ok = /HTTP\/1\.[01] 200/.test(response) && response.includes('"status":"UP"');
      resolve({ serial, address, ok, apiReverseMapping:false, health:ok ? 'UP' : 'unreachable' });
    });
  });
}
const results = await Promise.all(serials.map(check));
console.log(JSON.stringify(results, null, 2));
if (results.some(r => !r.ok)) process.exitCode = 1;
