package com.ruoyi.headband.service;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.common.constant.BusinessConst;
import com.ruoyi.common.core.redis.RedisCache;
import com.ruoyi.common.exception.ServiceException;
import com.ruoyi.common.utils.JacksonUtil;
import com.ruoyi.headband.client.OkHttpService;
import com.ruoyi.headband.pojo.param.*;
import com.ruoyi.headband.pojo.vo.HeadbandVO;
import com.ruoyi.headband.pojo.vo.ResourceFileVO;
import com.ruoyi.headband.pojo.vo.ResponseVO;
import lombok.extern.slf4j.Slf4j;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.ResponseBody;
import org.apache.commons.lang3.StringUtils;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.concurrent.TimeUnit;

@Service
@Slf4j
public class HeadbandService {

    @Value("${headband.server}")
    private String server;
    @Value("${headband.token.url}")
    private String tokenurl;
    @Value("${headband.token.username}")
    private String username;
    @Value("${headband.token.password}")
    private String password;

    @Value("${headband.device.list}")
    private String headbandDeviceApi;
    @Value("${headband.device.call.singCall}")
    private String singCallApi;
    @Value("${headband.device.call.groupCall}")
    private String groupCallApi;
    @Value("${headband.device.call.agoraToken}")
    private String agoraToken;
    @Value("${headband.device.call.agoraEnd}")
    private String agoraEnd;

    @Value("${headband.device.call.end}")
    private String endCallApi;
    @Value("${headband.device.playback}")
    private String playbackApi;
    @Value("${headband.device.singleBroadcast}")
    private String singleBroadcast;
    @Value("${headband.device.groupBroadcast}")
    private String groupBroadcastApi;
    @Value("${headband.device.startRecord}")
    private String startRecord;
    @Value("${headband.device.stopRecord}")
    private String stopRecord;
    @Value("${headband.device.recordStatus}")
    private String recordStatus;

    @Value("${headband.device.fileList}")
    private String fileListApi;

    @Autowired
    private OkHttpService okHttpService;

    @Autowired
    private RedisCache redisCache;

    public static void main(String[] args) {

    }

    public String getToken() throws Exception {
        if (StringUtils.isBlank(username) || StringUtils.isBlank(password)) {
            throw new ServiceException("真实设备平台凭据未配置，请设置 TOKEN_SERVICE_USERNAME 和 TOKEN_SERVICE_PASSWORD；未发起设备请求");
        }
        String accessToken = redisCache.getCacheObject(BusinessConst.CacheConst.HEADBAND_API_TOKEN);
        if (StringUtils.isNotBlank(accessToken)) {
            return accessToken;
        }
        String url = okhttp3.HttpUrl.parse(server + tokenurl).newBuilder()
                .addQueryParameter("client_id", username)
                .addQueryParameter("client_secret", password)
                .build().toString();
        String result = null;
        try {
            result = okHttpService.doGet(url, null, null);
        } catch (Exception e) {
            // 网络异常可能包含带凭据的请求 URL，不记录原始异常。
            log.warn("设备平台认证请求失败，异常类型: {}", e.getClass().getSimpleName());
            throw new ServiceException("设备平台认证失败，请检查网络、平台地址及账号凭据");
        }
        if (StringUtils.isBlank(result)) {
            throw new ServiceException("获取token异常");
        }
        try {
            JSONObject response = JSON.parseObject(result);
            if (response == null || !Integer.valueOf(200).equals(response.getInteger("code"))) {
                throw new ServiceException("设备平台认证未通过，请核对平台账号权限及凭据");
            }
            JSONObject data = response.getJSONObject("data");
            if (data == null || StringUtils.isBlank(data.getString("accessToken"))) {
                throw new ServiceException("设备平台认证响应缺少 Token，未连接真实设备");
            }
            String tokenType = StringUtils.defaultIfBlank(data.getString("tokenType"), "Bearer");
            Integer expireTime = data.getInteger("expireTime");
            if (expireTime == null || expireTime <= 0) {
                throw new ServiceException("设备平台认证响应有效期无效");
            }
            accessToken = tokenType + " " + data.getString("accessToken");
            redisCache.setCacheObject(BusinessConst.CacheConst.HEADBAND_API_TOKEN, accessToken,
                    Math.max(1, expireTime - 300), TimeUnit.SECONDS);
        } catch (ServiceException e) {
            throw e;
        } catch (RuntimeException e) {
            throw new ServiceException("设备平台认证响应格式异常");
        }
        return accessToken;
    }


