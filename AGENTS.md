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

Run both after every change. In Mudlet, run `icefx reload` to
reinstall the package from the built file.

## Layout

| path | role |
| ---- | ---- |
| `src/data.lua` | model: definitions, built-ins (`fx.BUILTIN`), persistence, estimates, live state, settings (`fx.setSetting`), migration |
| `src/ui.lua` | view: `fx.view` (what a button shows, as plain data), Geyser widgets (`fx.render`), banner, `effects` table rows |
| `src/controller.lua` | wiring: triggers, `effects` listing parser, alerts, `icefx` command, install and teardown |
| `build/build.sh` | wraps `src/*.lua` and the `icefx` alias into `IcesusEffects.xml`, then zips it with `package/config.lua` |
| `tests/test_effects.lua` | loads the three source files under a mocked Mudlet API |

Mudlet runs the three files in the order listed in `SOURCES` in
`build/build.sh`: data, then ui, then controller. They share the global
`icesusfx` table, and each file starts with `local fx = icesusfx`.

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
- **Messages are plain substrings of one line by default**, matched by
  `tempTrigger`. A `re:` prefix makes the message a PCRE regex, matched
  by `tempRegexTrigger`. The game wraps long messages, so match part of
  the first line.

## Tests

- **Mock new Mudlet calls.** The test file mocks every Mudlet function
  the package uses: Geyser widgets record their position, size, style,
  text and visibility, and triggers are matched by substring with
  `deliver(line)`. A new Mudlet API call needs a mock in the test file,
  or the suite crashes.
- **Time.** The clock is `W.clock`; advance it by hand.
- **Built-ins change.** The player edits `fx.BUILTIN` directly, so
  tests must not assume a fixed set of built-ins or a fixed trigger
  count. Use `patternCount(fx)`, or delete the data file and `boot()`
  again.
- **Persistence.** To test saving and loading, call `boot()` again,
  which re-runs all three files against the same profile directory.

## Releasing

`.github/workflows/build.yml` runs on every push to `main` and on every
pull request. It checks that the two version numbers agree, runs the
tests, builds the package, and uploads it as a workflow artifact.
`dist/` is gitignored, so built packages are never committed.

To publish a release:

1. Bump the version in both `package/config.lua` (`version`) and
   `src/data.lua` (`fx.version`). CI fails if the two differ.
2. Commit, then tag the commit with `v` plus the version and push the
   tag, e.g. `git tag v0.4.0 && git push origin v0.4.0`. CI fails if the
   tag doesn't match the version.
3. The `release` job creates a GitHub Release with
   `IcesusEffects.mpackage` attached. The install URL in the README,
   `releases/latest/download/IcesusEffects.mpackage`, then serves the
   new release.

Update `README.md` whenever user-visible behaviour or commands change.
The `icefx` help text is the `HELP` table in `controller.lua`; keep it
in sync with the README command list.
