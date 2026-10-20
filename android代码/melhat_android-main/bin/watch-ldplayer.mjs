// Optional save-to-reload driver for run-ldplayer.ps1; no npm dependencies.
// Uses Flutter's documented attach/run --machine protocol, just like an IDE.
import { spawn } from 'node:child_process';
import { existsSync, readdirSync, watch } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { createInterface } from 'node:readline';

const [flutter, ...args] = process.argv.slice(2);
if (!flutter || !['run', 'attach'].includes(args[0])) {
  throw new Error('Start with run-ldplayer.ps1 -Watch [-Attach].');
}
const flutterRoot = resolve(dirname(flutter), '..');
const dart = join(flutterRoot, 'bin/cache/dart-sdk/bin', process.platform === 'win32' ? 'dart.exe' : 'dart');
const snapshot = join(flutterRoot, 'bin/cache/flutter_tools.snapshot');
if (!existsSync(snapshot)) throw new Error('Run flutter --version once to initialize Flutter tools.');

// Launch Dart directly so paths/arguments never pass through a command shell.
const child = spawn(dart, [snapshot, ...args, '--machine'], {
  env: { ...process.env, FLUTTER_ROOT: flutterRoot },
  windowsHide: true,
  stdio: ['pipe', 'pipe', 'pipe'],
});
const log = message => console.log(`[${new Date().toISOString()}] ${message}`);
const watchers = [];
let appId, ready = false, busy = false, timer, stopping = false, requestId = 0;
let restartRequested = false;
const changed = new Set();
const requests = new Map();

function request(method, params, done = () => {}) {
  const id = ++requestId;
  requests.set(id, done);
  child.stdin.write(`${JSON.stringify([{ id, method, params }])}\n`);
}

function schedule(file) {
  if (stopping) return;
  changed.add(file);
  clearTimeout(timer);
  timer = setTimeout(reload, 750);
}

function reload() {
  if (!ready || busy || stopping || !changed.size) return;
  const files = [...changed];
  const fullRestart = restartRequested;
  changed.clear();
  restartRequested = false;
  busy = true;
  log(`${fullRestart ? 'Hot restart' : 'Hot reload'}: ${files.join(', ')}`);
  request('app.restart', { appId, fullRestart, pause: false, reason: 'save' }, response => {
    busy = false;
    if (response.error || response.result?.code !== 0) {
      log(`Reload failed; fix the error and save again: ${JSON.stringify(response.error ?? response.result)}`);
    } else {
      log(fullRestart ? 'Hot restart complete.' : 'Hot reload complete.');
    }
    // Changes saved during compilation are applied in the next reload.
    if (changed.size) timer = setTimeout(reload, 750);
  });
}

function observe(directory, accept) {
  if (!existsSync(directory)) return;
  const watcher = watch(directory, { recursive: true }, (_event, name) => {
    if (name && accept(String(name))) schedule(`${directory}/${name}`);
  });
  watcher.on('error', error => {
    log(`Watcher failed for ${directory}: ${error.message}`);
    process.exitCode = 1;
    stop();
  });
  watchers.push(watcher);
}
observe('lib', name => name.endsWith('.dart'));
observe('assets', () => true);
if (existsSync('packages')) {
  for (const entry of readdirSync('packages', { withFileTypes: true })) {
    if (entry.isDirectory()) observe(join('packages', entry.name, 'lib'), name => name.endsWith('.dart'));
  }
}

createInterface({ input: child.stdout }).on('line', line => {
  let events;
  try { events = JSON.parse(line); } catch { if (line.trim()) log(line); return; }
  if (!Array.isArray(events)) return;
  for (const event of events) {
    if (requests.has(event.id)) {
      const done = requests.get(event.id);
      requests.delete(event.id);
      done(event);
    }
    const params = event.params ?? {};
    if (event.event === 'app.started') {
      appId = params.appId;
      ready = true;
      log('Ready: saving Dart files reloads LDPlayer automatically. r + Enter reloads; R + Enter restarts; q + Enter detaches.');
      if (changed.size) reload();
    } else if (event.event === 'app.stop') {
      ready = false;
      log('Flutter disconnected. Run the command again to reconnect.');
      stop();
    } else if (['app.log', 'daemon.log', 'daemon.logMessage', 'daemon.showMessage'].includes(event.event)) {
      log(params.log ?? params.message ?? '');
    } else if (event.event === 'app.progress' && params.message) {
      log(params.message);
    }
  }
});
child.stderr.on('data', chunk => process.stderr.write(chunk));
child.stdin.on('error', error => log(`Flutter input closed: ${error.message}`));
child.on('error', error => { log(error.message); process.exitCode = 1; stop(); });
child.on('close', code => {
  clearTimeout(timer);
  for (const watcher of watchers) watcher.close();
  process.exit(code ?? process.exitCode ?? 1);
});

function stop() {
  if (stopping) return;
  stopping = true;
  clearTimeout(timer);
  for (const watcher of watchers) watcher.close();
  // Detach keeps the running app and its data intact.
  if (ready) request('app.detach', { appId }, () => child.stdin.end());
  else child.kill();
  setTimeout(() => child.kill(), 5000).unref();
}
process.on('SIGINT', stop);
process.on('SIGTERM', stop);
createInterface({ input: process.stdin }).on('line', line => {
  if (line.trim() === 'q') stop();
  else if (line.trim() === 'R') { restartRequested = true; schedule('manual restart'); }
  else if (line.trim() === 'r') schedule('manual reload');
});
log(`Connecting to Flutter (${args[0]}). Watching lib/, assets/ and local package Dart sources.`);
