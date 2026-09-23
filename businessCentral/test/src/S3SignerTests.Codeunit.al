// ABOUTME: Tests the AWS Signature Version 4 signing of S3 requests against AWS's published examples.
// ABOUTME: https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-header-based-auth.html
codeunit 85577 "ADLSE S3 Signer Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    trigger OnRun()
    begin
        // [FEATURE] bc2adls S3 request signing
    end;

    var
        LibraryAssert: Codeunit "Library Assert";
        AccessKeyIdTxt: Label 'AKIAIOSFODNN7EXAMPLE', Locked = true;
        SecretAccessKeyTxt: Label 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', Locked = true;
        HostTxt: Label 'examplebucket.s3.amazonaws.com', Locked = true;
        AmzDateTxt: Label '20130524T000000Z', Locked = true;
        RegionTxt: Label 'us-east-1', Locked = true;
        EmptyPayloadHashTxt: Label 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855', Locked = true;

    [Test]
    procedure TestAuthorization_GetObject_MatchesAwsExample()
    var
        ADLSES3Signer: Codeunit "ADLSE S3 Signer";
        Headers: Dictionary of [Text, Text];
        Query: Dictionary of [Text, Text];
        Result: Text;
    begin
        // [SCENARIO] A GET Object request is signed as in AWS's example
        // [GIVEN] The headers of AWS's GET Object example, in no particular order
        Headers.Add('x-amz-date', AmzDateTxt);
        Headers.Add('range', 'bytes=0-9');
        Headers.Add('host', HostTxt);
        Headers.Add('x-amz-content-sha256', EmptyPayloadHashTxt);

        // [WHEN] The request is signed
        Result := ADLSES3Signer.Authorization('GET', '/test.txt', Query, Headers, EmptyPayloadHashTxt, RegionTxt, AccessKeyIdTxt, SecretAccessKey());

        // [THEN] The Authorization header is AWS's
        LibraryAssert.AreEqual(
            'AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, SignedHeaders=host;range;x-amz-content-sha256;x-amz-date, Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41',
            Result, 'Authorization for GET Object');
    end;

    [Test]
    procedure TestAuthorization_PutObjectWithReservedCharacterInKey_MatchesAwsExample()
    var
        ADLSES3Signer: Codeunit "ADLSE S3 Signer";
        Headers: Dictionary of [Text, Text];
        Query: Dictionary of [Text, Text];
        PayloadHash: Text;
        Result: Text;
    begin
        // [SCENARIO] A PUT Object request whose key has a '$' is signed as in AWS's example
        // [GIVEN] The headers of AWS's PUT Object example
        PayloadHash := '44ce7dd67c959e0d3524ffac1771dfbba87d2b6b4b4e99e42034a8b803f8b072';
        Headers.Add('host', HostTxt);
        Headers.Add('date', 'Fri, 24 May 2013 00:00:00 GMT');
        Headers.Add('x-amz-storage-class', 'REDUCED_REDUNDANCY');
        Headers.Add('x-amz-date', AmzDateTxt);
        Headers.Add('x-amz-content-sha256', PayloadHash);

        // [WHEN] The request for key 'test$file.text' is signed
        Result := ADLSES3Signer.Authorization('PUT', '/test$file.text', Query, Headers, PayloadHash, RegionTxt, AccessKeyIdTxt, SecretAccessKey());

        // [THEN] The Authorization header is AWS's, which signs the key as 'test%24file.text'
        LibraryAssert.AreEqual(
            'AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, SignedHeaders=date;host;x-amz-content-sha256;x-amz-date;x-amz-storage-class, Signature=98ad721746da40c64f1a55b78f14c238d841ea1380cd77a1b5971af0ece108bd',
            Result, 'Authorization for PUT Object');
    end;

    [Test]
    procedure TestAuthorization_ListObjectsWithQuery_MatchesAwsExample()
    var
        ADLSES3Signer: Codeunit "ADLSE S3 Signer";
        Headers: Dictionary of [Text, Text];
        Query: Dictionary of [Text, Text];
        Result: Text;
    begin
        // [SCENARIO] A list request with query parameters is signed as in AWS's example
        // [GIVEN] The query of AWS's GET Bucket example, in no particular order
        Query.Add('prefix', 'J');
        Query.Add('max-keys', '2');
        Headers.Add('host', HostTxt);
        Headers.Add('x-amz-date', AmzDateTxt);
        Headers.Add('x-amz-content-sha256', EmptyPayloadHashTxt);

        // [WHEN] The request is signed
        Result := ADLSES3Signer.Authorization('GET', '/', Query, Headers, EmptyPayloadHashTxt, RegionTxt, AccessKeyIdTxt, SecretAccessKey());

        // [THEN] The Authorization header is AWS's
        LibraryAssert.AreEqual(
            'AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, SignedHeaders=host;x-amz-content-sha256;x-amz-date, Signature=34b48302e7b5fa45bde8084f4b7868a86f0a534bc59db6670ed5711ef69dc6f7',
            Result, 'Authorization for GET Bucket');
    end;

    local procedure SecretAccessKey(): SecretText
    var
        Secret: Text;
    begin
        Secret := SecretAccessKeyTxt;
        exit(Secret);
    end;
}
