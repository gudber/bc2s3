// ABOUTME: Records the events the extension reports to its monitoring URL, for tests; the HTTP handler cannot see
// ABOUTME: request bodies. Bind it with BindSubscription for the duration of a test.
codeunit 85584 "ADLSE Monitor Recorder"
{
    EventSubscriberInstance = Manual;

    var
        Events: List of [Text];

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
}
