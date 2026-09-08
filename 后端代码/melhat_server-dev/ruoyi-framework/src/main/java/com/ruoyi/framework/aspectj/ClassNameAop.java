package com.ruoyi.framework.aspectj;

import org.aspectj.lang.JoinPoint;
import org.aspectj.lang.annotation.Aspect;
import org.aspectj.lang.annotation.Before;
import org.aspectj.lang.annotation.Pointcut;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.aop.aspectj.MethodInvocationProceedingJoinPoint;
import org.springframework.context.annotation.Configuration;
import org.springframework.stereotype.Component;
/* 

* @Description: 
* @Author: zh
* @Version: 1.0
* @Date:  2023/8/3 18:00

*/

@Aspect
@Component
public class ClassNameAop {

    Logger logger  = LoggerFactory.getLogger(this.getClass());

    @Pointcut("@annotation(org.springframework.web.bind.annotation.GetMapping))")
    public void getPutCut(){}
    @Pointcut("@annotation(org.springframework.web.bind.annotation.PostMapping)")
    public void postPutCut(){}

    @Before("getPutCut() || postPutCut()")
    public void before(JoinPoint jp){
        MethodInvocationProceedingJoinPoint joinPoint = (MethodInvocationProceedingJoinPoint) jp;
        String className = joinPoint.getTarget().getClass().getName();
        String funName = joinPoint.getSignature().getName();
        logger.info("进入类：{} | 方法: {}",className,funName);
    }


}
