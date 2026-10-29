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

    private final Object lock = WearableBusinessStore.transactionLock();
    private final Path file = storeFile();
    private final GuardianHatArchive hats;
    private final WearableBusinessStore business;
    private long durableRevision;
    private JSONObject state;
    private boolean hatsMirrored;
    @org.springframework.beans.factory.annotation.Value("${melhat.demo-mode:false}") private boolean demoMode;
    @org.springframework.beans.factory.annotation.Autowired(required=false) private AdminLedgerStore ledger;
    @org.springframework.beans.factory.annotation.Autowired(required=false)
    private org.springframework.beans.factory.ObjectProvider<com.ruoyi.helmet.service.DirectHelmetAccess> directAccess;
    @org.springframework.beans.factory.annotation.Autowired(required=false)
    private org.springframework.beans.factory.ObjectProvider<DirectBeltAccess> directBeltAccess;
    @org.springframework.beans.factory.annotation.Autowired(required=false) private WearableMaintenance maintenance;

    private void projectPlatform() {
        JSONObject next=JSON.parseObject(state.toJSONString());
        if (ledger != null) PlatformProjection.apply(next, ledger.read());
        DirectHelmetProjection.apply(next, directAccess == null ? null : directAccess.getIfAvailable());
        DirectBeltProjection.apply(next, directBeltAccess == null ? null : directBeltAccess.getIfAvailable());
        PersonLocationProjection.apply(next);
        if(!next.toJSONString().equals(state.toJSONString())) {
            next.put("seq",state.getIntValue("seq")+1);
            commit(next);
        }
    }

    public GuardianStore(GuardianHatArchive hats) {
        this(hats, null);
    }

    @org.springframework.beans.factory.annotation.Autowired
    public GuardianStore(GuardianHatArchive hats, WearableBusinessStore business) {
        this.hats = hats;
        this.business = business;
    }

    public boolean isOperational(JSONObject row) { return demoMode || !GuardianDemoData.confirmed(row); }

    public JSONObject snapshot() {
        synchronized (lock) {
            ensure();
            if(maintenance!=null&&maintenance.paused())return JSON.parseObject(state.toJSONString());
            projectPlatform();
            mirrorHats();
            return JSON.parseObject(state.toJSONString());
        }
    }

    public void replace(JSONObject next) {
        validate(next);
        synchronized (lock) {
            if (business != null) ensure();
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
            validate(next);
            commit(next);
        }
    }

    public void update(Edit edit) {
        synchronized (lock) {
            if(maintenance!=null&&maintenance.paused())throw new IllegalStateException("业务正在维护，设备上报已进入持久接收队列");
            ensure();
            projectPlatform();
            JSONObject next = JSON.parseObject(state.toJSONString());
            if (edit == null || !edit.apply(next)) return;
            validate(next);
            commit(next);
        }
    }

    public void replaceScoped(JSONObject received, int expectedSeq, GuardianAccess.Context ctx) {
        // Spring's JSON reader may use Double where the durable parser uses BigDecimal.
        // Compare the same wire representation before enforcing the read-only collections.
        JSONObject next = JSON.parseObject(received.toJSONString());
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

    private void validate(JSONObject next) {
        // Classify exact legacy seeds before checking live business conflicts, including full imports.
        GuardianEvents.normalize(next);
        GuardianValidator.check(next, demoMode);
    }

    private void commit(JSONObject next) {
        GuardianEvents.normalize(next);
        if (business != null) {
            // The SQL event/projection write and legacy helmet archive participate in one transaction.
            long revision = business.save("guardian", durableRevision, next, () -> hats.sync(next));
            state = next; durableRevision = revision; hatsMirrored = true;
            return;
        }
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
        if (business != null) {
            // Always reload SQL revision: an enclosing report transaction may have rolled back
            // after save() returned, or another process may have committed a newer version.
            WearableBusinessStore.Snapshot loaded = business.load("guardian", file, this::initialState);
            state = loaded.state; durableRevision = loaded.revision;
            if (!readable(state)) throw new IllegalStateException("数据库监护数据格式无效，禁止回填示例");
            if (GuardianEvents.normalize(state)) durableRevision = business.save("guardian", durableRevision, state, null);
            return;
        }
        if (state != null && readable(state)) { GuardianEvents.normalize(state); return; }
        try {
            if (Files.exists(file)) {
                JSONObject saved = JSON.parseObject(readBytes(Files.readAllBytes(file)));
                if (readable(saved)) {
                    state = saved;
                    if (GuardianEvents.normalize(state)) persist();
                    return;
                }
                throw new IllegalStateException("历史业务文件格式无效，禁止回填示例");
            }
            state = initialState();
            GuardianEvents.normalize(state);
            persist();
        } catch (Exception e) {
            throw new IllegalStateException("监护数据不可用", e);
        }
    }

    private static boolean readable(JSONObject value) {
        return value != null && value.getIntValue("version") == 1 && value.getJSONArray("stations") != null;
    }

    private JSONObject initialState() {
        if (demoMode) {
            try { return JSON.parseObject(readStream(new ClassPathResource("guardian-seed.json").getInputStream())); }
            catch (Exception error) { throw new IllegalStateException("演示初始数据不可用", error); }
        }
        JSONObject empty = new JSONObject(); empty.put("version", 1); empty.put("seq", 0); empty.put("clock", 0);
        for (String key : new String[]{"stations","people","devices","bindings","locations","vitals","works","events","media","groups","fences","fenceRecords","calls","broadcasts","audit"})
            empty.put(key, new com.alibaba.fastjson2.JSONArray());
        empty.put("assistance",new JSONObject()); empty.put("eventOperations",new JSONObject()); empty.put("uploads",new JSONObject());
        return empty;
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