    /**
     * 获取安全帽列表
     *
     * @param param
     * @return
     * @throws Exception
     */
    public List<HeadbandVO> getHeadBandList(Map<String, Object> param) throws Exception {
        String responseBody = readDeviceApi(server + headbandDeviceApi, param);
        if (StringUtils.isBlank(responseBody)) {
            throw new Exception("未获取到返回结果");
        }
        ResponseVO responseVO = JSONObject.parseObject(responseBody, ResponseVO.class);
        if (responseVO.getCode() != 200) {
            throw new ServiceException(responseVO.getMessage());
        }
//        List<HeadbandVO> list = (List<HeadbandVO>) responseVO.getData();
        List<HeadbandVO> list = JSONArray.parseArray(JSONObject.toJSONString(responseVO.getData()),HeadbandVO.class);
        log.info("获取安全帽列表:{}", list);
        return list;
    }

    /**
     * 获取单个安全帽设备信息
     *
     * @param sn
     * @return
     * @throws Exception
     */
    public HeadbandVO getMelhatInfo(String sn) throws Exception {
        String responseBody = readDeviceApi(server + headbandDeviceApi + "/" + sn, null);
        if (StringUtils.isBlank(responseBody)) {
            throw new Exception("未获取到返回结果");
        }
        ResponseVO responseVO = JSONObject.parseObject(responseBody, ResponseVO.class);
        if (responseVO.getCode() != 200) {
            throw new ServiceException(responseVO.getMessage());
        }
        if (responseVO.getData() != null) {
            HeadbandVO info = JSONObject.parseObject(
                    JSONObject.toJSONString(responseVO.getData()),
                    HeadbandVO.class
            );
            return info;
        }
        return null;
    }


    /**
     * 单呼
     *
     * @param param
     * @return
     * @throws Exception
     */
    public ResponseVO singleCall(SingCallParam param) throws Exception {
        Map<String, String> headers = getHeaders();
        String responseBody = null;
        try {
            responseBody = okHttpService.doPostJson(server + singCallApi, JacksonUtil.toMapByJackson(param), headers);
        } catch (Exception e) {
            log.error("请求安全帽异常", e);
            throw new ServiceException("请求安全帽异常");
        }
        if (StringUtils.isBlank(responseBody)) {
            throw new Exception("未获取到返回结果");
        }
        ResponseVO responseVO = JSONObject.parseObject(responseBody, ResponseVO.class);
        if (responseVO.getCode() != 200) {
            throw new ServiceException(responseVO.getMessage());
        }
        return responseVO;
    }

    /**
     * 群呼
     *
     * @param param
     * @return
     * @throws Exception
     */
    public ResponseVO groupCall(GroupCallParam param) throws Exception {
        Map<String, String> headers = getHeaders();
        String responseBody = null;
        try {
            responseBody = okHttpService.doPostJson(server + singCallApi, JacksonUtil.toMapByJackson(param), headers);
        } catch (Exception e) {
            log.error("请求安全帽异常", e);
            throw new ServiceException("请求安全帽异常");
        }
        if (StringUtils.isBlank(responseBody)) {
            throw new Exception("未获取到返回结果");
        }
        ResponseVO responseVO = JSONObject.parseObject(responseBody, ResponseVO.class);
        if (responseVO.getCode() != 200) {
            throw new ServiceException(responseVO.getMessage());
        }
        return responseVO;
    }

    /**
     * 获取声网 RTC 通话所需的四元组信息
     *
     * @param param
     * @return
     * @throws Exception
     */
    public ResponseVO agoraToken(Map<String, Object> param) throws Exception {
        Map<String, String> headers = getHeaders();
        String responseBody = null;
        try {
            responseBody = okHttpService.doPostJson(server + agoraToken, JacksonUtil.toMapByJackson(param), headers);
        } catch (Exception e) {
            log.error("请求安全帽异常", e);
            throw new ServiceException("请求安全帽异常");
        }
        if (StringUtils.isBlank(responseBody)) {
            throw new Exception("未获取到返回结果");
        }
        ResponseVO responseVO = JSONObject.parseObject(responseBody, ResponseVO.class);
        if (responseVO.getCode() != 200) {
            throw new ServiceException(responseVO.getMessage());
        }
        return responseVO;
    }

