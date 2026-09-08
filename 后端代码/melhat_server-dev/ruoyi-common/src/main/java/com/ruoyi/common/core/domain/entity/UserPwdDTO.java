package com.ruoyi.common.core.domain.entity;

import lombok.Data;

@Data
public class UserPwdDTO {

    private String oldPassword;
    private String newPassword;

}
