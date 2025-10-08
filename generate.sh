#!/usr/bin/env bash
set -euo pipefail

# TODO: append Dash online url for all html files
# TODO: Build Dash docset

# Define colors for output messages
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m" # No Color

# Supported languages: https://github.com/php/doc-en?tab=readme-ov-file#translations
SUPPORTED_LANGUAGES=("pt_br" "zh" "en" "fr" "de" "it" "ja" "pl" "ro" "ru" "es" "tr" "uk")

# The root directory of this script
ROOT="$(cd "$(dirname "$0")" && pwd)"
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
Generate Dash docset for the PHP Manual.

Usage: $(basename "$0") [LANG] [OPTIONS]

Arguments:
  LANG      Language code for the PHP Manual to generate, defaults to '${lang}'.
            Supported languages: ${SUPPORTED_LANGUAGES[*]}

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

    git -C "$PHPDOC/phd" apply "$ROOT/assets/phd.patch"

    (
        cd "$PHPDOC"
        php phd/render.php --docbook doc-base/.manual.xml \
            --output "$PHPDOC_BUILD" \
            --package PHP --format "$format" "$@" 2>/dev/null
    )

    git -C "$PHPDOC/phd" reset --hard -q
}

build_docset() {
    # Prepare styles and fonts
    rm -rf "$PHPDOC_BUILD/fonts"
    cp -R "$PHPDOC/web-php/fonts" "$PHPDOC_BUILD/"
    find "$PHPDOC_BUILD/fonts" -type f -name "*.css" -exec sed -i '' "s|'/fonts/|'../fonts/|g" {} +
    find "$PHPDOC_BUILD/fonts/Font-Awesome" -type f -name "*.css" -exec sed -i '' "s|'\.\./font/|'../fonts/Font-Awesome/font/|g" {} +

    render_manual enhancedchm --forceindex --lang "$lang" \
        --css "$PHPDOC_BUILD/fonts/Fira/fira.css" \
        --css "$PHPDOC_BUILD/fonts/Font-Awesome/css/fontello.css" \
        --css "$PHPDOC/web-php/styles/theme-base.css" \
        --css "$PHPDOC/web-php/styles/theme-medium.css" \
        --css "$ROOT/assets/style.css"

    mv "$PHPDOC_BUILD/fonts" "$PHPDOC_BUILD/php-enhancedchm/res/"
    cp "$PHPDOC/web-php/images/bg-texture-00.svg" "$PHPDOC_BUILD/php-enhancedchm/res/images/"
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
    ) &>/dev/null || true

    rm -rf "$root/manual/$lang"
    mv "$PHPDOC_BUILD/php-web" "$root/manual/$lang"

    echo -e "\nCreated php.net mirror at $root, you may run the web server via:"
    echo -e "${GREEN}(cd \"$root\" && php -S localhost:8080 .router.php)${NC}"
}

main() {
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
    if [[ ! " ${SUPPORTED_LANGUAGES[*]} " =~ " $lang " ]]; then
        echo -e "${RED}Error: unsupported language: ${lang}${NC}"
        echo -e "${GREEN}Supported languages: ${SUPPORTED_LANGUAGES[*]}${NC}"
        exit 1
    fi
fi

main
