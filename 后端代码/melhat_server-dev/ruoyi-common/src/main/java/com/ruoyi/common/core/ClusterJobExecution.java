package com.ruoyi.common.core;
/** Invoked by both scheduled and manually triggered Quartz executions. */
public interface ClusterJobExecution {
    interface Invocation {void run() throws Exception;}
    boolean execute(String jobKey,String firingKey,Invocation invocation)throws Exception;
}
