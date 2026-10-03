package com.ruoyi.guardian;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import org.junit.jupiter.api.Test;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.util.StreamUtils;

import java.nio.charset.StandardCharsets;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class AdminLedgerStoreTest {
    @Test void seedRoundTripStoresPeopleInTables() throws Exception {
        JdbcTemplate jdbc = database("seed");
        AdminLedgerStore store = new AdminLedgerStore(jdbc);
        JSONObject seed = seed();
        JSONObject loaded = store.read();
        assertEquals("临江示范电厂", loaded.getJSONArray("sites").getJSONObject(0).getString("name"));
        assertEquals(names(seed.getJSONArray("people")), names(loaded.getJSONArray("people")));
        assertEquals(names(seed.getJSONArray("devices")), names(loaded.getJSONArray("devices")));
        assertEquals(seed.getJSONArray("maintenanceOrders").size(), loaded.getJSONArray("maintenanceOrders").size());
        assertEquals("陈建国", jdbc.queryForObject("SELECT name FROM wearable_person WHERE id = 'person-1-0'", String.class));
        assertEquals(0, jdbc.queryForObject("SELECT COUNT(*) FROM admin_ledger", Integer.class).intValue());

        person(loaded, "person-1-0").put("name", "陈建国乙");
        store.write(loaded);
        JSONObject again = store.read();
        assertEquals("陈建国乙", person(again, "person-1-0").getString("name"));
        assertEquals(seed.getJSONArray("people").size(), again.getJSONArray("people").size());
        assertEquals("陈建国乙", jdbc.queryForObject("SELECT name FROM wearable_person WHERE id = 'person-1-0'", String.class));
        assertEquals(0, jdbc.queryForObject("SELECT COUNT(*) FROM wearable_person WHERE name = '陈建国'", Integer.class).intValue());
        assertTrue(jdbc.queryForObject("SELECT body FROM wearable_person WHERE id = 'person-1-0'", String.class).contains("陈建国乙"));
    }

    @Test void existingLedgerImportsOnceAndLaterWritesStayInTables() throws Exception {
        JdbcTemplate jdbc = database("legacy");
        AdminLedgerStore store = new AdminLedgerStore(jdbc);
        JSONObject saved = seed();
        saved.getJSONArray("people").getJSONObject(0).put("name", "历史人员");
        jdbc.update("INSERT INTO admin_ledger (id, body) VALUES (1, ?)", saved.toJSONString());
        JSONObject loaded = store.read();
        assertEquals("历史人员", person(loaded, "person-1-0").getString("name"));
        person(loaded, "person-1-0").put("name", "表内人员");
        store.write(loaded);
        assertEquals("表内人员", person(store.read(), "person-1-0").getString("name"));
        assertEquals("表内人员", jdbc.queryForObject("SELECT name FROM wearable_person WHERE id = 'person-1-0'", String.class));
        assertTrue(jdbc.queryForObject("SELECT body FROM admin_ledger WHERE id = 1", String.class).contains("历史人员"));
    }

    private static JSONObject person(JSONObject state, String id) {
        for (Object item : state.getJSONArray("people")) {
            JSONObject row = (JSONObject) item;
            if (id.equals(row.getString("id"))) return row;
        }
        throw new AssertionError(id);
    }

    private static String names(JSONArray rows) {
        StringBuilder names = new StringBuilder();
        for (Object item : rows) names.append(((JSONObject) item).getString("id")).append(':').append(((JSONObject) item).getString("name")).append('\n');
        return names.toString();
    }

    private static JSONObject seed() throws Exception {
        return JSON.parseObject(StreamUtils.copyToString(new ClassPathResource("admin-seed.json").getInputStream(), StandardCharsets.UTF_8));
    }

    private static JdbcTemplate database(String name) {
        DriverManagerDataSource dataSource = new DriverManagerDataSource();
        dataSource.setDriverClassName("org.h2.Driver");
        dataSource.setUrl("jdbc:h2:mem:" + name + ";MODE=MySQL;DB_CLOSE_DELAY=-1;DATABASE_TO_LOWER=TRUE");
        dataSource.setUsername("sa");
        return new JdbcTemplate(dataSource);
    }
}
