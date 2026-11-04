// Isolated workload driver. Measures actual ACK/HTTP results; never extrapolates supported capacity.
import {readFile,writeFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {resolve} from 'node:path';
import {performance} from 'node:perf_hooks';
import {setTimeout as delay} from 'node:timers/promises';
import {WebSocket} from 'ws';

export function validateBenchmark(input,{testOnly=false}={}) {
  const origin=new URL(input.origin);
  if(origin.protocol!=='http:'||origin.hostname!=='127.0.0.1'||origin.origin!==input.origin||!origin.port||origin.port==='18084')
    throw Error('Benchmark must target a dedicated loopback entry, never the daily backend.');
  if(!/^wearable-lab-[a-z0-9-]+$/.test(input.runId??'')||!['single','dual'].includes(input.scenario))throw Error('An isolated run ID and scenario are required.');
  if(!/^wearable-lab-[a-z0-9-]+$/.test(input.labId??'')||!/^[A-Za-z0-9_-]{43}$/.test(input.isolationProof??''))
    throw Error('A separately provisioned lab identity and isolation proof are required.');
  const durationSeconds=input.durationSeconds??300,reportIntervalMillis=input.reportIntervalMillis??1000,timeoutMillis=input.timeoutMillis??5000;
  if(!Number.isInteger(durationSeconds)||durationSeconds<(testOnly?1:10)||durationSeconds>86400
    ||!Number.isInteger(reportIntervalMillis)||reportIntervalMillis<(testOnly?20:100)||reportIntervalMillis>60000
    ||!Number.isInteger(timeoutMillis)||timeoutMillis<(testOnly?20:100)||timeoutMillis>30000)throw Error('Invalid bounded workload settings.');
  if(!Array.isArray(input.devices)||input.devices.length<1||input.devices.length>10000)throw Error('Explicit synthetic devices are required.');
  const ids=new Set(),tokens=new Set();
  for(const d of input.devices){
    if(!/^900[0-9]{12}$/.test(d.deviceId??'')||!['helmet','belt'].includes(d.kind)||!/^[A-Za-z0-9_-]{43}$/.test(d.pathToken??'')
      ||ids.has(d.deviceId)||tokens.has(d.pathToken))throw Error('Only unique pre-registered synthetic devices/credentials are accepted.');
    ids.add(d.deviceId);tokens.add(d.pathToken);
  }
  const httpConcurrency=input.httpConcurrency??0;
  if(!Number.isInteger(httpConcurrency)||httpConcurrency<0||httpConcurrency>100)throw Error('Invalid HTTP concurrency.');
  if(httpConcurrency&&(!/^\/api\/(admin|guardian)\/[A-Za-z0-9_/?=&.-]+$/.test(input.httpPath??'')
    ||!/^[A-Za-z0-9_-]{43}$/.test(input.sessionToken??'')))throw Error('HTTP workload requires an explicit authenticated business GET.');
  if(httpConcurrency&&(!/^[A-Za-z][A-Za-z0-9_]{0,79}$/.test(input.httpSuccess?.field??'')
    ||!(Object.hasOwn(input.httpSuccess,'equals')||['number','string','boolean','object'].includes(input.httpSuccess.type))))
    throw Error('Specify the actual successful business response field, not HTTP status alone.');
  return {...input,durationSeconds,reportIntervalMillis,timeoutMillis,httpConcurrency};
}

function metric() {
  const samples=[];let total=0,errors=0,sum=0,max=0;
  return {record(ms,ok){total++;if(!ok)errors++;sum+=ms;max=Math.max(max,ms);if(samples.length<1000000)samples.push(ms);},
    result(seconds){samples.sort((a,b)=>a-b);const p=q=>samples.length?samples[Math.min(samples.length-1,Math.floor((samples.length-1)*q))]:null;
      return {attempts:total,success:total-errors,errors,errorRate:total?errors/total:0,successPerSecond:(total-errors)/seconds,
        latencyScope:'all completed attempts including errors',
        meanMillis:total?sum/total:null,maxMillis:total?max:null,p50Millis:p(.5),p95Millis:p(.95),p99Millis:p(.99),
        percentileSamples:samples.length,percentilesTruncated:samples.length<total};}};
}

export async function benchmark(input,{testOnly=false,onSample=()=>{}}={}) {
  const config=validateBenchmark(input,{testOnly});
  const attestation=await fetch(config.origin+'/.well-known/wearable-lab',{redirect:'error',signal:AbortSignal.timeout(config.timeoutMillis)});
  if(attestation.status!==200){await attestation.body?.cancel();throw Error('Target has no laboratory attestation.');}
  const chunks=[];let bytes=0;
  for await(const chunk of attestation.body){bytes+=chunk.length;if(bytes>2048)throw Error('Invalid lab attestation.');chunks.push(chunk);}
  const proof=JSON.parse(Buffer.concat(chunks).toString('utf8'));
  if(proof.isolated!==true||proof.labId!==config.labId||proof.proof!==config.isolationProof)throw Error('Target is not the provisioned isolated laboratory.');
  // No device connection or business GET is made before the independent entry identity matches.
  const started=performance.now(),end=started+config.durationSeconds*1000;
  const reports=metric(),logins=metric(),http=metric(),sockets=new Set(),sampleRows=[];
  let stopping=false,peakConnections=0,reconnects=0;
  const sample=()=>{const value={elapsedSeconds:(performance.now()-started)/1000,openConnections:[...sockets].filter(ws=>ws.readyState===WebSocket.OPEN).length,
    driverRssBytes:process.memoryUsage().rss};sampleRows.push(value);onSample(value);};
  const timer=setInterval(sample,1000);timer.unref();
  function exchange(ws,body,cmd) {
    return new Promise(resolve=>{
      const begin=performance.now();let done=false;
      const finish=ok=>{if(done)return;done=true;clearTimeout(timeout);ws.off('message',message);ws.off('close',closed);ws.off('error',closed);resolve({ok,ms:performance.now()-begin});};
      const message=raw=>{try{const value=JSON.parse(raw);if(value.cmd===cmd)finish(value.status===true);}catch{finish(false);}};
      const closed=()=>finish(false);
      const timeout=setTimeout(()=>{finish(false);ws.terminate();},config.timeoutMillis);
      ws.on('message',message);ws.once('close',closed);ws.once('error',closed);
      if(ws.readyState!==WebSocket.OPEN){finish(false);return;}
      ws.send(JSON.stringify(body),error=>{if(error)finish(false);});
    });
  }
  async function deviceWorker(device) {
    let attempts=0;
    while(performance.now()<end&&!stopping) {
      if(attempts++)reconnects++;
      const loginStarted=performance.now();
      const ws=new WebSocket(config.origin.replace('http:','ws:')+`/${device.pathToken}/${device.kind==='belt'?'wsBelt':'wsHat'}`,{handshakeTimeout:config.timeoutMillis,perMessageDeflate:false,maxPayload:65536});
      sockets.add(ws);ws.on('error',()=>{});
      const opened=await new Promise(resolve=>{ws.once('open',()=>resolve(true));ws.once('error',()=>resolve(false));ws.once('close',()=>resolve(false));});
      if(opened){
        peakConnections=Math.max(peakConnections,[...sockets].filter(s=>s.readyState===WebSocket.OPEN).length);
        const result=await exchange(ws,{act:'ca_login',device_id:device.deviceId},'ca_login');logins.record(performance.now()-loginStarted,result.ok);
        if(result.ok)while(performance.now()<end&&ws.readyState===WebSocket.OPEN&&!stopping){
          const begin=performance.now();
          const report=await exchange(ws,{act:'ca_report_location',device_id:device.deviceId,bat_l:90,is_weared:2},'ca_report_location');
          reports.record(report.ms,report.ok);
          // Never let a late ACK after timeout become the next report's success.
          if(!report.ok){ws.terminate();break;}
          await delay(Math.max(0,Math.min(end-performance.now(),config.reportIntervalMillis-(performance.now()-begin))));
        }
      }else logins.record(performance.now()-loginStarted,false);
      ws.terminate();sockets.delete(ws);
      if(performance.now()<end)await delay(Math.min(500,end-performance.now()));
    }
  }
  async function httpWorker(){
    while(performance.now()<end&&!stopping){const begin=performance.now();let ok=false;
      try{const r=await fetch(config.origin+config.httpPath,{redirect:'error',headers:{'X-Wearable-Token':config.sessionToken},signal:AbortSignal.timeout(config.timeoutMillis)});
        const body=await r.json(),contract=config.httpSuccess;
        ok=r.status===200&&body!=null&&!body.error&&body.status!==false&&(body.code==null||body.code===200)
          &&Object.hasOwn(body,contract.field)&&(Object.hasOwn(contract,'equals')?body[contract.field]===contract.equals:typeof body[contract.field]===contract.type);
      }catch{}http.record(performance.now()-begin,ok);
      await delay(0);
    }
  }
  try{await Promise.all([...config.devices.map(deviceWorker),...Array.from({length:config.httpConcurrency},httpWorker)]);}
  finally{stopping=true;clearInterval(timer);for(const ws of sockets)ws.terminate();sample();}
  const seconds=(performance.now()-started)/1000;
  return {runId:config.runId,scenario:config.scenario,startedAt:new Date(Date.now()-seconds*1000).toISOString(),durationSeconds:seconds,
    configuredDurationSeconds:config.durationSeconds,configuredConnections:config.devices.length,peakConnections,reconnects,
    reportIntervalMillis:config.reportIntervalMillis,httpConcurrency:config.httpConcurrency,
    login:logins.result(seconds),reports:reports.result(seconds),http:http.result(seconds),samples:sampleRows,
    workload:'synthetic heartbeat reports and optional authenticated GET; no device control/SOS/media writes',
    limits:'Client measurements only. Attach actual container resources, database lock waits and durable row reconciliation; this is not a supported-capacity declaration.'};
}

if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
  const [configPath,output]=process.argv.slice(2);
  try{if(!configPath||!output||process.argv.length!==4)throw Error();
    const result=await benchmark(JSON.parse(await readFile(configPath,'utf8')));
    await writeFile(output,JSON.stringify(result,null,2)+'\n',{flag:'wx',mode:0o600});
    console.log(`Measured ${result.reports.attempts} reports; ${result.reports.errors} failed. Result written to the requested new file.`);
  }catch{console.error('Isolated benchmark failed; no capacity conclusion was produced. Check private configuration and output path.');process.exitCode=1;}
}
