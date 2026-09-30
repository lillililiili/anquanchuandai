package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import com.ruoyi.common.core.redis.RedisCache;
import org.springframework.stereotype.Service;
import javax.servlet.http.HttpServletRequest;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.concurrent.TimeUnit;

/** Opaque, server-owned sessions, separate from the legacy RuoYi login. */
@Service
public class WearableSessions {
    public static final String HEADER = "X-Wearable-Token";
    private final RedisCache redis;
    private final AdminLedgerStore ledger;
    private final SecureRandom random = new SecureRandom();
    public WearableSessions(RedisCache redis, AdminLedgerStore ledger) { this.redis = redis; this.ledger = ledger; }

    public String issue(JSONObject account, String audience) {
        byte[] bytes = new byte[32]; random.nextBytes(bytes);
        String token = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
        JSONObject session = new JSONObject();
        session.put("accountId", account.getString("id"));
        session.put("credentialVersion", version(account));
        session.put("audience", audience);
        redis.setCacheObject("wearable:session:" + token, session.toJSONString(), 8, TimeUnit.HOURS);
        return token;
    }

    public JSONObject require(HttpServletRequest request, String audience) {
        String token = request.getHeader(HEADER);
        if (token == null || !token.matches("[A-Za-z0-9_-]{43}")) throw unauthorized();
        String value = redis.getCacheObject("wearable:session:" + token);
        if (value == null) throw unauthorized();
        JSONObject session = JSONObject.parseObject(value);
        JSONObject state = ledger.read();
        if (!audience.equals(session.getString("audience")) || state == null) throw unauthorized();
        for (Object item : state.getJSONArray("accounts")) {
            JSONObject actor = (JSONObject) item;
            if (actor.getString("id").equals(session.getString("accountId")) && actor.getBooleanValue("enabled")
                    && version(actor) == session.getIntValue("credentialVersion")) return actor;
        }
        throw unauthorized();
    }
    public void revoke(HttpServletRequest request) {
        String token = request.getHeader(HEADER);
        if (token != null) redis.deleteObject("wearable:session:" + token);
    }
    public static JSONObject actor(HttpServletRequest request) { return (JSONObject) request.getAttribute("wearable.actor"); }
    private static int version(JSONObject account) { return Math.max(1, account.getIntValue("credentialVersion")); }
    private static AdminQueryService.QueryFailed unauthorized() { return AdminQueryService.fail(401, "SESSION_EXPIRED", "登录已失效，请重新登录"); }
}
