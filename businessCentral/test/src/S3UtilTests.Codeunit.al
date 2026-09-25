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
        ResponseStatuses: List of [Integer];
        Requests: Integer;

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
    procedure TestObjectTimestamp_KeepsMilliseconds()
    var
        ADLSES3Util: Codeunit "ADLSE S3 Util";
        Moment: DateTime;
    begin
        // [SCENARIO] Object names start with the UTC time to the millisecond, so they sort in the order they were written
        // [GIVEN] A moment with milliseconds, given in UTC
        Evaluate(Moment, '2013-05-24T00:00:07.045Z', 9);

        // [WHEN] Its object timestamp is formatted
        // [THEN] It has the milliseconds
        LibraryAssert.AreEqual('20130524T000007045Z', ADLSES3Util.ObjectTimestamp(Moment), 'object timestamp');
    end;

    [Test]
    procedure TestObjectTimestamp_WholeSecond_HasZeroMilliseconds()
    var
        ADLSES3Util: Codeunit "ADLSE S3 Util";
        Moment: DateTime;
    begin
        // [SCENARIO] A moment on a whole second still has three millisecond digits, so all names have the same length
        // [GIVEN] A moment on a whole second, given in UTC
        Evaluate(Moment, '2013-05-24T00:00:07Z', 9);

        // [WHEN] Its object timestamp is formatted
        // [THEN] The milliseconds are 000
        LibraryAssert.AreEqual('20130524T000007000Z', ADLSES3Util.ObjectTimestamp(Moment), 'object timestamp');
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
        LibraryAssert.AreEqual(Format(HttpRequestType::Put), Format(RequestedMethod), 'method');
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
        LibraryAssert.AreEqual(Format(HttpRequestType::Get), Format(RequestedMethod), 'method');
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

    [Test]
    [HandlerFunctions('S3Handler')]
    procedure TestPutObject_RetriesAServerErrorAndSucceeds()
    var
        ADLSES3Util: Codeunit "ADLSE S3 Util";
    begin
        // [SCENARIO] A PUT that S3 answers with a server error is sent again, and succeeds when S3 recovers
        // [GIVEN] S3 answers 503 once, then 200
        Initialize(ADLSES3Util);
        AnswerWith(503, 200, 0, 0);

        // [WHEN] An object is put
        ADLSES3Util.PutObject(ObjectUrlTok, 'a,b\r\n', 'text/csv');

        // [THEN] It was sent twice, without an error
        LibraryAssert.AreEqual(2, Requests, 'requests');
    end;

    [Test]
    [HandlerFunctions('S3Handler')]
    procedure TestGetObject_RetriesAGatewayTimeoutAndReturnsTheContent()
    var
        ADLSES3Util: Codeunit "ADLSE S3 Util";
        ObjectExists: Boolean;
        Content: Text;
    begin
        // [SCENARIO] A GET that times out at S3's gateway is sent again
        // [GIVEN] S3 answers 504 once, then the object
        Initialize(ADLSES3Util);
        AnswerWith(504, 200, 0, 0);
        ResponseBody := '{"name":"Customer-18"}';

        // [WHEN] The object is got
        Content := ADLSES3Util.GetObject(ObjectUrlTok, ObjectExists);

        // [THEN] It was sent twice and its content came back
        LibraryAssert.AreEqual(2, Requests, 'requests');
        LibraryAssert.IsTrue(ObjectExists, 'The object should exist');
        LibraryAssert.AreEqual(ResponseBody, Content, 'content');
    end;

    [Test]
    [HandlerFunctions('S3Handler')]
    procedure TestPutObject_RetriesThrottling()
    var
        ADLSES3Util: Codeunit "ADLSE S3 Util";
    begin
        // [SCENARIO] A PUT that S3 throttles is sent again
        // [GIVEN] S3 answers 429 once, then 200
        Initialize(ADLSES3Util);
        AnswerWith(429, 200, 0, 0);

        // [WHEN] An object is put
        ADLSES3Util.PutObject(ObjectUrlTok, 'a,b\r\n', 'text/csv');

        // [THEN] It was sent twice, without an error
        LibraryAssert.AreEqual(2, Requests, 'requests');
    end;

    [Test]
    [HandlerFunctions('S3Handler')]
    procedure TestPutObject_GivesUpAfterFourAttempts()
    var
        ADLSES3Util: Codeunit "ADLSE S3 Util";
    begin
        // [SCENARIO] A server error that lasts fails the PUT after four attempts, with S3's last answer
        // [GIVEN] S3 answers 500 every time
        Initialize(ADLSES3Util);
        AnswerWith(500, 500, 500, 500);
        ResponseBody := '<Error><Code>InternalError</Code></Error>';

        // [WHEN] An object is put
        asserterror ADLSES3Util.PutObject(ObjectUrlTok, 'a,b\r\n', 'text/csv');

        // [THEN] It was sent four times, and the error gives the status and S3's answer
        LibraryAssert.AreEqual(4, Requests, 'requests');
        LibraryAssert.IsTrue(GetLastErrorText().Contains('500'), 'The error should give the status: ' + GetLastErrorText());
        LibraryAssert.IsTrue(GetLastErrorText().Contains('InternalError'), 'The error should include S3''s response: ' + GetLastErrorText());
    end;

    [Test]
    [HandlerFunctions('S3Handler')]
    procedure TestPutObject_DoesNotRetryAClientError()
    var
        ADLSES3Util: Codeunit "ADLSE S3 Util";
    begin
        // [SCENARIO] A request S3 refuses, e.g. for a wrong key, is not sent again: it would be refused again
        // [GIVEN] S3 answers 403
        Initialize(ADLSES3Util);
        ResponseStatus := 403;

        // [WHEN] An object is put
        asserterror ADLSES3Util.PutObject(ObjectUrlTok, 'a,b\r\n', 'text/csv');

        // [THEN] It was sent once
        LibraryAssert.AreEqual(1, Requests, 'requests');
    end;

    /// <summary>
    /// S3 answers the requests in turn with these statuses; a status of 0 ends the list.
    /// </summary>
    local procedure AnswerWith(First: Integer; Second: Integer; Third: Integer; Fourth: Integer)
    begin
        AddAnswer(First);
        AddAnswer(Second);
        AddAnswer(Third);
        AddAnswer(Fourth);
    end;

    local procedure AddAnswer(Status: Integer)
    begin
        if Status <> 0 then
            ResponseStatuses.Add(Status);
    end;

    [HttpClientHandler]
    procedure S3Handler(Request: TestHttpRequestMessage; var Response: TestHttpResponseMessage): Boolean
    begin
        RequestedMethod := Request.RequestType();
        RequestedUrl := Request.Path();
        Requests += 1;
        Response.HttpStatusCode := ResponseStatus;
        if Requests <= ResponseStatuses.Count() then
            Response.HttpStatusCode := ResponseStatuses.Get(Requests);
        Response.Content.WriteFrom(ResponseBody);
        exit(false);
    end;

    local procedure Initialize(var ADLSES3Util: Codeunit "ADLSE S3 Util")
    var
        SecretAccessKey: Text;
    begin
        Clear(RequestedMethod);
        Clear(RequestedUrl);
        Clear(ResponseStatuses);
        Requests := 0;
        SecretAccessKey := 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY';
        ADLSES3Util.Initialize('fsn1', 'AKIAIOSFODNN7EXAMPLE', SecretAccessKey);
    end;
}
