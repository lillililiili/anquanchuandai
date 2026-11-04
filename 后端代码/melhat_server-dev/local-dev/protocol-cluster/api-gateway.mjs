import {createWearGateway} from '../wear-api-gateway/gateway.mjs';
import {createGateway as createFudaGateway} from '../fuda-api-gateway/gateway.mjs';

// One instance of each API gateway: wear's existing per-process limiter stays global
// to this entry. Only the applications and paired device gateways scale in this release.
export function createApiGateway(kind, input = {}, {testOnly = false} = {}) {
  if (!['wear','fuda'].includes(kind)) throw Error('Invalid API gateway kind.');
  const {upstreamOrigin='http://backend:18084',listenHost='0.0.0.0',listenPort=8080,
    healthPollMillis=1000,healthTimeoutMillis=1500}=input;
  const upstream=new URL(upstreamOrigin);
  if (testOnly ? (upstream.protocol!=='http:'||upstream.hostname!=='127.0.0.1'||upstream.origin!==upstreamOrigin||upstream.port==='18084')
    : upstreamOrigin!=='http://backend:18084') throw Error('Expected the private cluster backend router.');
  if (upstream.username||upstream.password||!['127.0.0.1','0.0.0.0'].includes(listenHost)
    ||!Number.isInteger(listenPort)||listenPort<(testOnly?0:1)||listenPort>65535
    ||![healthPollMillis,healthTimeoutMillis].every(x=>Number.isInteger(x)&&x>=(testOnly?10:100)&&x<=30000)) throw Error('Invalid API gateway configuration.');
  let ready=false,closed=false,timer,abort;
  const accepting=()=>ready&&!closed;
  const management=(req,res)=>{
    if (!req.url?.startsWith('/internal/')) return false;
    const live=req.method==='GET'&&req.url==='/internal/gateway/live';
    const health=req.method==='GET'&&req.url==='/internal/gateway/ready';
    res.writeHead(live||health&&accepting()?200:health?503:404,{'Content-Type':'application/json','Cache-Control':'no-store'});
    res.end(JSON.stringify(live?{live:true}:health?{ready:accepting()}:{error:'Unavailable'}));return true;
  };
  const server=(kind==='wear'?createWearGateway:createFudaGateway)({upstreamOrigin,testOnly,management,accepting});
  async function probe(){
    abort=new AbortController();const timeout=setTimeout(()=>abort.abort(),healthTimeoutMillis);
    try {
      const response=await fetch(upstreamOrigin+'/internal/cluster/ready',{signal:abort.signal,redirect:'error'});
      ready=false;
      if(response.status!==200)await response.body?.cancel();
      else {const chunks=[];let bytes=0;for await(const chunk of response.body){bytes+=chunk.length;if(bytes>4096)throw Error();chunks.push(chunk);}
        ready=JSON.parse(Buffer.concat(chunks).toString('utf8'))?.ready===true;}
    }catch{ready=false;}finally{clearTimeout(timeout);if(!closed){timer=setTimeout(probe,healthPollMillis);timer.unref();}}
  }
  return {
    async listen(){await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(listenPort,listenHost,()=>{server.off('error',reject);resolve();});});await probe();return server.address();},
    async close(){closed=true;ready=false;clearTimeout(timer);abort?.abort();await new Promise((resolve,reject)=>server.close(e=>e?reject(e):resolve()));}
  };
}
