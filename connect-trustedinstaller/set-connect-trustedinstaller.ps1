# 1. Paths
$agentPath = "C:\Program Files\PDQ\PDQConnectAgent\pdq-connect-agent.exe"
$appLockerXmlPath = "$PSScriptRoot\PDQ_AppLocker_MI.xml"

Write-Host "=== Registering PDQ Agent as Local Managed Installer ===" -ForegroundColor Cyan

# 2. Gather target metrics dynamically
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

# FIXED: Normalize three-part versions (X.Y.Z) to schema-compliant four-part versions (X.Y.Z.0)
if ($fileVersion -match '^\d+\.\d+\.\d+$') {
    $fileVersion = "$fileVersion.0"
}

Write-Host "Using Publisher: $publisherName" -ForegroundColor Green
Write-Host "Using Schema-Compliant Min Version: $fileVersion" -ForegroundColor Green

# 3. Create the precise clean AppLocker XML 
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
<RuleCollection Type="Exe" EnforcementMode="AuditOnly">
	<FilePathRule Id="921cc481-6e17-4653-8f75-050b80acca20" Name="Allow Windows" Description="Designates WINDIR as a trusted directory." UserOrGroupSid="S-1-1-0" Action="Allow">
		<Conditions><FilePathCondition Path="%WINDIR%\*" /></Conditions>
	</FilePathRule>
	<FilePathRule Id="a61c8b2c-a54b-4a64-8fc3-516956927f47" Name="Allow Program Files" Description="Designates PROGRAMFILES as a trusted directory." UserOrGroupSid="S-1-1-0" Action="Allow">
		<Conditions><FilePathCondition Path="%PROGRAMFILES%\*" /></Conditions>
	</FilePathRule>
</RuleCollection>
<RuleCollection Type="Dll" EnforcementMode="AuditOnly">
	<FilePathRule Id="c4be5962-96ae-48fa-97c4-aa1af7bf0222" Name="Allow Windows DLLs" Description="Designates WINDIR as a trusted directory." UserOrGroupSid="S-1-1-0" Action="Allow">
		<Conditions><FilePathCondition Path="%WINDIR%\*" /></Conditions>
	</FilePathRule>
	<FilePathRule Id="6a86e745-f09b-4654-8e42-70b135f13b2d" Name="Allow Program Files DLLs" Description="Designates PROGRAMFILES as a trusted directory." UserOrGroupSid="S-1-1-0" Action="Allow">
		<Conditions><FilePathCondition Path="%PROGRAMFILES%\*" /></Conditions>	</FilePathRule>
</RuleCollection>
</AppLockerPolicy>
"@

Set-Content -Path $appLockerXmlPath -Value $appLockerXmlTemplate -Encoding UTF8
Write-Host "XML saved to: $appLockerXmlPath" -ForegroundColor Yellow

# 4. Apply the policy locally and ensure the Identity Engine is handling it
try {
    Write-Host "Applying policy to local AppLocker store..." -ForegroundColor Yellow
    Set-AppLockerPolicy -XmlPolicy $appLockerXmlPath -Merge -ErrorAction Stop
    
    Write-Host "Ensuring Application Identity Service (AppIDSvc) is active..." -ForegroundColor Yellow
    Start-Service AppIDSvc -ErrorAction SilentlyContinue
    
    Write-Host "`n=== SUCCESS! ===" -ForegroundColor Green
    Write-Host "The local machine now recognizes the PDQ Agent as an authorized Managed Installer." -ForegroundColor White
    $AppLockerPolicy = Get-AppLockerPolicy -Effective -xml
    Write-Host "This is the effective policy xml:`n$AppLockerPolicy"

}
catch {
    Write-Error "Failed to apply local policy store mapping. Details: $_"
}
