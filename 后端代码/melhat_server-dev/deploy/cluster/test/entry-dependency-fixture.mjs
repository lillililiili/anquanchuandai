// Transport-only stand-in: asserts routing, not media authentication or video playback.
import http from 'node:http';
import {WebSocketServer} from 'ws';
const server=http.createServer(async(req,res)=>{
  if(req.url.startsWith('/helmet-media/files/')){
    res.writeHead(req.headers.range?206:200,{'content-type':'image/jpeg','content-range':'bytes 0-3/8',
      'content-disposition':'attachment; filename="fixture.jpg"','content-length':'4'});
    res.end(req.method==='HEAD'?undefined:'abcd');return;
  }
  const chunks=[];for await(const c of req)chunks.push(c);
  res.writeHead(200,{'content-type':'application/json','access-control-allow-origin':req.headers.origin??'http://fixture'});
  res.end(JSON.stringify({dependency:true,path:req.url,method:req.method,headers:req.headers,body:Buffer.concat(chunks).toString('utf8')}));
});
const ws=new WebSocketServer({server});
ws.on('connection',(socket,req)=>socket.on('message',raw=>socket.send(JSON.stringify({path:req.url,body:raw.toString()}))));
server.listen(18084,'0.0.0.0');
