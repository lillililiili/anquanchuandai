package com.ruoyi.portal;
import java.util.*;
import com.ruoyi.portal.PortalModels.*;
/**
 * Authority boundary for future master-data connectors. No device commands.
 * Implementations return per-request DTOs, authorize actor/site on every read,
 * detect cross-person assignment conflicts globally, and preserve historical ownership.
 * null persons mean missing/not visible; unintegrated sources use Section, failures throw.
 */
public interface PortalSource {
    Context context(String actorId);
    Section<List<Person>> roster(String actorId,String siteId,String shiftId);
    Person person(String actorId,String siteId,String personId);
    Map<String,Section<Equipment>> equipment(String actorId,String siteId,List<String> personIds);
    Section<List<History>> history(String actorId,String siteId,String personId);
}

