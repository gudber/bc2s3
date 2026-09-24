// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License. See LICENSE in the project root for license information.
namespace bc2adls;

using Microsoft.CRM.Outlook;
using Microsoft.EServices.EDocument;
using Microsoft.Integration.SyncEngine;
using Microsoft.Utilities;
using System.Diagnostics;
using System.Environment.Configuration;
using System.Reflection;
using System.Security.Encryption;
using System.Threading;
using System.Utilities;
codeunit 82560 "ADLSE Setup"
{
    Access = Internal;

    var
        JobQueueCategoryTok: Label 'ADLSE', Locked = true;
        ScheduledExportLbl: Label 'Malia Data Silo Export', MaxLength = 30;
        FieldClassNotSupportedErr: Label 'The field %1 of class %2 is not supported.', Comment = '%1 = field name, %2 = field class';
        SelectTableLbl: Label 'Select the tables to be exported';
        FieldObsoleteNotSupportedErr: Label 'The field %1 is obsolete', Comment = '%1 = field name';
        FieldDisabledNotSupportedErr: Label 'The field %1 is disabled', Comment = '%1 = field name';

    /// <summary>
    /// Exports every business table with all the fields that can be exported. Tables already exported keep the
    /// fields chosen for them. Left out: this extension's own tables, which change on every export, BC's system
    /// tables, the infrastructure tables below, and tables that are not normal tables or have been removed. Adding tables changes the schema, so the
    /// schema export date is cleared.
    /// </summary>
    procedure AddAllTables()
    var
        ADLSETable: Record "ADLSE Table";
        AllObj: Record AllObj;
        TableMetadata: Record "Table Metadata";
        ADLSEExecution: Codeunit "ADLSE Execution";
        ThisExtension: ModuleInfo;
    begin
        NavApp.GetCurrentModuleInfo(ThisExtension);
        ADLSEExecution.ClearSchemaExportDate();

        AllObj.SetRange("Object Type", AllObj."Object Type"::Table);
        AllObj.SetFilter("Object ID", '<%1', 2000000000); // BC's system tables start at 2000000000
        AllObj.SetFilter("App Package ID", '<>%1', ThisExtension.PackageId);
        if AllObj.FindSet() then
            repeat
                if not ADLSETable.Get(AllObj."Object ID") then
                    if not IsInfrastructure(AllObj."Object ID") then
                        if TableMetadata.Get(AllObj."Object ID") then
                            if TableMetadata.TableType = TableMetadata.TableType::Normal then
                                if TableMetadata.ObsoleteState <> TableMetadata.ObsoleteState::Removed then begin
                                    ADLSETable.Init();
                                    ADLSETable."Table ID" := AllObj."Object ID";
                                    ADLSETable.Enabled := true;
                                    ADLSETable.Insert(true);
                                    ADLSETable.AddAllFields();
                                end;
            until AllObj.Next() = 0;
    end;

    /// <summary>
    /// Keeps one recurring job queue entry that starts the scheduled export every given number of minutes, every day,
    /// and sets it ready to run. The export window decides when those runs actually export.
    /// </summary>
    procedure ScheduleExport(MinutesBetweenRuns: Integer)
    var
        JobQueueEntry: Record "Job Queue Entry";
        JobQueueCategory: Record "Job Queue Category";
    begin
        JobQueueEntry.SetRange("Object Type to Run", JobQueueEntry."Object Type to Run"::Report);
        JobQueueEntry.SetRange("Object ID to Run", Report::"ADLSE Schedule Task Assignment");
        if not JobQueueEntry.FindFirst() then begin
            JobQueueCategory.InsertRec(JobQueueCategoryTok, ScheduledExportLbl);
            JobQueueEntry.Init();
            JobQueueEntry.Validate("Object Type to Run", JobQueueEntry."Object Type to Run"::Report);
            JobQueueEntry.Validate("Object ID to Run", Report::"ADLSE Schedule Task Assignment");
            JobQueueEntry.Insert(true);
        end else
            JobQueueEntry.SetStatus(JobQueueEntry.Status::"On Hold");
        JobQueueEntry.Description := ScheduledExportLbl;
        JobQueueEntry."Job Queue Category Code" := JobQueueCategoryTok;
        JobQueueEntry."Report Output Type" := JobQueueEntry."Report Output Type"::"None (Processing only)";
        JobQueueEntry.Validate("Run on Mondays", true);
        JobQueueEntry.Validate("Run on Tuesdays", true);
        JobQueueEntry.Validate("Run on Wednesdays", true);
        JobQueueEntry.Validate("Run on Thursdays", true);
        JobQueueEntry.Validate("Run on Fridays", true);
        JobQueueEntry.Validate("Run on Saturdays", true);
        JobQueueEntry.Validate("Run on Sundays", true);
        JobQueueEntry.Validate("No. of Minutes between Runs", MinutesBetweenRuns);
        JobQueueEntry.Modify(true);
        JobQueueEntry.SetStatus(JobQueueEntry.Status::Ready);
    end;

    /// <summary>
    /// Tables that record how BC runs rather than the business: logs, scheduling, notifications, upgrade bookkeeping,
    /// integration sync state and stored credentials. Several change constantly, which would also make tracking their
    /// deletions costly.
    /// </summary>
    local procedure IsInfrastructure(TableId: Integer): Boolean
    begin
        exit(TableId in [
            Database::"Change Log Entry", Database::"Change Log Setup", Database::"Change Log Setup (Table)",
            Database::"Change Log Setup (Field)",
            Database::"Job Queue Entry", Database::"Job Queue Log Entry", Database::"Job Queue Category",
            Database::"Activity Log", Database::"Error Message", Database::"Error Message Register",
            Database::"Notification Entry", Database::"Sent Notification Entry",
            Database::"Integration Synch. Job", Database::"Integration Synch. Job Errors",
            Database::"Feature Data Update Status", Database::"Report Inbox",
            Database::"Isolated Certificate", Database::"Office Admin. Credentials",
            // Internal to the System Application, so named only by number: User Login, Upgrade Tags,
            // Retention Policy Log Entry, Guided Experience Item.
            9008, 9999, 3905, 1990]);
    end;

    procedure AddTableToExport()
    var
        AllObjWithCaption: Record AllObjWithCaption;
        ADLSETable: Record "ADLSE Table";
        AllObjectsWithCaption: Page "All Objects with Caption";
    begin
        AllObjWithCaption.SetRange("Object Type", AllObjWithCaption."Object Type"::Table);
        AllObjWithCaption.SetFilter("Object ID", '<>%1', Database::"ADLSE Deleted Record");

        AllObjectsWithCaption.Caption(SelectTableLbl);
        AllObjectsWithCaption.SetTableView(AllObjWithCaption);
        AllObjectsWithCaption.LookupMode(true);
        if AllObjectsWithCaption.RunModal() = Action::LookupOK then begin
            AllObjectsWithCaption.SetSelectionFilter(AllObjWithCaption);
            if AllObjWithCaption.FindSet() then
                repeat
                    ADLSETable.Add(AllObjWithCaption."Object ID");
                until AllObjWithCaption.Next() = 0;
        end;
    end;

    procedure ChooseFieldsToExport(ADLSETable: Record "ADLSE Table")
    var
        ADLSEField: Record "ADLSE Field";
    begin
        ADLSEField.SetRange("Table ID", ADLSETable."Table ID");
        ADLSEField.InsertForTable(ADLSETable);
        Commit(); // changes made to the field table go into the database before RunModal is called
        Page.RunModal(Page::"ADLSE Setup Fields", ADLSEField, ADLSEField.Enabled);
    end;

    procedure CanFieldBeExported(TableID: Integer; FieldID: Integer): Boolean
    var
        Field: Record Field;
    begin
        if not Field.Get(TableID, FieldID) then
            exit(false);
        exit(CheckFieldCanBeExported(Field, false));
    end;

    procedure CheckFieldCanBeExported(Field: Record Field)
    begin
        CheckFieldCanBeExported(Field, true);
    end;

    local procedure CheckFieldCanBeExported(Field: Record Field; RaiseError: Boolean): Boolean
    begin
        if Field.Class <> Field.Class::Normal then begin
            if RaiseError then
                Error(FieldClassNotSupportedErr, Field."Field Caption", Field.Class);
            exit(false);
        end;
        if Field.ObsoleteState = Field.ObsoleteState::Removed then begin
            if RaiseError then
                Error(FieldObsoleteNotSupportedErr, Field."Field Caption");
            exit(false);
        end;
        if not Field.Enabled then begin
            if RaiseError then
                Error(FieldDisabledNotSupportedErr, Field."Field Caption");
            exit(false);
        end;
        exit(true);
    end;

    procedure CheckSetup(var ADLSESetup: Record "ADLSE Setup")
    var
        ADLSECurrentSession: Record "ADLSE Current Session";
        ADLSECredentials: Codeunit "ADLSE Credentials";
    begin
        ADLSESetup.GetSingleton();
        if ADLSESetup."Storage Type" = ADLSESetup."Storage Type"::"Azure Data Lake" then
            ADLSESetup.TestField(Container);
        if ADLSESetup."Storage Type" = ADLSESetup."Storage Type"::"Microsoft Fabric" then
            ADLSESetup.TestField(Workspace);
        if ADLSESetup."Storage Type" = ADLSESetup."Storage Type"::"Open Mirroring" then
            ADLSESetup.TestField(LandingZone);
        if ADLSESetup."Storage Type" = ADLSESetup."Storage Type"::S3 then begin
            ADLSESetup.TestField("S3 Endpoint");
            ADLSESetup.TestField("S3 Region");
            ADLSESetup.TestField("S3 Bucket");
        end;

        ADLSESetup.CheckSchemaExported();

        if ADLSECurrentSession.AreAnySessionsActive() then
            ADLSECurrentSession.CheckForNoActiveSessions();

        ADLSECredentials.Check();
    end;

    [InherentPermissions(PermissionObjectType::TableData, Database::"ADLSE Setup", 'rm')]
    [InherentPermissions(PermissionObjectType::TableData, Database::"ADLSE Current Session", 'd')]
    [EventSubscriber(ObjectType::Codeunit, Codeunit::System.DataAdministration."Environment Cleanup", OnClearDatabaseConfig, '', false, false)]
    local procedure EnvironmentCleanup_OnClearDatabaseConfig(SourceEnv: Enum System.DataAdministration."Environment Type"; DestinationEnv: Enum System.DataAdministration."Environment Type")
    var
        ADLSESetup: Record "ADLSE Setup";
        ADLSECurrentSession: Record "ADLSE Current Session";
    begin
        if DestinationEnv <> DestinationEnv::Sandbox then
            exit;
        if not ADLSESetup.Exists() then
            exit;
        ADLSESetup."Schema Exported On" := 0DT;
        ADLSESetup.Workspace := '';
        ADLSESetup.Lakehouse := '';
        ADLSESetup.LandingZone := '';
        ADLSESetup.Container := '';
        ADLSESetup."Account Name" := '';
        ADLSESetup.Modify(false);
        ADLSECurrentSession.DeleteAll(true);
    end;


    [InherentPermissions(PermissionObjectType::TableData, Database::"ADLSE Field", 'rd')]
    [InherentPermissions(PermissionObjectType::TableData, Database::"ADLSE Table", 'rd')]
    [InherentPermissions(PermissionObjectType::TableData, Database::"ADLSE Setup", 'm')]
    procedure FixIncorrectData()
    var
        ADLSEField: Record "ADLSE Field";
        ADLSETable: Record "ADLSE Table";
        ADLSESetupRec: Record "ADLSE Setup";
        TableMetadata: Record "Table Metadata";
        ADLSESetup: Codeunit "ADLSE Setup";
        ConfirmManagement: Codeunit "Confirm Management";
        ShowMessage: Boolean;
        ShowMessageLbl: Label 'Incorrect data has been removed from the table. Please export the schema again and reset all tables.';
        ConfirmQuestionMsg: Label 'With this action you will remove all fields that cannot be exported and all obsolete tables (pending / removed). Do you want to continue?';
    begin
        ShowMessage := false;

        if ConfirmManagement.GetResponse(ConfirmQuestionMsg, true) then begin
            if ADLSEField.FindSet() then
                repeat
                    if not ADLSESetup.CanFieldBeExported(ADLSEField."Table ID", ADLSEField."Field ID") then begin
                        ADLSEField.Delete(false);

                        if ShowMessage = false then
                            ShowMessage := true;
                    end;
                until ADLSEField.Next() = 0;

            ADLSETable.SetRange(Enabled, true);
            if ADLSETable.FindSet() then
                repeat
                    TableMetadata.SetRange(ID, ADLSETable."Table ID");
                    if TableMetadata.FindFirst() then begin
                        if TableMetadata.ObsoleteState <> TableMetadata.ObsoleteState::No then begin
                            ADLSETable.Delete(true);

                            if ShowMessage = false then
                                ShowMessage := true;
                        end;
                    end else begin
                        ADLSETable.Delete(true);

                        if ShowMessage = false then
                            ShowMessage := true;
                    end;
                until ADLSETable.Next() = 0;

            if ShowMessage then begin
                ADLSESetupRec.GetSingleton();
                ADLSESetupRec."Schema Exported On" := 0DT;
                ADLSESetupRec.Modify(true);
                Message(StrSubstNo(ShowMessageLbl));
            end;
        end;
    end;
}