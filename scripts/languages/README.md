# Language submissions

This directory is the translation area of the project. A language submission
only adds two files in one folder:

```text
scripts/languages/<code>/command_words.lua
scripts/languages/<code>/dialogue_lines.lua
```

Use `zh` and `en` as references. Keep command `id` values and dialogue keys
unchanged. A language file contains only one language. Chinese is the fallback
when a file is missing.

Contributors should submit these files through a pull request. Do not edit
`modmain.lua`, AI behavior files, or the language loader for a translation.
The maintainer reviews and merges the files, then adds the language option to
`modinfo.lua` before releasing it in the mod.
