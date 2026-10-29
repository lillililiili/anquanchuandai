import { readFile } from 'node:fs/promises';
import { ConfigError, validateConfig } from './config.mjs';
import { createDeviceGateway } from './gateway.mjs';
import { createGpsDiagnosticWriter } from './gps-diagnostics.mjs';

try {
  if (process.argv.slice(2).some(arg => arg !== '--check')) throw new ConfigError('Unsupported argument.');
  const config = validateConfig(JSON.parse(await readFile(new URL('./.local/config.json', import.meta.url), 'utf8')));
  if (process.argv.includes('--check')) {
    console.log('Local gateway configuration is valid. No listener or tunnel was started.');
  } else {
    const onGpsReport = process.env.HELMET_GPS_DIAGNOSTICS === '1'
      ? await createGpsDiagnosticWriter(new URL('./.local/gps-report-diagnostics.jsonl', import.meta.url)) : undefined;
    const gateway = createDeviceGateway(config, { onGpsReport });
    await gateway.listen();
    console.log(`Device gateway is listening only on loopback port ${config.listenPort}. No public tunnel was started.`);
    let closing = false;
    const stop = async () => {
      if (closing) return;
      closing = true;
      await gateway.close();
      console.log('Device gateway stopped.');
    };
    process.on('SIGINT', stop);
    process.on('SIGTERM', stop);
  }
} catch (error) {
  console.error(error instanceof ConfigError ? error.message : 'Gateway startup failed; local configuration and port availability must be checked.');
  process.exitCode = 1;
}
