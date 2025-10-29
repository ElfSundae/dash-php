#!/usr/bin/env bash
set -euo pipefail

# Build release assets for all PHP docsets.

ROOT="$(cd "$(dirname "$0")" && pwd)"
source "$ROOT/lib/common.sh"

OUTPUT_DIR="release"
OUTPUT="$ROOT/$OUTPUT_DIR"

RELEASE_BODY="$OUTPUT/release-body.md"
RELEASE_FILES="$OUTPUT/release-files.txt"

# Store docset versions table rows for release body
DOCSET_VERSIONS_ROWS=""

build_release() {
    local lang=$(normalize_lang_code "$1")

    local docset_name="PHP_${lang}"
    local docset_filename="${docset_name}.docset"
    local docset="$OUTPUT/$docset_filename"
    local docset_archive="${docset_name}.tgz"
    local docset_archive_url="https://github.com/ElfSundae/dash-php/releases/download/docsets/${docset_archive}"

    local lang_en_name=$(get_lang_en_name "$lang")
    local feed_filename="PHP_(${lang_en_name// /_}).xml"
    local feed_url="https://github.com/ElfSundae/dash-php/releases/download/docsets/${feed_filename}"
    local install_url="https://elfsundae.github.io/dash-php/feed/?lang=${lang}"

    local docset_bundle_name version

    echo "===== Build Release Assets for $docset_filename ====="

    "$ROOT/generate.sh" "$lang" --output "$OUTPUT" || {
        msg_error "Failed to generate $docset_filename"
        return 0
    }

    docset_bundle_name=$(get_docset_bundle_name "$docset")
    if [[ -z "$docset_bundle_name" ]]; then
        msg_error "Failed to obtain docset bundle name."
        return 0
    fi
    msg_main "$docset_filename bundle name: $docset_bundle_name"

    msg_main "Obtaining the docset version..."
    version=$(get_docset_version "$docset")
    if [[ -z "$version" ]]; then
        msg_error "Failed to obtain the docset version."
        return 0
    fi
    msg_sub "$docset_filename version: $version"

    msg_main "Archiving ${docset_filename}..."
    (
        cd "$OUTPUT"
        rm -rf "$docset_archive"
        tar --exclude='.DS_Store' --exclude='optimizedIndex.dsidx' -czf "$docset_archive" "$docset_filename"
    ) || {
        msg_error "Failed to archive $docset_filename"
        reutrn 0
    }
    msg_sub "Archived $docset_filename to $docset_archive"

    cat <<EOF | tee "${OUTPUT}/${feed_filename}"
<entry>
    <version>${version}</version>
    <url>${docset_archive_url}</url>
</entry>
EOF

    echo "$OUTPUT_DIR/${docset_archive}" >> "$RELEASE_FILES"
    echo "$OUTPUT_DIR/${feed_filename}" >> "$RELEASE_FILES"
    DOCSET_VERSIONS_ROWS+="| ${docset_bundle_name} | \`${version}\` | \
<${feed_url}> | [Install in Dash](${install_url}) |"$'\n'
}

rm -rf "$OUTPUT"
mkdir -p "$OUTPUT"

for lang in "${LANG_CODES[@]}"; do
    build_release "$lang"
done

if [[ ! -s "$RELEASE_FILES" ]]; then
    msg_error "Failed to build any docset release assets."
    exit 10
fi

cat <<EOF > "$RELEASE_BODY"
This release provides automatically updated Dash docsets for the [PHP Manual](https://www.php.net/manual), available in multiple languages.

| Docset | Version | Feed URL | Install |
|--------|---------|----------|---------|
$DOCSET_VERSIONS_ROWS
EOF
