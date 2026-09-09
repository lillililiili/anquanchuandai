package com.ruoyi.wear.person;

import java.util.Calendar;
import java.util.Date;
import com.ruoyi.wear.person.domain.WearPerson;

/**
 * Whether a person can be chosen for new assignment or new work.
 * History remains readable after disable / leave / expiry.
 */
public final class PersonEligibility
{
    private PersonEligibility()
    {
    }

    public static boolean selectableForNewWork(WearPerson person, boolean hasActiveSiteGrant, Date now)
    {
        if (person == null || !"0".equals(person.getStatus()) || "2".equals(person.getDelFlag()))
        {
            return false;
        }
        if (!hasActiveSiteGrant)
        {
            return false;
        }
        Date at = now == null ? new Date() : now;
        if (person.getValidFrom() != null && at.before(startOfDay(person.getValidFrom())))
        {
            return false;
        }
        if (person.getValidTo() != null && at.after(endOfDay(person.getValidTo())))
        {
            return false;
        }
        return true;
    }

    private static Date startOfDay(Date date)
    {
        Calendar cal = Calendar.getInstance();
        cal.setTime(date);
        cal.set(Calendar.HOUR_OF_DAY, 0);
        cal.set(Calendar.MINUTE, 0);
        cal.set(Calendar.SECOND, 0);
        cal.set(Calendar.MILLISECOND, 0);
        return cal.getTime();
    }

    private static Date endOfDay(Date date)
    {
        Calendar cal = Calendar.getInstance();
        cal.setTime(date);
        cal.set(Calendar.HOUR_OF_DAY, 23);
        cal.set(Calendar.MINUTE, 59);
        cal.set(Calendar.SECOND, 59);
        cal.set(Calendar.MILLISECOND, 999);
        return cal.getTime();
    }
}
