package com.ruoyi.portal;
import java.util.*;
import com.ruoyi.portal.PortalModels.*;
import com.ruoyi.portal.PortalVideoModels.*;
import com.ruoyi.portal.PortalVideoModels.Detail;

/** Implementations return fresh DTOs, complete collections and actor/site/purpose-scoped evidence.
 * No default database, device platform, storage or RTC access. A missing connector grants no scope. */
public interface PortalVideoSource {
    default Filters filters(String actor,String site){return new Filters();}
    default Section<List<VideoDevice>> devices(String actor,String site){return Section.missing("VIDEO_NOT_INTEGRATED");}
    default Section<StatisticsEvidence> statistics(String actor,PortalVideoQuery query){return Section.missing("STATISTICS_NOT_INTEGRATED");}
    default boolean visible(String actor,String site,String kind,String id,String permission){return false;}
    default Detail detail(String actor,String site,String id){return null;}
}
