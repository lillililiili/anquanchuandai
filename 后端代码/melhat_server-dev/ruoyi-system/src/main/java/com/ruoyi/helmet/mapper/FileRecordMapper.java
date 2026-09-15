package com.ruoyi.helmet.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.ruoyi.helmet.pojo.po.FileRecord;
import com.ruoyi.helmet.pojo.po.SafetyHatLocationRecord;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.util.Date;
import java.util.List;

/**
 * 文件记录表Mapper 接口
 *
 * @author autoGennerate
 * @date 2026-03-12
 */
@Mapper
public interface FileRecordMapper extends BaseMapper<FileRecord> {
    /**
     * 自定义查询：关联安全帽表获取设备和人员信息（可选）
     * 假设存在 safety_hat_info 表，字段有 hat_number, bind_user_name
     */
    @Select("<script>" +
            "SELECT fr.*, shi.hat_number, shi.bind_user_name " +
            "FROM file_record fr " +
            "LEFT JOIN safety_hat_info shi ON fr.hat_id = shi.id " +
            "WHERE fr.del_flag = '0' " +
            "<if test='fileType != null and fileType != \"\" '> AND fr.file_type = #{fileType} </if>" +
            "<if test='fileName != null and fileName != \"\"'> AND fr.file_name LIKE CONCAT('%', #{fileName}, '%') </if>" +
            "<if test='hatId != null'> AND fr.hat_id = #{hatId} </if>" +
            "<if test='userName != null and userName != \"\"'> AND shi.bind_user_name LIKE CONCAT('%', #{userName}, '%') </if>" +
            "<if test='uploadTimeFrom != null'> AND fr.upload_time &gt;= #{uploadTimeFrom} </if>" +
            "<if test='uploadTimeTo != null'> AND fr.upload_time &lt;= #{uploadTimeTo} </if>" +
            "ORDER BY fr.upload_time DESC" +
            "</script>")
    List<FileRecord> selectWithDeviceInfo(
            @Param("fileName") String fileName,
            @Param("fileType") String fileType,
            @Param("hatId") Long hatId,
            @Param("userName") String userName,
            @Param("uploadTimeFrom") Date uploadTimeFrom,
            @Param("uploadTimeTo") Date uploadTimeTo
    );


    @Select("<script>" +
            "SELECT * FROM file_record fr " +
            "WHERE fr.del_flag = '0' " +
            "<if test='fileType != null and fileType != \"\" '> AND fr.file_type = #{fileType} </if>" +
            "<if test='hatNumber != null'> AND fr.hat_number = #{hatNumber} </if>" +
            "<if test='startTime != null'> AND fr.upload_time &gt;= #{startTime} </if>" +
            "<if test='endTime != null'> AND fr.upload_time &lt;= #{endTime} </if>" +
            "ORDER BY fr.upload_time DESC" +
            "</script>")
    List<FileRecord> selectRelatedFiles(@Param("hatNumber") String hatNumber,
                                                     @Param("fileType") String fileType,
                                                     @Param("startTime") String startTime,
                                                     @Param("endTime") String endTime);

    @Select("<script>" +
            "SELECT fr.*, shi.hat_number, COALESCE(fr.user_name, shi.bind_user_name) AS user_name, " +
            "CONCAT(shi.hat_number, CASE WHEN shi.bind_user_name IS NULL OR shi.bind_user_name = '' THEN '' ELSE CONCAT(' - ', shi.bind_user_name) END) AS device_info " +
            "FROM file_record fr JOIN safety_hat_info shi ON fr.hat_id = shi.id " +
            "WHERE fr.del_flag = '0' AND shi.site_id IN " +
            "<foreach collection='siteIds' item='siteId' open='(' separator=',' close=')'>#{siteId}</foreach> " +
            "<if test='fileType != null and fileType != \"\"'> AND fr.file_type = #{fileType} </if>" +
            "<if test='fileName != null and fileName != \"\"'> AND fr.file_name LIKE CONCAT('%', #{fileName}, '%') </if>" +
            "<if test='device != null and device != \"\"'> AND shi.hat_number LIKE CONCAT('%', #{device}, '%') </if>" +
            "<if test='userName != null and userName != \"\"'> AND shi.bind_user_name LIKE CONCAT('%', #{userName}, '%') </if>" +
            "<if test='uploadTimeFrom != null'> AND fr.upload_time &gt;= #{uploadTimeFrom} </if>" +
            "<if test='uploadTimeTo != null'> AND fr.upload_time &lt;= #{uploadTimeTo} </if>" +
            "ORDER BY fr.upload_time DESC" +
            "</script>")
    List<FileRecord> selectAuditRecords(@Param("siteIds") List<Long> siteIds,
            @Param("fileName") String fileName, @Param("fileType") String fileType,
            @Param("device") String device, @Param("userName") String userName,
            @Param("uploadTimeFrom") Date uploadTimeFrom,
            @Param("uploadTimeTo") Date uploadTimeTo);

}
