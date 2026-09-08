package com.ruoyi.system.domain;
/**
 * 场站外包人员实体
 *
 * @author yinweihua
 */
public class UserNumber {
    /**
     * 场站人员
     */
    private int terminaUser;
    /**
     * 外包人员
     */
    private int subcontractorUser;
    /**
     * 在线人数
     */
    private int onLineUser;

    public UserNumber(int terminaUser, int subcontractorUser, int onLineUser) {
        this.terminaUser = terminaUser;
        this.subcontractorUser = subcontractorUser;
        this.onLineUser = onLineUser;
    }

    public UserNumber() {
    }

    public int getTerminaUser() {
        return terminaUser;
    }

    public void setTerminaUser(int terminaUser) {
        this.terminaUser = terminaUser;
    }

    public int getSubcontractorUser() {
        return subcontractorUser;
    }

    public void setSubcontractorUser(int subcontractorUser) {
        this.subcontractorUser = subcontractorUser;
    }

    public int getOnLineUser() {
        return onLineUser;
    }

    public void setOnLineUser(int onLineUser) {
        this.onLineUser = onLineUser;
    }

    @Override
    public String toString() {
        return "UserNumber{" +
                "terminaUser=" + terminaUser +
                ", subcontractorUser=" + subcontractorUser +
                ", onLineUser=" + onLineUser +
                '}';
    }
}
