package com.ruoyi.common.constant;

import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.Set;

/**
 * Wear platform role_key values. Distinct from physical sites.
 */
public final class WearRoleKeys
{
    public static final String PLATFORM_ADMIN = "wear_platform_admin";
    public static final String DEVICE_ADMIN = "wear_device_admin";
    public static final String DUTY = "wear_duty";
    public static final String REVIEWER = "wear_reviewer";
    public static final String TEAM_LEAD = "wear_team_lead";
    public static final String READONLY = "wear_readonly";
    public static final String RUOYI_ADMIN = "admin";

    public static final String PERM_HAT_LIST = "wear:hat:list";
    public static final String PERM_HAT_QUERY = "wear:hat:query";
    public static final String PERM_HAT_EDIT = "wear:hat:edit";
    public static final String PERM_SITE_LIST = "wear:site:list";
    public static final String PERM_SITE_SELECT = "wear:site:select";
    public static final String PERM_PERSON_LIST = "wear:person:list";
    public static final String PERM_PERSON_QUERY = "wear:person:query";
    public static final String PERM_PERSON_EDIT = "wear:person:edit";
    public static final String PERM_SPACE_LIST = "wear:space:list";
    public static final String PERM_SPACE_EDIT = "wear:space:edit";
    public static final String PERM_TEAM_EDIT = "wear:team:edit";
    public static final String PERM_CONTRACTOR_EDIT = "wear:contractor:edit";
    public static final String PERM_DEVICE_LIST = "wear:device:list";
    public static final String PERM_DEVICE_QUERY = "wear:device:query";
    public static final String PERM_DEVICE_EDIT = "wear:device:edit";
    public static final String PERM_MODEL_LIST = "wear:model:list";
    public static final String PERM_MODEL_EDIT = "wear:model:edit";
    public static final String PERM_ASSIGNMENT_LIST = "wear:assignment:list";
    public static final String PERM_ASSIGNMENT_QUERY = "wear:assignment:query";
    public static final String PERM_ASSIGNMENT_ISSUE = "wear:assignment:issue";
    public static final String PERM_EVENT_LIST = "wear:event:list";
    public static final String PERM_EVENT_QUERY = "wear:event:query";
    public static final String PERM_EVENT_CLAIM = "wear:event:claim";
    public static final String PERM_EVENT_REVIEW = "wear:event:review";
    public static final String PERM_CALL_LIST = "wear:call:list";
    public static final String PERM_CALL_QUERY = "wear:call:query";
    public static final String PERM_CALL_START = "wear:call:start";
    public static final String PERM_COMMAND_TTS = "wear:command:tts";
    public static final String PERM_TASK_LIST = "wear:task:list";
    public static final String PERM_TASK_QUERY = "wear:task:query";
    public static final String PERM_TASK_EDIT = "wear:task:edit";
    public static final String PERM_DUTY_QUERY = "wear:duty:query";
    public static final String PERM_DUTY_HANDOVER = "wear:duty:handover";
    public static final String PERM_LOCATION_LIST = "wear:location:list";
    public static final String PERM_LOCATION_QUERY = "wear:location:query";
    public static final String PERM_FENCE_LIST = "wear:fence:list";
    public static final String PERM_FENCE_QUERY = "wear:fence:query";
    public static final String PERM_FENCE_EDIT = "wear:fence:edit";
    public static final String PERM_OVERVIEW_LIST = "wear:overview:list";
    public static final String PERM_PERSON_IMPORT = "wear:person:import";
    public static final String PERM_PERSON_EXPORT = "wear:person:export";
    public static final String PERM_DEVICE_IMPORT = "wear:device:import";
    public static final String PERM_DEVICE_EXPORT = "wear:device:export";
    public static final String PERM_MODEL_IMPORT = "wear:model:import";
    public static final String PERM_MODEL_EXPORT = "wear:model:export";
    public static final String PERM_ASSIGNMENT_EXPORT = "wear:assignment:export";
    public static final String PERM_TASK_EXPORT = "wear:task:export";
    public static final String PERM_FENCE_EXPORT = "wear:fence:export";
    public static final String PERM_EVENT_EXPORT = "wear:event:export";
    public static final String PERM_FILE_LIST = "wear:file:list";
    public static final String PERM_FILE_QUERY = "wear:file:query";
    public static final String PERM_FILE_EXPORT = "wear:file:export";

    private static final Set<String> ALL_SITES = Collections.unmodifiableSet(new HashSet<String>(
            Arrays.asList(PLATFORM_ADMIN, RUOYI_ADMIN)));

    private static final Set<String> HAT_WRITE = Collections.unmodifiableSet(new HashSet<String>(
            Arrays.asList(PLATFORM_ADMIN, RUOYI_ADMIN, DEVICE_ADMIN)));

    private WearRoleKeys()
    {
    }

    public static boolean seesAllSites(Set<String> roleKeys, boolean ruoyiAdminUser)
    {
        if (ruoyiAdminUser)
        {
            return true;
        }
        if (roleKeys == null)
        {
            return false;
        }
        for (String key : roleKeys)
        {
            if (ALL_SITES.contains(key))
            {
                return true;
            }
        }
        return false;
    }

    public static boolean canWriteHat(Set<String> roleKeys, boolean ruoyiAdminUser)
    {
        return seesAllSites(roleKeys, ruoyiAdminUser);
    }

    public static boolean canWritePerson(Set<String> roleKeys, boolean ruoyiAdminUser)
    {
        return seesAllSites(roleKeys, ruoyiAdminUser);
    }

    public static boolean canWriteDevice(Set<String> roleKeys, boolean ruoyiAdminUser)
    {
        return canWriteHat(roleKeys, ruoyiAdminUser);
    }

    public static boolean canClaimEvent(Set<String> roleKeys, boolean ruoyiAdminUser)
    {
        return seesAllSites(roleKeys, ruoyiAdminUser);
    }

    public static boolean canReviewEvent(Set<String> roleKeys, boolean ruoyiAdminUser)
    {
        return seesAllSites(roleKeys, ruoyiAdminUser);
    }

    public static boolean canSimulateEvent(Set<String> roleKeys, boolean ruoyiAdminUser)
    {
        return seesAllSites(roleKeys, ruoyiAdminUser);
    }

    public static boolean canStartCall(Set<String> roleKeys, boolean ruoyiAdminUser)
    {
        return canClaimEvent(roleKeys, ruoyiAdminUser);
    }

    public static boolean canEditTask(Set<String> roleKeys, boolean ruoyiAdminUser)
    {
        return seesAllSites(roleKeys, ruoyiAdminUser);
    }

    public static boolean canSendTts(Set<String> roleKeys, boolean ruoyiAdminUser)
    {
        return seesAllSites(roleKeys, ruoyiAdminUser);
    }
}
