#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# One-time setup of everything the release workflow needs (interactive, on your own Mac):
#
#   tools/setup_release_secrets.sh
#
# Steps:
#   1. Target: GitHub environment "release" (recommended: required approval, only tags v* and
#      the branch main may use it) or repository secrets.
#   2. "Developer ID Application" certificate + private key as .p12: exported from the login
#      keychain (macOS asks once per private key for your login password → "Allow") or from a
#      .p12 you exported yourself; reduced to exactly this identity, new password.
#   3. App Store Connect API key (.p8) for notarization: found automatically in the usual
#      places (~/Downloads, ~/.appstoreconnect/private_keys, ~/private_keys, ~/.private_keys,
#      current directory) or asked for; key ID from the file name, issuer ID asked; checked
#      against Apple (notarytool history).
#   4. Optional (ENABLE_SPARKLE=1): Sparkle EdDSA key pair in the login keychain (own account
#      per app), created if missing; private key → secret, public key → variable.
#   5. Secrets via `gh secret set` (stdin), variable via `gh variable set`.
#   6. Optional: GitHub Pages on branch gh-pages (update feed and/or homepage).
#   7. Optional (HOMEBREW_TAP_REPO set): SSH deploy key with write access to the tap repository
#      (created if missing) → secret HOMEBREW_TAP_DEPLOY_KEY. Never expires, valid for that repo only.
#   8. Temporary files are removed (also on Ctrl-C).
#
# Secrets: MACOS_CERT_P12_BASE64, MACOS_CERT_PASSWORD, NOTARY_API_KEY_P8_BASE64,
# NOTARY_API_KEY_ID, NOTARY_API_ISSUER_ID [, SPARKLE_ED_PRIVATE_KEY] [, HOMEBREW_TAP_DEPLOY_KEY]
# Variable: [SPARKLE_PUBLIC_ED_KEY]
#
# Requirements: gh (logged in, admin rights on the repository), a "Developer ID Application"
# certificate in the login keychain, Xcode or the Command Line Tools.
# No value ever reaches the repository, the shell history, a command line or the output.
set -euo pipefail

# ---- Configuration (filled in by the agent for this project) -----------------------
APP_SLUG=${APP_SLUG:-altswitch}
ENABLE_SPARKLE=${ENABLE_SPARKLE:-0}
HOMEBREW_TAP_REPO=${HOMEBREW_TAP_REPO:-brokoskokoli/homebrew-tap}
ENV_NAME=${RELEASE_ENV:-release}
REPO=${RELEASE_REPO:-}                            # default: the repository of the current directory
IDENTITY=${SIGN_IDENTITY:-}
SPARKLE_BIN=${SPARKLE_BIN:-third_party/Sparkle/bin}

LOGIN_KC="$HOME/Library/Keychains/login.keychain-db"
# The system's LibreSSL reads the PKCS#12 of `security export` and writes one that
# `security import` on the runner accepts (3DES/SHA1; OpenSSL 3 defaults to AES, which fails).
OPENSSL=/usr/bin/openssl
SECRET_SCOPE=()
WORK=

