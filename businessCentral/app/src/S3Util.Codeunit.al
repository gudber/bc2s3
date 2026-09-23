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
        RequestRejectedErr: Label 'The %1 request to %2 failed with HTTP status %3. %4', Comment = '%1: HTTP method, %2: object URL, %3: HTTP status code, %4: S3''s response';

    procedure Initialize(RegionValue: Text; AccessKeyIdValue: Text; SecretAccessKeyValue: SecretText)
    begin
        Region := RegionValue;
        AccessKeyId := AccessKeyIdValue;
        SecretAccessKey := SecretAccessKeyValue;
    end;

    procedure PutObject(Url: Text; Body: Text; ContentType: Text)
    var
        Content: HttpContent;
        ContentHeaders: HttpHeaders;
        Response: HttpResponseMessage;
    begin
        Content.WriteFrom(Body);
        Content.GetHeaders(ContentHeaders);
        ContentHeaders.Remove('Content-Type');
        ContentHeaders.Add('Content-Type', ContentType);
        Response := Send('PUT', Url, Content);
        if not Response.IsSuccessStatusCode() then
            Error(RequestRejectedErr, 'PUT', Url, Response.HttpStatusCode(), ReadBody(Response));
    end;

    procedure GetObject(Url: Text; var ObjectExists: Boolean): Text
    var
        Content: HttpContent;
        Response: HttpResponseMessage;
    begin
        Response := Send('GET', Url, Content);
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
    var
        UtcIso8601: Text;
    begin
        // Format 9 is ISO 8601 in UTC, e.g. 2013-05-24T00:00:07.123Z; the fraction is dropped.
        UtcIso8601 := CopyStr(Format(Moment, 0, 9), 1, 19);
        exit(UtcIso8601.Replace('-', '').Replace(':', '') + 'Z');
    end;

    local procedure Send(Method: Text; Url: Text; Content: HttpContent) Response: HttpResponseMessage
    var
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
        if Method = 'PUT' then
            Request.Content(Content);
        Request.GetHeaders(RequestHeaders);
        RequestHeaders.Add('x-amz-content-sha256', SignedHeaders.Get('x-amz-content-sha256'));
        RequestHeaders.Add('x-amz-date', SignedHeaders.Get('x-amz-date'));
        RequestHeaders.Add('Authorization', ADLSES3Signer.Authorization(Method, Path, Query, SignedHeaders, UnsignedPayloadTok, Region, AccessKeyId, SecretAccessKey));

        if not Client.Send(Request, Response) then
            Error(RequestFailedErr, Method, Url, GetLastErrorText());
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
