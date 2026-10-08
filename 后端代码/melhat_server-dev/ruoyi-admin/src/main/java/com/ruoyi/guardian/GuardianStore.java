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
            for (String key : new String[]{"works", "stations", "people", "devices", "bindings", "mapAreas", "platformSync", "events", "sos", "assistance", "eventOperations", "uploads"}) {
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
            projectPlatform();
            JSONObject next = JSON.parseObject(state.toJSONString());
            if (edit == null || !edit.apply(next)) return;
            GuardianValidator.check(next);
            commit(next);
        }
    }

    public void replaceScoped(JSONObject next, int expectedSeq, GuardianAccess.Context ctx) {
        update(current -> {
            if(expectedSeq!=current.getIntValue("seq") || next.getIntValue("seq")<=expectedSeq)
                throw AdminQueryService.fail(409,"VERSION_CONFLICT","数据已变化，请刷新后重试");
            JSONObject visible=ctx.snapshot(current);
            for(String key:new String[]{"events","assistance","sos","works","stations","people","devices","bindings","mapAreas","platformSync","vitals","locations"}) {
                if(!java.util.Objects.equals(visible.get(key),next.get(key)))
                    throw AdminQueryService.fail(409,"SNAPSHOT_READ_ONLY","事件、SOS和来源资料须使用共用业务接口，不能整份覆盖");
            }
            // Preserve invisible rows and all migrated event media. Only legacy domains remain writable.
            for(String key:new String[]{"fences","fenceRecords","groups","calls","broadcasts","media"}) {
                com.alibaba.fastjson2.JSONArray old=WearableModel.rows(visible,key), supplied=WearableModel.rows(next,key);
                if(java.util.Objects.equals(old,supplied)) continue;
                java.util.Set<String> visibleIds=new java.util.HashSet<>();
                for(Object raw:old) visibleIds.add(((JSONObject)raw).getString("id"));
                com.alibaba.fastjson2.JSONArray merged=new com.alibaba.fastjson2.JSONArray();
                for(Object raw:WearableModel.rows(current,key)) if(!visibleIds.contains(((JSONObject)raw).getString("id"))) merged.add(raw);
                for(Object raw:supplied) {
                    JSONObject row=(JSONObject)raw;
                    String site=WearableModel.siteId(ctx.data,row.getString("station"));
                    if(!ctx.can("events:read",site,null)) throw AdminQueryService.fail(403,"PERMISSION_DENIED","快照变更超出授权范围");
                    JSONObject prior=WearableModel.find(visible,key,row.getString("id"));
                    if("media".equals(key) && (migratedPhoto(row) || migratedPhoto(prior)) && !java.util.Objects.equals(prior,row))
                        throw AdminQueryService.fail(409,"SNAPSHOT_READ_ONLY","事件照片只能通过业务接口保存");
                    if(!visibleIds.contains(row.getString("id")) && WearableModel.find(current,key,row.getString("id"))!=null)
                        throw AdminQueryService.fail(409,"ID_CONFLICT","记录编号已存在");
                    if("media".equals(key) && prior==null && row.getString("blobId")!=null) {
                        JSONObject uploads=current.getJSONObject("uploads"), upload=uploads==null?null:uploads.getJSONObject(row.getString("blobId"));
                        if(upload==null || !ctx.id().equals(upload.getString("ownerId")) || upload.getString("eventId")!=null)
                            throw AdminQueryService.fail(403,"PHOTO_SCOPE","不能引用其他人员的照片");
                        if(row.getString("eventId")!=null&&!row.getString("eventId").isEmpty()) ctx.requireEvent(WearableModel.find(current,"events",row.getString("eventId")),null);
                        upload.put("eventId",row.getString("eventId"));upload.put("mediaId",row.getString("id"));
                    }
                    merged.add(row);
                }
                if("media".equals(key)) for(Object raw:old) {
                    JSONObject row=(JSONObject)raw;
                    if(migratedPhoto(row) && WearableModel.find(next,key,row.getString("id"))==null)
                        throw AdminQueryService.fail(409,"SNAPSHOT_READ_ONLY","不能通过快照删除事件照片");
                }
                current.put(key,merged);
            }
            current.put("clock",next.get("clock"));current.put("seq",next.getIntValue("seq"));
            WearableModel.rows(current,"audit").add(WearableModel.object("id","A-"+java.util.UUID.randomUUID(),"time",java.time.Instant.now().toString(),"text","保存未迁移业务","actorId",ctx.id(),"actorName",ctx.name()));
            return true;
        });
    }

    private static boolean migratedPhoto(JSONObject row) {
        return row!=null && ("核验上传".equals(row.getString("source")) || "现场补充".equals(row.getString("source")) || row.getString("purpose")!=null);
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
        if (state != null && readable(state)) { GuardianEvents.normalize(state); return; }
        try {
            if (Files.exists(file)) {
                JSONObject saved = JSON.parseObject(readBytes(Files.readAllBytes(file)));
                if (readable(saved)) {
                    state = saved;
                    if (GuardianEvents.normalize(state)) persist();
                    return;
                }
            }
            state = JSON.parseObject(readStream(new ClassPathResource("guardian-seed.json").getInputStream()));
            GuardianEvents.normalize(state);
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
            Path temporary = file.resolveSibling(file.getFileName() + ".tmp");
            Files.write(temporary, state.toJSONString().getBytes(StandardCharsets.UTF_8));
            try { Files.move(temporary, file, java.nio.file.StandardCopyOption.ATOMIC_MOVE, java.nio.file.StandardCopyOption.REPLACE_EXISTING); }
            catch (java.nio.file.AtomicMoveNotSupportedException unsupported) { Files.move(temporary, file, java.nio.file.StandardCopyOption.REPLACE_EXISTING); }
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
