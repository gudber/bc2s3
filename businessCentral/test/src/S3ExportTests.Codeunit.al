// ABOUTME: Tests exporting a table to S3-compatible storage end to end, with S3 answered by an HTTP handler.
// ABOUTME: Checks which objects are read and written: the entity schema and one delta object per flush.
codeunit 85580 "ADLSE S3 Export Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;
    TestHttpRequestPolicy = BlockOutboundRequests;

    trigger OnRun()
    begin
        // [FEATURE] bc2adls export to S3
    end;

    var
        ADLSETable: Record "ADLSE Table";
        ADLSELibrarybc2adls: Codeunit "ADLSE Library - bc2adls";
        LibraryAssert: Codeunit "Library Assert";
        LibraryERM: Codeunit "Library - ERM";
        "Storage Type": Enum "ADLSE Storage Type";
        IsInitialized: Boolean;
        Requests: List of [Text];
        EntityJson: Text;
        EntityUrlTok: Label 'https://fsn1.your-objectstorage.com/bc2adls/ReasonCode-231.cdm.json', Locked = true;
        DeltasPrefixTok: Label 'https://fsn1.your-objectstorage.com/bc2adls/deltas/ReasonCode-231/', Locked = true;
        MonitoringUrlTok: Label 'https://eu1-api.openobserve.ai/api/test-org/bc_export/_json', Locked = true;
        MonitoringStatus: Integer;

    [Test]
    [HandlerFunctions('S3Handler')]
    procedure TestExport_S3_WritesOneDeltaObjectNamedByTime()
    var
        ADLSERun: Record "ADLSE Run";
        ADLSEExecute: Codeunit "ADLSE Execute";
        DeltaUrl: Text;
        ObjectName: Text;
    begin
        // [SCENARIO] Exporting a table to S3 reads its schema and writes its records as one delta object
        // [GIVEN] Reason codes, exported to S3, whose schema is already in the bucket
        Initialize();
        SetUpReasonCodeExportToS3();

        // [WHEN] The table is exported
        ADLSEExecute.Run(ADLSETable);

        // [THEN] The export succeeded
        ADLSERun.SetRange("Table ID", Database::"Reason Code");
        ADLSERun.FindLast();
        LibraryAssert.AreEqual(ADLSERun.State::Success, ADLSERun.State, 'The export should succeed: ' + ADLSERun.Error);

        // [THEN] The schema was read, and one delta object was put under deltas/<entity>/, named <utc time>_<guid>.csv
        LibraryAssert.IsTrue(Requests.Contains('GET ' + EntityUrlTok), 'The schema should be read. Requests: ' + Format(Requests.Count()));
        DeltaUrl := SinglePutUnder(DeltasPrefixTok);
        ObjectName := CopyStr(DeltaUrl, StrLen(DeltasPrefixTok) + 1);
        LibraryAssert.IsTrue(ObjectName.EndsWith('.csv'), 'The delta should be a CSV: ' + ObjectName);
        LibraryAssert.AreEqual('T', CopyStr(ObjectName, 9, 1), 'The name should start with the UTC time: ' + ObjectName);
        LibraryAssert.AreEqual('Z_', CopyStr(ObjectName, 19, 2), 'The time should be followed by an underscore: ' + ObjectName);
    end;

    [Test]
    [HandlerFunctions('S3Handler')]
    procedure TestExport_S3_TouchesNoManifest()
    var
        ADLSEExecute: Codeunit "ADLSE Execute";
        Request: Text;
    begin
        // [SCENARIO] Exporting to S3 neither reads nor writes the CDM manifests, which need Azure's blob leases
        // [GIVEN] Reason codes, exported to S3, whose schema is already in the bucket
        Initialize();
        SetUpReasonCodeExportToS3();

        // [WHEN] The table is exported
        ADLSEExecute.Run(ADLSETable);

        // [THEN] No request concerned a manifest
        foreach Request in Requests do
            LibraryAssert.IsFalse(Request.Contains('manifest'), 'No manifest should be touched: ' + Request);
    end;

    [Test]
    [HandlerFunctions('S3Handler')]
    procedure TestExportSchema_S3_PutsEntitySchema()
    var
        ADLSEExecute: Codeunit "ADLSE Execute";
        Request: Text;
    begin
        // [SCENARIO] Exporting the schema to S3 puts the entity's .cdm.json and no manifest
        // [GIVEN] Reason codes, exported to S3, with no schema in the bucket yet
        Initialize();
        SetUpReasonCodeExportToS3();
        EntityJson := '';

        // [WHEN] The schema is exported
        ADLSEExecute.ExportSchema(Database::"Reason Code");

        // [THEN] The entity's schema was put, and no manifest was touched
        LibraryAssert.IsTrue(Requests.Contains('PUT ' + EntityUrlTok), 'The schema should be put. Requests: ' + Format(Requests.Count()));
        foreach Request in Requests do
            LibraryAssert.IsFalse(Request.Contains('manifest'), 'No manifest should be touched: ' + Request);
    end;

    [Test]
    [HandlerFunctions('S3Handler')]
    procedure TestExport_S3_EveryObjectStartsWithTheHeader()
    var
        ADLSESetup: Record "ADLSE Setup";
        ReasonCode: Record "Reason Code";
        ADLSEExecute: Codeunit "ADLSE Execute";
        ADLSES3PutRecorder: Codeunit "ADLSE S3 Put Recorder";
        Body: Text;
        Header: Text;
        i: Integer;
    begin
        // [SCENARIO] A table too big for one object is exported as several, and each starts with the CSV header
        // [GIVEN] Enough reason codes for more than one 1 MiB object
        Initialize();
        SetUpReasonCodeExportToS3();
        ADLSESetup.Get(0);
        ADLSESetup.MaxPayloadSizeMiB := 1;
        ADLSESetup.Modify();
        for i := 1 to 6000 do begin
            ReasonCode.Init();
            ReasonCode.Code := CopyStr(StrSubstNo('R%1', i), 1, MaxStrLen(ReasonCode.Code));
            ReasonCode.Description := PadStr('', MaxStrLen(ReasonCode.Description), 'x');
            ReasonCode.Insert();
        end;

        // [WHEN] The table is exported
        BindSubscription(ADLSES3PutRecorder);
        ADLSEExecute.Run(ADLSETable);
        UnbindSubscription(ADLSES3PutRecorder);

        // [THEN] It took several objects, each starting with the same header
        LibraryAssert.IsTrue(ADLSES3PutRecorder.CsvBodies().Count() > 1, 'The export should need more than one object');
        Header := ADLSES3PutRecorder.CsvBodies().Get(1).Split(CRLF()).Get(1);
        LibraryAssert.IsTrue(Header.StartsWith('Code-1,'), 'The first object should start with the header: ' + Header);
        foreach Body in ADLSES3PutRecorder.CsvBodies() do
            LibraryAssert.AreEqual(Header, Body.Split(CRLF()).Get(1), 'Every object should start with the header');
    end;

    local procedure CRLF() Result: Text[2]
    begin
        Result[1] := 13;
        Result[2] := 10;
    end;

    [Test]
    [HandlerFunctions('S3Handler')]
    procedure TestExport_ReportsTheTablesRunToTheMonitoringUrl()
    var
        ADLSEExecute: Codeunit "ADLSE Execute";
        ADLSEMonitorRecorder: Codeunit "ADLSE Monitor Recorder";
        Reported: JsonObject;
        Token: JsonToken;
    begin
        // [SCENARIO] Each table's export is reported to the monitoring URL: which table, how it went, how many records
        // [GIVEN] Three reason codes exported to S3, with a monitoring URL
        Initialize();
        SetUpReasonCodeExportToS3();
        SetMonitoring(200);

        // [WHEN] The table is exported
        BindSubscription(ADLSEMonitorRecorder);
        ADLSEExecute.Run(ADLSETable);
        UnbindSubscription(ADLSEMonitorRecorder);

        // [THEN] One event was posted to the monitoring URL, saying the table was exported with its three records
        LibraryAssert.IsTrue(Requests.Contains('POST ' + MonitoringUrlTok), 'The run should be reported to the monitoring URL');
        LibraryAssert.AreEqual(1, ADLSEMonitorRecorder.Reported().Count(), 'reported events');
        Reported.ReadFrom(ADLSEMonitorRecorder.Reported().Get(1));
        Reported.Get('event', Token);
        LibraryAssert.AreEqual('table_exported', Token.AsValue().AsText(), 'event');
        Reported.Get('table_id', Token);
        LibraryAssert.AreEqual(Database::"Reason Code", Token.AsValue().AsInteger(), 'table_id');
        Reported.Get('state', Token);
        LibraryAssert.AreEqual('Success', Token.AsValue().AsText(), 'state');
        Reported.Get('records', Token);
        LibraryAssert.AreEqual(3, Token.AsValue().AsInteger(), 'records');
        Reported.Get('company', Token);
        LibraryAssert.AreEqual(CompanyName(), Token.AsValue().AsText(), 'company');
    end;

    [Test]
    [HandlerFunctions('S3Handler')]
    procedure TestExport_SucceedsWhenTheMonitoringUrlFails()
    var
        ADLSERun: Record "ADLSE Run";
        ADLSEExecute: Codeunit "ADLSE Execute";
    begin
        // [SCENARIO] Monitoring must never stop the data: a failing monitoring URL does not fail the export
        // [GIVEN] Reason codes exported to S3, with a monitoring URL that answers 500
        Initialize();
        SetUpReasonCodeExportToS3();
        SetMonitoring(500);

        // [WHEN] The table is exported
        ADLSEExecute.Run(ADLSETable);

        // [THEN] The export succeeded and its delta was written
        ADLSERun.SetRange("Table ID", Database::"Reason Code");
        ADLSERun.FindLast();
        LibraryAssert.AreEqual(ADLSERun.State::Success, ADLSERun.State, 'The export should succeed: ' + ADLSERun.Error);
        SinglePutUnder(DeltasPrefixTok);
    end;

    [Test]
    [HandlerFunctions('S3Handler')]
    procedure TestExport_WithoutMonitoringUrlReportsNothing()
    var
        ADLSEExecute: Codeunit "ADLSE Execute";
        Request: Text;
    begin
        // [SCENARIO] Monitoring is off until a monitoring URL is set
        // [GIVEN] Reason codes exported to S3, without a monitoring URL
        Initialize();
        SetUpReasonCodeExportToS3();

        // [WHEN] The table is exported
        ADLSEExecute.Run(ADLSETable);

        // [THEN] Nothing but S3 was called
        foreach Request in Requests do
            LibraryAssert.IsTrue(Request.Contains('your-objectstorage.com'), 'Only S3 should be called: ' + Request);
    end;

    [Test]
    [HandlerFunctions('S3Handler,ExportStartedMessageHandler')]
    procedure TestStartExport_ReportsThatTheExportStarted()
    var
        ADLSEExecution: Codeunit "ADLSE Execution";
        ADLSEMonitorRecorder: Codeunit "ADLSE Monitor Recorder";
        Reported: JsonObject;
        Token: JsonToken;
    begin
        // [SCENARIO] Every export reports that it started, even when no table has changes, so a stopped schedule shows
        // [GIVEN] An S3 export with a monitoring URL and no tables
        Initialize();
        SetUpReasonCodeExportToS3();
        ADLSETable.Delete(true);
        SetMonitoring(200);

        // [WHEN] The export starts
        BindSubscription(ADLSEMonitorRecorder);
        ADLSEExecution.StartExport();
        UnbindSubscription(ADLSEMonitorRecorder);

        // [THEN] It reported that it started no tables of none enabled
        LibraryAssert.AreEqual(1, ADLSEMonitorRecorder.Reported().Count(), 'reported events');
        Reported.ReadFrom(ADLSEMonitorRecorder.Reported().Get(1));
        Reported.Get('event', Token);
        LibraryAssert.AreEqual('export_started', Token.AsValue().AsText(), 'event');
        Reported.Get('tables_started', Token);
        LibraryAssert.AreEqual(0, Token.AsValue().AsInteger(), 'tables_started');
        Reported.Get('tables_enabled', Token);
        LibraryAssert.AreEqual(0, Token.AsValue().AsInteger(), 'tables_enabled');
    end;

    [MessageHandler]
    procedure ExportStartedMessageHandler(Message: Text[1024])
    begin
    end;

    local procedure SetMonitoring(Status: Integer)
    var
        ADLSESetup: Record "ADLSE Setup";
        ADLSECredentials: Codeunit "ADLSE Credentials";
    begin
        ADLSESetup.Get(0);
        ADLSESetup."Monitoring URL" := MonitoringUrlTok;
        ADLSESetup."Monitoring User" := 'test-org';
        ADLSESetup.Modify();
        ADLSECredentials.SetMonitoringToken('o2oi_test');
        MonitoringStatus := Status;
    end;

    [HttpClientHandler]
    procedure S3Handler(Request: TestHttpRequestMessage; var Response: TestHttpResponseMessage): Boolean
    var
        Url: Text;
    begin
        Url := Request.Path();
        Requests.Add(Format(Request.RequestType()).ToUpper() + ' ' + Url);
        Response.HttpStatusCode := 200;
        if Url = MonitoringUrlTok then begin
            Response.HttpStatusCode := MonitoringStatus;
            exit(false);
        end;
        if Request.RequestType() = HttpRequestType::Get then
            if (Url = EntityUrlTok) and (EntityJson <> '') then
                Response.Content.WriteFrom(EntityJson)
            else
                Response.HttpStatusCode := 404;
        exit(false);
    end;

    local procedure SetUpReasonCodeExportToS3()
    var
        ReasonCode: Record "Reason Code";
        ADLSECredentials: Codeunit "ADLSE Credentials";
        ADLSESessionManager: Codeunit "ADLSE Session Manager";
        i: Integer;
    begin
        ADLSELibrarybc2adls.CleanUp();
        ADLSESessionManager.SavePendingTables('');
        Clear(Requests);

        ReasonCode.DeleteAll(false);
        for i := 1 to 3 do
            LibraryERM.CreateReasonCode(ReasonCode);

        ADLSELibrarybc2adls.CreateAdlseSetup("Storage Type"::S3);
        ADLSECredentials.SetClientID('AKIAIOSFODNN7EXAMPLE');
        ADLSECredentials.SetClientSecret('wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY');

        ADLSETable.Add(Database::"Reason Code");
        ADLSELibrarybc2adls.InsertFields();
        ADLSELibrarybc2adls.EnableFields();
        EntityJson := ADLSELibrarybc2adls.GetExpectedEntityJson(Database::"Reason Code");
    end;

    local procedure SinglePutUnder(Prefix: Text) Url: Text
    var
        Request: Text;
        Found: Integer;
    begin
        foreach Request in Requests do
            if Request.StartsWith('PUT ' + Prefix) then begin
                Url := CopyStr(Request, StrLen('PUT ') + 1);
                Found += 1;
            end;
        LibraryAssert.AreEqual(1, Found, 'There should be exactly one object put under ' + Prefix);
    end;

    local procedure Initialize()
    var
        LibraryTestInitialize: Codeunit "Library - Test Initialize";
    begin
        LibraryTestInitialize.OnTestInitialize(Codeunit::"ADLSE S3 Export Tests");

        if IsInitialized then
            exit;

        LibraryTestInitialize.OnBeforeTestSuiteInitialize(Codeunit::"ADLSE S3 Export Tests");

        IsInitialized := true;
        Commit();

        LibraryTestInitialize.OnAfterTestSuiteInitialize(Codeunit::"ADLSE S3 Export Tests");
    end;
}
