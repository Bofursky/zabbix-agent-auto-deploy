# Specyfikacja zabbix-agent-auto-deploy

Wersja dokumentu: 1.6.1

## 1. Cel i pliki

Przygotować dwa samodzielne skrypty instalujące i konfigurujące **Zabbix Agent 2 z linii 7.0.x LTS**:

- `7.0/install.ps1` — Windows, Windows PowerShell 5.1.
- `7.0/install.sh` — Linux: Debian, Ubuntu, RHEL, Rocky Linux i AlmaLinux.

Każdy skrypt działa po skopiowaniu go na host, bez dodatkowych modułów i plików projektu. Linux korzysta z apt lub dnf i systemd. Wymagane są uprawnienia administratora/root. Przed zmianami sprawdzić wersję systemu, architekturę i dostępność odpowiedniego oficjalnego pakietu; niewspierany system zakończyć czytelnym komunikatem. W README podać rzeczywiście sprawdzone systemy.

Struktura repozytorium:

```text
zabbix-agent-auto-deploy/
├── 7.0/
│   ├── install.ps1
│   └── install.sh
├── README.md
├── SPECIFICATION.md
├── CHANGELOG.md
├── LICENSE
└── .gitignore
```

Katalog `7.0` dotyczy 7.0.x, nie całej rodziny 7.x. Dokładną wersję pakietu, oficjalne źródła i dane weryfikacji zapisać w sekcji stałych każdego skryptu. Nie pobierać automatycznie ruchomego „latest”. Wersję samych skryptów umieścić w nagłówku i CHANGELOG.

## 2. Ustawienia agenta

Administrator podaje `Server`. Jeśli pominie `ServerActive`, skrypt używa dla niego tego samego IPv4, z domyślnym portem 10051. Oba wpisy są zapisywane w konfiguracji niezależnie od sposobu monitorowania:

Przy korzystaniu z proxy administrator ręcznie podaje IPv4 wybranego Zabbix Proxy w `Server`; bez proxy podaje IPv4 serwera. Instalator nie wykrywa ani nie wybiera proxy automatycznie. Pominięty `ServerActive` wskazuje ten sam adres, również dla `passive`; jawnie podany inny endpoint ma pierwszeństwo. Przypisanie hosta i reguły discovery do właściwego proxy administrator ustawia osobno w Zabbix.

| Ustawienie | Wymaganie |
|---|---|
| `Server` | IPv4 serwera/proxy uprawnionego do zapytań passive |
| `ServerActive` | Opcjonalny IPv4 serwera/proxy do kontroli active, także z portem; domyślnie taki sam IPv4 jak `Server`, port 10051 |
| `Hostname` | Ręcznie podany prefiks + systemowa nazwa hosta |
| `ListenIP` | Wykryty lokalny IPv4, z możliwością korekty |
| `ListenPort` | Domyślnie 10050 |

Jawnie podany `ServerActive` ma pierwszeństwo przed wartością domyślną. W kreatorze pusta odpowiedź oznacza użycie `Server`; w CLI pominięcie parametru oznacza to samo, także przy `NonInteractive`. Jawnie podana pusta lub błędna wartość CLI jest błędem. Przy każdym uruchomieniu domyślną wartość wyliczać z aktualnego `Server`, nie z poprzedniej konfiguracji. Nie stosować profili lokalizacji ani zapisanych danych środowiska.

Monitoring jest głównie passive; dla DMZ przewidziany jest active. Parametr skryptu `Mode` opisuje zamierzony sposób monitorowania, nie jest dyrektywą agenta. Ponieważ oba wpisy pozostają w konfiguracji, agent może nasłuchiwać i próbować pobierać aktywne kontrole. O faktycznym sposobie zbierania danych decydują pozycje i szablony w Zabbix.

Hosty `passive` dodawać przez **Zabbix 7.0 Network Discovery i Discovery Actions**. Hosty `active` w DMZ dodaje administrator ręcznie. Skrypty nie tworzą hostów przez API ani nie konfigurują reguł lub akcji na serwerze.

Dodanie integracji z API Zabbix wymaga osobnej zgody użytkownika i nie należy do bieżącego zakresu.

