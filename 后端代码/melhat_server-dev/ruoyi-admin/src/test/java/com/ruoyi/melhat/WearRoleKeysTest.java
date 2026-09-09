package com.ruoyi.melhat;

import com.ruoyi.common.constant.WearRoleKeys;
import org.junit.jupiter.api.Test;

import java.util.Collections;
import java.util.HashSet;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class WearRoleKeysTest {

    @Test
    void platformAdminSeesAllSitesAndCanWriteHats() {
        assertTrue(WearRoleKeys.seesAllSites(set(WearRoleKeys.PLATFORM_ADMIN), false));
        assertTrue(WearRoleKeys.canWriteHat(set(WearRoleKeys.PLATFORM_ADMIN), false));
        assertTrue(WearRoleKeys.seesAllSites(Collections.emptySet(), true));
    }

    @Test
    void dutyAndReadonlyCannotWriteHats() {
        assertFalse(WearRoleKeys.canWriteHat(set(WearRoleKeys.DUTY), false));
        assertFalse(WearRoleKeys.canWriteHat(set(WearRoleKeys.READONLY), false));
        assertTrue(WearRoleKeys.canWriteHat(set(WearRoleKeys.DEVICE_ADMIN), false));
    }

    @Test
    void personWriteFollowsDeviceAdminNotDuty() {
        assertTrue(WearRoleKeys.canWritePerson(set(WearRoleKeys.DEVICE_ADMIN), false));
        assertTrue(WearRoleKeys.canWritePerson(set(WearRoleKeys.PLATFORM_ADMIN), false));
        assertFalse(WearRoleKeys.canWritePerson(set(WearRoleKeys.DUTY), false));
        assertFalse(WearRoleKeys.canWritePerson(set(WearRoleKeys.READONLY), false));
        assertTrue(WearRoleKeys.canWritePerson(Collections.emptySet(), true));
    }

    @Test
    void dutyDoesNotSeeAllSites() {
        assertFalse(WearRoleKeys.seesAllSites(set(WearRoleKeys.DUTY), false));
    }

    @Test
    void deviceWriteFollowsDeviceAdmin() {
        assertTrue(WearRoleKeys.canWriteDevice(set(WearRoleKeys.DEVICE_ADMIN), false));
        assertFalse(WearRoleKeys.canWriteDevice(set(WearRoleKeys.DUTY), false));
        assertTrue(WearRoleKeys.canWriteDevice(set(WearRoleKeys.PLATFORM_ADMIN), false));
        assertFalse(WearRoleKeys.canWriteDevice(set(WearRoleKeys.READONLY), false));
    }

    @Test
    void platformAdminCannotClaimEvents() {
        assertFalse(WearRoleKeys.canClaimEvent(set(WearRoleKeys.PLATFORM_ADMIN), false));
        assertFalse(WearRoleKeys.canClaimEvent(Collections.emptySet(), true));
        assertFalse(WearRoleKeys.canClaimEvent(set(WearRoleKeys.READONLY), false));
        assertFalse(WearRoleKeys.canClaimEvent(set(WearRoleKeys.REVIEWER), false));
        assertFalse(WearRoleKeys.canClaimEvent(set(WearRoleKeys.DEVICE_ADMIN), false));
        assertTrue(WearRoleKeys.canClaimEvent(set(WearRoleKeys.DUTY), false));
        assertTrue(WearRoleKeys.canClaimEvent(set(WearRoleKeys.TEAM_LEAD), false));
    }

    @Test
    void callStartFollowsClaimNotPlatform() {
        assertTrue(WearRoleKeys.canStartCall(set(WearRoleKeys.DUTY), false));
        assertFalse(WearRoleKeys.canStartCall(set(WearRoleKeys.PLATFORM_ADMIN), false));
        assertTrue(WearRoleKeys.canSendTts(set(WearRoleKeys.DEVICE_ADMIN), false));
        assertFalse(WearRoleKeys.canSendTts(set(WearRoleKeys.READONLY), false));
    }

    @Test
    void taskEditFollowsDutyNotPlatform() {
        assertTrue(WearRoleKeys.canEditTask(set(WearRoleKeys.DUTY), false));
        assertTrue(WearRoleKeys.canEditTask(set(WearRoleKeys.TEAM_LEAD), false));
        assertFalse(WearRoleKeys.canEditTask(set(WearRoleKeys.PLATFORM_ADMIN), false));
        assertFalse(WearRoleKeys.canEditTask(set(WearRoleKeys.READONLY), false));
    }

    @Test
    void reviewerCanReviewButDutyCannot() {
        assertTrue(WearRoleKeys.canReviewEvent(set(WearRoleKeys.REVIEWER), false));
        assertTrue(WearRoleKeys.canReviewEvent(set(WearRoleKeys.PLATFORM_ADMIN), false));
        assertTrue(WearRoleKeys.canReviewEvent(Collections.emptySet(), true));
        assertFalse(WearRoleKeys.canReviewEvent(set(WearRoleKeys.DUTY), false));
        assertFalse(WearRoleKeys.canReviewEvent(set(WearRoleKeys.READONLY), false));
    }

    private static HashSet<String> set(String key) {
        HashSet<String> values = new HashSet<String>();
        values.add(key);
        return values;
    }
}
