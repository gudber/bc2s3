// ABOUTME: Starts the export for the scheduled job, so that the job can report an export that could not start
// ABOUTME: before failing its job queue entry with the same error.
namespace bc2adls;

codeunit 82587 "ADLSE Scheduled Export"
{
    Access = Internal;
    TableNo = "ADLSE Table";

    trigger OnRun()
    var
        ADLSEExecution: Codeunit "ADLSE Execution";
    begin
        ADLSEExecution.StartExport(Rec);
    end;
}
