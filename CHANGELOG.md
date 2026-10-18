# Changelog

Alle nennenswerten Änderungen an AltSwitch. Format: [Keep a Changelog](https://keepachangelog.com/de/1.1.0/),
Versionen nach [Semantic Versioning](https://semver.org/lang/de/).

## [Unreleased]

### Hinzugefügt
- Minimierte Fenster zeigen eine Vorschau: das letzte Bild, bevor sie minimiert wurden.
- Beim ersten Start aus dem Programme-Ordner schaltet sich der Autostart ein. Abschalten geht weiter im Menü.
- Es läuft immer nur eine Instanz. Ein zweiter Start meldet „AltSwitch läuft bereits“ und beendet sich.

### Behoben
- Rasteransicht: ↓ springt nicht mehr in die erste Reihe, wenn die letzte Reihe kürzer ist.
- Rasteransicht: Scrollen unter dem ruhenden Mauszeiger verstellt die Auswahl nicht mehr.

## [1.0.1] - 2026-10-18

### Geändert
- AltSwitch ist jetzt mit einer Apple Developer ID signiert und von Apple notarisiert. Die App startet ohne Gatekeeper-Warnung.
- Universal-Build: läuft nativ auf Apple-Silicon- und Intel-Macs.
- Installation per Homebrew: `brew install --cask brokoskokoli/tap/altswitch`.

## [1.0.0] - 2026-10-17

Erste Version (nicht signiert, zurückgezogen).

[1.0.1]: https://github.com/brokoskokoli/altswitch/releases/tag/v1.0.1
