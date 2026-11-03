package com.ruoyi.database;
import com.ruoyi.common.database.DatabaseDialect;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
@EnabledIfEnvironmentVariable(named="MYSQL_CONNECTION_FILE",matches=".+")
class RealMySqlContractTest extends RealDatabaseContract {
 @Test void realMySqlPreservesDatabaseContracts() throws Exception {verify("MYSQL_CONNECTION_FILE",DatabaseDialect.MYSQL,"MYSQL_RESET_TEST_SCHEMA");}
}
