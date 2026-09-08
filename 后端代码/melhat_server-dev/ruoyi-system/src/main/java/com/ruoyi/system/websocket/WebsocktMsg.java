package com.ruoyi.system.websocket;

import lombok.AllArgsConstructor;
import lombok.Data;

@Data
@AllArgsConstructor
public class WebsocktMsg {

    private String type;

    private Object data;
}
