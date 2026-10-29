import {configuration} from './config.mjs';
import {MediaAdapter} from './media.mjs';
import {GbBridge} from './bridge.mjs';
try{
  const config=configuration();
  if(!config.enabled){console.log('GB bridge disabled. No signaling sockets or media connections opened.');}
  else{
    const bridge=new GbBridge(config,new MediaAdapter(config),{log:event=>console.log(JSON.stringify({at:new Date().toISOString(),event}))});
    await bridge.start();
    let stopping=false;for(const signal of ['SIGTERM','SIGINT'])process.on(signal,async()=>{if(stopping)return;stopping=true;await bridge.close();process.exit(0);});
  }
}catch(error){console.error('GB bridge startup failed; verify configuration and private recovery journal.');process.exitCode=1;}
