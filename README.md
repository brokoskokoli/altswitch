# AltSwitch 🪟

<p align="center">
  <img src="Resources/AppIcon.icns" alt="AltSwitch App Icon" width="128" height="128">
</p>

<p align="center">
  <strong>Der moderne, native Windows-Style Fenster-Umschalter für macOS in Swift & SwiftUI.</strong><br>
  Wechsle zwischen <em>einzelnen Fenstern</em> statt nur Programmen – blitzschnell, mit Live-Vorschau und Tastatur- oder Mauskontrolle.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2013%2B%20%28Ventura%2C%20Sonoma%2C%20Sequoia%29-blue?logo=apple" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/Architecture-Universal%20%28Apple%20Silicon%20%2F%20Intel%29-success" alt="Universal">
  <img src="https://img.shields.io/badge/License-MIT-lightgrey" alt="License MIT">
  <img src="https://img.shields.io/badge/Privacy-100%25%20Offline%20%26%20Local-brightgreen" alt="100% Offline">
</p>

---

## 💡 Warum AltSwitch?

Auf macOS wechselt das klassische `⌘-Tab` standardmäßig nur zwischen **Programmen**, nicht zwischen einzelnen Fenstern. Wenn du mehrere Browser-Fenster, Dokumente oder Terminal-Sessions geöffnet hast, musst du dich umständlich mit Mission Control oder `⌘-<` behelfen.

**AltSwitch bringt den schnellen und beliebten Windows-Style Alt-Tab Switcher auf den Mac:**
- Jedes offene Fenster aller laufenden Programme wird als **eigenständige Vorschau-Karte** angezeigt.
- Echte **Z-Order (Most Recently Used / MRU)** Erkennung: Das zuletzt genutzte Fenster wird beim ersten Tastendruck sofort vorausgewählt.
- **Zwei umschaltbare Layouts**: Kompaktes Karussell oder bildschirmfüllende Raster-Übersicht (Task View) für alle Fenster.
- **Sofortige Klick-Aktivierung**: Kein Doppelklick nötig – dank nativer `acceptsFirstMouse`-Unterstützung aktiviert der erste Mausklick sofort das Zielfenster.
- **100% nativ**: Geschrieben in modernem Swift, AppKit & SwiftUI – ohne Electron, ohne Framework-Ballast, ressourcenschonend und extrem performant.

---

## ✨ Hauptfunktionen

### 1. 🪟 Windows-Style Fenster-Navigation
- Zeigt **alle aktiven Fenster** aller laufenden Anwendungen (Finder, Browser, IDEs, Terminals, Notizen etc.) in chronologischer Nutzungsreihenfolge (MRU Z-Order).
- Erkennt minimierte Fenster und kennzeichnet sie mit einem dezenten Badge.
- Beim Loslassen der Hotkey-Taste (`⌥` oder `⌘`) wird das ausgewählte Fenster sofort in den Vordergrund geholt.

### 2. 📐 Zwei Layout-Modi
Du kannst das Erscheinungsbild nach deinen Wünschen anpassen:
- **Kompakt (Fokus)**:
  - Horizontales Karussell mit automatischem Zentrieren des aktiven Elements.
  - Ideal für den schnellen, fokussierten Wechsel zwischen den letzten Fenstern.
- **Alle Fenster (Raster-Übersicht / Task View)**:
  - Dynamisches Multi-Column Raster, das sich flexibel bis zu **88% Bildschirmbreite** und **80% Bildschirmhöhe** ausdehnt.
  - Zeigt alle Fenster auf einen Blick ohne horizontales Scrollen – wie die Task View in Windows 10/11.
  - Unterstützt 2D-Navigation mit den Pfeiltasten (`←`, `↑`, `→`, `↓`).

### 3. 🖱️ Sofortige Mausklick-Aktivierung (`acceptsFirstMouse`)
- Durch eine spezialisierte `ClickableHostingView` reagiert jede Fensterkarte unmittelbar auf den **ersten Mausklick**.
- Auch wenn das Overlay als schwebendes, nicht-aktivierendes Panel angezeigt wird, ist kein Vorfokussieren oder Doppelklick erforderlich.
- Hover-Effekte heben das überfahrene Fenster optisch hervor.

