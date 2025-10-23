#!/usr/bin/env bash
set -euo pipefail

# Automatically update the PHP docset to the Dash user contributed docsets repository.
# This script is designed to be executed both locally and within a GitHub workflow.

FORK_REPO="${FORK_REPO:-ElfSundae/Dash-User-Contributions}"
UPSTREAM_REPO="Kapeli/Dash-User-Contributions"

ROOT="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="$ROOT/output"

# Define colors for output messages
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m" # No Color

msg_main() {
    echo -e "${GREEN}[+] $*${NC}"
}

msg_sub() {
    echo -e "    $*"
}

msg_error() {
    echo -e "${RED}[!] $*${NC}" >&2
}

require() {
    local cmd
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || { msg_error "Missing command: $cmd"; exit 1; }
    done
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

# Compare two versions, return 0 if same, 1 if different: $version1 $version2
version_same() {
    local v1="$1" v2="$2"
    [[ "${v1#*_}" == "${v2#*_}" ]]
}

# Obtain the version of the Dash docset: $docset_path
# Return empty string if failed, otherwise the version.
docset_version() {
    local docset="$1"

    local pubdate; pubdate=$(xmllint --html --xpath 'string(//div[@class="pubdate"][1])' \
        "$docset/Contents/Resources/Documents/index.html" 2>/dev/null | xargs)
    [[ -n "$pubdate" ]] || { echo ""; return 0; }

    local indexes; indexes=$(sqlite3 -noheader "$docset/Contents/Resources/docSet.dsidx" \
        'SELECT COUNT(*) FROM searchIndex;' 2>/dev/null)
    [[ -n "$indexes" ]] || { echo ""; return 0; }

    local hash; hash=$(
        cd "$docset" 2>/dev/null || { echo ""; return 0; }
        find . -type f \
            -not -name '.DS_Store' \
            -not -name '*.dsidx' \
            -print0 | sort -z | xargs -0 md5sum | md5sum | cut -c1-6
    )
    [[ -n "$hash" ]] || { echo ""; return 0; }

    echo "/${pubdate}_${indexes}_${hash}"
}

# Fetch the latest version of the Dash docset: $docset_name OR $docset_filename OR $docset_path
# Return non-zero exit code if request failed, empty string if not found, otherwise the version.
fetch_latest_docset_version() {
    local name; name=$(basename "$1" .docset)
    local url="https://raw.githubusercontent.com/${UPSTREAM_REPO}/HEAD/docsets/${name}/docset.json"

    local exit_code=0
    local response; response=$(curl -fsL -w "\n%{http_code}" "$url" 2>/dev/null) || exit_code=$?
    local http_code; http_code=$(echo "$response" | tail -n1)

    # Return empty string if docset does not exist upstream (404)
    if [[ $http_code -eq 404 ]]; then
        echo ""
        return 0
    fi

    # Return failure if request failed or HTTP status is not 200
    if [[ $exit_code -ne 0 || $http_code -ne 200 ]]; then
        return 1
    fi

    # Extract version from JSON response
    local version; version=$( (echo "$response" | sed '$d' | jq -r '.version') 2>/dev/null )

    # Return failure if version is empty or null - invalid docset.json
    if [[ -z "$version" || "$version" == "null" ]]; then
        return 1
    fi

    echo "$version"
}

require xmllint sqlite3 curl jq tar git gh

if [[ $# -lt 1 ]]; then
    msg_error "Usage: $0 <lang> [options...]"
    exit 1
fi

lang=$(normalize_lang_code "$1"); shift

docset_name="PHP_${lang}"
docset_filename="${docset_name}.docset"
docset_archive="${docset_name}.tgz"

fork_owner="${FORK_REPO%%/*}"
fork_path="$OUTPUT/${FORK_REPO##*/}"
branch="auto-update-${docset_name}"

msg_main "Auto updating ${docset_filename}..."

# Generate the Dash docset
"$ROOT/generate.sh" "$lang" "$@" || {
    msg_error "Failed to generate Dash docset for language: $lang"
    exit 2
}

docset_bundle_name=$(xmllint \
    --xpath 'string(/plist/dict/key[.="CFBundleName"]/following-sibling::string[1])' \
    "$OUTPUT/$docset_filename/Contents/Info.plist" 2>/dev/null) || {
    msg_error "Failed to obtain docset bundle name."
    exit 3
}
msg_main "Docset bundle name: $docset_bundle_name"

localized_manual_title=$(xmllint --html --xpath 'string(//title[1])' \
    "$OUTPUT/$docset_filename/Contents/Resources/Documents/index.html" 2>/dev/null) || {
    msg_error "Failed to obtain localized manual title."
    exit 3
}
msg_main "Localized manual title: $localized_manual_title"

msg_main "Obtaining the docset version..."
version=$(docset_version "$OUTPUT/$docset_filename")
if [[ -z "$version" ]]; then
    msg_error "Failed to obtain the docset version."
    exit 3
fi
msg_sub "$docset_filename version: $version"

msg_main "Fetching the latest version..."
latest_version=$(fetch_latest_docset_version "$docset_name") || {
    msg_error "Failed to fetch the latest version."
    exit 4
}
msg_sub "$docset_filename latest version: ${latest_version:-none}"

# Compare versions to determine if an update is necessary
if version_same "$version" "$latest_version"; then
    msg_main "$docset_filename is already up-to-date, skipping update."
    exit 0
fi

msg_main "Archiving ${docset_filename}..."
(
    cd "$OUTPUT"
    rm -rf "$docset_archive"
    tar --exclude='.DS_Store' --exclude='optimizedIndex.dsidx' -czf "$docset_archive" "$docset_filename"
) || {
    msg_error "Failed to archive $docset_filename"
    exit 5
}
msg_sub "Archived $docset_filename to $docset_archive"

msg_main "Preparing the fork repository..."
if [[ ! -d "$fork_path" ]]; then
    if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
        git clone "https://x-access-token:${GH_TOKEN}@github.com/${FORK_REPO}.git" "$fork_path"
    else
        git clone "https://github.com/${FORK_REPO}.git" "$fork_path"
    fi
else
    (
        cd "$fork_path"
        git reset --hard
        git clean -dxfq
    )
fi

# Sync fork, checkout master branch
(
    cd "$fork_path"
    git remote add upstream "https://github.com/${UPSTREAM_REPO}.git" 2>/dev/null || true
    git fetch --all
    git checkout master
    git reset --hard upstream/master
    git push origin master --force
)

msg_main "Checking for existing pull requests..."
existing_pr_url=$(gh pr list \
    --repo "$UPSTREAM_REPO" \
    --base master \
    --author "$fork_owner" \
    --head "$branch" \
    --state open \
    --json url \
    --jq '.[0].url' 2>/dev/null
) || {
    msg_error "Failed to check existing pull requests."
    exit 6
}
msg_sub "Existing pull request: ${existing_pr_url:-none}"

# If no existing opened PR on this branch, clean up old branch if exists, to avoid conflicts.
# If there is an existing opened PR, keep the branch as is to preserve history,
# and new commits will be added to the existing branch, then the PR will be automatically updated.
if [[ -z "$existing_pr_url" ]]; then
    msg_main "Cleaning up old branch if exists..."
    (
        cd "$fork_path"
        git branch -D "$branch" 2>/dev/null || true

        exit_code=0
        git push origin --delete "$branch" 2>/dev/null || exit_code=$?

        # exit_code 0: branch deleted; 1: branch does not exist
        if [[ $exit_code -eq 0 || $exit_code -eq 1 ]]; then
            exit 0
        fi

        # Network or authentication error while deleting branch
        exit $exit_code
    ) || {
        msg_error "Failed to clean up old branch, maybe due to network or authentication error."
        exit 7
    }
fi

msg_main "Checking out branch '$branch'..."
(
    cd "$fork_path"
    if git rev-parse --verify "origin/$branch" >/dev/null 2>&1; then
        git checkout -B "$branch" "origin/$branch"
    else
        git checkout -b "$branch"
    fi
)

# Compare existing docset.json version (PR in progress) to determine if an update is necessary.
fork_docset_json="$fork_path/docsets/$docset_name/docset.json"
if [[ -f "$fork_docset_json" ]]; then
    msg_main "Reading existing docset.json version in the fork repository..."
    existing_version=$(jq -r '.version' "$fork_docset_json" 2>/dev/null) || {
        msg_error "Failed to read existing docset.json version."
        exit 8
    }
    msg_sub "Existing docset.json version: $existing_version"

    if version_same "$version" "$existing_version"; then
        msg_main "$docset_filename is already up-to-date in the fork repository, skipping update."
        exit 0
    fi
fi

msg_main "Updating the docset in the fork repository..."

if [[ -z "$latest_version" ]]; then
    commit_message="Add new docset: $docset_bundle_name (\`$version\`)"
    pr_body="This PR adds a new docset: **${docset_bundle_name}** version \`$version\`."
else
    commit_message="Update $docset_bundle_name to \`$version\`"
    pr_body="This PR updates the **${docset_bundle_name}** docset to version \`$version\`."
fi

(
    cd "$fork_path"

    root="docsets/$docset_name"
    mkdir -p "$root"

    cp -f "$OUTPUT/$docset_archive" "$root/"
    cp -f "$OUTPUT/$docset_filename/icon.png" "$root/"
    cp -f "$OUTPUT/$docset_filename/icon@2x.png" "$root/"
    cp -f "$ROOT/assets/Dash-User-Contributions/README.md" "$root/"

    jq --indent 4 -n \
        --arg name "$docset_bundle_name" \
        --arg version "$version" \
        --arg archive "$docset_archive" \
        '{
            "name": $name,
            "version": $version,
            "archive": $archive,
            "author": {
                "name": "Elf Sundae",
                "link": "https://github.com/ElfSundae"
            },
            "aliases": ["PHP", "PHP Manual", "PHP Documentation"]
         }' > "$root/docset.json"

    if [[ "$lang" != "en" ]]; then
        jq --indent 4 --arg title "$localized_manual_title" \
            '.aliases |= (if index($title) then . else . + [$title] end)' "$root/docset.json" \
            > temp.json && mv temp.json "$root/docset.json"
    fi

    cat "$root/docset.json"

    git add -A
    git commit -m "$commit_message"
    git push -u origin "$branch"
)

if [[ -z "$existing_pr_url" ]]; then
    msg_main "Creating a new pull request..."
    pr_url=$(gh pr create \
        --repo "$UPSTREAM_REPO" \
        --base master \
        --title "$commit_message" \
        --body "$pr_body" \
        --head "$fork_owner:$branch" 2>/dev/null
    ) || {
        msg_error "Failed to create a new pull request."
        exit 9
    }
    msg_sub "Pull request created: $pr_url"
else
    msg_main "Updating existing pull request: $existing_pr_url..."
    pr_url=$(gh pr edit "$existing_pr_url" \
        --repo "$UPSTREAM_REPO" \
        --title "$commit_message" \
        --body "$pr_body" 2>/dev/null
    ) || {
        msg_error "Failed to update existing pull request."
        exit 10
    }
    msg_sub "Pull request updated: $pr_url"
fi
