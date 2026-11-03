# AGENTS.md — Zabbix Agent Auto Deploy

## 1. Cel projektu

Projekt `zabbix-agent-auto-deploy` służy do automatyzacji instalacji, konfiguracji i kontrolowanej aktualizacji Zabbix Agent 2 na systemach Windows oraz Linux.

Projekt jest publiczny i powinien być rozwijany zgodnie z dobrymi praktykami programowania, bezpieczeństwa, dokumentowania zmian i kontroli wersji.

Kod musi być czytelny, bezpieczny, możliwy do przetestowania oraz odpowiedni do wykorzystania w środowiskach produkcyjnych po przeprowadzeniu odpowiednich testów.

## 2. Język i nazewnictwo

- Komunikacja z użytkownikiem odbywa się w języku polskim.
- Dokumentacja, komentarze w kodzie, komunikaty instalatorów i opisy commitów muszą być w języku polskim.
- Nazwy plików, katalogów, funkcji, zmiennych i parametrów muszą być w języku angielskim.
- Zachowuj oryginalne angielskie nazwy parametrów Zabbixa, poleceń systemowych, bibliotek i technologii.
- Wszystkie pliki tekstowe zapisuj w UTF-8.
- Instalator Windows musi obsługiwać Windows PowerShell 5.1; pliki PowerShell zawierające polskie znaki zapisuj w UTF-8 z BOM. PowerShell 7 może służyć do kontroli, ale nie zastępuje zgodności z 5.1. Bash zapisuj w UTF-8 bez BOM i z zakończeniami LF.

## 3. Zasady wykonywania zadań

1. Przed rozpoczęciem pracy przeanalizuj istniejący kod, dokumentację i wymagania projektu.
2. Przestrzegaj pliku `SPECIFICATION.md` jako podstawowego źródła wymagań funkcjonalnych.
3. Wprowadzaj wyłącznie zmiany objęte zleconym zadaniem.
4. Nie dodawaj nowych funkcjonalności bez zgody użytkownika.
5. Jeżeli zauważysz problem niezwiązany z zadaniem, zgłoś go zamiast samodzielnie poprawiać.
6. Nie usuwaj istniejących funkcjonalności bez wyraźnej zgody.
7. W przypadku niejasnych wymagań zadawaj krótkie, konkretne pytania.
8. Nie zakładaj, że zmiana jest poprawna, dopóki nie zostanie zweryfikowana dostępnymi testami.
9. Przedstawiaj krótkie podsumowanie wykonanej pracy, zmienionych plików i wyników testów.

## 4. Zarządzanie gałęziami Git

- Główną gałęzią projektu jest `main`.
- Codex może samodzielnie tworzyć nowe gałęzie robocze.
- Każda nowa funkcjonalność, poprawka lub większa zmiana powinna być realizowana na osobnej gałęzi.
- Stosuj nazwy gałęzi w języku angielskim, np.:
  - `feature/windows-installer`
  - `feature/linux-installer`
  - `fix/powershell-encoding`
  - `docs/installation-guide`
  - `ci/github-actions`
- Nie wykonuj bezpośrednich commitów do `main`, z wyjątkiem pierwszej publikacji projektu po wyraźnej zgodzie użytkownika.
- Nie usuwaj gałęzi bez zgody użytkownika.
- Nie wykonuj `git rebase`, `git reset --hard`, `git push --force` ani innych operacji przepisujących historię bez wyraźnej zgody.

## 5. Zasady commitów

Stosuj standard Conventional Commits.

Dozwolone prefiksy:

- `feat:` — nowa funkcjonalność
- `fix:` — poprawka błędu
- `docs:` — dokumentacja
- `test:` — testy
- `ci:` — automatyzacja CI/CD
- `refactor:` — przebudowa kodu bez zmiany funkcjonalności
- `chore:` — konfiguracja, porządkowanie i utrzymanie projektu

Opisy commitów muszą być w języku polskim.