### 4. 🔄 Flexible Tasten- & Rückwärtsnavigation
- **Vorwärts**: `Tab` oder `→` bzw. `↓`.
- **Rückwärts**:
  - `⇧⇥` (Shift + Tab) bei gehaltenem Modifier (`⌥` oder `⌘`).
  - **Shift-Tap**: Drücke oder tippe einfach kurz `Shift`, während das Overlay aktiv ist, um einen Schritt zurückzugehen!
  - `←` bzw. `↑` für Richtungsnavigation.
- **Abbrechen**: `Escape` schließt das Overlay sofort, ohne den Fokus zu ändern.
- **Bestätigen**: `Enter`, `Leertaste` oder Loslassen der Auslösetaste.

### 5. 📸 Live-Vorschau mit ScreenCaptureKit
- Rendert flüssige, hochauflösende Screenshots aller Fenster im Hintergrund.
- Automatischer Fallback mit App-Icon und Hinweisen, falls die Bildschirmaufnahme-Berechtigung noch nicht gewährt wurde.

### 6. ⚙️ Menüleiste & Einrichtungs-Assistent
- Läuft als reiner Menüleisten-Agent (`LSUIElement=true`, kein störendes Dock-Icon).
- Komfortabler **Einrichtungs-Assistent** mit Live-Erkennung von macOS-Berechtigungen.
- Schnelleinstellungen direkt im Menüleisten-Menü:
  - Tastenkombination: `⌥ Option + Tab` oder `⌘ Command + Tab`.
  - Layout: `Kompakt (Fokus)` oder `Alle Fenster (Raster-Übersicht)`.
  - Autostart beim Anmelden (`SMAppService`).

---

## ⌨️ Tastaturkürzel & Steuerung

| Aktion | Tastenkürzel | Beschreibung |
| :--- | :--- | :--- |
| **Switcher öffnen & Vorwärts** | `⌥ + ⇥` oder `⌘ + ⇥` | Öffnet das Overlay und wählt das vorherige aktive Fenster aus. |
| **Vorwärts blättern** | `⇥` (halten + wiederholt Tab) | Springt zum nächsten Fenster in der Z-Order. |
| **Rückwärts blättern** | `⇧ + ⇥` (Shift + Tab) | Springt einen Schritt zurück in der Liste. |
| **Schnell-Rückschritt** | `⇧` (Shift antippen) | Geht beim Drücken von Shift sofort einen Schritt zurück. |
| **Pfeilnavigation** | `←` / `→` / `↑` / `↓` | Navigiert frei im Karussell bzw. im 2D-Raster. |
| **Fenster aktivieren** | Modifier loslassen oder `↵` / `Space` | Schließt das Overlay und bringt das gewählte Fenster nach vorne. |
| **Fenster per Klick aktivieren**| Mausklick | Aktiviert das angeklickte Fenster sofort. |
| **Abbrechen** | `Esc` | Schließt das Overlay ohne Fensterwechsel. |

---

## 🚀 Installation & Erste Schritte

### Option 1: Homebrew

```bash
brew install --cask brokoskokoli/tap/altswitch
```

