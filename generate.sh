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
# The root directory of the PHP doc repositories
PHPDOC="$ROOT/phpdoc"

# The working build directory
BUILD=$(mktemp -d)
trap 'rm -rf "$BUILD"' EXIT

### Flags and variables for options
# The languages to generate
LANGS=()
# The output directory for generated docsets or php.net mirror
OUTPUT="$ROOT/output"
# Whether to generate a php.net mirror instead of docsets
mirror=false
# Whether to exclude user-contributed notes from the manual
no_usernotes=false
# Whether to skip fetching or updating PHP doc repositories
skip_fetch=false

# Print script usage information
usage() {
    cat <<EOF
Generate Dash docset for the PHP Manual in multiple languages.

Usage: $(basename "$0") [LANG...] [OPTIONS]

Arguments:
  LANG          Language code(s) for the PHP Manual to generate.
                You can specify multiple languages separated by space.
                Supported languages: ${LANG_CODES[*]}
                (default: 'en')

Options:
  --output <dir>    Specify the output directory (default: '$OUTPUT').
  --mirror          Generate a php.net mirror instead of docsets.
  --no-usernotes    Exclude user-contributed notes from the manual.
  --skip-fetch      Skip fetching or updating PHP doc repositories.
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
            (
                cd "$path"
                git fetch origin
                git reset --hard origin/$(git symbolic-ref --short HEAD)
                git clean -dxfq
            )
        else
            git clone "$repo" "$path"
        fi
    )
}

# Fetch or update the required git repositories
fetch_repos() {
    echo -e "${GREEN}Fetching or updating PHP doc repositories...${NC}"

    clone_or_pull "https://github.com/php/doc-base.git"
    clone_or_pull "https://github.com/php/doc-en.git" en
    clone_or_pull "https://github.com/php/phd.git"
    clone_or_pull "https://github.com/php/web-php.git"

    for lang in "${LANGS[@]}"; do
        if [[ "$lang" != "en" ]]; then
            clone_or_pull "https://github.com/php/doc-${lang}.git" "$lang"
        fi
    done
}

# Build the Docbook XML file doc-base/.manual.xml for the specified language: $lang
build_docbook() {
    local lang="$1"
    (
        cd "$PHPDOC"
        php doc-base/configure.php --with-lang="$lang"
    )
}

