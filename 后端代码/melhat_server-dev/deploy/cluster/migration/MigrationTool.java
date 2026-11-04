import com.fasterxml.jackson.core.JsonParser;
import com.fasterxml.jackson.databind.*;
import com.fasterxml.jackson.databind.node.*;
import com.ruoyi.common.database.DatabaseDialect;
import com.ruoyi.database.SchemaLifecycle;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.SingleConnectionDataSource;

import java.io.*;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.sql.*;
import java.time.*;
import java.util.*;
import java.util.regex.*;

/** Offline, fail-closed transfer. Run through migrate.py with the tested application jar. */
public class MigrationTool implements AutoCloseable {
    static final ObjectMapper JSON = new ObjectMapper()
        .enable(JsonParser.Feature.STRICT_DUPLICATE_DETECTION)
        .enable(DeserializationFeature.USE_BIG_DECIMAL_FOR_FLOATS)
        .enable(DeserializationFeature.FAIL_ON_TRAILING_TOKENS);
    static final Set<String> INTERNAL = Set.of("wearable_schema_history", "wearable_schema_step", "wearable_schema_lock");
    static final Set<String> ARCHIVE = Set.of("wearable_cluster_control", "wearable_cluster_node", "wearable_device_owner",
        "wearable_cluster_work", "wearable_cluster_operation", "qrtz_fired_triggers", "qrtz_scheduler_state", "qrtz_locks");
    static final Pattern FILE_ID = Pattern.compile("(?:upload|capture)-[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}");
    static final int MAX_LINE = 32 * 1024 * 1024;
    static final int MAX_CELL = 16 * 1024 * 1024;
    static String context="initial";
    interface Checkpoint { void at(String stage,String table)throws Exception; }
    // Package-local fault barrier used by the two-process crash test. No CLI/environment switch enables it.
    static Checkpoint checkpoint=(stage,table)->{};
    final ObjectNode config;
    final Path shared;
    final DatabaseDialect dialect;
    final Connection db;
    final JdbcTemplate jdbc;
    final String schema;
    final SortedMap<String, Table> tables = new TreeMap<>();
    final Set<String> expected = new TreeSet<>();
    final Set<String> fileIds = new TreeSet<>();
    final Set<String> localReferences = new TreeSet<>();
    final Set<String> externalReferences = new TreeSet<>();
    final byte[] mediaKey;
    record Column(String name, String actual, int type, String kind, boolean identity) {}
    record Table(String name, String actual, List<Column> columns, List<String> primaryKey) {}

    public static void main(String[] args) {
        try {
            if (args.length != 2 || !Set.of("export", "import", "reconcile", "resume").contains(args[0]))
                throw new IllegalArgumentException("Expected transfer command and bundle directory");
            try (MigrationTool tool = new MigrationTool()) {
                Path bundle = Path.of(args[1]).toAbsolutePath().normalize();
                switch (args[0]) {
                    case "export" -> tool.exportBundle(bundle);
                    case "import" -> tool.importBundle(bundle, false);
                    case "resume" -> tool.importBundle(bundle, true);
                    case "reconcile" -> tool.reconcileBundle(bundle);
                }
            }
            System.out.println("PASS: " + args[0] + " completed with content, identity and file checks.");
        } catch (Exception failure) {
            // Vendor exceptions can contain SQL, data or credentials. Only controlled error codes leave the process.
            String code = failure instanceof TransferFailure ? failure.getMessage() : "TRANSFER_FAILED";
            System.err.println("FAIL: " + code + ". Preserve the private journal and inspect the target before retrying.");
            if(context.matches("[A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)?"))System.err.println("CONTEXT: "+context);
            System.exit(2);
        }
    }

    MigrationTool() throws Exception {
        this((ObjectNode) JSON.readTree(Files.readString(Path.of(required("MIGRATION_DB_CONFIG")), StandardCharsets.UTF_8)));
    }
    MigrationTool(ObjectNode config) throws Exception {
        this.config = config;
        dialect = DatabaseDialect.valueOf(text(config, "product").toUpperCase(Locale.ROOT));
        require(dialect != DatabaseDialect.H2, "REAL_DATABASE_REQUIRED");
        schema = text(config, "schema"); DatabaseDialect.identifier(schema);
        shared = Path.of(text(config, "sharedRoot")).toAbsolutePath().normalize();
        require(shared.getParent()!=null&&!Files.isSymbolicLink(shared) && Files.isDirectory(shared, LinkOption.NOFOLLOW_LINKS), "SHARED_DIRECTORY_REQUIRED");
        mediaKey=Base64.getDecoder().decode(backendEnvironment().getOrDefault("MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY",""));
        require(mediaKey.length==32,"MEDIA_KEY_INVALID");
        Class.forName(dialect == DatabaseDialect.DM8 ? "dm.jdbc.driver.DmDriver" : "com.mysql.cj.jdbc.Driver");
        DriverManager.setLoginTimeout(10);
        db = DriverManager.getConnection(text(config, "url"), text(config, "username"), text(config, "password"));
        dialect.requireProduct(db.getMetaData().getDatabaseProductName());
        require(schema.equalsIgnoreCase(dialect == DatabaseDialect.MYSQL ? db.getCatalog() : db.getSchema()), "SCHEMA_IDENTITY_MISMATCH");
        jdbc = new JdbcTemplate(new SingleConnectionDataSource(db, true)); jdbc.setQueryTimeout(30);
        if (dialect == DatabaseDialect.MYSQL) {
            execute("SET SESSION time_zone = '+00:00'");
            execute("SET SESSION information_schema_stats_expiry=0");
            execute("SET SESSION sql_mode=CONCAT(@@sql_mode,',NO_AUTO_VALUE_ON_ZERO,STRICT_ALL_TABLES')");
            require(jdbc.queryForObject("SELECT @@auto_increment_increment", Integer.class) == 1
                && jdbc.queryForObject("SELECT @@auto_increment_offset", Integer.class) == 1, "IDENTITY_STEP_UNSUPPORTED");
        }
        new SchemaLifecycle(jdbc).validate(SchemaLifecycle.all(dialect));
        List<String> migrations = new ArrayList<>(List.of("00000000_base")); migrations.addAll(List.of(SchemaLifecycle.BUSINESS));
        for (String migration : migrations) {
            String resource = "db/" + dialect.name().toLowerCase(Locale.ROOT) + "/" + migration + ".sql";
            try (InputStream stream = SchemaLifecycle.class.getClassLoader().getResourceAsStream(resource)) {
                require(stream != null, "SCHEMA_RESOURCE_MISSING");
                Matcher match = Pattern.compile("(?i)CREATE\\s+TABLE(?:\\s+IF\\s+NOT\\s+EXISTS)?\\s+([A-Za-z_][A-Za-z0-9_]*)")
                    .matcher(new String(stream.readAllBytes(), StandardCharsets.UTF_8));
                while (match.find()) expected.add(match.group(1).toLowerCase(Locale.ROOT));
            }
        }
        loadMetadata();
    }
    public void close() throws SQLException { db.close(); }

