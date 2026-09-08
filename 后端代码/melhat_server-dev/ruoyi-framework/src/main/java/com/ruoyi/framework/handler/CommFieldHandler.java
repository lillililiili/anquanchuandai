package com.ruoyi.framework.handler;

import com.baomidou.mybatisplus.core.handlers.MetaObjectHandler;
import com.ruoyi.common.core.domain.model.LoginUser;
import com.ruoyi.common.utils.SecurityUtils;
import lombok.extern.slf4j.Slf4j;
import org.apache.ibatis.reflection.MetaObject;
import org.springframework.stereotype.Component;
import org.springframework.util.Assert;

import java.util.Date;
import java.util.Objects;

@Component
@Slf4j
public class CommFieldHandler implements MetaObjectHandler {


    @Override
    public void insertFill(MetaObject metaObject) {
        log.info("insertFill--------");
        LoginUser loginUser = SecurityUtils.getCurtLoginUser();
        Object createId = getFieldValByName("createBy", metaObject);
        Object createTime = getFieldValByName("createTime", metaObject);
        if (Objects.isNull(createId)) {
            this.setFieldValByName("createBy", loginUser==null?"":loginUser.getUser().getUserName(), metaObject);
        }
        if (Objects.isNull(createTime)) {
            this.setFieldValByName("createTime", new Date(), metaObject);
        }
    }

    @Override
    public void updateFill(MetaObject metaObject) {
        log.info("updateFill--------");
        LoginUser loginUser = SecurityUtils.getCurtLoginUser();
        Object updateId = getFieldValByName("updateBy", metaObject);
        Object updateTime = getFieldValByName("updateTime", metaObject);
        if (Objects.isNull(updateId)) {
            this.setFieldValByName("updateBy", loginUser==null?"":loginUser.getUser().getUserName(), metaObject);
        }
        if (Objects.isNull(updateTime)) {
            this.setFieldValByName("updateTime", new Date(), metaObject);
        }
    }
}
