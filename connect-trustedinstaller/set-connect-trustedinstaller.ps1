$agentPath = "C:\Program Files\PDQ\PDQConnectAgent\pdq-connect-agent.exe"
$appLockerXmlPath = "$PSScriptRoot\PDQ_AppLocker_MI.xml"

Write-Host "=== Registering PDQ Agent as Local Managed Installer ===" -ForegroundColor Cyan

if (-not (Test-Path $agentPath)) {
    Write-Error "PDQ Connect Agent file missing at '$agentPath'."
    exit
}

$signature = Get-AuthenticodeSignature $agentPath
if ($null -eq $signature.SignerCertificate) {
    Write-Error "The binary at $agentPath is not digitally signed."
    exit
}

$publisherName = $signature.SignerCertificate.Subject
$fileVersion = (Get-Item $agentPath).VersionInfo.ProductVersion
if ($null -eq $fileVersion) { 
    $fileVersion = "1.0.0.0" 
}

if ($fileVersion -match '^\d+\.\d+\.\d+$') {
    $fileVersion = "$fileVersion.0"
}

Write-Host "Using Publisher: $publisherName" -ForegroundColor Green
Write-Host "Using Schema-Compliant Min Version: $fileVersion" -ForegroundColor Green

$appLockerXmlTemplate = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="ManagedInstaller" EnforcementMode="AuditOnly">
    <FilePublisherRule Id="e91264be-3bc2-4cb6-ba4a-7bc9bda99e90" Name="Allow PDQ Connect Agent to stamp applications" Description="Designates the PDQ Connect Agent as an authorized software deployment source." UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="$publisherName" ProductName="*" BinaryName="pdq-connect-agent.exe">
          <BinaryVersionRange LowSection="$fileVersion" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
  </RuleCollection>
  <RuleCollection Type="Exe" EnforcementMode="AuditOnly" />
  <RuleCollection Type="Dll" EnforcementMode="AuditOnly" />
</AppLockerPolicy>
"@

Set-Content -Path $appLockerXmlPath -Value $appLockerXmlTemplate -Encoding UTF8
Write-Host "XML saved to: $appLockerXmlPath" -ForegroundColor Yellow

try {
    Write-Host "Applying policy to local AppLocker store..." -ForegroundColor Yellow
    Set-AppLockerPolicy -XmlPolicy $appLockerXmlPath -Merge -ErrorAction Stop
    
    Write-Host "Ensuring Application Identity Service (AppIDSvc) is active..." -ForegroundColor Yellow
    Start-Service AppIDSvc -ErrorAction SilentlyContinue
    
    Write-Host "`n=== SUCCESS! ===" -ForegroundColor Green
    Write-Host "The local machine now recognizes the PDQ Agent as an authorized Managed Installer." -ForegroundColor White
}
catch {
    Write-Error "Failed to apply local policy store mapping. Details: $_"
}
