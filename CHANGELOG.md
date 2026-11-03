# Historia zmian

Wersjonowanie SemVer instalatorów jest niezależne od wersji Zabbix Agent 2.

## Nieopublikowane

### 0.2.0

- Zaimplementowano samodzielne instalatory Windows x64 (PowerShell 5.1), Debian 12/13 amd64 i Rocky Linux 9 x86_64, przypięte do Zabbix Agent 2 7.0.32.
- Dodano kreator, CLI, wybór lokalnego IPv4, prefiks nazwy hosta, tryby passive/active, propozycję adresu GUI i plan bez zmian.
- Dodano domyślne `ServerActive` z aktualnego `Server`, kontrolowane aktualizacje bez downgrade, zachowanie obcych ustawień i wykrywanie konfliktów Include, TLS, autorejestracji oraz niestandardowych instalacji.
- Dodano chronione backupy i logi, atomową podmianę konfiguracji, lokalne kontrole usługi, wersji i nasłuchu oraz próbę odzyskiwania po błędzie.
- Dodano weryfikację SHA-256 i Authenticode MSI oraz klucza i podpisów pakietów Linux; zablokowano start konfiguracji dostawcy, a MSI otrzymuje `SKIP=fw` z porównaniem lokalnej polityki zapory.
- Zaktualizowano instrukcję i ograniczenia testów. Rzeczywiste instalacje oraz scenariusze laboratoryjne nie zostały jeszcze wykonane. Nie dodano CI ani frameworków testowych.
- Dodano `.gitattributes`, aby Git zachowywał LF skryptu Bash i CRLF skryptu PowerShell.

### 0.1.0

- Dodano zasady pracy w `AGENTS.md` i wymagania projektu w `SPECIFICATION.md` dla Zabbix Agent 2 7.0.x LTS.
- Przygotowano strukturę projektu oraz szkielety `7.0/install.ps1` i `7.0/install.sh` w wersji 0.1.0. Skrypty obsługują pomoc; instalacja i konfiguracja agenta nie są jeszcze zaimplementowane.
- Przygotowano README opisujący aktualny stan projektu i wymagania: passive przez Network Discovery i Discovery Actions, active w DMZ dodawany ręcznie, `ServerActive` także dla passive, nazewnictwo oparte na `agent.hostname` z ograniczeniami discovery oraz ręczne podawanie IP proxy.
- Udokumentowano brak autorejestracji, wymóg osobnej zgody na integrację z API i testy wyłącznie lokalne, bez GitHub Actions.
- Dodano licencję MIT z właścicielem praw Bofursky.
- Przygotowano `.gitignore` wykluczający między innymi logi, backupy, lokalne narzędzia, pliki środowiskowe i pakiety instalacyjne.
