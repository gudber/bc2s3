// ABOUTME: Tests setting up S3-compatible storage as the export destination: storage type, fields and credentials.
// ABOUTME: The access key id and secret access key are kept as the client id and client secret.
codeunit 85579 "ADLSE S3 Setup Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    trigger OnRun()
    begin
        // [FEATURE] bc2adls S3 setup
    end;

    var
        ADLSELibrarybc2adls: Codeunit "ADLSE Library - bc2adls";
        LibraryAssert: Codeunit "Library Assert";
        "Storage Type": Enum "ADLSE Storage Type";
        IsInitialized: Boolean;

    [Test]
    procedure TestNewSetup_StorageTypeIsS3()
    var
        ADLSESetup: Record "ADLSE Setup";
    begin
        // [SCENARIO] A new setup exports to S3 unless another storage type is chosen
        // [GIVEN] No setup
        Initialize();

        // [WHEN] The setup is created, as when the setup page is first opened
        ADLSESetup.GetOrCreate();

        // [THEN] Its storage type is S3
        ADLSESetup.Get(0);
        LibraryAssert.AreEqual("ADLSE Storage Type"::S3, ADLSESetup."Storage Type", 'Storage type');
    end;

    [Test]
    procedure TestStorageType_S3_ClearsOtherStorageSettings()
    var
        ADLSESetup: Record "ADLSE Setup";
    begin
        // [SCENARIO] Choosing S3 clears the settings of the other storage types
        // [GIVEN] A setup for Azure Data Lake, with Fabric settings left over
        Initialize();
        ADLSELibrarybc2adls.CreateAdlseSetup("Storage Type"::"Azure Data Lake");
        ADLSESetup.Get(0);
        ADLSESetup.Workspace := 'workspace';
        ADLSESetup.Lakehouse := 'lakehouse';
        ADLSESetup.LandingZone := 'https://landingzone';

        // [WHEN] The storage type is changed to S3
        ADLSESetup.Validate("Storage Type", "ADLSE Storage Type"::S3);

        // [THEN] The Azure and Fabric settings are cleared
        LibraryAssert.AreEqual('', ADLSESetup.Container, 'Container');
        LibraryAssert.AreEqual('', ADLSESetup."Account Name", 'Account Name');
        LibraryAssert.AreEqual('', ADLSESetup.Workspace, 'Workspace');
        LibraryAssert.AreEqual('', ADLSESetup.Lakehouse, 'Lakehouse');
        LibraryAssert.AreEqual('', ADLSESetup.LandingZone, 'Landing Zone');
    end;

    [Test]
    procedure TestStorageType_AzureDataLake_ClearsS3Settings()
    var
        ADLSESetup: Record "ADLSE Setup";
    begin
        // [SCENARIO] Choosing another storage type clears the S3 settings
        // [GIVEN] A setup for S3
        Initialize();
        ADLSELibrarybc2adls.CreateAdlseSetup("Storage Type"::S3);
        ADLSESetup.Get(0);

        // [WHEN] The storage type is changed to Azure Data Lake
        ADLSESetup.Validate("Storage Type", "ADLSE Storage Type"::"Azure Data Lake");

        // [THEN] The S3 settings are cleared
        LibraryAssert.AreEqual('', ADLSESetup."S3 Endpoint", 'S3 Endpoint');
        LibraryAssert.AreEqual('', ADLSESetup."S3 Region", 'S3 Region');
        LibraryAssert.AreEqual('', ADLSESetup."S3 Bucket", 'S3 Bucket');
    end;

    [Test]
    procedure TestS3Endpoint_Https_IsAccepted()
    var
        ADLSESetup: Record "ADLSE Setup";
    begin
        // [SCENARIO] An https endpoint is accepted, without a trailing slash
        // [GIVEN] A setup for S3
        Initialize();
        ADLSELibrarybc2adls.CreateAdlseSetup("Storage Type"::S3);
        ADLSESetup.Get(0);

        // [WHEN] An https endpoint with a trailing slash is entered
        ADLSESetup.Validate("S3 Endpoint", 'https://fsn1.your-objectstorage.com/');

        // [THEN] It is kept without the trailing slash
        LibraryAssert.AreEqual('https://fsn1.your-objectstorage.com', ADLSESetup."S3 Endpoint", 'S3 Endpoint');
    end;

    [Test]
    procedure TestS3Endpoint_Http_IsRejected()
    var
        ADLSESetup: Record "ADLSE Setup";
    begin
        // [SCENARIO] A plain http endpoint is rejected, since request bodies are not signed and must travel over TLS
        // [GIVEN] A setup for S3
        Initialize();
        ADLSELibrarybc2adls.CreateAdlseSetup("Storage Type"::S3);
        ADLSESetup.Get(0);

        // [WHEN] An http endpoint is entered
        asserterror ADLSESetup.Validate("S3 Endpoint", 'http://fsn1.your-objectstorage.com');

        // [THEN] It is rejected
        LibraryAssert.ExpectedError('https://');
    end;

    [Test]
    procedure TestGetS3BucketUrl_JoinsEndpointAndBucket()
    var
        ADLSESetup: Record "ADLSE Setup";
    begin
        // [SCENARIO] The bucket is addressed path-style under the endpoint
        // [GIVEN] A setup for S3
        Initialize();
        ADLSELibrarybc2adls.CreateAdlseSetup("Storage Type"::S3);
        ADLSESetup.Get(0);

        // [WHEN] The bucket's URL is asked for
        // [THEN] It is the endpoint followed by the bucket
        LibraryAssert.AreEqual('https://fsn1.your-objectstorage.com/bc2adls', ADLSESetup.GetS3BucketUrl(), 'bucket URL');
    end;

    [Test]
    procedure TestCredentialsCheck_S3_DoesNotRequireTenantId()
    var
        ADLSECredentials: Codeunit "ADLSE Credentials";
    begin
        // [SCENARIO] S3 needs an access key id and a secret access key, but no tenant id
        // [GIVEN] A setup for S3 with an access key and no tenant id
        Initialize();
        ADLSELibrarybc2adls.CreateAdlseSetup("Storage Type"::S3);
        ADLSECredentials.SetTenantID('');
        ADLSECredentials.SetClientID('AKIAIOSFODNN7EXAMPLE');
        ADLSECredentials.SetClientSecret('wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY');

        // [WHEN] The credentials are checked
        // [THEN] No error is raised
        ADLSECredentials.Check();
    end;

    [Test]
    procedure TestCredentialsCheck_S3WithoutSecretAccessKey_Errors()
    var
        ADLSECredentials: Codeunit "ADLSE Credentials";
    begin
        // [SCENARIO] S3 cannot be used without a secret access key
        // [GIVEN] A setup for S3 with an access key id but no secret
        Initialize();
        ADLSELibrarybc2adls.CreateAdlseSetup("Storage Type"::S3);
        ADLSECredentials.SetTenantID('');
        ADLSECredentials.SetClientID('AKIAIOSFODNN7EXAMPLE');
        ADLSECredentials.SetClientSecret('');

        // [WHEN] The credentials are checked
        asserterror ADLSECredentials.Check();

        // [THEN] The missing secret is reported
        LibraryAssert.ExpectedError('adlse-client-secret');
    end;

    [Test]
    procedure TestCheckSetup_S3WithoutBucket_Errors()
    var
        ADLSESetup: Record "ADLSE Setup";
        ADLSESetupCodeunit: Codeunit "ADLSE Setup";
    begin
        // [SCENARIO] An export to S3 cannot start without a bucket
        // [GIVEN] A setup for S3 without a bucket
        Initialize();
        ADLSELibrarybc2adls.CreateAdlseSetup("Storage Type"::S3);
        ADLSESetup.Get(0);
        ADLSESetup."S3 Bucket" := '';
        ADLSESetup.Modify();

        // [WHEN] The setup is checked
        asserterror ADLSESetupCodeunit.CheckSetup(ADLSESetup);

        // [THEN] The missing bucket is reported
        LibraryAssert.ExpectedError(ADLSESetup.FieldCaption("S3 Bucket"));
    end;

    [Test]
    procedure TestSetupPage_S3_ShowsS3SettingsOnly()
    var
        ADLSESetupPage: TestPage "ADLSE Setup";
    begin
        // [SCENARIO] With S3 chosen, the setup page shows the S3 settings and access key, not the Azure or Fabric ones
        // [GIVEN] A setup for S3
        Initialize();
        ADLSELibrarybc2adls.CreateAdlseSetup("Storage Type"::S3);

        // [WHEN] The setup page is opened
        ADLSESetupPage.OpenEdit();

        // [THEN] Only the S3 connection settings are shown
        LibraryAssert.IsTrue(ADLSESetupPage.S3Endpoint.Visible(), 'S3 Endpoint should be visible');
        LibraryAssert.IsTrue(ADLSESetupPage.S3Region.Visible(), 'S3 Region should be visible');
        LibraryAssert.IsTrue(ADLSESetupPage.S3Bucket.Visible(), 'S3 Bucket should be visible');
        LibraryAssert.IsTrue(ADLSESetupPage.S3AccessKeyId.Visible(), 'Access key ID should be visible');
        LibraryAssert.IsTrue(ADLSESetupPage.S3SecretAccessKey.Visible(), 'Secret access key should be visible');
        LibraryAssert.IsFalse(ADLSESetupPage."Tenant ID".Visible(), 'Tenant ID should be hidden');
        LibraryAssert.IsFalse(ADLSESetupPage."Client ID".Visible(), 'Client ID should be hidden');
        LibraryAssert.IsFalse(ADLSESetupPage.Container.Visible(), 'Container should be hidden');
        LibraryAssert.IsFalse(ADLSESetupPage.Workspace.Visible(), 'Workspace should be hidden');
        ADLSESetupPage.Close();
    end;

    [Test]
    procedure TestSetupPage_AzureDataLake_HidesS3Settings()
    var
        ADLSESetupPage: TestPage "ADLSE Setup";
    begin
        // [SCENARIO] With Azure Data Lake chosen, the setup page hides the S3 settings
        // [GIVEN] A setup for Azure Data Lake
        Initialize();
        ADLSELibrarybc2adls.CreateAdlseSetup("Storage Type"::"Azure Data Lake");

        // [WHEN] The setup page is opened
        ADLSESetupPage.OpenEdit();

        // [THEN] The S3 settings are hidden and the Azure ones shown
        LibraryAssert.IsFalse(ADLSESetupPage.S3Endpoint.Visible(), 'S3 Endpoint should be hidden');
        LibraryAssert.IsFalse(ADLSESetupPage.S3AccessKeyId.Visible(), 'Access key ID should be hidden');
        LibraryAssert.IsTrue(ADLSESetupPage."Tenant ID".Visible(), 'Tenant ID should be visible');
        LibraryAssert.IsTrue(ADLSESetupPage.Container.Visible(), 'Container should be visible');
        ADLSESetupPage.Close();
    end;

    [Test]
    procedure TestSetupApi_SetsS3Settings()
    var
        ADLSESetup: Record "ADLSE Setup";
        LibraryGraphMgt: Codeunit "Library - Graph Mgt";
        TargetURL: Text;
        ResponseText: Text;
    begin
        // [SCENARIO] The setup API chooses S3 and sets its endpoint, region and bucket
        // [GIVEN] A setup for Azure Data Lake
        Initialize();
        ADLSELibrarybc2adls.CreateAdlseSetup("Storage Type"::"Azure Data Lake");
        ADLSESetup.Get(0);
        Commit(); // the web service request runs in a session of its own

        // [WHEN] S3 and its settings are patched through the setup API
        TargetURL := LibraryGraphMgt.CreateTargetURL(ADLSESetup.SystemId, Page::"ADLSE Setup API v12", 'adlseSetup');
        LibraryGraphMgt.PatchToWebService(TargetURL,
            '{"storageType":"S3","s3Endpoint":"https://fsn1.your-objectstorage.com","s3Region":"fsn1","s3Bucket":"malia-spike-test"}',
            ResponseText);

        // [THEN] The setup exports to that bucket on S3
        ADLSESetup.Get(0);
        LibraryAssert.AreEqual("ADLSE Storage Type"::S3, ADLSESetup."Storage Type", 'Storage type');
        LibraryAssert.AreEqual('https://fsn1.your-objectstorage.com/malia-spike-test', ADLSESetup.GetS3BucketUrl(), 'bucket URL');
        LibraryAssert.AreEqual('fsn1', ADLSESetup."S3 Region", 'S3 Region');
    end;

    local procedure Initialize()
    var
        LibraryTestInitialize: Codeunit "Library - Test Initialize";
    begin
        LibraryTestInitialize.OnTestInitialize(Codeunit::"ADLSE S3 Setup Tests");
        ADLSELibrarybc2adls.CleanUp();

        if IsInitialized then
            exit;

        LibraryTestInitialize.OnBeforeTestSuiteInitialize(Codeunit::"ADLSE S3 Setup Tests");

        IsInitialized := true;
        Commit();

        LibraryTestInitialize.OnAfterTestSuiteInitialize(Codeunit::"ADLSE S3 Setup Tests");
    end;
}