cleanup() {
  if [[ -n "$WORK" && -d "$WORK" ]]; then
    find "$WORK" -type f -exec sh -c 'for f; do
      dd if=/dev/urandom of="$f" bs=1k count="$(( ($(stat -f %z "$f") + 1023) / 1024 ))" conv=notrunc 2>/dev/null
    done' sh {} + 2>/dev/null || true
    rm -rf "$WORK"
  fi
}
say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
ask() { local p=$1 d=${2:-}; [[ -n "$d" ]] && p="$p [$d]"; read -r -p "$p: " REPLY; REPLY=${REPLY:-$d}; }
confirm() {
  local d=${2:-n} h="[y/N]"; [[ "$d" == y ]] && h="[Y/n]"
  read -r -p "$1 $h " REPLY; REPLY=${REPLY:-$d}; [[ "$REPLY" =~ ^[yYjJ] ]]
}
ask_secret() { # ask_secret prompt [min] → REPLY (entered twice, hidden)
  local a b min=${2:-1}
  while true; do
    read -r -s -p "$1: " a; echo
    if (( ${#a} < min )); then say "At least $min characters."; continue; fi
    read -r -s -p "Repeat: " b; echo
    [[ "$a" == "$b" ]] && { REPLY=$a; return 0; }
    say "Does not match, again."
  done
}

# ---- PKCS#12 helpers ----------------------------------------------------------------
# Splits the PEM output of `openssl pkcs12 -nodes` (stdin) into blocks:
#   mode=list  localKeyID of every identity named $id (certificate with a matching key)
#   mode=pair  key + certificate with localKeyID $want      mode=cert  only the certificate
# shellcheck disable=SC2016
P12_AWK='
  /^Bag Attributes/ { lkid = ""; fname = ""; subj = ""; next }
  /^[[:space:]]+localKeyID:/ { sub(/^[[:space:]]+localKeyID:[[:space:]]*/, ""); lkid = $0; next }
  /^[[:space:]]+friendlyName:/ { sub(/^[[:space:]]+friendlyName:[[:space:]]*/, ""); fname = $0; next }
  /^subject=/ { subj = $0; next }
  /^-----BEGIN / { inpem = 1; type = ($0 ~ /CERTIFICATE/) ? "cert" : "key"; pem = $0 "\n"; next }
  inpem { pem = pem $0 "\n"
          if ($0 ~ /^-----END /) { inpem = 0; n++; T[n] = type; L[n] = lkid; F[n] = fname; S[n] = subj; P[n] = pem }
          next }
  function named(i) { return id == "" || F[i] == id || index(S[i], "CN=" id "/") || index(S[i], "CN = " id ",") || S[i] ~ ("CN ?= ?" id "$") }
  END {
    for (i = 1; i <= n; i++) if (T[i] == "key" && L[i] != "") K[L[i]] = i
    for (i = 1; i <= n; i++) {
      if (T[i] != "cert" || L[i] == "" || !(L[i] in K) || !named(i)) continue
      if (mode == "list") print L[i]
      else if (L[i] == want) { if (mode == "pair") printf "%s", P[K[L[i]]]; printf "%s", P[i]; exit 0 }
    }
  }'
p12_dump() { IN_PASS=$2 "$OPENSSL" pkcs12 -in "$1" -nodes -passin env:IN_PASS 2>/dev/null; }
not_after_epoch() {
  local d; d=$("$OPENSSL" x509 -noout -enddate | cut -d= -f2 | tr -s ' ')
  LC_ALL=C date -j -u -f '%b %d %T %Y GMT' "$d" +%s
}
# extract_identity <in.p12> <in-pass> <identity> <out.p12> <out-pass> [chain.pem]
# Exactly one identity (the valid one with the latest expiry) → new PKCS#12.
# Returns 0 ok, 1 error, 3 identity missing, 5 all expired. Keys stay in pipes only.
extract_identity() {
  local in=$1 in_pass=$2 identity=$3 out=$4 out_pass=$5 chain=${6:-}
  local certfile=() lkids lkid pem end best="" best_end=0
  [[ -n "$chain" && -s "$chain" ]] && certfile=(-certfile "$chain")
  IN_PASS=$in_pass "$OPENSSL" pkcs12 -in "$in" -nokeys -passin env:IN_PASS >/dev/null 2>&1 || return 1
  lkids=$(p12_dump "$in" "$in_pass" | awk -v mode=list -v id="$identity" "$P12_AWK")
  [[ -n "$lkids" ]] || return 3
  while IFS= read -r lkid; do
    pem=$(p12_dump "$in" "$in_pass" | awk -v mode=cert -v want="$lkid" -v id="$identity" "$P12_AWK")
    "$OPENSSL" x509 -noout -checkend 0 <<<"$pem" >/dev/null 2>&1 || continue
    end=$(not_after_epoch <<<"$pem") || continue
    if (( end > best_end )); then best=$lkid; best_end=$end; fi
  done <<<"$lkids"
  [[ -n "$best" ]] || return 5
  p12_dump "$in" "$in_pass" | awk -v mode=pair -v want="$best" -v id="$identity" "$P12_AWK" \
    | OUT_PASS=$out_pass "$OPENSSL" pkcs12 -export -name "$identity" ${certfile[@]+"${certfile[@]}"} \
        -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 -passout env:OUT_PASS -out "$out" 2>/dev/null \
    || { rm -f "$out"; return 1; }
}
verify_p12() { # identity present, key matches certificate, not expired
  local p12=$1 pass=$2 identity=$3 cert subj pub_cert pub_key
  cert=$(P=$pass "$OPENSSL" pkcs12 -in "$p12" -nokeys -clcerts -passin env:P 2>/dev/null) \
    || { say "  Cannot open the .p12 with this password."; return 1; }
  # utf8: names with umlauts etc. are printed as text, not as \xC3\xBC escapes.
  subj=$("$OPENSSL" x509 -noout -subject -nameopt utf8,sep_comma_plus <<<"$cert")
  [[ "$subj" == *"$identity"* ]] || { say "  Certificate is not \"$identity\" ($subj)."; return 1; }
  "$OPENSSL" x509 -noout -checkend 0 <<<"$cert" >/dev/null || { say "  Certificate expired."; return 1; }
  pub_cert=$("$OPENSSL" x509 -noout -pubkey <<<"$cert")
  pub_key=$(P=$pass "$OPENSSL" pkcs12 -in "$p12" -nocerts -nodes -passin env:P 2>/dev/null | "$OPENSSL" pkey -pubout 2>/dev/null) || true
  [[ -n "$pub_key" && "$pub_cert" == "$pub_key" ]] || { say "  No matching private key in the .p12."; return 1; }
  say "  OK: $subj, valid until $("$OPENSSL" x509 -noout -enddate <<<"$cert" | cut -d= -f2)"
}

# ---- Steps ----------------------------------------------------------------------------
step_target() {
  command -v gh >/dev/null || die "gh (GitHub CLI) missing: brew install gh"
  gh auth status >/dev/null 2>&1 || die "gh is not logged in: gh auth login"
  [[ -n "$REPO" ]] || REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)
  ask "Repository (owner/name)" "$REPO"; REPO=$REPLY
  [[ "$REPO" == */* ]] || die "Repository must be owner/name"
  local private def=y
  private=$(gh api "repos/$REPO" --jq .private 2>/dev/null) || die "Repository $REPO not found or no access."
  say ""
  say "Secrets in the environment \"$ENV_NAME\" are only visible to jobs that use it and can"
  say "require your approval before every release run (recommended)."
  if [[ "$private" == true ]]; then
    say "Note: $REPO is PRIVATE. On GitHub Free/Pro/Team, environment secrets and required reviewers"
    say "work only in public repositories (private: Enterprise). Without them choose \"n\" (repository secrets)."
    def=n
  fi
  if confirm "Store the secrets in the environment \"$ENV_NAME\"?" "$def"; then
    SECRET_SCOPE=(--env "$ENV_NAME")
    if ! gh api "repos/$REPO/environments/$ENV_NAME" >/dev/null 2>&1; then
      gh api -X PUT "repos/$REPO/environments/$ENV_NAME" >/dev/null
      say "  Environment created."
    fi
    step_protection
  fi
}

step_protection() {
  say ""
  say "Protection: every release run waits for your approval; only tags v* and the branch main"
  say "(dry run) may use the environment."
  confirm "Set this up now?" y || return 0
  local current uid existing ok=1 pol branch_policy
  current=$(gh api "repos/$REPO/environments/$ENV_NAME" --jq '[(.protection_rules // [])[] | .type] | join(", ")' 2>/dev/null || true)
  if [[ -n "$current" ]]; then
    say "warning: the environment already has protection rules ($current); they will be replaced."
    confirm "Replace them?" n || { say "  Left unchanged."; return 0; }
  fi
  # 1) Branch/tag rules first: create the policies, and only switch to "selected branches and
  #    tags" once both exist - an empty custom list would block every deployment.
  if printf '{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}' \
       | gh api -X PUT "repos/$REPO/environments/$ENV_NAME" --input - >/dev/null; then
    existing=$(gh api "repos/$REPO/environments/$ENV_NAME/deployment-branch-policies" --jq '.branch_policies[] | "\(.type):\(.name)"' 2>/dev/null || true)
    for pol in 'tag:v*' 'branch:main'; do
      grep -qxF "$pol" <<<"$existing" && continue
      gh api -X POST "repos/$REPO/environments/$ENV_NAME/deployment-branch-policies" \
        -f name="${pol#*:}" -f type="${pol%%:*}" >/dev/null || ok=0
    done
    if [[ $ok == 0 ]]; then
      say "warning: could not add the tag/branch rules - leaving the environment unrestricted."
      ok=0
    else
      say "  Tag/branch rules set (v*, main)."
    fi
  else
    say "warning: could not set tag/branch rules; set them under Settings → Environments → $ENV_NAME."
    ok=0
  fi
  if [[ $ok == 1 ]]; then
    branch_policy='{"protected_branches":false,"custom_branch_policies":true}'
  else
    branch_policy=null
  fi
  # 2) Required reviewer (you). A PUT sets every protection field, so it repeats the branch policy.
  uid=$(gh api user --jq .id)
  if printf '{"reviewers":[{"type":"User","id":%s}],"prevent_self_review":false,"deployment_branch_policy":%s}' "$uid" "$branch_policy" \
       | gh api -X PUT "repos/$REPO/environments/$ENV_NAME" --input - >/dev/null; then
    say "  Required approval set (you)."
  else
    say "warning: required reviewers not available (private repository without Enterprise?)."
    printf '{"deployment_branch_policy":%s}' "$branch_policy" \
      | gh api -X PUT "repos/$REPO/environments/$ENV_NAME" --input - >/dev/null || true
  fi
}

choose_identity() {
  [[ -n "$IDENTITY" ]] && return 0
  local found=() line i
  while IFS= read -r line; do [[ -n "$line" ]] && found+=("$line"); done < <(
    security find-identity -v -p codesigning 2>/dev/null | sed -nE 's/.*"(Developer ID Application: [^"]+)".*/\1/p' | sort -u)
  if (( ${#found[@]} == 0 )); then
    die "No valid \"Developer ID Application\" identity in the keychain. Create it at developer.apple.com → Certificates (account holder only), double-click the .cer, run again."
  elif (( ${#found[@]} == 1 )); then
    IDENTITY=${found[0]}
  else
    say "Several Developer ID identities:"
    for i in "${!found[@]}"; do say "  $((i + 1))) ${found[$i]}"; done
    ask "Number" 1
    [[ "$REPLY" =~ ^[1-9][0-9]*$ ]] && (( REPLY <= ${#found[@]} )) || die "Invalid choice: $REPLY"
    IDENTITY=${found[$((REPLY - 1))]}
  fi
  [[ "$IDENTITY" == "Developer ID Application: "* ]] || die "Not a Developer ID identity: $IDENTITY"
}

step_certificate() {
  choose_identity
  say ""; say "== Certificate: $IDENTITY"
  say "New password for the .p12 (stored as MACOS_CERT_PASSWORD; random, from your password manager, no line breaks):"
  ask_secret "Password" 12; P12_PASS=$REPLY
  P12="$WORK/developer-id.p12"
  local chain="$WORK/chain.pem" rc=0
  security find-certificate -a -c "Developer ID Certification Authority" -p \
    /Library/Keychains/System.keychain "$LOGIN_KC" > "$chain" 2>/dev/null || true
  say "  a) export automatically from the login keychain (macOS asks per private key → Allow)"
  say "  b) use a .p12 you exported in Keychain Access (My Certificates → right-click → Export)"
  ask "Way" a
  if [[ "$REPLY" == a ]]; then
    # The only password on a command line: a random one-time password for this temporary
    # export (0700 directory, deleted right after); `security export` has no stdin option.
    local all="$WORK/all.p12" tmp_pass; tmp_pass=$("$OPENSSL" rand -hex 24)
    security export -k "$LOGIN_KC" -t identities -f pkcs12 -P "$tmp_pass" -o "$all" \
      || die "security export failed - run again and choose b)."
    extract_identity "$all" "$tmp_pass" "$IDENTITY" "$P12" "$P12_PASS" "$chain" || rc=$?
    rm -f "$all"
  else
    ask "Path to the .p12"; local src=${REPLY/#\~/$HOME} src_pass
    [[ -f "$src" ]] || die "Not found: $src"
    read -r -s -p "Password of this .p12: " src_pass; echo
    extract_identity "$src" "$src_pass" "$IDENTITY" "$P12" "$P12_PASS" "$chain" || rc=$?
    unset src_pass
  fi
  case $rc in
    0) ;; 5) die "Every certificate \"$IDENTITY\" has expired - create a new one." ;;
    *) die "Identity \"$IDENTITY\" with its private key not found (or wrong password)." ;;
  esac
  verify_p12 "$P12" "$P12_PASS" "$IDENTITY" || die ".p12 invalid."
}

step_api_key() {
  say ""; say "== App Store Connect API key (notarization)"
  local cands=() d f
  for d in "$HOME/Downloads" "$HOME/.appstoreconnect/private_keys" "$HOME/private_keys" "$HOME/.private_keys" "$PWD"; do
    for f in "$d"/AuthKey_*.p8; do [[ -f "$f" ]] && cands+=("$f"); done
  done
  if (( ${#cands[@]} == 1 )); then
    P8=${cands[0]}; say "  Found: $P8"
    confirm "Use it?" y || P8=
  elif (( ${#cands[@]} > 1 )); then
    for f in "${!cands[@]}"; do say "  $((f + 1))) ${cands[$f]}"; done
    ask "Number (empty = enter a path)"
    P8=
    if [[ -n "$REPLY" ]]; then
      [[ "$REPLY" =~ ^[1-9][0-9]*$ ]] && (( REPLY <= ${#cands[@]} )) || die "Invalid choice: $REPLY"
      P8=${cands[$((REPLY - 1))]}
    fi
  fi
  if [[ -z "${P8:-}" ]]; then
    say "  App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys,"
    say "  role Developer; the .p8 can be downloaded only once."
    ask "Path to AuthKey_XXXXXXXXXX.p8"; P8=${REPLY/#\~/$HOME}
  fi
  [[ -f "$P8" ]] || die "Not found: $P8"
  grep -q -- '-----BEGIN PRIVATE KEY-----' "$P8" || die "$P8 is not a .p8 key."
  local guess=; [[ "$(basename "$P8")" =~ ^AuthKey_([A-Z0-9]{10})\.p8$ ]] && guess=${BASH_REMATCH[1]}
  while true; do ask "Key ID" "$guess"; KEY_ID=$REPLY; [[ "$KEY_ID" =~ ^[A-Z0-9]{10}$ ]] && break; say "10 characters A-Z/0-9."; done
  while true; do
    ask "Issuer ID (UUID above the key list)"; ISSUER_ID=$REPLY
    [[ "$ISSUER_ID" =~ ^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$ ]] && break; say "A UUID (8-4-4-4-12)."
  done
  xcrun notarytool history --key "$P8" --key-id "$KEY_ID" --issuer "$ISSUER_ID" >/dev/null \
    || die "Apple does not accept this API key (key ID, issuer ID, role?)."
  say "  API key works."
}

step_sparkle() {
  [[ "$ENABLE_SPARKLE" == 1 ]] || return 0
  say ""; say "== Sparkle key pair (keychain account \"$APP_SLUG\")"
  local gk="$SPARKLE_BIN/generate_keys"
  if [[ ! -x "$gk" ]]; then
    [[ -x tools/fetch_sparkle.sh ]] || die "$gk missing and no tools/fetch_sparkle.sh"
    tools/fetch_sparkle.sh >/dev/null
  fi
  if SPARKLE_PUB=$("$gk" --account "$APP_SLUG" -p 2>/dev/null) && [[ -n "$SPARKLE_PUB" ]]; then
    say "  Existing pair found (public key $SPARKLE_PUB). Never create a new one: installed copies trust only this key."
  else
    say "  No pair yet. It is created now and stored in the login keychain."
    say "  IMPORTANT: losing the private key means no more updates for installed copies - back it up."
    confirm "Create?" y || die "Aborted."
    "$gk" --account "$APP_SLUG" >/dev/null
    SPARKLE_PUB=$("$gk" --account "$APP_SLUG" -p)
    say "  Created: public key $SPARKLE_PUB"
  fi
  SPARKLE_KEY="$WORK/sparkle_private.key"
  "$gk" --account "$APP_SLUG" -x "$SPARKLE_KEY" >/dev/null || die "Export failed."
  if [[ -x tools/sparkle_key_check.sh ]] && tools/sparkle_key_check.sh --print-public "$SPARKLE_KEY" >/dev/null 2>&1; then
    tools/sparkle_key_check.sh "$SPARKLE_KEY" "$SPARKLE_PUB" >/dev/null || die "Sparkle keys do not match."
    say "  Key pair matches."
  fi
  say "  Backup: \"$gk --account $APP_SLUG -x <file>\" → store the file in your password manager."
}

set_secret() { gh secret set "$1" --repo "$REPO" ${SECRET_SCOPE[@]+"${SECRET_SCOPE[@]}"} >/dev/null; say "  $1 set"; }

step_set_secrets() {
  say ""; say "== Setting secrets in $REPO ${SECRET_SCOPE[*]:-(repository)}"
  confirm "Set now (existing values are overwritten)?" y || die "Aborted, nothing set."
  base64 -i "$P12" | tr -d '\n' | set_secret MACOS_CERT_P12_BASE64
  printf '%s' "$P12_PASS" | set_secret MACOS_CERT_PASSWORD
  base64 -i "$P8" | tr -d '\n' | set_secret NOTARY_API_KEY_P8_BASE64
  printf '%s' "$KEY_ID" | set_secret NOTARY_API_KEY_ID
  printf '%s' "$ISSUER_ID" | set_secret NOTARY_API_ISSUER_ID
  if [[ "$ENABLE_SPARKLE" == 1 ]]; then
    tr -d '\n' < "$SPARKLE_KEY" | set_secret SPARKLE_ED_PRIVATE_KEY
    gh variable set SPARKLE_PUBLIC_ED_KEY --repo "$REPO" --body "$SPARKLE_PUB" >/dev/null
    say "  SPARKLE_PUBLIC_ED_KEY (variable) set"
  fi
}

step_pages() {
  say ""; say "== GitHub Pages (branch gh-pages: update feed / homepage)"
  local src; src=$(gh api "repos/$REPO/pages" --jq '"\(.source.branch) \(.source.path)"' 2>/dev/null || true)
  if [[ "$src" == "gh-pages /" ]]; then say "  Already on (gh-pages, /)."; return 0; fi
  if [[ -n "$src" ]]; then
    say "warning: Pages uses \"$src\"."
    confirm "Switch to gh-pages, / ?" n || return 0
    if gh api -X PUT "repos/$REPO/pages" -f 'source[branch]=gh-pages' -f 'source[path]=/' >/dev/null; then
      say "  Switched."
    else
      say "warning: switching failed; Settings → Pages."
    fi
    return 0
  fi
  if ! gh api "repos/$REPO/branches/gh-pages" >/dev/null 2>&1; then
    confirm "Branch gh-pages does not exist. Create it (empty, only .nojekyll) and enable Pages?" y || return 0
    local tmp="$WORK/pages"; git init -q -b gh-pages "$tmp"; touch "$tmp/.nojekyll"
    git -C "$tmp" add .nojekyll
    git -C "$tmp" -c user.name="github-actions[bot]" -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
      commit -q -m "Initialize GitHub Pages"
    # Push with gh's credentials (no token in the URL or the git config).
    git -C "$tmp" -c credential.helper= -c 'credential.helper=!gh auth git-credential' \
      push -q "https://github.com/$REPO.git" gh-pages \
      || { say "warning: push failed; the first release creates the branch."; return 0; }
  else
    confirm "Enable Pages (gh-pages, /)?" y || return 0
  fi
  if gh api -X POST "repos/$REPO/pages" -f 'source[branch]=gh-pages' -f 'source[path]=/' >/dev/null; then
    say "  Enabled: https://${REPO%%/*}.github.io/${REPO#*/}/"
  else
    say "warning: enabling failed; Settings → Pages."
  fi
}

step_tap() {
  [[ -n "$HOMEBREW_TAP_REPO" ]] || return 0
  say ""; say "== Homebrew tap $HOMEBREW_TAP_REPO (deploy key)"
  if ! gh api "repos/$HOMEBREW_TAP_REPO" >/dev/null 2>&1; then
    confirm "Tap repository does not exist. Create it (public)?" y || return 0
    gh repo create "$HOMEBREW_TAP_REPO" --public --add-readme --description "Homebrew tap" >/dev/null
  fi
  confirm "Create a deploy key with write access for the release workflow?" y || return 0
  local kd="$WORK/tapkey" title="${APP_SLUG} release workflow" id
  mkdir -m 700 "$kd"
  ssh-keygen -q -t ed25519 -N "" -C "$title" -f "$kd/key"
  for id in $(gh api "repos/$HOMEBREW_TAP_REPO/keys" --jq ".[] | select(.title == \"$title\") | .id" 2>/dev/null); do
    gh api -X DELETE "repos/$HOMEBREW_TAP_REPO/keys/$id" >/dev/null
  done
  gh repo deploy-key add "$kd/key.pub" --repo "$HOMEBREW_TAP_REPO" --title "$title" --allow-write >/dev/null \
    || die "Could not add the deploy key (admin rights on $HOMEBREW_TAP_REPO?)."
  set_secret HOMEBREW_TAP_DEPLOY_KEY < "$kd/key"
}

main() {
  case "${1:-}" in "") ;; -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; return 0 ;; *) die "Unknown option $1" ;; esac
  [[ "$(uname -s)" == Darwin ]] || die "macOS only (keychain)."
  [[ -t 0 ]] || die "Interactive script: run it in a terminal."
  cd "$(dirname "$0")/.."
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/release-secrets.XXXXXX"); chmod 700 "$WORK"
  trap cleanup EXIT; trap 'exit 130' INT TERM
  step_target
  step_certificate
  step_api_key
  step_sparkle
  step_set_secrets
  unset P12_PASS
  step_pages
  step_tap
  cat <<MSG

Done. Next:
  - Dry run (builds, signs, notarizes, publishes nothing): gh workflow run release.yml --repo $REPO --ref main
  - Release: set the version, add the CHANGELOG section, commit, then git tag vX.Y.Z && git push origin vX.Y.Z
  - Keep the .p8 offline (Apple offers it only once) or delete it.
MSG
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
