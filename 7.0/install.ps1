#requires -Version 5.1
<#
Wersja szkieletu: 0.1.0
Docelowy instalator Zabbix Agent 2 7.0.x LTS dla Windows.
Implementacja instalacji i konfiguracji pozostaje do wykonania.
#>

$ErrorActionPreference = 'Stop'

if ($args.Count -eq 1 -and $args[0] -in @('-Help', '--help')) {
    Write-Output 'Szkielet instalatora Zabbix Agent 2 7.0.x LTS dla Windows.'
    Write-Output 'Instalacja nie jest jeszcze zaimplementowana. Wymagania: SPECIFICATION.md.'
    exit 0
}

Write-Error -Message 'Instalacja nie jest jeszcze zaimplementowana. Nie wykonano zmian w systemie.' -ErrorAction Continue
exit 1
