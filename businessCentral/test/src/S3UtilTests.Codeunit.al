// ABOUTME: Tests the S3 client: the requests it issues and how it reads S3's responses.
// ABOUTME: Outbound HTTP is answered by a handler, so no request leaves the test.
codeunit 85578 "ADLSE S3 Util Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;
    TestHttpRequestPolicy = BlockOutboundRequests;

    trigger OnRun()
    begin
        // [FEATURE] bc2adls S3 client
    end;

    var
        LibraryAssert: Codeunit "Library Assert";
        ObjectUrlTok: Label 'https://fsn1.your-objectstorage.com/bucket/deltas/Customer-18/file.csv', Locked = true;
        RequestedMethod: HttpRequestType;
        RequestedUrl: Text;
        ResponseStatus: Integer;
        ResponseBody: Text;

    [Test]
    procedure TestAmzDate_FormatsUtcMomentAsBasicIso8601()
    var
        ADLSES3Util: Codeunit "ADLSE S3 Util";
        Moment: DateTime;
    begin
        // [SCENARIO] The x-amz-date of a moment is its UTC time as yyyyMMddTHHmmssZ
        // [GIVEN] A moment given in UTC
        Evaluate(Moment, '2013-05-24T00:00:07Z', 9);

        // [WHEN] Its x-amz-date is formatted
        // [THEN] It is the basic ISO 8601 form AWS signs
        LibraryAssert.AreEqual('20130524T000007Z', ADLSES3Util.AmzDate(Moment), 'x-amz-date');
    end;

    [Test]
    [HandlerFunctions('S3Handler')]
    procedure TestPutObject_IssuesPutToObjectUrl()
    var
        ADLSES3Util: Codeunit "ADLSE S3 Util";
    begin
        // [SCENARIO] Putting an object issues a PUT to the object's URL
        // [GIVEN] S3 accepts the request
        ResponseStatus := 200;

        // [WHEN] An object is put
        Initialize(ADLSES3Util);
        ADLSES3Util.PutObject(ObjectUrlTok, 'a,b\r\n', 'text/csv');

        // [THEN] A PUT went to the object's URL
        LibraryAssert.AreEqual(HttpRequestType::Put, RequestedMethod, 'method');
        LibraryAssert.AreEqual(ObjectUrlTok, RequestedUrl, 'url');
    end;

    [Test]
    [HandlerFunctions('S3Handler')]
    procedure TestPutObject_RejectedRequest_ErrorsWithS3Response()
    var
        ADLSES3Util: Codeunit "ADLSE S3 Util";
    begin
        // [SCENARIO] A rejected PUT raises an error that carries S3's explanation
        // [GIVEN] S3 rejects the request
        ResponseStatus := 403;
        ResponseBody := '<Error><Code>SignatureDoesNotMatch</Code></Error>';

        // [WHEN] An object is put
        Initialize(ADLSES3Util);
        asserterror ADLSES3Util.PutObject(ObjectUrlTok, 'a,b\r\n', 'text/csv');

        // [THEN] The error names the object and includes S3's response
        LibraryAssert.ExpectedError(ObjectUrlTok);
        LibraryAssert.IsTrue(GetLastErrorText().Contains('SignatureDoesNotMatch'), 'The error should include S3''s response: ' + GetLastErrorText());
    end;

    [Test]
    [HandlerFunctions('S3Handler')]
    procedure TestGetObject_ExistingObject_ReturnsContent()
    var
        ADLSES3Util: Codeunit "ADLSE S3 Util";
        ObjectExists: Boolean;
        Content: Text;
    begin
        // [SCENARIO] Getting an existing object returns its content
        // [GIVEN] S3 has the object
        ResponseStatus := 200;
        ResponseBody := '{"name":"Customer-18"}';

        // [WHEN] The object is got
        Initialize(ADLSES3Util);
        Content := ADLSES3Util.GetObject(ObjectUrlTok, ObjectExists);

        // [THEN] A GET went to the object's URL and its content came back
        LibraryAssert.AreEqual(HttpRequestType::Get, RequestedMethod, 'method');
        LibraryAssert.AreEqual(ObjectUrlTok, RequestedUrl, 'url');
        LibraryAssert.IsTrue(ObjectExists, 'The object should exist');
        LibraryAssert.AreEqual(ResponseBody, Content, 'content');
    end;

    [Test]
    [HandlerFunctions('S3Handler')]
    procedure TestGetObject_MissingObject_ReportsItDoesNotExist()
    var
        ADLSES3Util: Codeunit "ADLSE S3 Util";
        ObjectExists: Boolean;
        Content: Text;
    begin
        // [SCENARIO] Getting a missing object reports that it does not exist, without an error
        // [GIVEN] S3 does not have the object
        ResponseStatus := 404;
        ResponseBody := '<Error><Code>NoSuchKey</Code></Error>';

        // [WHEN] The object is got
        Initialize(ADLSES3Util);
        Content := ADLSES3Util.GetObject(ObjectUrlTok, ObjectExists);

        // [THEN] It does not exist and there is no content
        LibraryAssert.IsFalse(ObjectExists, 'The object should not exist');
        LibraryAssert.AreEqual('', Content, 'content');
    end;

    [Test]
    [HandlerFunctions('S3Handler')]
    procedure TestGetObject_RejectedRequest_ErrorsWithS3Response()
    var
        ADLSES3Util: Codeunit "ADLSE S3 Util";
        ObjectExists: Boolean;
    begin
        // [SCENARIO] A GET that fails for another reason than a missing object raises an error
        // [GIVEN] S3 rejects the request
        ResponseStatus := 403;
        ResponseBody := '<Error><Code>AccessDenied</Code></Error>';

        // [WHEN] The object is got
        Initialize(ADLSES3Util);
        asserterror ADLSES3Util.GetObject(ObjectUrlTok, ObjectExists);

        // [THEN] The error names the object and includes S3's response
        LibraryAssert.ExpectedError(ObjectUrlTok);
        LibraryAssert.IsTrue(GetLastErrorText().Contains('AccessDenied'), 'The error should include S3''s response: ' + GetLastErrorText());
    end;

    [HttpClientHandler]
    procedure S3Handler(Request: TestHttpRequestMessage; var Response: TestHttpResponseMessage): Boolean
    begin
        RequestedMethod := Request.RequestType();
        RequestedUrl := Request.Path();
        Response.HttpStatusCode := ResponseStatus;
        Response.Content.WriteFrom(ResponseBody);
        exit(false);
    end;

    local procedure Initialize(var ADLSES3Util: Codeunit "ADLSE S3 Util")
    var
        SecretAccessKey: Text;
    begin
        Clear(RequestedMethod);
        Clear(RequestedUrl);
        SecretAccessKey := 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY';
        ADLSES3Util.Initialize('fsn1', 'AKIAIOSFODNN7EXAMPLE', SecretAccessKey);
    end;
}