Nie wykorzystywać aktywnej autorejestracji do dodawania hostów. Nie udostępniać parametrów CLI ani pytań kreatora ustawiających `HostMetadata`, `HostMetadataItem`, `HostInterface` lub `HostInterfaceItem` w tym celu. Istniejących ustawień nie usuwać automatycznie; przy konflikcie z wybranym modelem przerwać i wskazać ręczny przegląd. Istniejące akcje autorejestracji po stronie serwera mogą reagować na połączenia active także bez metadanych; administrator musi zweryfikować, że nie dodadzą hostów poza przyjętym modelem. Skrypt nie zarządza tymi akcjami.

`ServerActive` powoduje próby połączenia agenta, nawet gdy monitoring jest passive. Brak tego połączenia może generować wpisy w logu, ale nie blokuje poprawnie działających kontroli passive. Nie wymagać dostępu do TCP/10051 wyłącznie na potrzeby discovery. Network Discovery dla passive wymaga istniejącej lub osobno zapewnionej przez administratora ścieżki serwer/proxy → agent TCP/10050 (albo wybrany `ListenPort`). Bez niej wykrywanie agenta nie zadziała; skrypt nie otwiera komunikacji między VLAN-ami.

Passive wymaga dostępu serwera/proxy do agenta na TCP/10050 i ruchu odpowiedzi. Active wymaga dostępu agenta do endpointu `ServerActive`. Uwzględnić porty podane przez administratora. Bez odpowiedniej ścieżki sieciowej sam wpis IP nie zapewnia monitoringu.

### 2.1. Network Discovery i Discovery Actions dla passive

- Administrator definiuje zakres IPv4, interwał i wykonawcę reguły: serwer albo właściwy Zabbix Proxy mający dostęp do tej sieci. Agent musi już działać, nasłuchiwać na właściwym adresie i porcie oraz dopuszczać rzeczywisty adres źródłowy wykonawcy w `Server` (uwzględnić NAT). Discovery nie instaluje agenta.
- Reguła używa kontroli typu Zabbix agent z kluczem `agent.hostname` na porcie zgodnym z `ListenPort`. Sam test ICMP lub otwartego portu TCP nie potwierdza poprawnej odpowiedzi agenta ani jego nazwy. Kontrole agenta w Network Discovery wymagają komunikacji nieszyfrowanej; istniejący TLS nadal wymaga ręcznego przeglądu zgodnie z sekcją 5.
- Pole `Host name` w regule ustawić na wartość kontroli `agent.hostname`; `Visible name` może korzystać z tej samej nazwy. Wynik zawiera prefiks z konfiguracji `Hostname`. Domyślna nazwa DNS/IP nie zapewnia tej zgodności. Administrator zapewnia unikalność nazw; kolizje mogą skutkować sufiksami, a kolejne przebiegi discovery nie aktualizują automatycznie nazwy po zmianie prefiksu.
- Ograniczenie automatycznego ustawiania nazwy technicznej: samo dodanie kontroli `agent.hostname` nie wybiera jej jako źródła `Host name`. Zabbix 7.0 może nadać nazwę z wyniku kontroli przy tworzeniu hosta, ale nie synchronizuje jej przy kolejnych przebiegach ani nie zmienia w ten sposób nazwy już istniejącego hosta. Jeśli nie można użyć wartości kontroli, stosowana jest domyślna nazwa DNS, a przy braku rozpoznania DNS — adres IP. `Visible name` nie zastępuje technicznego `Host name`. Administrator po utworzeniu hosta porównuje nazwę techniczną z `Hostname` i ręcznie koryguje rozbieżności oraz późniejsze zmiany prefiksu; instalator nie wykonuje korekt przez API.
- Discovery Actions ograniczyć do właściwej reguły, zakresu i dostępnej usługi agenta. Operacje mają dodać i włączyć host, przypisać właściwe grupy i szablony passive. Rozróżnienie Windows/Linux oprzeć na osobnych regułach lub dodatkowej kontroli, np. `system.uname`; nie zakładać, że `agent.hostname` rozpoznaje system.
- Interfejs dodanego hosta musi wskazywać osiągalny dla wykonawcy adres i właściwy port. `InterfaceAddress` z instalatora jest wyłącznie propozycją; discovery nie odczytuje tego parametru i nie przenosi go do GUI. Przy NAT administrator uzgadnia skanowany adres, mapowanie portu i interfejs hosta; lokalny `ListenIP` nadal musi należeć do hosta.
- W środowisku wielu proxy administrator uzgadnia wykonawcę reguły i pole `Monitored by` utworzonego hosta (proxy lub grupę proxy, jeśli używana). CLI nadal przyjmuje pojedynczy IPv4 dla `Server` i pojedynczy endpoint dla `ServerActive`, bez automatycznego wyboru proxy. Nie zakładać, że dowolny proxy ma dostęp do wszystkich sieci.
- Ustalić kryterium unikalności urządzeń i unikać niezamierzonego nakładania zakresów. Identyfikacja urządzenia w regule nie jest tym samym co dopasowanie istniejącego hosta przez akcję. Zmiana IP, interfejsu lub źródła discovery może utworzyć kolejny host; migrację proxy i przypadki wielu interfejsów sprawdzić na używanej wersji 7.0.x. Instalator nie scala ani nie usuwa duplikatów.
- Sam wynik wykrywania nie oznacza utworzenia hosta: potrzebna jest włączona, pasująca Discovery Action. Administrator potwierdza nazwę, interfejs, przypisanie proxy, szablony i napływ danych po wykonaniu akcji.

