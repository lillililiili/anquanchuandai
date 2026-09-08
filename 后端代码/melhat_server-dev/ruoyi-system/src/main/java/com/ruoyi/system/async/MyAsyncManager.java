package com.ruoyi.system.async;

import com.ruoyi.common.utils.Threads;
import com.ruoyi.common.utils.spring.SpringUtils;

import java.util.TimerTask;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;

/**
 * 异步任务管理器
 * 
 * @author ruoyi
 */
public class MyAsyncManager
{
    /**
     * 操作延迟10毫秒
     */
    private final int OPERATE_DELAY_TIME = 10;

    /**
     * 异步操作任务调度线程池
     */
    private ScheduledExecutorService executor = SpringUtils.getBean("scheduledExecutorService");

    /**
     * 单例模式
     */
    private MyAsyncManager(){}

    private static MyAsyncManager me = new MyAsyncManager();

    public static MyAsyncManager me()
    {
        return me;
    }

    /**
     * 执行任务
     * 
     * @param task 任务
     */
    public void execute(TimerTask task)
    {
        executor.schedule(task, OPERATE_DELAY_TIME, TimeUnit.MILLISECONDS);
    }

    /**
     *  延迟几秒后执行
     * @param task
     * @param seconds
     */
    public void executeDelay(TimerTask task,long seconds)
    {
        executor.schedule(task, seconds, TimeUnit.SECONDS);
    }

    /**
     * 执行任务
     *
     * @param task 任务
     */
    public ScheduledFuture executeSchedule(TimerTask task,long delay,long period)
    {
        ScheduledFuture<?> scheduledFuture = executor.scheduleAtFixedRate(task, delay, period, TimeUnit.MILLISECONDS);
        return scheduledFuture;
    }

    /**
     * 停止任务线程池
     */
    public void shutdown()
    {
        Threads.shutdownAndAwaitTermination(executor);
    }
}
