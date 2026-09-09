package com.ruoyi.wear.person.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.ruoyi.wear.person.domain.WearPerson;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

@Mapper
public interface WearPersonMapper extends BaseMapper<WearPerson>
{
    @Select("SELECT id, person_code, name, org_dept_id, team_id, contractor_id, account_user_id, status, "
            + "valid_from, valid_to, version, del_flag, create_by, create_time, update_by, update_time "
            + "FROM wear_person WHERE id = #{id} AND del_flag = '0' FOR UPDATE")
    WearPerson selectByIdForUpdate(@Param("id") Long id);
}
