package com.ruoyi.guardian;

import org.springframework.stereotype.Component;

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
    private final Path root = storeRoot();

    public void save(String id, String contentType, InputStream body) {
        if (!ID.matcher(id == null ? "" : id).matches()) throw new GuardianRejected("照片保存失败，请检查磁盘空间");
        byte[] bytes = readLimited(body);
        String sniffed = sniff(bytes);
        String declared = normalize(contentType);
        if (sniffed == null || !sniffed.equals(declared)) throw new GuardianRejected("仅支持 JPG、PNG 图片");
        synchronized (lock) {
            try {
                Files.createDirectories(root);
                String ext = "image/png".equals(sniffed) ? ".png" : ".jpg";
                Path target = inside(id + ext);
                Path other = inside(id + ("image/png".equals(sniffed) ? ".jpg" : ".png"));
                Path temp = inside(id + ext + ".tmp");
                Files.write(temp, bytes);
                move(temp, target);
                if (Files.exists(other)) Files.delete(other);
            } catch (IOException error) {
                throw new GuardianRejected("照片保存失败，请检查磁盘空间");
            }
        }
    }

    public Stored read(String id) {
        if (!ID.matcher(id == null ? "" : id).matches()) return null;
        synchronized (lock) {
            try {
                Path png = inside(id + ".png");
                if (Files.isRegularFile(png)) return new Stored(Files.readAllBytes(png), "image/png");
                Path jpeg = inside(id + ".jpg");
                if (Files.isRegularFile(jpeg)) return new Stored(Files.readAllBytes(jpeg), "image/jpeg");
                return null;
            } catch (IOException error) {
                throw new GuardianRejected("照片读取失败");
            }
        }
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

    private static void move(Path temp, Path target) throws IOException {
        try {
            Files.move(temp, target, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
        } catch (AtomicMoveNotSupportedException error) {
            Files.move(temp, target, StandardCopyOption.REPLACE_EXISTING);
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
