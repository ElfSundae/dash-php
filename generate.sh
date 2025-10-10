#!/usr/bin/env bash
set -euo pipefail

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

# Supported languages: https://github.com/php/doc-en?tab=readme-ov-file#translations
LANG_CODES=(
    "pt_br" "zh" "en" "fr" "de" "it"
    "ja" "pl" "ro" "ru" "es" "tr" "uk"
)
LANG_NAMES=(
    "Português Brasil" "简体中文" "English" "Français" "Deutsch" "Italiano"
    "日本語" "Polski" "Română" "Русский" "Español" "Türkçe" "Українська"
)

# The root directory of this script
ROOT="$(cd "$(dirname "$0")" && pwd)"
# The output directory for generated docsets
OUTPUT="$ROOT/output"

# The root directory of the PHP doc repositories
PHPDOC="$ROOT/phpdoc"
# The build output directory for phpdoc
PHPDOC_BUILD="$PHPDOC/build"

# The language to generate
lang="en"
# Whether to create a php.net mirror during generation
mirror=false

# Print script usage information
usage() {
    cat <<EOF
Generate Dash docset for the PHP Manual in multiple languages.

Usage: $(basename "$0") [LANG] [OPTIONS]

Arguments:
  LANG      Language code for the PHP Manual to generate, defaults to '${lang}'.
            Supported languages: ${LANG_CODES[*]}

Options:
  --mirror          Create a php.net mirror during generation.
  help, -h, --help  Display this help message.
EOF
}

# Clone or pull a git repository: $repo [$path]
clone_or_pull() {
    (
        cd "$PHPDOC"

        local repo="$1"
        local path="${2:-$(basename "$repo" .git)}"

        if [ -d "$path" ]; then
            git -C "$path" clean -dxfq
            git -C "$path" reset --hard
            git -C "$path" pull
        else
            git clone "$repo" "$path"
        fi
    )
}

# Fetch or update the required git repositories
fetch_repos() {
    clone_or_pull "https://github.com/php/doc-base.git"
    clone_or_pull "https://github.com/php/doc-en.git" en
    clone_or_pull "https://github.com/php/phd.git"
    clone_or_pull "https://github.com/php/web-php.git"

    if [[ "$lang" != "en" ]]; then
        clone_or_pull "https://github.com/php/doc-${lang}.git" "$lang"
    fi
}

# Generate the Docbook XML file: doc-base/.manual.xml
generate_docbook() {
    (
        cd "$PHPDOC"
        php doc-base/configure.php --with-lang="$lang"
    )
}

# Render the PHP manual in the specified format with phd: $format [options]...
render_manual() {
    local format="$1"; shift

    local output_dir="$PHPDOC_BUILD/php-"
    if [[ $format == "php" ]]; then
        output_dir+="web"
    else
        output_dir+="$format"
    fi
    rm -rf "$output_dir"

    git -C "$PHPDOC/phd" apply "$ROOT"/assets/phd.patch

    (
        cd "$PHPDOC"
        php phd/render.php --docbook doc-base/.manual.xml \
            --output "$PHPDOC_BUILD" \
            --package PHP --format "$format" "$@"
    )

    git -C "$PHPDOC/phd" reset --hard -q
}

# Get the language name from the language code: $code
get_lang_name() {
    local code="$1"
    for i in "${!LANG_CODES[@]}"; do
        if [[ "${LANG_CODES[$i]}" == "$code" ]]; then
            echo "${LANG_NAMES[$i]}"
            return 0
        fi
    done
    return 1
}

escape_sql_string() {
    local s="$1"
    s="${s//\'/''}"
    s="${s//\\/\\\\}"
    echo "$s"
}

