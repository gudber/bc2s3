namespace bc2adls;
codeunit 82577 "ADLSE Wrapper Execute"
{
    Access = Internal;
    TableNo = "ADLSE Table";

    trigger OnRun()
    var
        ADLSEExecute: Codeunit "ADLSE Execute";
        ADLSEExecution: Codeunit "ADLSE Execution";
        ADLSEMonitor: Codeunit "ADLSE Monitor";
        CustomDimensions: Dictionary of [Text, Text];
    begin
        if not ADLSEExecute.Run(Rec) then begin
            ADLSEMonitor.ReportTableSessionFailed(Rec."Table ID", GetLastErrorText(), GetLastErrorCode(), GetLastErrorCallStack());
            CustomDimensions.Add('Entity', Format(Rec."Table ID"));
            CustomDimensions.Add('SessionId', Format(SessionId()));
            CustomDimensions.Add('AL Call Stack', GetLastErrorCallStack());
            CustomDimensions.Add('Last Error Code', GetLastErrorCode());
            CustomDimensions.Add('Last Error Text', GetLastErrorText());
            ADLSEExecution.Log('ADLSE-050', 'Session is failes to start', Verbosity::Normal, CustomDimensions);
        end;
    end;
}