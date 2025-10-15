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

# Supported languages: https://github.com/php/web-php/blob/master/src/I18n/Languages.php
# You may run the following command to get the latest language codes:
# `tmp=$(mktemp) && curl -fsSL 'https://raw.githubusercontent.com/php/web-php/master/src/I18n/Languages.php' -o "$tmp" && php -r 'require '"'"$tmp"'"'; echo implode(" ", array_keys(\phpweb\I18n\Languages::ACTIVE_ONLINE_LANGUAGES)).PHP_EOL;' && rm -f "$tmp"`
LANG_CODES=(en de es fr it ja pt_BR ru tr uk zh)
LANG_NAMES=(
    "English" "Deutsch" "Español" "Français" "Italiano" "日本語"
    "Português Brasil" "Русский" "Türkçe" "Українська" "简体中文"
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
# Whether to generate a php.net mirror instead of docsets
mirror=false
# Whether to exclude user-contributed notes from the manual
no_usernotes=false
# Whether to skip fetching or updating PHP doc repositories
skip_update=false
# The output directory for generated docsets or php.net mirror
OUTPUT="$ROOT/output"
# Whether to display verbose output
verbose=false

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
  --mirror          Generate a php.net mirror instead of docsets.
  --no-usernotes    Exclude user-contributed notes from the manual.
  --skip-update     Skip cloning or updating PHP doc repositories.
  --output <dir>    Specify the output directory (default: '$OUTPUT').
  --verbose         Display verbose output.
  help, -h, --help  Display this help message.
EOF
}

msg_main() {
    echo -e "${GREEN}➤ $*${NC}"
}

msg_sub() {
    echo -e "  ⏳ $*"
}

msg_done() {
    echo -e "${GREEN}✔ $*${NC}"
}

msg_error() {
    echo -e "${RED}❌ $*${NC}" >&2
}

