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
echo "Code-Signierung und Apple-Notarisierung in deinen GitHub Actions ein."
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

# Helper to clean input strings (trim whitespace, remove wrapping quotes)
clean_input() {
    local val="${1:-}"
    # Remove leading whitespace
    val="${val#"${val%%[![:space:]]*}"}"
    # Remove trailing whitespace
    val="${val%"${val##*[![:space:]]}"}"
    # Strip wrapping double quotes
    if [[ "$val" =~ ^\"(.*)\"$ ]]; then
        val="${BASH_REMATCH[1]}"
    fi
    # Strip wrapping single quotes
    if [[ "$val" =~ ^\'(.*)\'$ ]]; then
        val="${BASH_REMATCH[1]}"
    fi
    # Trim again if spaces were inside quotes
    val="${val#"${val%%[![:space:]]*}"}"
    val="${val%"${val##*[![:space:]]}"}"
    printf '%s' "$val"
}

# Helper to resolve file paths (handling tilde expansion and drag & drop backslashes)
resolve_path() {
    local p="$1"
    # Expand tilde
    p="${p/#\~/$HOME}"
    # Check if exists as-is
    if [ -f "$p" ]; then
        printf '%s' "$p"
        return
    fi
    # Try unescaping backslash-escaped spaces (common in macOS Terminal drag & drop)
    local unescaped="${p//\\ / }"
    if [ -f "$unescaped" ]; then
        printf '%s' "$unescaped"
        return
    fi
    printf '%s' "$p"
}

# 1. Certificate (.p12 path or base64)
echo -e "${BOLD}1. Apple Developer ID Application Zertifikat (.p12)${NC}"
echo "   Woher: Schlüsselbundverwaltung (Keychain Access) ->"
echo "   'Developer ID Application: ...' als .p12-Datei exportieren."
read -r -p "   Pfad zur .p12-Datei oder Base64-String: " RAW_CERT_INPUT
CERT_INPUT=$(clean_input "$RAW_CERT_INPUT")
RESOLVED_CERT_PATH=$(resolve_path "$CERT_INPUT")

CERT_BASE64=""
if [ -f "${RESOLVED_CERT_PATH}" ]; then
    echo "   -> Lese .p12-Datei ein und konvertiere nach Base64..."
    CERT_BASE64=$(base64 < "${RESOLVED_CERT_PATH}" | tr -d '\r\n')
elif [[ "${CERT_INPUT}" == *".p12"* ]] || [[ "${CERT_INPUT}" == *".pfx"* ]] || [[ "${CERT_INPUT}" == *"/"* ]] || [[ "${CERT_INPUT}" == *"~"* ]]; then
    echo -e "${RED}[Fehler] Zertifikatsdatei wurde nicht gefunden: ${RESOLVED_CERT_PATH}${NC}"
    exit 1
else
    CERT_BASE64="${CERT_INPUT//[[:space:]]/}"
fi

if [ -z "${CERT_BASE64}" ]; then
    echo -e "${RED}[Fehler] Kein Zertifikat angegeben.${NC}"
    exit 1
fi

# 2. Certificate Password
echo ""
echo -e "${BOLD}2. Zertifikats-Passwort (P12-Passwort)${NC}"
echo "   Das Passwort, mit dem die .p12-Datei beim Export geschützt wurde."
read -r -s -p "   Passwort: " CERT_PASSWORD
echo ""

# 3. Notarization Method
echo ""
echo -e "${BOLD}3. Notarisierungs-Methode wählen${NC}"
echo "   1) App Store Connect API Key (Empfohlen & modern — Key ID, Issuer ID, .p8 AuthKey)"
echo "   2) Apple ID & App-spezifisches Passwort (Legacy Methode)"
read -r -p "   Auswahl [1/2, Standard: 1]: " AUTH_CHOICE
AUTH_CHOICE="${AUTH_CHOICE:-1}"

if [ "${AUTH_CHOICE}" = "1" ]; then
    echo ""
    echo -e "${CYAN}--- App Store Connect API Key Konfiguration ---${NC}"
    echo "Woher bekommst du die Daten?"
    echo " 1. Gehe zu App Store Connect: https://appstoreconnect.apple.com/access/integrations/api"
    echo " 2. Unter 'Benutzer und Zugriff' -> Tab 'Integrationen' (oder 'Schlüssel') -> 'App Store Connect-API'."
    echo " 3. Klicke auf '+' um einen neuen Schlüssel zu erstellen (Rolle: 'Entwickler' oder 'App-Manager')."
    echo " 4. Lade die Datei 'AuthKey_XXXXXXXXXX.p8' herunter (Achtung: kann nur 1x heruntergeladen werden!)."
    echo " 5. Kopiere die 'Schlüssel-ID' (Key ID, z.B. 2X9R427ND4) und 'Aussteller-ID' (Issuer ID, UUID)."
    echo ""

    # API Key file / base64
    read -r -p "   Pfad zur AuthKey_XXXXXX.p8 Datei oder Base64-String: " RAW_KEY_INPUT
    KEY_INPUT=$(clean_input "$RAW_KEY_INPUT")
    RESOLVED_KEY_PATH=$(resolve_path "$KEY_INPUT")

    DETECTED_KEY_ID=""
    API_KEY_BASE64=""

    if [ -f "${RESOLVED_KEY_PATH}" ]; then
        echo "   -> Lese .p8-Datei ein und konvertiere nach Base64..."
        API_KEY_BASE64=$(base64 < "${RESOLVED_KEY_PATH}" | tr -d '\r\n')
        FILENAME=$(basename "${RESOLVED_KEY_PATH}")
        if [[ "${FILENAME}" =~ AuthKey_([A-Za-z0-9]+)\.p8 ]]; then
            DETECTED_KEY_ID="${BASH_REMATCH[1]}"
        fi
    elif [[ "${KEY_INPUT}" == *".p8"* ]] || [[ "${KEY_INPUT}" == *"/"* ]] || [[ "${KEY_INPUT}" == *"~"* ]]; then
        echo -e "${RED}[Fehler] API-Key-Datei (.p8) wurde nicht gefunden: ${RESOLVED_KEY_PATH}${NC}"
        exit 1
    elif [[ "${KEY_INPUT}" == *"BEGIN PRIVATE KEY"* ]]; then
        API_KEY_BASE64=$(printf '%s' "${KEY_INPUT}" | base64 | tr -d '\r\n')
    else
        API_KEY_BASE64="${KEY_INPUT//[[:space:]]/}"
    fi

    if [ -z "${API_KEY_BASE64}" ]; then
        echo -e "${RED}[Fehler] Kein API Key angegeben.${NC}"
        exit 1
    fi

    # Key ID
    if [ -n "${DETECTED_KEY_ID}" ]; then
        read -r -p "   Key ID (10 Zeichen) [Erkannt: ${DETECTED_KEY_ID}]: " KEY_ID
        KEY_ID="${KEY_ID:-$DETECTED_KEY_ID}"
    else
        read -r -p "   Key ID (10 Zeichen, z.B. 2X9R427ND4): " KEY_ID
    fi
    KEY_ID=$(clean_input "$KEY_ID")

    if [ -z "${KEY_ID}" ]; then
        echo -e "${RED}[Fehler] Keine Key ID angegeben.${NC}"
        exit 1
    fi

    if [[ ! "${KEY_ID}" =~ ^[A-Za-z0-9]{10}$ ]]; then
        echo -e "${YELLOW}[Warnung] Die Key ID hat üblicherweise genau 10 alphanumerische Zeichen (z.B. 2X9R427ND4). Eingegeben: '${KEY_ID}'${NC}"
    fi

    # Issuer ID
    read -r -p "   Issuer ID (UUID, z.B. 57246542-96fe-1a63-e053-0824d011072a): " ISSUER_ID
    ISSUER_ID=$(clean_input "$ISSUER_ID")

    if [ -z "${ISSUER_ID}" ]; then
        echo -e "${RED}[Fehler] Keine Issuer ID angegeben.${NC}"
        exit 1
    fi

    if [[ ! "${ISSUER_ID}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
        echo -e "${YELLOW}[Warnung] Die Issuer ID entspricht nicht dem typischen UUID-Format (z.B. 57246542-96fe-1a63-e053-0824d011072a).${NC}"
    fi

    # Setting Secrets
    echo ""
    echo -e "${YELLOW}Setze Secrets im GitHub Repository...${NC}"

    printf '%s' "${CERT_BASE64}" | gh secret set APPLE_CERTIFICATE_BASE64
    echo -e "${GREEN}✓ APPLE_CERTIFICATE_BASE64 gesetzt.${NC}"

    printf '%s' "${CERT_PASSWORD}" | gh secret set APPLE_CERTIFICATE_PASSWORD
    echo -e "${GREEN}✓ APPLE_CERTIFICATE_PASSWORD gesetzt.${NC}"

    printf '%s' "${API_KEY_BASE64}" | gh secret set APPLE_API_KEY_BASE64
    echo -e "${GREEN}✓ APPLE_API_KEY_BASE64 gesetzt.${NC}"

    printf '%s' "${KEY_ID}" | gh secret set APPLE_API_KEY_ID
    echo -e "${GREEN}✓ APPLE_API_KEY_ID gesetzt.${NC}"

    printf '%s' "${ISSUER_ID}" | gh secret set APPLE_API_ISSUER
    echo -e "${GREEN}✓ APPLE_API_ISSUER gesetzt.${NC}"

else
    echo ""
    echo -e "${CYAN}--- Apple ID & App-spezifisches Passwort (Legacy) ---${NC}"

    # Apple ID Email
    read -r -p "   Apple ID (E-Mail): " RAW_APPLE_ID
    APPLE_ID=$(clean_input "$RAW_APPLE_ID")

    if [[ ! "${APPLE_ID}" == *"@"* ]]; then
        echo -e "${YELLOW}[Warnung] Die Apple ID sollte eine gültige E-Mail-Adresse sein.${NC}"
    fi

    # Team ID
    echo "   Woher: https://developer.apple.com/account -> 'Membership details' -> Team ID"
    read -r -p "   Apple Team ID (10 Zeichen): " RAW_TEAM_ID
    TEAM_ID=$(clean_input "$RAW_TEAM_ID")

    if [[ ! "${TEAM_ID}" =~ ^[A-Za-z0-9]{10}$ ]]; then
        echo -e "${YELLOW}[Warnung] Die Team ID hat üblicherweise genau 10 alphanumerische Zeichen.${NC}"
    fi

    # App-Specific Password
    echo "   Woher: https://appleid.apple.com -> 'Anmelden und Sicherheit' ->"
    echo "   'App-spezifische Passwörter' -> Neues Passwort erstellen."
    read -r -s -p "   App-spezifisches Passwort (Format: xxxx-xxxx-xxxx-xxxx): " RAW_APP_SPECIFIC_PW
    echo ""
    APP_SPECIFIC_PW=$(clean_input "$RAW_APP_SPECIFIC_PW")

    # Setting Secrets
    echo ""
    echo -e "${YELLOW}Setze Secrets im GitHub Repository...${NC}"

    printf '%s' "${CERT_BASE64}" | gh secret set APPLE_CERTIFICATE_BASE64
    echo -e "${GREEN}✓ APPLE_CERTIFICATE_BASE64 gesetzt.${NC}"

    printf '%s' "${CERT_PASSWORD}" | gh secret set APPLE_CERTIFICATE_PASSWORD
    echo -e "${GREEN}✓ APPLE_CERTIFICATE_PASSWORD gesetzt.${NC}"

    printf '%s' "${APPLE_ID}" | gh secret set APPLE_ID
    echo -e "${GREEN}✓ APPLE_ID gesetzt.${NC}"

    printf '%s' "${TEAM_ID}" | gh secret set APPLE_TEAM_ID
    echo -e "${GREEN}✓ APPLE_TEAM_ID gesetzt.${NC}"

    printf '%s' "${APP_SPECIFIC_PW}" | gh secret set APPLE_APP_SPECIFIC_PASSWORD
    echo -e "${GREEN}✓ APPLE_APP_SPECIFIC_PASSWORD gesetzt.${NC}"
fi

echo ""
echo -e "${BOLD}${GREEN}====================================================${NC}"
echo -e "${BOLD}${GREEN}   Alle Secrets wurden erfolgreich hinterlegt!      ${NC}"
echo -e "${BOLD}${GREEN}====================================================${NC}"
echo ""
echo "Aktuelle Secrets in diesem Repository:"
gh secret list
echo ""
echo "Wenn du einen neuen Release erstellen möchtest:"
echo "  git tag v1.0.1"
echo "  git push origin v1.0.1"
echo "Die GitHub Action baut, signiert und notarisiert das Release automatisch!"
