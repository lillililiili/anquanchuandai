package com.ruoyi.fuda;

import com.alibaba.fastjson2.JSONObject;
import com.alibaba.fastjson2.JSONWriter;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.transaction.support.TransactionTemplate;
import java.nio.charset.StandardCharsets;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.*;

/** The only delivery truth is this durable queue, never the internal device receipt marker. */
@Repository
public class FudaPushOutbox {
    private final JdbcTemplate jdbc;
    private final com.ruoyi.common.database.DatabaseDialect dialect;
    private final TransactionTemplate tx;
    private volatile Runnable wakeup = () -> {};

    public FudaPushOutbox(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
        this.dialect = com.ruoyi.common.database.DatabaseDialect.of(jdbc);
        tx = new TransactionTemplate(new DataSourceTransactionManager(jdbc.getDataSource()));
        com.ruoyi.database.SchemaLifecycle.ensure(jdbc,"20261102_fuda_push_outbox");
    }

    public void onCommit(Runnable action) { wakeup = Objects.requireNonNull(action); }

    public void enqueue(String destination, String ledgerId, String deviceType, String deviceId, JSONObject envelope, long now) {
        if (!TransactionSynchronizationManager.isActualTransactionActive())
            throw new IllegalStateException("推送任务必须在业务事务内写入");
        String body = envelope.toJSONString(JSONWriter.Feature.WriteMapNullValue);
        if (body.getBytes(StandardCharsets.UTF_8).length > 65536) throw new IllegalArgumentException("推送数据超过限制");
        int changed = dialect.insertIfAbsent(jdbc,"fuda_push_outbox",Arrays.asList("event_id","destination_key","destination_id","ledger_device_id","device_type","device_id","device_key","event_type","body","status","next_attempt_at","created_at"),Arrays.asList("event_id"),
                envelope.getString("eventId"), hash(destination), destination, ledgerId, deviceType, deviceId,
                hash(deviceType+":"+deviceId), envelope.getString("eventType"), body,"PENDING", now, now);
        if (changed != 0) TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override public void afterCommit() {
                // Notification is only an optimization. Periodic polling recovers missed wakeups.
                try { wakeup.run(); } catch (RuntimeException ignored) { }
            }
        });
    }

    /** One short transaction. No network calls or business monitors while a row is locked. */
    public Delivery claim(String destination, long now, long leaseMillis) {
        // A database deadlock aborts the whole short claim transaction. Retrying cannot
        // acknowledge a lease or emit a network request; the fresh token still fences old workers.
        for(int attempt=0;;attempt++) {
            try{return claimOnce(destination,now,leaseMillis);}
            catch(org.springframework.dao.ConcurrencyFailureException conflict){if(attempt>=2)throw conflict;}
        }
    }
    private Delivery claimOnce(String destination,long now,long leaseMillis) {
        return tx.execute(s -> {
            String due = "((o.status='PENDING' AND o.next_attempt_at<=?) OR (o.status='IN_FLIGHT' AND o.lease_until<=?))";
            List<Delivery> rows = jdbc.query(dialect.limit("SELECT o.* FROM fuda_push_outbox o WHERE o.destination_key=? AND " + due
                    + " AND NOT EXISTS (SELECT 1 FROM fuda_push_outbox older WHERE older.destination_key=o.destination_key"
                    + " AND older.device_key=o.device_key AND older.sequence<o.sequence AND older.status IN ('PENDING','IN_FLIGHT'))"
                    + " ORDER BY o.sequence","1")+" FOR UPDATE", (rs,n) -> read(rs), hash(destination), now, now);
            if (rows.isEmpty()) return null;
            Delivery row = rows.get(0);
            String token = UUID.randomUUID().toString();
            int claimed = jdbc.update("UPDATE fuda_push_outbox SET status='IN_FLIGHT',lease_token=?,lease_until=?,attempts=attempts+1,last_attempt_at=?"
                            + " WHERE sequence=? AND ((status='PENDING' AND next_attempt_at<=?) OR (status='IN_FLIGHT' AND lease_until<=?))",
                    token, now+leaseMillis, now, row.sequence, now, now);
            if (claimed != 1) return null;
            row.leaseToken = token; row.attempts++; return row;
        });
    }

    public boolean finish(Delivery row, String status, String outcome, int httpStatus, long now, long retryAt) {
        if (!Arrays.asList("DELIVERED", "PENDING", "CANCELLED").contains(status)) throw new IllegalArgumentException("非法投递状态");
        return jdbc.update("UPDATE fuda_push_outbox SET status=?,last_outcome=?,last_http_status=?,next_attempt_at=?,completed_at=?,lease_token=NULL,lease_until=NULL"
                        + " WHERE sequence=? AND status='IN_FLIGHT' AND lease_token=? AND lease_until>?",
                status, outcome, httpStatus, retryAt, "PENDING".equals(status)?null:now,
                row.sequence, row.leaseToken, now) == 1;
    }

    private static Delivery read(ResultSet rs) throws SQLException {
        Delivery row = new Delivery(); row.sequence=rs.getLong("sequence"); row.eventId=rs.getString("event_id");
        row.ledgerId=rs.getString("ledger_device_id"); row.deviceType=rs.getString("device_type"); row.deviceId=rs.getString("device_id");
        row.eventType=rs.getString("event_type"); row.body=rs.getString("body"); row.attempts=rs.getInt("attempts"); return row;
    }

    static String hash(String input) { return FudaAuth.sha256(input.getBytes(StandardCharsets.UTF_8)); }

    public static final class Delivery {
        public long sequence;
        public String eventId, ledgerId, deviceType, deviceId, eventType, body, leaseToken;
        public int attempts;
    }
}
