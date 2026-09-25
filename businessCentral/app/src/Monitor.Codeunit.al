// ABOUTME: Reports what the export does to a monitoring URL (an OpenObserve JSON stream): exports started, skipped or
// ABOUTME: failed, each table's run, each object written. Best effort: a monitoring failure never fails an export.
namespace bc2adls;

using System.Environment;
using System.Azure.Identity;
using System.Text;

codeunit 82586 "ADLSE Monitor"
{
    Access = Internal;
    Permissions = tabledata "ADLSE Run" = r;

    var
        NoMonitoringUrlErr: Label 'Set the monitoring URL first.';
        MonitoringUnreachableErr: Label 'Could not reach the monitoring URL %1: %2', Comment = '%1 = URL, %2 = error';
        MonitoringRefusedErr: Label 'The monitoring URL refused the test event with status %1: %2', Comment = '%1 = HTTP status, %2 = its answer';
        MonitoringAnsweredTxt: Label 'The monitoring URL took the test event with status %1: %2', Comment = '%1 = HTTP status, %2 = its answer';

    /// <summary>
    /// Sends a test event to the monitoring URL and gives its answer; an error with the answer when it refuses it.
    /// </summary>
    procedure CheckMonitoring(): Text
    var
        ADLSESetup: Record "ADLSE Setup";
        ADLSECredentials: Codeunit "ADLSE Credentials";
        Body: Text;
        Status: Integer;
        Answer: Text;
    begin
        ADLSESetup.GetSingleton();
        if ADLSESetup."Monitoring URL" = '' then
            Error(NoMonitoringUrlErr);
        ADLSECredentials.Init();
        NewEvent('monitoring_check').WriteTo(Body);
        if not Send(ADLSESetup."Monitoring URL", ADLSESetup."Monitoring User", ADLSECredentials.GetMonitoringToken(), Body, Status, Answer) then
            Error(MonitoringUnreachableErr, ADLSESetup."Monitoring URL", GetLastErrorText());
        if (Status < 200) or (Status > 299) then
            Error(MonitoringRefusedErr, Status, Answer);
        exit(StrSubstNo(MonitoringAnsweredTxt, Status, Answer));
    end;

    procedure ReportExportStarted(TablesStarted: Integer; TablesEnabled: Integer; TablesUnreadable: Text)
    var
        ADLSESetup: Record "ADLSE Setup";
        ExportStarted: JsonObject;
    begin
        ExportStarted := NewEvent('export_started');
        ExportStarted.Add('tables_started', TablesStarted);
        ExportStarted.Add('tables_enabled', TablesEnabled);
        ExportStarted.Add('tables_unreadable', TablesUnreadable);
        if ADLSESetup.Get(0) then begin
            AddExportWindow(ExportStarted, ADLSESetup);
            ExportStarted.Add('delayed_export_seconds', ADLSESetup."Delayed Export");
            ExportStarted.Add('shared_tables_company', ADLSESetup."Export Company Database Tables");
        end;
        Report(ExportStarted);
    end;

    procedure ReportExportSkipped(ADLSESetup: Record "ADLSE Setup")
    var
        ExportSkipped: JsonObject;
    begin
        ExportSkipped := NewEvent('export_skipped');
        ExportSkipped.Add('reason', 'outside the export window');
        AddExportWindow(ExportSkipped, ADLSESetup);
        Report(ExportSkipped);
    end;

    procedure ReportExportFailed(ErrorText: Text; CallStack: Text)
    var
        ExportFailed: JsonObject;
    begin
        ExportFailed := NewEvent('export_failed');
        ExportFailed.Add('error', ErrorText);
        ExportFailed.Add('call_stack', CallStack);
        Report(ExportFailed);
    end;

    procedure ReportSessionNotStarted(TableID: Integer)
    var
        SessionNotStarted: JsonObject;
    begin
        SessionNotStarted := NewEvent('session_not_started');
        AddTable(SessionNotStarted, TableID);
        SessionNotStarted.Add('reason', 'the session limit was reached; the table waits for a running export to end');
        Report(SessionNotStarted);
    end;

    procedure ReportTableSessionFailed(TableID: Integer; ErrorText: Text; ErrorCode: Text; CallStack: Text)
    var
        TableSessionFailed: JsonObject;
    begin
        TableSessionFailed := NewEvent('table_session_failed');
        AddTable(TableSessionFailed, TableID);
        TableSessionFailed.Add('error', ErrorText);
        TableSessionFailed.Add('error_code', ErrorCode);
        TableSessionFailed.Add('call_stack', CallStack);
        Report(TableSessionFailed);
    end;

    procedure ReportObjectWritten(TableID: Integer; Path: Text; Characters: Integer; Records: Integer)
    var
        ObjectWritten: JsonObject;
    begin
        ObjectWritten := NewEvent('object_written');
        AddTable(ObjectWritten, TableID);
        ObjectWritten.Add('path', Path);
        ObjectWritten.Add('characters', Characters);
        ObjectWritten.Add('records', Records);
        Report(ObjectWritten);
    end;

    /// <summary>
    /// Reports a table's run as registered in ADLSE Run, with the details the export collected along the way.
    /// </summary>
    procedure ReportTableExported(TableID: Integer; RunDetails: JsonObject)
    var
        ADLSERun: Record "ADLSE Run";
        TableExported: JsonObject;
        DetailName: Text;
        Detail: JsonToken;
    begin
        ADLSERun.SetRange("Table ID", TableID);
        ADLSERun.SetRange("Company Name", CompanyName());
        if not ADLSERun.FindLast() then
            exit;
        TableExported := NewEvent('table_exported');
        AddTable(TableExported, TableID);
        TableExported.Add('run_id', ADLSERun.ID);
        TableExported.Add('state', Format(ADLSERun.State));
        TableExported.Add('started_at', ADLSERun.Started);
        TableExported.Add('ended_at', ADLSERun.Ended);
        TableExported.Add('duration_seconds', ADLSERun.Duration() / 1000);
        TableExported.Add('error', ADLSERun.Error);
        foreach DetailName in RunDetails.Keys() do begin
            RunDetails.Get(DetailName, Detail);
            TableExported.Add(DetailName, Detail);
        end;
        Report(TableExported);
    end;

    local procedure NewEvent(Name: Text) NewEventObject: JsonObject
    var
        ADLSESetup: Record "ADLSE Setup";
        EnvironmentInformation: Codeunit "Environment Information";
        AzureADTenant: Codeunit "Azure AD Tenant";
        ModuleInfo: ModuleInfo;
    begin
        NavApp.GetCurrentModuleInfo(ModuleInfo);
        NewEventObject.Add('event', Name);
        NewEventObject.Add('tenant_id', AzureADTenant.GetAadTenantId());
        NewEventObject.Add('environment', EnvironmentInformation.GetEnvironmentName());
        NewEventObject.Add('company', CompanyName());
        NewEventObject.Add('app_version', Format(ModuleInfo.AppVersion()));
        NewEventObject.Add('session_id', SessionId());
        NewEventObject.Add('user_id', UserId());
        if ADLSESetup.Get(0) then
            NewEventObject.Add('s3_bucket', ADLSESetup."S3 Bucket");
    end;

    local procedure AddTable(MonitoringEvent: JsonObject; TableID: Integer)
    var
        ADLSEUtil: Codeunit "ADLSE Util";
    begin
        MonitoringEvent.Add('table_id', TableID);
        MonitoringEvent.Add('table_caption', ADLSEUtil.GetTableCaption(TableID));
        MonitoringEvent.Add('entity', ADLSEUtil.GetDataLakeCompliantTableName(TableID));
    end;

    local procedure AddExportWindow(MonitoringEvent: JsonObject; ADLSESetup: Record "ADLSE Setup")
    begin
        MonitoringEvent.Add('export_window_start', Format(ADLSESetup."Export Window Start", 0, 9));
        MonitoringEvent.Add('export_window_end', Format(ADLSESetup."Export Window End", 0, 9));
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
        Status: Integer;
        Answer: Text;
    begin
        if Send(Url, User, Token, Body, Status, Answer) then;
    end;

    /// <summary>
    /// Posts one event; false when the monitoring URL could not be reached, else its status and body.
    /// </summary>
    [NonDebuggable]
    local procedure Send(Url: Text; User: Text; Token: Text; Body: Text; var Status: Integer; var Answer: Text): Boolean
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
        if not Client.Post(Url, Content, Response) then
            exit(false);
        Status := Response.HttpStatusCode();
        Response.Content().ReadAs(Answer);
        exit(true);
    end;

    /// <summary>
    /// Raised after an event was reported, whether or not the monitoring URL accepted it.
    /// </summary>
    [IntegrationEvent(false, false)]
    local procedure OnAfterReport(MonitoringEvent: JsonObject)
    begin
    end;
}
