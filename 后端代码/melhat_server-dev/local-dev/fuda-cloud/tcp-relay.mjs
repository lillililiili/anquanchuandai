import net from 'node:net';

// Replaces only the three old SSH reverse-forward listeners after planned cutover.
// Each destination is fixed loopback. Never accepts a caller-supplied proxy target.
const mappings = [[28086,18086],[28087,18087],[28088,18088]];
const sockets = new Set(), servers = [];
for (const [port,target] of mappings) {
  const server=net.createServer(client=>{
    if(sockets.size>=128){client.destroy();return;}
    const upstream=net.connect(target,'127.0.0.1');sockets.add(client);sockets.add(upstream);
    const stop=()=>{client.destroy();upstream.destroy();sockets.delete(client);sockets.delete(upstream);};
    for(const s of [client,upstream]){s.setTimeout(120000,stop);s.on('error',stop);s.on('close',stop);}
    client.pipe(upstream);upstream.pipe(client);
  });
  server.on('error',()=>{console.error(`Private relay ${port} unavailable; no listener was replaced`);for(const s of servers)s.close();for(const s of sockets)s.destroy();process.exitCode=1;});
  server.listen(port,'10.255.1.1');servers.push(server);
}
for(const signal of ['SIGTERM','SIGINT'])process.on(signal,()=>{for(const s of servers)s.close();for(const s of sockets)s.destroy();});
