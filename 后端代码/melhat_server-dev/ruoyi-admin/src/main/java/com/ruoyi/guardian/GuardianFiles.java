package com.ruoyi.guardian;

import org.springframework.stereotype.Component;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.jdbc.core.JdbcTemplate;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.Locale;
import java.util.regex.Pattern;
import java.util.UUID;
import java.security.MessageDigest;
import java.nio.channels.FileChannel;
import java.nio.ByteBuffer;
import java.nio.file.StandardOpenOption;
import java.nio.file.LinkOption;
import java.nio.charset.StandardCharsets;

@Component
public class GuardianFiles {
    public static final class Stored {
        public final byte[] bytes;
        public final String type;

        public Stored(byte[] bytes, String type) {
            this.bytes = bytes;
            this.type = type;
        }
    }

    static final int MAX_BYTES = 10 * 1024 * 1024;
    private static final Pattern ID = Pattern.compile("^(upload|capture)-[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$");

    private final Object lock = new Object();
    private final Path root;
    private final GuardianFileCatalog catalog;
    private final byte[] storeMarker;

    public GuardianFiles() { this(storeRoot(),null); }

    @Autowired
    public GuardianFiles(@Value("${melhat.files.root:}") String configuredRoot,
                         ObjectProvider<JdbcTemplate> jdbc,
                         @Value("${melhat.cluster.enabled:false}") boolean cluster,
                         @Value("${melhat.files.store-id:${MELHAT_FILES_STORE_ID:}}") String storeId) {
        if(cluster && configuredRoot.trim().isEmpty()) throw new IllegalStateException("Cluster requires melhat.files.root mounted on shared storage");
        if(cluster && storeId.trim().isEmpty()) throw new IllegalStateException("Cluster requires melhat.files.store-id");
        this.root=(configuredRoot.trim().isEmpty()?storeRoot():Paths.get(configuredRoot)).toAbsolutePath().normalize();
        JdbcTemplate database=jdbc.getIfAvailable();
        if(cluster && database==null) throw new IllegalStateException("Cluster file publication requires the shared database");
        this.catalog=database==null?null:new GuardianFileCatalog(database);
        this.storeMarker=cluster?markerBytes(storeId):null;
    }

    GuardianFiles(Path root,GuardianFileCatalog catalog) {this(root,catalog,null);}

    GuardianFiles(Path root,GuardianFileCatalog catalog,String storeId) {
        this.root=root.toAbsolutePath().normalize();
        this.catalog=catalog;
        this.storeMarker=storeId==null?null:markerBytes(storeId);
    }

    public void save(String id, String contentType, InputStream body) {
        prepare(id,contentType,body,false).run();
    }

    Runnable prepareCreate(String id, String contentType, InputStream body) {
        return prepare(id,contentType,body,true);
    }

    private Runnable prepare(String id,String contentType,InputStream body,boolean createOnly) {
        if (!ID.matcher(id == null ? "" : id).matches()) throw new GuardianRejected("照片保存失败，请检查磁盘空间");
        byte[] bytes = readLimited(body);
        String sniffed = sniff(bytes);
        String declared = normalize(contentType);
        if (sniffed == null || !sniffed.equals(declared)) throw new GuardianRejected("仅支持 JPG、PNG 图片");
        return ()->publish(id,bytes,sniffed,createOnly);
    }

    private void publish(String id,byte[] bytes,String sniffed,boolean createOnly) {
        synchronized (lock) {
            try {
                prepareRoot();
                String ext = "image/png".equals(sniffed) ? ".png" : ".jpg";
                String name=id+"-"+UUID.randomUUID()+ext;
                Path temp=inside(name+".tmp");
                try {
                    try(FileChannel channel=FileChannel.open(temp,StandardOpenOption.CREATE_NEW,StandardOpenOption.WRITE)) {
                        ByteBuffer buffer=ByteBuffer.wrap(bytes);
                        while(buffer.hasRemaining())channel.write(buffer);
                        channel.force(true);
                    }
                    if(catalog!=null) {
                        GuardianFileCatalog.Entry entry=new GuardianFileCatalog.Entry(name,sniffed,sha256(bytes),bytes.length);
                        catalog.publish(id,entry,()->{
                            try {
                                verifyMount();
                                if(createOnly) requireNoLegacy(id);
                                move(temp,inside(name));
                                verifyMount();
                            }
                            catch(IOException failure){throw new GuardianRejected("照片发布失败，请检查共享目录");}
                        },createOnly);
                    } else {
                        if(createOnly) requireNoLegacy(id);
                        move(temp,inside(id+ext));
                        if(!createOnly) Files.deleteIfExists(inside(id+("image/png".equals(sniffed)?".jpg":".png")));
                    }
                } finally {Files.deleteIfExists(temp);}
            } catch (AdminQueryService.QueryFailed | GuardianRejected error) {
                throw error;
            } catch (IOException | RuntimeException error) {
                throw new GuardianRejected("照片保存失败，请检查磁盘空间");
            }
        }
    }

    public Stored read(String id) {
        if (!ID.matcher(id == null ? "" : id).matches()) return null;
        synchronized (lock) {
            try {
                verifyMount();
                if(catalog!=null) {
                    GuardianFileCatalog.Entry entry=catalog.find(id);
                    if(entry!=null) {
                        Path file=inside(entry.name);
                        if(!Files.isRegularFile(file,LinkOption.NOFOLLOW_LINKS)||Files.size(file)>MAX_BYTES)
                            throw new GuardianRejected("照片文件缺失或无效");
                        byte[] bytes=Files.readAllBytes(file);
                        if(bytes.length!=entry.length||!sha256(bytes).equals(entry.sha256)||!entry.type.equals(sniff(bytes)))
                            throw new GuardianRejected("照片校验失败");
                        return new Stored(bytes,entry.type);
                    }
                }
                Path png = inside(id + ".png");
                if (Files.isRegularFile(png,LinkOption.NOFOLLOW_LINKS)) return legacy(png,"image/png");
                Path jpeg = inside(id + ".jpg");
                if (Files.isRegularFile(jpeg,LinkOption.NOFOLLOW_LINKS)) return legacy(jpeg,"image/jpeg");
                return null;
            } catch (IOException | RuntimeException error) {
                throw new GuardianRejected("照片读取失败");
            }
        }
    }

