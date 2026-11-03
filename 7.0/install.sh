#!/usr/bin/env bash
# Wersja instalatora: 0.2.0. Zabbix Agent 2, przypięta linia 7.0 LTS.
set -Eeuo pipefail
umask 077

# Oficjalne źródła HTTPS; sumy odczytane z artefaktów 2026-11-03.
readonly AGENT_VERSION='7.0.32'
readonly KEY_URL='https://repo.zabbix.com/RPM-GPG-KEY-ZABBIX-B5333005'
readonly SIGNING_FINGERPRINT='4C3D6F2CC75F5146754FC374D913219AB5333005'
readonly SIGNING_SHA256='501e584b5c868c3230538197ada3e1204cd7c91e899cc8af2db5ef6445399fc1'
readonly CONFIG='/etc/zabbix/zabbix_agent2.conf'
readonly UNIT='zabbix-agent2.service'
mode=passive server='' server_active='' prefix='' local_address='' interface_address='' listen_port=10050
prefix_set=0 active_set=0 mode_set=0 server_set=0 local_set=0 interface_set=0 upgrade=0 non_interactive=0 yes=0 dry_run=0
work='' log_file='' backup='' changed=0 masked=0 mutation=0 was_active=0 was_enabled=0 installed=''
config_mode=640 config_owner=root:zabbix

fail() { printf 'Błąd: %s\n' "$*" >&2; exit 1; }
help_text() {
    cat <<'HELP'
Instalator Zabbix Agent 2 7.0 LTS, wersja 0.2.0.
Obsługiwane platformy: Debian 12/13 amd64, Rocky Linux 9 x86_64; systemd.
Uruchom jako root. Bez parametrów uruchamia kreator.
  --server IPv4                 Serwer lub wybrany proxy (wymagany)
  --server-active IPv4[:port]   Domyślnie aktualny --server:10051
  --hostname-prefix TEKST      Jawny prefiks, także pusty: --hostname-prefix ''
  --local-address IPv4         Lokalny adres nasłuchu
  --interface-address IPv4     Propozycja adresu do GUI, także NAT
  --listen-port PORT           1024–32767, domyślnie 10050
  --mode passive|active        Domyślnie passive
  --upgrade                    Aktualizacja do wersji przypiętej; bez downgrade
  --non-interactive            Bez pytań, wymagane --yes lub --dry-run
  --yes                        Pomiń potwierdzenie
  --dry-run                    Plan bez pobierania, zapisu i zmian usług
  --help                       Pomoc bez uprawnień root
Skrypt nie zmienia zapory, SELinux ani konfiguracji serwera Zabbix.
HELP
}
ipv4() {
    local value=$1 part
    local -a parts
    [[ $value =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS=. read -r -a parts <<< "$value"
    for part in "${parts[@]}"; do
        [[ $part == 0 || $part != 0* ]] && ((10#$part <= 255)) || return 1
    done
    [[ ${parts[0]} != 0 && ${parts[0]} != 127 ]] && ((10#${parts[0]} < 224)) && [[ ${parts[0]}.${parts[1]} != 169.254 ]]
}
port() { [[ $1 =~ ^[0-9]{1,5}$ ]] && ((10#$1 >= $2 && 10#$1 <= $3)); }
note() { printf '%s\n' "$*"; [[ -z $log_file ]] || printf '%s %s\n' "$(date -Is)" "$*" >> "$log_file"; }
fetch() { curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 "$1" -o "$2"; }
checksum() { printf '%s  %s\n' "$1" "$2" | sha256sum --check --status || fail 'Suma SHA-256 pakietu jest niezgodna.'; }
cleanup() {
    local result=$?
    trap - EXIT
    set +e
    if ((result != 0 && mutation)); then
        note 'Operacja nie powiodła się. Próba odzyskania konfiguracji i stanu usługi.'
        systemctl stop "$UNIT" >> "$log_file" 2>&1
        local recovered=1
        if [[ -n $backup ]]; then
            cp -- "$backup" "${CONFIG}.recover" && chmod "$config_mode" "${CONFIG}.recover" && chown "$config_owner" "${CONFIG}.recover" && mv -f -- "${CONFIG}.recover" "$CONFIG" || recovered=0
        elif [[ -z $installed ]]; then note 'Nowy pakiet pozostaje zainstalowany; usługa pozostaje zatrzymana.'; fi
        if ((masked)); then systemctl unmask --runtime "$UNIT" >> "$log_file" 2>&1 || recovered=0; masked=0; fi
        if ((was_enabled)); then systemctl enable "$UNIT" >> "$log_file" 2>&1 || recovered=0
        else systemctl disable "$UNIT" >> "$log_file" 2>&1 || recovered=0; fi
        if ((was_active)); then systemctl start "$UNIT" >> "$log_file" 2>&1 || recovered=0; fi
        if ((recovered)); then note 'Odtworzono pliki i poprzedni stan usługi. Backup nie cofa aktualizacji programu.'
        else note 'Odzyskiwanie niepełne. Wymagany ręczny przegląd konfiguracji i usługi.'; fi
    fi
    if ((masked)); then systemctl unmask --runtime "$UNIT" >> "$log_file" 2>&1; fi
    if ((result != 0)); then note "Błąd instalacji. Log: ${log_file:-nieutworzony}; backup: ${backup:-brak}."; fi
    [[ -z $work ]] || rm -rf -- "$work"
    exit "$result"
}

while (($#)); do
    case $1 in
        --help) help_text; exit 0 ;;
        --upgrade) upgrade=1; shift ;;
        --non-interactive) non_interactive=1; shift ;;
        --yes) yes=1; shift ;;
        --dry-run) dry_run=1; shift ;;
        --mode|--server|--server-active|--hostname-prefix|--local-address|--interface-address|--listen-port)
            (($# >= 2)) || fail "Brak wartości parametru $1."
            [[ $2 != --* ]] || fail "Brak wartości parametru $1."
            case $1 in
                --mode) mode=$2; mode_set=1 ;;
                --server) server=$2; server_set=1 ;;
                --server-active) server_active=$2; active_set=1 ;;
                --hostname-prefix) prefix=$2; prefix_set=1 ;;
                --local-address) local_address=$2; local_set=1 ;;
                --interface-address) interface_address=$2; interface_set=1 ;;
                --listen-port) listen_port=$2 ;;
            esac
            shift 2 ;;
        *) fail "Nieznany parametr: $1." ;;
    esac
