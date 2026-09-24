// ABOUTME: Tests the export window, the time of day scheduled exports may run in (e.g. 20:00-06:00), and scheduling them.
// ABOUTME: A window may span midnight; without one, scheduled exports run whenever the job queue starts them.
codeunit 85582 "ADLSE Export Window Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    trigger OnRun()
    begin
        // [FEATURE] bc2adls export window
    end;

    var
        ADLSELibrarybc2adls: Codeunit "ADLSE Library - bc2adls";
        LibraryAssert: Codeunit "Library Assert";
        "Storage Type": Enum "ADLSE Storage Type";
        IsInitialized: Boolean;

    [Test]
    procedure TestNoWindow_EveryTimeOfDayIsInside()
    var
        ADLSESetup: Record "ADLSE Setup";
    begin
        // [SCENARIO] Without a window, scheduled exports may run at any time
        Initialize();
        ADLSESetup.Get(0);

        LibraryAssert.IsTrue(ADLSESetup.IsWithinExportWindow(000000T), 'midnight');
        LibraryAssert.IsTrue(ADLSESetup.IsWithinExportWindow(120000T), 'noon');
        LibraryAssert.IsFalse(ADLSESetup.HasExportWindow(), 'no window');
    end;

    [Test]
    procedure TestNightWindow_SpansMidnightAndEndsBeforeItsEnd()
    var
        ADLSESetup: Record "ADLSE Setup";
    begin
        // [SCENARIO] A window from 20:00 to 06:00 covers the night, up to but not including 06:00
        Initialize();
        SetWindow(ADLSESetup, 200000T, 060000T);

        LibraryAssert.IsTrue(ADLSESetup.IsWithinExportWindow(200000T), '20:00');
        LibraryAssert.IsTrue(ADLSESetup.IsWithinExportWindow(233000T), '23:30');
        LibraryAssert.IsTrue(ADLSESetup.IsWithinExportWindow(000000T), '00:00');
        LibraryAssert.IsTrue(ADLSESetup.IsWithinExportWindow(055959T), '05:59:59');
        LibraryAssert.IsFalse(ADLSESetup.IsWithinExportWindow(060000T), '06:00');
        LibraryAssert.IsFalse(ADLSESetup.IsWithinExportWindow(120000T), '12:00');
        LibraryAssert.IsFalse(ADLSESetup.IsWithinExportWindow(195959T), '19:59:59');
    end;

    [Test]
    procedure TestDayWindow_CoversOnlyItsHours()
    var
        ADLSESetup: Record "ADLSE Setup";
    begin
        // [SCENARIO] A window within one day, e.g. 01:00 to 05:00 for a shop that closes late
        Initialize();
        SetWindow(ADLSESetup, 010000T, 050000T);

        LibraryAssert.IsTrue(ADLSESetup.IsWithinExportWindow(010000T), '01:00');
        LibraryAssert.IsTrue(ADLSESetup.IsWithinExportWindow(045959T), '04:59:59');
        LibraryAssert.IsFalse(ADLSESetup.IsWithinExportWindow(050000T), '05:00');
        LibraryAssert.IsFalse(ADLSESetup.IsWithinExportWindow(003000T), '00:30');
        LibraryAssert.IsFalse(ADLSESetup.IsWithinExportWindow(230000T), '23:00');
        LibraryAssert.IsTrue(ADLSESetup.HasExportWindow(), 'a window');
    end;

    [Test]
    procedure TestScheduleExport_KeepsOneRecurringJobQueueEntryReadyToRun()
    var
        JobQueueEntry: Record "Job Queue Entry";
        ADLSESetupCodeunit: Codeunit "ADLSE Setup";
    begin
        // [SCENARIO] Scheduling exports every 30 minutes makes one recurring job queue entry, however often it is done
        Initialize();

        // [WHEN] The export is scheduled twice
        ADLSESetupCodeunit.ScheduleExport(30);
        ADLSESetupCodeunit.ScheduleExport(30);

        // [THEN] One job queue entry runs the scheduled export every 30 minutes, every day
        JobQueueEntry.SetRange("Object Type to Run", JobQueueEntry."Object Type to Run"::Report);
        JobQueueEntry.SetRange("Object ID to Run", Report::"ADLSE Schedule Task Assignment");
        LibraryAssert.AreEqual(1, JobQueueEntry.Count(), 'job queue entries');
        JobQueueEntry.FindFirst();
        LibraryAssert.IsTrue(JobQueueEntry."Recurring Job", 'recurring');
        LibraryAssert.AreEqual(30, JobQueueEntry."No. of Minutes between Runs", 'minutes between runs');
        LibraryAssert.IsTrue(JobQueueEntry."Run on Sundays" and JobQueueEntry."Run on Saturdays" and JobQueueEntry."Run on Mondays", 'every day');
        LibraryAssert.AreEqual(JobQueueEntry.Status::Ready, JobQueueEntry.Status, 'status');
        JobQueueEntry.DeleteAll(true);
    end;

    local procedure SetWindow(var ADLSESetup: Record "ADLSE Setup"; WindowStart: Time; WindowEnd: Time)
    begin
        ADLSESetup.Get(0);
        ADLSESetup.Validate("Export Window Start", WindowStart);
        ADLSESetup.Validate("Export Window End", WindowEnd);
        ADLSESetup.Modify();
    end;

    local procedure Initialize()
    var
        LibraryTestInitialize: Codeunit "Library - Test Initialize";
    begin
        LibraryTestInitialize.OnTestInitialize(Codeunit::"ADLSE Export Window Tests");
        ADLSELibrarybc2adls.CleanUp();
        ADLSELibrarybc2adls.CreateAdlseSetup("Storage Type"::S3);

        if IsInitialized then
            exit;

        LibraryTestInitialize.OnBeforeTestSuiteInitialize(Codeunit::"ADLSE Export Window Tests");

        IsInitialized := true;
        Commit();

        LibraryTestInitialize.OnAfterTestSuiteInitialize(Codeunit::"ADLSE Export Window Tests");
    end;
}