Przykłady:

- `feat: dodanie instalatora Zabbix Agent 2 dla Windows`
- `fix: poprawa wykrywania adresu IPv4`
- `docs: aktualizacja dokumentacji wykrywania hostów`
- `test: dodanie testów instalatora PowerShell`
- `ci: poprawa kodowania w GitHub Actions`
- `chore: inicjalizacja struktury projektu`

### Obowiązkowa procedura przed commitem

1. Zakończ implementację zleconej zmiany.
2. Uruchom dostępne testy i kontrole.
3. Przedstaw listę zmienionych plików.
4. Przedstaw wyniki testów i ewentualne problemy.
5. Zaproponuj dokładny opis commita.
6. Poczekaj na wyraźną akceptację użytkownika.
7. Dopiero po akceptacji wykonaj `git commit`.

Jeżeli użytkownik poda własny opis, użyj dokładnie wskazanego tekstu.

Nie wykonuj automatycznych commitów bez zatwierdzenia.

Jeden commit powinien obejmować jedną logiczną zmianę.

Nie dodawaj automatycznych podpisów AI ani informacji o współautorstwie, chyba że są wymagane przez narzędzia lub zasady projektu.

## 6. Zasady publikowania zmian

- Nie wykonuj `git push` bez wyraźnej zgody użytkownika.
- Akceptacja commita nie oznacza automatycznie zgody na push.
- Przed wysłaniem zmian przedstaw docelową gałąź i repozytorium.
- Nie wykonuj merge do `main` bez wyraźnej zgody.
- Po pierwszej publikacji preferuj Pull Requesty.
- Nie zamykaj ani nie łącz Pull Requestów automatycznie.
- Nie omijaj zabezpieczeń repozytorium.
- Nie modyfikuj ustawień GitHub bez zgody użytkownika.

## 7. Testowanie i kontrola jakości

Codex może samodzielnie uruchamiać testy, analizatory i kontrole jakości bez każdorazowego pytania o zgodę.

Na obecnym etapie testy i kontrole wykonujemy wyłącznie lokalnie. Nie dodawaj ani nie uruchamiaj GitHub Actions w ramach tego zakresu; wdrożenie CI wymaga osobnego zlecenia. Istniejących plików workflow nie usuwaj automatycznie.

Wymagane działania, zależnie od zakresu zmian:

- Kontrola składni PowerShell.
- Analiza statyczna PSScriptAnalyzer.
- Testy Pester dla instalatora Windows.
- Kontrola składni Bash (`bash -n`).
- Analiza ShellCheck dla instalatora Linux.
- Kontrola formatowania i składni YAML.
- Skanowanie Gitleaks.
- Testowanie powtarzalności uruchomienia instalatorów.
- Weryfikacja obsługi błędów i kodów zakończenia.

Nie wyłączaj testów, analizatorów ani skanowania bezpieczeństwa w celu ukrycia problemów.

Jeżeli testu nie można wykonać, wyraźnie zgłoś to w podsumowaniu.

Nie przedstawiaj nieuruchomionych testów jako zakończonych sukcesem.

Testy wymagające uprawnień administratora, rzeczywistej instalacji agenta, modyfikacji systemu lub połączenia z infrastrukturą produkcyjną wymagają osobnej zgody użytkownika.

## 8. Bezpieczeństwo

- Nie zapisuj haseł, tokenów, kluczy prywatnych ani innych sekretów w repozytorium.
- Nie umieszczaj rzeczywistych poufnych adresów IP, nazw hostów, domen i danych infrastruktury firmowej.
- Używaj neutralnych danych przykładowych.
- Nie zapisuj sekretów w logach instalatorów.
- Nie wyłączaj Gitleaks.
- Nie twórz szerokich wyjątków bezpieczeństwa bez uzasadnienia i zgody.
- Jeśli wykryjesz rzeczywisty sekret, wstrzymaj publikację i zgłoś problem.
- Nie wykonuj automatycznych zmian zapory systemowej.
- Nie wprowadzaj TLS PSK bez osobnego wymagania.
- Nie wykonuj destrukcyjnych operacji na systemach produkcyjnych bez zgody.

