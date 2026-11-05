# zabbix-agent-auto-deploy

Projekt dwóch samodzielnych instalatorów **Zabbix Agent 2 7.0.x LTS** dla Windows i Linux. Źródłem wymagań jest [SPECIFICATION.md](SPECIFICATION.md), wersja 1.6.1; zasady pracy opisuje [AGENTS.md](AGENTS.md).

## Stan projektu

Instalator Windows w wersji **0.2.2** i instalator Linux w wersji **0.2.0** implementują instalację, konfigurację i jawną aktualizację Zabbix Agent 2 **7.0.32**. Obsługują kreator, CLI i `DryRun`. Użytkownik potwierdził pomyślną instalację Windows 0.2.2. Nie podano dokładnej wersji Windows; pełna macierz testów i gotowość produkcyjna nie zostały jeszcze potwierdzone.

## Struktura docelowa

```text
zabbix-agent-auto-deploy/
├── 7.0/
│   ├── install.ps1
│   └── install.sh
├── AGENTS.md
├── README.md
├── SPECIFICATION.md
├── CHANGELOG.md
├── LICENSE
├── .gitattributes
└── .gitignore
```

Katalog `7.0/` dotyczy linii 7.0.x LTS. Instalatory mają działać po skopiowaniu pojedynczego skryptu na host. Nie dodajemy modułów, dodatkowego katalogu dokumentacji, frameworków testowych ani GitHub Actions. Zachowany `.gitkeep` jest wyłącznie wcześniejszym znacznikiem katalogu.

## Pomoc

Windows PowerShell 5.1, bez uprawnień administratora:

```powershell
.\7.0\install.ps1 -Help
```

Linux Bash:

```bash
bash 7.0/install.sh --help
```

## Wymagania i użycie

Windows: 64-bitowy Windows PowerShell 5.1, architektura x64 i kompilacja systemu co najmniej 17763 (Windows 10/11, Server 2019/2022/2025). Linux: **Debian 12/13 amd64 lub Rocky Linux 9 x86_64**, Bash 4+, działający systemd, Python 3, iproute2 (`ip`, `ss`), procps (`pgrep`), curl, GnuPG, coreutils i util-linux (`flock`). Debian wymaga apt/dpkg; Rocky wymaga dnf/rpm. Pakiety zależności systemowych muszą być dostępne w poprawnie skonfigurowanych repozytoriach dystrybucji.

Instalacja oraz plan wymagają administratora/root; pomoc działa bez podwyższonych uprawnień. Inne wersje Linuksa i architektury są odrzucane. Ubuntu, RHEL i AlmaLinux pozostają docelowym zakresem specyfikacji i nie są zaimplementowane w tej zmianie dla Debiana i Rocky. Lista systemów zweryfikowanych pełną instalacją: **brak**.

Po skopiowaniu pojedynczego skryptu na host uruchom kreator:

```powershell
.\7.0\install.ps1
```

```bash
sudo bash 7.0/install.sh
```

Administrator podaje IPv4 serwera lub wybranego proxy i prefiks nazwy hosta; lokalny IPv4 jest wykrywany z możliwością korekty. Przy wielu adresach wymagany jest świadomy wybór. Najpierw sprawdź plan:

```powershell
.\7.0\install.ps1 -Server '192.0.2.20' -HostnamePrefix 'LAB-' -LocalAddress '192.0.2.10' -NonInteractive -DryRun
```

```bash
sudo bash 7.0/install.sh --server '192.0.2.20' --hostname-prefix 'LAB-' --local-address '192.0.2.10' --non-interactive --dry-run
```

Adresy są dokumentacyjne; należy zastąpić je danymi zatwierdzonego laboratorium. `LocalAddress` musi należeć do hosta. `DryRun` pokazuje plan bez pobierania pakietów, zapisów i zmian usług; dostępność zdalnego pakietu jest sprawdzana dopiero przed instalacją. Aby wykonać plan, zastąp `-DryRun` przez `-Yes`, a w Bash `--dry-run` przez `--yes`.

