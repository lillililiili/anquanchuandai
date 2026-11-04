import {readFile} from 'node:fs/promises';
import {createClusterGateway} from './gateway.mjs';

try {
  const [kind,configPath] = process.argv.slice(2);
  if (!configPath || process.argv.length !== 4) throw new Error('Expected gateway kind and private configuration file.');
  const gateway = createClusterGateway(kind,JSON.parse(await readFile(configPath,'utf8')));
  await gateway.listen();
  console.log(`Cluster ${kind} gateway listening.`);
  let closing = false;
  for (const signal of ['SIGINT','SIGTERM']) process.on(signal,async () => {
    if (closing) return; closing = true;
    try { await gateway.close(); process.exitCode = 0; } catch { process.exitCode = 1; }
  });
} catch {
  // URLs contain device credentials; never print parser errors or the private config.
  console.error('Cluster gateway failed to start; check the private configuration.');
  process.exitCode = 1;
}
