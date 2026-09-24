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

    [HttpClientHandler]
    procedure S3Handler(Request: TestHttpRequestMessage; var Response: TestHttpResponseMessage): Boolean
    var
        Url: Text;
    begin
        Url := Request.Path();
        Requests.Add(Format(Request.RequestType()).ToUpper() + ' ' + Url);
        Response.HttpStatusCode := 200;
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
