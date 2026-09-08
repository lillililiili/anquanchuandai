package com.ruoyi.headband.pojo.vo;

import lombok.Data;

import java.util.List;

@Data
public class ResourceFileVO {

    /**
     * 安全帽SN
     */
    private String helmetSn;
    private List<FileVO> file_list;
    private List<FileCountVO> file_count;


    public static class FileVO{
        /**
         * 媒体资源地址
         */
        private String url;
        /**
         * 媒体类型
         */
        private String type;
        /**
         *  文件最后修改时间
         */
        private String lastModified;
        /**
         * 文件大小（字节）
         */
        private String size;
        /**
         * 文件名
         */
        private String key;
    }

    public static class FileCountVO{
        private Integer image;
        private Integer video;
        private Integer audio;
    }

}
