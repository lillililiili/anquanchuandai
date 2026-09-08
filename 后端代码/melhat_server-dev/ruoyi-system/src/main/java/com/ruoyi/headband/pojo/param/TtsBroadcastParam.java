package com.ruoyi.headband.pojo.param;

import lombok.AllArgsConstructor;
import lombok.Data;

import java.util.List;

@Data
@AllArgsConstructor
public class TtsBroadcastParam {

    private List<String> helmetSnList;

    private String tts_text;

}
