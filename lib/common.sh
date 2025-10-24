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
LANG_NAMES=(
    "English" "Deutsch" "Español" "Français" "Italiano" "日本語"
    "Português Brasil" "Русский" "Türkçe" "Українська" "简体中文"
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

# Get the language name from the language code: $code
get_lang_name() {
    local code="$1"
    local i
    for i in "${!LANG_CODES[@]}"; do
        if [[ "${LANG_CODES[$i]}" == "$code" ]]; then
            echo "${LANG_NAMES[$i]}"
            return 0
        fi
    done
    return 1
}

# Obtain the version of the Dash docset: $docset_path
# Return empty string if failed, otherwise the version.
get_docset_version() {
    local docset="$1"

    local pubdate; pubdate=$(xmllint --html --xpath 'string(//div[@class="pubdate"][1])' \
        "$docset/Contents/Resources/Documents/index.html" 2>/dev/null | xargs)
    [[ -n "$pubdate" ]] || { echo ""; return 0; }

    local indexes; indexes=$(sqlite3 -noheader "$docset/Contents/Resources/docSet.dsidx" \
        'SELECT COUNT(*) FROM searchIndex;' 2>/dev/null)
    [[ -n "$indexes" ]] || { echo ""; return 0; }

    local hash; hash=$(
        cd "$docset" 2>/dev/null || { echo ""; exit 0; }
        find . -type f ! -name '.DS_Store' ! -name '*.dsidx' \
            -print0 | LC_ALL=C sort -z | xargs -0 md5sum | md5sum | cut -c1-6
    )
    [[ -n "$hash" ]] || { echo ""; return 0; }

    echo "/${pubdate}_${indexes}_${hash}"
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