    /**
     * 声网 结束通话
     *
     * @param channelName
     * @return
     * @throws Exception
     */
    public ResponseVO agoraEnd(String channelName) throws Exception {
        Map<String, String> headers = getHeaders();
        String responseBody = null;
        try {
            Map<String, Object> params = new HashMap<>();
            params.put("channelName", channelName);
            responseBody = okHttpService.doPostJson(server + agoraEnd, params, headers);
        } catch (Exception e) {
            log.error("请求安全帽异常", e);
            throw new ServiceException("请求安全帽异常");
        }
        if (StringUtils.isBlank(responseBody)) {
            throw new Exception("未获取到返回结果");
        }
        ResponseVO responseVO = JSONObject.parseObject(responseBody, ResponseVO.class);
        if (responseVO.getCode() != 200) {
            throw new ServiceException(responseVO.getMessage());
        }
        return responseVO;
    }


    /**
     * 结束通话
     *
     * @param helmetSn
     * @return
     * @throws Exception
     */
    public ResponseVO endCall(String helmetSn) throws Exception {
        Map<String, String> headers = getHeaders();
        String responseBody = null;
        try {
            responseBody = okHttpService.doPutJson(server + endCallApi + "/" + helmetSn, null, headers);
        } catch (Exception e) {
            log.error("请求安全帽异常", e);
            throw new ServiceException("请求安全帽异常");
        }
        if (StringUtils.isBlank(responseBody)) {
            throw new Exception("未获取到返回结果");
        }
        ResponseVO responseVO = JSONObject.parseObject(responseBody, ResponseVO.class);
        if (responseVO.getCode() != 200) {
            throw new ServiceException(responseVO.getMessage());
        }
        return responseVO;
    }

    /**
     * 获取对讲回放媒体资源
     *
     * @param helmetSn
     * @return
     * @throws Exception
     */
    public List<ResourceFileVO> playback(String helmetSn) throws Exception {
        Map<String, String> headers = getHeaders();
        String responseBody = null;
        try {
            responseBody = okHttpService.doGet(server + playbackApi + "/" + helmetSn, headers, null);
        } catch (Exception e) {
            log.error("请求安全帽异常", e);
            throw new ServiceException("请求安全帽异常");
        }
        if (StringUtils.isBlank(responseBody)) {
            throw new Exception("未获取到返回结果");
        }
        ResponseVO responseVO = JSONObject.parseObject(responseBody, ResponseVO.class);
        if (responseVO.getCode() != 200) {
            throw new ServiceException(responseVO.getMessage());
        }
        List<ResourceFileVO> list = JSONArray.parseArray(
                JSONObject.toJSONString(responseVO.getData()),
                ResourceFileVO.class
        );
        return list;
    }


    /**
     * TTS单播
     *
     * @param param
     * @return
     * @throws Exception
     */
    public ResponseVO singleBroadcast(TtsSingleBroadcastParam param) throws Exception {
        Map<String, String> headers = getHeaders();
        String responseBody = null;
        try {
            responseBody = okHttpService.doPostJson(server + singleBroadcast, JacksonUtil.toMapByJackson(param), headers);
        } catch (Exception e) {
            log.error("请求安全帽异常", e);
            throw new ServiceException("请求安全帽异常");
        }
        if (StringUtils.isBlank(responseBody)) {
            throw new Exception("未获取到返回结果");
        }
        ResponseVO responseVO = JSONObject.parseObject(responseBody, ResponseVO.class);
        if (responseVO.getCode() != 200) {
            throw new ServiceException(responseVO.getMessage());
        }
        return responseVO;
    }