## 9. Wymagania techniczne projektu

### Windows

- Instalator Zabbix Agent 2 w PowerShell.
- Obsługa instalacji interaktywnej.
- Obsługa parametrów CLI.
- Wykrywanie adresu IPv4 z możliwością ręcznej korekty.
- Obsługa prefiksu nazwy hosta.
- Konfiguracja `Server`, `ServerActive` i `Hostname`.
- Wybór `Mode`: domyślnie `passive` lub jawnie `active`; oba wpisy `Server` i `ServerActive` pozostają w konfiguracji.
- Kopia zapasowa istniejącej konfiguracji przed modyfikacją.
- Obsługa ponownego uruchomienia instalatora.
- Kontrola statusu usługi.
- Logowanie działań i błędów.
- Brak automatycznej konfiguracji zapory.

### Linux

- Instalator Zabbix Agent 2 w Bash.
- Obsługa Debian/Ubuntu oraz RHEL/Rocky/AlmaLinux.
- Instalacja interaktywna i przez parametry CLI.
- Wykrywanie IPv4 z możliwością korekty.
- Prefiks nazwy hosta.
- Konfiguracja `Server`, `ServerActive` i `Hostname` oraz wybór `Mode`: domyślnie `passive` lub jawnie `active`; oba wpisy pozostają w konfiguracji.
- Obsługa systemd.
- Kopia zapasowa konfiguracji.
- Idempotentność.
- Logowanie działań i błędów.
- Brak automatycznej konfiguracji zapory.

### Zabbix

- Docelowa wersja: Zabbix 7.0 LTS.
- Główny sposób monitorowania: agent pasywny.
- Agent aktywny wykorzystywany między innymi w DMZ.
- Hosty `passive` dodają Zabbix 7.0 Network Discovery i Discovery Actions; hosty `active` w DMZ dodaje administrator ręcznie.
- Reguły discovery wykonuje serwer lub właściwy proxy, który musi mieć dostęp do agenta na TCP/10050 (albo wybranym `ListenPort`) i być dozwolony w `Server`. Instalator nie otwiera komunikacji sieciowej.
- W regule discovery źródłem pola `Host name` ma być kontrola Zabbix agent `agent.hostname`, aby techniczna nazwa nowego hosta zawierała prefiks z `Hostname`. Samo dodanie kontroli nie ustawia tego pola. Zabbix 7.0 obsługuje takie nazewnictwo przy tworzeniu hosta, ale nie synchronizuje późniejszych zmian `Hostname` ani prefiksu. Gdy nie można użyć wartości kontroli, stosowana jest domyślna nazwa DNS (z zastąpieniem przez IP przy braku rozpoznania); kolizje nazw mogą powodować sufiksy. Administrator sprawdza techniczną nazwę po utworzeniu hosta i ręcznie koryguje rozbieżności. `Visible name` nie zastępuje nazwy technicznej.
- Administrator ręcznie podaje IPv4 właściwego proxy w `Server` (albo IPv4 serwera przy monitorowaniu bez proxy). Instalator nie wykrywa ani nie wybiera proxy automatycznie i nie zmienia przypisania hosta w Zabbix.
- Obsługa wielu Zabbix Proxy oznacza wybór właściwego endpointu dla danego hosta i reguły discovery, nie automatyczne wykrywanie proxy ani listę adresów w CLI. Zakresy i przypisanie hostów do proxy uzgadnia administrator; zmiany źródła discovery i nakładające się zakresy mogą powodować duplikaty.
- Nie wdrażać autorejestracji ani parametrów `HostMetadata`, `HostMetadataItem`, `HostInterface` i `HostInterfaceItem` do dodawania hostów. Istniejących ustawień nie usuwać automatycznie; przy konflikcie przerwać i wskazać ręczny przegląd.
- Dla `active` techniczna nazwa hosta w Zabbix musi dokładnie odpowiadać `Hostname`; administrator dobiera szablony aktywne i właściwy serwer/proxy. W DMZ nie wymagać otwierania TCP/10050 na potrzeby discovery.
- Pominięty `ServerActive` przyjmuje aktualny IPv4 z `Server` i port 10051 zgodnie ze specyfikacją; jawna wartość ma pierwszeństwo.
- `ServerActive` konfiguruj także dla `passive`. Nie dodawaj integracji z API Zabbix bez osobnej zgody użytkownika.
- Nie zakładaj, że obecność `ServerActive` oznacza wykonywanie aktywnych pomiarów, jeżeli host nie ma odpowiednich pozycji aktywnych.

