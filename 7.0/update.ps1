#requires -Version 5.1
$ErrorActionPreference = 'Stop'

function Test-ProxyIPv4 {
    param([string]$Address)

    $parsed = $null
    return $Address -cmatch '\A(?:[0-9]{1,3}\.){3}[0-9]{1,3}\z' -and
        [Net.IPAddress]::TryParse($Address, [ref]$parsed) -and
        $parsed.ToString() -ceq $Address
}

try {
    Write-Host "Wybierz co chcesz zmienić:`n`n1. Adres IP proxy`n"
    if ((Read-Host 'Wybór') -cne '1') { throw 'Nieprawidłowy wybór.' }
    $proxyIp = (Read-Host 'Nowy adres IPv4 proxy').Trim()
    if (-not (Test-ProxyIPv4 $proxyIp)) { throw 'Podaj poprawny adres IPv4.' }

    $programFiles = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
    $config = Get-Item -LiteralPath (Join-Path $programFiles 'Zabbix Agent 2\zabbix_agent2.conf')
    if ($config.PSIsContainer -or ($config.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        $config.LinkType -eq 'HardLink') {
        throw 'Konfiguracja musi być zwykłym plikiem bez dowiązań.'
    }

    $original = [IO.File]::ReadAllBytes($config.FullName)
    $hasBom = $original.Length -ge 3 -and $original[0] -eq 239 -and $original[1] -eq 187 -and $original[2] -eq 191
    $offset = if ($hasBom) { 3 } else { 0 }
    $encoding = [Text.UTF8Encoding]::new($hasBom, $true)
    $contents = $encoding.GetString($original, $offset, $original.Length - $offset)
    $setting = [regex]'(?m)^([ \t]*(Server|ServerActive)[ \t]*=[ \t]*)([^\r\n]*)'
    $entries = $setting.Matches($contents)
    $keys = @($entries | ForEach-Object { $_.Groups[2].Value })
    if ($entries.Count -ne 2 -or 'Server' -cnotin $keys -or 'ServerActive' -cnotin $keys) {
        throw 'W głównym pliku musi występować po jednym aktywnym wpisie Server i ServerActive.'
    }

    $updated = $setting.Replace($contents, {
        param($entry)
        $key = $entry.Groups[2].Value
        $value = [regex]::Match($entry.Groups[3].Value, '\A([0-9]+(?:\.[0-9]+){3})(:([0-9]{1,5}))?([ \t]*)\z')
        if (-not $value.Success -or -not (Test-ProxyIPv4 $value.Groups[1].Value) -or
            ($key -ceq 'Server' -and $value.Groups[2].Success)) {
            throw ('{0}: wymagany pojedynczy adres IPv4. Sprawdź konfigurację ręcznie.' -f $key)
        }
        if ($value.Groups[3].Success -and
            ([int]$value.Groups[3].Value -lt 1 -or [int]$value.Groups[3].Value -gt 65535)) {
            throw 'Nieprawidłowy port ServerActive.'
        }
        return $entry.Groups[1].Value + $proxyIp + $value.Groups[2].Value + $value.Groups[4].Value
    })

    if ($updated -ceq $contents) {
        Write-Host 'Oba wpisy mają już podany adres IPv4.'
    } else {
        $id = [guid]::NewGuid().ToString('N')
        $candidate = $config.FullName + '.tmp-' + $id
        $backup = $config.FullName + '.bak-' + $id
        try {
            [IO.File]::WriteAllText($candidate, $updated, $encoding)
            $current = [IO.File]::ReadAllBytes($config.FullName)
            if (-not [Collections.StructuralComparisons]::StructuralEqualityComparer.Equals($original, $current)) {
                throw 'Konfiguracja zmieniła się podczas odczytu. Uruchom skrypt ponownie.'
            }
            [IO.File]::Replace($candidate, $config.FullName, $backup)
        } finally {
            if ([IO.File]::Exists($candidate)) { [IO.File]::Delete($candidate) }
        }
        Write-Host "Kopia zapasowa: $backup"
        Write-Host 'Zapisano adres proxy w Server i ServerActive.'
    }
    $restart = (Read-Host 'Czy uruchomić ponownie usługę Zabbix Agent 2? [t/N]').Trim()
    if ($restart -in @('t', 'tak')) {
        try {
            Restart-Service -Name 'Zabbix Agent 2'
            Write-Host 'Usługa Zabbix Agent 2 została uruchomiona ponownie.'
        } catch {
            throw "Nie udało się uruchomić ponownie usługi Zabbix Agent 2. Konfiguracja zawiera podany adres. $($_.Exception.Message)"
        }
    }
} catch {
    [Console]::Error.WriteLine("Błąd aktualizacji: $($_.Exception.Message)")
    exit 1
}
