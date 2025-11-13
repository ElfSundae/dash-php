#!/usr/bin/env bash

[[ "${_COMMON_SH_LOADED:-}" == 1 ]] && return
_COMMON_SH_LOADED=1

# Define colors for output messages
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m" # No Color

# Determine sed in-place editing option for macOS or Linux
if [[ "$(uname)" == "Darwin" ]]; then
    SED_INPLACE=(-i '')
else
    SED_INPLACE=(-i)
fi

# Supported languages: https://github.com/php/web-php/blob/master/src/I18n/Languages.php
# You may run the following command to get the latest language codes:
# `tmp=$(mktemp) && curl -fsSL 'https://raw.githubusercontent.com/php/web-php/master/src/I18n/Languages.php' -o "$tmp" && php -r 'require '"'$tmp'"'; echo implode(" ", array_keys(\phpweb\I18n\Languages::ACTIVE_ONLINE_LANGUAGES)).PHP_EOL;' && rm -f "$tmp"`
LANG_CODES=(en de es fr it ja pt_BR ru tr uk zh)
LANG_LOCAL_NAMES=(
    "English" "Deutsch" "Español" "Français" "Italiano" "日本語"
    "Português Brasileiro" "Русский" "Türkçe" "Українська" "简体中文"
)
LANG_EN_NAMES=(
    "English" "German" "Spanish" "French" "Italian" "Japanese"
    "Brazilian Portuguese" "Russian" "Turkish" "Ukrainian" "Simplified Chinese"
)

msg_main() {
    echo -e "${GREEN}➤ $*${NC}"
}

msg_sub() {
    echo -e "    $*"
}

msg_done() {
    echo -e "${GREEN}✔ $*${NC}"
}

msg_error() {
    echo -e "${RED}❌ $*${NC}" >&2
}

# Check if required commands are available: $commands...
require_command() {
    local cmd
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || { msg_error "Missing command: $cmd"; exit 1; }
    done
}

# Normalize the language code to a standard format (e.g., "en_us" to "en_US"): $code
normalize_lang_code() {
    local code="$1"
    local lang region

    if [[ "$code" == *_* ]]; then
        lang="${code%%_*}"
        region="${code##*_}"
        echo "$(tr '[:upper:]' '[:lower:]' <<<"$lang")_$(tr '[:lower:]' '[:upper:]' <<<"$region")"
    else
        echo "$(tr '[:upper:]' '[:lower:]' <<<"$code")"
    fi
}

# Get the language name by code from a specified array: $code, $array_name
_get_lang_name() {
    local code="$1"
    local array_name="$2"
    local i

    for i in "${!LANG_CODES[@]}"; do
        if [[ "${LANG_CODES[$i]}" == "$code" ]]; then
            eval "echo \${${array_name}[$i]}"
            return 0
        fi
    done
    return 1
}

# Get the local (native) name of the language: $code
get_lang_local_name() {
    _get_lang_name "$1" "LANG_LOCAL_NAMES"
}

# Get the English name of a language: $code
get_lang_en_name() {
    _get_lang_name "$1" "LANG_EN_NAMES"
}

# Obtain the version of the Dash docset: $docset_path
# Return empty string if failed, otherwise the version.
get_docset_version() {
    local docset="$1"
    local phpver hash

    # Get the latest migration file
    local migration
    migration=$(
        {
            find "$docset/Contents/Resources/Documents" \
                -maxdepth 1 -type f -name 'migration*.html' \
                | grep -E '/migration[0-9]+\.html$' \
                | sort --version-sort \
                | tail -n 1
        } 2>/dev/null || true
    )
    [[ -n "$migration" ]] || { echo ""; return 0; }

    # Get the PHP version for the doc
    phpver=$(sed -E -n 's/.*PHP ([0-9]+\.[0-9]+)(\.x)?[^<]*<\/title>/\1/p' "$migration" 2>/dev/null || true)
    [[ -n "$phpver" ]] || { echo ""; return 0; }

    # Calc the files hash
    # The regex matches `uniqid()`.html files, like `PHP_es.docset/Contents/Resources/Documents/68fca58a0edb6.html`
    hash=$(
        (
            cd "$docset"
            find . -type f ! -name '.DS_Store' ! -name '*.dsidx' -print0 \
                | grep -zEv '/[0-9a-f]{13}\.html$' \
                | LC_ALL=C sort -z | xargs -0 md5sum | md5sum | cut -c1-6
        ) 2>/dev/null || true
    )
    [[ -n "$hash" ]] || { echo ""; return 0; }

    echo "/${phpver}_${hash}"
}

# Obtain the CFBundleName of the Dash docset: $docset_path
# Return empty string if failed, otherwise the bundle name.
get_docset_bundle_name() {
    local docset="$1"
    xmllint --xpath 'string(/plist/dict/key[.="CFBundleName"]/following-sibling::string[1])' \
        "$docset/Contents/Info.plist" 2>/dev/null || {
        echo ""
        return 0
    }
}
