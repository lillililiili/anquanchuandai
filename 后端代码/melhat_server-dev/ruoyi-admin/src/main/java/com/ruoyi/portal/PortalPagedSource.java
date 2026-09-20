package com.ruoyi.portal;
import com.ruoyi.portal.PortalModels.*;
/** Optional database paging contract. The source applies actor/site scope before counting. */
public interface PortalPagedSource extends PortalSource {
    Page<Person> peoplePage(String actor,PortalQuery query);
    Page<History> historyPage(String actor,PortalQuery query,String personId);
    Section<HistorySummary> historySummary(String actor,String site,String personId);
}
