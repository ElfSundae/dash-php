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

## Installing pre-generated PHP docsets

You can install the prebuilt and automatically updated PHP docsets directly in [Dash](https://kapeli.com/dash) or [Zeal](https://zealdocs.org) by adding the following feed URLs:

| Docset                     | Feed URL                                                                                                               | Install                          |
| -------------------------- | ---------------------------------------------------------------------------------------------------------------------- | -------------------------------- |
| PHP (English)              | <https://elfsundae.github.io/dash-php/feed/PHP_-_English.xml><br>[![Version Badge][badge_en]][release]                 | 📚 [Add to Dash][install_en]    |
| PHP (Español)              | <https://elfsundae.github.io/dash-php/feed/PHP_-_Spanish.xml><br>[![Version Badge][badge_es]][release]                 | 📚 [Add to Dash][install_es]    |
| PHP (Français)             | <https://elfsundae.github.io/dash-php/feed/PHP_-_French.xml><br>[![Version Badge][badge_fr]][release]                  | 📚 [Add to Dash][install_fr]    |
| PHP (Italiano)             | <https://elfsundae.github.io/dash-php/feed/PHP_-_Italian.xml><br>[![Version Badge][badge_it]][release]                 | 📚 [Add to Dash][install_it]    |
| PHP (日本語)               | <https://elfsundae.github.io/dash-php/feed/PHP_-_Japanese.xml><br>[![Version Badge][badge_ja]][release]                | 📚 [Add to Dash][install_ja]    |
| PHP (Português Brasileiro) | <https://elfsundae.github.io/dash-php/feed/PHP_-_Brazilian_Portuguese.xml><br>[![Version Badge][badge_pt_BR]][release] | 📚 [Add to Dash][install_pt_BR] |
| PHP (Русский)              | <https://elfsundae.github.io/dash-php/feed/PHP_-_Russian.xml><br>[![Version Badge][badge_ru]][release]                 | 📚 [Add to Dash][install_ru]    |
| PHP (Türkçe)               | <https://elfsundae.github.io/dash-php/feed/PHP_-_Turkish.xml><br>[![Version Badge][badge_tr]][release]                 | 📚 [Add to Dash][install_tr]    |
| PHP (Українська)           | <https://elfsundae.github.io/dash-php/feed/PHP_-_Ukrainian.xml><br>[![Version Badge][badge_uk]][release]               | 📚 [Add to Dash][install_uk]    |
| PHP (简体中文)             | <https://elfsundae.github.io/dash-php/feed/PHP_-_Simplified_Chinese.xml><br>[![Version Badge][badge_zh]][release]      | 📚 [Add to Dash][install_zh]    |

[release]: https://github.com/ElfSundae/dash-php/releases/tag/docsets
[badge_en]: https://img.shields.io/endpoint?url=https%3A%2F%2Felfsundae.github.io%2Fdash-php%2Fshields%2FPHP_en.json
[badge_es]: https://img.shields.io/endpoint?url=https%3A%2F%2Felfsundae.github.io%2Fdash-php%2Fshields%2FPHP_es.json
[badge_fr]: https://img.shields.io/endpoint?url=https%3A%2F%2Felfsundae.github.io%2Fdash-php%2Fshields%2FPHP_fr.json
[badge_it]: https://img.shields.io/endpoint?url=https%3A%2F%2Felfsundae.github.io%2Fdash-php%2Fshields%2FPHP_it.json
[badge_ja]: https://img.shields.io/endpoint?url=https%3A%2F%2Felfsundae.github.io%2Fdash-php%2Fshields%2FPHP_ja.json
[badge_pt_BR]: https://img.shields.io/endpoint?url=https%3A%2F%2Felfsundae.github.io%2Fdash-php%2Fshields%2FPHP_pt_BR.json
[badge_ru]: https://img.shields.io/endpoint?url=https%3A%2F%2Felfsundae.github.io%2Fdash-php%2Fshields%2FPHP_ru.json
[badge_tr]: https://img.shields.io/endpoint?url=https%3A%2F%2Felfsundae.github.io%2Fdash-php%2Fshields%2FPHP_tr.json
[badge_uk]: https://img.shields.io/endpoint?url=https%3A%2F%2Felfsundae.github.io%2Fdash-php%2Fshields%2FPHP_uk.json
[badge_zh]: https://img.shields.io/endpoint?url=https%3A%2F%2Felfsundae.github.io%2Fdash-php%2Fshields%2FPHP_zh.json
[install_en]: https://elfsundae.github.io/dash-php/feed/?lang=en "Add PHP (English) docset feed to Dash"
[install_es]: https://elfsundae.github.io/dash-php/feed/?lang=es "Add PHP (Español) docset feed to Dash"
[install_fr]: https://elfsundae.github.io/dash-php/feed/?lang=fr "Add PHP (Français) docset feed to Dash"
[install_it]: https://elfsundae.github.io/dash-php/feed/?lang=it "Add PHP (Italiano) docset feed to Dash"
[install_ja]: https://elfsundae.github.io/dash-php/feed/?lang=ja "Add PHP (日本語) docset feed to Dash"
[install_pt_BR]: https://elfsundae.github.io/dash-php/feed/?lang=pt_BR "Add PHP (Português Brasileiro) docset feed to Dash"
[install_ru]: https://elfsundae.github.io/dash-php/feed/?lang=ru "Add PHP (Русский) docset feed to Dash"
[install_tr]: https://elfsundae.github.io/dash-php/feed/?lang=tr "Add PHP (Türkçe) docset feed to Dash"
[install_uk]: https://elfsundae.github.io/dash-php/feed/?lang=uk "Add PHP (Українська) docset feed to Dash"
[install_zh]: https://elfsundae.github.io/dash-php/feed/?lang=zh "Add PHP (简体中文) docset feed to Dash"

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
