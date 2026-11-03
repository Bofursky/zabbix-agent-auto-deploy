#!/usr/bin/env bash
# Wersja szkieletu: 0.1.0
# Docelowy instalator Zabbix Agent 2 7.0.x LTS dla Linux.
# Implementacja instalacji i konfiguracji pozostaje do wykonania.

set -euo pipefail

if [[ $# -eq 1 && "$1" == '--help' ]]; then
    printf '%s\n' 'Szkielet instalatora Zabbix Agent 2 7.0.x LTS dla Linux.'
    printf '%s\n' 'Instalacja nie jest jeszcze zaimplementowana. Wymagania: SPECIFICATION.md.'
    exit 0
fi

printf '%s\n' 'Instalacja nie jest jeszcze zaimplementowana. Nie wykonano zmian w systemie.' >&2
exit 1
