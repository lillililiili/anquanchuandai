package com.ruoyi.system.utils;

import org.osgeo.proj4j.*;

//gps坐标
public class GPS2MKTUtil {

    //lng 经度  lat 纬度
    public static ProjCoordinate gps2MKT(double lng, double lat) {
        // 创建Proj4J地理CRS
        CRSFactory crsFactory = new CRSFactory();
        CoordinateReferenceSystem wgs84 = crsFactory.createFromName("EPSG:4326");//指明坐标系 4326代表gps
        CoordinateReferenceSystem mercator = crsFactory.createFromName("EPSG:3857"); //3857 代表 墨卡托

        // 创建坐标变换对象
        CoordinateTransform transform = new BasicCoordinateTransform(wgs84, mercator);

        // 定义一个WGS-84坐标点 118.63809195032725, 38.056841021216485
       // double lng = 118.63809195032725;
       // double lat = 38.056841021216485;

        // 进行坐标转换
        ProjCoordinate source = new ProjCoordinate(lng, lat);
        ProjCoordinate target = new ProjCoordinate();
        transform.transform(source, target);

        // 输出墨卡托坐标
        System.out.println(target.toShortString());

        return target;
    }

    //lng 经度  lat 纬度
    public static ProjCoordinate mkt2GPS(double lng,double lat) {
        // 创建Proj4J地理CRS
        CRSFactory crsFactory = new CRSFactory();
        CoordinateReferenceSystem wgs84 = crsFactory.createFromName("EPSG:4326");
        CoordinateReferenceSystem mercator = crsFactory.createFromName("EPSG:3857");

        // 创建坐标变换对象
        CoordinateTransform transform = new BasicCoordinateTransform( mercator,wgs84);

        // 定义一个WGS-84坐标点 117.139079,36.725794


//        double lng = 13205562.595782;
//        double lat = 4593447.713043;

        // 进行坐标转换
        ProjCoordinate source = new ProjCoordinate(lng, lat);
        ProjCoordinate target = new ProjCoordinate();
        transform.transform(source, target);

        // 输出墨卡托坐标
        System.out.println(target.toShortString());

        return target;
    }

    public static void main(String[] args) {
        CRSFactory crsFactory = new CRSFactory();
        CoordinateReferenceSystem wgs84 = crsFactory.createFromName("EPSG:4326");
        CoordinateReferenceSystem mercator = crsFactory.createFromName("EPSG:3857");

        // 创建坐标变换对象
        CoordinateTransform transform = new BasicCoordinateTransform( mercator,wgs84);

        // 定义一个WGS-84坐标点 117.139079,36.725794


        double lng = 13232623.554176;
        double lat = 4564290.371634;


        // 进行坐标转换
        ProjCoordinate source = new ProjCoordinate(lng, lat);
        ProjCoordinate target = new ProjCoordinate();
        transform.transform(source, target);

        // 输出墨卡托坐标
        System.out.println(target.toShortString());
    }
}
