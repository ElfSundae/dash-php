#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
source "$ROOT/lib/common.sh"

# The root directory of the PHP doc repositories
PHPDOC="$ROOT/phpdoc"

# The working build directory
BUILD=""

### Flags and variables for options
# The languages to generate
LANGS=()
# Whether to generate a php.net mirror instead of docsets
MIRROR=false
# Whether to exclude user-contributed notes from the manual
NO_USERNOTES=false
# Whether to skip fetching or updating PHP doc repositories
SKIP_UPDATE=false
# The output directory for generated docsets or php.net mirror
OUTPUT="$ROOT/output"
# Whether to display verbose output
VERBOSE=false
# Local dev mode
DEV_MODE=false

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

# Run a shell command with optional verbose output: $cmd
run() {
    if [[ "${VERBOSE:-false}" == true ]]; then
        "$@"
    else
        "$@" >/dev/null 2>&1
    fi
}

# Trim leading and trailing whitespace from a string: $string
trim() {
    local var="$1"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    printf '%s' "$var"
}

escape_sql_string() {
    local s="$1"
    s="${s//\'/''}"
    s="${s//\\/\\\\}"
    echo "$s"
}

# Clone or update a git repository: $repo [$path]
clone_or_update() {
    local repo="$1"
    local path="${2:-$(basename "$repo" .git)}"

    (
        cd "$PHPDOC"
        if [ -d "$path" ]; then
            (
                cd "$path"
                run git fetch --depth=1 origin
                run git reset --hard origin/$(git symbolic-ref --short HEAD)
                run git clean -dxfq
            )
        else
            run git clone --depth=1 "$repo" "$path"
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

    local lang
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

PHD_INDEX_DB_CONDITIONS=(
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

ANCHOR_INDEX_DB_QUERIES=(
    "Constant: SELECT docbook_id, filename FROM ids
                WHERE element IN ('row', 'varlistentry')
                AND (docbook_id LIKE 'constant.%' OR docbook_id LIKE '%.constant.%'
                    OR docbook_id LIKE 'constants.%' OR docbook_id LIKE '%.constants.%')"
    "Setting: SELECT docbook_id, filename FROM ids
                WHERE element = 'varlistentry' AND docbook_id LIKE 'ini.%'"
    "Property: SELECT t.docbook_id, t.filename, s.sdesc AS classname
                FROM ids AS t
                LEFT JOIN ids AS s
                    ON s.docbook_id = t.filename
                    AND s.filename = t.filename
                    AND s.sdesc <> ''
                WHERE t.element = 'varlistentry' AND t.docbook_id LIKE '%.props.%' AND t.filename LIKE 'class.%'"
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

    local lang_name; lang_name=$(get_lang_local_name "$lang")
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

    msg_sub "Creating Dash docset index database..."

    local sql="$docset.sql"

    cat <<EOF > "$sql"
BEGIN TRANSACTION;
CREATE TABLE searchIndex(id INTEGER PRIMARY KEY, name TEXT, type TEXT, path TEXT);
CREATE UNIQUE INDEX anchor ON searchIndex (name, type, path);
COMMIT;
EOF

    echo 'BEGIN TRANSACTION;' >> "$sql"

    # Generating indexes from PhD index.sqlite
    local entry type condition
    for entry in "${PHD_INDEX_DB_CONDITIONS[@]}"; do
        type="${entry%%:*}"
        condition="${entry#*:}"
        (
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
        ) || {
            msg_error "Failed to create indexes for type: $type"
            exit 11
        }
    done

    # Generating indexes for Constant/Setting/Property from PhD index.sqlite and rendered files
    local query
    for entry in "${ANCHOR_INDEX_DB_QUERIES[@]}"; do
        type="${entry%%:*}"
        query="${entry#*:}"
        (
            sqlite3 -noheader -separator $'\x1F' "$index_db" "$query;" | \
                while IFS=$'\x1F' read -r id filename extra; do
                    path="${filename}.html#${id}"

                    html_file="$docset/Contents/Resources/Documents/${filename}.html"
                    if [[ ! -f "$html_file" ]]; then
                        if [[ "$DEV_MODE" == true ]]; then
                            echo -e "$type ${GREEN}$id${NC} html file does not exist: ${GREEN}$html_file${NC}"
                        fi
                        continue
                    fi

                    case "$type" in
                        Constant)
                            name=$(xmllint --html --xpath "string(//*[@id='$id']//code[1])" "$html_file" 2>/dev/null || true)
                            ;;
                        Setting)
                            name=$(xmllint --html --xpath "string(//a[@href='$path'][1])" "$html_file" 2>/dev/null || true)
                            name=$(trim "$name")
                            if [[ -z "$name" ]]; then
                                name=$(xmllint --html --xpath "string(//*[@id='$id']//code[1])" "$html_file" 2>/dev/null || true)
                            fi
                            ;;
                        Property)
                            name=$(xmllint --html --xpath "string(//*[@id='$id']//var[@class='varname'][1])" "$html_file" 2>/dev/null || true)
                            name=$(trim "$name")
                            if [[ -n "$name" ]]; then
                                name="${extra}::${name}"
                            fi
                            ;;
                    esac

                    name=$(trim "$name")

                    if [[ -z "${name:-}" ]]; then
                        if [[ "$DEV_MODE" == true ]]; then
                            echo -e "$type ${GREEN}$id${NC} name not found: ${GREEN}$html_file${NC}"
                        fi
                        continue
                    fi

                    printf "INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES('%s', '%s', '%s');\n" \
                        "$(escape_sql_string "$name")" "$(escape_sql_string "$type")" "$(escape_sql_string "$path")" \
                        >> "$sql"
                done
        ) || {
            msg_error "Failed to create indexes for type: $type"
            exit 12
        }
    done

    echo 'COMMIT;' >> "$sql"

    sqlite3 "$docset/Contents/Resources/docSet.dsidx" < "$sql" || {
        msg_error "Failed to create Dash docset index database."
        exit 10
    }

    mkdir -p "$OUTPUT"
    local output_docset="$OUTPUT/$docset_basename"
    rm -rf "$output_docset"
    mv "$docset" "$output_docset"

    if [[ "$DEV_MODE" == true ]]; then
        sqlite3 -box "$output_docset/Contents/Resources/docSet.dsidx" \
            "SELECT type, count(*) AS count FROM searchIndex GROUP BY type UNION ALL SELECT '-TOTAL-', count(*) FROM searchIndex;"
    fi

    msg_done "Generated PHP Dash docset (${lang_name}) at: $output_docset"
}

