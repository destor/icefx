# AGENTS.md

This file is for coding agents and contributors working on this
repository. [README.md](README.md) is the user-facing documentation.

## What this is

A Mudlet package for the Icesus MUD that tracks spell and skill
effects from their game messages. Each effect gets a floating button on
the right edge of the main console. The package learns how long each
effect lasts from previous runs, can alert when an effect falls off,
and rewrites the game's `effects` output into a table. It is separate
from the official Icesus HUD package (`../icesus-hud`). When the HUD is
loaded, this package uses the HUD's `icesus.palette` and
`icesus.fontStack` and follows the console borders the HUD sets.

## Commands

```sh
luajit tests/test_effects.lua   # unit tests; exits non-zero on failure
./build/build.sh                # builds dist/IcesusEffects.mpackage
```

Run both after every change. To try a build in Mudlet, run
`icefx update <path to dist/IcesusEffects.mpackage>` once. The path is
saved, so after that plain `icefx update` is enough. Without a saved
source, `icefx update` installs the latest GitHub release if it is
newer. (`icefx reload` is the old name for the same command.)

Reload and update fetch URLs with `downloadFile` and only uninstall
once the download has succeeded. Keep it that way: an uninstall
followed by a failed download leaves the player with no package.

## Layout

| path | role |
| ---- | ---- |
| `src/builtins.lua` | data only: the shipped effects, `fx.BUILTIN`, with the format documented at the top |
| `src/data.lua` | model: definitions, seeding built-ins, persistence, estimates, live state, settings (`fx.setSetting`), migration |
| `src/ui.lua` | view: `fx.view` (what a button shows, as plain data), Geyser widgets (`fx.render`), banner, `effects` table rows |
| `src/controller.lua` | wiring: triggers, `effects` listing parser, alerts, `icefx` command, install and teardown |
| `build/build.sh` | wraps `src/*.lua` and the `icefx` alias into `IcesusEffects.xml`, then zips it with `package/config.lua` |
| `tests/test_effects.lua` | loads the four source files under a mocked Mudlet API |

Mudlet runs the four files in the order listed in `SOURCES` in
`build/build.sh`: builtins, data, ui, then controller. They share the
global `icesusfx` table, and each file starts with
`local fx = icesusfx`.

To ship a new effect, add an entry to `src/builtins.lua`, tagged with
the guild or race it comes from, and nothing else. Players get new entries on their next load. Changes to an existing
entry reach players only through `icefx migrate`.

## Rules

- **Lua 5.1.** Mudlet embeds Lua 5.1, so don't use `//`, `goto`,
  `table.unpack` or integer-division idioms. Use `unpack` and
  `math.floor`. LuaJIT runs the tests for the same reason.
- **Keep the layers separate.**
  - `data.lua` never calls Mudlet UI or trigger APIs and never calls
    `fx.render()`.
  - `ui.lua` changes state only through functions in `data.lua`, for
    example `fx.dismiss`.
  - The controller calls `fx.render()` after every state change.
- **Commands don't edit `fx.data` directly.** Add a function to
  `data.lua` and call that.
- **Saved data must stay compatible.** `fx.data` is saved to
  `<profile>/IcesusEffects.lua` with `table.save`. `fx.load` must
  accept files written by older versions: check each field's type and
  fall back to a default. Never rename a saved field without migrating
  it.
- **Built-ins are copied into the player's data once**, tracked by
  `fx.data.seeded`. Editing `fx.BUILTIN` doesn't change existing
  profiles. Instead, `fx.checkShipped` notices the change and players
  update with `icefx migrate`. Don't add code that overwrites the
  player's definitions.
- **Re-runs must be safe.** The controller calls `fx.teardown()` before
  `fx.install()`. Anything new that install creates (a trigger, timer,
  event handler or widget) must also be removed in `fx.teardown`.
  Temp triggers go into `fx.triggerIds`.
- **No `]]>` in source files.** The build places them in XML CDATA
  blocks and refuses to build if one is found.
- **Messages are bound to the start of a sentence.**
  - Mudlet runs triggers on the whole line the game sent, before
    wrapping it for display, and the game often puts a spell's flavour
    text and its effect message on one line. So a message can't be
    required at the start of the line.
  - `fx.messageRegex` prefixes every message with `fx.SENTENCE_START`
    (line start, or after `. `, `! ` or `? `). That keeps say, tell and
    channel lines from firing it.
  - A leading `^` in a `re:` message is replaced by the same prefix.
    Shipped regexes start with `^`.
  - Every message runs as a `tempRegexTrigger`.

## Tests

- **Mock new Mudlet calls.** The test file mocks every Mudlet function
  the package uses: Geyser widgets record their position, size, style,
  text and visibility. `deliver(line)` runs a line through the
  triggers, using a small stand-in for PCRE (`rex.match`). The stand-in
  raises an error on regex features it doesn't support, rather than
  silently not matching. A new Mudlet API call needs a mock in the test file,
  or the suite crashes.
- **Time.** The clock is `W.clock`; advance it by hand.
- **Built-ins change.** The player edits `fx.BUILTIN` directly, so
  tests must not assume a fixed set of built-ins or a fixed trigger
  count. Use `patternCount(fx)`, or delete the data file and `boot()`
  again.
- **Persistence.** To test saving and loading, call `boot()` again,
  which re-runs all four files against the same profile directory.

## Releasing

`.github/workflows/build.yml` runs on every push to `main` and on every
pull request. It runs the tests, builds the package, and uploads it as
a workflow artifact.
`dist/` is gitignored, so built packages are never committed.

To publish a release:

1. Bump `fx.version` in `src/data.lua`. That is the only copy: the
   build writes it into the package's `config.lua` in place of
   `@VERSION@`, so don't put a version in `package/config.lua`.
2. Commit, then tag the commit with `v` plus the version and push the
   tag, e.g. `git tag v0.4.0 && git push origin v0.4.0`. CI fails if the
   tag doesn't match the version.
3. The `release` job creates a GitHub Release with
   `IcesusEffects.mpackage` attached. The install URL in the README,
   `releases/latest/download/IcesusEffects.mpackage`, then serves the
   new release.

Update `README.md` whenever user-visible behaviour or commands change.
Commands and their help are one table, `fx.COMMANDS` in
`controller.lua`: dispatch and `icefx help` are built from it, so a new
command is one entry there. `main = true` puts it in plain `icefx`;
keep that set short. Old command names go in `aliases`, not in the
help. The settings list is `SETTING_HELP`. Keep both in sync with the
README command list.
