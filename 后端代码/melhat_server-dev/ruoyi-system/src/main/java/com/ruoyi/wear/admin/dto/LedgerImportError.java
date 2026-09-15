package com.ruoyi.wear.admin.dto;

public class LedgerImportError
{
    private int row;
    private String field;
    private String reason;

    public LedgerImportError() {}
    public LedgerImportError(int row, String field, String reason)
    {
        this.row = row;
        this.field = field;
        this.reason = reason;
    }
    public int getRow() { return row; }
    public void setRow(int row) { this.row = row; }
    public String getField() { return field; }
    public void setField(String field) { this.field = field; }
    public String getReason() { return reason; }
    public void setReason(String reason) { this.reason = reason; }
}
