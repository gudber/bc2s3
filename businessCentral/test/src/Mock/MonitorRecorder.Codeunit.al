// ABOUTME: Records the events the extension reports to its monitoring URL, for tests; the HTTP handler cannot see
// ABOUTME: request bodies. Bind it with BindSubscription for the duration of a test.
codeunit 85584 "ADLSE Monitor Recorder"
{
    EventSubscriberInstance = Manual;

    var
        Events: List of [Text];
        NotReportedOnceErr: Label 'Event %1 was reported %2 times, not once. Reported: %3', Comment = '%1 = event name, %2 = count, %3 = the events', Locked = true;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"ADLSE Monitor", OnAfterReport, '', false, false)]
    local procedure RecordReport(MonitoringEvent: JsonObject)
    var
        Body: Text;
    begin
        MonitoringEvent.WriteTo(Body);
        Events.Add(Body);
    end;

    procedure Reported(): List of [Text]
    begin
        exit(Events);
    end;

    /// <summary>
    /// The one event of this name that was reported; an error when there was none or more than one.
    /// </summary>
    procedure Single(EventName: Text) Found: JsonObject
    var
        Candidate: JsonObject;
        Body: Text;
        Count: Integer;
    begin
        foreach Body in Events do begin
            Candidate.ReadFrom(Body);
            if Value(Candidate, 'event').AsText() = EventName then begin
                Found := Candidate;
                Count += 1;
            end;
            Clear(Candidate);
        end;
        if Count <> 1 then
            Error(NotReportedOnceErr, EventName, Count, Events.Count());
    end;

    /// <summary>
    /// How many events of this name were reported.
    /// </summary>
    procedure Count(EventName: Text) Result: Integer
    var
        Candidate: JsonObject;
        Body: Text;
    begin
        foreach Body in Events do begin
            Candidate.ReadFrom(Body);
            if Value(Candidate, 'event').AsText() = EventName then
                Result += 1;
            Clear(Candidate);
        end;
    end;

    procedure Value(ReportedEvent: JsonObject; Name: Text): JsonValue
    var
        Token: JsonToken;
    begin
        ReportedEvent.Get(Name, Token);
        exit(Token.AsValue());
    end;
}
