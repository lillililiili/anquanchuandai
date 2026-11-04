import {createApiGateway} from './api-gateway.mjs';
try {
  if(process.argv.length!==3)throw Error();
  const gateway=createApiGateway(process.argv[2]);await gateway.listen();
  console.log('Private cluster API gateway listening.');
  let closing=false;
  for(const signal of ['SIGINT','SIGTERM'])process.on(signal,async()=>{
    if(closing)return;closing=true;
    try{await gateway.close();process.exitCode=0;}catch{process.exitCode=1;}
  });
}catch{console.error('Cluster API gateway could not start.');process.exitCode=1;}
