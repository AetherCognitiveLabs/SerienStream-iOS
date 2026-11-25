# Changelog

## [3.2.0] - 2026-11-25

### Player — komplett neu
- **Kein Cloudflare-Turnstile mehr nötig**: Direct-Resolver löst Hoster rein über HTTP auf (POST /r mit signiertem Token — das Gate war nur UI)
- Nahtloser Handoff: WebView-Fallback scannt im Hintergrund weiter und wechselt automatisch in den nativen Player
- Autoplay im Web-Player (mediaTypesRequiringUserActionForPlayback)
- XHR/fetch-Netzwerk-Hook schreibt Stream-URLs ab dem ersten Byte mit
- Tracking-URLs (jwpltx etc.) werden nicht mehr als Stream erkannt

### Design — Apple-TV-Stil
- Cinematic Hero-Carousel auf Home mit echten Homepage-Backdrops, Auto-Rotation und „Jetzt ansehen"
- „Neue Episoden"-Sektion aus dem offiziellen Episoden-Kalender (Cover, S/E-Badge, Datum)
- Detail-Seite: großes Backdrop-Hero, Serienlogo (TMDB), Badge-Zeile mit Score/Jahr/FSK/Genres
- TMDB-Integration: Score, Logo, HD-Backdrop — API-Key in den Einstellungen hinterlegbar

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
