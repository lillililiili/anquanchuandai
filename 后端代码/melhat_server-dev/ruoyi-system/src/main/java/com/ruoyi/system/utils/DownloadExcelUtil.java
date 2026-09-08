package com.ruoyi.system.utils;

//下载实现

import lombok.extern.slf4j.Slf4j;

import javax.servlet.ServletOutputStream;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.InputStream;
import java.net.URLEncoder;

/**
 * @ClassName: DownloadExcelUtil
 * @Description: 文件下载
 **/
@Slf4j
public class DownloadExcelUtil {

    private static final String filesPath = "model/";

    /**
     * @description: Resource中文件模板下载
     * @param: [request, response, fileName]
     **/
    public static void downAchievementTemplate(HttpServletRequest request,
                                               HttpServletResponse response,
                                               String fileName){
        ServletOutputStream out;
        response.setContentType("multipart/form-data");
        response.setCharacterEncoding("UTF-8");
        response.setContentType("text/html");
        try {
            InputStream inputStream = DownloadExcelUtil.class.getClassLoader().getResourceAsStream(filesPath + fileName);
            String userAgent = request.getHeader("User-Agent");
            if (userAgent.contains("MSIE") || userAgent.contains("Trident")) {
                fileName = URLEncoder.encode(fileName, "UTF-8");
            } else {
                // 非IE浏览器的处理：
                fileName = new String((fileName).getBytes("UTF-8"), "ISO-8859-1");
            }
            response.setHeader("Content-Disposition", "attachment;fileName=" + fileName);
            out = response.getOutputStream();
            int b = 0;
            byte[] buffer = new byte[1024];
            while ((b = inputStream.read(buffer)) != -1) {
                // 4.写到输出流(out)中
                out.write(buffer, 0, b);
            }
            inputStream.close();
            if (out != null) {
                out.flush();
                out.close();
            }
        } catch (Exception e) {
            log.error("文件下载失败，异常：{}", e.getMessage());
            throw new RuntimeException("文件下载失败！");
        }
    }
}
