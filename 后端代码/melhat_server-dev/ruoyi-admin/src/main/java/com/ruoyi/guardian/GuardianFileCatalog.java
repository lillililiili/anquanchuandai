package com.ruoyi.guardian;

import com.ruoyi.common.database.DatabaseDialect;
import com.ruoyi.database.SchemaLifecycle;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import java.util.Arrays;
import java.util.List;

/** A committed pointer names an immutable shared file; orphan files are safe to retain. */
final class GuardianFileCatalog {
    private final JdbcTemplate jdbc;
    private final TransactionTemplate transaction;
    GuardianFileCatalog(JdbcTemplate jdbc) {
        this.jdbc=jdbc;
        this.transaction=new TransactionTemplate(new DataSourceTransactionManager(jdbc.getDataSource()));
        SchemaLifecycle.ensure(jdbc,"20261103_shared_files");
    }
    static final class Entry {
        final String name,type,sha256;
        final long length;
        Entry(String name,String type,String sha256,long length) {this.name=name;this.type=type;this.sha256=sha256;this.length=length;}
    }
    Entry find(String id) {
        List<Entry> rows=jdbc.query("SELECT file_name,content_type,sha256,byte_length FROM guardian_file_publication WHERE file_id=?",
                (rs,n)->new Entry(rs.getString(1),rs.getString(2),rs.getString(3),rs.getLong(4)),id);
        return rows.isEmpty()||rows.get(0).name==null?null:rows.get(0);
    }
    void publish(String id,Entry entry,Runnable publishFile,boolean createOnly) {
        // Prepare the lock row. For an upload this joins the enclosing business save.
        DatabaseDialect.of(jdbc).insertIfAbsent(jdbc,"guardian_file_publication",Arrays.asList("file_id"),Arrays.asList("file_id"),id);
        transaction.execute(status->{
            String published=jdbc.queryForObject("SELECT file_name FROM guardian_file_publication WHERE file_id=? FOR UPDATE",String.class,id);
            if(createOnly && published!=null) throw AdminQueryService.fail(409,"FILE_EXISTS","照片编号已使用，请使用新编号");
            publishFile.run();
            jdbc.update("UPDATE guardian_file_publication SET file_name=?,content_type=?,sha256=?,byte_length=? WHERE file_id=?",
                    entry.name,entry.type,entry.sha256,entry.length,id);
            return null;
        });
    }
}