Przykład active w DMZ, z innym endpointem i propozycją adresu NAT do GUI:

```powershell
.\7.0\install.ps1 -Server '192.0.2.20' -ServerActive '192.0.2.30:10051' -Mode active -HostnamePrefix 'DMZ-' -LocalAddress '192.0.2.10' -InterfaceAddress '198.51.100.10' -NonInteractive -DryRun
```

```bash
sudo bash 7.0/install.sh --server '192.0.2.20' --server-active '192.0.2.30:10051' --mode active --hostname-prefix 'DMZ-' --local-address '192.0.2.10' --interface-address '198.51.100.10' --non-interactive --dry-run
```

`-Upgrade` / `--upgrade` zezwala na aktualizację do przypiętej wersji. Istniejący agent 7.0.x bez tej flagi zachowuje swoją wersję; downgrade jest odrzucany. `-ListenPort` / `--listen-port` przyjmuje 1024–32767, domyślnie 10050. `ServerActive` dopuszcza port 1–65535. Pusty prefiks podaj jawnie: `-HostnamePrefix ''` lub `--hostname-prefix ''`. Nieznane parametry, jawnie pusty `ServerActive` oraz niepoprawne adresy i porty kończą działanie błędem.

`Mode` domyślnie wynosi `passive`; dla DMZ można wskazać `active`. Oba tryby zapisują `Server` i `ServerActive`. Pominięty `ServerActive` otrzymuje aktualny IPv4 z `Server` i port 10051; jawny endpoint ma pierwszeństwo. Sama obecność `ServerActive` nie zapewnia aktywnych pomiarów — wymagają one odpowiednich pozycji i szablonów w Zabbix. Administrator ręcznie wybiera IP proxy; instalator nie wykrywa proxy ani nie zmienia przypisania hosta w Zabbix.

Instalator zachowuje obce ustawienia, usuwa duplikaty zarządzanych kluczy i przygotowuje nowy plik przed atomową podmianą. Rekursywnie sprawdza `Include`; nie modyfikuje plików dołączonych. Windows obsługuje również względne ścieżki Include, a konfigurację tymczasową sprawdza w katalogu docelowym. Konflikt zarządzanych kluczy, aktywne dyrektywy `TLS*` (także `unencrypted`), autorejestracja, klasyczny agent, wiele instancji, konfiguracja poza standardową ścieżką lub dowiązanie wymagają ręcznego przeglądu. Na Linuksie niestandardowe rozszerzenia jednostki systemd również wymagają przeglądu.

