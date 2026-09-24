// ABOUTME: Reports the export's progress to a monitoring URL (an OpenObserve JSON stream): a heartbeat when an export
// ABOUTME: starts and each table's run. Best effort: a monitoring failure never fails or delays an export for long.
namespace bc2adls;

using System.Environment;
using System.Azure.Identity;
using System.Text;

codeunit 82586 "ADLSE Monitor"
{
    Access = Internal;
    Permissions = tabledata "ADLSE Run" = r;

    procedure ReportExportStarted(TablesStarted: Integer; TablesEnabled: Integer)
    var
        ExportStarted: JsonObject;
    begin
        ExportStarted := NewEvent('export_started');
        ExportStarted.Add('tables_started', TablesStarted);
        ExportStarted.Add('tables_enabled', TablesEnabled);
        Report(ExportStarted);
    end;

    procedure ReportTableExported(TableID: Integer; RecordsSent: Integer)
    var
        ADLSERun: Record "ADLSE Run";
        ADLSEUtil: Codeunit "ADLSE Util";
        TableExported: JsonObject;
    begin
        ADLSERun.SetRange("Table ID", TableID);
        ADLSERun.SetRange("Company Name", CompanyName());
        if not ADLSERun.FindLast() then
            exit;
        TableExported := NewEvent('table_exported');
        TableExported.Add('table_id', TableID);
        TableExported.Add('table_name', ADLSEUtil.GetTableName(TableID));
        TableExported.Add('state', Format(ADLSERun.State));
        TableExported.Add('records', RecordsSent);
        TableExported.Add('duration_seconds', ADLSERun.Duration() / 1000);
        TableExported.Add('error', ADLSERun.Error);
        Report(TableExported);
    end;

    local procedure NewEvent(Name: Text) NewEventObject: JsonObject
    var
        EnvironmentInformation: Codeunit "Environment Information";
        AzureADTenant: Codeunit "Azure AD Tenant";
    begin
        NewEventObject.Add('event', Name);
        NewEventObject.Add('tenant_id', AzureADTenant.GetAadTenantId());
        NewEventObject.Add('environment', EnvironmentInformation.GetEnvironmentName());
        NewEventObject.Add('company', CompanyName());
    end;

    local procedure Report(MonitoringEvent: JsonObject)
    var
        ADLSESetup: Record "ADLSE Setup";
        ADLSECredentials: Codeunit "ADLSE Credentials";
        Body: Text;
    begin
        if not ADLSESetup.Get(0) then
            exit;
        if ADLSESetup."Monitoring URL" = '' then
            exit;
        ADLSECredentials.Init();
        MonitoringEvent.WriteTo(Body);
        // The last error is left as it was, for the export's own bookkeeping that follows.
        if not TrySend(ADLSESetup."Monitoring URL", ADLSESetup."Monitoring User", ADLSECredentials.GetMonitoringToken(), Body) then
            ClearLastError();
        OnAfterReport(MonitoringEvent);
    end;

    [NonDebuggable]
    [TryFunction]
    local procedure TrySend(Url: Text; User: Text; Token: Text; Body: Text)
    var
        Base64Convert: Codeunit "Base64 Convert";
        Client: HttpClient;
        Content: HttpContent;
        ContentHeaders: HttpHeaders;
        Response: HttpResponseMessage;
    begin
        Content.WriteFrom('[' + Body + ']');
        Content.GetHeaders(ContentHeaders);
        ContentHeaders.Remove('Content-Type');
        ContentHeaders.Add('Content-Type', 'application/json');
        Client.DefaultRequestHeaders().Add('Authorization', 'Basic ' + Base64Convert.ToBase64(User + ':' + Token));
        Client.Timeout(10000);
        if Client.Post(Url, Content, Response) then;
    end;

    /// <summary>
    /// Raised after an event was reported, whether or not the monitoring URL accepted it.
    /// </summary>
    [IntegrationEvent(false, false)]
    local procedure OnAfterReport(MonitoringEvent: JsonObject)
    begin
    end;
}
