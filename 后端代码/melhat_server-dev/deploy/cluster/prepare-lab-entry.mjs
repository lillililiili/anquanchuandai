// Development only. Produces a separate Caddy file; production Caddyfile stays unchanged.
import {readFile,writeFile,mkdir,lstat} from 'node:fs/promises';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
try {
  const [privateConfig,output]=process.argv.slice(2);
  if(!privateConfig||!output||process.argv.length!==4)throw Error();
  const input=JSON.parse(await readFile(privateConfig,'utf8'));
  if(!/^wearable-lab-[a-z0-9-]+$/.test(input.labId??'')||!/^[A-Za-z0-9_-]{43}$/.test(input.isolationProof??''))throw Error();
  const destination=resolve(output),parent=dirname(destination);
  await mkdir(parent,{recursive:true,mode:0o700});
  const stat=await lstat(parent);
  if(stat.isSymbolicLink()||!stat.isDirectory()||(process.platform!=='win32'&&((stat.mode&0o077)!==0||stat.uid!==process.getuid())))throw Error();
  const template=await readFile(new URL('./Caddyfile',import.meta.url),'utf8');
  if(destination===fileURLToPath(new URL('./Caddyfile',import.meta.url)))throw Error();
  const body=JSON.stringify({isolated:true,labId:input.labId,proof:input.isolationProof});
  const marked=template.replace('{$CADDY_SITE}','http://:80').replace('    route {',`    route {\n        respond /.well-known/wearable-lab \`${body}\` 200`);
  await writeFile(destination,'# ISOLATED LAB ONLY. Bind to loopback; never install in production.\n'+marked,{flag:'wx',mode:0o600});
  console.log('Created a separate isolated laboratory entry. Verify the laboratory DB/Redis/devices before mounting it.');
}catch{console.error('Laboratory entry preparation failed; check private input and new output path.');process.exitCode=1;}
