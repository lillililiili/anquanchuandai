package com.ruoyi.headband.pojo.param;

import lombok.Data;

@Data
public class FileListParam {

    /**
     * video 视频
     *  audio 音频
     *  image 图片
     */
    private String type;

    private String helmetSn;
    /**
     * xxxx-xx-xx xx:xx:xx 形式
     */
    private String startTime;
    private String endTime;

    private Integer pageNum;
    private Integer pageSize;
}
