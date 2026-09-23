// ABOUTME: Signs S3 requests with AWS Signature Version 4, producing the Authorization header.
// ABOUTME: https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-header-based-auth.html
namespace bc2adls;

using System.Security.Encryption;
using System.Utilities;
codeunit 82584 "ADLSE S3 Signer"
{
    Access = Internal;

    var
        AlgorithmTok: Label 'AWS4-HMAC-SHA256', Locked = true;
        ServiceTok: Label 's3', Locked = true;
        AuthorizationTok: Label '%1 Credential=%2/%3, SignedHeaders=%4, Signature=%5', Locked = true, Comment = '%1: algorithm, %2: access key id, %3: credential scope, %4: signed header names, %5: signature';
        CredentialScopeTok: Label '%1/%2/%3/aws4_request', Locked = true, Comment = '%1: date (yyyyMMdd), %2: region, %3: service';
        AmzDateMissingErr: Label 'The request to sign has no x-amz-date header.';
        HmacSha256Opt: Option HMACMD5,HMACSHA1,HMACSHA256,HMACSHA384,HMACSHA512;
        Sha256Opt: Option MD5,SHA1,SHA256,SHA384,SHA512;

    /// <summary>
    /// Returns the Authorization header value for a request.
    /// </summary>
    /// <param name="Path">The unencoded path, e.g. /bucket/folder/file.csv.</param>
    /// <param name="Query">The unencoded query parameters.</param>
    /// <param name="Headers">The headers to sign, with lowercase names; must include host and x-amz-date.</param>
    /// <param name="PayloadHash">The hex SHA-256 of the body, or UNSIGNED-PAYLOAD.</param>
    procedure Authorization(Method: Text; Path: Text; Query: Dictionary of [Text, Text]; Headers: Dictionary of [Text, Text]; PayloadHash: Text; Region: Text; AccessKeyId: Text; SecretAccessKey: SecretText): Text
    var
        CryptographyManagement: Codeunit "Cryptography Management";
        HeaderNames: List of [Text];
        AmzDate: Text;
        CredentialScope: Text;
        SignedHeaderNames: Text;
        CanonicalRequest: Text;
        StringToSign: Text;
        Signature: Text;
        LF: Text[1];
    begin
        if not Headers.Get('x-amz-date', AmzDate) then
            Error(AmzDateMissingErr);
        LF[1] := 10;
        HeaderNames := SortedOrdinal(Headers.Keys());
        SignedHeaderNames := Join(HeaderNames, ';');

        CanonicalRequest :=
            Method + LF +
            CanonicalPath(Path) + LF +
            CanonicalQuery(Query) + LF +
            CanonicalHeaders(Headers, HeaderNames, LF) + LF +
            SignedHeaderNames + LF +
            PayloadHash;

        CredentialScope := StrSubstNo(CredentialScopeTok, CopyStr(AmzDate, 1, 8), Region, ServiceTok);
        StringToSign :=
            AlgorithmTok + LF +
            AmzDate + LF +
            CredentialScope + LF +
            LowerCase(CryptographyManagement.GenerateHash(CanonicalRequest, Sha256Opt::SHA256));

        Signature := LowerCase(CryptographyManagement.GenerateBase64KeyedHash(StringToSign, SigningKey(SecretAccessKey, CopyStr(AmzDate, 1, 8), Region), HmacSha256Opt::HMACSHA256));
        exit(StrSubstNo(AuthorizationTok, AlgorithmTok, AccessKeyId, CredentialScope, SignedHeaderNames, Signature));
    end;

    /// <summary>
    /// The derived signing key, base64 encoded: HMAC chained over the date, region, service and 'aws4_request'.
    /// </summary>
    local procedure SigningKey(SecretAccessKey: SecretText; DateStamp: Text; Region: Text): SecretText
    var
        CryptographyManagement: Codeunit "Cryptography Management";
        DateKey: SecretText;
        RegionKey: SecretText;
        ServiceKey: SecretText;
    begin
        DateKey := CryptographyManagement.GenerateHashAsBase64String(DateStamp, SecretStrSubstNo('AWS4%1', SecretAccessKey), HmacSha256Opt::HMACSHA256);
        RegionKey := CryptographyManagement.GenerateBase64KeyedHashAsBase64String(Region, DateKey, HmacSha256Opt::HMACSHA256);
        ServiceKey := CryptographyManagement.GenerateBase64KeyedHashAsBase64String(ServiceTok, RegionKey, HmacSha256Opt::HMACSHA256);
        exit(CryptographyManagement.GenerateBase64KeyedHashAsBase64String('aws4_request', ServiceKey, HmacSha256Opt::HMACSHA256));
    end;

    local procedure CanonicalPath(Path: Text) Result: Text
    var
        Segment: Text;
        IsFirst: Boolean;
    begin
        IsFirst := true;
        foreach Segment in Path.Split('/') do begin
            if not IsFirst then
                Result += '/';
            Result += UriEncode(Segment);
            IsFirst := false;
        end;
    end;

    local procedure CanonicalQuery(Query: Dictionary of [Text, Text]) Result: Text
    var
        Name: Text;
        Pairs: List of [Text];
    begin
        foreach Name in Query.Keys() do
            Pairs.Add(UriEncode(Name) + '=' + UriEncode(Query.Get(Name)));
        exit(Join(SortedOrdinal(Pairs), '&'));
    end;

    local procedure CanonicalHeaders(Headers: Dictionary of [Text, Text]; HeaderNames: List of [Text]; LF: Text[1]) Result: Text
    var
        Name: Text;
    begin
        foreach Name in HeaderNames do
            Result += Name + ':' + Headers.Get(Name).Trim() + LF;
    end;

    local procedure UriEncode(Value: Text): Text
    var
        Uri: Codeunit Uri;
    begin
        exit(Uri.EscapeDataString(Value));
    end;

    local procedure Join(Items: List of [Text]; Separator: Text) Result: Text
    var
        Item: Text;
    begin
        foreach Item in Items do begin
            if Result <> '' then
                Result += Separator;
            Result += Item;
        end;
    end;

    /// <summary>
    /// Sorts by character code, which is the order Signature Version 4 requires.
    /// </summary>
    local procedure SortedOrdinal(Items: List of [Text]) Result: List of [Text]
    var
        Item: Text;
        Index: Integer;
    begin
        foreach Item in Items do begin
            Index := 1;
            while (Index <= Result.Count()) and not IsOrdinalLess(Item, Result.Get(Index)) do
                Index += 1;
            if Index > Result.Count() then
                Result.Add(Item)
            else
                Result.Insert(Index, Item);
        end;
    end;

    local procedure IsOrdinalLess(Left: Text; Right: Text): Boolean
    var
        Index: Integer;
    begin
        for Index := 1 to StrLen(Left) do begin
            if Index > StrLen(Right) then
                exit(false);
            if Left[Index] <> Right[Index] then
                exit(Left[Index] < Right[Index]);
        end;
        exit(StrLen(Left) < StrLen(Right));
    end;
}