    void loadMetadata() throws Exception {
        DatabaseMetaData metadata = db.getMetaData();
        String catalog = dialect == DatabaseDialect.MYSQL ? schema : null;
        String owner = dialect == DatabaseDialect.DM8 ? schema.toUpperCase(Locale.ROOT) : null;
        try (ResultSet rows = metadata.getTables(catalog, owner, "%", new String[]{"TABLE"})) {
            while (rows.next()) {
                String actual = rows.getString("TABLE_NAME"); DatabaseDialect.identifier(actual);
                String name = actual.toLowerCase(Locale.ROOT);
                if (INTERNAL.contains(name)) continue;
                if (!expected.contains(name)) {
                    require(count(actual) == 0, "UNEXPECTED_POPULATED_TABLE");
                    continue;
                }
                List<Column> columns = new ArrayList<>();
                try (ResultSet fields = metadata.getColumns(catalog, owner, actual, "%")) {
                    while (fields.next()) {
                        String field = fields.getString("COLUMN_NAME"); DatabaseDialect.identifier(field);
                        int type = fields.getInt("DATA_TYPE");
                        String normalized=field.toLowerCase(Locale.ROOT);
                        columns.add(new Column(normalized, field, type, jsonColumn(name,normalized)?"text":kind(type), "YES".equalsIgnoreCase(fields.getString("IS_AUTOINCREMENT"))));
                    }
                }
                TreeMap<Integer, String> keys = new TreeMap<>();
                try (ResultSet primary = metadata.getPrimaryKeys(catalog, owner, actual)) {
                    while (primary.next()) keys.put(primary.getInt("KEY_SEQ"), primary.getString("COLUMN_NAME").toLowerCase(Locale.ROOT));
                }
                require(!columns.isEmpty() && !keys.isEmpty(), "TABLE_METADATA_OR_PRIMARY_KEY_MISSING");
                require(columns.stream().filter(Column::identity).count() <= 1, "MULTIPLE_IDENTITIES_UNSUPPORTED");
                tables.put(name, new Table(name, actual, columns, new ArrayList<>(keys.values())));
            }
        }
        require(tables.keySet().equals(expected), "EXPECTED_TABLE_MISSING");
    }

    static String kind(int type) {
        return switch (type) {
            case Types.BIT, Types.BOOLEAN, Types.TINYINT, Types.SMALLINT, Types.INTEGER, Types.BIGINT,
                 Types.DECIMAL, Types.NUMERIC, Types.FLOAT, Types.REAL, Types.DOUBLE -> "number";
            case Types.CHAR, Types.VARCHAR, Types.LONGVARCHAR, Types.NCHAR, Types.NVARCHAR, Types.LONGNVARCHAR,
                 Types.CLOB, Types.NCLOB -> "text";
            case Types.BINARY, Types.VARBINARY, Types.LONGVARBINARY, Types.BLOB -> "binary";
            case Types.DATE -> "date";
            case Types.TIME -> "time";
            case Types.TIMESTAMP -> "timestamp";
            default -> throw new TransferFailure("UNSUPPORTED_COLUMN_TYPE");
        };
    }
    String quote(String identifier) { DatabaseDialect.identifier(identifier); return (dialect == DatabaseDialect.MYSQL ? "`" : "\"") + identifier + (dialect == DatabaseDialect.MYSQL ? "`" : "\""); }
    void execute(String sql) throws SQLException { try (Statement s = db.createStatement()) { s.setQueryTimeout(30); s.execute(sql); } }
    long count(String table) { return jdbc.queryForObject("SELECT COUNT(*) FROM " + quote(table), Long.class); }
    String qTable(String name) { return quote(tables.get(name).actual); }

    void requireOffline(boolean emptyTarget) throws Exception {
        String evidence = required("MIGRATION_OFFLINE_EVIDENCE");
        ObjectNode offline = (ObjectNode) JSON.readTree(Files.readString(Path.of(evidence)));
        require(offline.path("verifiedStopped").asBoolean(false) && text(offline, "schema").equals(schema), "OFFLINE_EVIDENCE_REQUIRED");
        require(offline.path("expiresAt").asLong() > System.currentTimeMillis(), "OFFLINE_EVIDENCE_EXPIRED");
        Set<String> nodeIds = new HashSet<>(); offline.withArray("nodeIds").forEach(v -> nodeIds.add(v.asText()));
        List<String> recordedNodes = jdbc.query("SELECT node_id FROM wearable_cluster_node", (r, n) -> r.getString(1));
        require(nodeIds.containsAll(recordedNodes), "OFFLINE_NODE_INVENTORY_INCOMPLETE");
        long now = dialect.dbTimeMillis(jdbc);
        require(jdbc.queryForObject("SELECT COUNT(*) FROM wearable_cluster_node WHERE lease_until>?", Long.class, now) == 0, "APPLICATION_NODE_STILL_ACTIVE");
        if (tables.containsKey("wearable_cluster_operation"))
            require(jdbc.queryForObject("SELECT COUNT(*) FROM wearable_cluster_operation WHERE state='ACTIVE'", Long.class) == 0, "UNFINISHED_OPERATION");
        if (tables.containsKey("wearable_media_effect"))
            require(jdbc.queryForObject("SELECT COUNT(*) FROM wearable_media_effect WHERE state IN ('IN_FLIGHT','UNKNOWN')", Long.class) == 0, "UNRESOLVED_MEDIA_EFFECT");
        require(jdbc.queryForObject("SELECT COUNT(*) FROM fuda_push_outbox WHERE status='IN_FLIGHT'", Long.class) == 0, "UNRESOLVED_PUSH_ATTEMPT");
        require(jdbc.queryForObject("SELECT COUNT(*) FROM wearable_transport_command WHERE delivery_status IN ('PREPARING','QUEUED','DISPATCHING','SENT')", Long.class) == 0, "UNRESOLVED_DEVICE_DELIVERY");
        List<String> modes = jdbc.query("SELECT mode FROM wearable_runtime_control WHERE control_key='global'", (r,n) -> r.getString(1));
        require(emptyTarget && modes.isEmpty() || modes.size() == 1 && "PAUSED".equals(modes.get(0)), "GLOBAL_PAUSE_REQUIRED");
    }
    void lockSnapshot() throws Exception {
        db.setAutoCommit(false);
        List<String> names = new ArrayList<>(); for (Table t : tables.values()) names.add(t.actual);
        names.addAll(INTERNAL); names.sort(String::compareTo);
        if (dialect == DatabaseDialect.MYSQL) execute("LOCK TABLES " + String.join(",", names.stream().map(n -> quote(n) + " READ").toList()));
        else for (String name : names) execute("LOCK TABLE " + quote(name) + " IN SHARE MODE NOWAIT");
    }
    void unlockSnapshot() throws SQLException {
        db.rollback();
        if (dialect == DatabaseDialect.MYSQL) execute("UNLOCK TABLES");
        db.setAutoCommit(true);
    }