    /** Tests the same create/flush/rename operations used by uploads. */
    public boolean storageReady() {
        String name=".readiness-"+UUID.randomUUID();
        Path from=inside(name+".tmp"),to=inside(name);
        try {
            prepareRoot();
            try(FileChannel channel=FileChannel.open(from,StandardOpenOption.CREATE_NEW,StandardOpenOption.WRITE)) {
                channel.write(ByteBuffer.wrap(new byte[]{1}));channel.force(true);
            }
            verifyMount();
            move(from,to);
            verifyMount();
            return Files.size(to)==1;
        } catch(IOException | RuntimeException error) {return false;}
        finally {try {Files.deleteIfExists(from);Files.deleteIfExists(to);}catch(IOException ignored){/* probe failed */}}
    }

    private void prepareRoot() throws IOException {
        if(storeMarker==null) Files.createDirectories(root);
        else verifyMount();
    }

    private void verifyMount() throws IOException {
        if(storeMarker==null) return;
        Path marker=inside(".wearable-store-id");
        if(!Files.isDirectory(root,LinkOption.NOFOLLOW_LINKS) || !Files.isRegularFile(marker,LinkOption.NOFOLLOW_LINKS))
            throw new IOException("Shared storage marker missing or invalid");
        try(InputStream input=Files.newInputStream(marker,LinkOption.NOFOLLOW_LINKS)) {
            for(byte expected:storeMarker) {
                if(input.read()!=(expected & 0xff)) throw new IOException("Shared storage marker mismatch");
            }
            if(input.read()!=-1) throw new IOException("Shared storage marker mismatch");
        }
    }

    private static byte[] markerBytes(String storeId) {
        return (storeId.trim()+"\n").getBytes(StandardCharsets.UTF_8);
    }

    private void requireNoLegacy(String id) {
        if(Files.exists(inside(id+".png"),LinkOption.NOFOLLOW_LINKS)
                || Files.exists(inside(id+".jpg"),LinkOption.NOFOLLOW_LINKS))
            throw AdminQueryService.fail(409,"FILE_EXISTS","照片编号已使用，请使用新编号");
    }

    private Stored legacy(Path file,String type) throws IOException {
        if(Files.size(file)>MAX_BYTES)throw new GuardianRejected("照片文件无效");
        byte[] bytes=Files.readAllBytes(file);
        if(!type.equals(sniff(bytes)))throw new GuardianRejected("照片校验失败");
        return new Stored(bytes,type);
    }

    private static String sha256(byte[] bytes) {
        try {StringBuilder out=new StringBuilder();for(byte b:MessageDigest.getInstance("SHA-256").digest(bytes))out.append(String.format("%02x",b&255));return out.toString();}
        catch(java.security.NoSuchAlgorithmException impossible){throw new IllegalStateException(impossible);}
    }

    private byte[] readLimited(InputStream body) {
        try {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buffer = new byte[8192];
            int total = 0;
            int read;
            while ((read = body.read(buffer)) >= 0) {
                total += read;
                if (total > MAX_BYTES) throw new GuardianRejected("图片不能超过 10MB");
                out.write(buffer, 0, read);
            }
            return out.toByteArray();
        } catch (GuardianRejected error) {
            throw error;
        } catch (IOException error) {
            throw new GuardianRejected("照片保存失败，请检查磁盘空间");
        }
    }

    private Path inside(String name) {
        Path path = root.resolve(name).normalize();
        if (!path.startsWith(root)) throw new GuardianRejected("照片保存失败，请检查磁盘空间");
        return path;
    }

    void move(Path temp, Path target) throws IOException {
        try {
            Files.move(temp, target, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
        } catch (AtomicMoveNotSupportedException error) {
            throw new IOException("Shared storage must support atomic rename",error);
        }
    }

    private static String normalize(String contentType) {
        if (contentType == null) return null;
        String value = contentType.toLowerCase(Locale.ROOT);
        int split = value.indexOf(';');
        if (split >= 0) value = value.substring(0, split);
        value = value.trim();
        if ("image/jpg".equals(value) || "image/pjpeg".equals(value)) return "image/jpeg";
        if ("image/jpeg".equals(value) || "image/png".equals(value)) return value;
        return null;
    }

    private static String sniff(byte[] bytes) {
        if (bytes.length >= 3 && (bytes[0] & 0xFF) == 0xFF && (bytes[1] & 0xFF) == 0xD8 && (bytes[2] & 0xFF) == 0xFF) return "image/jpeg";
        if (bytes.length >= 8
                && (bytes[0] & 0xFF) == 0x89
                && bytes[1] == 0x50
                && bytes[2] == 0x4E
                && bytes[3] == 0x47
                && bytes[4] == 0x0D
                && bytes[5] == 0x0A
                && bytes[6] == 0x1A
                && bytes[7] == 0x0A) return "image/png";
        return null;
    }

    private static Path storeRoot() {
        Path data = Paths.get("/data");
        Path root = Files.isDirectory(data) ? data.resolve("guardian-files") : Paths.get("data", "guardian-files");
        return root.toAbsolutePath().normalize();
    }
}