Konfiguracja Windows: `%ProgramFiles%\Zabbix Agent 2\zabbix_agent2.conf`. Log instalatora trafia bezpośrednio i wyłącznie na pulpit konta uruchamiającego, do pliku `Zabbix-install-<identyfikator>.log`; dotyczy to również błędów po rozpoczęciu logowania. Pulpit może być przekierowany, np. do OneDrive. Przy uruchomieniu przez UAC z innym kontem używany jest pulpit tego konta, a dla SYSTEM pulpit publiczny. Brak dostępnego pulpitu przerywa instalację. Chronione backupy i pliki robocze są w `%LOCALAPPDATA%\ZabbixAgentAutoDeploy\`; instalator nie tworzy własnych danych w ProgramData i nie usuwa danych po starszych uruchomieniach. `DryRun` nie zapisuje plików. Konfiguracja Linux: `/etc/zabbix/zabbix_agent2.conf`; backupy w `/var/backups/zabbix-auto-deploy/`, logi w `/var/log/zabbix-auto-deploy/`. Backup powstaje przed zmianą konfiguracji lub aktualizacją pakietu, a przy identycznej konfiguracji i wersji nie jest tworzony ponownie. Nie zmieniamy plików Include, więc nie wymagają osobnej kopii.

Po błędzie skrypt próbuje przywrócić główny plik konfiguracji oraz poprzedni stan usługi i raportuje wynik. Nowa nieudana instalacja pozostaje zatrzymana; pakiet nie jest automatycznie odinstalowywany. Backup nie cofa aktualizacji programu ani zależności. Logi, backupy i ewentualne zmiany pakietów wymagają ręcznego przeglądu po niepełnym odzyskiwaniu. MSI zgłaszający kod 3010 powoduje komunikat o wymaganym restarcie; skrypt nie restartuje systemu.

## Dodawanie hostów passive

Po instalacji i uruchomieniu agenta administrator konfiguruje **Network Discovery i Discovery Actions**:

1. Wybiera zakres IPv4 i serwer albo proxy mający dostęp do agentów na TCP/10050 lub wybranym `ListenPort`. Rzeczywisty adres źródłowy wykonawcy musi być dozwolony w `Server`.
2. Dodaje kontrolę Zabbix agent `agent.hostname` i wybiera jej wynik jako źródło pola `Host name`. Wynik zawiera prefiks z `Hostname`; `Visible name` jest osobnym polem.
3. Tworzy i włącza Discovery Action ograniczoną do właściwej reguły i dostępnej usługi agenta. Akcja dodaje i włącza host oraz przypisuje grupy i szablony passive. System rozpoznaje się osobną regułą lub kontrolą, np. `system.uname`.
4. Sprawdza nazwę techniczną, interfejs i port, przypisanie serwera/proxy oraz napływ danych.

Nazwa z wyniku kontroli dotyczy tworzenia hosta; discovery nie synchronizuje późniejszych zmian prefiksu ani nazwy istniejącego hosta. Gdy nie można użyć wyniku, stosowana jest nazwa DNS lub IP przy braku rozpoznania DNS. Kolizje mogą powodować sufiksy. Rozbieżności administrator poprawia ręcznie. Nakładające się zakresy, zmiany IP lub źródła discovery mogą tworzyć duplikaty; instalator ich nie scala.

Discovery nie instaluje agenta i nie otwiera komunikacji sieciowej. Nie wymaga się dostępu do TCP/10051 wyłącznie na potrzeby discovery; niedostępny `ServerActive` może jednak generować wpisy w logach agenta.

## Active w DMZ

Administrator ręcznie tworzy i włącza host z technicznym `Host name` dokładnie zgodnym z `Hostname`, łącznie z prefiksem i wielkością liter. Przypisuje grupy, szablony z pozycjami Zabbix agent (active) i właściwy serwer/proxy odpowiadający `ServerActive`.

Wymagana jest komunikacja agent → `ServerActive` (domyślnie TCP/10051) z odpowiedziami. Dla monitorowania wyłącznie aktywnego nie wymaga się discovery ani przychodzącego TCP/10050. Ewentualne pozycje passive wymagają osobnej ścieżki sieciowej.

Nie stosujemy autorejestracji ani `HostMetadata`, `HostMetadataItem`, `HostInterface` lub `HostInterfaceItem` do dodawania hostów. Administrator sprawdza istniejące akcje autorejestracji, które mogą reagować na połączenia active także bez metadanych. Instalator nie zarządza tymi akcjami. Integracja z API wymaga osobnej zgody.

## Bezpieczeństwo

- Nowa konfiguracja używa komunikacji nieszyfrowanej; sieć musi być odpowiednio chroniona. Tryb active nie zapewnia szyfrowania. Istniejącego TLS nie wolno usuwać ani osłabiać.
- Instalatory nie konfigurują zapory, routingu, NAT ani SELinux. MSI otrzymuje `SKIP=fw` i `STARTUPTYPE=disabled`; skrypt porównuje lokalne reguły i filtry zapory przed i po MSI. Wykryta różnica przerywa instalację i wymaga ręcznego przeglądu, bez automatycznego cofania reguł. Linux czasowo maskuje jednostkę systemd, aby pakiet nie uruchomił konfiguracji dostawcy.
- Pakiety pochodzą z oficjalnych źródeł HTTPS. Windows weryfikuje przypięty SHA-256 i prawidłowy podpis Authenticode wydawcy Zabbix SIA. Linux sprawdza SHA-256 przypiętego bootstrapu repozytorium oraz SHA-256 i fingerprint publicznego klucza podpisującego. Debian pobiera dokładną wersję przez apt z osobnego, tymczasowego źródła HTTPS i podpisanych indeksów. Rocky weryfikuje podpis pobranego RPM w osobnej bazie zawierającej wyłącznie przypięty klucz, po czym instaluje go przez dnf z kontrolą podpisu. Skrypt nie zapisuje trwałej definicji repozytorium Zabbix. Dla Debiana przypięto `1:7.0.32-2+debian12/13`, dla Rocky `7.0.32-release2.el9`.
- Sekrety, dane infrastruktury, logi, backupy i binaria nie należą do repozytorium. Backup konfiguracji nie cofa aktualizacji pakietu.

## Testy lokalne

Testy i analizatory uruchamiamy wyłącznie lokalnie, bez GitHub Actions. Wyniki bieżącej weryfikacji są raportowane przy przeglądzie zmiany. Pomoc można uruchomić poleceniami powyżej; składnię sprawdzić parserem Windows PowerShell 5.1 i `bash -n 7.0/install.sh`. Zalecane są również PSScriptAnalyzer, ShellCheck i Gitleaks. Zachowuj UTF-8 z BOM dla PowerShell oraz UTF-8 bez BOM i LF dla Bash, również po skopiowaniu skryptów z Windows.

Weryfikacja 0.2.0 z 3 listopada 2026: 33/33 testy Pester w Windows PowerShell 5.1, 13/13 symulacji CLI Windows i 34/34 testy Linuksa z atrapami poleceń i plikami tymczasowymi. Sprawdzono walidację, domyślny i jawny `ServerActive`, brak zapisu przez `DryRun`, zachowanie obcych ustawień, powtarzalność generatora konfiguracji, blokadę downgrade oraz konflikty Include, TLS i autorejestracji. Testy pomocnicze są lokalne, poza śledzonym zakresem repozytorium. Nie potwierdzają działania instalacji na docelowych systemach.

Weryfikacja Windows 0.2.2 z 4 listopada 2026: 70/70 testów Pester w Windows PowerShell 5.1, obejmujących walidację parametrów, powtarzalność konfiguracji, względne Include i konflikty, rozpoznawanie usługi, podmianę i odzyskiwanie plików, zapis logu na pulpicie oraz odczyt wersji rzeczywistego pliku agenta bez uruchamiania usługi. Testy pomocnicze pozostają lokalne, poza śledzonym zakresem repozytorium.

Dla Windows 0.2.2 użytkownik potwierdził pomyślną instalację. Nie potwierdzono pełnej macierzy systemów, aktualizacji, odzyskiwania po błędzie, idempotencji całej instalacji ani wyników Network Discovery. Instalacji Linux nie sprawdzono. Nie sprawdzono rzeczywistej blokady startu usługi przez pakiet ani braku zmian zapory podczas instalacji. Przed wdrożeniem wymagane są scenariusze z sekcji 7 specyfikacji na zatwierdzonych maszynach Windows, Debian i Rocky. Testy zmieniające system, wymagające administratora lub dostępu do infrastruktury potrzebują osobnej zgody.

## Licencja i źródła

[Licencja MIT](LICENSE), właściciel praw: Bofursky. Licencja dotyczy własnego kodu projektu; binariów Zabbix nie dołączamy.

- [Wymagania projektu](SPECIFICATION.md)
- [Historia zmian](CHANGELOG.md)
- [Zabbix 7.0: Network Discovery](https://www.zabbix.com/documentation/7.0/en/manual/discovery/network_discovery)
- [Zabbix 7.0: konfiguracja reguły discovery](https://www.zabbix.com/documentation/7.0/en/manual/discovery/network_discovery/rule)