done
((EUID == 0)) || fail 'Uruchom skrypt jako root.'
for command_name in ip python3 systemctl uname hostname grep awk sort pgrep; do
    command -v "$command_name" >/dev/null || fail "Brak wymaganego polecenia: $command_name."
done
[[ -d /run/systemd/system ]] || fail 'Wymagany działający systemd.'
# Plik systemowy odczytujemy jako dane, bez wykonywania jego zawartości.
os_id=$(awk -F= '$1=="ID" {gsub(/"/,"",$2); print $2}' /etc/os-release)
os_version=$(awk -F= '$1=="VERSION_ID" {gsub(/"/,"",$2); print $2}' /etc/os-release)
[[ $(uname -m) == x86_64 ]] || fail 'Obsługiwana architektura: x86_64/amd64.'
case "$os_id:$os_version" in
    debian:12|debian:13)
        family=deb
        bootstrap_url="https://repo.zabbix.com/zabbix/7.0/debian/pool/main/z/zabbix-release/zabbix-release_7.0-5%2Bdebian${os_version}_all.deb"
        if [[ $os_version == 12 ]]; then bootstrap_hash=950bd75b2a0f813208f8d01fc114ff2907296425664b0366927b6269024212ed; codename=bookworm
        else bootstrap_hash=4a926b8815cdefddc31558fe622676730a3987610f75d5af0d4024809d21dd43; codename=trixie; fi
        package_version="${AGENT_VERSION}-2+debian${os_version}"
        package_url="https://repo.zabbix.com/zabbix/7.0/debian/pool/main/z/zabbix/zabbix-agent2_${package_version/+/%2B}_amd64.deb"
        if dpkg-query -W -f='${db:Status-Status}' zabbix-agent2 2>/dev/null | grep -qx installed; then installed=$(dpkg-query -W -f='${Version}' zabbix-agent2); fi
        if dpkg-query -W -f='${db:Status-Status}' zabbix-agent 2>/dev/null | grep -qx installed; then fail 'Wykryto klasycznego agenta. Wymagany ręczny przegląd.'; fi ;;
    rocky:9|rocky:9.*)
        family=rpm
        bootstrap_url='https://repo.zabbix.com/zabbix/7.0/rocky/9/x86_64/zabbix-release-7.0-5.el9.noarch.rpm'
        bootstrap_hash=f4d3cd3b1a197f161c94e49f351389d84735dab4ee5e970d6f41244868fcf2fb
        package_version="${AGENT_VERSION}-release2.el9"
        package_url="https://repo.zabbix.com/zabbix/7.0/rocky/9/x86_64/zabbix-agent2-${package_version}.x86_64.rpm"
        if rpm -q zabbix-agent2 >/dev/null 2>&1; then installed=$(rpm -q --qf '%{VERSION}-%{RELEASE}' zabbix-agent2); fi
        if rpm -q zabbix-agent >/dev/null 2>&1; then fail 'Wykryto klasycznego agenta. Wymagany ręczny przegląd.'; fi ;;
    *) fail 'Nieobsługiwany system. Przypięte pakiety: Debian 12/13 i Rocky Linux 9, x86_64.' ;;
