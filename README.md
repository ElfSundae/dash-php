# PHP Dash Docset Generator

This project provides a Bash script to generate [Dash](https://kapeli.com/dash) docset for the [PHP Manual](https://www.php.net/docs.php) in multiple languages.

## Features

- Supports multiple languages: English, Chinese, French, German, Japanese, etc.
- Automatically fetches and updates official PHP documentation repositories.
- Creates fully functional Dash docsets with search indexes.
- Optional local php.net mirror generation with images, styles, and backend files.

## Usage

```bash
# Generate the English docset
./generate.sh

# Generate Simplified Chinese docset
./generate.sh zh

# Generate docset and php.net mirror
./generate.sh zh --mirror

# Display help
./generate.sh -h
```

## Requirements

- macOS / Linux
- PHP (>= 8.2 recommended)
- sqlite3
- git
- wget
