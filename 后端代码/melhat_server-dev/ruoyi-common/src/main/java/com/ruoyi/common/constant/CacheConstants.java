package com.ruoyi.common.constant;

/**
 * 缓存的key 常量
 * 
 * @author ruoyi
 */
public class CacheConstants
{
    /**
     * 登录用户 redis key
     */
    public static final String LOGIN_TOKEN_KEY = "login_tokens:";

    /** All session token uuids for one account, used to revoke immediately. */
    public static final String LOGIN_USER_TOKENS_KEY = "login_user_tokens:";

    /** Set when an account is disabled so in-flight tokens fail even if a key is missed. */
    public static final String ACCOUNT_DISABLED_KEY = "account_disabled:";

    /**
     * 验证码 redis key
     */
    public static final String CAPTCHA_CODE_KEY = "captcha_codes:";

    /**
     * 参数管理 cache key
     */
    public static final String SYS_CONFIG_KEY = "sys_config:";

    /**
     * 字典管理 cache key
     */
    public static final String SYS_DICT_KEY = "sys_dict:";

    /**
     * 防重提交 redis key
     */
    public static final String REPEAT_SUBMIT_KEY = "repeat_submit:";

    /**
     * 限流 redis key
     */
    public static final String RATE_LIMIT_KEY = "rate_limit:";

    /**
     * 登录账户密码错误次数 redis key
     */
    public static final String PWD_ERR_CNT_KEY = "pwd_err_cnt:";

    public static final String VIDEO_UPLOAD="VIDEO_UPLOAD_";
    //正在推流的数量
    public static final String VIDEO_TRMP_NUM="VIDEO_TRMP_NUM";
    //正在复制重要视频的数量
    public static final String VIDEO_TRMP_MOVE_NUM="VIDEO_TRMP_MOVE_NUM";

    public static final String HATINFO="hatInfo:";
    public static final String SIP_HAT="sip_hat:";
    public static final String HAT_VIDEO_INFO="hatVideoInfo:";
    public static final String SRS_INFO="srsInfo:";
    public static final String HAT="hat:";
}