# Generate the docset for a specific language: $lang
generate_docset() {
    local lang="$1"

    msg_main "Generating PHP Dash docset for language: $lang ($(get_lang_local_name "$lang"))..."

    msg_sub "Building PHP documentation..."

    build_docbook "$lang"

    # Prepare styles and fonts
    local fonts="$BUILD/fonts"
    rm -rf "$fonts"
    cp -R "$PHPDOC/web-php/fonts" "$fonts"
    find "$fonts" -type f -name "*.css" -exec sed "${SED_INPLACE[@]}" "s|'/fonts/|'../fonts/|g" {} +
    find "$fonts/Font-Awesome" -type f -name "*.css" -exec sed "${SED_INPLACE[@]}" "s|'\.\./font/|'../fonts/Font-Awesome/font/|g" {} +

    local format="enhancedchm"
    if [[ "$NO_USERNOTES" == true ]]; then
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
}

# Generate Dash docsets for all specified languages
generate_docsets() {
    local lang
    for lang in "${LANGS[@]}"; do
        generate_docset "$lang"
    done
}

# Generate a php.net mirror in the output directory
generate_mirror() {
    require_command rsync wget

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

    local lang
    for lang in "${LANGS[@]}"; do
        msg_sub "Building PHP documentation for language: $lang ($(get_lang_local_name "$lang"))..."
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

    if [[ "$DEV_MODE" == false ]]; then
        BUILD=$(mktemp -d)
        trap 'rm -rf "$BUILD"' EXIT
    else
        BUILD="$PHPDOC/build"
        mkdir -p "$BUILD"
    fi

    if [[ "$SKIP_UPDATE" == false ]]; then
        update_repos
    fi

    if [[ "$MIRROR" == true ]]; then
        generate_mirror
    else
        generate_docsets
    fi
}

require_command php git sqlite3 xmllint

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
        --mirror)
            MIRROR=true
            shift
            ;;
        --no-usernotes)
            NO_USERNOTES=true
            shift
            ;;
        --skip-update)
            SKIP_UPDATE=true
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
            VERBOSE=true
            shift
            ;;
        --dev)
            DEV_MODE=true
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
