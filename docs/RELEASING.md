# Releases

Ein Tag `vX.Y.Z` startet `.github/workflows/release.yml`:

1. **build** (macOS, Environment `release`): `build.sh` baut AltSwitch universal (arm64 + x86_64).
   Der Job prüft, ob der Tag zu `CFBundleShortVersionString` passt. Dann signiert und
   notarisiert `tools/package_macos.sh` die App mit Developer ID und Hardened Runtime, von innen
   nach außen. Ergebnis: gestapelte DMG und ZIP, jeweils mit `.sha256`.
2. **draft**: GitHub Release als Entwurf, Text aus dem passenden Abschnitt in `CHANGELOG.md`.
3. **publish** (Environment `release`): Der Entwurf wird veröffentlicht.
4. **homebrew-tap** (Environment `release`): `version` und `sha256` in
   `brokoskokoli/homebrew-tap/Casks/altswitch.rb` werden aktualisiert.

Jeder Job mit Environment `release` wartet auf eine Freigabe („Review deployments“ im Lauf),
pro Release also drei Freigaben. Immer nur ein Release gleichzeitig taggen.

## Secrets (Environment `release`)

| Name | Inhalt |
|---|---|
| `MACOS_CERT_P12_BASE64` | `.p12` mit genau der Identität „Developer ID Application“ + Zwischenzertifikat, Base64 |
| `MACOS_CERT_PASSWORD` | Passwort dieser `.p12` |
| `NOTARY_API_KEY_P8_BASE64` | App Store Connect API Key `AuthKey_<id>.p8`, Base64 |
| `NOTARY_API_KEY_ID` | Key-ID (10 Zeichen) |
| `NOTARY_API_ISSUER_ID` | Issuer-ID (UUID) |
| `HOMEBREW_TAP_DEPLOY_KEY` | privater SSH-Deploy-Key mit Schreibrecht nur auf `brokoskokoli/homebrew-tap` |

Einrichten oder erneuern: `tools/setup_release_secrets.sh` im eigenen Terminal ausführen. Das
Skript exportiert das Zertifikat aus dem Schlüsselbund, findet die `.p8`, prüft sie bei Apple und
legt das Environment mit Freigabe-Pflicht an (nur Tags `v*` und Branch `main`). Kein Wert landet
im Repo oder in einer Kommandozeile.

## Ablauf

1. Version in `Resources/Info.plist` setzen:
   - `CFBundleShortVersionString` = `X.Y.Z`;
   - `CFBundleVersion` = `X*10000 + Y*100 + Z` (1.2.3 → `10203`). Der Wert muss bei jedem Release steigen.
2. In `CHANGELOG.md` den Abschnitt `## [X.Y.Z] - JJJJ-MM-TT` schreiben.
3. Commit und Push nach `main`.
4. `git tag vX.Y.Z && git push origin vX.Y.Z`, danach die Freigaben im Lauf erteilen.

**Probelauf** (baut, signiert und notarisiert, veröffentlicht nichts):
`gh workflow run release.yml --ref main`. Das Artefakt `release-dist` bleibt 30 Tage am Lauf.

## Lokal

```bash
./build.sh                                   # ad-hoc signiert, zum Ausprobieren
tools/package_macos.sh AltSwitch.app         # DMG/ZIP ad-hoc (nur Test)
SIGN_IDENTITY="Developer ID Application: Stefan Richter (AGRWTKQZ8C)" \
NOTARY_PROFILE=<profil> tools/package_macos.sh AltSwitch.app --notarize   # Notfallweg ohne CI
```

`NOTARY_PROFILE` legt `xcrun notarytool store-credentials <profil>` einmalig an. Die Dateien vom
Notfallweg lädt man von Hand in einen Release-Entwurf (`gh release create vX.Y.Z --draft dist/*`).

## Schlüssel wechseln

- **Developer-ID-Zertifikat erneuert** (gilt 5 Jahre): neues Zertifikat in den Schlüsselbund
  legen und das Skript erneut ausführen. Es nimmt das gültige mit dem spätesten Ablaufdatum.
  Bereits notarisierte Releases bleiben gültig.
- **API-Key widerrufen**: einen neuen Key anlegen und das Skript erneut ausführen.
- **Tap-Deploy-Key**: Das Skript ersetzt den Key mit dem Titel „altswitch release workflow“.
