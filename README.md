# PHP Manual Dash Docset Generator

Generate [Dash](https://kapeli.com/dash) docsets for the official [PHP Manual](https://www.php.net/docs.php) in multiple languages, or build a complete php.net mirror locally.

## Features

- **Multi-language support** — build docsets for all active PHP documentation translations.
- **Comprehensive index coverage**, including:
  - Classes, Interfaces, Enums, Exceptions
  - Methods, Functions, Keywords, Variables, Types, Operators
  - Extensions, Guides
  - Constants, Settings, Properties
- **Optional exclusion of user-contributed notes** for cleaner reference sets.
- **Automatic repository updates** from official PHP sources.
- **Cross-platform support** (macOS and Linux).
- **Customizable output directory** and **verbose mode** for debugging.

## Usage

```bash
./generate.sh [LANG...] [OPTIONS]

Arguments:
  LANG          Language code(s) for the PHP Manual to generate.
                You can specify multiple languages separated by space.
                Supported languages: en de es fr it ja pt_BR ru tr uk zh
                (default: 'en')

Options:
  --mirror          Generate a php.net mirror instead of docsets.
  --no-usernotes    Exclude user-contributed notes from the manual.
  --skip-update     Skip cloning or updating PHP doc repositories.
  --output <dir>    Specify the output directory (default: './output').
  --verbose         Display verbose output.
  help, -h, --help  Display this help message.
```

## Examples

Generate English docset:

```bash
./generate.sh

# or:
./generate.sh en
```

Generate multiple languages:

```bash
./generate.sh en zh fr
```

Generate php.net mirror:

```bash
./generate.sh en zh fr --mirror
```

Exclude user-contributed notes:

```bash
./generate.sh en zh --no-usernotes
```

## Output

- Dash docsets are generated under:
  ```
  output/PHP_<lang>.docset
  ```
- php.net mirror will be located at:
  ```
  output/php.net
  ```
  You can run a local server:
  ```bash
  (cd output/php.net && php -S localhost:8080 .router.php)
  ```

## Requirements

- macOS / Linux
- PHP (>= 8.2 recommended)
- `git`
- `sqlite3`
- `xmllint`
- `rsync`, `wget` — required only for generating a php.net mirror

## License

[MIT License](LICENSE) © Elf Sundae

This project is independent of php.net but built entirely on its official documentation sources.

## Contributing

Pull requests are welcome! You can improve indexing rules, or enhance the build process.
