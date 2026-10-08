package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONObject;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Service;
import java.nio.charset.StandardCharsets;
import static com.ruoyi.guardian.WearableModel.*;

@Service
public class WearableCredentials {
    private static final BCryptPasswordEncoder ENCODER = new BCryptPasswordEncoder();
    private final AdminLedgerStore ledger;
    public WearableCredentials(AdminLedgerStore ledger) { this.ledger=ledger; }
    public JSONObject authenticate(String username,String password) {
        synchronized(ledger) {
            JSONObject state=ledger.read();
            JSONObject found=null;
            for(Object raw:rows(state,"accounts")) { JSONObject row=(JSONObject)raw;
                if(username!=null && (username.equals(row.getString("loginName")) || username.equals(row.getString("id")))) found=row; }
            if(found==null || !found.getBooleanValue("enabled") || password==null || password.getBytes(StandardCharsets.UTF_8).length>72
                    || text(found,"passwordHash").isEmpty() || !ENCODER.matches(password,found.getString("passwordHash")))
                throw AdminQueryService.fail(401,"IDENTITY_INVALID","账号或密码错误，或账号已停用");
            return copy(found);
        }
    }
    static String hash(String password) {
        if(password==null || password.length()<8 || password.getBytes(StandardCharsets.UTF_8).length>72)
            throw AdminQueryService.fail(400,"INVALID_PASSWORD","密码须至少8个字符，UTF-8长度不超过72字节");
        return ENCODER.encode(password);
    }
    static boolean migrate(JSONObject state) {
        if(state.getBooleanValue("hashedCredentialsV1")) return false;
        for(Object raw:rows(state,"accounts")) { JSONObject row=(JSONObject)raw;
            // One-time compatibility migration of the previous login contract. New accounts never inherit a default.
            if(text(row,"passwordHash").isEmpty()) row.put("passwordHash",ENCODER.encode("demo-duty".equals(row.getString("id"))?"123456":"Admin@2026")); }
        state.put("hashedCredentialsV1",true);
        return true;
    }
}
