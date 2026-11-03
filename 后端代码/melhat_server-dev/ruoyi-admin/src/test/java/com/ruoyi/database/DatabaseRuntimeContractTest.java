package com.ruoyi.database;
import com.ruoyi.common.database.DatabaseRuntimeContract;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
class DatabaseRuntimeContractTest {
 @Test void acceptsOnlyTheCommissionedStrictDmConfiguration() {
  assertDoesNotThrow(()->DatabaseRuntimeContract.validateDmParameters(4,7,0,1));
  assertThrows(IllegalStateException.class,()->DatabaseRuntimeContract.validateDmParameters(4,1,0,1));
  assertThrows(IllegalStateException.class,()->DatabaseRuntimeContract.validateDmParameters(0,7,0,1));
  assertThrows(IllegalStateException.class,()->DatabaseRuntimeContract.validateDmParameters(4,7,1,1));
  assertThrows(IllegalStateException.class,()->DatabaseRuntimeContract.validateDmParameters(4,7,0,0));
 }
}
