import { randomBytes } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { DEFAULTS } from './config.mjs';

const directory = fileURLToPath(new URL('./.local/', import.meta.url));
try {
  await mkdir(directory, { recursive: true });
  await writeFile(new URL('./.local/config.json', import.meta.url),
    JSON.stringify({ ...DEFAULTS, pathToken: randomBytes(32).toString('base64url') }, null, 2) + '\n',
    { encoding: 'utf8', mode: 0o600, flag: 'wx' });
  console.log('Ignored local configuration created. Set its public HTTPS origin before starting.');
} catch (error) {
  console.error(error.code === 'EEXIST' ? 'Local configuration already exists; it was preserved.' : 'Local configuration could not be created.');
  process.exitCode = 1;
}
