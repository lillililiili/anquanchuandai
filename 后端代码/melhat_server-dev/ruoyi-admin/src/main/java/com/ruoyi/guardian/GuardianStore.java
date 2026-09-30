package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONObject;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

@Component
public class GuardianStore {
    public interface Edit {
        /** 返回 true 时校验并保存。没有改动时返回 false。 */
        boolean apply(JSONObject state);
    }

    private static final Logger log = LoggerFactory.getLogger(GuardianStore.class);

    private final Object lock = new Object();
    private final Path file = storeFile();
    private final GuardianHatArchive hats;
    private JSONObject state;
    private boolean hatsMirrored;
    @org.springframework.beans.factory.annotation.Autowired(required=false) private AdminLedgerStore ledger;

    private void projectPlatform() {
        if(ledger==null)return;
        JSONObject next=JSON.parseObject(state.toJSONString());
        if(PlatformProjection.apply(next,ledger.read())) {
            next.put("seq",state.getIntValue("seq")+1);
            commit(next);
        }
    }

    public GuardianStore(GuardianHatArchive hats) {
        this.hats = hats;
    }

    public JSONObject snapshot() {
        synchronized (lock) {
            ensure();
            projectPlatform();
            mirrorHats();
            return JSON.parseObject(state.toJSONString());
        }
    }

    public void replace(JSONObject next) {
        GuardianValidator.check(next);
        synchronized (lock) {
            commit(next);
        }
    }

    public void replaceFromClient(JSONObject next, int expectedSeq) {
        synchronized (lock) {
            ensure();
            projectPlatform();
            for (String key : new String[]{"works", "stations", "people", "devices", "bindings", "mapAreas", "platformSync"}) {
                if (!java.util.Objects.equals(state.get(key), next.get(key)))
                    throw new IllegalArgumentException("作业票、人员与装备来源资料只读，请刷新后重试");
            }
            if (expectedSeq != state.getIntValue("seq") || next.getIntValue("seq") <= expectedSeq)
                throw new IllegalArgumentException("数据已变化，请刷新后重试");
            GuardianValidator.check(next);
            commit(next);
        }
    }

    public void update(Edit edit) {
        synchronized (lock) {
            ensure();
            JSONObject next = JSON.parseObject(state.toJSONString());
            if (edit == null || !edit.apply(next)) return;
            GuardianValidator.check(next);
            commit(next);
        }
    }

    private void commit(JSONObject next) {
        hats.sync(next);
        JSONObject previous = state;
        state = next;
        try {
            persist();
        } catch (RuntimeException error) {
            state = previous;
            hatsMirrored = false;
            throw error;
        }
        hatsMirrored = true;
    }

    private void mirrorHats() {
        if (hatsMirrored || state == null) return;
        try {
            hats.sync(state);
            hatsMirrored = true;
        } catch (RuntimeException error) {
            log.warn("安全帽档案尚未对齐: {}", error.getMessage());
        }
    }

    private static Path storeFile() {
        Path data = Paths.get("/data");
        if (Files.isDirectory(data)) return data.resolve("guardian-state.json");
        return Paths.get("data", "guardian-state.json");
    }

    private void ensure() {
        if (state != null && readable(state)) return;
        try {
            if (Files.exists(file)) {
                JSONObject saved = JSON.parseObject(readBytes(Files.readAllBytes(file)));
                if (readable(saved)) {
                    state = saved;
                    return;
                }
            }
            state = JSON.parseObject(readStream(new ClassPathResource("guardian-seed.json").getInputStream()));
            persist();
        } catch (Exception e) {
            throw new IllegalStateException("监护数据不可用", e);
        }
    }

    private static boolean readable(JSONObject value) {
        if (value == null || value.getJSONArray("stations") == null || value.getJSONArray("stations").isEmpty()) return false;
        String name = value.getJSONArray("stations").getJSONObject(0).getString("name");
        if (name == null) return false;
        for (int i = 0; i < name.length(); i++) {
            char c = name.charAt(i);
            if (c >= 0x4e00 && c <= 0x9fff) return true;
        }
        return false;
    }

    private void persist() {
        try {
            if (file.getParent() != null) Files.createDirectories(file.getParent());
            Files.write(file, state.toJSONString().getBytes(StandardCharsets.UTF_8));
        } catch (Exception e) {
            throw new IllegalStateException("监护数据保存失败", e);
        }
    }

    private static String readBytes(byte[] bytes) {
        return new String(bytes, StandardCharsets.UTF_8);
    }

    private static String readStream(InputStream input) throws Exception {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        int n;
        while ((n = input.read(buffer)) >= 0) out.write(buffer, 0, n);
        input.close();
        return new String(out.toByteArray(), StandardCharsets.UTF_8);
    }
}
