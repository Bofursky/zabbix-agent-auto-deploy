# zabbix-agent-auto-deploy

Projekt dwóch samodzielnych instalatorów **Zabbix Agent 2 7.0.x LTS** dla Windows i Linux. Źródłem wymagań jest [SPECIFICATION.md](SPECIFICATION.md), wersja 1.6.1; zasady pracy opisuje [AGENTS.md](AGENTS.md).

## Stan projektu

Przygotowano strukturę i szkielety skryptów w wersji 0.1.0. **Skrypty w `7.0/` nie instalują ani nie konfigurują agenta.** Obsługują wyłącznie pomoc; pozostałe wywołania kończą się kodem 1 i komunikatem o braku implementacji. Nie są gotowe do wdrożenia.

Starszy lokalny prototyp, jego moduły, dodatkowa dokumentacja, testy i workflow zostały usunięte podczas porządkowania katalogu na polecenie użytkownika. Bieżący zakres obejmuje pliki z poniższej struktury.

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
└── .gitignore
```

Katalog `7.0/` dotyczy linii 7.0.x LTS. Instalatory mają działać po skopiowaniu pojedynczego skryptu na host. Nie dodajemy modułów, dodatkowego katalogu dokumentacji, frameworków testowych ani GitHub Actions. Zachowany `.gitkeep` jest wyłącznie wcześniejszym znacznikiem katalogu.

## Uruchomienie obecnych szkieletów

Windows PowerShell 5.1, bez uprawnień administratora:

```powershell
.\7.0\install.ps1 -Help
```

Linux Bash:

```bash
bash 7.0/install.sh --help
```

## Docelowe wymagania i użycie

Windows: Windows PowerShell 5.1. Linux: Bash, systemd oraz apt lub dnf; docelowe rodziny systemów to Debian/Ubuntu i RHEL/Rocky/AlmaLinux. Rzeczywista instalacja będzie wymagała administratora/root. Lista systemów zweryfikowanych pełną instalacją: brak.

Poniższe przykłady opisują **docelowy interfejs, który nie jest jeszcze zaimplementowany**. Bez parametrów ma działać kreator. Administrator podaje IPv4 serwera lub wybranego proxy i prefiks nazwy hosta; lokalny IPv4 jest wykrywany z możliwością korekty.

```powershell
.\7.0\install.ps1 -Server '192.0.2.20' -HostnamePrefix 'LAB-' -LocalAddress '192.0.2.10' -NonInteractive -DryRun
```

```bash
bash 7.0/install.sh --server '192.0.2.20' --hostname-prefix 'LAB-' --local-address '192.0.2.10' --non-interactive --dry-run
```

Adresy są dokumentacyjne; należy zastąpić je danymi zatwierdzonego laboratorium. `LocalAddress` musi należeć do hosta. Docelowy `DryRun` pokazuje plan bez pobierania pakietów, zapisów i zmian usług.

`Mode` domyślnie wynosi `passive`; dla DMZ można wskazać `active`. Oba tryby zapisują `Server` i `ServerActive`. Pominięty `ServerActive` otrzymuje aktualny IPv4 z `Server` i port 10051; jawny endpoint ma pierwszeństwo. Sama obecność `ServerActive` nie zapewnia aktywnych pomiarów — wymagają one odpowiednich pozycji i szablonów w Zabbix. Administrator ręcznie wybiera IP proxy; instalator nie wykrywa proxy ani nie zmienia przypisania hosta w Zabbix.

Docelowy instalator zachowuje obce ustawienia, tworzy chroniony backup przed zmianą konfiguracji i nie reinstaluje ani nie restartuje usługi bez potrzeby. Aktualizacja wymaga jawnego `Upgrade`. Błędny adres, konflikt konfiguracji/include, istniejący TLS, nieobsługiwana instalacja lub błąd weryfikacji pakietu mają przerwać operację z czytelnym komunikatem i niezerowym kodem. Szczegóły parametrów, odzyskiwania i logowania zawiera specyfikacja.

## Dodawanie hostów passive

Po przyszłej instalacji i uruchomieniu agenta administrator konfiguruje **Network Discovery i Discovery Actions**:

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

- Nowa konfiguracja ma używać komunikacji nieszyfrowanej; sieć musi być odpowiednio chroniona. Tryb active nie zapewnia szyfrowania. Istniejącego TLS nie wolno usuwać ani osłabiać.
- Instalatory nie zmieniają zapory, routingu, NAT ani SELinux. Dla MSI wymagane jest `SKIP=fw`.
- Pakiety mają pochodzić z oficjalnych źródeł HTTPS, z przypiętą wersją i weryfikacją zgodną ze specyfikacją. Szkielety jeszcze ich nie pobierają.
- Sekrety, dane infrastruktury, logi, backupy i binaria nie należą do repozytorium. Backup konfiguracji nie cofa aktualizacji pakietu.

## Testy lokalne

Testy i analizatory uruchamiamy wyłącznie lokalnie, bez GitHub Actions. Szkielety wymagają sprawdzenia składni, kodowania, pomocy i kodu błędu dla pozostałych wywołań. Wyniki bieżącej weryfikacji są raportowane przy przeglądzie zmiany.

Weryfikacja szkieletów 0.1.0 z 3 listopada 2026: poprawna składnia PowerShell i Bash (`bash -n`), brak uwag PSScriptAnalyzer i ShellCheck, pomoc z kodem 0 i brak implementacji z kodem 1 w Windows PowerShell 5.1 oraz Bash 5.2. Sprawdzono UTF-8 z BOM dla PowerShell oraz UTF-8 bez BOM i LF dla Bash. Gitleaks nie wykrył sekretów w skryptach i przygotowanej dokumentacji. Nie jest to potwierdzenie działania instalatorów.

Nie wykonano pełnej instalacji, aktualizacji, odzyskiwania, testów idempotencji ani testów laboratoryjnych Zabbix dla skryptów `7.0/`. Przed wdrożeniem wymagane są kontrole i scenariusze z sekcji 7 specyfikacji. Testy zmieniające system, wymagające administratora lub dostępu do infrastruktury potrzebują osobnej zgody.

## Licencja i źródła

[Licencja MIT](LICENSE), właściciel praw: Bofursky. Licencja dotyczy własnego kodu projektu; binariów Zabbix nie dołączamy.

- [Wymagania projektu](SPECIFICATION.md)
- [Historia zmian](CHANGELOG.md)
- [Zabbix 7.0: Network Discovery](https://www.zabbix.com/documentation/7.0/en/manual/discovery/network_discovery)
- [Zabbix 7.0: konfiguracja reguły discovery](https://www.zabbix.com/documentation/7.0/en/manual/discovery/network_discovery/rule)
