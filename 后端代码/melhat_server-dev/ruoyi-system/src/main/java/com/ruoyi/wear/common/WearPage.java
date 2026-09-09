package com.ruoyi.wear.common;

import java.util.Collections;
import java.util.List;

public class WearPage<T>
{
    private List<T> records = Collections.emptyList();
    private long total;
    private long current;
    private long size;

    public static <T> WearPage<T> of(List<T> records, long total, long current, long size)
    {
        WearPage<T> page = new WearPage<T>();
        page.setRecords(records == null ? Collections.<T>emptyList() : records);
        page.setTotal(total);
        page.setCurrent(current);
        page.setSize(size);
        return page;
    }

    public List<T> getRecords() { return records; }
    public void setRecords(List<T> records) { this.records = records; }
    public long getTotal() { return total; }
    public void setTotal(long total) { this.total = total; }
    public long getCurrent() { return current; }
    public void setCurrent(long current) { this.current = current; }
    public long getSize() { return size; }
    public void setSize(long size) { this.size = size; }
}
