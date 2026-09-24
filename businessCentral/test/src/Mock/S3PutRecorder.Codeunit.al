// ABOUTME: Records the bodies of the objects the S3 client puts, for tests; the HTTP handler cannot see request bodies.
// ABOUTME: Bind it with BindSubscription for the duration of a test.
codeunit 85583 "ADLSE S3 Put Recorder"
{
    EventSubscriberInstance = Manual;

    var
        Bodies: List of [Text];

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"ADLSE S3 Util", OnAfterPutObject, '', false, false)]
    local procedure RecordPutObject(Url: Text; Body: Text)
    begin
        if Url.EndsWith('.csv') then
            Bodies.Add(Body);
    end;

    procedure CsvBodies(): List of [Text]
    begin
        exit(Bodies);
    end;
}
