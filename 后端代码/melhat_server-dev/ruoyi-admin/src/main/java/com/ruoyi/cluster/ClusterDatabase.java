package com.ruoyi.cluster;
import com.ruoyi.common.database.DatabaseDialect;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.stereotype.Component;
import java.util.function.Supplier;
/** Lock order: captured business context/JVM lock -> cluster control -> owner -> report/command.
* Never run socket/cloud calls or business projection under this transaction. */
@Component public class ClusterDatabase {
    public final JdbcTemplate jdbc;
    public final DatabaseDialect dialect;
    private final TransactionTemplate tx;
    public ClusterDatabase(JdbcTemplate jdbc) {
        this.jdbc=jdbc;
        dialect=DatabaseDialect.of(jdbc);
        tx=new TransactionTemplate(new DataSourceTransactionManager(jdbc.getDataSource()));
    }
    public long now() {
        return dialect.dbTimeMillis(jdbc);
    }
    public <T>T locked(Supplier<T> work) {
        return tx.execute(s-> {
            jdbc.queryForObject("SELECT id FROM wearable_cluster_control WHERE id=1 FOR UPDATE",Integer.class);
            return work.get();
        }
        );
    }
}
