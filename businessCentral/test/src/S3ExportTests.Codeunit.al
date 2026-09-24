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
        PutStatus: Integer;

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
        ADLSERun: Record "ADLSE Run";
        ADLSEExecute: Codeunit "ADLSE Execute";
        ADLSEMonitorRecorder: Codeunit "ADLSE Monitor Recorder";
        Reported: JsonObject;
    begin
        // [SCENARIO] Each table's export is reported to the monitoring URL: which table, how it went, what was sent
        // [GIVEN] Three reason codes exported to S3, with a monitoring URL
        Initialize();
        SetUpReasonCodeExportToS3();
        SetMonitoring(200);

        // [WHEN] The table is exported
        BindSubscription(ADLSEMonitorRecorder);
        ADLSEExecute.Run(ADLSETable);
        UnbindSubscription(ADLSEMonitorRecorder);

        // [THEN] The run was posted to the monitoring URL with its table, outcome, records and progress
        LibraryAssert.IsTrue(Requests.Contains('POST ' + MonitoringUrlTok), 'The run should be reported to the monitoring URL');
        Reported := ADLSEMonitorRecorder.Single('table_exported');
        ADLSERun.SetRange("Table ID", Database::"Reason Code");
        ADLSERun.FindLast();
        LibraryAssert.AreEqual(Database::"Reason Code", ADLSEMonitorRecorder.Value(Reported, 'table_id').AsInteger(), 'table_id');
        LibraryAssert.AreEqual('Reason Code', ADLSEMonitorRecorder.Value(Reported, 'table_caption').AsText(), 'table_caption');
        LibraryAssert.AreEqual('Success', ADLSEMonitorRecorder.Value(Reported, 'state').AsText(), 'state');
        LibraryAssert.AreEqual(ADLSERun.ID, ADLSEMonitorRecorder.Value(Reported, 'run_id').AsInteger(), 'run_id');
        LibraryAssert.AreEqual(3, ADLSEMonitorRecorder.Value(Reported, 'records').AsInteger(), 'records');
        LibraryAssert.AreEqual(3, ADLSEMonitorRecorder.Value(Reported, 'records_updated').AsInteger(), 'records_updated');
        LibraryAssert.AreEqual(0, ADLSEMonitorRecorder.Value(Reported, 'records_deleted').AsInteger(), 'records_deleted');
        LibraryAssert.AreEqual(0, ADLSEMonitorRecorder.Value(Reported, 'records_delayed').AsInteger(), 'records_delayed');
        LibraryAssert.AreEqual(1, ADLSEMonitorRecorder.Value(Reported, 'objects_written').AsInteger(), 'objects_written');
        LibraryAssert.AreEqual(0, ADLSEMonitorRecorder.Value(Reported, 'timestamp_before').AsBigInteger(), 'timestamp_before');
        LibraryAssert.IsTrue(ADLSEMonitorRecorder.Value(Reported, 'timestamp_after').AsBigInteger() > 0, 'timestamp_after');
        LibraryAssert.IsFalse(ADLSEMonitorRecorder.Value(Reported, 'stopped_at_window_end').AsBoolean(), 'stopped_at_window_end');
        LibraryAssert.AreEqual('', ADLSEMonitorRecorder.Value(Reported, 'error').AsText(), 'error');
        AssertDescribesThisSession(ADLSEMonitorRecorder, Reported);
    end;

    [Test]
    [HandlerFunctions('S3Handler')]
    procedure TestExport_ReportsEachObjectWritten()
    var
        ADLSEExecute: Codeunit "ADLSE Execute";
        ADLSEMonitorRecorder: Codeunit "ADLSE Monitor Recorder";
        Reported: JsonObject;
    begin
        // [SCENARIO] Each object put in the bucket is reported, so a delta in the bucket can be traced to its export
        // [GIVEN] Three reason codes exported to S3, with a monitoring URL
        Initialize();
        SetUpReasonCodeExportToS3();
        SetMonitoring(200);

        // [WHEN] The table is exported
        BindSubscription(ADLSEMonitorRecorder);
        ADLSEExecute.Run(ADLSETable);
        UnbindSubscription(ADLSEMonitorRecorder);

        // [THEN] The one delta object is reported with its path in the bucket, its length and its records
        Reported := ADLSEMonitorRecorder.Single('object_written');
        LibraryAssert.AreEqual(SinglePutUnder(DeltasPrefixTok), 'https://fsn1.your-objectstorage.com/bc2adls' + ADLSEMonitorRecorder.Value(Reported, 'path').AsText(), 'path');
        LibraryAssert.AreEqual(Database::"Reason Code", ADLSEMonitorRecorder.Value(Reported, 'table_id').AsInteger(), 'table_id');
        LibraryAssert.AreEqual(3, ADLSEMonitorRecorder.Value(Reported, 'records').AsInteger(), 'records');
        LibraryAssert.IsTrue(ADLSEMonitorRecorder.Value(Reported, 'characters').AsInteger() > 0, 'characters');
    end;

    [Test]
    [HandlerFunctions('S3Handler')]
    procedure TestExport_ReportsDeletedRecords()
    var
        ReasonCode: Record "Reason Code";
        ADLSEExecute: Codeunit "ADLSE Execute";
        ADLSEMonitorRecorder: Codeunit "ADLSE Monitor Recorder";
        Reported: JsonObject;
    begin
        // [SCENARIO] Deletes are counted apart from updates
        // [GIVEN] Three reason codes exported to S3, then one of them deleted
        Initialize();
        SetUpReasonCodeExportToS3();
        SetMonitoring(200);
        ADLSEExecute.Run(ADLSETable);
        ReasonCode.FindFirst();
        ReasonCode.Delete(true);

        // [WHEN] The table is exported again
        BindSubscription(ADLSEMonitorRecorder);
        ADLSEExecute.Run(ADLSETable);
        UnbindSubscription(ADLSEMonitorRecorder);

        // [THEN] The run reports one deleted record and no updates
        Reported := ADLSEMonitorRecorder.Single('table_exported');
        LibraryAssert.AreEqual(0, ADLSEMonitorRecorder.Value(Reported, 'records_updated').AsInteger(), 'records_updated');
        LibraryAssert.AreEqual(1, ADLSEMonitorRecorder.Value(Reported, 'records_deleted').AsInteger(), 'records_deleted');
        LibraryAssert.IsTrue(ADLSEMonitorRecorder.Value(Reported, 'deleted_entry_after').AsBigInteger() > 0, 'deleted_entry_after');
    end;

    [Test]
    [HandlerFunctions('S3Handler')]
    procedure TestExport_ReportsTheErrorOfAFailedRun()
    var
        ADLSEExecute: Codeunit "ADLSE Execute";
        ADLSEMonitorRecorder: Codeunit "ADLSE Monitor Recorder";
        Reported: JsonObject;
    begin
        // [SCENARIO] A failed run is reported with the storage's answer, so it can be diagnosed from the monitoring
        // [GIVEN] Reason codes exported to S3, where the bucket refuses the put
        Initialize();
        SetUpReasonCodeExportToS3();
        SetMonitoring(200);
        PutStatus := 403;

        // [WHEN] The table is exported
        BindSubscription(ADLSEMonitorRecorder);
        ADLSEExecute.Run(ADLSETable);
        UnbindSubscription(ADLSEMonitorRecorder);

        // [THEN] The run is reported failed, with the status S3 answered
        Reported := ADLSEMonitorRecorder.Single('table_exported');
        LibraryAssert.AreEqual('Failed', ADLSEMonitorRecorder.Value(Reported, 'state').AsText(), 'state');
        LibraryAssert.IsTrue(ADLSEMonitorRecorder.Value(Reported, 'error').AsText().Contains('403'), 'error: ' + ADLSEMonitorRecorder.Value(Reported, 'error').AsText());
    end;

    [Test]
    [HandlerFunctions('S3Handler')]
    procedure TestExport_ReportsASessionThatCouldNotExport()
    var
        ADLSECurrentSession: Record "ADLSE Current Session";
        ADLSEWrapperExecute: Codeunit "ADLSE Wrapper Execute";
        ADLSEMonitorRecorder: Codeunit "ADLSE Monitor Recorder";
        Reported: JsonObject;
    begin
        // [SCENARIO] An export session that fails before it can register its run is still reported, with its error
        // [GIVEN] Reason codes exported to S3, while this session already holds the table's export
        Initialize();
        SetUpReasonCodeExportToS3();
        SetMonitoring(200);
        ADLSECurrentSession.Start(Database::"Reason Code");
        Commit();

        // [WHEN] An export session runs for the table
        BindSubscription(ADLSEMonitorRecorder);
        ADLSEWrapperExecute.Run(ADLSETable);
        UnbindSubscription(ADLSEMonitorRecorder);

        // [THEN] It reported that it failed, and why
        Reported := ADLSEMonitorRecorder.Single('table_session_failed');
        LibraryAssert.AreEqual(Database::"Reason Code", ADLSEMonitorRecorder.Value(Reported, 'table_id').AsInteger(), 'table_id');
        LibraryAssert.AreNotEqual('', ADLSEMonitorRecorder.Value(Reported, 'error').AsText(), 'error');
        LibraryAssert.AreNotEqual('', ADLSEMonitorRecorder.Value(Reported, 'call_stack').AsText(), 'call_stack');
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
        ADLSESetup: Record "ADLSE Setup";
        ADLSEExecution: Codeunit "ADLSE Execution";
        ADLSEMonitorRecorder: Codeunit "ADLSE Monitor Recorder";
        Reported: JsonObject;
    begin
        // [SCENARIO] Every export reports that it started and with which settings, even when no table has changes
        // [GIVEN] An S3 export with a monitoring URL, an export window and no tables
        Initialize();
        SetUpReasonCodeExportToS3();
        ADLSETable.Delete(true);
        SetMonitoring(200);
        ADLSESetup.Get(0);
        ADLSESetup."Export Window Start" := 000000T;
        ADLSESetup."Export Window End" := 235959T;
        ADLSESetup."Delayed Export" := 900;
        ADLSESetup.Modify();

        // [WHEN] The export starts
        BindSubscription(ADLSEMonitorRecorder);
        ADLSEExecution.StartExport();
        UnbindSubscription(ADLSEMonitorRecorder);

        // [THEN] It reported that it started no tables of none enabled, and the settings it ran with
        Reported := ADLSEMonitorRecorder.Single('export_started');
        LibraryAssert.AreEqual(0, ADLSEMonitorRecorder.Value(Reported, 'tables_started').AsInteger(), 'tables_started');
        LibraryAssert.AreEqual(0, ADLSEMonitorRecorder.Value(Reported, 'tables_enabled').AsInteger(), 'tables_enabled');
        LibraryAssert.AreEqual('', ADLSEMonitorRecorder.Value(Reported, 'tables_unreadable').AsText(), 'tables_unreadable');
        LibraryAssert.AreEqual('00:00:00', ADLSEMonitorRecorder.Value(Reported, 'export_window_start').AsText(), 'export_window_start');
        LibraryAssert.AreEqual('23:59:59', ADLSEMonitorRecorder.Value(Reported, 'export_window_end').AsText(), 'export_window_end');
        LibraryAssert.AreEqual(900, ADLSEMonitorRecorder.Value(Reported, 'delayed_export_seconds').AsInteger(), 'delayed_export_seconds');
        AssertDescribesThisSession(ADLSEMonitorRecorder, Reported);
    end;

    [Test]
    [HandlerFunctions('S3Handler')]
    procedure TestScheduledExport_ReportsASkipOutsideTheWindow()
    var
        ADLSESetup: Record "ADLSE Setup";
        ADLSEMonitorRecorder: Codeunit "ADLSE Monitor Recorder";
        Reported: JsonObject;
    begin
        // [SCENARIO] A scheduled export outside its window reports that it skipped, so a quiet day is told from a stopped schedule
        // [GIVEN] An S3 export with a monitoring URL and an export window that does not include now
        Initialize();
        SetUpReasonCodeExportToS3();
        SetMonitoring(200);
        ADLSESetup.Get(0);
        if DT2Time(CurrentDateTime()) < 120000T then begin
            ADLSESetup."Export Window Start" := 130000T;
            ADLSESetup."Export Window End" := 140000T;
        end else begin
            ADLSESetup."Export Window Start" := 010000T;
            ADLSESetup."Export Window End" := 020000T;
        end;
        ADLSESetup.Modify();

        // [WHEN] The scheduled export runs
        BindSubscription(ADLSEMonitorRecorder);
        Report.Run(Report::"ADLSE Schedule Task Assignment", false);
        UnbindSubscription(ADLSEMonitorRecorder);

        // [THEN] It reported the skip, and did not start
        Reported := ADLSEMonitorRecorder.Single('export_skipped');
        LibraryAssert.AreEqual(Format(ADLSESetup."Export Window Start", 0, 9), ADLSEMonitorRecorder.Value(Reported, 'export_window_start').AsText(), 'export_window_start');
        LibraryAssert.AreEqual(0, ADLSEMonitorRecorder.Count('export_started'), 'export_started');
    end;

    [Test]
    [HandlerFunctions('S3Handler')]
    procedure TestScheduledExport_ReportsWhyItCouldNotStart()
    var
        ADLSESetup: Record "ADLSE Setup";
        ADLSEMonitorRecorder: Codeunit "ADLSE Monitor Recorder";
        Reported: JsonObject;
    begin
        // [SCENARIO] A scheduled export that cannot start reports why, and still fails its job queue entry
        // [GIVEN] An S3 export with a monitoring URL but no bucket
        Initialize();
        SetUpReasonCodeExportToS3();
        SetMonitoring(200);
        ADLSESetup.Get(0);
        ADLSESetup."S3 Bucket" := '';
        ADLSESetup.Modify();
        Commit();

        // [WHEN] The scheduled export runs
        BindSubscription(ADLSEMonitorRecorder);
        asserterror Report.Run(Report::"ADLSE Schedule Task Assignment", false);
        UnbindSubscription(ADLSEMonitorRecorder);

        // [THEN] It failed, and reported the same error
        Reported := ADLSEMonitorRecorder.Single('export_failed');
        LibraryAssert.AreEqual(GetLastErrorText(), ADLSEMonitorRecorder.Value(Reported, 'error').AsText(), 'error');
        LibraryAssert.IsTrue(GetLastErrorText().Contains('S3 bucket'), 'The error should name the missing bucket: ' + GetLastErrorText());
        LibraryAssert.AreNotEqual('', ADLSEMonitorRecorder.Value(Reported, 'call_stack').AsText(), 'call_stack');
    end;

    [MessageHandler]
    procedure ExportStartedMessageHandler(Message: Text[1024])
    begin
    end;

    local procedure AssertDescribesThisSession(ADLSEMonitorRecorder: Codeunit "ADLSE Monitor Recorder"; Reported: JsonObject)
    var
        ModuleInfo: ModuleInfo;
    begin
        NavApp.GetModuleInfo('efbd8e9d-3612-4996-bb16-784208b15e1d', ModuleInfo);
        LibraryAssert.AreEqual(Format(ModuleInfo.AppVersion()), ADLSEMonitorRecorder.Value(Reported, 'app_version').AsText(), 'app_version');
        LibraryAssert.AreEqual(CompanyName(), ADLSEMonitorRecorder.Value(Reported, 'company').AsText(), 'company');
        LibraryAssert.AreEqual(SessionId(), ADLSEMonitorRecorder.Value(Reported, 'session_id').AsInteger(), 'session_id');
        LibraryAssert.AreEqual(UserId(), ADLSEMonitorRecorder.Value(Reported, 'user_id').AsText(), 'user_id');
        LibraryAssert.AreEqual('bc2adls', ADLSEMonitorRecorder.Value(Reported, 's3_bucket').AsText(), 's3_bucket');
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
        if (Request.RequestType() = HttpRequestType::Put) and (PutStatus <> 0) then
            Response.HttpStatusCode := PutStatus;
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
        Clear(PutStatus);
        Clear(MonitoringStatus);

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