# Run a shell command with optional verbose output: $cmd
run() {
    if [[ "${verbose:-false}" == true ]]; then
        "$@"
    else
        "$@" >/dev/null 2>&1
    fi
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

# Normalize the language code to a standard format (e.g., "en_us" to "en_US")
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

escape_sql_string() {
    local s="$1"
    s="${s//\'/''}"
    s="${s//\\/\\\\}"
    echo "$s"
}

# Clone or update a git repository: $repo [$path]
clone_or_update() {
    (
        cd "$PHPDOC"

        local repo="$1"
        local path="${2:-$(basename "$repo" .git)}"

        if [ -d "$path" ]; then
            (
                cd "$path"
                run git fetch origin
                run git reset --hard origin/$(git symbolic-ref --short HEAD)
                run git clean -dxfq
            )
        else
            run git clone "$repo" "$path"
        fi
    )
}

# Update the required git repositories
update_repos() {
    msg_main "Updating PHP doc repositories..."

    clone_or_update "https://github.com/php/doc-base.git"
    clone_or_update "https://github.com/php/doc-en.git" en
    clone_or_update "https://github.com/php/phd.git"
    clone_or_update "https://github.com/php/web-php.git"

    for lang in "${LANGS[@]}"; do
        if [[ "$lang" != "en" ]]; then
            clone_or_update "https://github.com/php/doc-${lang}.git" "$lang"
        fi
    done
}

# Build the Docbook XML file doc-base/.manual.xml for the specified language: $lang
build_docbook() {
    local lang="$1"
    (
        cd "$PHPDOC"
        run php doc-base/configure.php --with-lang="$lang"
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

    git -C "$PHPDOC/phd" apply "$ROOT/assets/phd.patch"

    rm -rf "$dest"
    run php "$PHPDOC/phd/render.php" --docbook "$PHPDOC/doc-base/.manual.xml" \
        --output "$(dirname "$dest")" --package PHP --format "$format" "$@"

    git -C "$PHPDOC/phd" reset --hard -q
}

PHP_INDEX_DB_CONDITIONS=(
    "Interface: chunk = 1 AND element = 'phpdoc:classref' AND parent_id = 'reserved.interfaces'"
    "Enum: chunk = 1 AND element = 'phpdoc:classref' AND filename LIKE 'enum.%'"
    "Class: chunk = 1 AND element = 'phpdoc:classref' AND parent_id <> 'reserved.interfaces' AND filename NOT LIKE 'enum.%'"
    "Exception: chunk = 1 AND element = 'phpdoc:exceptionref'"
    "Method: element = 'refentry' AND sdesc LIKE '%::%'"
    "Function: element = 'refentry' AND sdesc NOT LIKE '%::%'"
    "Keyword: chunk = 1 AND filename LIKE 'control-structures.%' AND filename NOT IN ('control-structures.intro', 'control-structures.alternative-syntax')"
    "Keyword: chunk = 1 AND parent_id = 'language.control-structures' AND filename NOT LIKE 'control-structures.%'"
    "Variable: chunk = 1 AND element = 'phpdoc:varentry'"
    "Type: chunk = 1 AND parent_id = 'language.types' AND filename <> 'language.types.intro'"
    "Operator: chunk = 1 AND parent_id = 'language.operators'"
    "Extension: chunk = 1 AND element = 'set' AND parent_id <> ''"
    "Extension: chunk = 1 AND element = 'book' AND parent_id <> 'index'"
    "Guide: chunk = 1 AND filename = 'control-structures.alternative-syntax'"
    "Guide: chunk = 1 AND filename LIKE 'reserved.%' AND element <> 'phpdoc:varentry'"
    "Guide: chunk = 1 AND filename LIKE 'language.%' AND element <> 'phpdoc:varentry' AND parent_id <> 'language.types' AND parent_id <> 'language.operators'"
)

# Create a Dash docset from the rendered HTML files: $source $lang $index_db
# https://kapeli.com/docsets#dashDocset
create_dash_docset() {
    msg_sub "Creating Dash docset..."

    local source="$1"
    local lang="$2"
    local index_db="$3"

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
	<string>php_${lang}</string>
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

    msg_sub "Creating Dash docset index..."

    local sql="$docset.sql"
    cat <<EOF > "$sql"
BEGIN TRANSACTION;
CREATE TABLE searchIndex(id INTEGER PRIMARY KEY, name TEXT, type TEXT, path TEXT);
CREATE UNIQUE INDEX anchor ON searchIndex (name, type, path);
COMMIT;
EOF

    echo 'BEGIN TRANSACTION;' >> "$sql"

    # local name="strlen"
    # local type="Function"
    # local path="function.strlen.html"
    # printf "INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES ('%s', '%s', '%s');\n" \
    #     "$(escape_sql_string "$name")" "$(escape_sql_string "$type")" "$(escape_sql_string "$path")" \
    #     >> "$sql"

    for entry in "${PHP_INDEX_DB_CONDITIONS[@]}"; do
        type="${entry%%:*}"
        condition="${entry#*:}"
        sqlite3 "$index_db" <<SQL | sed 's/^INSERT INTO searchIndex /INSERT OR IGNORE INTO searchIndex(name, type, path) /' >> "$sql"
.mode insert searchIndex
.headers off
SELECT
  CASE WHEN sdesc <> '' THEN sdesc ELSE ldesc END AS name,
  '$type' AS type,
  filename || '.html' AS path
FROM ids
WHERE $condition;
SQL
    done

    echo 'COMMIT;' >> "$sql"

    run sqlite3 "$docset/Contents/Resources/docSet.dsidx" < "$sql" || {
        msg_error "Failed to create Dash docset index."
        exit 3
    }

    mkdir -p "$OUTPUT"
    local output_docset="$OUTPUT/$docset_basename"
    rm -rf "$output_docset"
    mv "$docset" "$output_docset"

    msg_done "Generated PHP Dash docset (${lang_name}) at: $output_docset"
}

# Generate the docset for a specific language: $lang
generate_docset() {
    local lang="$1"

    msg_main "Generating PHP Dash docset for language: $lang ($(get_lang_name "$lang"))..."

    msg_sub "Building PHP documentation..."

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

    create_dash_docset "$root/res" "$lang" "$BUILD/index.sqlite"
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

    msg_main "Generating php.net mirror..."

    rsync -aq --delete --exclude='.git' "$PHPDOC/web-php/" "$root/"

    msg_sub "Downloading php.net pre-generated files..."
    # See https://wiki.php.net/web/mirror
    (
        cd "$root"
        # Some files are pre-generated on master.php.net for various reasons
        (cd include && for i in countries.inc last_updated.inc mirrors.inc pregen-confs.inc pregen-events.inc pregen-news.inc; do run wget "https://www.php.net/include/$i" -O $i; done;)
        (cd backend && for i in ip-to-country.db ip-to-country.idx; do run wget "https://www.php.net/backend/$i" -O $i; done;)
    ) || {
        msg_error "Failed to download php.net pre-generated files."
        exit 4
    }

    for lang in "${LANGS[@]}"; do
        msg_sub "Building PHP documentation for language: $lang ($(get_lang_name "$lang"))..."
        build_docbook "$lang"
        render_docbook php
        rm -rf "$root/manual/$lang"
        mv "$BUILD/php-web" "$root/manual/$lang"
    done

    mkdir -p "$OUTPUT"
    local output_mirror="$OUTPUT/php.net"
    rsync -aq --delete "$root/" "$output_mirror/"

    msg_done "Generated php.net mirror at $output_mirror, you may run the web server via:
(cd \"$output_mirror\" && php -S localhost:8080 .router.php)"
}

main() {
    mkdir -p "$PHPDOC"

    if [[ "$skip_update" == false ]]; then
        update_repos
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
        --mirror)
            mirror=true
            shift
            ;;
        --no-usernotes)
            no_usernotes=true
            shift
            ;;
        --skip-update)
            skip_update=true
            shift
            ;;
        --output)
            if [[ $# -lt 2 ]]; then
                msg_error "Error: --output requires a directory argument."
                exit 1
            fi
            OUTPUT="$2"
            shift 2
            ;;
        --verbose)
            verbose=true
            shift
            ;;
        help|-h|--help)
            usage
            exit 0
            ;;
        *)
            # Check if argument is a supported language code
            code=$(normalize_lang_code "$arg")
            if [[ " ${LANG_CODES[*]} " =~ " ${code} " ]]; then
                if [[ ${#LANGS[@]} -eq 0 ]] || [[ ! " ${LANGS[*]} " =~ " ${code} " ]]; then
                    LANGS+=("$code")
                fi
                shift
            else
                msg_error "Error: unsupported argument or language code: ${arg}"
                usage
                exit 1
            fi
            ;;
    esac
done

# Default to 'en' if no languages are specified
if [[ ${#LANGS[@]} -eq 0 ]]; then
    LANGS=(en)
fi

main