## 10. Dokumentacja

Aktualizuj dokumentację wyłącznie wtedy, gdy jest to związane z wykonywanym zadaniem.

Podstawowe pliki projektu:

- `README.md`
- `SPECIFICATION.md`
- `CHANGELOG.md`
- `AGENTS.md`
- Dokumentacja Windows i Linux
- Dokumentacja Network Discovery, Discovery Actions i ręcznego dodawania hostów active w DMZ (w README)
- Dokumentacja testów lokalnych

Nie wprowadzaj niepotwierdzonych informacji do dokumentacji.

Docelowy zakres ze `SPECIFICATION.md` obejmuje dwa samodzielne skrypty `7.0/install.ps1` i `7.0/install.sh`. Nie dodawaj modułów, katalogów dokumentacji, frameworków testowych ani GitHub Actions. Powyższa lista dokumentacji określa tematy, nie nakaz tworzenia osobnych plików. Zasady testów i workflow dotyczą istniejących narzędzi oraz zmian osobno zleconych przez użytkownika; nie rozszerzają zakresu specyfikacji. Nie usuwaj istniejących elementów projektu w ramach uzgadniania tych dokumentów.

## 11. GitHub Actions — poza bieżącym zakresem

Obowiązują wyłącznie testy lokalne, bez GitHub Actions. Poniższe zasady dotyczą ewentualnego przyszłego wdrożenia workflow po osobnym zleceniu; nie stanowią zgody na jego dodanie ani uruchomienie.

- Stosuj aktualne i wspierane wersje akcji.
- W workflow Windows preferuj `pwsh`, jeżeli nie jest wymagany Windows PowerShell 5.1.
- Zachowaj poprawne kodowanie UTF-8.
- Nie wyłączaj kontroli jakości, aby uzyskać zielony status workflow.
- Nie publikuj raportów zawierających sekrety.
- Nie dodawaj zbędnych uprawnień do tokenów GitHub Actions.
- W miarę możliwości stosuj zasadę minimalnych uprawnień.

## 12. Raportowanie wyników pracy

Po wykonaniu zadania przedstaw:

1. Krótkie podsumowanie zmian.
2. Listę zmodyfikowanych plików.
3. Wyniki uruchomionych testów.
4. Wykryte problemy lub ograniczenia.
5. Proponowany opis commita.
6. Informację, czy zmiany są gotowe do zatwierdzenia.

Nie wykonuj commita ani push przed otrzymaniem odpowiedniej zgody.

## 13. Zasada nadrzędna

Codex może samodzielnie analizować projekt, tworzyć gałęzie, modyfikować pliki w zakresie zadania i uruchamiać bezpieczne testy.

Użytkownik zachowuje kontrolę nad:

- Zatwierdzaniem opisów commitów.
- Tworzeniem commitów.
- Wysyłaniem zmian na GitHub.
- Łączeniem gałęzi.
- Zmianami historii Git.
- Operacjami destrukcyjnymi.
- Zmianami w infrastrukturze produkcyjnej.

W przypadku wątpliwości Codex powinien zatrzymać operację wymagającą zgody i poprosić użytkownika o decyzję.
