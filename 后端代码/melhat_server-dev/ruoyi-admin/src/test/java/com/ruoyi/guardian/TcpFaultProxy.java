package com.ruoyi.guardian;
import java.net.*;
import java.io.*;
import java.util.*;
import java.util.concurrent.*;
/** Cuts only one test node's real TCP connections; never stops the shared SQL/Redis service. */
final class TcpFaultProxy implements AutoCloseable {
    private final String host;private final int target;private final ServerSocket listener;
    private final Set<Socket> sockets=ConcurrentHashMap.newKeySet();private volatile boolean enabled=true,closed;
    private final ExecutorService pool=Executors.newCachedThreadPool(r->{Thread t=new Thread(r,"isolated-tcp-fault");t.setDaemon(true);return t;});
    TcpFaultProxy(String host,int target)throws IOException{this.host=host;this.target=target;listener=new ServerSocket(0,50,InetAddress.getLoopbackAddress());pool.execute(()->{while(!closed)try{Socket client=listener.accept();if(!enabled){client.close();continue;}Socket remote=new Socket(host,target);sockets.add(client);sockets.add(remote);pool.execute(()->copy(client,remote));pool.execute(()->copy(remote,client));}catch(IOException ignored){}});}
    int port(){return listener.getLocalPort();}
    void cut(){enabled=false;for(Socket s:sockets)try{s.close();}catch(IOException ignored){}sockets.clear();}
    void restore(){enabled=true;}
    private void copy(Socket from,Socket to){try{from.getInputStream().transferTo(to.getOutputStream());}catch(IOException ignored){}finally{for(Socket s:new Socket[]{from,to}){sockets.remove(s);try{s.close();}catch(IOException ignored){}}}}
    public void close(){closed=true;cut();try{listener.close();}catch(IOException ignored){}pool.shutdownNow();}
}
