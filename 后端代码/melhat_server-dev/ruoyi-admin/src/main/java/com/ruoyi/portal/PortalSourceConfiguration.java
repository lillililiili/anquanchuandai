package com.ruoyi.portal;
import java.util.*;
import com.ruoyi.portal.PortalModels.*;
import org.springframework.context.annotation.*;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
@Configuration
public class PortalSourceConfiguration {
    @Bean @ConditionalOnMissingBean(PortalSource.class)
    public PortalSource portalSource() {
        return new PortalSource() {
            public Context context(String actor) { return new Context(); }
            public Section<List<Person>> roster(String actor,String site,String shift) { return Section.missing("ROSTER_NOT_INTEGRATED"); }
            public Person person(String actor,String site,String person) { return null; }
            public Map<String,Section<Equipment>> equipment(String actor,String site,List<String> ids) { return Collections.emptyMap(); }
            public Section<List<History>> history(String actor,String site,String person) { return Section.missing("HISTORY_NOT_INTEGRATED"); }
        };
    }
}