# Render the Docbook XML file to the specified format: $format [options...]
# Supported formats: php, xhtml, chm, enhancedchm
render_docbook() {
    local format="$1"; shift

    local dest="$BUILD/php-"
    if [[ $format == "php" ]]; then
        dest+="web"
    else
        dest+="$format"
    fi

    git -C "$PHPDOC/phd" apply "$ROOT"/assets/phd.patch

    rm -rf "$dest"
    php "$PHPDOC/phd/render.php" --docbook "$PHPDOC/doc-base/.manual.xml" \
        --output "$(dirname "$dest")" --package PHP --format "$format" "$@"

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

# Create a Dash docset from the rendered HTML files: $source $lang
# https://kapeli.com/docsets#dashDocset
create_dash_docset() {
    local source="$1"
    local lang="$2"

    local docset_basename="PHP_${lang}.docset"
    local docset="$BUILD/$docset_basename"

    rm -rf "$docset"
    mkdir -p "$docset/Contents/Resources"
    cp -R "$source" "$docset/Contents/Resources/Documents"

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

    local sql="$docset.sql"
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

    mkdir -p "$OUTPUT"
    local output_docset="$OUTPUT/$docset_basename"
    local output_docset_archive="$OUTPUT/${docset_basename%.*}.tgz"

    tar --exclude='.DS_Store' -czf "$output_docset_archive" -C "$(dirname "$docset")" "$(basename "$docset")"
    rm -rf "$output_docset"
    mv "$docset" "$output_docset"

    echo -e "${GREEN}Generated PHP Dash docset at: $output_docset${NC}"
    echo -e "${GREEN}Generated PHP Dash docset archive at: $output_docset_archive${NC}"
}

# Generate the docset for a specific language: $lang
generate_docset() {
    local lang="$1"

    echo -e "${GREEN}Generating PHP Dash docset for language: $lang ($(get_lang_name "$lang"))...${NC}"

    build_docbook "$lang"

    # Prepare styles and fonts
    local fonts="$BUILD/fonts"
    rm -rf "$fonts"
    cp -R "$PHPDOC/web-php/fonts" "$fonts"
    find "$fonts" -type f -name "*.css" -exec sed "${SED_INPLACE[@]}" "s|'/fonts/|'../fonts/|g" {} +
    find "$fonts/Font-Awesome" -type f -name "*.css" -exec sed "${SED_INPLACE[@]}" "s|'\.\./font/|'../fonts/Font-Awesome/font/|g" {} +

    local format="enhancedchm"
    if [[ "$no_usernotes" == true ]]; then
        format="chm"
    fi

    render_docbook "$format" --lang "$lang" \
        --css "$fonts/Fira/fira.css" \
        --css "$fonts/Font-Awesome/css/fontello.css" \
        --css "$PHPDOC/web-php/styles/theme-base.css" \
        --css "$PHPDOC/web-php/styles/theme-medium.css" \
        --css "$ROOT/assets/style.css"

    local root="$BUILD/php-$format"
    mv "$fonts" "$root/res/"
    cp "$PHPDOC/web-php/images/bg-texture-00.svg" "$root/res/images/"

    create_dash_docset "$root/res" "$lang"
    rm -rf "$root"
}

# Generate Dash docsets for all specified languages
generate_docsets() {
    for lang in "${LANGS[@]}"; do
        generate_docset "$lang"
    done
}

# Generate a php.net mirror in the output directory
generate_mirror() {
    local root="$BUILD/php.net"

    echo -e "${GREEN}Generating php.net mirror...${NC}"

    rsync -aq --delete --exclude='.git' "$PHPDOC/web-php/" "$root/"

    # Download php.net pre-generated files
    # See https://wiki.php.net/web/mirror
    (
        cd "$root"
        # Some files are pre-generated on master.php.net for various reasons
        (cd include && for i in countries.inc last_updated.inc mirrors.inc pregen-confs.inc pregen-events.inc pregen-news.inc; do wget "https://www.php.net/include/$i" -O $i; done;)
        (cd backend && for i in ip-to-country.db ip-to-country.idx; do wget "https://www.php.net/backend/$i" -O $i; done;)
    ) &>/dev/null || {
        echo -e "${RED}Error: Failed to download php.net pre-generated files.${NC}" >&2
        exit 4
    }

    for lang in "${LANGS[@]}"; do
        build_docbook "$lang"
        render_docbook php
        local output="$BUILD/php-web"
        rm -rf "$root/manual/$lang"
        mv "$output" "$root/manual/$lang"
    done

    mkdir -p "$OUTPUT"
    local output_mirror="$OUTPUT/php.net"
    rsync -aq --delete "$root/" "$output_mirror/"

    echo -e "${GREEN}Generated php.net mirror at $output_mirror, you may run the web server via:${NC}"
    echo -e "${GREEN}(cd \"$output_mirror\" && php -S localhost:8080 .router.php)${NC}"
}

main() {
    mkdir -p "$PHPDOC"

    if [[ "$skip_fetch" == false ]]; then
        fetch_repos
    fi

    if [[ "$mirror" == false ]]; then
        generate_docsets
    else
        generate_mirror
    fi
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
        --output)
            if [[ $# -lt 2 ]]; then
                echo -e "${RED}Error: --output requires a directory argument.${NC}" >&2
                exit 1
            fi
            OUTPUT="$2"
            shift 2
            ;;
        --mirror)
            mirror=true
            shift
            ;;
        --no-usernotes)
            no_usernotes=true
            shift
            ;;
        --skip-fetch)
            skip_fetch=true
            shift
            ;;
        help|-h|--help)
            usage
            exit 0
            ;;
        *)
            # Check if argument is a supported language code
            lower_arg=$(echo "$arg" | tr '[:upper:]' '[:lower:]')
            if [[ " ${LANG_CODES[*]} " =~ " ${lower_arg} " ]]; then
                if [[ ${#LANGS[@]} -eq 0 ]] || [[ ! " ${LANGS[*]} " =~ " ${lower_arg} " ]]; then
                    LANGS+=("$lower_arg")
                fi
                shift
            else
                echo -e "${RED}Error: unsupported argument or language code: ${arg}${NC}" >&2
                usage
                exit 1
            fi
            ;;
    esac
done

# Default to 'en' if no languages are specified
if [[ ${#LANGS[@]} -eq 0 ]]; then
    LANGS=("en")
fi

main
