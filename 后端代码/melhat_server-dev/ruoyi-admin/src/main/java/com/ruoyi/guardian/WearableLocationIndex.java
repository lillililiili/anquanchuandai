package com.ruoyi.guardian;

import org.springframework.jdbc.core.ConnectionCallback;
import org.springframework.jdbc.core.JdbcTemplate;

import java.sql.Connection;
import java.sql.DatabaseMetaData;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.Arrays;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.TreeMap;

/** Startup-only additive upgrade; the working-set query and its ordering stay unchanged. */
final class WearableLocationIndex {
    static final String NAME = "wb_2_live";
    static final String CREATE = "CREATE INDEX " + NAME
            + " ON wearable_location(namespace,collection_key,device_id,observed_at DESC,record_key ASC)";
    private static final List<String> DEFINITION = Arrays.asList(
            "namespace:A", "collection_key:A", "device_id:A", "observed_at:D", "record_key:A");

    private WearableLocationIndex() {}

    // Startup only: avoid concurrent H2 metadata/DDL races within this process.
    // Separate application processes still converge through the precise duplicate-index check below.
    static synchronized void ensure(JdbcTemplate jdbc) {
        jdbc.execute((ConnectionCallback<Void>) connection -> {
            DatabaseMetaData metadata = connection.getMetaData();
            if ("MySQL".equalsIgnoreCase(metadata.getDatabaseProductName()) && metadata.getDatabaseMajorVersion() < 8)
                throw new SQLException("Live location ordering requires MySQL 8 or newer with descending index support");
            if (matches(connection)) return null;
            try (Statement statement = connection.createStatement()) {
                statement.execute(CREATE);
            } catch (SQLException failure) {
                // Another initializer may have won CREATE INDEX. Accept only that precise
                // race, and only after checking every column and sort direction again.
                boolean duplicate = failure.getErrorCode() == 1061 || failure.getErrorCode() == 42111
                        || "42S11".equals(failure.getSQLState());
                if (!duplicate || !matches(connection)) throw failure;
            }
            if (!matches(connection)) throw new SQLException("Live location index was not created with its required ordering");
            return null;
        });
    }

    private static boolean matches(Connection connection) throws SQLException {
        DatabaseMetaData metadata = connection.getMetaData();
        String table = metadata.storesUpperCaseIdentifiers() ? "WEARABLE_LOCATION" : "wearable_location";
        Map<Integer, String> actual = new TreeMap<>();
        try (ResultSet indexes = metadata.getIndexInfo(connection.getCatalog(), connection.getSchema(), table, false, false)) {
            while (indexes.next()) {
                if (!NAME.equalsIgnoreCase(indexes.getString("INDEX_NAME"))) continue;
                if (!indexes.getBoolean("NON_UNIQUE"))
                    throw new SQLException("Existing " + NAME + " must be non-unique; no indexes were removed");
                String column = indexes.getString("COLUMN_NAME"), direction = indexes.getString("ASC_OR_DESC");
                if (column == null || direction == null)
                    throw new SQLException("Cannot verify existing live location index definition");
                actual.put(indexes.getInt("ORDINAL_POSITION"), column.toLowerCase(Locale.ROOT) + ":" + direction);
            }
        }
        if (actual.isEmpty()) return false;
        if (!DEFINITION.equals(new java.util.ArrayList<>(actual.values())))
            throw new SQLException("Existing " + NAME + " has incompatible columns or ordering; no indexes were removed");
        if ("MySQL".equalsIgnoreCase(metadata.getDatabaseProductName())) {
            // JDBC metadata omits prefix lengths and visibility. A same-named prefix
            // or invisible index cannot satisfy the full ORDER BY through the optimizer.
            try (PreparedStatement statement = connection.prepareStatement(
                    "SELECT SUB_PART,IS_VISIBLE FROM information_schema.statistics "
                            + "WHERE TABLE_SCHEMA=? AND TABLE_NAME=? AND INDEX_NAME=? ORDER BY SEQ_IN_INDEX")) {
                statement.setString(1, connection.getCatalog());statement.setString(2, table);statement.setString(3, NAME);
                int parts = 0;
                try (ResultSet details = statement.executeQuery()) {
                    while (details.next()) {
                        parts++;
                        if (details.getObject("SUB_PART") != null || !"YES".equalsIgnoreCase(details.getString("IS_VISIBLE")))
                            throw new SQLException("Existing " + NAME + " must be full-length and visible; no indexes were removed");
                    }
                }
                if (parts != DEFINITION.size()) throw new SQLException("Cannot verify complete MySQL live location index definition");
            }
        }
        return true;
    }
}
