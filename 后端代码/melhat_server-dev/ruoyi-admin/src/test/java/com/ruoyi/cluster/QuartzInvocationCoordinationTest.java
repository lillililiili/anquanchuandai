package com.ruoyi.cluster;
import com.ruoyi.common.core.ClusterJobExecution;
import com.ruoyi.common.constant.ScheduleConstants;
import com.ruoyi.common.utils.spring.SpringUtils;
import com.ruoyi.quartz.domain.SysJob;
import com.ruoyi.quartz.service.ISysJobLogService;
import com.ruoyi.quartz.util.*;
import org.junit.jupiter.api.Test;
import org.quartz.*;
import org.springframework.beans.factory.support.DefaultListableBeanFactory;
import org.springframework.test.util.ReflectionTestUtils;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
class QuartzInvocationCoordinationTest {
    public static class Target {int calls;public void run(){calls++;}}
    @Test void actualConcurrentAndSerialJobEntriesInvokeCoordinatorAndSkipWithoutSuccessLog()throws Exception {
        Object original=ReflectionTestUtils.getField(SpringUtils.class,"beanFactory");
        try{
            DefaultListableBeanFactory beans=new DefaultListableBeanFactory();new SpringUtils().postProcessBeanFactory(beans);
            Target target=new Target();beans.registerSingleton("fixtureTarget",target);ISysJobLogService logs=mock(ISysJobLogService.class);beans.registerSingleton("jobLogs",logs);
            List<String> firing=new ArrayList<>();ClusterJobExecution coordinator=(job,fire,action)->{firing.add(job+":"+fire);if(firing.size()==1)return false;action.run();return true;};beans.registerSingleton("cluster",coordinator);
            SysJob job=new SysJob();job.setJobId(42L);job.setJobName("fixture");job.setJobGroup("fixture");job.setInvokeTarget("fixtureTarget.run()");
            JobExecutionContext context=mock(JobExecutionContext.class);JobDataMap data=new JobDataMap();data.put(ScheduleConstants.TASK_PROPERTIES,job);when(context.getMergedJobDataMap()).thenReturn(data);when(context.getScheduledFireTime()).thenReturn(new Date(1000));
            new QuartzJobExecution().execute(context);assertEquals(0,target.calls);verifyNoInteractions(logs);
            new QuartzDisallowConcurrentExecution().execute(context);assertEquals(1,target.calls);verify(logs,times(1)).addJobLog(any());assertEquals(Arrays.asList("42:1000","42:1000"),firing);
        }finally{ReflectionTestUtils.setField(SpringUtils.class,"beanFactory",original);}
    }
}
