#!/usr/bin/env bash
set -euo pipefail

# Text styling
BOLD="\033[1m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
RED="\033[0;31m"
NC="\033[0m" # No Color

echo -e "${BOLD}${CYAN}====================================================${NC}"
echo -e "${BOLD}${CYAN}   AltSwitch — GitHub Secrets Setup for Release   ${NC}"
echo -e "${BOLD}${CYAN}====================================================${NC}"
echo ""
echo "Dieses Skript richtet die benötigten GitHub Secrets für die automatische"
echo "Code-Signierung und Notarisierung durch Apple in deinen GitHub Actions ein."
echo ""

# Check for gh CLI
if ! command -v gh &> /dev/null; then
    echo -e "${RED}[Fehler] Die GitHub CLI ('gh') ist nicht installiert.${NC}"
    echo "Installiere sie z.B. mit: brew install gh"
    exit 1
fi

# Check gh authentication
if ! gh auth status &> /dev/null; then
    echo -e "${YELLOW}[Hinweis] Du bist noch nicht in der GitHub CLI angemeldet.${NC}"
    echo "Führe zuerst aus: gh auth login"
    exit 1
fi

echo -e "${GREEN}✓ GitHub CLI ist installiert und angemeldet.${NC}"
echo ""

# 1. Certificate (.p12 path or base64)
echo -e "${BOLD}1. Apple Developer ID Application Zertifikat (.p12)${NC}"
echo "   Woher: Keychain Access (Schlüsselbundverwaltung) ->"
echo "   'Developer ID Application: ...' als .p12-Datei exportieren."
read -r -p "   Pfad zur .p12-Datei oder Base64-String: " CERT_INPUT

CERT_BASE64=""
if [ -f "${CERT_INPUT/#\~/$HOME}" ]; then
    EXPANDED_PATH="${CERT_INPUT/#\~/$HOME}"
    echo "   -> Lese Datei ein und konvertiere nach Base64..."
    CERT_BASE64=$(base64 -i "${EXPANDED_PATH}" | tr -d '\n')
else
    CERT_BASE64="${CERT_INPUT}"
fi

if [ -z "${CERT_BASE64}" ]; then
    echo -e "${RED}Fehler: Kein Zertifikat angegeben.${NC}"
    exit 1
fi

# 2. Certificate Password
echo ""
echo -e "${BOLD}2. Zertifikats-Passwort (P12-Passwort)${NC}"
echo "   Das Passwort, mit dem die .p12-Datei beim Export geschützt wurde."
read -r -s -p "   Passwort: " CERT_PASSWORD
echo ""

# 3. Apple ID Email
echo ""
echo -e "${BOLD}3. Apple ID (E-Mail)${NC}"
echo "   Die E-Mail-Adresse deines Apple Developer Accounts."
read -r -p "   Apple ID: " APPLE_ID

# 4. Apple Team ID
echo ""
echo -e "${BOLD}4. Apple Team ID (10 Zeichen)${NC}"
echo "   Woher: https://developer.apple.com/account -> 'Membership details' -> Team ID"
read -r -p "   Team ID: " TEAM_ID

# 5. App-Specific Password
echo ""
echo -e "${BOLD}5. App-spezifisches Passwort für Notarisierung${NC}"
echo "   Woher: https://appleid.apple.com -> 'Anmelden und Sicherheit' ->"
echo "   'App-spezifische Passwörter' -> Neues Passwort erstellen (z.B. 'AltSwitch Notarization')."
read -r -s -p "   App-spezifisches Passwort (Format: xxxx-xxxx-xxxx-xxxx): " APP_SPECIFIC_PW
echo ""

# Confirmation and Setting
echo ""
echo -e "${YELLOW}Setze Secrets in GitHub Repository...${NC}"

echo -n "${CERT_BASE64}" | gh secret set APPLE_CERTIFICATE_BASE64
echo -e "${GREEN}✓ APPLE_CERTIFICATE_BASE64 gesetzt.${NC}"

echo -n "${CERT_PASSWORD}" | gh secret set APPLE_CERTIFICATE_PASSWORD
echo -e "${GREEN}✓ APPLE_CERTIFICATE_PASSWORD gesetzt.${NC}"

echo -n "${APPLE_ID}" | gh secret set APPLE_ID
echo -e "${GREEN}✓ APPLE_ID gesetzt.${NC}"

echo -n "${TEAM_ID}" | gh secret set APPLE_TEAM_ID
echo -e "${GREEN}✓ APPLE_TEAM_ID gesetzt.${NC}"

echo -n "${APP_SPECIFIC_PW}" | gh secret set APPLE_APP_SPECIFIC_PASSWORD
echo -e "${GREEN}✓ APPLE_APP_SPECIFIC_PASSWORD gesetzt.${NC}"

echo ""
echo -e "${BOLD}${GREEN}====================================================${NC}"
echo -e "${BOLD}${GREEN}   Alle Secrets wurden erfolgreich hinterlegt!      ${NC}"
echo -e "${BOLD}${GREEN}====================================================${NC}"
echo ""
echo "Aktuelle Secrets in diesem Repository:"
gh secret list
echo ""
echo "Wenn du einen neuen Release erstellen möchtest:"
echo "  git tag v1.0.0"
echo "  git push origin v1.0.0"
echo "Die GitHub Action baut, signiert und notarisiert das Release automatisch!"
