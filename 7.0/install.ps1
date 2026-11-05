#requires -Version 5.1
<# Wersja instalatora: 0.2.2. Samodzielny instalator Zabbix Agent 2 7.0 LTS.
Poprawki: podmiana konfiguracji w PowerShell 5.1; log wyłącznie na pulpicie.
#>
[CmdletBinding()]
param(
    [string]$Mode = 'passive',
    [string]$Server,
    [AllowEmptyString()][string]$ServerActive,
    [AllowEmptyString()][string]$HostnamePrefix,
    [string]$LocalAddress,
    [string]$InterfaceAddress,
    [string]$ListenPort = '10050',
    [switch]$Upgrade,
    [switch]$NonInteractive,
    [switch]$Yes,
    [switch]$DryRun,
    [switch]$Help
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
# Oficjalny artefakt HTTPS; suma i podpis sprawdzone 2026-11-03.
$AgentVersion = '7.0.32'
$PackageUrl = 'https://cdn.zabbix.com/zabbix/binaries/stable/7.0/7.0.32/zabbix_agent2-7.0.32-windows-amd64-openssl.msi'
$PackageSha256 = 'B91069F7372F05F704CC31C021561F4E9558EBE2C45D7956A9C841221C357ED6'
$PublisherSubject = 'CN=Zabbix SIA, O=Zabbix SIA, L=Riga, C=LV'
$ServiceName = 'Zabbix Agent 2'
$script:LogFile = $null
$workPath = $null
$backupPath = $null
$stagedPath = $null
$mutation = $false
$wasRunning = $false
$oldStartMode = $null
$oldDelayedStart = 0
$lockStream = $null
$exitCode = 0

function Write-Status {
    param([string]$Message)
    Write-Output $Message
    if ($script:LogFile) { Add-Content -LiteralPath $script:LogFile -Value ('{0:o} {1}' -f (Get-Date), $Message) -Encoding UTF8 }
}
function Set-AgentConfigurationFile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Source, [string]$Destination)
    if (-not $PSCmdlet.ShouldProcess($Destination, 'Atomowa podmiana konfiguracji')) { return }
    # W PowerShell 5.1 $null bywa wiązany jako pusty string: File.Replace go odrzuca.
    $temporaryBackup = Join-Path ([IO.Path]::GetDirectoryName($Destination)) ('previous-' + [guid]::NewGuid().ToString('N') + '.tmp')
    if ([IO.File]::Exists($Destination)) {
        [IO.File]::Replace($Source, $Destination, $temporaryBackup)
        Remove-Item -LiteralPath $temporaryBackup -Force
    } else { [IO.File]::Move($Source, $Destination) }
}
function Initialize-DesktopLog {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$RunId, [string]$DesktopPath)
    if (-not $DesktopPath) {
        $DesktopPath = [Environment]::GetFolderPath('DesktopDirectory')
        if ([Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) { $DesktopPath = [Environment]::GetFolderPath('CommonDesktopDirectory') }
    }
    if (-not $DesktopPath -or -not (Test-Path -LiteralPath $DesktopPath -PathType Container)) { throw 'Brak dostępnego pulpitu do zapisu logu instalatora.' }
    $path = Join-Path $DesktopPath ("Zabbix-install-$RunId.log")
    if ($PSCmdlet.ShouldProcess($path, 'Utworzenie logu na pulpicie')) {
        $stream = [IO.File]::Open($path, 'CreateNew', 'Write', 'None')
        $stream.Dispose()
        return $path
    }
}
function Test-IPv4 {
    param([string]$Value)
    if ($Value -notmatch '^([0-9]{1,3}\.){3}[0-9]{1,3}$') { return $false }
    foreach ($part in $Value.Split('.')) {
        if (($part.Length -gt 1 -and $part.StartsWith('0')) -or [int]$part -gt 255) { return $false }
    }
    $parts = $Value.Split('.')
    return ([int]$parts[0] -gt 0 -and [int]$parts[0] -lt 224 -and $parts[0] -ne '127' -and "$($parts[0]).$($parts[1])" -ne '169.254')
}
function Test-Port {
    param([string]$Value, [int]$Minimum, [int]$Maximum)
    return ($Value -match '^[0-9]{1,5}$' -and [int]$Value -ge $Minimum -and [int]$Value -le $Maximum)
}
function Set-PrivateDirectory {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Path)
    if (-not $PSCmdlet.ShouldProcess($Path, 'Utworzenie i ochrona katalogu')) { return }
    if (Test-Path -LiteralPath $Path) {
        if ((Get-Item -LiteralPath $Path).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Katalog roboczy jest dowiązaniem. Wymagany ręczny przegląd.' }
    } else { New-Item -ItemType Directory -Path $Path | Out-Null }
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in @('S-1-5-18', 'S-1-5-32-544')) {
        $identity = New-Object Security.Principal.SecurityIdentifier($sid)
        $rule = New-Object Security.AccessControl.FileSystemAccessRule($identity, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
}
function Read-AgentConfiguration {
    param([string]$Path, [bool]$Main, [hashtable]$Visited)
    $fullPath = [IO.Path]::GetFullPath($Path)
    if ($Visited.ContainsKey($fullPath)) { throw 'Powtórzony lub cykliczny Include. Wymagany ręczny przegląd.' }
    $Visited[$fullPath] = $true
    $item = Get-Item -LiteralPath $fullPath
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Niestandardowy plik konfiguracji. Wymagany ręczny przegląd.' }
    $strictUtf8 = New-Object Text.UTF8Encoding($false, $true)
    $text = [IO.File]::ReadAllText($fullPath, $strictUtf8)
    foreach ($line in ($text -split '\r?\n')) {
        if ($line -match '^\s*([^#;\s=]+)\s*=\s*(.*?)\s*$') {
            $key = $Matches[1]; $value = $Matches[2]
            if ($key -cmatch '^TLS' -or $key -cin @('HostMetadata','HostMetadataItem','HostInterface','HostInterfaceItem')) { throw 'Wykryto TLS lub ustawienia autorejestracji. Wymagany ręczny przegląd.' }
            if (-not $Main -and $key -cin @('Server','ServerActive','Hostname','ListenIP','ListenPort')) { throw 'Konflikt zarządzanych ustawień w Include. Wymagany ręczny przegląd.' }
            if ($key -ceq 'Include') {
                if (-not [IO.Path]::IsPathRooted($value)) { $value = Join-Path ([IO.Path]::GetDirectoryName($fullPath)) $value }
                foreach ($child in @(Get-ChildItem -Path $value -File -ErrorAction Stop)) {
                    $null = Read-AgentConfiguration -Path $child.FullName -Main $false -Visited $Visited
                }
                if (-not [Management.Automation.WildcardPattern]::ContainsWildcardCharacters($value) -and -not (Test-Path -LiteralPath $value)) { throw 'Brak pliku lub katalogu Include. Wymagany ręczny przegląd.' }
            }
        }
    }
    return $text
}
function ConvertTo-AgentConfiguration {
    param([string]$Text, [System.Collections.IDictionary]$Settings)
    $seen = @{}
    $lines = New-Object 'Collections.Generic.List[string]'
    foreach ($line in ($Text.TrimEnd("`r", "`n") -split '\r?\n')) {
        if ($line -match '^\s*([^#;\s=]+)\s*=' -and $Settings.Contains($Matches[1])) {
            $key = $Matches[1]
            if (-not $seen.ContainsKey($key)) { $lines.Add("$key=$($Settings[$key])"); $seen[$key] = $true }
        } else { $lines.Add($line) }
    }
    foreach ($key in $Settings.Keys) { if (-not $seen.ContainsKey($key)) { $lines.Add("$key=$($Settings[$key])") } }
    return (($lines -join "`r`n") + "`r`n")
}
function Get-FirewallSnapshot {
    # Odczyt całej lokalnej polityki umożliwia wykrycie zmian reguł i filtrów MSI.
    $rules = @(Get-NetFirewallRule -PolicyStore PersistentStore | Sort-Object Name | Select-Object Name, Enabled, Direction, Action, Profile)
    $ports = @(Get-NetFirewallPortFilter -PolicyStore PersistentStore | Sort-Object InstanceID | Select-Object InstanceID, Protocol, LocalPort, RemotePort)
    $addresses = @(Get-NetFirewallAddressFilter -PolicyStore PersistentStore | Sort-Object InstanceID | Select-Object InstanceID, LocalAddress, RemoteAddress)
    $applications = @(Get-NetFirewallApplicationFilter -PolicyStore PersistentStore | Sort-Object InstanceID | Select-Object InstanceID, Program, Package)
    return (ConvertTo-Json -InputObject @($rules, $ports, $addresses, $applications) -Depth 6 -Compress)
}
function Invoke-AgentValidation {
    param([string]$Binary, [string]$Path)
    # Agent może wypisać obce ustawienia przy błędzie; nie zapisujemy jego wyjścia.
    try { $null = & $Binary -c $Path -T 2>&1 }
    catch { throw 'Walidacja konfiguracji agenta nie powiodła się. Wymagany ręczny przegląd.' }
    if ($LASTEXITCODE -ne 0) { throw 'Walidacja konfiguracji agenta nie powiodła się. Wymagany ręczny przegląd.' }
}
function ConvertFrom-AgentVersion {
    param([string[]]$OutputLines, [int]$ExitCode)
    if ($ExitCode -ne 0 -or $OutputLines.Count -eq 0) { throw 'Nie można odczytać wersji pliku agenta.' }
    # Zachowaj granice wierszy: 7.0.32 i Revision nie mogą stać się 7.0.32Revision.
    $banner = $OutputLines[0].Trim()
    if ($banner -notmatch '^zabbix_agent2\b[^\r\n]*\(Zabbix\)\s+([0-9]+\.[0-9]+\.[0-9]+)\s*$') { throw 'Nie rozpoznano nagłówka wersji Zabbix Agent 2.' }
    $version = [version]$Matches[1]
    if ($version.Major -ne 7 -or $version.Minor -ne 0) { throw 'Wersja pliku agenta jest spoza obsługiwanej linii 7.0.x.' }
    return $version
}
function Get-AgentBinaryVersion {
    param([string]$Binary)
    try {
        $outputLines = @(& $Binary -V 2>&1 | ForEach-Object { [string]$_ })
        $code = $LASTEXITCODE
    } catch { throw 'Nie można uruchomić odczytu wersji pliku agenta.' }
    return ConvertFrom-AgentVersion -OutputLines $outputLines -ExitCode $code
}

if ($Help) {
    @'
Instalator Zabbix Agent 2 7.0 LTS, wersja 0.2.2; Windows PowerShell 5.1.
Windows x64: Windows 10/11 (kompilacja >=17763), Server 2019/2022/2025.
Bez parametrów uruchamia kreator. Instalacja wymaga administratora.
-Server IPv4                Wymagany adres serwera lub wybranego proxy
-ServerActive IPv4[:port]   Domyślnie aktualny Server i port 10051
-HostnamePrefix TEKST      Wymagany jawny prefiks; dopuszczalne ''
-LocalAddress IPv4         Lokalny IPv4 nasłuchu
-InterfaceAddress IPv4     Propozycja adresu do GUI Zabbix (także NAT)
-ListenPort PORT           1024–32767, domyślnie 10050
-Mode passive|active       Domyślnie passive
-Upgrade                   Jawna aktualizacja do przypiętej wersji, bez downgrade
-NonInteractive            Bez pytań; wymagane -Yes albo -DryRun
-Yes                       Pomiń końcowe potwierdzenie
-DryRun                    Plan bez pobierania, zapisu i zmian usług
-Help                      Pomoc bez uprawnień administratora
Skrypt nie konfiguruje zapory ani serwera Zabbix; nowa konfiguracja bez TLS.
'@
    exit 0
}

try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Uruchom Windows PowerShell jako administrator.' }
    $os = Get-CimInstance Win32_OperatingSystem
    if (-not [Environment]::Is64BitOperatingSystem -or -not [Environment]::Is64BitProcess -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64' -or [int]$os.BuildNumber -lt 17763) { throw 'Obsługiwany jest Windows x64 od kompilacji 17763, w 64-bitowym PowerShell.' }
    $installPath = Join-Path $env:ProgramFiles 'Zabbix Agent 2'
    $configPath = Join-Path $installPath 'zabbix_agent2.conf'
    $binaryPath = Join-Path $installPath 'zabbix_agent2.exe'
    $rootPath = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'ZabbixAgentAutoDeploy'
    $runId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N')
    if (-not $DryRun) {
        $script:LogFile = Initialize-DesktopLog -RunId $runId
        Write-Status 'Rozpoczęto sprawdzanie parametrów i przygotowanie instalacji.'
    }
    $adapters = @(Get-NetAdapter | Where-Object Status -eq 'Up')
    $addresses = @(Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.AddressState -eq 'Preferred' -and $_.InterfaceIndex -in $adapters.ifIndex -and (Test-IPv4 $_.IPAddress) } | Sort-Object IPAddress -Unique)
    if ($addresses.Count -eq 0) { throw 'Nie wykryto lokalnego IPv4 na aktywnych interfejsach.' }
    foreach ($address in $addresses) { Write-Output ('Lokalny IPv4: {0} ({1})' -f $address.IPAddress, $address.InterfaceAlias) }
    if (-not $NonInteractive) {
        if (-not $PSBoundParameters.ContainsKey('Server')) { $Server = Read-Host 'IPv4 serwera lub właściwego proxy' }
        if (-not $PSBoundParameters.ContainsKey('ServerActive')) { $ServerActive = Read-Host "ServerActive [$($Server):10051]" }
        if (-not $PSBoundParameters.ContainsKey('HostnamePrefix')) { $HostnamePrefix = Read-Host 'Prefiks nazwy hosta (może być pusty)' }
        if (-not $PSBoundParameters.ContainsKey('Mode')) { $answer = Read-Host 'Mode [passive/active, domyślnie passive]'; if ($answer) { $Mode = $answer } }
        if (-not $PSBoundParameters.ContainsKey('LocalAddress')) {
            $suggestion = ''; if ($addresses.Count -eq 1) { $suggestion = $addresses[0].IPAddress }
            $LocalAddress = Read-Host "Lokalny IPv4 [$suggestion]"; if (-not $LocalAddress) { $LocalAddress = $suggestion }
        }
        if (-not $PSBoundParameters.ContainsKey('InterfaceAddress')) { $InterfaceAddress = Read-Host "Propozycja IPv4 do GUI [$LocalAddress]" }
    } elseif (-not $PSBoundParameters.ContainsKey('HostnamePrefix')) { throw 'Podaj -HostnamePrefix, także świadomie pusty.' }
    if (-not (Test-IPv4 $Server)) { throw 'Server musi być pojedynczym poprawnym IPv4.' }
    if ($Mode -cnotin @('passive', 'active')) { throw 'Mode musi mieć wartość passive albo active.' }
    if (-not $ServerActive -and -not $PSBoundParameters.ContainsKey('ServerActive')) { $ServerActive = "$($Server):10051" }
    if ($ServerActive -notmatch '^([^:]+)(?::([0-9]{1,5}))?$') { throw 'Nieprawidłowy ServerActive.' }
    $activeIp = $Matches[1]; $activePort = '10051'; if ($Matches[2]) { $activePort = $Matches[2] }
    if (-not (Test-IPv4 $activeIp) -or -not (Test-Port -Value $activePort -Minimum 1 -Maximum 65535)) { throw 'Nieprawidłowy IPv4 lub port ServerActive.' }
    $ServerActive = '{0}:{1}' -f $activeIp, [int]$activePort
    if (-not (Test-Port -Value $ListenPort -Minimum 1024 -Maximum 32767)) { throw 'ListenPort musi należeć do zakresu 1024–32767.' }
    $ListenPort = ([int]$ListenPort).ToString()
    if (-not $LocalAddress -and $addresses.Count -eq 1 -and -not $PSBoundParameters.ContainsKey('LocalAddress')) { $LocalAddress = $addresses[0].IPAddress }
    if (-not (Test-IPv4 $LocalAddress) -or $LocalAddress -notin $addresses.IPAddress) { throw 'Wskaż IPv4 przypisany do aktywnego lokalnego interfejsu przez -LocalAddress.' }
    if (-not $InterfaceAddress -and -not $PSBoundParameters.ContainsKey('InterfaceAddress')) { $InterfaceAddress = $LocalAddress }
    if (-not (Test-IPv4 $InterfaceAddress)) { throw 'InterfaceAddress musi być poprawnym IPv4.' }
    $hostNameValue = $HostnamePrefix + [Environment]::MachineName
    if ($hostNameValue -cnotmatch '^[A-Za-z0-9._-]{1,128}$') { throw 'Wynikowy Hostname jest nieprawidłowy lub przekracza 128 znaków.' }
    if ($NonInteractive -and -not $Yes -and -not $DryRun) { throw '-NonInteractive wymaga -Yes albo -DryRun.' }

    $services = @(Get-CimInstance Win32_Service | Where-Object { $_.Name -like '*Zabbix*' -or $_.PathName -match 'zabbix_agent' })
    if (@($services | Where-Object Name -ne $ServiceName).Count -gt 0 -or $services.Count -gt 1) { throw 'Wykryto klasycznego agenta lub wiele instancji. Wymagany ręczny przegląd.' }
    $registryPaths = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')
    $products = @(Get-ItemProperty -Path $registryPaths -ErrorAction SilentlyContinue | Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -like 'Zabbix Agent*' })
    if ($products.Count -gt 1 -or @($products | Where-Object DisplayName -notlike 'Zabbix Agent 2*').Count -gt 0) { throw 'Niejednoznaczna instalacja MSI lub klasyczny agent. Wymagany ręczny przegląd.' }
    $installedVersion = $null
    if ($services.Count -eq 1) {
        $serviceInfo = $services[0]
        $expectedCommand = '^"?' + [regex]::Escape($binaryPath) + '"?\s+(?:-c|--config)\s+"?' + [regex]::Escape($configPath) + '"?(?:\s+-f=false)?\s*$'
        if ($serviceInfo.PathName -notmatch $expectedCommand -or $products.Count -ne 1 -or -not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw 'Niestandardowa instalacja, ścieżka lub usługa. Wymagany ręczny przegląd.' }
        $productVersion = [version]$products[0].DisplayVersion
        $installedVersion = New-Object version($productVersion.Major, $productVersion.Minor, $productVersion.Build)
        if ($installedVersion.Major -ne 7 -or $installedVersion.Minor -ne 0) { throw 'Istniejący agent jest spoza linii 7.0.x.' }
        $wasRunning = $serviceInfo.State -eq 'Running'; $oldStartMode = $serviceInfo.StartMode
        $serviceRegistry = Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
        if ($serviceRegistry.PSObject.Properties['DelayedAutoStart']) { $oldDelayedStart = $serviceRegistry.DelayedAutoStart }
    } elseif ($products.Count -gt 0 -or (Test-Path -LiteralPath $installPath)) { throw 'Pozostałości instalacji bez standardowej usługi. Wymagany ręczny przegląd.' }
    if ($Upgrade -and $installedVersion -and $installedVersion -gt [version]$AgentVersion) { throw 'Downgrade jest zabroniony.' }
    $installNeeded = (-not $installedVersion) -or ($Upgrade -and $installedVersion -lt [version]$AgentVersion)
    $originalText = $null
    $agentProcesses = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -in @('zabbix_agentd.exe','zabbix_agent2.exe') })
    if ($agentProcesses.Count -gt 1 -or ($agentProcesses.Count -eq 1 -and ($services.Count -eq 0 -or $agentProcesses[0].ProcessId -ne $services[0].ProcessId))) { throw 'Wykryto agenta poza rozpoznaną usługą. Wymagany ręczny przegląd.' }
    if ($installedVersion) { $originalText = Read-AgentConfiguration -Path $configPath -Main $true -Visited @{} }
    $settings = [ordered]@{Server=$Server; ServerActive=$ServerActive; Hostname=$hostNameValue; ListenIP=$LocalAddress; ListenPort=$ListenPort}
    $baseText = $originalText
    if ($null -eq $baseText) { $baseText = "LogType=file`r`nLogFile=$installPath\zabbix_agent2.log`r`n" }
    $targetText = ConvertTo-AgentConfiguration -Text $baseText -Settings $settings
    $changed = $targetText -cne $originalText
    Write-Output "Plan: Zabbix Agent 2 $AgentVersion; obecnie: $installedVersion; instalacja/aktualizacja: $installNeeded"
    Write-Output "Server=$Server; ServerActive=$ServerActive; Hostname=$hostNameValue; Mode=$Mode"
    Write-Output "ListenIP=$($LocalAddress):$ListenPort; GUI=$($InterfaceAddress):$ListenPort; zmiana konfiguracji: $changed"
    Write-Output "Źródło przypiętego pakietu: $PackageUrl"
    if ($DryRun) { Write-Output 'DryRun: nie wykonano zmian ani pobierania. Dostępność pakietu zostanie sprawdzona przed instalacją.'; exit 0 }
    if (-not $Yes -and (Read-Host 'Wykonać plan? Wpisz TAK') -cne 'TAK') { throw 'Anulowano.' }
    Set-PrivateDirectory $rootPath
    $lockStream = [IO.File]::Open((Join-Path $rootPath 'install.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    if ($installedVersion -and (Read-AgentConfiguration -Path $configPath -Main $true -Visited @{}) -cne $originalText) { throw 'Konfiguracja zmieniła się od przygotowania planu. Uruchom instalator ponownie.' }
    $workPath = Join-Path $rootPath $runId
    Set-PrivateDirectory $workPath
    Write-Status 'Rozpoczęto realizację zatwierdzonego planu.'
    $targetPath = Join-Path $workPath 'target.conf'
    [IO.File]::WriteAllText($targetPath, $targetText, (New-Object Text.UTF8Encoding($false)))
    if ($installedVersion -and ($changed -or $installNeeded)) {
        $backupPath = Join-Path $workPath 'zabbix_agent2.conf.backup'
        Copy-Item -LiteralPath $configPath -Destination $backupPath
        $originalAcl = Get-Acl -LiteralPath $configPath
        Write-Status "Zapisano kopię konfiguracji: $backupPath"
    }
    if ($installNeeded) {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $msiPath = Join-Path $workPath 'agent.msi'
        # Nie akceptujemy przekierowania do innego hosta/protokołu.
        Invoke-WebRequest -UseBasicParsing -Uri $PackageUrl -MaximumRedirection 0 -OutFile $msiPath
        if ((Get-FileHash -LiteralPath $msiPath -Algorithm SHA256).Hash -cne $PackageSha256) { throw 'Suma SHA-256 MSI jest niezgodna.' }
        $signature = Get-AuthenticodeSignature -LiteralPath $msiPath
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -cne $PublisherSubject) { throw 'Nieprawidłowy podpis Authenticode lub wydawca MSI.' }
        $firewallBefore = Get-FirewallSnapshot
        $mutation = $true
        # Docelowe wartości od początku; disabled blokuje start konfiguracji dostawcy.
        $msiArguments = '/i "{0}" /qn /norestart SKIP=fw STARTUPTYPE=disabled SERVER={1} SERVERACTIVE={2} HOSTNAME={3} LISTENIP={4} LISTENPORT={5} INSTALLFOLDER="{6}"' -f $msiPath, $Server, $ServerActive, $hostNameValue, $LocalAddress, $ListenPort, $installPath
        $process = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList $msiArguments -Wait -PassThru -WindowStyle Hidden
        if ($process.ExitCode -notin @(0,3010)) { throw "Instalator MSI zakończył się kodem $($process.ExitCode)." }
        if ((Get-FirewallSnapshot) -cne $firewallBefore) { throw 'Wykryto zmianę lokalnej polityki zapory podczas MSI. Wymagany ręczny przegląd; skrypt nie cofa reguł.' }
        if ($process.ExitCode -eq 3010) { Write-Status 'MSI zgłosił potrzebę restartu systemu. Instalator nie wykonuje restartu automatycznie.' }
        if ((Get-Service -Name $ServiceName).Status -ne 'Stopped') { Stop-Service -Name $ServiceName; throw 'MSI nie pozostawił usługi zatrzymanej. Wymagany ręczny przegląd.' }
    }
    $binaryVersion = Get-AgentBinaryVersion -Binary $binaryPath
    if ($installNeeded -and $binaryVersion -ne [version]$AgentVersion) { throw 'Wersja zainstalowanego pliku agenta nie odpowiada przypiętej wersji pakietu.' }
    Write-Status "Sprawdzono wersję pliku agenta: $binaryVersion"
    $mutation = $true
    if ($changed -or $installNeeded) {
        # Zachowaj bazę względnych Include podczas sprawdzania pliku tymczasowego.
        $stagedPath = Join-Path $installPath ('zabbix_agent2.conf.' + [guid]::NewGuid().ToString('N') + '.tmp')
        [IO.File]::WriteAllText($stagedPath, $targetText, (New-Object Text.UTF8Encoding($false)))
        Set-Acl -LiteralPath $stagedPath -AclObject (Get-Acl -LiteralPath $configPath)
        Invoke-AgentValidation -Binary $binaryPath -Path $stagedPath
        Set-AgentConfigurationFile -Source $stagedPath -Destination $configPath
    } else { Invoke-AgentValidation -Binary $binaryPath -Path $configPath }
    Set-Service -Name $ServiceName -StartupType Automatic
    $service = Get-Service -Name $ServiceName
    if ($service.Status -eq 'Running' -and ($changed -or $installNeeded)) { Restart-Service -Name $ServiceName }
    elseif ($service.Status -ne 'Running') { Start-Service -Name $ServiceName }
    (Get-Service -Name $ServiceName).WaitForStatus('Running', [timespan]::FromSeconds(20))
    $listener = @()
    for ($attempt = 0; $attempt -lt 15; $attempt++) {
        $listener = @(Get-NetTCPConnection -State Listen -LocalPort ([int]$ListenPort) -ErrorAction SilentlyContinue | Where-Object LocalAddress -eq $LocalAddress)
        if ($listener.Count -gt 0) { break }; Start-Sleep -Seconds 1
    }
    $servicePid = (Get-CimInstance Win32_Service -Filter "Name='Zabbix Agent 2'").ProcessId
    if (@($listener | Where-Object OwningProcess -eq $servicePid).Count -eq 0) { throw 'Brak docelowego nasłuchu procesu agenta.' }
    $pingResult = & $binaryPath -c $configPath -t agent.ping 2>&1
    if ($LASTEXITCODE -ne 0 -or ($pingResult -join '') -notmatch '\[(?:s|u)\|1\]') { throw 'Lokalny test agent.ping nie powiódł się.' }
    $mutation = $false
    Write-Status "Sukces. Konfiguracja: $configPath; backup: $backupPath; log: $script:LogFile"
    Write-Status "Hostname=$hostNameValue; Server=$Server; ServerActive=$ServerActive; GUI=$($InterfaceAddress):$ListenPort"
    if ($Mode -eq 'passive') { Write-Status 'Zweryfikuj host po Network Discovery i Discovery Actions: nazwę z agent.hostname, interfejs, proxy i szablony passive.' }
    else { Write-Status 'Dodaj host ręcznie w DMZ: dokładny Hostname, właściwy serwer/proxy i szablony active. Discovery i przychodzący TCP/10050 nie są wymagane.' }
    Write-Status 'Test lokalny nie potwierdza dostępności sieciowej ani danych w Zabbix.'
} catch {
    $exitCode = 1
    # Nie wypisujemy treści błędu obcego procesu ani pełnej konfiguracji.
    Write-Status ('Błąd: ' + $_.Exception.Message)
    if ($script:LogFile) { Write-Status "Log: $script:LogFile; backup: $backupPath" }
    if ($mutation) {
        try {
            if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) { Stop-Service -Name $ServiceName -ErrorAction Stop }
            if ($backupPath) {
                $recoveryPath = Join-Path $installPath ('recovery-' + [guid]::NewGuid().ToString('N') + '.tmp')
                Copy-Item -LiteralPath $backupPath -Destination $recoveryPath
                Set-Acl -LiteralPath $recoveryPath -AclObject $originalAcl
                Set-AgentConfigurationFile -Source $recoveryPath -Destination $configPath
            }
            if ($oldStartMode) {
                $startMode = @{Auto='Automatic'; Manual='Manual'; Disabled='Disabled'}[$oldStartMode]
                Set-Service -Name $ServiceName -StartupType $startMode
                Set-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName" -Name DelayedAutoStart -Value $oldDelayedStart
                if ($wasRunning) { Start-Service -Name $ServiceName }
            } elseif (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) { Set-Service -Name $ServiceName -StartupType Disabled }
            if ($backupPath) { Write-Status 'Odtworzono konfigurację i poprzedni stan usługi. Backup nie cofa aktualizacji programu.' }
            elseif ($oldStartMode) { Write-Status 'Przywrócono poprzedni stan usługi. Nie odtwarzano konfiguracji, ponieważ nie było backupu.' }
            else { Write-Status 'Nowa instalacja pozostaje zatrzymana i wyłączona. Brak poprzedniej konfiguracji do odtworzenia.' }
        } catch { Write-Status 'Odzyskiwanie niepełne. Wymagany ręczny przegląd konfiguracji i usługi.' }
    }
} finally {
    if ($lockStream) { $lockStream.Dispose() }
    if ($stagedPath -and (Test-Path -LiteralPath $stagedPath)) { Remove-Item -LiteralPath $stagedPath -Force }
    if ($workPath) {
        foreach ($name in @('agent.msi', 'target.conf')) {
            $temporaryPath = Join-Path $workPath $name
            if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
        }
    }
}
exit $exitCode
