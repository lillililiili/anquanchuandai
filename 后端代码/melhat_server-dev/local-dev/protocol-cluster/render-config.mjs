import {readFile,writeFile,mkdir,lstat,rename,unlink} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {randomUUID,createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {validateClusterConfig} from './gateway.mjs';

// Reads operator-supplied device secrets; never rotates a commissioned device.
export function renderConfigs(input) {
  const allowed=new Set(['publicOrigin','deviceWebsocketOrigin','adminToken','helmets','belts','mediaControlOrigin','mediaSigningKey','limits','drainTimeoutMillis']);
  if(!input||Object.keys(input).some(key=>!allowed.has(key))||!Array.isArray(input.helmets)||!Array.isArray(input.belts))throw new Error('Invalid gateway inventory.');
  const common={listenHost:'0.0.0.0',listenPort:8080,publicOrigin:input.publicOrigin,adminToken:input.adminToken,
    ...(input.deviceWebsocketOrigin?{deviceWebsocketOrigin:input.deviceWebsocketOrigin}:{}),
    ...(input.limits?{limits:input.limits}:{}),...(input.drainTimeoutMillis?{drainTimeoutMillis:input.drainTimeoutMillis}:{})};
  // Validate full and shortened credential uniqueness across protocol families.
  validateClusterConfig({...common,upstreamOrigin:'http://app-a:18084',nodeId:'app-a',devices:[...input.helmets,...input.belts]});
  const files={},routes=[];
  for(const [kind,devices] of [['helmet',input.helmets],['belt',input.belts]]) {
    for(const node of ['a','b']) {
      const config={...common,upstreamOrigin:`http://app-${node}:18084`,nodeId:`app-${node}`,devices,
        ...(kind==='helmet'&&input.mediaControlOrigin?{mediaControlOrigin:input.mediaControlOrigin,mediaSigningKey:input.mediaSigningKey}: {})};
      validateClusterConfig(config);
      files[`${kind}-${node}.json`]=JSON.stringify(config,null,2)+'\n';
    }
    const paths=devices.flatMap(d=>kind==='belt'?[`/${d.pathToken}/*`,`/${d.pathToken.slice(0,24)}/wsHat`]:[`/${d.pathToken}/*`]);
    routes.push(`@cluster_${kind} path ${paths.join(' ')}\nhandle @cluster_${kind} {\n    reverse_proxy ${kind}-a:8080 ${kind}-b:8080 {\n        import gateway_pool\n    }\n}`);
  }
  files['Caddy.devices']=routes.join('\n')+'\n';
  return files;
}

export async function requirePrivateDirectory(root) {
  const stat=await lstat(root);
  if(!stat.isDirectory()||stat.isSymbolicLink())throw new Error('Private directory must be a real directory.');
  // Windows deployments must restrict the directory ACL separately; POSIX mode bits are not ACL evidence.
  if(process.platform!=='win32'&&((stat.mode&0o077)!==0||stat.uid!==process.getuid()))
    throw new Error('Use an owned private directory with mode 0700.');
}

export async function publishGeneration(root,files,replace=false,afterPublish=()=>{}) {
  await mkdir(root,{recursive:true,mode:0o700});
  await requirePrivateDirectory(root);
  for(const name of Object.keys(files)) {
    const target=join(root,name);
    try {const stat=await lstat(target);if(!stat.isFile()||stat.isSymbolicLink()||!replace)throw new Error('Existing output requires explicit replacement.');}
    catch(error){if(error.code!=='ENOENT')throw error;}
  }
  const marker=join(root,'.gateway-config.incomplete');
  // An interrupted replacement remains visibly blocked. ops.py checks both marker and all hashes.
  await writeFile(marker,'Generation in progress. Do not start/recreate services.\n',{flag:'wx',mode:0o600});
  const manifest={generation:randomUUID(),files:Object.fromEntries(Object.entries(files).map(([name,body])=>
    [name,createHash('sha256').update(body).digest('hex')]))};
  for(const [name,body] of Object.entries({...files,'gateway-manifest.json':JSON.stringify(manifest,null,2)+'\n'})) {
    const target=join(root,name),temp=join(root,`.render-${randomUUID()}`);
    try {
      // Parent directory is private; each gateway mounts only its own readable file.
      await writeFile(temp,body,{flag:'wx',mode:name.endsWith('.json')&&name!=='gateway-manifest.json'?0o644:0o600});
      await rename(temp,target);
      await afterPublish(name);
    } finally {await unlink(temp).catch(()=>{});}
  }
  await unlink(marker);
}
async function main() {
  const [source,destination,replace]=process.argv.slice(2);
  if(!source||!destination||(replace&&replace!=='--replace')||process.argv.length>5)throw new Error('Expected inventory, private output directory, optional --replace.');
  const files=renderConfigs(JSON.parse(await readFile(source,'utf8')));
  await publishGeneration(resolve(destination),files,replace==='--replace');
  console.log('Rendered four paired gateway configurations and private ingress routes. No device credentials were changed.');
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href)main().catch(()=>{
  console.error('Gateway configuration generation failed. Check private input and output permissions; no credentials are printed.');process.exitCode=1;
});
