import java.sql.*;
import java.time.Instant;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Standalone, read-only instance metrics. Credentials only come from environment. */
public final class DatabaseMetrics {
    private static String required(String name) {
        String value=System.getenv(name);
        if(value==null||value.isBlank())throw new IllegalArgumentException();
        return value;
    }
    private static double query(Connection connection,String sql) throws SQLException {
        try(Statement statement=connection.createStatement()) {
            statement.setQueryTimeout(4);
            try(ResultSet rows=statement.executeQuery(sql)) {
                if(!rows.next())throw new SQLException("No metric");
                return rows.getDouble(1);
            }
        }
    }
    public static void main(String[] args) {
        ExecutorService network=Executors.newSingleThreadExecutor(r->{Thread t=new Thread(r,"metrics-network-timeout");t.setDaemon(true);return t;});
        int failures=0;
        try {
            if(args.length!=2||!"true".equals(required("METRICS_ISOLATED")))throw new IllegalArgumentException();
            int duration=Integer.parseInt(args[0]),interval=Integer.parseInt(args[1]);
            if(duration<10||duration>86400||interval<250||interval>60000)throw new IllegalArgumentException();
            String product=required("METRICS_DB_PRODUCT");
            boolean dm="dm8".equals(product);
            if(!dm&&!"mysql".equals(product))throw new IllegalArgumentException();
            Class.forName(dm?"dm.jdbc.driver.DmDriver":"com.mysql.cj.jdbc.Driver");
            DriverManager.setLoginTimeout(5);
            try(Connection connection=DriverManager.getConnection(required("METRICS_DB_URL"),required("METRICS_DB_USERNAME"),required("METRICS_DB_PASSWORD"))) {
                String actual=connection.getMetaData().getDatabaseProductName().toUpperCase(java.util.Locale.ROOT);
                if(dm?!actual.contains("DM"):!actual.contains("MYSQL"))throw new IllegalArgumentException();
                connection.setNetworkTimeout(network,5000);
                connection.setAutoCommit(true);
                String waiting=dm?"SELECT COUNT(DISTINCT ID) FROM V$TRXWAIT":"SELECT COUNT(DISTINCT REQUESTING_ENGINE_TRANSACTION_ID) FROM performance_schema.data_lock_waits";
                String age=dm?"SELECT COALESCE(MAX(WAIT_TIME),0) FROM V$TRXWAIT":"SELECT COALESCE(MAX(TIMESTAMPDIFF(MICROSECOND,trx_wait_started,CURRENT_TIMESTAMP(6))),0)/1000.0 FROM information_schema.innodb_trx WHERE trx_state='LOCK WAIT'";
                String active=dm?"SELECT COUNT(*) FROM V$TRX WHERE STATUS IN ('ACTIVE','LOCK WAIT')":"SELECT COUNT(*) FROM information_schema.innodb_trx";
                long started=System.nanoTime();
                while((System.nanoTime()-started)/1_000_000_000L<duration) {
                    String stamp=Instant.now().toString();
                    try {
                        double count=query(connection,waiting),max=query(connection,age),transactions=query(connection,active);
                        System.out.println("{\"utc\":\""+stamp+"\",\"product\":\""+product+"\",\"scope\":\"whole isolated database instance\",\"waitingTransactions\":"+(long)count+",\"maxCurrentWaitMillis\":"+max+",\"activeTransactions\":"+(long)transactions+"}");
                    }catch(SQLException error) {
                        failures++;
                        System.out.println("{\"utc\":\""+stamp+"\",\"error\":true,\"sqlErrorCode\":"+error.getErrorCode()+"}");
                    }
                    System.out.flush();
                    long remaining=duration*1000L-(System.nanoTime()-started)/1_000_000L;
                    if(remaining>0)Thread.sleep(Math.min(interval,remaining));
                }
            }
        }catch(Exception error) {
            failures++;
            System.err.println("Database metrics unavailable; verify private configuration, matching JDBC driver and monitoring privileges. No SQL or credentials are printed.");
        }finally {network.shutdownNow();}
        if(failures>0)System.exit(2);
    }
}
