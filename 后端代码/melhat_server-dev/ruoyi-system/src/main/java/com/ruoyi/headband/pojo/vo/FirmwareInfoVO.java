package com.ruoyi.headband.pojo.vo;

import lombok.Data;

@Data
public class FirmwareInfoVO {

    private String id;

    private String version;

    private String force_upgrade;

    private String firmware_model;

    private String download_url;

    private String  comment;

    private String created_at;
}
