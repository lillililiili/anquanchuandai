package com.ruoyi.melhat;

import com.alibaba.fastjson2.JSON;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ruoyi.common.core.domain.AjaxResult;
import com.ruoyi.common.core.domain.entity.SysUser;
import com.ruoyi.common.core.domain.model.SysUserProfileDto;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class SysUserSerializationTest {

    private static final String SECRET = "hashed-secret-should-not-leak";

    @Test
    void jacksonDoesNotWritePassword() throws Exception {
        ObjectMapper mapper = new ObjectMapper();
        String json = mapper.writeValueAsString(sampleUser());
        assertFalse(json.contains("password"), json);
        assertFalse(json.contains(SECRET), json);
        assertTrue(json.contains("admin"), json);
    }

    @Test
    void fastjsonDoesNotWritePassword() {
        String json = JSON.toJSONString(sampleUser());
        assertFalse(json.contains("password"), json);
        assertFalse(json.contains(SECRET), json);
    }

    @Test
    void profileDtoOmitsPasswordAndKeepsAccount() throws Exception {
        SysUserProfileDto dto = SysUserProfileDto.from(sampleUser());
        assertNotNull(dto);
        assertNull(fieldIfPresent(dto));
        ObjectMapper mapper = new ObjectMapper();
        String json = mapper.writeValueAsString(dto);
        assertFalse(json.contains("password"), json);
        assertFalse(json.contains(SECRET), json);
        assertTrue(json.contains("\"userName\":\"admin\"") || json.contains("\"userName\": \"admin\""), json);

        AjaxResult ajax = AjaxResult.success();
        ajax.put("user", dto);
        String wrapped = mapper.writeValueAsString(ajax);
        assertFalse(wrapped.contains(SECRET), wrapped);
        assertFalse(wrapped.contains("\"password\""), wrapped);
    }

    @Test
    void toStringDoesNotPrintRawPassword() {
        String text = sampleUser().toString();
        assertFalse(text.contains(SECRET), text);
    }

    @Test
    void passwordCanBeReadFromRequestBody() throws Exception {
        ObjectMapper mapper = new ObjectMapper();
        SysUser user = mapper.readValue("{\"userName\":\"u1\",\"password\":\"plain-pass\"}", SysUser.class);
        assertEquals("plain-pass", user.getPassword());
    }

    private static String fieldIfPresent(SysUserProfileDto dto) {
        try {
            return (String) SysUserProfileDto.class.getDeclaredField("password").get(dto);
        } catch (NoSuchFieldException ignored) {
            return null;
        } catch (IllegalAccessException ex) {
            throw new IllegalStateException(ex);
        }
    }

    private static SysUser sampleUser() {
        SysUser user = new SysUser();
        user.setUserId(1L);
        user.setUserName("admin");
        user.setNickName("管理员");
        user.setPassword(SECRET);
        return user;
    }
}
