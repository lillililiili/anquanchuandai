package com.ruoyi.wear.location;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import com.ruoyi.wear.event.EventIngestService;
import com.ruoyi.wear.event.dto.IngestRequest;

@Service
public class GeofenceEventWriter
{
    @Autowired
    private EventIngestService eventIngestService;

    @Transactional(propagation = Propagation.REQUIRES_NEW, rollbackFor = Exception.class)
    public void write(IngestRequest ingest)
    {
        eventIngestService.ingest(ingest);
    }
}
