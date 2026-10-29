import fs from 'node:fs';
import path from 'node:path';
import {createHash,randomUUID} from 'node:crypto';

export async function spool(stream,directory,maximum=256*1024*1024) {
  fs.mkdirSync(directory,{recursive:true,mode:0o700});
  const filename=path.join(directory,randomUUID()+'.upload');
  const out=await fs.promises.open(filename,'wx',0o600),hash=createHash('sha256'); let length=0;
  try {
    for await(const chunk of stream) {
      length+=chunk.length; if(length>maximum) throw Object.assign(Error('UPLOAD_TOO_LARGE'),{status:413});
      hash.update(chunk); await out.write(chunk);
    }
    await out.sync(); await out.close();
    return {filename,length,digest:hash.digest('hex')};
  } catch(error) {await out.close().catch(()=>{});await fs.promises.unlink(filename).catch(()=>{});throw error;}
}
