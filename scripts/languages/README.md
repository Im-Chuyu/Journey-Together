# Language submissions

This directory is the translation area of the project. A language submission
can add shared files and optional character-specific files:

```text
scripts/languages/<code>/command_words.lua
scripts/languages/<code>/dialogue_lines.lua
scripts/languages/<code>/characters/<character>.lua
scripts/languages/<code>/characters/<character>_command_words.lua
```

Use `zh`, `en`, and `ru` as references. Keep command `id` values and dialogue
keys unchanged. A language file contains only one language. Chinese is the
fallback when a file is missing.

Character command files use stable command `id` values plus localized
`keywords` and a wheel `label`. Contributors should submit these files through
a pull request. Do not edit
`modmain.lua`, AI behavior files, or the language loader for a translation.
The maintainer reviews and merges the files, then adds the language option to
`modinfo.lua` before releasing it in the mod.
