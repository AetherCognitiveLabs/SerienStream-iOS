# Changelog

## [3.1.0] - 2026-11-25

### Neu
- Episodentitel (deutsch + englisch) aus der Staffel-Tabelle
- Wiedergabe-Position wird gespeichert — Resume beim erneuten Abspielen
- Fortschrittsbalken auf Episoden und Weiterschauen-Karten
- Autoplay: nächste Episode startet automatisch mit gleichem Hoster
- „Nächste Episode"-Overlay im Player
- „Weiterschauen"-Button auf der Serien-Detailseite
- Kontextmenü auf Episoden: als gesehen/ungesehen markieren
- Favoriten-Sektion auf Home
- Hoster-Sortierung: bevorzugte Sprache + bevorzugter Hoster
- Neue Settings: Autoplay, Deutsch bevorzugen, bevorzugter Hoster, echte Versionsnummer

### Fix
- Episoden-Regex: raw-string interpolation (\# statt \) — Episoden laden jetzt
- Detail-Layout: Backdrop sprengte die Breite, Inhalte waren verschoben

## [3.0.0] - 2026-11-25
### Hinzugefügt
- Diagnose-System mit In-App-Logs (Settings → Diagnose)
- CI-Verifikation: Simulator-Screenshots und Smoke-Tests bei jedem Build
- Launch-Arguments für Deep-Navigation und automatisierte Tests

### Behoben
- Kritische Fehler in Verbindung, Player und Layout (siehe Commit-Historie)

## [2.0.0] - 2026-11-25
### Hinzugefügt
- Auto-Endpoint-Probing, Proxy als Standard
- Weiterschauen, Verlauf, Gesehen-Markierungen
- Home-Sektionen, Zufalls-Serie, App-Icon, neues Settings-Design

## [1.0.0] - 2026-11-25
### Hinzugefügt
- Erstversion: Katalog, Detail, Player mit Turnstile-Resolver
