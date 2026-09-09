package com.ruoyi.common.core.domain.model;

import java.util.Date;
import java.util.List;
import com.ruoyi.common.core.domain.entity.SysDept;
import com.ruoyi.common.core.domain.entity.SysRole;
import com.ruoyi.common.core.domain.entity.SysUser;

/**
 * 对外返回的当前用户资料。不含 password 及证件影像等内部字段。
 */
public class SysUserProfileDto
{
    private Long userId;
    private Long deptId;
    private String userName;
    private String nickName;
    private String userType;
    private String email;
    private String phonenumber;
    private String sex;
    private String avatar;
    private String status;
    private String loginIp;
    private Date loginDate;
    private SysDept dept;
    private List<SysRole> roles;
    private Long[] roleIds;
    private Long[] postIds;
    private String roleKey;
    private String sipId;
    private String assistGroup;
    private String melHat;
    private String melHatSip;
    private String remark;
    private boolean admin;

    public static SysUserProfileDto from(SysUser user)
    {
        if (user == null)
        {
            return null;
        }
        SysUserProfileDto dto = new SysUserProfileDto();
        dto.setUserId(user.getUserId());
        dto.setDeptId(user.getDeptId());
        dto.setUserName(user.getUserName());
        dto.setNickName(user.getNickName());
        dto.setUserType(user.getUserType());
        dto.setEmail(user.getEmail());
        dto.setPhonenumber(user.getPhonenumber());
        dto.setSex(user.getSex());
        dto.setAvatar(user.getAvatar());
        dto.setStatus(user.getStatus());
        dto.setLoginIp(user.getLoginIp());
        dto.setLoginDate(user.getLoginDate());
        dto.setDept(user.getDept());
        dto.setRoles(user.getRoles());
        dto.setRoleIds(user.getRoleIds());
        dto.setPostIds(user.getPostIds());
        dto.setRoleKey(user.getRoleKey());
        dto.setSipId(user.getSipId());
        dto.setAssistGroup(user.getAssistGroup());
        dto.setMelHat(user.getMelHat());
        dto.setMelHatSip(user.getMelHatSip());
        dto.setRemark(user.getRemark());
        dto.setAdmin(user.isAdmin());
        return dto;
    }

    public Long getUserId()
    {
        return userId;
    }

    public void setUserId(Long userId)
    {
        this.userId = userId;
    }

    public Long getDeptId()
    {
        return deptId;
    }

    public void setDeptId(Long deptId)
    {
        this.deptId = deptId;
    }

    public String getUserName()
    {
        return userName;
    }

    public void setUserName(String userName)
    {
        this.userName = userName;
    }

    public String getNickName()
    {
        return nickName;
    }

    public void setNickName(String nickName)
    {
        this.nickName = nickName;
    }

    public String getUserType()
    {
        return userType;
    }

    public void setUserType(String userType)
    {
        this.userType = userType;
    }

    public String getEmail()
    {
        return email;
    }

    public void setEmail(String email)
    {
        this.email = email;
    }

    public String getPhonenumber()
    {
        return phonenumber;
    }

    public void setPhonenumber(String phonenumber)
    {
        this.phonenumber = phonenumber;
    }

    public String getSex()
    {
        return sex;
    }

    public void setSex(String sex)
    {
        this.sex = sex;
    }

    public String getAvatar()
    {
        return avatar;
    }

    public void setAvatar(String avatar)
    {
        this.avatar = avatar;
    }

    public String getStatus()
    {
        return status;
    }

    public void setStatus(String status)
    {
        this.status = status;
    }

    public String getLoginIp()
    {
        return loginIp;
    }

    public void setLoginIp(String loginIp)
    {
        this.loginIp = loginIp;
    }

    public Date getLoginDate()
    {
        return loginDate;
    }

    public void setLoginDate(Date loginDate)
    {
        this.loginDate = loginDate;
    }

    public SysDept getDept()
    {
        return dept;
    }

    public void setDept(SysDept dept)
    {
        this.dept = dept;
    }

    public List<SysRole> getRoles()
    {
        return roles;
    }

    public void setRoles(List<SysRole> roles)
    {
        this.roles = roles;
    }

    public Long[] getRoleIds()
    {
        return roleIds;
    }

    public void setRoleIds(Long[] roleIds)
    {
        this.roleIds = roleIds;
    }

    public Long[] getPostIds()
    {
        return postIds;
    }

    public void setPostIds(Long[] postIds)
    {
        this.postIds = postIds;
    }

    public String getRoleKey()
    {
        return roleKey;
    }

    public void setRoleKey(String roleKey)
    {
        this.roleKey = roleKey;
    }

    public String getSipId()
    {
        return sipId;
    }

    public void setSipId(String sipId)
    {
        this.sipId = sipId;
    }

    public String getAssistGroup()
    {
        return assistGroup;
    }

    public void setAssistGroup(String assistGroup)
    {
        this.assistGroup = assistGroup;
    }

    public String getMelHat()
    {
        return melHat;
    }

    public void setMelHat(String melHat)
    {
        this.melHat = melHat;
    }

    public String getMelHatSip()
    {
        return melHatSip;
    }

    public void setMelHatSip(String melHatSip)
    {
        this.melHatSip = melHatSip;
    }

    public String getRemark()
    {
        return remark;
    }

    public void setRemark(String remark)
    {
        this.remark = remark;
    }

    public boolean isAdmin()
    {
        return admin;
    }

    public void setAdmin(boolean admin)
    {
        this.admin = admin;
    }
}
