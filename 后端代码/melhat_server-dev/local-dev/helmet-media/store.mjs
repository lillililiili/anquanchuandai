import fs from 'node:fs';
import path from 'node:path';

export class Store {
  constructor(directory) {
    this.directory = path.resolve(directory);
    fs.mkdirSync(this.directory, { recursive: true, mode: 0o700 });
    this.filename = path.join(this.directory, 'state.json');
    this.data = fs.existsSync(this.filename) ? JSON.parse(fs.readFileSync(this.filename, 'utf8'))
      : { version: 1, sequence: 0, accounts: {}, streams: {}, calls: {}, assets: {}, recordings: {}, events: [] };
    for (const item of Object.values(this.data.recordings)) if (['starting', 'recording', 'finalizing'].includes(item.status)) {
      item.status = 'interrupted';
      this.event('recording.failed', { recordingId:item.recordingId, requestId:item.requestId, deviceId:item.deviceId, reason:'SERVICE_RESTART' });
    }
    fs.mkdirSync(path.join(this.directory, 'assets'), { recursive: true, mode: 0o700 });
    this.save();
  }
  save() {
    const temporary = this.filename + '.tmp';
    const output=fs.openSync(temporary,'w',0o600);
    try {fs.writeFileSync(output,JSON.stringify(this.data));fs.fsyncSync(output);}finally{fs.closeSync(output);}
    fs.renameSync(temporary, this.filename);
    if(process.platform!=='win32'){const dir=fs.openSync(this.directory,'r');try{fs.fsyncSync(dir);}finally{fs.closeSync(dir);}}
  }
  event(type, values = {}) {
    const createdAt = new Date().toISOString();
    const event = { sequence: ++this.data.sequence, type, at: createdAt, createdAt, ...values };
    this.data.events.push(event);
    if (this.data.events.length > 10000) this.data.events.splice(0, this.data.events.length - 10000);
    this.save(); return event;
  }
  assetPath(id, extension) { return path.join(this.directory, 'assets', `${id}.${extension}`); }
}