    void exportBundle(Path bundle) throws Exception {
        require(!Files.exists(bundle, LinkOption.NOFOLLOW_LINKS), "NEW_BUNDLE_DIRECTORY_REQUIRED");
        requireOffline(false);
        createPrivateDirectory(bundle); createPrivateDirectory(bundle.resolve("tables")); createPrivateDirectory(bundle.resolve("files"));
        ObjectNode manifest = JSON.createObjectNode(); manifest.put("format", 1); manifest.put("state", "STARTED");
        manifest.put("snapshotId", UUID.randomUUID().toString()); manifest.put("sourceProduct", dialect.name());
        manifest.put("applicationSha256",required("MIGRATION_APPLICATION_SHA256"));
        manifest.put("sourceSchema", schema); manifest.put("createdAt", Instant.now().toString());
        manifest.set("continuity", continuity());
        writeJson(bundle.resolve("manifest.json"), manifest);
        lockSnapshot();
        try {
            requireOffline(false);
            ObjectNode descriptors = manifest.putObject("tables");
            for (Table t : tables.values()) descriptors.set(t.name, exportTable(t, bundle.resolve("tables").resolve(t.name + ".jsonl")));
            manifest.set("files", snapshotFiles(bundle.resolve("files")));
            validateReferences(manifest.path("files"));
            manifest.set("externalMediaReferences", JSON.valueToTree(externalReferences));
            manifest.set("configuration", archiveConfiguration(bundle));
            manifest.put("state", "COMPLETE"); manifest.put("completedAt", Instant.now().toString());
            writeJson(bundle.resolve("manifest.json"), manifest);
            Files.writeString(bundle.resolve("manifest.sha256"), sha(bundle.resolve("manifest.json")) + "\n", StandardOpenOption.CREATE_NEW);
        } finally { unlockSnapshot(); }
    }

