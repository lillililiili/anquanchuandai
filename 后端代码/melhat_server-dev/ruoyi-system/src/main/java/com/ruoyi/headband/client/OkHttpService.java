package com.ruoyi.headband.client;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.common.constant.BusinessConst;
import com.ruoyi.common.core.redis.RedisCache;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.headband.pojo.vo.ResponseVO;
import lombok.extern.slf4j.Slf4j;
import okhttp3.*;
import org.apache.commons.lang3.StringUtils;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.util.CollectionUtils;

import java.io.UnsupportedEncodingException;
import java.net.URLEncoder;
import java.util.Map;
import java.util.concurrent.TimeUnit;

@Component
@Slf4j
public class OkHttpService {


    @Autowired
    private OkHttpClient okHttpClient;

    /**
     * 同步GET请求
     */
    public String doGet(String url, Map<String, String> headers, Map<String, Object> param) throws Exception {
        HttpUrl.Builder urlBuilder = HttpUrl.parse(url).newBuilder();
        if (!CollectionUtils.isEmpty(param)) {
            param.forEach((key, value) -> {
                String paramValue;
                if (value instanceof java.util.List || value.getClass().isArray()) {
                    // 将List或数组转换为JSON数组格式
                    paramValue = JSON.toJSONString(value);
                } else {
                    paramValue = String.valueOf(value);
                }
                // 对参数值进行URL编码
                String encodedValue = null;
                try {
                    encodedValue = URLEncoder.encode(paramValue, "UTF-8");
                } catch (UnsupportedEncodingException e) {
                    throw new RuntimeException(e);
                }
                urlBuilder.addEncodedQueryParameter(key, encodedValue);
            });
        }
        String acturl = urlBuilder.build().toString();
        log.info("请求URL: {}", acturl);
        Request.Builder builder = new Request.Builder().url(acturl).get();
        if (!CollectionUtils.isEmpty(headers)) {
            headers.forEach(builder::addHeader);
        }
        Request request = builder.build();
        try (Response response = okHttpClient.newCall(request).execute()) {
            if (!response.isSuccessful()) {
                throw new ServiceException("请求异常: " + response);
            }
            ResponseBody body = response.body();
            return body == null ? null : body.string();
        }
    }

    /**
     * 同步POST JSON请求
     */
    public String doPostJson(String url, Map<String, Object> params, Map<String, String> headers) throws Exception {
        // 打印请求信息
        log.info("========== HTTP POST 请求 ==========");
        log.info("请求URL: {}", url);
        log.info("请求Headers: {}", headers);
        log.info("请求Params: {}", JSON.toJSONString(params));
        
        MediaType mediaType = MediaType.parse("application/json; charset=utf-8");
        RequestBody requestBody = RequestBody.create(mediaType, JSON.toJSONString(params));
        Request.Builder builder = new Request.Builder().url(url).post(requestBody);
        if (!CollectionUtils.isEmpty(headers)) {
            headers.forEach(builder::addHeader);
        }
        Request request = builder.build();
        
        try (Response response = okHttpClient.newCall(request).execute()) {
            log.info("响应状态码: {}", response.code());
            log.info("响应消息: {}", response.message());
            
            if (!response.isSuccessful()) {
                log.error("请求失败 - 状态码: {}, 消息: {}", response.code(), response.message());
                throw new ServiceException("请求异常: " + response);
            }
            ResponseBody responseBody = response.body();
            String result = responseBody == null ? null : responseBody.string();
            log.info("响应内容: {}", result);
            log.info("====================================");
            return result;
        } catch (Exception e) {
            log.error("HTTP POST 请求异常 - URL: {}, 错误: {}", url, e.getMessage(), e);
            throw e;
        }
    }

    /**
     * PUT JSON请求
     */
    public String doPutJson(String url, String jsonParam, Map<String, String> headers) throws Exception {
        MediaType mediaType = MediaType.parse("application/json; charset=utf-8");
        RequestBody requestBody = RequestBody.create(mediaType, jsonParam);
        Request.Builder builder = new Request.Builder().url(url).put(requestBody);
        if (!CollectionUtils.isEmpty(headers)) {
            headers.forEach(builder::addHeader);
        }
        Request request = builder.build();
        try (Response response = okHttpClient.newCall(request).execute()) {
            if (!response.isSuccessful()) {
                throw new ServiceException("请求异常: " + response);
            }
            ResponseBody responseBody = response.body();
            return responseBody == null ? null : responseBody.string();
        }
    }

    /**
     * 异步GET请求（带回调）
     */
    public void doGetAsync(String url, Map<String, String> headers, Callback callback) {
        Request.Builder builder = new Request.Builder().url(url).get();
        if (!CollectionUtils.isEmpty(headers)) {
            headers.forEach(builder::addHeader);
        }
        Request request = builder.build();
        okHttpClient.newCall(request).enqueue(callback);
    }
}