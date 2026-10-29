package com.ruoyi.melhat.direct;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONObject;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import java.nio.file.*;
import java.nio.channels.FileChannel;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.function.Function;

/** Durable private command/account journal. Deliberately separate from editable Guardian snapshots. */
@Component
public class HelmetMediaStore {
    private final Path file;
    private final com.ruoyi.guardian.WearableBusinessStore business;
    private long durableRevision;
    private JSONObject state;
    @org.springframework.beans.factory.annotation.Autowired
    public HelmetMediaStore(@Value("${melhat.helmet-media.store:/data/helmet-media-private.json}") String path,
            @Value("${ruoyi.profile:/data/uploadPath}") String publicDirectory,
            com.ruoyi.guardian.WearableBusinessStore business) {
        this.file = Paths.get(path); this.business = business;
        if(file.toAbsolutePath().normalize().startsWith(Paths.get(publicDirectory).toAbsolutePath().normalize()))
            throw new IllegalArgumentException("媒体凭据记录必须保存在静态文件目录之外");
    }
    public HelmetMediaStore(String path, String publicDirectory) { this(path,publicDirectory,null); }
    public HelmetMediaStore(String path) { file = Paths.get(path); business = null; }
    public JSONObject snapshot() { synchronized(com.ruoyi.guardian.WearableBusinessStore.transactionLock()) { ensure(); return JSON.parseObject(state.toJSONString()); } }
    public <T> T update(Function<JSONObject,T> edit) {
        synchronized(com.ruoyi.guardian.WearableBusinessStore.transactionLock()) {
        ensure(); JSONObject next = JSON.parseObject(state.toJSONString()); T result = edit.apply(next);
        if (business != null) {
            long revision = business.save("media",durableRevision,next,null);
            state=next;durableRevision=revision;return result;
        }
        try {
            Files.createDirectories(file.toAbsolutePath().getParent());
            Path temp = Files.createTempFile(file.toAbsolutePath().getParent(), ".helmet-media-", ".tmp");
            try {
                try { Files.setPosixFilePermissions(temp, java.nio.file.attribute.PosixFilePermissions.fromString("rw-------")); }
                catch (UnsupportedOperationException ignored) { }
                try (FileChannel channel = FileChannel.open(temp, StandardOpenOption.WRITE, StandardOpenOption.TRUNCATE_EXISTING)) {
                    ByteBuffer buffer = ByteBuffer.wrap(next.toJSONString().getBytes(StandardCharsets.UTF_8));
                    while (buffer.hasRemaining()) channel.write(buffer); channel.force(true);
                }
                Files.move(temp, file, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
            } finally { Files.deleteIfExists(temp); }
            state = next; return result;
        } catch (Exception error) { throw new IllegalStateException("设备操作记录保存失败，未确认操作结果", error); }
        }
    }
    private void ensure() {
        if (business != null) {
            com.ruoyi.guardian.WearableBusinessStore.Snapshot loaded=business.load("media",file,JSONObject::new);
            state=loaded.state;durableRevision=loaded.revision;return;
        }
        if (state != null) return;
        try {
            state = Files.exists(file) ? JSON.parseObject(new String(Files.readAllBytes(file), StandardCharsets.UTF_8)) : new JSONObject();
            if (state == null) throw new IllegalStateException("empty journal");
        } catch (Exception error) { throw new IllegalStateException("设备操作记录无法读取，禁止覆盖原始记录", error); }
    }
}
