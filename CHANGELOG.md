# Historia zmian

Wersjonowanie SemVer instalatorów jest niezależne od wersji Zabbix Agent 2.

## Nieopublikowane

- Dodano zasady pracy w `AGENTS.md` i wymagania projektu w `SPECIFICATION.md` dla Zabbix Agent 2 7.0.x LTS.
- Przygotowano strukturę projektu oraz szkielety `7.0/install.ps1` i `7.0/install.sh` w wersji 0.1.0. Skrypty obsługują pomoc; instalacja i konfiguracja agenta nie są jeszcze zaimplementowane.
- Przygotowano README opisujący aktualny stan projektu i wymagania: passive przez Network Discovery i Discovery Actions, active w DMZ dodawany ręcznie, `ServerActive` także dla passive, nazewnictwo oparte na `agent.hostname` z ograniczeniami discovery oraz ręczne podawanie IP proxy.
- Udokumentowano brak autorejestracji, wymóg osobnej zgody na integrację z API i testy wyłącznie lokalne, bez GitHub Actions.
- Dodano licencję MIT z właścicielem praw Bofursky.
- Przygotowano `.gitignore` wykluczający między innymi logi, backupy, lokalne narzędzia, pliki środowiskowe i pakiety instalacyjne.