### 2.2. Ręczne dodawanie active w DMZ

Administrator tworzy i włącza host ręcznie, wpisuje techniczne `Host name` dokładnie zgodne z `Hostname` (z uwzględnieniem wielkości liter i prefiksu), przypisuje grupy, szablony z pozycjami Zabbix agent (active) oraz właściwy serwer/proxy zgodny z `ServerActive`. Sama widoczna nazwa hosta nie zastępuje nazwy technicznej. Wymagana jest komunikacja agent → `ServerActive`, domyślnie TCP/10051, wraz z odpowiedziami. Nie wymagać discovery ani otwierania przychodzącego TCP/10050 dla hosta monitorowanego wyłącznie aktywnie; pozostawiony lokalny nasłuch nie nakłada takiego wymagania. Jeśli administrator dołączy pozycje passive, musi osobno zapewnić ich interfejs i dostęp sieciowy.

## 3. Wykrycie IP i nazwa hosta

- Odczytać IPv4 z aktywnych lokalnych interfejsów; pominąć loopback, link-local/APIPA i adresy nieprawidłowe.
- Pokazać propozycję z nazwą interfejsu i pozwolić wybrać lub wpisać inny lokalny adres.
- Przy wielu adresach bez jednoznacznego wyboru wymagać decyzji użytkownika lub parametru CLI. Nie wymagać połączenia z Zabbix do wykrycia lokalnego IP.
- `ListenIP` musi być adresem przypisanym do hosta. Nie wpisywać tam adresu NAT.
- Adres interfejsu hosta w GUI Zabbix jest osobnym ustawieniem. Skrypt wyświetla propozycję do weryfikacji interfejsu utworzonego przez discovery lub do ręcznego wpisania, jeśli jest potrzebny, ale nie zmienia konfiguracji serwera. Parametr `InterfaceAddress` pozwala wskazać inną propozycję, np. adres NAT; domyślnie jest to lokalny IPv4.
- Prefiks dopisywać zawsze do nazwy systemowej, nie do poprzedniej wartości `Hostname`. Nie zmieniać nazwy systemowej i nie podwajać prefiksu przy kolejnym uruchomieniu.
- Dopuścić świadomie podany pusty prefiks. Wynikowy `Hostname`: pojedyncza nazwa, do 128 znaków, znaki `A-Za-z0-9._-`. Nie poprawiać ani nie ucinać jej po cichu.

## 4. Uruchamianie

Bez parametrów skrypt uruchamia kreator. Obsługuje również własne parametry CLI:

| PowerShell | Bash | Znaczenie |
|---|---|---|
| `-Mode` | `--mode` | `passive` domyślnie lub `active` |
| `-Server` | `--server` | Wymagany IPv4 |
| `-ServerActive` | `--server-active` | Opcjonalny IPv4, także z portem; pominięty przyjmuje IPv4 z `Server`, port 10051 |
| `-HostnamePrefix` | `--hostname-prefix` | Wymagany jawny prefiks, także pusty |
| `-LocalAddress` | `--local-address` | Ręczny wybór lokalnego IPv4 |
| `-InterfaceAddress` | `--interface-address` | Propozycja adresu do GUI Zabbix |
| `-ListenPort` | `--listen-port` | Port nasłuchu, domyślnie 10050 |
| `-Upgrade` | `--upgrade` | Jawna aktualizacja do wersji zapisanej w skrypcie |
| `-NonInteractive` | `--non-interactive` | Bez pytań; brak wymaganych danych jest błędem |
| `-Yes` | `--yes` | Pominięcie końcowego potwierdzenia |
| `-DryRun` | `--dry-run` | Wyświetlenie planu bez zmian |
| `-Help` | `--help` | Pomoc |