    ObjectNode exportTable(Table t, Path output) throws Exception {
        List<Path> runs = new ArrayList<>(); List<String> rows = new ArrayList<>(); long buffered = 0, count = 0;
        ObjectNode descriptor = JSON.createObjectNode(); descriptor.put("policy", ARCHIVE.contains(t.name) ? "archive" : "restore");
        ArrayNode cols = descriptor.putArray("columns");
        for (Column c : t.columns) { ObjectNode col = cols.addObject(); col.put("name", c.name); col.put("kind", c.kind); col.put("identity", c.identity); }
        descriptor.set("primaryKey", JSON.valueToTree(t.primaryKey));
        Column identity = t.columns.stream().filter(Column::identity).findFirst().orElse(null);
        if (identity != null) descriptor.put("nextIdentity", nextIdentity(t, identity));
        try (Statement stmt = db.createStatement(ResultSet.TYPE_FORWARD_ONLY, ResultSet.CONCUR_READ_ONLY)) {
            stmt.setQueryTimeout(60); stmt.setFetchSize(dialect == DatabaseDialect.MYSQL ? Integer.MIN_VALUE : 500);
            try (ResultSet rs = stmt.executeQuery("SELECT " + String.join(",", t.columns.stream().map(c -> quote(c.actual)).toList()) + " FROM " + quote(t.actual))) {
                while (rs.next()) {
                    ArrayNode values = JSON.createArrayNode(), key = JSON.createArrayNode();
                    long rowCharacters=0;
                    for (int i = 0; i < t.columns.size(); i++) {
                        JsonNode cell=value(rs,i+1,t,t.columns.get(i));rowCharacters+=cell.isTextual()?cell.textValue().length():4;
                        require(rowCharacters<=MAX_LINE,"ROW_EXCEEDS_TRANSFER_LIMIT");values.add(cell);
                    }
                    validatePrivatePayloads(t,values);
                    for (String name : t.primaryKey) key.add(values.get(index(t, name)));
                    ObjectNode row = JSON.createObjectNode(); row.set("key", key); row.set("values", values); String line = canonical(row);
                    require(line.length() <= MAX_LINE, "ROW_EXCEEDS_TRANSFER_LIMIT"); rows.add(line); buffered += line.length(); count++;
                    if (rows.size() >= 4096 || buffered >= 16*1024*1024) { runs.add(writeRun(output, rows)); rows.clear(); buffered=0; }
                }
            }
        }
        if (!rows.isEmpty() || runs.isEmpty()) runs.add(writeRun(output, rows));
        mergeRuns(runs, output);
        descriptor.put("rows", count); descriptor.put("sha256", sha(output));
        return descriptor;
    }
    long nextIdentity(Table t, Column identity) {
        if (dialect == DatabaseDialect.MYSQL) {
            Long next = jdbc.queryForObject("SELECT AUTO_INCREMENT FROM information_schema.TABLES WHERE TABLE_SCHEMA=? AND TABLE_NAME=?", Long.class, schema, t.actual);
            require(next != null && next > 0, "IDENTITY_METADATA_MISSING"); return next;
        }
        String full = schema + "." + t.actual;
        require(jdbc.queryForObject("SELECT IDENT_INCR(?) FROM DUAL", Long.class, full) == 1, "IDENTITY_STEP_UNSUPPORTED");
        Long current = jdbc.queryForObject("SELECT IDENT_CURRENT(?) FROM DUAL", Long.class, full);
        require(current != null && current < Long.MAX_VALUE, "IDENTITY_EXHAUSTED"); return current+1;
    }
    JsonNode value(ResultSet rs, int ordinal, Table table, Column column) throws Exception {
        switch (column.kind) {
            case "number": {
                BigDecimal n;
                if (column.type == Types.BOOLEAN || column.type == Types.BIT) { boolean b=rs.getBoolean(ordinal); n=rs.wasNull()?null:BigDecimal.valueOf(b?1:0); }
                else n=rs.getBigDecimal(ordinal);
                return n==null?NullNode.instance:TextNode.valueOf(decimal(n));
            }
            case "binary": { byte[] bytes=readBytes(rs.getBinaryStream(ordinal)); return bytes==null?NullNode.instance:TextNode.valueOf(Base64.getEncoder().encodeToString(bytes)); }
            case "date": { java.sql.Date v=rs.getDate(ordinal); return v==null?NullNode.instance:TextNode.valueOf(v.toLocalDate().toString()); }
            case "time": { String v=rs.getString(ordinal); return v==null?NullNode.instance:TextNode.valueOf(LocalTime.parse(v).toString()); }
            case "timestamp": { Timestamp v=rs.getTimestamp(ordinal, Calendar.getInstance(TimeZone.getTimeZone("UTC"))); return v==null?NullNode.instance:TextNode.valueOf(v.toLocalDateTime().toString()); }
            default: {
                String v;
                if(column.type==Types.BLOB&&jsonColumn(table.name,column.name)){
                    byte[] bytes=readBytes(rs.getBinaryStream(ordinal));v=bytes==null?null:StandardCharsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(bytes)).toString();
                }else v=readCharacters(rs.getCharacterStream(ordinal));
                if(v==null)return NullNode.instance;
                if (jsonColumn(table.name, column.name) && !v.startsWith("enc:v1:")) {
                    JsonNode parsed;
                    try { parsed=JSON.readTree(v); require(parsed!=null,"INVALID_BUSINESS_JSON"); } catch(Exception e) { throw new TransferFailure("INVALID_BUSINESS_JSON"); }
                    collectFileIds(parsed); v=canonical(parsed);
                }
                if (table.name.equals("file_record") && column.name.equals("file_url") || table.name.equals("intercom_record") && column.name.equals("record_path")) collectReference(v);
                return TextNode.valueOf(v);
            }
        }
    }
    static boolean jsonColumn(String table, String column) {
        return column.equals("body") || column.equals("payload") && table.equals("demo_compat_record")
            || table.equals("helmet_event_group")&&column.equals("initial_body")
            || Set.of("wire_json", "context_json", "status_json", "summary_json").contains(column);
    }
    void validatePrivatePayloads(Table table,JsonNode values)throws Exception{
        for(int i=0;i<table.columns.size();i++){
            Column column=table.columns.get(i);JsonNode value=values.get(i);if(value==null||value.isNull()||!value.isTextual())continue;
            String stored=value.textValue();
            if(column.name.equals("body")&&stored.startsWith("enc:v1:")){
                String namespace=values.get(index(table,"namespace")).asText(),collection=values.get(index(table,"collection_key")).asText();
                require(namespace.equals("media")||Set.of("sharedCommunications","voiceSessions").contains(collection),"ENCRYPTED_BODY_CONTEXT_INVALID");
                String id=table.name.equals("wearable_business_document")?"$":values.get(index(table,"record_key")).asText();
                collectFileIds(decryptJson(stored.substring(7),namespace+"\n"+collection+"\n"+id));
            }else if(table.name.equals("wearable_media_effect")&&column.name.equals("response_json")){
                collectFileIds(decryptJson(stored,null));
            }
        }
    }
    JsonNode decryptJson(String stored,String aad)throws Exception{
        try{
            byte[] bytes=Base64.getDecoder().decode(stored);require(bytes.length>=28,"ENCRYPTED_PAYLOAD_INVALID");
            javax.crypto.Cipher cipher=javax.crypto.Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(javax.crypto.Cipher.DECRYPT_MODE,new javax.crypto.spec.SecretKeySpec(mediaKey,"AES"),new javax.crypto.spec.GCMParameterSpec(128,Arrays.copyOf(bytes,12)));
            if(aad!=null)cipher.updateAAD(aad.getBytes(StandardCharsets.UTF_8));
            JsonNode value=JSON.readTree(cipher.doFinal(Arrays.copyOfRange(bytes,12,bytes.length)));require(value!=null,"ENCRYPTED_PAYLOAD_INVALID");return value;
        }catch(Exception failure){throw new TransferFailure("ENCRYPTED_PAYLOAD_AUTHENTICATION_FAILED");}
    }
    static int index(Table t, String field) {
        for(int i=0;i<t.columns.size();i++) if(t.columns.get(i).name.equals(field)) return i;
        throw new TransferFailure("COLUMN_NOT_FOUND");
    }
    static String decimal(BigDecimal number) { return number.signum()==0?"0":number.stripTrailingZeros().toPlainString(); }
    static byte[] readBytes(InputStream input)throws Exception{
        if(input==null)return null;
        try(input;ByteArrayOutputStream output=new ByteArrayOutputStream()){
            byte[] buffer=new byte[65536];int n,total=0;while((n=input.read(buffer))!=-1){total+=n;require(total<=MAX_CELL,"CELL_EXCEEDS_TRANSFER_LIMIT");output.write(buffer,0,n);}return output.toByteArray();
        }
    }
    static String readCharacters(Reader input)throws Exception{
        if(input==null)return null;
        try(input){StringBuilder output=new StringBuilder();char[] buffer=new char[16384];int n;while((n=input.read(buffer))!=-1){require((long)output.length()+n<=MAX_CELL,"CELL_EXCEEDS_TRANSFER_LIMIT");output.append(buffer,0,n);}return output.toString();}
    }
    static String canonical(JsonNode node) throws Exception {
        if(node.isObject()) {
            ObjectNode sorted=JSON.createObjectNode(); TreeSet<String> keys=new TreeSet<>(); node.fieldNames().forEachRemaining(keys::add);
            for(String key:keys)sorted.set(key,JSON.readTree(canonical(node.get(key)))); return JSON.writeValueAsString(sorted);
        }
        if(node.isArray()) { ArrayNode result=JSON.createArrayNode(); for(JsonNode item:node)result.add(JSON.readTree(canonical(item))); return JSON.writeValueAsString(result); }
        if(node.isNumber())return decimal(node.decimalValue());
        return JSON.writeValueAsString(node);
    }
    static Path writeRun(Path output, List<String> rows) throws Exception {
        rows.sort(String::compareTo); Path run=Files.createTempFile(output.getParent(),".sort-",".jsonl");
        try(BufferedWriter writer=Files.newBufferedWriter(run,StandardCharsets.UTF_8)) { for(String row:rows){writer.write(row);writer.write('\n');} }
        return run;
    }
    static void mergeRuns(List<Path> runs, Path output) throws Exception {
        if(runs.size()>64){
            List<Path> next=new ArrayList<>();
            for(int i=0;i<runs.size();i+=64){Path intermediate=output.resolveSibling(".merge-"+UUID.randomUUID()+".jsonl");mergeRuns(runs.subList(i,Math.min(i+64,runs.size())),intermediate);next.add(intermediate);}
            mergeRuns(next,output);return;
        }
        record Head(String line, int reader) {}
        List<BufferedReader> readers=new ArrayList<>(); PriorityQueue<Head> queue=new PriorityQueue<>(Comparator.comparing(Head::line));
        try {
            for(Path run:runs) { BufferedReader reader=Files.newBufferedReader(run,StandardCharsets.UTF_8); readers.add(reader);String line=readLine(reader);if(line!=null)queue.add(new Head(line,readers.size()-1)); }
            try(BufferedWriter writer=Files.newBufferedWriter(output,StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW)) {
                while(!queue.isEmpty()) { Head head=queue.remove();writer.write(head.line);writer.write('\n');String line=readLine(readers.get(head.reader));if(line!=null)queue.add(new Head(line,head.reader)); }
            }
        } finally { for(BufferedReader reader:readers)reader.close();for(Path run:runs)Files.deleteIfExists(run); }
    }
    static String readLine(BufferedReader reader) throws IOException {
        StringBuilder result=new StringBuilder(); int c;
        while((c=reader.read())!=-1&&c!='\n') { require(result.length()<MAX_LINE,"ROW_EXCEEDS_TRANSFER_LIMIT");result.append((char)c); }
        return c==-1&&result.length()==0?null:result.toString();
    }

    ArrayNode snapshotFiles(Path destination) throws Exception {
        ArrayNode manifest=JSON.createArrayNode();
        for(Path source:listFiles(shared)) {
            String relative=shared.relativize(source).toString().replace('\\','/'); Path copy=safe(destination,relative);
            Files.createDirectories(copy.getParent()); Files.copy(source,copy);
            String digest=sha(copy);require(digest.equals(sha(source)),"SHARED_FILE_CHANGED_DURING_EXPORT");
            ObjectNode entry=manifest.addObject();entry.put("path",relative);entry.put("bytes",Files.size(copy));entry.put("sha256",digest);
        }
        verifyFiles(shared,manifest,true);return manifest;
    }
    static List<Path> listFiles(Path root) throws Exception {
        require(!Files.isSymbolicLink(root)&&Files.isDirectory(root,LinkOption.NOFOLLOW_LINKS),"FILE_ROOT_INVALID");
        List<Path> files=new ArrayList<>();
        try(var walk=Files.walk(root)) { for(Path path:walk.toList()) {
            require(!Files.isSymbolicLink(path),"SYMLINK_NOT_ALLOWED");
            if(Files.isDirectory(path,LinkOption.NOFOLLOW_LINKS))continue;
            require(Files.isRegularFile(path,LinkOption.NOFOLLOW_LINKS),"SPECIAL_FILE_NOT_ALLOWED");files.add(path);
        }}
        files.sort(Comparator.comparing(p->root.relativize(p).toString()));return files;
    }
    static Path safe(Path root,String relative) {
        require(!relative.isEmpty()&&!relative.contains("\\")&&!relative.contains(":")&&!relative.startsWith("/")
            &&Arrays.stream(relative.split("/",-1)).noneMatch(v->v.isEmpty()||v.equals(".")||v.equals("..")),"UNSAFE_ARTIFACT_PATH");
        Path result=root.resolve(relative).normalize();require(result.startsWith(root)&&!result.equals(root),"UNSAFE_ARTIFACT_PATH");
        for(Path path=result;path!=null&&path.startsWith(root);path=path.getParent())require(!Files.isSymbolicLink(path),"SYMLINK_NOT_ALLOWED");return result;
    }
    static void verifyFiles(Path root,JsonNode entries,boolean exact) throws Exception {
        Set<String> declared=new HashSet<>();
        for(JsonNode entry:entries) {
            String relative=text(entry,"path");require(declared.add(relative),"DUPLICATE_FILE_PATH");Path file=safe(root,relative);
            require(Files.isRegularFile(file,LinkOption.NOFOLLOW_LINKS)&&Files.size(file)==entry.path("bytes").asLong(-1)&&sha(file).equals(text(entry,"sha256")),"FILE_HASH_MISMATCH");
        }
        if(exact) { Set<String> actual=new HashSet<>();for(Path file:listFiles(root))actual.add(root.relativize(file).toString().replace('\\','/'));require(actual.equals(declared),"FILE_SET_MISMATCH"); }
    }
    void collectFileIds(JsonNode node) {
        if(node.isTextual()){
            String value=node.textValue();if(value.contains("/guardian/files/")||value.contains("/wearable/files/")){Matcher matcher=FILE_ID.matcher(value);while(matcher.find())fileIds.add(matcher.group());}
        }else if(node.isObject()){
            node.fields().forEachRemaining(entry->{
                if(Set.of("photoIds","blobId").contains(entry.getKey())){
                    Matcher matcher=FILE_ID.matcher(entry.getValue().toString());while(matcher.find())fileIds.add(matcher.group());
                }else collectFileIds(entry.getValue());
            });
        }else if(node.isArray())for(JsonNode value:node)collectFileIds(value);
    }
    void collectReference(String reference) {
        if(reference.isBlank())return;
        for(JsonNode mapping:config.withArray("urlMappings")) {
            String prefix=text(mapping,"prefix"); if(reference.startsWith(prefix)) {
                String path=text(mapping,"directory")+"/"+reference.substring(prefix.length());safe(shared,path);localReferences.add(path);return;
            }
        }
        for(JsonNode prefix:config.withArray("externalMediaPrefixes"))if(reference.startsWith(prefix.asText())){externalReferences.add(reference);return;}
        throw new TransferFailure("UNMAPPED_FILE_REFERENCE");
    }
    void validateReferences(JsonNode entries) throws Exception {
        Map<String,JsonNode> files=new HashMap<>();for(JsonNode entry:entries)files.put(text(entry,"path"),entry);
        require(files.keySet().containsAll(localReferences),"REFERENCED_FILE_MISSING");
        Map<String,String> published=new HashMap<>();
        jdbc.query("SELECT file_id,file_name,sha256,byte_length FROM guardian_file_publication",rs->{
            String name=rs.getString(2);require(name!=null,"UNCOMMITTED_FILE_POINTER");String path="files/"+name;JsonNode file=files.get(path);
            require(file!=null&&text(file,"sha256").equals(rs.getString(3))&&file.path("bytes").asLong()==rs.getLong(4),"FILE_PUBLICATION_MISMATCH");
            published.put(rs.getString(1),path);
        });
        for(String id:fileIds)require(published.containsKey(id)||files.containsKey("files/"+id+".png")||files.containsKey("files/"+id+".jpg"),"REFERENCED_PHOTO_MISSING");
    }
    ObjectNode continuity() throws Exception {
        Map<String,String> values=backendEnvironment();
        ObjectNode result=JSON.createObjectNode();
        for(String key:List.of("JWT_SECRET","MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY")){
            String value=values.get(key);require(value!=null&&!value.isBlank(),"CONTINUITY_KEY_MISSING");result.put(key,sha(value.getBytes(StandardCharsets.UTF_8)));
        }
        Path marker=safe(shared,"files/.wearable-store-id");String store=Files.readString(marker,StandardCharsets.US_ASCII).trim();
        require(UUID.fromString(store).toString().equals(store),"STORE_MARKER_INVALID");result.put("storeId",store);return result;
    }
    Map<String,String> backendEnvironment()throws Exception{
        Path env=Path.of(text(config,"backendEnvFile"));require(!Files.isSymbolicLink(env),"CONFIG_SYMLINK_NOT_ALLOWED");
        Map<String,String> values=new HashMap<>();for(String line:Files.readAllLines(env,StandardCharsets.UTF_8)){int i=line.indexOf('=');if(i>0)values.put(line.substring(0,i),line.substring(i+1));}
        return values;
    }
    ArrayNode archiveConfiguration(Path bundle) throws Exception {
        Path root=bundle.resolve("configuration");Files.createDirectory(root);ArrayNode list=JSON.createArrayNode();
        List<Path> sources=new ArrayList<>();sources.add(Path.of(text(config,"backendEnvFile")));for(JsonNode item:config.withArray("configurationFiles"))sources.add(Path.of(item.asText()));
        for(int i=0;i<sources.size();i++){
            Path source=sources.get(i);require(Files.isRegularFile(source,LinkOption.NOFOLLOW_LINKS)&&!Files.isSymbolicLink(source),"CONFIGURATION_FILE_INVALID");
            String name=String.format(Locale.ROOT,"%03d-",i)+source.getFileName();Path copy=safe(root,name);Files.copy(source,copy);
            ObjectNode entry=list.addObject();entry.put("path",name);entry.put("bytes",Files.size(copy));entry.put("sha256",sha(copy));
        }return list;
    }

    ObjectNode validateBundle(Path bundle) throws Exception {
        require(!Files.isSymbolicLink(bundle)&&Files.isDirectory(bundle,LinkOption.NOFOLLOW_LINKS),"BUNDLE_DIRECTORY_REQUIRED");
        require(sha(bundle.resolve("manifest.json")).equals(Files.readString(bundle.resolve("manifest.sha256")).trim()),"MANIFEST_HASH_MISMATCH");
        ObjectNode manifest=(ObjectNode)JSON.readTree(Files.readString(bundle.resolve("manifest.json"),StandardCharsets.UTF_8));
        require(manifest.path("format").asInt()==1&&"COMPLETE".equals(text(manifest,"state")),"INCOMPLETE_BUNDLE");
        require(text(manifest,"applicationSha256").equals(required("MIGRATION_APPLICATION_SHA256")),"TESTED_APPLICATION_ARTIFACT_MISMATCH");
        Set<String> present=new TreeSet<>();manifest.path("tables").fieldNames().forEachRemaining(present::add);require(present.equals(expected),"BUNDLE_SCHEMA_MISMATCH");
        for(Table table:tables.values()){
            context=table.name;
            JsonNode descriptor=manifest.path("tables").path(table.name);Path file=safe(bundle,"tables/"+table.name+".jsonl");
            require(sha(file).equals(text(descriptor,"sha256")),"TABLE_HASH_MISMATCH");
            require(text(descriptor,"policy").equals(ARCHIVE.contains(table.name)?"archive":"restore"),"TABLE_POLICY_MISMATCH");
            require(descriptor.path("columns").size()==table.columns.size()&&descriptor.path("primaryKey").equals(JSON.valueToTree(table.primaryKey)),"TABLE_DEFINITION_MISMATCH");
            for(int i=0;i<table.columns.size();i++){Column c=table.columns.get(i);context=table.name+"."+c.name;JsonNode col=descriptor.path("columns").get(i);require(c.name.equals(text(col,"name"))&&c.kind.equals(text(col,"kind")),"COLUMN_DEFINITION_MISMATCH");}
            long rows=0;String previous=null,previousKey=null;
            try(BufferedReader reader=Files.newBufferedReader(file,StandardCharsets.UTF_8)){String line;while((line=readLine(reader))!=null){
                require(previous==null||previous.compareTo(line)<0,"UNSORTED_OR_DUPLICATE_ROWS");previous=line;JsonNode row=JSON.readTree(line);
                require(row.path("values").size()==table.columns.size()&&row.path("key").size()==table.primaryKey.size(),"INVALID_ROW_SHAPE");
                String rowKey=canonical(row.path("key"));require(!rowKey.equals(previousKey),"DUPLICATE_PRIMARY_KEY");previousKey=rowKey;
                for(int i=0;i<table.primaryKey.size();i++)require(row.path("key").get(i).equals(row.path("values").get(index(table,table.primaryKey.get(i)))),"ROW_PRIMARY_KEY_MISMATCH");
                for(int i=0;i<table.columns.size();i++)validateValue(table,table.columns.get(i),row.path("values").get(i));
                validatePrivatePayloads(table,row.path("values"));rows++;
            }}
            require(rows==descriptor.path("rows").asLong(-1),"ROW_COUNT_MISMATCH");
        }
        verifyFiles(bundle.resolve("files"),manifest.path("files"),true);
        verifyFiles(bundle.resolve("configuration"),manifest.path("configuration"),true);
        require(manifest.path("continuity").equals(continuity()),"ENCRYPTION_LOGIN_OR_STORE_CONTINUITY_MISMATCH");
        return manifest;
    }
    static void validateValue(Table table,Column c,JsonNode value) throws Exception {
        require(value!=null&&(value.isNull()||value.isTextual()),"INVALID_TYPED_VALUE");if(value.isNull())return;
        String v=value.textValue();switch(c.kind){
            case "number" -> { require(decimal(new BigDecimal(v)).equals(v),"NONCANONICAL_NUMBER"); }
            case "binary" -> { require(Base64.getEncoder().encodeToString(Base64.getDecoder().decode(v)).equals(v),"INVALID_BINARY_ENCODING"); }
            case "date" -> LocalDate.parse(v);
            case "time" -> LocalTime.parse(v);
            case "timestamp" -> LocalDateTime.parse(v);
            case "text" -> {if(jsonColumn(table.name,c.name)&&!v.startsWith("enc:v1:"))require(canonical(JSON.readTree(v)).equals(v),"INVALID_BUSINESS_JSON");}
        }
    }

    void importBundle(Path bundle,boolean resume) throws Exception {
        Path journal=Path.of(required("MIGRATION_JOURNAL")).toAbsolutePath().normalize();
        require(!Files.isSymbolicLink(journal)&&!Files.isSymbolicLink(journal.resolveSibling(journal.getFileName()+".lock")),"JOURNAL_SYMLINK_NOT_ALLOWED");
        try(var channel=java.nio.channels.FileChannel.open(journal.resolveSibling(journal.getFileName()+".lock"),StandardOpenOption.CREATE,StandardOpenOption.WRITE);
            var lock=channel.tryLock()){
            require(lock!=null,"IMPORT_JOURNAL_ALREADY_IN_USE");importLocked(bundle,resume,journal);
        }
    }
    void importLocked(Path bundle,boolean resume,Path journal) throws Exception {
        require(text(config,"targetId").equals(required("MIGRATION_CONFIRM_TARGET")),"EXPLICIT_TARGET_CONFIRMATION_REQUIRED");
        ObjectNode manifest=validateBundle(bundle);requireOffline(!resume);
        ObjectNode progress;String claim=UUID.randomUUID().toString();
        String endpoint=sha((dialect+"\n"+text(config,"url")+"\n"+schema+"\n"+text(config,"username")).getBytes(StandardCharsets.UTF_8));
        if(resume){
            progress=(ObjectNode)JSON.readTree(Files.readString(journal));
            require(text(progress,"targetId").equals(text(config,"targetId"))&&text(progress,"endpointSha256").equals(endpoint)
                &&text(progress,"manifestSha256").equals(sha(bundle.resolve("manifest.json"))),"RESUME_TARGET_OR_BUNDLE_MISMATCH");
            require(Set.of("ROWS_COMMITTED","RESEEDING","RESEED_FAILED").contains(text(progress,"state")),"RESUME_STAGE_UNSAFE");
            compareRows(bundle,manifest,false);verifyFiles(shared,manifest.path("files"),true);
            require(jdbc.update("UPDATE wearable_schema_lock SET owner=? WHERE id=1 AND owner=?",claim,text(progress,"owner"))==1,"MIGRATION_LOCK_LOST");
            progress.put("owner",claim);writeJson(journal,progress);
        }else{
            require(!Files.exists(journal,LinkOption.NOFOLLOW_LINKS),"NEW_IMPORT_JOURNAL_REQUIRED");
            requireEmptyTarget();requireNewFileTarget(manifest);
            progress=JSON.createObjectNode();progress.put("targetId",text(config,"targetId"));progress.put("endpointSha256",endpoint);progress.put("owner",claim);
            progress.put("manifestSha256",sha(bundle.resolve("manifest.json")));progress.put("state","IMPORTING_ROWS");writeJsonNew(journal,progress);
            db.setAutoCommit(false);
            try{
                // Serialize row import with schema operations. The target stays offline through DDL reseeding.
                require(jdbc.update("UPDATE wearable_schema_lock SET owner=? WHERE id=1 AND owner IS NULL",claim)==1,"MIGRATION_LOCK_UNAVAILABLE");
                requireEmptyTarget();
                jdbc.update("DELETE FROM fuda_alarm_journal_state WHERE id=1 AND committed_sequence=0 AND retained_floor=0 AND backfill_completed_at IS NULL");
                for(Table table:dependencyOrder())if(!ARCHIVE.contains(table.name))insertRows(table,bundle.resolve("tables").resolve(table.name+".jsonl"));
                restoreFiles(bundle,manifest);
                db.commit();progress.put("state","ROWS_COMMITTED");writeJson(journal,progress);
            }catch(Exception error){db.rollback();progress.put("state","ROWS_FAILED_OR_COMMIT_UNCERTAIN");writeJson(journal,progress);throw error;}
            finally{db.setAutoCommit(true);}
        }
        try{
            reseed(manifest,progress,journal);ObjectNode verification=compareRows(bundle,manifest,true);verifyFiles(shared,manifest.path("files"),true);
            require(jdbc.update("UPDATE wearable_schema_lock SET owner=NULL WHERE id=1 AND owner=?",claim)==1,"MIGRATION_LOCK_LOST");
            verification.put("filesVerified",true);progress.set("verification",verification);progress.put("state","COMPLETE");writeJson(journal,progress);
        }catch(Exception error){progress.put("state","RESEED_FAILED");writeJson(journal,progress);throw error;}
    }
    void requireEmptyTarget(){
        for(Table table:tables.values()){
            long count=count(table.actual);
            if(table.name.equals("wearable_cluster_control")){require(count==1&&jdbc.queryForObject("SELECT id FROM wearable_cluster_control",Integer.class)==1,"TARGET_NOT_EMPTY");continue;}
            if(table.name.equals("fuda_alarm_journal_state")&&count==1){require(jdbc.queryForObject("SELECT COUNT(*) FROM fuda_alarm_journal_state WHERE id=1 AND committed_sequence=0 AND retained_floor=0 AND backfill_completed_at IS NULL",Long.class)==1,"TARGET_NOT_EMPTY");continue;}
            require(count==0,"TARGET_NOT_EMPTY");
        }
    }
    void requireNewFileTarget(JsonNode manifest)throws Exception{
        List<Path> existing=listFiles(shared);require(existing.size()==1&&shared.relativize(existing.get(0)).toString().replace('\\','/').equals("files/.wearable-store-id"),"TARGET_FILES_NOT_EMPTY");
    }
    List<Table> dependencyOrder()throws Exception{
        List<Table> ordered=new ArrayList<>();Set<String> visited=new HashSet<>();Map<String,Set<String>> parents=new HashMap<>();
        for(Table table:tables.values()){
            Set<String> refs=new HashSet<>();try(ResultSet keys=db.getMetaData().getImportedKeys(dialect==DatabaseDialect.MYSQL?schema:null,dialect==DatabaseDialect.DM8?schema.toUpperCase(Locale.ROOT):null,table.actual)){
                while(keys.next()){String parent=keys.getString("PKTABLE_NAME").toLowerCase(Locale.ROOT);if(!parent.equals(table.name))refs.add(parent);}
            }require(expected.containsAll(refs),"FOREIGN_KEY_OUTSIDE_SCHEMA");parents.put(table.name,refs);
        }
        while(ordered.size()<tables.size()){
            int before=ordered.size();for(Table t:tables.values())if(!visited.contains(t.name)&&visited.containsAll(parents.get(t.name))){visited.add(t.name);ordered.add(t);}
            require(ordered.size()>before,"CYCLIC_FOREIGN_KEYS_REQUIRE_REVIEW");
        }return ordered;
    }
    void insertRows(Table table,Path file)throws Exception{
        boolean identity=table.columns.stream().anyMatch(Column::identity);
        if(identity&&dialect==DatabaseDialect.DM8)execute("SET IDENTITY_INSERT "+quote(table.actual)+" ON");
        String sql="INSERT INTO "+quote(table.actual)+" ("+String.join(",",table.columns.stream().map(c->quote(c.actual)).toList())+") VALUES ("+String.join(",",Collections.nCopies(table.columns.size(),"?"))+")";
        try(PreparedStatement stmt=db.prepareStatement(sql);BufferedReader reader=Files.newBufferedReader(file,StandardCharsets.UTF_8)){
            stmt.setQueryTimeout(30);String line;while((line=readLine(reader))!=null){JsonNode values=JSON.readTree(line).path("values");for(int i=0;i<table.columns.size();i++)bind(stmt,i+1,table.columns.get(i),values.get(i));stmt.executeUpdate();}
        }finally{if(identity&&dialect==DatabaseDialect.DM8)execute("SET IDENTITY_INSERT "+quote(table.actual)+" OFF");}
    }
    static void bind(PreparedStatement stmt,int i,Column column,JsonNode value)throws Exception{
        if(value.isNull()){stmt.setNull(i,column.type);return;}String v=value.asText();
        switch(column.kind){
            case "number" -> stmt.setBigDecimal(i,new BigDecimal(v));
            case "binary" -> stmt.setBytes(i,Base64.getDecoder().decode(v));
            case "date" -> stmt.setDate(i,java.sql.Date.valueOf(LocalDate.parse(v)));
            case "time" -> stmt.setObject(i,LocalTime.parse(v));
            case "timestamp" -> stmt.setTimestamp(i,Timestamp.valueOf(LocalDateTime.parse(v)),Calendar.getInstance(TimeZone.getTimeZone("UTC")));
            // DM reports JSON as BLOB but its parameter contract is textual JSON; setBytes is rejected as invalid JSON.
            // The launcher fixes file.encoding=UTF-8. Real binary columns still use setBytes above.
            default -> stmt.setString(i,v);
        }
    }
    void restoreFiles(Path bundle,JsonNode manifest)throws Exception{
        for(JsonNode entry:manifest.path("files")){
            String path=text(entry,"path");Path destination=safe(shared,path),source=safe(bundle.resolve("files"),path);
            if(path.equals("files/.wearable-store-id")){require(sha(destination).equals(text(entry,"sha256")),"STORE_MARKER_MISMATCH");continue;}
            Files.createDirectories(destination.getParent());Files.copy(source,destination);require(sha(destination).equals(text(entry,"sha256")),"RESTORED_FILE_HASH_MISMATCH");
        }
    }
    void reseed(JsonNode manifest,ObjectNode progress,Path journal)throws Exception{
        ObjectNode remembered=progress.has("identityWatermarks")?(ObjectNode)progress.get("identityWatermarks"):progress.putObject("identityWatermarks");
        // Preserve the interrupted table before earlier tables update the current progress pointer.
        String interrupted=progress.path("table").asText();long interruptedNext=progress.path("nextIdentity").asLong();
        if(!interrupted.isEmpty()&&interruptedNext>0)remembered.put(interrupted,Math.max(interruptedNext,remembered.path(interrupted).asLong()));
        for(Table table:tables.values()){
            JsonNode descriptor=manifest.path("tables").path(table.name);if(!descriptor.has("nextIdentity")||ARCHIVE.contains(table.name))continue;
            String identityName=null;for(JsonNode column:descriptor.path("columns"))if(column.path("identity").asBoolean())identityName=text(column,"name");
            require(identityName!=null,"SOURCE_IDENTITY_COLUMN_MISSING");Column identity=table.columns.get(index(table,identityName));
            long desired=descriptor.path("nextIdentity").asLong();require(desired>0,"IDENTITY_WATERMARK_INVALID");
            desired=Math.max(desired,remembered.path(table.name).asLong());
            if(identity.identity)desired=Math.max(desired,nextIdentity(table,identity));
            require(desired<Long.MAX_VALUE&&(identity.type==Types.BIGINT||desired<Integer.MAX_VALUE),"IDENTITY_RANGE_EXHAUSTED");
            remembered.put(table.name,desired);progress.put("state","RESEEDING");progress.put("table",table.name);progress.put("nextIdentity",desired);progress.put("ddlStage","BEFORE_CHANGE");writeJson(journal,progress);
            if(dialect==DatabaseDialect.MYSQL)execute("ALTER TABLE "+quote(table.actual)+" AUTO_INCREMENT="+desired);
            else{
                if(identity.identity)execute("ALTER TABLE "+quote(table.actual)+" DROP IDENTITY");
                progress.put("ddlStage","IDENTITY_PROPERTY_REMOVED");writeJson(journal,progress);
                checkpoint.at("identity-removed",table.name);
                execute("ALTER TABLE "+quote(table.actual)+" ADD COLUMN "+quote(identity.actual)+" IDENTITY("+desired+",1)");
            }
            progress.put("ddlStage","IDENTITY_PROPERTY_RESTORED");writeJson(journal,progress);
        }
        tables.clear();loadMetadata();
    }
    ObjectNode compareRows(Path bundle,JsonNode manifest,boolean identities)throws Exception{
        Path scratch=Files.createTempDirectory(Path.of(required("MIGRATION_WORK_DIR")),"compare-");
        ObjectNode report=JSON.createObjectNode(),result=report.putObject("tables");
        report.put("manifestSha256",sha(bundle.resolve("manifest.json")));report.put("databaseProduct",dialect.name());
        report.put("identityWatermarksVerified",identities);report.set("archivedOnlyTables",JSON.valueToTree(new TreeSet<>(ARCHIVE)));
        try{
            for(Table table:tables.values()){
                if(ARCHIVE.contains(table.name))continue;
                context=table.name;
                ObjectNode actual=exportTable(table,scratch.resolve(table.name+".jsonl"));JsonNode expected=manifest.path("tables").path(table.name);
                if(actual.path("rows").asLong()==expected.path("rows").asLong(-1)&&!actual.path("sha256").equals(expected.path("sha256"))){
                    try(BufferedReader a=Files.newBufferedReader(scratch.resolve(table.name+".jsonl"));BufferedReader e=Files.newBufferedReader(bundle.resolve("tables").resolve(table.name+".jsonl"))){
                        String x,y;while((x=readLine(a))!=null&&(y=readLine(e))!=null)if(!x.equals(y)){
                            JsonNode av=JSON.readTree(x).path("values"),ev=JSON.readTree(y).path("values");for(int i=0;i<table.columns.size();i++)if(!av.get(i).equals(ev.get(i))){context=table.name+"."+table.columns.get(i).name;break;}break;
                        }
                    }
                }
                require(actual.path("rows").asLong()==expected.path("rows").asLong(-1)&&actual.path("sha256").equals(expected.path("sha256")),"ROW_CONTENT_RECONCILIATION_FAILED");
                if(identities&&expected.has("nextIdentity"))require(actual.has("nextIdentity")&&actual.path("nextIdentity").asLong()>=expected.path("nextIdentity").asLong(),"IDENTITY_WATERMARK_RECONCILIATION_FAILED");
                ObjectNode matched=result.putObject(table.name);matched.set("rows",actual.path("rows"));matched.set("sha256",actual.path("sha256"));matched.set("primaryKey",actual.path("primaryKey"));
                if(actual.has("nextIdentity"))matched.set("nextIdentity",actual.path("nextIdentity"));
            }
            validateReferences(manifest.path("files"));
            report.put("completedAt",Instant.now().toString());return report;
        }finally{try(var walk=Files.walk(scratch)){for(Path path:walk.sorted(Comparator.reverseOrder()).toList())Files.deleteIfExists(path);}}
    }
    void reconcileBundle(Path bundle)throws Exception{
        ObjectNode manifest=validateBundle(bundle);requireOffline(false);lockSnapshot();
        try{requireOffline(false);ObjectNode report=compareRows(bundle,manifest,true);verifyFiles(shared,manifest.path("files"),true);
            report.put("filesVerified",true);report.put("state","COMPLETE");writeJsonNew(Path.of(required("MIGRATION_REPORT")),report);
        }finally{unlockSnapshot();}
    }

    static String required(String name){String value=System.getenv(name);require(value!=null&&!value.isBlank(),"REQUIRED_ENVIRONMENT_MISSING");return value;}
    static String text(JsonNode object,String field){JsonNode value=object.get(field);require(value!=null&&value.isTextual()&&!value.asText().isEmpty(),"REQUIRED_MANIFEST_FIELD_MISSING");return value.asText();}
    static void require(boolean condition,String code){if(!condition)throw new TransferFailure(code);}
    static final class TransferFailure extends RuntimeException{TransferFailure(String code){super(code);}}
    static String sha(byte[] bytes)throws Exception{return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));}
    static String sha(Path file)throws Exception{
        require(Files.isRegularFile(file,LinkOption.NOFOLLOW_LINKS)&&!Files.isSymbolicLink(file),"HASH_INPUT_NOT_REGULAR_FILE");MessageDigest digest=MessageDigest.getInstance("SHA-256");
        try(InputStream in=Files.newInputStream(file)){byte[] buffer=new byte[65536];int n;while((n=in.read(buffer))!=-1)digest.update(buffer,0,n);}return HexFormat.of().formatHex(digest.digest());
    }
    static void writeJsonNew(Path file,JsonNode value)throws Exception{try(OutputStream out=Files.newOutputStream(file,StandardOpenOption.CREATE_NEW)){out.write((canonical(value)+"\n").getBytes(StandardCharsets.UTF_8));} }
    static void createPrivateDirectory(Path directory)throws Exception{
        if(FileSystems.getDefault().supportedFileAttributeViews().contains("posix"))Files.createDirectory(directory,java.nio.file.attribute.PosixFilePermissions.asFileAttribute(java.nio.file.attribute.PosixFilePermissions.fromString("rwx------")));
        else Files.createDirectory(directory);
    }
    static void writeJson(Path file,JsonNode value)throws Exception{
        Path temp=Files.createTempFile(file.toAbsolutePath().getParent(),".journal-",".json");
        try{try(var channel=java.nio.channels.FileChannel.open(temp,StandardOpenOption.WRITE)){java.nio.ByteBuffer bytes=java.nio.ByteBuffer.wrap((canonical(value)+"\n").getBytes(StandardCharsets.UTF_8));while(bytes.hasRemaining())channel.write(bytes);channel.force(true);}Files.move(temp,file,StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);}
        finally{Files.deleteIfExists(temp);}
    }
}