# Create a Dash docset from the rendered HTML files: $root
# https://kapeli.com/docsets#dashDocset
create_dash_docset() {
    local docset_basename="PHP_${lang}.docset"
    local docset="$PHPDOC_BUILD/$docset_basename"

    rm -rf "$docset"
    mkdir -p "$docset/Contents/Resources"
    cp -R "$1" "$docset/Contents/Resources/Documents"

    cp "$ROOT/assets/icon.png" "$docset/"
    cp "$ROOT/assets/icon@2x.png" "$docset/"

    local lang_name=$(get_lang_name "$lang")
    cat <<EOF > "$docset/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>php.${lang}</string>
	<key>CFBundleName</key>
	<string>PHP (${lang_name})</string>
	<key>DocSetPlatformFamily</key>
	<string>php</string>
	<key>dashIndexFilePath</key>
	<string>index.html</string>
	<key>isDashDocset</key>
	<true/>
</dict>
</plist>
EOF

    local sql="$PHPDOC_BUILD/docset.sql"
    cat <<EOF > "$sql"
BEGIN TRANSACTION;
CREATE TABLE searchIndex(id INTEGER PRIMARY KEY, name TEXT, type TEXT, path TEXT);
CREATE UNIQUE INDEX anchor ON searchIndex (name, type, path);
COMMIT;
EOF

    echo 'BEGIN TRANSACTION;' >> "$sql"

    local name="strlen"
    local type="Function"
    local path="function.strlen.html"
    printf "INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES ('%s', '%s', '%s');\n" \
        "$(escape_sql_string "$name")" "$(escape_sql_string "$type")" "$(escape_sql_string "$path")" \
        >> "$sql"

    echo 'COMMIT;' >> "$sql"

    sqlite3 "$docset/Contents/Resources/docSet.dsidx" < "$sql"
    rm "$sql"

    tar --exclude='.DS_Store' -czf "$OUTPUT/${docset_basename%.*}.tgz" -C "$(dirname "$docset")" "$docset_basename"
    rm -rf "$OUTPUT/$docset_basename" && mv "$docset" "$OUTPUT/"
    echo -e "\nCreated Dash docset at $OUTPUT/$docset_basename"
}

build_docset() {
    # Prepare styles and fonts
    rm -rf "$PHPDOC_BUILD/fonts"
    cp -R "$PHPDOC/web-php/fonts" "$PHPDOC_BUILD/"
    find "$PHPDOC_BUILD/fonts" -type f -name "*.css" -exec sed "${SED_INPLACE[@]}" "s|'/fonts/|'../fonts/|g" {} +
    find "$PHPDOC_BUILD/fonts/Font-Awesome" -type f -name "*.css" -exec sed "${SED_INPLACE[@]}" "s|'\.\./font/|'../fonts/Font-Awesome/font/|g" {} +

    render_manual enhancedchm --forceindex --lang "$lang" \
        --css "$PHPDOC_BUILD/fonts/Fira/fira.css" \
        --css "$PHPDOC_BUILD/fonts/Font-Awesome/css/fontello.css" \
        --css "$PHPDOC/web-php/styles/theme-base.css" \
        --css "$PHPDOC/web-php/styles/theme-medium.css" \
        --css "$ROOT/assets/style.css"

    local root="$PHPDOC_BUILD/php-enhancedchm/res"

    mv "$PHPDOC_BUILD/fonts" "$root/"
    cp "$PHPDOC/web-php/images/bg-texture-00.svg" "$root/images/"

    create_dash_docset "$root"
}

build_mirror() {
    local root="$PHPDOC_BUILD/php.net"

    render_manual php

    rsync -aq --delete --exclude='.git' "$PHPDOC/web-php/" "$root/"

    # See https://wiki.php.net/web/mirror
    (
        cd "$root"
        # Some files are pre-generated on master.php.net for various reasons
        (cd include && for i in countries.inc last_updated.inc mirrors.inc pregen-confs.inc pregen-events.inc pregen-news.inc; do wget "https://www.php.net/include/$i" -O $i; done;)
        (cd backend && for i in ip-to-country.db ip-to-country.idx; do wget "https://www.php.net/backend/$i" -O $i; done;)
    ) &>/dev/null

    rm -rf "$root/manual/$lang"
    mv "$PHPDOC_BUILD/php-web" "$root/manual/$lang"

    echo -e "\nCreated php.net mirror at $root, you may run the web server via:"
    echo -e "${GREEN}(cd \"$root\" && php -S localhost:8080 .router.php)${NC}"
}

main() {
    mkdir -p "$OUTPUT"
    mkdir -p "$PHPDOC"
    mkdir -p "$PHPDOC_BUILD"

    fetch_repos
    generate_docbook

    build_docset

    if [[ "$mirror" == true ]]; then
        build_mirror
    fi
}

# Handle user input and arguments
if [[ $# -gt 0 ]]; then
    for arg in "$@"; do
        case "$arg" in
            --mirror)
                mirror=true
                ;;
            help|-h|--help)
                usage
                exit 0
                ;;
            *)
                lang="$arg"
                ;;
        esac
    done

    lang=$(echo "$lang" | tr '[:upper:]' '[:lower:]')
    if [[ ! " ${LANG_CODES[*]} " =~ " $lang " ]]; then
        echo -e "${RED}Error: unsupported language: ${lang}${NC}"
        echo -e "${GREEN}Supported languages: ${LANG_CODES[*]}${NC}"
        exit 1
    fi
fi

main
