package com.ruoyi.portal;
import java.util.*;
import com.ruoyi.portal.PortalModels.Section;
import com.ruoyi.portal.PortalEventModels.*;

/** Fresh actor/site-scoped DTOs, no shared mutable cache. Complete collections, not pre-paginated.
 * Text must already be authorized/redacted for the caller. visible is checked again by the service.
 * Association evidence must describe the event-time association, not a current device binding. */
public interface PortalEventSource {
    default Filters filters(String actor,String site){return new Filters();}
    default Section<List<Fact>> events(String actor,String site){return Section.missing("EVENT_NOT_INTEGRATED");}
    default Section<StatisticsEvidence> statistics(String actor,PortalEventQuery q){return Section.missing("STATISTICS_NOT_INTEGRATED");}
    default boolean visible(String actor,String site,String kind,String id,String permission){return false;}
    default Detail detail(String actor,String site,String id){return null;}
    default Section<List<Timeline>> timeline(String actor,String site,String id){return Section.missing("TIMELINE_NOT_INTEGRATED");}
    default Section<List<Verification>> verifications(String actor,String site,String id){return Section.missing("VERIFICATION_NOT_INTEGRATED");}
}