esac
mapfile -t addresses < <(ip -o -4 address show up scope global | awk '{split($4,a,"/"); print a[1]" "$2}' | sort -u)
local_addresses=()
for entry in "${addresses[@]}"; do
    address=${entry%% *}
    if ipv4 "$address"; then local_addresses+=("$address"); printf 'Lokalny IPv4: %s (%s)\n' "$address" "${entry#* }"; fi
done
((${#local_addresses[@]})) || fail 'Nie wykryto lokalnego IPv4 na aktywnych interfejsach.'
if ((!non_interactive)); then
    [[ -t 0 ]] || fail 'Brak terminala kreatora. Użyj --non-interactive.'
    if ((!server_set)); then read -r -p 'IPv4 serwera lub właściwego proxy: ' server; fi
    if ((!active_set)); then read -r -p "ServerActive [${server}:10051]: " server_active; fi
    if ((!prefix_set)); then read -r -p 'Prefiks nazwy hosta (może być pusty): ' prefix; prefix_set=1; fi
    if ((!mode_set)); then read -r -p 'Tryb [passive/active, domyślnie passive]: ' mode; mode=${mode:-passive}; fi
    if ((!local_set)); then
        suggestion=''; ((${#local_addresses[@]} != 1)) || suggestion=${local_addresses[0]}
        read -r -p "Lokalny IPv4 [$suggestion]: " local_address; local_address=${local_address:-$suggestion}
    fi
    if ((!interface_set)); then read -r -p "Propozycja IPv4 do GUI [$local_address]: " interface_address; fi
fi
ipv4 "$server" || fail 'Server musi być pojedynczym poprawnym IPv4.'
((prefix_set)) || fail 'Podaj --hostname-prefix, także świadomie pusty.'
[[ $mode == passive || $mode == active ]] || fail 'Mode musi mieć wartość passive albo active.'
if ((!active_set)) && [[ -z $server_active ]]; then server_active="${server}:10051"; fi
active_ip=${server_active%%:*}; active_port=10051
[[ $server_active != *:* ]] || active_port=${server_active#*:}
if ! ipv4 "$active_ip" || ! port "$active_port" 1 65535; then fail 'Nieprawidłowy ServerActive.'; fi
server_active="${active_ip}:$((10#$active_port))"
port "$listen_port" 1024 32767 || fail 'ListenPort musi należeć do zakresu 1024–32767.'
listen_port=$((10#$listen_port))
if ((!local_set)) && [[ -z $local_address && ${#local_addresses[@]} == 1 ]]; then local_address=${local_addresses[0]}; fi
ipv4 "$local_address" || fail 'Wskaż lokalny IPv4 przez --local-address.'
found=0; for address in "${local_addresses[@]}"; do [[ $address != "$local_address" ]] || found=1; done
((found)) || fail 'LocalAddress nie jest adresem aktywnego lokalnego interfejsu.'
if ((!interface_set)) && [[ -z $interface_address ]]; then interface_address=$local_address; fi
ipv4 "$interface_address" || fail 'InterfaceAddress musi być poprawnym IPv4.'
host_name="${prefix}$(hostname)"
[[ $host_name =~ ^[A-Za-z0-9._-]{1,128}$ ]] || fail 'Wynikowy Hostname jest nieprawidłowy lub przekracza 128 znaków.'
((!non_interactive || yes || dry_run)) || fail '--non-interactive wymaga --yes lub --dry-run.'
if [[ -n $installed ]]; then
    [[ $installed =~ ^(1:)?7\.0\.[0-9]+- ]] || fail 'Istniejąca wersja jest spoza 7.0.x. Wymagany ręczny przegląd.'
    current_version=${installed#1:}
    if ((upgrade)) && [[ $(printf '%s\n%s\n' "$current_version" "$package_version" | sort -V | tail -1) != "$package_version" ]]; then fail 'Downgrade jest zabroniony.'; fi
    [[ -f $CONFIG ]] || fail 'Istniejący pakiet nie ma standardowej konfiguracji. Wymagany ręczny przegląd.'
elif [[ -e $CONFIG ]]; then fail 'Konfiguracja bez rozpoznanego pakietu. Wymagany ręczny przegląd.'; fi
[[ ! -L $CONFIG ]] || fail 'Konfiguracja jest dowiązaniem. Wymagany ręczny przegląd.'
unit_state=$(systemctl is-enabled "$UNIT" 2>/dev/null || true)
[[ $unit_state != masked* ]] || fail 'Usługa jest zamaskowana. Wymagany ręczny przegląd.'
[[ $unit_state != enabled ]] || was_enabled=1
if systemctl is-active --quiet "$UNIT"; then was_active=1; fi
units=$(systemctl list-unit-files --no-legend 'zabbix*' | awk '{print $1}' | grep -Ev '^(zabbix-agent2.service|zabbix-agent2-plugin.*)$' || true)
[[ -z $units ]] || fail 'Wykryto inne jednostki Zabbix. Wymagany ręczny przegląd.'
if [[ -n $installed ]]; then
    unit_command=$(systemctl show "$UNIT" -p ExecStart --value)
    [[ $unit_command == *'/usr/sbin/zabbix_agent2'* ]] || fail 'Niestandardowa jednostka agenta. Wymagany ręczny przegląd.'
    [[ -z $(systemctl show "$UNIT" -p DropInPaths --value) ]] || fail 'Niestandardowe rozszerzenia jednostki. Wymagany ręczny przegląd.'
    if [[ $unit_command == *"\$CONFFILE"* ]]; then
        unit_environment=$(systemctl show "$UNIT" -p Environment --value)
        [[ $unit_environment == *"CONFFILE=$CONFIG"* ]] || fail 'Niestandardowy CONFFILE. Wymagany ręczny przegląd.'
        for environment_file in /etc/default/zabbix-agent2 /etc/sysconfig/zabbix-agent2; do
            if [[ -f $environment_file ]]; then
                override=$(awk -F= '/^[[:space:]]*CONFFILE[[:space:]]*=/ {gsub(/["\047[:space:]]/,"",$2); print $2}' "$environment_file")
                [[ -z $override || $override == "$CONFIG" ]] || fail 'Niestandardowy CONFFILE w pliku środowiska. Wymagany ręczny przegląd.'
            fi
        done
    elif [[ $unit_command != *"$CONFIG"* ]]; then fail 'Niestandardowa konfiguracja jednostki. Wymagany ręczny przegląd.'; fi
fi
mapfile -t agent_pids < <(pgrep -x zabbix_agent2 || true)
if pgrep -x zabbix_agentd >/dev/null; then fail 'Wykryto klasycznego agenta poza pakietem. Wymagany ręczny przegląd.'; fi
((${#agent_pids[@]} <= 1)) || fail 'Wykryto wiele procesów agenta.'
if ((${#agent_pids[@]} == 1)); then
    [[ ${agent_pids[0]} == "$(systemctl show "$UNIT" -p MainPID --value)" ]] || fail 'Wykryto agenta poza standardową usługą.'
fi

# Rekursywne Include sprawdzamy bez ujawniania obcych ustawień w komunikatach.
render_config() {
    python3 - "$CONFIG" "$1" "$server" "$server_active" "$host_name" "$local_address" "$listen_port" <<'PY'
import glob, os, re, sys
path, output, server, active, hostname, address, port = sys.argv[1:]
managed = dict(Server=server, ServerActive=active, Hostname=hostname, ListenIP=address, ListenPort=port)
visited = set()
def inspect(filename, main=False):
    real = os.path.realpath(filename)
    if real in visited or os.path.islink(filename) or not os.path.isfile(filename):
        raise ValueError('Konflikt Include lub niestandardowy plik.')
    visited.add(real)
    text = open(filename, encoding='utf-8-sig').read()
    for line in text.splitlines():
        match = re.match(r'^\s*([^#;\s=]+)\s*=\s*(.*?)\s*$', line)
        if not match:
            continue
        key, value = match.groups()
        if key.startswith('TLS') or key in ('HostMetadata','HostMetadataItem','HostInterface','HostInterfaceItem'):
            raise ValueError('TLS lub autorejestracja wymaga przeglądu.')
        if not main and key in managed:
            raise ValueError('Konflikt zarządzanych ustawień w Include.')
        if key == 'Include':
            if not os.path.isabs(value):
                raise ValueError('Względny Include wymaga przeglądu.')
            children = sorted(glob.glob(value))
            if not children and not glob.has_magic(value):
                raise ValueError('Brak pliku Include.')
            for child in children:
                inspect(child)
    return text
try:
    text = inspect(path, True) if os.path.exists(path) else 'LogType=system\nPidFile=/run/zabbix/zabbix_agent2.pid\nControlSocket=/run/zabbix/agent.sock\n'
    lines, seen = [], set()
    for line in text.splitlines():
        match = re.match(r'^\s*([^#;\s=]+)\s*=', line)
        key = match.group(1) if match else None
        if key in managed:
            if key not in seen:
                lines.append(key + '=' + managed[key]); seen.add(key)
        else:
            lines.append(line)
    lines.extend(key + '=' + value for key, value in managed.items() if key not in seen)
    result = '\n'.join(lines) + '\n'
    if output != '-':
        with open(output, 'w', encoding='utf-8', newline='\n') as handle:
            handle.write(result)
except (ValueError, OSError, UnicodeError):
    sys.exit('Błąd: konflikt lub nieczytelna konfiguracja/include; TLS i autorejestracja wymagają ręcznego przeglądu.')
PY
}
render_config -
install_needed=0
if [[ -z $installed ]] || { ((upgrade)) && [[ ${installed#1:} != "$package_version" ]]; }; then install_needed=1; fi
printf 'Plan: pakiet %s, obecnie %s, instalacja/aktualizacja=%s\nServer=%s\nServerActive=%s\nHostname=%s\nListenIP=%s:%s\nGUI=%s:%s\nMode=%s\n' \
    "$package_version" "${installed:-brak}" "$install_needed" "$server" "$server_active" "$host_name" "$local_address" "$listen_port" "$interface_address" "$listen_port" "$mode"
printf 'Źródło przypiętego pakietu: %s\n' "$package_url"
if ((dry_run)); then printf 'DryRun: nie wykonano zmian ani pobierania. Dostępność pakietu zostanie sprawdzona przed instalacją.\n'; exit 0; fi
if ((!yes)); then read -r -p 'Wykonać plan? Wpisz TAK: ' answer; [[ $answer == TAK ]] || fail 'Anulowano.'; fi
for command_name in curl sha256sum gpg flock ss cmp mktemp; do command -v "$command_name" >/dev/null || fail "Brak wymaganego polecenia: $command_name."; done
exec 9>/run/lock/zabbix-agent-auto-deploy.lock
flock -n 9 || fail 'Inny instalator już działa.'
work=$(mktemp -d /var/tmp/zabbix-auto-deploy.XXXXXXXX)
trap cleanup EXIT
log_dir=/var/log/zabbix-auto-deploy
[[ ! -L $log_dir ]] || fail 'Katalog logów jest dowiązaniem.'
install -d -m 700 "$log_dir"
log_file=$(mktemp "$log_dir/install-$(date +%Y%m%d-%H%M%S)-XXXXXXXX.log")
note 'Rozpoczęto realizację zatwierdzonego planu.'
render_config "$work/target.conf"
if [[ ! -f $CONFIG ]] || ! cmp -s "$CONFIG" "$work/target.conf"; then changed=1; fi
if [[ -f $CONFIG ]] && ((changed || install_needed)); then
    config_mode=$(stat -c %a "$CONFIG"); config_owner=$(stat -c %u:%g "$CONFIG")
    backup_dir=/var/backups/zabbix-auto-deploy
    [[ ! -L $backup_dir ]] || fail 'Katalog backupu jest dowiązaniem.'
    install -d -m 700 "$backup_dir"
    backup=$(mktemp "$backup_dir/zabbix_agent2-$(date +%Y%m%d-%H%M%S)-XXXXXXXX.conf")
    cp -- "$CONFIG" "$backup"; chmod 600 "$backup"
    note "Zapisano kopię konfiguracji: $backup"
fi
if ((install_needed)); then
    fetch "$bootstrap_url" "$work/bootstrap"; checksum "$bootstrap_hash" "$work/bootstrap"
    fetch "$KEY_URL" "$work/key"; checksum "$SIGNING_SHA256" "$work/key"
    fingerprint=$(gpg --batch --homedir "$work" --show-keys --with-colons "$work/key" 2>/dev/null | awk -F: '$1=="fpr" {print $10; exit}')
    [[ $fingerprint == "$SIGNING_FINGERPRINT" ]] || fail 'Nieprawidłowy fingerprint klucza repozytorium.'
    curl --fail --silent --show-error --head --proto '=https' "$package_url" >/dev/null || fail 'Przypięty pakiet jest niedostępny.'
    mutation=1
    systemctl mask --runtime "$UNIT" >> "$log_file" 2>&1; masked=1
    if [[ $family == deb ]]; then
        command -v apt-get >/dev/null || fail 'Brak apt-get.'
        # Osobne źródło i magazyn list; nie zmieniamy konfiguracji apt hosta.
        gpg --batch --yes --homedir "$work" --dearmor -o "$work/key.gpg" "$work/key"
        mkdir -p "$work/lists/partial"
        # _apt odczytuje jedynie klucz i źródło; konfiguracja pozostaje 0600.
        chmod 711 "$work"; chmod 644 "$work/key.gpg"
        printf 'deb [arch=amd64 signed-by=%s/key.gpg] https://repo.zabbix.com/zabbix/7.0/debian %s main\n' "$work" "$codename" > "$work/source.list"
        chmod 644 "$work/source.list"
        apt_options=(-o "Dir::Etc::sourcelist=$work/source.list" -o 'Dir::Etc::sourceparts=-' -o "Dir::State::lists=$work/lists" -o 'APT::Get::AllowUnauthenticated=false' -o 'Acquire::AllowInsecureRepositories=false' -o 'Acquire::https::Verify-Peer=true')
        apt-get "${apt_options[@]}" update >> "$log_file" 2>&1
        (cd "$work"; apt-get "${apt_options[@]}" download "zabbix-agent2=1:$package_version") >> "$log_file" 2>&1
        shopt -s nullglob; packages=("$work"/zabbix-agent2_*.deb); shopt -u nullglob
        ((${#packages[@]} == 1)) || fail 'Nie znaleziono jednego zweryfikowanego pakietu.'
        DEBIAN_FRONTEND=noninteractive apt-get -y -o 'APT::Get::AllowUnauthenticated=false' -o 'Acquire::AllowInsecureRepositories=false' -o 'Acquire::https::Verify-Peer=true' -o 'Dpkg::Options::=--force-confold' install "${packages[0]}" >> "$log_file" 2>&1
    else
        fetch "$package_url" "$work/agent.rpm"
        mkdir "$work/rpmdb"
        rpm --dbpath "$work/rpmdb" --initdb
        rpm --dbpath "$work/rpmdb" --import "$work/key"
        rpm --dbpath "$work/rpmdb" --checksig "$work/agent.rpm" >> "$log_file" 2>&1 || fail 'Podpis RPM nie odpowiada przypiętemu kluczowi.'
        rpm --import "$work/key" >> "$log_file" 2>&1
        dnf -y --disablerepo='*zabbix*' --setopt=sslverify=1 --setopt=gpgcheck=1 --setopt=localpkg_gpgcheck=1 \
            install "$work/agent.rpm" >> "$log_file" 2>&1
    fi
    note 'Zainstalowano przypięty pakiet z weryfikacją podpisów repozytorium.'
fi
mutation=1
binary=/usr/sbin/zabbix_agent2
[[ -x $binary ]] || fail 'Brak pliku wykonywalnego agenta.'
binary_version=$($binary -V | head -1)
[[ $binary_version == *' 7.0.'* ]] || fail 'Nieoczekiwana wersja pliku agenta.'
"$binary" -c "$work/target.conf" -T >/dev/null 2>&1 || fail 'Walidacja konfiguracji nie powiodła się; szczegóły wymagają ręcznego przeglądu.'
if ((changed || install_needed)); then
    [[ -f $CONFIG ]] && config_mode=$(stat -c %a "$CONFIG") || config_mode=640
    [[ -f $CONFIG ]] && config_owner=$(stat -c %u:%g "$CONFIG") || config_owner=root:zabbix
    install -m "$config_mode" "$work/target.conf" "${CONFIG}.auto-deploy"
    chown "$config_owner" "${CONFIG}.auto-deploy"
    mv -f -- "${CONFIG}.auto-deploy" "$CONFIG"
fi
if ((masked)); then systemctl unmask --runtime "$UNIT" >> "$log_file" 2>&1; masked=0; fi
systemctl daemon-reload
systemctl enable "$UNIT" >> "$log_file" 2>&1
if ((changed || install_needed)) && systemctl is-active --quiet "$UNIT"; then systemctl restart "$UNIT" >> "$log_file" 2>&1
elif ! systemctl is-active --quiet "$UNIT"; then systemctl start "$UNIT" >> "$log_file" 2>&1; fi
for ((attempt=0; attempt<15; attempt++)); do
    if systemctl is-active --quiet "$UNIT" && ss -H -ltn "sport = :$listen_port" | awk '{print $4}' | grep -Fxq "$local_address:$listen_port"; then break; fi
    sleep 1
done
systemctl is-active --quiet "$UNIT" || fail 'Usługa nie działa.'
ss -H -ltn "sport = :$listen_port" | awk '{print $4}' | grep -Fxq "$local_address:$listen_port" || fail 'Brak docelowego nasłuchu.'
ping_result=$("$binary" -c "$CONFIG" -t agent.ping 2>> "$log_file")
[[ $ping_result == *'[s|1]'* || $ping_result == *'[u|1]'* ]] || fail 'Lokalny test agent.ping nie powiódł się.'
mutation=0
note "Sukces. $binary_version; konfiguracja: $CONFIG; backup: ${backup:-niepotrzebny}; log: $log_file"
note "Hostname=$host_name; Server=$server; ServerActive=$server_active; GUI=$interface_address:$listen_port"
if [[ $mode == passive ]]; then note 'Zweryfikuj host po Network Discovery i Discovery Actions: nazwę z agent.hostname, interfejs, proxy i szablony passive.'
else note 'Dodaj host ręcznie w DMZ: dokładny Hostname, właściwy serwer/proxy i szablony active. Discovery i przychodzący TCP/10050 nie są wymagane.'; fi
note 'Test lokalny nie potwierdza dostępności sieciowej ani danych w Zabbix. Zapora i SELinux nie były zmieniane.'
