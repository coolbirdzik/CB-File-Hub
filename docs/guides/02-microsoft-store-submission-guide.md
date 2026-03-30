# Microsoft Store Submission Guide

## Required Store Identity

These values must match Microsoft Partner Center exactly:

| Field | Value |
|---|---|
| `Package/Identity/Name` | `CoolBirdZik.CBFileHub` |
| `Package/Identity/Publisher` | `CN=C193F601-16B4-4BC5-89D3-1AE882F628DE` |
| `Package/Properties/PublisherDisplayName` | `CoolBirdZik` |

They are configured in `cb_file_manager/pubspec.yaml`.

## 1. Prepare a Signing Certificate

You need a `.pfx` certificate whose **Subject** matches:

```text
CN=C193F601-16B4-4BC5-89D3-1AE882F628DE
```

For local testing, you can create one with PowerShell:

```powershell
$subject = "CN=C193F601-16B4-4BC5-89D3-1AE882F628DE"
$cert = New-SelfSignedCertificate -Type Custom -Subject $subject -CertStoreLocation "Cert:\CurrentUser\My" -KeyUsage DigitalSignature -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3")
$password = ConvertTo-SecureString "ReplaceWithStrongPassword" -AsPlainText -Force
Export-PfxCertificate -Cert $cert -FilePath "$PWD\cb-file-hub-signing.pfx" -Password $password
```

## 2. Add GitHub Secrets

Create these repository secrets:

- `MSIX_CERT_BASE64`
- `MSIX_CERT_PASSWORD`
- `MSIX_PUBLISHER`

Convert `.pfx` to base64:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes(".\cb-file-hub-signing.pfx")) | Set-Clipboard
```

Set:

- `MSIX_CERT_BASE64`: base64 string of the `.pfx`
- `MSIX_CERT_PASSWORD`: password of the `.pfx`
- `MSIX_PUBLISHER`: `CN=C193F601-16B4-4BC5-89D3-1AE882F628DE`

## 3. Build the Signed MSIX

Push a release tag or run the release workflow manually.

The pipeline will:

1. Restore the `.pfx` from `MSIX_CERT_BASE64`
2. Build the Windows MSIX
3. Sign it with the certificate
4. Upload the `.msix` artifact to the GitHub Release

## 4. Verify Before Submission

Check the built MSIX locally:

```powershell
Get-AuthenticodeSignature .\CBFileManager-1.0.0.msix | Format-List Status,SignerCertificate
(Get-AuthenticodeSignature .\CBFileManager-1.0.0.msix).SignerCertificate.Subject
```

Expected:

- `Status` is `Valid`
- `Subject` is `CN=C193F601-16B4-4BC5-89D3-1AE882F628DE`

## 5. Submit to Microsoft Store

In Partner Center:

1. Open the app submission page
2. Upload the generated `.msix`
3. Confirm package identity matches Partner Center
4. Complete store listing fields
5. Submit for certification