    /**
     * TTS群播
     *
     * @param param
     * @return
     * @throws Exception
     */
    public ResponseVO groupBroadcast(TtsBroadcastParam param) throws Exception {
        Map<String, String> headers = getHeaders();
        String responseBody = null;
        try {
            responseBody = okHttpService.doPostJson(server + groupBroadcastApi, JacksonUtil.toMapByJackson(param), headers);
        } catch (Exception e) {
            log.error("请求安全帽异常", e);
            throw new ServiceException("请求安全帽异常：TTS语音播报异常");
        }
        if (StringUtils.isBlank(responseBody)) {
            throw new Exception("未获取到返回结果");
        }
        ResponseVO responseVO = JSONObject.parseObject(responseBody, ResponseVO.class);
        if (responseVO.getCode() != 200) {
            throw new ServiceException(responseVO.getMessage());
        }
        return responseVO;
    }

    /**
     * 文件列表
     *
     * @param param
     * @return
     * @throws Exception
     */
    public ResponseVO getFileList(FileListParam param) throws Exception {
        Map<String, String> headers = getHeaders();
        Map<String, Object> params = JacksonUtil.toMapByJackson(param);
        String responseBody = null;
        try {
            responseBody = okHttpService.doGet(server + fileListApi, headers, params);
        } catch (Exception e) {
            log.error("请求安全帽异常", e);
            throw new ServiceException("请求安全帽异常");
        }
        if (StringUtils.isBlank(responseBody)) {
            throw new Exception("未获取到返回结果");
        }
        ResponseVO responseVO = JSONObject.parseObject(responseBody, ResponseVO.class);
        if (responseVO.getCode() != 200) {
            throw new ServiceException(responseVO.getMessage());
        }
        return responseVO;
    }

    /**
     * 开始云端录制
     *
     * @param param
     * @return
     * @throws Exception
     */
    public ResponseVO startRecord(StartRecordParam param) throws Exception {
        Map<String, String> headers = getHeaders();
        Map<String, Object> params = JacksonUtil.toMapByJackson(param);
        String responseBody = null;
        try {
            responseBody = okHttpService.doPostJson(server + startRecord, params, headers);
        } catch (Exception e) {
            log.error("请求安全帽异常", e);
            throw new ServiceException("请求安全帽异常");
        }
        if (StringUtils.isBlank(responseBody)) {
            throw new Exception("未获取到返回结果");
        }
        ResponseVO responseVO = JSONObject.parseObject(responseBody, ResponseVO.class);
        if (responseVO.getCode() != 200) {
            throw new ServiceException(responseVO.getMessage());
        }
        return responseVO;
    }

    /**
     * 停止录制
     *
     * @param sid
     * @return
     * @throws Exception
     */
    public ResponseVO stopRecord(String sid) throws Exception {
        Map<String, String> headers = getHeaders();
        Map<String, Object> params = new HashMap<>();
        params.put("sid", sid);
        String responseBody = null;
        try {
            responseBody = okHttpService.doPostJson(server + stopRecord, params, headers);
        } catch (Exception e) {
            log.error("请求安全帽异常", e);
            throw new ServiceException("请求安全帽异常");
        }
        if (StringUtils.isBlank(responseBody)) {
            throw new Exception("未获取到返回结果");
        }
        ResponseVO responseVO = JSONObject.parseObject(responseBody, ResponseVO.class);
        if (responseVO.getCode() != 200) {
            throw new ServiceException(responseVO.getMessage());
        }
        return responseVO;
    }




    // 仅对只读查询重试一次。通话、广播等控制请求绝不自动重放。
    private String readDeviceApi(String url, Map<String, Object> param) throws Exception {
        for (int attempt = 0; attempt < 2; attempt++) {
            try {
                String body = okHttpService.doGet(url, getHeaders(), param);
                JSONObject result = StringUtils.isBlank(body) ? null : JSON.parseObject(body);
                if (result != null && Integer.valueOf(401).equals(result.getInteger("code"))) {
                    throw new ServiceException("设备平台认证已失效", 401);
                }
                return body;
            } catch (ServiceException e) {
                if (attempt == 0 && Integer.valueOf(401).equals(e.getCode())) {
                    redisCache.deleteObject(BusinessConst.CacheConst.HEADBAND_API_TOKEN);
                } else {
                    throw e;
                }
            }
        }
        throw new ServiceException("设备平台认证失败，请核对凭据");
    }

    private Map<String, String> getHeaders() throws Exception {
        String accessToken = getToken();
        Map<String, String> headers = new HashMap<>();
        headers.put("Authorization", accessToken);
        return headers;
    }


}
