package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.SingleConnectionDataSource;

import java.sql.Connection;
import java.sql.DatabaseMetaData;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import static com.ruoyi.guardian.WearableModel.object;
import static com.ruoyi.guardian.WearableModel.rows;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class WearableLocationIndexTest {
    private JdbcTemplate database(boolean lower) {
        return new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()
                +";MODE=MySQL;DB_CLOSE_DELAY=-1"+(lower?";DATABASE_TO_LOWER=TRUE":""),"sa",""));
    }
    private boolean indexExists(JdbcTemplate jdbc,String name) {
        return jdbc.queryForObject("SELECT COUNT(*) FROM information_schema.indexes WHERE LOWER(index_name)=?",Integer.class,name.toLowerCase())>0;
    }
    private JdbcTemplate oldDatabase() {
        JdbcTemplate jdbc=database(true);new WearableBusinessStore(jdbc);
        jdbc.execute("DROP INDEX "+WearableLocationIndex.NAME);
        return jdbc;
    }
    private JSONObject empty() {
        return object("version",1,"seq",0,"stations",new JSONArray(),"people",new JSONArray(),
                "devices",new JSONArray(),"events",new JSONArray(),"locations",new JSONArray());
    }

    @Test void freshAndRepeatedStartupSupportLowerAndUpperCaseMetadata() {
        for(boolean lower:new boolean[]{true,false}) {
            JdbcTemplate jdbc=database(lower);
            new WearableBusinessStore(jdbc);new WearableBusinessStore(jdbc);
            assertTrue(indexExists(jdbc,WearableLocationIndex.NAME));
            // ensure verifies column sequence and the actual DESC/ASC metadata, not just a name.
            assertDoesNotThrow(()->WearableLocationIndex.ensure(jdbc));
            assertTrue(indexExists(jdbc,"wb_2_device"));
        }
    }

    @Test void existingRowsKeepPerDeviceBoundaryTiesNullsQuietDevicesAndFullHistory() {
        JdbcTemplate jdbc=oldDatabase();WearableBusinessStore old=WearableBusinessStore.existing(jdbc,"");
        WearableBusinessStore.Snapshot initial=old.load("guardian",null,this::empty);
        for(int n=599;n>=0;n--)rows(initial.state,"locations").add(object("id",String.format("p%03d",n),"deviceId","busy","receivedMillis",1000));
        rows(initial.state,"locations").add(object("id","quiet-old","deviceId","quiet","receivedMillis",0));
        rows(initial.state,"locations").add(object("id","quiet-null-time","deviceId","quiet"));
        rows(initial.state,"locations").add(object("id","null-device","receivedMillis",2000));
        rows(initial.state,"locations").add(object("id","null-device-null-time"));
        old.save("guardian",initial.revision,initial.state,null);
        jdbc.update("INSERT INTO wearable_location(namespace,collection_key,record_key,device_id,observed_at,sort_order,body) VALUES (?,?,?,?,?,?,?)",
                "media","locations","foreign","busy",9999,0,"{\"id\":\"foreign\"}");
        WearableBusinessStore.Snapshot before=old.loadWorkingSet("guardian",null,this::empty);
        JSONObject history=old.read("guardian").state;
        new WearableBusinessStore(jdbc);
        WearableBusinessStore.Snapshot after=old.loadWorkingSet("guardian",null,this::empty);
        assertEquals(before.revision,after.revision);assertEquals(before.state,after.state);
        assertEquals(history,old.read("guardian").state);
        List<String> ids=new ArrayList<>();for(Object raw:rows(after.state,"locations"))ids.add(((JSONObject)raw).getString("id"));
        assertEquals(516,ids.size());assertTrue(ids.contains("p000"));assertTrue(ids.contains("p511"));assertFalse(ids.contains("p512"));
        assertTrue(ids.contains("quiet-old"));assertTrue(ids.contains("quiet-null-time"));
        assertTrue(ids.contains("null-device"));assertTrue(ids.contains("null-device-null-time"));assertFalse(ids.contains("foreign"));
        assertEquals(604,rows(history,"locations").size());
    }

    @Test void concurrentOldDatabaseInitializersConvergeWithoutDroppingExistingIndexes() throws Exception {
        JdbcTemplate jdbc=oldDatabase();ExecutorService pool=Executors.newFixedThreadPool(6);
        CountDownLatch start=new CountDownLatch(1);List<Future<?>> pending=new ArrayList<>();
        try {
            for(int n=0;n<6;n++)pending.add(pool.submit(()->{start.await();WearableLocationIndex.ensure(jdbc);return null;}));
            start.countDown();for(Future<?> result:pending)result.get(10,TimeUnit.SECONDS);
        } finally {pool.shutdownNow();}
        assertDoesNotThrow(()->WearableLocationIndex.ensure(jdbc));
        assertTrue(indexExists(jdbc,WearableLocationIndex.NAME));assertTrue(indexExists(jdbc,"wb_2_device"));
    }

    @Test void readOnlyAndExistingConstructorsNeverUpgradeSchema() {
        JdbcTemplate jdbc=oldDatabase();WearableBusinessStore.readOnly(jdbc,"");WearableBusinessStore.existing(jdbc,"");
        assertFalse(indexExists(jdbc,WearableLocationIndex.NAME));assertTrue(indexExists(jdbc,"wb_2_device"));
    }

    @Test void incompatibleNamedIndexFailsClearlyWithoutReplacingAnyIndex() {
        JdbcTemplate jdbc=oldDatabase();jdbc.execute("CREATE INDEX "+WearableLocationIndex.NAME+" ON wearable_location(device_id)");
        DataAccessException failure=assertThrows(DataAccessException.class,()->WearableLocationIndex.ensure(jdbc));
        assertTrue(failure.getMessage().contains("incompatible columns or ordering"));
        assertTrue(indexExists(jdbc,WearableLocationIndex.NAME));assertTrue(indexExists(jdbc,"wb_2_device"));
    }

    @Test void permissionFailureIsNotMistakenForConcurrentSuccessfulInitialization() throws Exception {
        Connection connection=mock(Connection.class);DatabaseMetaData metadata=mock(DatabaseMetaData.class);
        ResultSet indexes=mock(ResultSet.class);Statement statement=mock(Statement.class);
        when(connection.getMetaData()).thenReturn(metadata);when(metadata.getDatabaseProductName()).thenReturn("MySQL");when(metadata.getDatabaseMajorVersion()).thenReturn(8);
        when(metadata.getIndexInfo(any(),any(),anyString(),eq(false),eq(false))).thenReturn(indexes);
        when(connection.createStatement()).thenReturn(statement);
        when(statement.execute(WearableLocationIndex.CREATE)).thenThrow(new SQLException("QA permission denied","42000",1142));
        JdbcTemplate jdbc=new JdbcTemplate(new SingleConnectionDataSource(connection,true));
        DataAccessException failure=assertThrows(DataAccessException.class,()->WearableLocationIndex.ensure(jdbc));
        assertTrue(failure.getMessage().contains("QA permission denied"));
        verify(statement,times(1)).execute(WearableLocationIndex.CREATE);
    }

    @Test void mysqlWithoutRealDescendingIndexesFailsBeforeDdl() throws Exception {
        Connection connection=mock(Connection.class);DatabaseMetaData metadata=mock(DatabaseMetaData.class);
        when(connection.getMetaData()).thenReturn(metadata);when(metadata.getDatabaseProductName()).thenReturn("MySQL");when(metadata.getDatabaseMajorVersion()).thenReturn(5);
        JdbcTemplate jdbc=new JdbcTemplate(new SingleConnectionDataSource(connection,true));
        DataAccessException failure=assertThrows(DataAccessException.class,()->WearableLocationIndex.ensure(jdbc));
        assertTrue(failure.getMessage().contains("MySQL 8 or newer"));verify(connection,never()).createStatement();
    }

    @Test void mysqlSameNamedPrefixOrInvisibleIndexIsRejectedWithoutDdl() throws Exception {
        for(boolean prefix:new boolean[]{true,false}) {
            Connection connection=mock(Connection.class);DatabaseMetaData metadata=mock(DatabaseMetaData.class);
            ResultSet indexes=mock(ResultSet.class),details=mock(ResultSet.class);PreparedStatement statement=mock(PreparedStatement.class);
            when(connection.getMetaData()).thenReturn(metadata);when(metadata.getDatabaseProductName()).thenReturn("MySQL");when(metadata.getDatabaseMajorVersion()).thenReturn(8);
            when(metadata.getIndexInfo(any(),any(),anyString(),eq(false),eq(false))).thenReturn(indexes);
            when(indexes.next()).thenReturn(true,true,true,true,true,false);
            when(indexes.getString("INDEX_NAME")).thenReturn(WearableLocationIndex.NAME);when(indexes.getBoolean("NON_UNIQUE")).thenReturn(true);
            when(indexes.getString("COLUMN_NAME")).thenReturn("namespace","collection_key","device_id","observed_at","record_key");
            when(indexes.getString("ASC_OR_DESC")).thenReturn("A","A","A","D","A");when(indexes.getInt("ORDINAL_POSITION")).thenReturn(1,2,3,4,5);
            when(connection.prepareStatement(startsWith("SELECT SUB_PART,IS_VISIBLE"))).thenReturn(statement);
            when(statement.executeQuery()).thenReturn(details);when(details.next()).thenReturn(true,false);
            when(details.getObject("SUB_PART")).thenReturn(prefix?20:null);when(details.getString("IS_VISIBLE")).thenReturn(prefix?"YES":"NO");
            JdbcTemplate jdbc=new JdbcTemplate(new SingleConnectionDataSource(connection,true));
            DataAccessException failure=assertThrows(DataAccessException.class,()->WearableLocationIndex.ensure(jdbc));
            assertTrue(failure.getMessage().contains("full-length and visible"));verify(connection,never()).createStatement();
        }
    }
}
