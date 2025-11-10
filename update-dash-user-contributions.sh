#!/usr/bin/env bash
set -euo pipefail

# Automatically update the PHP docsets to the Kapeli/Dash-User-Contributions repository.
# This script is designed to be executed both locally and within a GitHub workflow.

ROOT="$(cd "$(dirname "$0")" && pwd)"
source "$ROOT/lib/common.sh"

FORK_REPO="${FORK_REPO:-ElfSundae/Dash-User-Contributions}"
UPSTREAM_REPO="Kapeli/Dash-User-Contributions"
OUTPUT="$ROOT/output"

DEV_MODE=false
if [[ " $* " == *" --dev "* ]]; then
    DEV_MODE=true
    # Use the fork as upstream in dev mode
    UPSTREAM_REPO="$FORK_REPO"
fi

require_command md5sum tar jq gh

fork_owner="${FORK_REPO%%/*}"
fork_path="$OUTPUT/${FORK_REPO##*/}"
branch="update-php-docsets"

msg_main "Preparing the fork repository (${FORK_REPO})..."

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
    upstream_url="https://github.com/${UPSTREAM_REPO}.git"
    if git remote get-url upstream >/dev/null 2>&1; then
        git remote set-url upstream "$upstream_url"
    else
        git remote add upstream "$upstream_url"
    fi
    git fetch --all
    git checkout master
    git reset --hard upstream/master
    git push origin master --force
)

# Clean up old branch
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
    msg_error "Failed to clean up old branch '${branch}', maybe due to network or authentication error."
    exit 1
}

# Checkout new branch
(
    cd "$fork_path"
    git checkout -b "$branch"
)

commit_message="Update PHP docsets"
pr_body=$(cat <<EOF
This pull request updates the following PHP docsets:

| Docset | Version |
|--------|---------|
EOF
)

for lang in "${LANG_CODES[@]}"; do
    if [[ "$lang" == "en" ]]; then
        continue;
    fi

    docset_name="PHP_${lang}"
    docset_filename="${docset_name}.docset"
    docset_archive="${docset_name}.tgz"
    docset="$OUTPUT/$docset_filename"

    msg_main "Updating ${docset_filename}..."

    if [[ "$DEV_MODE" == false || ! -d "$docset" ]]; then
        "$ROOT/generate.sh" "$lang" "$@" --output "$OUTPUT" || {
            msg_error "Failed to generate Dash docset for language: $lang"
            continue
        }
    fi

    docset_bundle_name=$(get_docset_bundle_name "$docset")
    if [[ -z "$docset_bundle_name" ]]; then
        msg_error "Failed to obtain docset bundle name."
        continue
    fi
    msg_sub "$docset_filename bundle name: $docset_bundle_name"

    localized_manual_title=$(xmllint --html --xpath 'string(//title[1])' \
        "$docset/Contents/Resources/Documents/index.html" 2>/dev/null) || {
        msg_error "Failed to obtain localized manual title."
        continue
    }
    msg_sub "$docset_filename localized manual title: $localized_manual_title"

    msg_sub "Obtaining the docset version..."
    version=$(get_docset_version "$docset")
    if [[ -z "$version" ]]; then
        msg_error "Failed to obtain the docset version."
        continue
    fi
    msg_sub "$docset_filename version: $version"

    msg_sub "Archiving ${docset_filename}..."
    (
        cd "$OUTPUT"
        rm -rf "$docset_archive"
        tar --exclude='.DS_Store' --exclude='optimizedIndex.dsidx' -czf "$docset_archive" "$docset_filename"
    ) || {
        msg_error "Failed to archive $docset_filename"
        continue
    }
    msg_sub "Archived $docset_filename to $docset_archive"

    msg_sub "Updating $docset_archive in the fork repository..."
    (
        cd "$fork_path"

        root="docsets/$docset_name"
        mkdir -p "$root"

        cp -f "$OUTPUT/$docset_archive" "$root/"
        cp -f "$docset/icon.png" "$root/"
        cp -f "$docset/icon@2x.png" "$root/"
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

        jq --indent 4 --arg title "$localized_manual_title" \
            '.aliases |= (if index($title) then . else . + [$title] end)' "$root/docset.json" \
            > temp.json && mv temp.json "$root/docset.json"

        cat "$root/docset.json"

        git add -A "$root"
    ) || {
        msg_error "Failed to update $docset_archive in the fork repository."
        continue
    }

    if ! git -C "$fork_path" diff --cached --quiet -- "docsets/$docset_name"; then
        pr_body+=$'\n'"| ${docset_bundle_name} | \`${version}\` |"
    fi
done

if git -C "$fork_path" diff --cached --quiet; then
    msg_main "No changes detected, skipping pull request creation."
    exit 0
fi

(
    cd "$fork_path"
    git commit -m "$commit_message"
    git push -u origin "$branch"
)

msg_main "Creating pull request on ${UPSTREAM_REPO}..."
if ! pr_url=$(gh pr create \
    --repo "$UPSTREAM_REPO" \
    --base master \
    --title "$commit_message" \
    --body "$pr_body" \
    --head "$fork_owner:$branch"
); then
    msg_error "Failed to create pull request."
    exit 9
fi
msg_sub "Pull request created: $pr_url"
