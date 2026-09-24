// ABOUTME: Tests adding every table to the export: which tables are added, with which fields, and what is left alone.
// ABOUTME: Business data is exported in full; the extension's own tables and BC's system tables are not.
codeunit 85581 "ADLSE Add All Tables Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    trigger OnRun()
    begin
        // [FEATURE] bc2adls add all tables
    end;

    var
        ADLSELibrarybc2adls: Codeunit "ADLSE Library - bc2adls";
        LibraryAssert: Codeunit "Library Assert";
        "Storage Type": Enum "ADLSE Storage Type";
        IsInitialized: Boolean;

    [Test]
    procedure TestAddAllTables_AddsBusinessTablesWithTheirExportableFields()
    var
        ADLSETable: Record "ADLSE Table";
        ADLSEField: Record "ADLSE Field";
        ADLSESetup: Codeunit "ADLSE Setup";
        TableId: Integer;
    begin
        // [SCENARIO] Adding all tables exports the business tables, each with every field that can be exported
        // [GIVEN] An S3 setup exporting nothing yet
        Initialize();

        // [WHEN] All tables are added
        ADLSESetup.AddAllTables();

        // [THEN] Business tables of the base application are exported, enabled, with fields
        foreach TableId in BusinessTables() do begin
            LibraryAssert.IsTrue(ADLSETable.Get(TableId), StrSubstNo('Table %1 should be exported', TableId));
            LibraryAssert.IsTrue(ADLSETable.Enabled, StrSubstNo('Table %1 should be enabled', TableId));
            ADLSEField.SetRange("Table ID", TableId);
            ADLSEField.SetRange(Enabled, true);
            LibraryAssert.IsFalse(ADLSEField.IsEmpty(), StrSubstNo('Table %1 should have fields', TableId));
        end;
    end;

    [Test]
    procedure TestAddAllTables_LeavesOutTheExtensionsOwnAndSystemTables()
    var
        ADLSETable: Record "ADLSE Table";
        ADLSESetup: Codeunit "ADLSE Setup";
    begin
        // [SCENARIO] The extension's own tables change on every export, and system tables hold no business data
        // [GIVEN] An S3 setup exporting nothing yet
        Initialize();

        // [WHEN] All tables are added
        ADLSESetup.AddAllTables();

        // [THEN] Neither the extension's tables nor system tables are exported
        LibraryAssert.IsFalse(ADLSETable.Get(Database::"ADLSE Table"), 'The extension''s own table should not be exported');
        LibraryAssert.IsFalse(ADLSETable.Get(Database::"ADLSE Run"), 'The extension''s run log should not be exported');
        LibraryAssert.IsFalse(ADLSETable.Get(Database::Company), 'System tables should not be exported');
    end;

    [Test]
    procedure TestAddAllTables_LeavesOutLogsSchedulingAndOtherInfrastructure()
    var
        ADLSETable: Record "ADLSE Table";
        ADLSESetup: Codeunit "ADLSE Setup";
    begin
        // [SCENARIO] Tables that record how BC runs rather than the business are not exported
        // [GIVEN] An S3 setup exporting nothing yet
        Initialize();

        // [WHEN] All tables are added
        ADLSESetup.AddAllTables();

        // [THEN] Logs, scheduling and stored credentials are left out
        LibraryAssert.IsFalse(ADLSETable.Get(Database::"Change Log Entry"), 'The change log should not be exported');
        LibraryAssert.IsFalse(ADLSETable.Get(Database::"Job Queue Entry"), 'The job queue should not be exported');
        LibraryAssert.IsFalse(ADLSETable.Get(Database::"Job Queue Log Entry"), 'The job queue log should not be exported');
        LibraryAssert.IsFalse(ADLSETable.Get(Database::"Activity Log"), 'The activity log should not be exported');
        LibraryAssert.IsFalse(ADLSETable.Get(Database::"Isolated Certificate"), 'Stored certificates should not be exported');
        LibraryAssert.IsTrue(ADLSETable.Get(Database::Customer), 'Customers should still be exported');
    end;

    [Test]
    procedure TestAddAllTables_LeavesOutCopiesPersonalizationToolingAndDerivedTables()
    var
        ADLSETable: Record "ADLSE Table";
        ADLSESetup: Codeunit "ADLSE Setup";
    begin
        // [SCENARIO] Tables that are not business data are not exported: copies kept for BC's APIs, personal settings,
        // test and demo tooling, technical metadata, and tables BC derives from others
        // [GIVEN] An S3 setup exporting nothing yet
        Initialize();

        // [WHEN] All tables are added
        ADLSESetup.AddAllTables();

        // [THEN] They are left out, while the documents they copy are exported
        LibraryAssert.IsFalse(ADLSETable.Get(Database::"Sales Invoice Entity Aggregate"), 'API copy of sales invoices');
        LibraryAssert.IsFalse(ADLSETable.Get(Database::"My Customer"), 'personal customer list');
        LibraryAssert.IsFalse(ADLSETable.Get(Database::"Test Input"), 'test tooling');
        LibraryAssert.IsFalse(ADLSETable.Get(Database::"Tenant Web Service Columns"), 'technical metadata');
        LibraryAssert.IsFalse(ADLSETable.Get(Database::"Calendar Entry"), 'derived capacity calendar');
        LibraryAssert.IsTrue(ADLSETable.Get(Database::"Sales Invoice Header"), 'Sales invoices should still be exported');
    end;

    [Test]
    procedure TestAddAllTables_KeepsTheFieldsChosenForATableAlreadyExported()
    var
        ADLSETable: Record "ADLSE Table";
        ADLSEField: Record "ADLSE Field";
        ADLSESetup: Codeunit "ADLSE Setup";
        FieldsBefore: Integer;
    begin
        // [SCENARIO] A table already exported keeps the fields chosen for it
        // [GIVEN] Payment Terms exported with only its primary key
        Initialize();
        ADLSETable.Add(Database::"Payment Terms");
        ADLSEField.SetRange("Table ID", Database::"Payment Terms");
        ADLSEField.SetRange(Enabled, true);
        FieldsBefore := ADLSEField.Count();

        // [WHEN] All tables are added
        ADLSESetup.AddAllTables();

        // [THEN] Payment Terms still exports the same fields
        LibraryAssert.AreEqual(FieldsBefore, ADLSEField.Count(), 'The fields chosen for Payment Terms should be kept');
    end;

    [Test]
    procedure TestAddAllTables_ClearsTheSchemaExportDate()
    var
        ADLSESetupRecord: Record "ADLSE Setup";
        ADLSESetup: Codeunit "ADLSE Setup";
    begin
        // [SCENARIO] Adding tables changes the schema, so it has to be exported again
        // [GIVEN] A setup whose schema was exported
        Initialize();
        ADLSESetupRecord.Get(0);
        ADLSESetupRecord."Schema Exported On" := CurrentDateTime();
        ADLSESetupRecord.Modify();

        // [WHEN] All tables are added
        ADLSESetup.AddAllTables();

        // [THEN] The schema export date is cleared
        ADLSESetupRecord.Get(0);
        LibraryAssert.AreEqual(0DT, ADLSESetupRecord."Schema Exported On", 'Schema exported on');
    end;

    [Test]
    [HandlerFunctions('MessageHandler')]
    procedure TestSetupPage_AddAllTablesAction_AddsTheBusinessTables()
    var
        ADLSETable: Record "ADLSE Table";
        ADLSESetupPage: TestPage "ADLSE Setup";
    begin
        // [SCENARIO] Without the command line, all tables are added from the setup page
        // [GIVEN] An S3 setup exporting nothing yet
        Initialize();

        // [WHEN] Add all tables is chosen on the setup page
        ADLSESetupPage.OpenEdit();
        ADLSESetupPage.AddAllTables.Invoke();
        ADLSESetupPage.Close();

        // [THEN] The business tables are exported
        LibraryAssert.IsTrue(ADLSETable.Get(Database::Customer), 'Customers should be exported');
        LibraryAssert.IsTrue(ADLSETable.Get(Database::"G/L Entry"), 'G/L entries should be exported');
    end;

    [Test]
    [HandlerFunctions('MessageHandler')]
    procedure TestSetupPage_ScheduleEvery30MinutesAction_MakesAJobQueueEntryReadyToRun()
    var
        JobQueueEntry: Record "Job Queue Entry";
        ADLSESetupPage: TestPage "ADLSE Setup";
    begin
        // [SCENARIO] Without the command line, the export is scheduled from the setup page, ready to run
        // [GIVEN] An S3 setup
        Initialize();

        // [WHEN] Schedule every 30 minutes is chosen on the setup page
        ADLSESetupPage.OpenEdit();
        ADLSESetupPage.ScheduleEvery30Minutes.Invoke();
        ADLSESetupPage.Close();

        // [THEN] A recurring job queue entry runs the export every 30 minutes
        JobQueueEntry.SetRange("Object Type to Run", JobQueueEntry."Object Type to Run"::Report);
        JobQueueEntry.SetRange("Object ID to Run", Report::"ADLSE Schedule Task Assignment");
        JobQueueEntry.FindFirst();
        LibraryAssert.AreEqual(30, JobQueueEntry."No. of Minutes between Runs", 'minutes between runs');
        LibraryAssert.AreEqual(JobQueueEntry.Status::Ready, JobQueueEntry.Status, 'status');
        JobQueueEntry.DeleteAll(true);
    end;

    [MessageHandler]
    procedure MessageHandler(Message: Text[1024])
    begin
    end;

    local procedure BusinessTables() Tables: List of [Integer]
    begin
        Tables.Add(Database::"Payment Terms");
        Tables.Add(Database::Customer);
        Tables.Add(Database::"G/L Entry");
        Tables.Add(Database::"Sales Header");
    end;

    local procedure Initialize()
    var
        LibraryTestInitialize: Codeunit "Library - Test Initialize";
    begin
        LibraryTestInitialize.OnTestInitialize(Codeunit::"ADLSE Add All Tables Tests");
        ADLSELibrarybc2adls.CleanUp();
        ADLSELibrarybc2adls.CreateAdlseSetup("Storage Type"::S3);

        if IsInitialized then
            exit;

        LibraryTestInitialize.OnBeforeTestSuiteInitialize(Codeunit::"ADLSE Add All Tables Tests");

        IsInitialized := true;
        Commit();

        LibraryTestInitialize.OnAfterTestSuiteInitialize(Codeunit::"ADLSE Add All Tables Tests");
    end;
}
