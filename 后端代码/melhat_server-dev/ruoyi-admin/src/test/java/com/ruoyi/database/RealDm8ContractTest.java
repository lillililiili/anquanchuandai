package com.ruoyi.database;
import com.ruoyi.common.database.DatabaseDialect;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
@EnabledIfEnvironmentVariable(named="DM8_CONNECTION_FILE",matches=".+")
class RealDm8ContractTest extends RealDatabaseContract {
 @Test void realDm8PreservesDatabaseContracts() throws Exception {verify("DM8_CONNECTION_FILE",DatabaseDialect.DM8,"DM8_RESET_TEST_SCHEMA");}
}
