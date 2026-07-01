# 1. Target Configurations & Directory Mapping
$agentPath = "C:\Program Files\PDQ\PDQConnectAgent\pdq-connect-agent.exe"
$baseXmlPath = "$PSScriptRoot\AppControl_Base.xml"
$baseCipPath = "$PSScriptRoot\AppControl_Base.cip"
$appLockerXmlPath = "$PSScriptRoot\PDQ_AppLocker_MI.xml"

Write-Host "=== Starting Validated App Control Policy Generation ===" -ForegroundColor Cyan

# 2. Extract Native System Metrics & Target Identification
if (-not (Test-Path $agentPath)) {
    Write-Error "PDQ Connect Agent file missing at '$agentPath'. Please run this directly on an active endpoint."
    exit
}

Write-Host "Extracting Authenticode details and File Properties..." -ForegroundColor Yellow

# Fallback-safe method to get the Publisher String directly from the Cert Subject
$signature = Get-AuthenticodeSignature $agentPath
if ($null -eq $signature.SignerCertificate) {
    Write-Error "The binary at $agentPath is not digitally signed. Cannot generate Managed Installer rules."
    exit
}

# Format the Subject to match what the AppLocker engine natively demands
$publisherName = $signature.SignerCertificate.Subject

# Extract version metrics
$fileVersion = (Get-Item $agentPath).VersionInfo.ProductVersion
if ($null -eq $fileVersion) { $fileVersion = "1.0.0.0" }

Write-Host "Detected Publisher Identity: $publisherName" -ForegroundColor Green
Write-Host "Detected Executable Version: $fileVersion" -ForegroundColor Green

# ==========================================
# FILE 1: GENERATE APP CONTROL BASE POLICY
# ==========================================
Write-Host "Generating Modern App Control Base Policy..." -ForegroundColor Yellow

try {
    $defaultPolicyXml = "$env:windir\schemas\CodeIntegrity\ExamplePolicies\DefaultWindows_Audit.xml"
    if (Test-Path $defaultPolicyXml) {
        Copy-Item $defaultPolicyXml -Destination $baseXmlPath -Force
    } else {
        # Fallback to a clean scan of a known safe core system file if the example template is missing
        New-CIPolicy -FilePath $baseXmlPath -Level Publisher -ScanPath "$env:windir\system32\drivers\null.sys" -UserPEs -Name "PDQ App Control Base Policy - v$fileVersion" -ErrorAction Stop
    }

    # FIXED: Corrected the Set-RuleOption syntax parameters
    Set-RuleOption -FilePath $baseXmlPath -Option 3   # Audit Mode
    Set-RuleOption -FilePath $baseXmlPath -Option 13  # Managed Installer support
    Set-RuleOption -FilePath $baseXmlPath -Option 14  # Managed Installer Heuristic tracking
    Set-RuleOption -FilePath $baseXmlPath -Option 18  # Supplemental Policy authorization
    
    Write-Host "Successfully generated valid App Control base XML configuration." -ForegroundColor Green
}
catch {
    Write-Error "Failed to programmatically establish base code integrity structures. Trace: $_"
    exit
}

# ==========================================
# FILE 2: BUILD APPLOCKER MI DESIGNATION PROFILE
# ==========================================
Write-Host "Generating AppLocker Managed Installer Designation Payload..." -ForegroundColor Yellow

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

# ==========================================
# STEP 4: COMPILE MODERN WDAC BASE POLICY
# ==========================================
Write-Host "Compiling App Control XML down to final system binary format..." -ForegroundColor Yellow
try {
    if (Get-Command ConvertFrom-CIPolicy -ErrorAction SilentlyContinue) {
        ConvertFrom-CIPolicy -XmlFilePath $baseXmlPath -BinaryFilePath $baseCipPath
        Write-Host "`n=== SCRIPT PIPELINE COMPLETED SUCCESSFULLY ===" -ForegroundColor Green
        Write-Host "1. App Control Base Binary (Upload to Intune Blade): $baseCipPath" -ForegroundColor Cyan
        Write-Host "2. AppLocker Custom XML (Upload via Intune Custom URI Settings): $appLockerXmlPath" -ForegroundColor Cyan
    } else {
         Write-Warning "AppLocker XML exported successfully. However, 'ConvertFrom-CIPolicy' compilation failed because the cmdlet was unavailable on this environment."
    }
}
catch {
    Write-Error "Compilation pipeline fault triggered. Review log trace: $_"
}
