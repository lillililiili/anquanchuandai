package com.ruoyi.helmet.vo;

import com.ruoyi.helmet.pojo.po.ElectronicFence;
import com.ruoyi.helmet.pojo.po.ElectronicFenceLatitude;
import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

import java.util.List;

@Data
@ApiModel(value = "电子围栏信息", description = "电子围栏信息")
public class SaveFenceRequest {

    @ApiModelProperty(value = "电子围栏")
    private ElectronicFence fence;

    @ApiModelProperty(value = "电子围栏坐标")
    private List<ElectronicFenceLatitude> coordinates;
}
