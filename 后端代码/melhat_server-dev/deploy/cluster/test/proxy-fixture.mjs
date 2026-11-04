// Test-only backend stand-in. Never included in a production image.
import http from 'node:http';
import {WebSocketServer} from 'ws';
let ready=true,writes=0;
const node=process.env.FIXTURE_NODE;
const server=http.createServer(async(req,res)=>{
  res.setHeader('Content-Type','application/json');
  if(req.url==='/internal/cluster/ready'){res.statusCode=ready?200:503;res.end(JSON.stringify({ready}));return;}
  if(req.url.startsWith('/test/ready/')){ready=req.url.endsWith('/true');res.end('{}');return;}
  if(req.url==='/test/counts'){res.end(JSON.stringify({writes,node}));return;}
  if(req.url==='/fail-write'){writes++;for await(const _ of req){}res.statusCode=503;res.end('{}');return;}
  if(req.url.startsWith('/api/')){res.end(JSON.stringify({status:true,data:{config:JSON.stringify({api_url:'http://fixture/api/',ws_url:'ws://fixture/wsHat'})}}));return;}
  res.end(JSON.stringify({node}));
});
const ws=new WebSocketServer({server});
ws.on('connection',socket=>{socket.on('error',()=>{});socket.on('message',raw=>{const msg=JSON.parse(raw);socket.send(JSON.stringify({cmd:msg.act,status:true,node}));});});
server.listen(18084,'0.0.0.0');
