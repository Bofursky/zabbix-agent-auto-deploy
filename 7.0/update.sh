#!/usr/bin/env bash
set -euo pipefail

printf 'Wybierz co chcesz zmienić:\n\n1. Adres IP proxy\n\n'
read -r -p 'Wybór: ' choice
if [[ $choice != 1 ]]; then
    printf 'Nieprawidłowy wybór.\n' >&2
    exit 1
fi
read -r -p 'Nowy adres IPv4 proxy: ' proxy_ip

python3 - "$proxy_ip" /etc/zabbix/zabbix_agent2.conf <<'PY'
import ipaddress
import os
import re
import shutil
import stat
import sys
import tempfile
from pathlib import Path

proxy_ip, config_path = sys.argv[1:]
config = Path(config_path)
setting = re.compile(rb'(?m)^([ \t]*(Server|ServerActive)[ \t]*=[ \t]*)([^\r\n]*)')
endpoint = re.compile(rb'([0-9]+(?:\.[0-9]+){3})(:[0-9]{1,5})?([ \t]*)')

try:
    new_ip = str(ipaddress.IPv4Address(proxy_ip.strip())).encode('ascii')
    original_stat = config.lstat()
    if not stat.S_ISREG(original_stat.st_mode) or original_stat.st_nlink != 1:
        raise ValueError('Konfiguracja musi być zwykłym plikiem bez dowiązań.')
    original = config.read_bytes()
    bom = b'\xef\xbb\xbf' if original.startswith(b'\xef\xbb\xbf') else b''
    contents = original[len(bom):]
    matches = list(setting.finditer(contents))
    if sorted(match[2] for match in matches) != [b'Server', b'ServerActive']:
        raise ValueError('W głównym pliku musi występować po jednym aktywnym wpisie Server i ServerActive.')

    def replace_address(match):
        value = endpoint.fullmatch(match[3])
        if value is None or (match[2] == b'Server' and value[2]):
            raise ValueError(f'{match[2].decode()}: wymagany pojedynczy adres IPv4. Sprawdź konfigurację ręcznie.')
        ipaddress.IPv4Address(value[1].decode('ascii'))
        if value[2] and not 1 <= int(value[2][1:]) <= 65535:
            raise ValueError('Nieprawidłowy port ServerActive.')
        return match[1] + new_ip + (value[2] or b'') + value[3]

    updated = bom + setting.sub(replace_address, contents)
    if updated == original:
        print('Oba wpisy mają już podany adres IPv4.')
        sys.exit(0)

    with tempfile.TemporaryDirectory(prefix='.zabbix-update-', dir=config.parent) as directory:
        work = Path(directory)
        candidate = work / 'config'
        candidate.write_bytes(updated)
        os.chown(candidate, original_stat.st_uid, original_stat.st_gid)
        shutil.copystat(config, candidate)
        current_stat = config.lstat()
        if (current_stat.st_dev, current_stat.st_ino, current_stat.st_ctime_ns) != (
            original_stat.st_dev, original_stat.st_ino, original_stat.st_ctime_ns
        ):
            raise ValueError('Konfiguracja zmieniła się podczas odczytu. Uruchom skrypt ponownie.')
        backup_fd, backup = tempfile.mkstemp(prefix=config.name + '.bak-', dir=config.parent)
        with os.fdopen(backup_fd, 'wb') as stream:
            stream.write(original)
        print(f'Kopia zapasowa: {backup}')
        os.replace(candidate, config)

    print('Zapisano adres proxy w Server i ServerActive.')
except (OSError, ValueError) as error:
    sys.exit(f'Błąd aktualizacji: {error}')
PY

if read -r -p 'Czy uruchomić ponownie usługę Zabbix Agent 2? [t/N] ' restart; then
    case ${restart,,} in
        t|tak)
            if ! systemctl restart zabbix-agent2.service; then
                printf 'Nie udało się uruchomić ponownie usługi Zabbix Agent 2. Konfiguracja zawiera podany adres.\n' >&2
                exit 1
            fi
            printf 'Usługa Zabbix Agent 2 została uruchomiona ponownie.\n'
            ;;
    esac
fi