Parametry CLI mają pierwszeństwo przed propozycjami kreatora. W trybie bez pytań wymagane jest `Yes`, chyba że wybrano `DryRun`. Pomoc nie wymaga uprawnień administratora.

Przed wykonaniem pokazać wersję agenta, oba IP, nazwę hosta, lokalny adres, port i plan zmian. Sprawdzić składnię IPv4 i portów oraz odrzucić nieznane flagi i znaki pozwalające wstrzyknąć dodatkowe dyrektywy. Port `ServerActive`: 1–65535; `ListenPort`: 1024–32767. Nie używać `eval` ani `Invoke-Expression`.

## 5. Instalacja, backup i błędy

1. Sprawdzić uprawnienia, platformę, parametry, istniejący pakiet, konfigurację i usługę.
2. Jeśli agent nie istnieje, zainstalować wskazaną w skrypcie wersję. Istniejącego Agent 2 z obsługiwanej linii 7.0.x nie aktualizować bez `Upgrade`. Nie wykonywać downgrade ani pełnej aktualizacji systemu.
3. Przed zmianą konfiguracji wykonać kopię z datą i godziną, poza repozytorium, dostępną tylko uprawnionym użytkownikom. Uwzględnić zmieniane pliki include.
4. Zachować obce ustawienia. Nie dopisywać wielokrotnie tych samych kluczy. Przy konflikcie w plikach include przerwać z opisem problemu.
5. Przygotować i sprawdzić nową konfigurację przed podmianą; zastosować ją bez pozostawienia częściowo zapisanego pliku.
6. Uruchomić usługę lub zrestartować ją tylko wtedy, gdy jest to potrzebne.
7. Przy błędzie konfiguracji lub startu spróbować odtworzyć poprzednie pliki i stan usługi. Podać wynik odzyskiwania. Backup konfiguracji nie cofa aktualizacji programu.

Ponowne uruchomienie z tymi samymi ustawieniami nie powoduje reinstalacji, dopisywania wpisów, zbędnego restartu ani kolejnego backupu bez zmiany konfiguracji.

Przy klasycznym agencie, instalacji spoza 7.0.x, wielu instancjach lub istniejącym TLS przerwać i wskazać potrzebę ręcznego przeglądu. Nie usuwać ani nie osłabiać istniejących zabezpieczeń. Nie uruchamiać świeżo instalowanego agenta z przypadkową konfiguracją dostawcy przed zapisaniem ustawień docelowych.

Błędy zgłaszać po polsku i kończyć niezerowym kodem. Zapisać lokalny log przebiegu, bez sekretów i pełnego zrzutu cudzej konfiguracji. Nie wykonywać automatycznego restartu systemu. Jeśli instalator wymaga restartu, wyraźnie to zgłosić.

## 6. Pobieranie i ograniczenia

- Pobierać wyłącznie z oficjalnych źródeł Zabbix przez HTTPS z kontrolą certyfikatu.
- Windows: zweryfikować SHA-256 z sekcji stałych oraz podpis Authenticode właściwego wydawcy przed wykonaniem MSI.
- Linux: użyć oficjalnego repozytorium 7.0 i weryfikacji podpisów przez apt/dnf. Bootstrap repozytorium sprawdzić przez zaufaną sumę, a klucz przez fingerprint zapisany w skrypcie.
- Przy błędzie weryfikacji przerwać instalację. Nie wyłączać kontroli podpisów ani certyfikatów.
- Nie zmieniać zapory, routingu ani SELinux. Dla MSI użyć `SKIP=fw` i sprawdzić, że reguły zapory pozostają bez zmian.
- Nie konfigurować TLS PSK ani certyfikatów; w README jasno podać, że nowa konfiguracja używa komunikacji nieszyfrowanej.
- `DryRun` nie instaluje, nie pobiera pakietów i nie zapisuje plików ani nie zmienia usług.

## 7. Sprawdzenie działania i dokumentacja

Na obecnym etapie wszystkie testy i kontrole wykonujemy wyłącznie lokalnie, bez GitHub Actions. Testy instalacyjne i sieciowe przeprowadza się na zatwierdzonych maszynach laboratoryjnych po osobnej zgodzie użytkownika; nie oznacza to zgody na zmiany w produkcji. Nie dodawać ani nie uruchamiać workflow CI w ramach tego zakresu. Istniejących elementów projektu, w tym workflow i narzędzi testowych, nie usuwać automatycznie.

