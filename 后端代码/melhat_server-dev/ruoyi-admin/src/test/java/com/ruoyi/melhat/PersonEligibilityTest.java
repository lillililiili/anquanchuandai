package com.ruoyi.melhat;

import com.ruoyi.wear.person.PersonEligibility;
import com.ruoyi.wear.person.domain.WearPerson;
import org.junit.jupiter.api.Test;

import java.util.Calendar;
import java.util.Date;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class PersonEligibilityTest {

    @Test
    void activePersonWithGrantIsSelectable() {
        WearPerson person = person("0", null, null);
        assertTrue(PersonEligibility.selectableForNewWork(person, true, new Date()));
    }

    @Test
    void disabledOrNoGrantOrExpiredIsNotSelectable() {
        assertFalse(PersonEligibility.selectableForNewWork(person("1", null, null), true, new Date()));
        assertFalse(PersonEligibility.selectableForNewWork(person("0", null, null), false, new Date()));
        Calendar cal = Calendar.getInstance();
        cal.set(2020, Calendar.JANUARY, 1);
        assertFalse(PersonEligibility.selectableForNewWork(person("0", null, cal.getTime()), true, new Date()));
    }

    @Test
    void deletedPersonIsNotSelectable() {
        WearPerson person = person("0", null, null);
        person.setDelFlag("2");
        assertFalse(PersonEligibility.selectableForNewWork(person, true, new Date()));
    }

    private WearPerson person(String status, Date from, Date to) {
        WearPerson person = new WearPerson();
        person.setStatus(status);
        person.setDelFlag("0");
        person.setValidFrom(from);
        person.setValidTo(to);
        return person;
    }
}
