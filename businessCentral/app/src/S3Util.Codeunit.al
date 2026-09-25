// ABOUTME: A minimal S3 client: puts and gets objects on S3-compatible storage with signed requests.
// ABOUTME: Bodies are sent as UNSIGNED-PAYLOAD over HTTPS, so they are never hashed in AL.
namespace bc2adls;

codeunit 82585 "ADLSE S3 Util"
{
    Access = Internal;

    var
        Region: Text;
        AccessKeyId: Text;
        SecretAccessKey: SecretText;
        UnsignedPayloadTok: Label 'UNSIGNED-PAYLOAD', Locked = true;
        RequestFailedErr: Label 'The %1 request to %2 failed. %3', Comment = '%1: HTTP method, %2: object URL, %3: reason or S3''s response';
        AuthorizationHeaderRejectedErr: Label 'The Authorization header could not be added to the request.';
        RequestRejectedErr: Label 'The %1 request to %2 failed with HTTP status %3. %4', Comment = '%1: HTTP method, %2: object URL, %3: HTTP status code, %4: S3''s response';

    procedure Initialize(RegionValue: Text; AccessKeyIdValue: Text; SecretAccessKeyValue: SecretText)
    begin
        Region := RegionValue;
        AccessKeyId := AccessKeyIdValue;
        SecretAccessKey := SecretAccessKeyValue;
    end;

    procedure PutObject(Url: Text; Body: Text; ContentType: Text)
    var
        Response: HttpResponseMessage;
    begin
        Response := Send('PUT', Url, Body, ContentType);
        if not Response.IsSuccessStatusCode() then
            Error(RequestRejectedErr, 'PUT', Url, Response.HttpStatusCode(), ReadBody(Response));
        OnAfterPutObject(Url, Body);
    end;

    /// <summary>
    /// Raised after an object was put, with its URL and content.
    /// </summary>
    [IntegrationEvent(false, false)]
    local procedure OnAfterPutObject(Url: Text; Body: Text)
    begin
    end;

    procedure GetObject(Url: Text; var ObjectExists: Boolean): Text
    var
        Response: HttpResponseMessage;
    begin
        Response := Send('GET', Url, '', '');
        ObjectExists := Response.IsSuccessStatusCode();
        if ObjectExists then
            exit(ReadBody(Response));
        if Response.HttpStatusCode() = 404 then
            exit('');
        Error(RequestRejectedErr, 'GET', Url, Response.HttpStatusCode(), ReadBody(Response));
    end;

    /// <summary>
    /// The x-amz-date of a moment: its UTC time as yyyyMMddTHHmmssZ.
    /// </summary>
    procedure AmzDate(Moment: DateTime): Text
    begin
        exit(UtcBasicSeconds(Moment) + 'Z');
    end;

    /// <summary>
    /// The UTC time of a moment to the millisecond, as yyyyMMddTHHmmssfffZ, so object names sort in the order they were written.
    /// </summary>
    procedure ObjectTimestamp(Moment: DateTime): Text
    var
        UtcIso8601: Text;
        Milliseconds: Text;
    begin
        UtcIso8601 := Format(Moment, 0, 9);
        Milliseconds := '000';
        if CopyStr(UtcIso8601, 20, 1) = '.' then
            Milliseconds := PadStr(CopyStr(UtcIso8601, 21, StrPos(UtcIso8601, 'Z') - 21), 3, '0');
        exit(UtcBasicSeconds(Moment) + Milliseconds + 'Z');
    end;

    /// <summary>
    /// The UTC time of a moment to the second, as yyyyMMddTHHmmss.
    /// </summary>
    local procedure UtcBasicSeconds(Moment: DateTime): Text
    var
        UtcIso8601: Text;
    begin
        // Format 9 is ISO 8601 in UTC, e.g. 2013-05-24T00:00:07.123Z, with the fraction only when there is one.
        UtcIso8601 := CopyStr(Format(Moment, 0, 9), 1, 19);
        exit(UtcIso8601.Replace('-', '').Replace(':', ''));
    end;

    /// <summary>
    /// Sends a request, and again while S3 throttles it, fails on its side or cannot be reached: up to four attempts,
    /// pausing 1, 2 and 4 seconds between them, each signed anew. The last answer is S3's final one.
    /// </summary>
    local procedure Send(Method: Text; Url: Text; Body: Text; ContentType: Text) Response: HttpResponseMessage
    var
        Attempt: Integer;
        Sent: Boolean;
        PauseMilliseconds: Integer;
    begin
        PauseMilliseconds := 1000;
        for Attempt := 1 to MaxAttempts() do begin
            Clear(Response);
            Sent := SendOnce(Method, Url, Body, ContentType, Response);
            if Sent and not IsTransient(Response.HttpStatusCode()) then
                exit(Response);
            if Attempt < MaxAttempts() then begin
                Sleep(PauseMilliseconds);
                PauseMilliseconds *= 2;
            end;
        end;
        if not Sent then
            Error(RequestFailedErr, Method, Url, GetLastErrorText());
    end;

    local procedure MaxAttempts(): Integer
    begin
        exit(4);
    end;

    /// <summary>
    /// Whether S3's answer may be different when asked again: throttling and its own failures.
    /// </summary>
    local procedure IsTransient(Status: Integer): Boolean
    begin
        exit((Status = 429) or ((Status >= 500) and (Status <= 599)));
    end;

    local procedure SendOnce(Method: Text; Url: Text; Body: Text; ContentType: Text; var Response: HttpResponseMessage): Boolean
    var
        Content: HttpContent;
        ContentHeaders: HttpHeaders;
        ADLSES3Signer: Codeunit "ADLSE S3 Signer";
        Client: HttpClient;
        Request: HttpRequestMessage;
        RequestHeaders: HttpHeaders;
        SignedHeaders: Dictionary of [Text, Text];
        Query: Dictionary of [Text, Text];
        Host: Text;
        Path: Text;
    begin
        SplitUrl(Url, Host, Path);
        SignedHeaders.Add('host', Host);
        SignedHeaders.Add('x-amz-content-sha256', UnsignedPayloadTok);
        SignedHeaders.Add('x-amz-date', AmzDate(CurrentDateTime()));

        Request.Method(Method);
        Request.SetRequestUri(Url);
        if Method = 'PUT' then begin
            Content.WriteFrom(Body);
            Content.GetHeaders(ContentHeaders);
            ContentHeaders.Remove('Content-Type');
            ContentHeaders.Add('Content-Type', ContentType);
            Request.Content(Content);
        end;
        Request.GetHeaders(RequestHeaders);
        RequestHeaders.Add('x-amz-content-sha256', SignedHeaders.Get('x-amz-content-sha256'));
        RequestHeaders.Add('x-amz-date', SignedHeaders.Get('x-amz-date'));
        // Added without validation: HttpHeaders rejects the comma-separated parameters of a Signature Version 4 Authorization value.
        if not RequestHeaders.TryAddWithoutValidation('Authorization', ADLSES3Signer.Authorization(Method, Path, Query, SignedHeaders, UnsignedPayloadTok, Region, AccessKeyId, SecretAccessKey)) then
            Error(RequestFailedErr, Method, Url, AuthorizationHeaderRejectedErr);

        exit(Client.Send(Request, Response));
    end;

    /// <summary>
    /// Splits https://host/path into its host and its unencoded path.
    /// </summary>
    local procedure SplitUrl(Url: Text; var Host: Text; var Path: Text)
    var
        AfterScheme: Text;
        PathStart: Integer;
    begin
        AfterScheme := CopyStr(Url, StrPos(Url, '://') + 3);
        PathStart := StrPos(AfterScheme, '/');
        if PathStart = 0 then begin
            Host := AfterScheme;
            Path := '/';
            exit;
        end;
        Host := CopyStr(AfterScheme, 1, PathStart - 1);
        Path := CopyStr(AfterScheme, PathStart);
    end;

    local procedure ReadBody(Response: HttpResponseMessage) Body: Text
    begin
        Response.Content().ReadAs(Body);
    end;
}