Po instalacji sprawdzić wersję agenta, stan usługi, odpowiedź lokalnego testu `agent.ping`, zapis obu IP i nasłuch na wybranym adresie. Test lokalny nie potwierdza dostępności przez VLAN ani otrzymywania danych przez Zabbix.

Raport końcowy zawiera wynik instalacji, ścieżkę konfiguracji, backupu i logu, techniczną nazwę hosta oraz propozycję adresu i portu do GUI Zabbix. Dla passive wskazuje oczekiwanie na Network Discovery i Discovery Actions oraz potrzebę weryfikacji utworzonego hosta; dla active w DMZ wskazuje ręczne dodanie hosta i szablonów aktywnych. Konfigurację reguł, akcji, grup, szablonów i proxy oraz sprawdzenie danych w Zabbix wykonuje administrator.

Przed użyciem produkcyjnym sprawdzić składnię obu skryptów oraz na maszynach testowych: świeżą instalację, ponowne uruchomienie bez zmian, rekonfigurację z backupem, błędne parametry, odzyskanie po błędzie i brak zmian zapory. Sprawdzić pominięcie `ServerActive` (kopiowanie IPv4 z `Server`) i jawne podanie innego adresu/portu, także w trybie bez pytań. Wariant passive sprawdzić także bez dostępu do `ServerActive`. Zapisać w README rzeczywiście wykonane sprawdzenia.

README zawiera krótką instrukcję, przykłady interaktywne i CLI, wymagania, sprawdzone systemy, opis obu wpisów IP oraz backupu i typowych błędów. CHANGELOG opisuje rzeczywiste zmiany. LICENSE: MIT dla własnych skryptów, z prawidłowymi danymi właściciela praw; binariów Zabbix nie dołączać.

W README opisać także konfigurację Network Discovery i Discovery Actions dla passive oraz ręczne dodawanie active w DMZ zgodnie z sekcjami 2.1–2.2. Przed użyciem produkcyjnym w zatwierdzonym laboratorium sprawdzić oba systemy: dodanie passive przez akcję, nazwę z prefiksem, interfejs i port, właściwy proxy, brak odpowiedzi przy niedostępnym TCP/10050 oraz ręcznie utworzony active w DMZ bez przychodzącego TCP/10050. Sprawdzić ponowne discovery bez duplikatu przy niezmienionym IP i źródle oraz brak dodawania hostów przez istniejące akcje autorejestracji. Są to wymagania przyszłej weryfikacji, nie deklaracja wykonanych testów.

Dokumentacja, komentarze i komunikaty po polsku; nazwy plików, funkcji i zmiennych po angielsku. PowerShell 5.1: UTF-8 z BOM dla polskich znaków; Bash: UTF-8 bez BOM i zakończenia LF.

Repozytorium publiczne nie może zawierać danych firmowych ani sekretów. Przykłady używają adresów dokumentacyjnych, np. `192.0.2.10`. Logi i backupy wykluczyć przez `.gitignore`.

Nie tworzyć dodatkowych modułów, katalogów dokumentacji, frameworków testowych ani GitHub Actions. Dokument dotyczy wyłącznie opisanych dwóch skryptów.

## Dokumentacja Zabbix 7.0 do implementacji

- [Agent 2 — Linux](https://www.zabbix.com/documentation/7.0/en/manual/appendix/config/zabbix_agent2)
- [Agent 2 — Windows](https://www.zabbix.com/documentation/7.0/en/manual/appendix/config/zabbix_agent2_win)
- [Instalacja MSI i SKIP=fw](https://www.zabbix.com/documentation/7.0/en/manual/installation/install_from_packages/win_msi)
- [Network Discovery — nazwy, interfejsy i proxy](https://www.zabbix.com/documentation/7.0/en/manual/discovery/network_discovery)
- [Konfiguracja reguły Network Discovery](https://www.zabbix.com/documentation/7.0/en/manual/discovery/network_discovery/rule)
- [Konfiguracja akcji](https://www.zabbix.com/documentation/7.0/en/manual/config/notifications/action)
- [Ręczna konfiguracja hosta](https://www.zabbix.com/documentation/7.0/en/manual/config/hosts/host)
