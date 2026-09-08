package com.ruoyi.common.core.domain.entity;

import lombok.Data;

import java.util.List;

@Data
public class AssistDO {

    /**
     * app呼叫 90 帽子呼叫91 pc呼叫92
     */
    private String sosType;

    /**
     * 选择的协助人列表
     */
    private List<AssistInfo> assistList;


    @Data
    public static class AssistInfo {
        private Long userId;

        private String userSipId;

        private String hatNumber;

        private String hatSipId;

        private String userName;


    }


}
