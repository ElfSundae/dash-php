#!/usr/bin/env bash
set -euo pipefail

# Build Release assets for all PHP docsets.
# Generate partial site files.

ROOT="$(cd "$(dirname "$0")" && pwd)"
source "$ROOT/lib/common.sh"

OUTPUT_DIR="release"
OUTPUT="$ROOT/$OUTPUT_DIR"
SITE="$ROOT/_site"

RELEASE_BODY_FILE="$OUTPUT/body.md"
RELEASE_ASSETS_FILE="$OUTPUT/assets.txt"

# Store docset versions table rows for release body
DOCSET_VERSIONS_ROWS=""

build_release() {
    local lang=$(normalize_lang_code "$1")

    local docset_name="PHP_${lang}"
    local docset_filename="${docset_name}.docset"
    local docset="$OUTPUT/$docset_filename"
    local docset_archive="${docset_name}.tgz"
    local docset_archive_path="$OUTPUT/$docset_archive"
    local docset_archive_url="https://github.com/ElfSundae/dash-php/releases/download/docsets/${docset_archive}"

    local lang_en_name=$(get_lang_en_name "$lang")
    local feed_filename="PHP_-_${lang_en_name// /_}.xml"
    local feed_url="https://elfsundae.github.io/dash-php/feeds/${feed_filename}"
    local install_url="https://elfsundae.github.io/dash-php/feed/?lang=${lang}"

    echo "===== Build Release Assets for $docset_filename ====="

    if ! "$ROOT/generate.sh" "$lang" --output "$OUTPUT"; then
        msg_main "Try to download existing docset: ${docset_archive_url}..."
        if ! curl -fsL -o "$docset_archive_path" "$docset_archive_url"; then
            msg_error "Failed to download existing docset: $docset_archive"
            return 0
        fi

        msg_main "Unarchiving ${docset_archive}..."
        tar -xf "$docset_archive_path" -C "$OUTPUT" || {
            msg_error "Failed to unarchive $docset_archive"
            return 0
        }
    fi

    if [[ ! -f "$docset_archive_path" ]]; then
        msg_main "Archiving ${docset_filename}..."
        (
            cd "$OUTPUT"
            tar --exclude='.DS_Store' --exclude='optimizedIndex.dsidx' -czf "$docset_archive" "$docset_filename"
        ) || {
            msg_error "Failed to archive $docset_filename"
            reutrn 0
        }
        msg_sub "Archived $docset_filename to $docset_archive"
    fi

    local docset_bundle_name
    docset_bundle_name=$(get_docset_bundle_name "$docset")
    if [[ -z "$docset_bundle_name" ]]; then
        msg_error "Failed to obtain docset bundle name."
        return 0
    fi
    msg_main "$docset_filename bundle name: $docset_bundle_name"

    local docset_build_date
    docset_build_date=$(get_docset_build_date "$docset")
    if [[ -z "$docset_build_date" ]]; then
        msg_error "Failed to obtain docset build date."
        return 0
    fi
    msg_main "$docset_filename build date: $docset_build_date"

    msg_main "Obtaining the docset version..."
    local version
    version=$(get_docset_version "$docset")
    if [[ -z "$version" ]]; then
        msg_error "Failed to obtain the docset version."
        return 0
    fi
    msg_sub "$docset_filename version: $version"

    tee "${OUTPUT}/${feed_filename}" <<EOF
<entry>
    <version>${version}</version>
    <url>${docset_archive_url}</url>
</entry>
EOF

    echo "$OUTPUT_DIR/${docset_archive}" >> "$RELEASE_ASSETS_FILE"
    # echo "$OUTPUT_DIR/${feed_filename}" >> "$RELEASE_ASSETS_FILE"

    DOCSET_VERSIONS_ROWS+="| ${docset_bundle_name} | \
${docset_build_date} | \`${version}\` | <${feed_url}> | \
📚 [Add to Dash](${install_url} \"Add ${docset_bundle_name} docset feed to Dash\") | \
"$'\n'

    msg_main "Generating site files..."

    mkdir -p "$SITE/feeds"
    cp "${OUTPUT}/${feed_filename}" "$SITE/feeds/"

    mkdir -p "$SITE/shields"
    jq --indent 4 -n \
        --arg build_date "$docset_build_date" \
        --arg version "$version" \
        '{
            "schemaVersion": 1,
            "label": $build_date,
            "message": $version,
            "color": "blue",
            "labelColor": "grey"
        }' > "$SITE/shields/${docset_name}.json"
}

require_command curl md5sum tar jq

rm -rf "$OUTPUT"
mkdir -p "$OUTPUT"

rm -rf "$SITE"
mkdir -p "$SITE"

for lang in "${LANG_CODES[@]}"; do
    build_release "$lang"
done

if [[ ! -s "$RELEASE_ASSETS_FILE" ]]; then
    msg_error "Failed to build any docset release assets."
    exit 10
fi

cat <<EOF > "$RELEASE_BODY_FILE"
This release provides automatically updated Dash docsets for the [PHP Manual](https://www.php.net/manual), available in multiple languages.

| Docset | Build Date | Version | Feed URL | Install |
|--------|------------|---------|----------|---------|
$DOCSET_VERSIONS_ROWS
EOF
