# 1. Configuration & Paths
$agentPath = "C:\Program Files\PDQ\PDQConnectAgent\pdq-connect-agent.exe"
$xmlOutputPath = "$PSScriptRoot\PDQConnect_ManagedInstaller.xml"
$cipOutputPath = "$PSScriptRoot\PDQConnect_ManagedInstaller.cip"

Write-Host "=== Starting App Control Policy Builder ===" -ForegroundColor Cyan

# 2. Safety Checks
if (-not (Test-Path $agentPath)) {
    Write-Error "PDQ Connect Agent not found at $agentPath."
    exit
}

# 3. Gather Executable Metrics (TBS Hash & Version)
Write-Host "Extracting Authenticode Signature and File Version..." -ForegroundColor Yellow

$signature = Get-AuthenticodeSignature $agentPath
if ($null -eq $signature.SignerCertificate) {
    Write-Error "The binary at $agentPath is not digitally signed."
    exit
}

# Get raw public key block converted to a hexadecimal string
$rawCertBytes = $signature.SignerCertificate.GetRawCertData()
$tbsHash = [System.BitConverter]::ToString($rawCertBytes).Replace("-", "")

# Extract the string version of the file
$fileVersion = (Get-Item $agentPath).VersionInfo.ProductVersion
if ($null -eq $fileVersion) {
    $fileVersion = "1.0.0.0" # Fallback if version string is missing
}

Write-Host "Extracted TBS Hash: $tbsHash" -ForegroundColor Green
Write-Host "Detected Executable Version: $fileVersion" -ForegroundColor Green

# 4. Generate Production Identifiers
$newGuid = [guid]::NewGuid().ToString().ToUpper()
$policyName = "PDQ Connect Managed Installer Policy - v$fileVersion"

# 5. Build the Dynamic XML String Configuration
$xmlTemplate = @"
<?xml version="1.0" encoding="utf-8"?>
<SiPolicy xmlns="urn:schemas-microsoft-com:sipolicy" PolicyType="Base Policy">
  <VersionEx>1.0.0.0</VersionEx>
  <PolicyID>{$newGuid}</PolicyID>
  <BasePolicyID>{$newGuid}</BasePolicyID>
  <Settings>
    <Setting Provider="PolicyInfo" Key="Information" ValueName="Name">
      <Value>
        <String>$policyName</String>
      </Value>
    </Setting>
  </Settings>

  <Rules>
    <Rule>
      <Option>Enabled:Audit Mode</Option>
    </Rule>
    <Rule>
      <Option>Enabled:Managed Installer Heuristic 1</Option>
    </Rule>
    <Rule>
      <Option>Enabled:Allow Supplemental Policies</Option>
    </Rule>
  </Rules>

  <ManagedInstallers>
    <Rules>
      <FilePublisherRule ID="ID_RULE_PDQ_AGENT" FriendlyName="Allow PDQ Connect Agent" Action="Allow">
        <FileAttrib Name="pdq-connect-agent.exe" MinimumFileVersion="$fileVersion" />
        <PublisherSigner SignerId="ID_SIGNER_PDQ" />
      </FilePublisherRule>
    </Rules>
  </ManagedInstallers>

  <Signers>
    <Signer ID="ID_SIGNER_PDQ" Name="PDQ.com Corporation">
      <CertRoot Type="TBS" Value="$tbsHash" />
    </Signer>
  </Signers>

  <AllowedSigners>
    <AllowedSigner SignerId="ID_SIGNER_PDQ" />
  </AllowedSigners>
</SiPolicy>
"@

# 6. Export the complete customized text mapping out to an XML file
Write-Host "Saving XML configuration to: $xmlOutputPath" -ForegroundColor Yellow
Set-Content -Path $xmlOutputPath -Value $xmlTemplate -Encoding UTF8

# 7. Convert raw XML to the required binary schema format (.cip)
Write-Host "Compiling structural policy payload into device binary code format..." -ForegroundColor Yellow
try {
    if (Get-Command ConvertFrom-SiPolicy -ErrorAction SilentlyContinue) {
        ConvertFrom-SiPolicy -XmlFilePath $xmlOutputPath -BinaryFilePath $cipOutputPath
        Write-Host "=== Success! ===" -ForegroundColor Green
        Write-Host "Policy Generated: $policyName" -ForegroundColor White
        Write-Host "Ready for upload to Intune: $cipOutputPath" -ForegroundColor Cyan
    } else {
         Write-Warning "XML file written out. However, 'ConvertFrom-SiPolicy' compilation failed. Ensure you run this inside an Enterprise/Pro build."
    }
}
catch {
    Write-Error "Could not complete engine compilation phase. Context: $_"
}
