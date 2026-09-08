package com.ruoyi.common.utils.bean;

import lombok.Data;

@Data
public class LatLng {

    public Double longitude;
    public Double latitude;

    public LatLng() {
    }

    public LatLng(Double longitude, Double latitude) {
        this.longitude = longitude;
        this.latitude = latitude;
    }

}
