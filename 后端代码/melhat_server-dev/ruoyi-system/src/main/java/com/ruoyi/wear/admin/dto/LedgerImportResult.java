package com.ruoyi.wear.admin.dto;

import java.util.ArrayList;
import java.util.List;

public class LedgerImportResult
{
    private int total;
    private int created;
    private int updated;
    private int skipped;
    private List<LedgerImportError> errors = new ArrayList<LedgerImportError>();

    public int getTotal() { return total; }
    public void setTotal(int total) { this.total = total; }
    public int getCreated() { return created; }
    public void setCreated(int created) { this.created = created; }
    public int getUpdated() { return updated; }
    public void setUpdated(int updated) { this.updated = updated; }
    public int getSkipped() { return skipped; }
    public void setSkipped(int skipped) { this.skipped = skipped; }
    public List<LedgerImportError> getErrors() { return errors; }
    public void setErrors(List<LedgerImportError> errors) { this.errors = errors; }
    public boolean hasErrors() { return errors != null && !errors.isEmpty(); }
}