### Option 2: Fertiges Release herunterladen
1. Lade das neueste Release (`.dmg` oder `.zip`) von [GitHub Releases](https://github.com/brokoskokoli/altswitch/releases) herunter.
2. Öffne die `.dmg` und ziehe **AltSwitch** in deinen `Programme` (`/Applications`) Ordner.
3. Starte AltSwitch. Beim ersten Start führt dich der integrierte Einrichtungs-Assistent durch die beiden benötigten macOS-Berechtigungen.

### Option 3: Aus dem Quellcode bauen
Voraussetzungen:
- macOS 13.0 oder neuer
- Xcode Command Line Tools (`xcode-select --install`)

```bash
# Repository klonen
git clone https://github.com/brokoskokoli/altswitch.git
cd altswitch

# Kompilieren und App-Bundle erzeugen
./build.sh
# oder
make

# AltSwitch starten
open AltSwitch.app
```

---

## 🔒 Erforderliche macOS-Berechtigungen

AltSwitch benötigt zwei Standard-Systemberechtigungen von macOS:

1. **Bedienungshilfen (Accessibility / Steuerung des Computers)**:
   - *Zweck*: Globaler `CGEventTap` zum Abfangen von `⌥-Tab` / `⌘-Tab` sowie das gezielte Anheben und Fokussieren einzelner Fenster über die `AXUIElement`-API.
   - *Einstellung*: `Systemeinstellungen` → `Datenschutz & Sicherheit` → `Bedienungshilfen`.
2. **Bildschirmaufnahme (Screen Recording)**:
   - *Zweck*: Erstellung der Live-Vorschau-Thumbnails für die Fensterkarten.
   - *Hinweis*: Fehlt diese Berechtigung, funktioniert AltSwitch dennoch vollumfänglich – es werden statt Live-Bildern elegante Platzhalter mit App-Icon angezeigt.
   - *Einstellung*: `Systemeinstellungen` → `Datenschutz & Sicherheit` → `Bildschirmaufnahme`.

> [!NOTE]
> **Datenschutz garantiert**: AltSwitch sendet keinerlei Daten, nutzt keine Analytics und besitzt keinen Netzwerkzugriff. Alle Operationen finden zu 100% lokal im RAM deines Macs statt.

---

## 🏗️ Architektur & Technologie-Stack

AltSwitch ist strikt modular aufgebaut und nutzt die modernsten Apple-Frameworks:

```
altswitch/
├── Sources/
│   └── AltSwitch/
│       ├── App/
│       │   ├── AppDelegate.swift         # Lifecycle, Koordination von Overlay & Statusleiste
│       │   └── main.swift                # App-Einstiegspunkt (@main)
│       ├── Models/
│       │   ├── WindowItem.swift          # Datenmodell für Fenster (ID, Titel, Bounds, Thumbnails)
│       │   └── AppSettings.swift         # Persistente Konfiguration (ShortcutMode, SwitcherLayout)
│       ├── Services/
│       │   ├── WindowManager.swift       # MRU Z-Order Fenster-Enumeration, Thumbnail-Laden & AX-Aktivierung
│       │   ├── HotkeyManager.swift       # Globaler CGEventTap mit Modifier-Tracking & Shift-Erkennung
│       │   ├── PermissionsManager.swift  # Statusprüfung & Deep-Links in Systemeinstellungen
│       │   └── AutostartManager.swift    # SMAppService Integration für System-Login
│       └── UI/
│           ├── ClickableHostingView      # NSHostingView mit acceptsFirstMouse = true
│           ├── OverlayPanel.swift        # NSPanel (.screenSaver level) mit dynamischer Größenberechnung
│           ├── OverlayView.swift         # SwiftUI Overlay: LazyVGrid (Grid) & ScrollView (Kompakt)
│           ├── WindowCardView.swift      # Fensterkarte mit Hover, Selektionsrahmen und Bildvorschau
│           ├── StatusBarController.swift # Menüleisten-Steuerung (NSStatusItem)
│           ├── SetupWindowController.swift# Onboarding-Fenster
│           └── SetupView.swift           # SwiftUI Einrichtungs-Assistent
├── Resources/
│   ├── Info.plist                        # LSUIElement=true, Permissions Usage Descriptions
│   └── AppIcon.icns                      # Offizielles AltSwitch Icon
├── tools/
│   ├── setup_release_secrets.sh          # Einmalig: Release-Secrets interaktiv einrichten
│   └── package_macos.sh                  # Signieren, notarisieren, DMG/ZIP
├── .github/workflows/
│   └── release.yml                       # Automatische GitHub Actions Release Pipeline
├── build.sh                              # High-Performance Swift Build & Packaging Skript
└── Makefile                              # Build Automatisierung (build, run, clean)
```

---

## 🚢 Releases

Releases entstehen per Tag `vX.Y.Z` über GitHub Actions: Universal-Build, Signatur mit Developer ID
und Hardened Runtime, Apple-Notarisierung, DMG/ZIP mit SHA-256, Release-Text aus dem
[CHANGELOG](CHANGELOG.md), anschließend Update des Homebrew-Casks. Jeder Schritt mit Secrets
wartet auf eine Freigabe im GitHub-Environment `release`.

Ablauf, Secrets und Notfallweg: [docs/RELEASING.md](docs/RELEASING.md).

---

## 🏷️ Tags & Keywords

`alt-tab` • `macos-window-switcher` • `task-view` • `window-manager` • `swift` • `swiftui` • `appkit` • `screencapturekit` • `macos-utility` • `accessibility` • `productivity` • `windows-alt-tab-for-mac` • `alt-tab-replacement` • `macos-sequoia` • `macos-sonoma`

---

## 📄 Lizenz

Dieses Projekt ist unter der **MIT Lizenz** lizenziert – freie Nutzung, Anpassung und Weitergabe für jedermann. Details siehe [LICENSE](LICENSE).
