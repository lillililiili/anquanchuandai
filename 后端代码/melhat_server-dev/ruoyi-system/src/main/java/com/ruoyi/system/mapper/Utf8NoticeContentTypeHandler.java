package com.ruoyi.system.mapper;

import java.nio.charset.StandardCharsets;
import java.sql.CallableStatement;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import org.apache.ibatis.type.BaseTypeHandler;
import org.apache.ibatis.type.JdbcType;

/**
 * DM8 exposes notice LONG BLOB values as hex through getString and can
 * transcode setString using the client encoding. Store and read UTF-8 bytes.
 */
public final class Utf8NoticeContentTypeHandler extends BaseTypeHandler<String>
{
    @Override
    public void setNonNullParameter(PreparedStatement statement, int index, String value, JdbcType jdbcType)
        throws SQLException
    {
        statement.setBytes(index, value.getBytes(StandardCharsets.UTF_8));
    }

    @Override
    public String getNullableResult(ResultSet result, String column) throws SQLException
    {
        return decode(result.getBytes(column));
    }

    @Override
    public String getNullableResult(ResultSet result, int column) throws SQLException
    {
        return decode(result.getBytes(column));
    }

    @Override
    public String getNullableResult(CallableStatement statement, int column) throws SQLException
    {
        return decode(statement.getBytes(column));
    }

    private static String decode(byte[] value)
    {
        return value == null ? null : new String(value, StandardCharsets.UTF_8);
    }
}
