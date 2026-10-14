# Icesus Effects

A Mudlet package for [Icesus](https://icesus.org) that tracks your
spell and skill effects from their game messages. Each effect gets a
floating button on the right edge of the main console. Timed effects
also get a draining bar, the elapsed time, and an expiry estimate.

It is separate from the official Icesus HUD package and works with or
without it. When the HUD is loaded, this package uses the HUD's
colours and font and stays to the left of the HUD's right-hand column.

```
┌───────────────────────────────────┐
│ Essence of the nether 2:30 / ~5:00│   active, estimate known
│ ▬▬▬▬▬▬▬▬▬▬▬▬▬▬                    │
├───────────────────────────────────┤
│ Stone skin                        │   no duration: name only
├───────────────────────────────────┤
│ Blessing (struck through)    4:58 │   expired: dimmed, how long it lasted
└───────────────────────────────────┘
```

## Install

Paste this into Mudlet's command line:

```
lua installPackage("https://github.com/destor/icefx/releases/latest/download/IcesusEffects.mpackage")
```

To install a release by hand instead, download `IcesusEffects.mpackage`
from the [latest release](https://github.com/destor/icefx/releases/latest).
In Mudlet, open `Toolbox → Package Manager → Install` and choose the
file.

To install your own build, run `./build/build.sh` and install
`dist/IcesusEffects.mpackage` the same way.

## Updating

`icefx update` checks GitHub for the latest release. If that release is
newer than the version you have, it downloads and installs it.
Otherwise it tells you that you're up to date.

`icefx reload` reinstalls the package. You can tell it where to
install from:

| command | installs from |
| ------- | ------------- |
| `icefx reload` | the file or URL saved last time, or the latest release if nothing is saved |
| `icefx reload latest` | the latest release; the saved file or URL stays saved |
| `icefx reload <file or URL>` | that `.mpackage` file or `https://` URL, which is then saved for next time |

The package downloads a URL before it uninstalls anything. If the
download fails, the version you have keeps running. Reloading keeps
your effects, recorded runs, settings and active effects.

## How it works

Each effect has three kinds of message. A message is the start of one
line of game output. It only matches when the line begins with it, so
the same words inside a say or a channel line don't set it off:

| kind      | what it does |
| --------- | ------------ |
| `on`      | Starts the effect. If the effect is already active, this counts as a refresh. |
| `refresh` | Restarts the clock. The package assumes a refresh restores the full duration. |
| `off`     | Ends the effect. For a timed effect, the time since the last start or refresh is saved as one run. |

**Estimate.** The estimate is the average of the last 10 saved runs.
The first time you use an effect there are no runs yet, so the button
shows `1:05 / ?`. After the first expiry it shows `1:05 / ~5:00`.
Runs are saved in `IcesusEffects.lua` in your profile directory
(`lua getMudletHomeDir()` prints the path), so estimates are kept
between sessions. The package does not save a run in these cases:
- it never saw the effect start;
- the effect lasted less than 2 seconds;
- the effect has no timer.

**Bar.** The bar shows the estimated time remaining. It is green, then
amber, then red as the effect nears expiry. When an effect runs past
its estimate, the time turns amber and the bar is empty.

**Expired effects.** An expired effect stays on screen, dimmed and
struck through, until you click it or type `icefx clear`. When you start
it again, the same button becomes active again.

**Multi-line messages.** The game wraps long messages over several
lines, and a message can only match one line. Use the beginning of the
first line. For example, the start message of Essence of the nether is
matched by `You are suddenly enveloped into coldness of netherplane`.

**Lines that start with a name.** Some messages begin with whoever cast
the spell, for example `Kili creates a subdimensional rift around you…`.
Plain text can't match those, so use a regex:
`re:^[A-Z][a-z]+ creates a subdimensional rift around you`. A regex is
used exactly as written. Start it with `^` to keep it bound to the
start of the line.

## Adding effects

The package includes these effects:

- Aspect of elements
- Elemental shield of water
- Embrace of the rimewind
- Essence of the nether
- Flagellation
- Fleshcraft
- Gift of elements
- Haste
- Inertia bubble
- Life boost
- Mantle of darkness
- Martyrdom
- Presence of the dark master
- Senses of a beast
- Shadow barrier
- Slow
- Spectral claws
- Sphere of protection
- Sphere of warding
- Thirst for knowledge
- Unfold mind

Many of their messages come from
[IceTF](https://github.com/icekili/IceTF), Kili's TinyFugue scripts for
Icesus. The ones from IceTF haven't been checked against the current
game, so a message may have changed since. If an effect doesn't start
or stop when it should, fix the message with `icefx config`.

You add other effects with `icefx add` and give them messages with
`icefx config`:

```
icefx add Stone skin
icefx config stone effect.on="Your skin turns to stone." effect.off="Your skin softens."
icefx config stone effect.timed=false        (only if the effect has no duration)
```

Wherever a command takes `<effect>`, you can type its number in
`icefx list`, its name, or any unambiguous start of the name (`stone`,
`ess`). To use a regex instead of plain text, start the message with
`re:`, for example `icefx config stone effect.off="re:^Your skin (softens|cracks)"`.

To check which messages a line matches without waiting for it in the
game, paste the line into `icefx test`:

```
icefx test You feel essence of the nether leave your body.
```

## Settings

`icefx config <effect> <setting>=<value>` changes a setting, and you can
change several at once. `icefx set` does the same thing.
`icefx show <effect>`, or `icefx config <effect>` with nothing after it,
lists every setting in a form you can copy back into `icefx config`.

| setting | value |
| ------- | ----- |
| `effect.label` | display name |
| `effect.timed` | `true` if the effect has a duration |
| `effect.on`, `effect.refresh`, `effect.off` | messages, see below |
| `alert.flash` | `true`: the button flashes red for 5 s when the effect falls off |
| `alert.banner` | `true`: a banner appears in the middle of the console when it falls off, and when it reaches the warning time |
| `alert.warn` | seconds, or `off`: the button pulses amber from this long before the estimated end until you refresh the effect or it falls off |

Each message setting holds a list:

```
icefx config 1 effect.on="text"       replace the list with this one message
icefx config 1 effect.on+="text"      add a message
icefx config 1 effect.on.2="text"     replace message 2
icefx config 1 effect.on.2=           remove message 2
icefx config 1 effect.on=             remove all start messages
```

Quotes are needed only when the value contains spaces. A quoted value
ends at the last quote before the next setting, so a message that
contains quotes doesn't need escaping.

`alert.warn` needs an estimate, so it starts working after the
effect's first recorded run. It counts from the estimate, so when
runs vary in length, leave some margin.

```
icefx config essence alert.warn=15 alert.banner=on
```

## All commands

`icefx` on its own prints this list.

```
icefx list                         effects, estimates, on/off
icefx show <effect>                all its settings and recorded runs
icefx add <name>                   define a new effect
icefx remove <effect>              delete it
icefx config <effect> <setting>=<value> ...
                                   change settings
icefx activate|deactivate <effect> force it on or off
icefx reset                        everything off, all buttons gone
icefx reset-to-baseline            back to a fresh install (see below)
icefx sync                         run `effects` and match it
icefx clear                        dismiss expired buttons
icefx forget <effect>              wipe its recorded runs
icefx migrate [<effect>|all]       compare built-ins with the package / take its version
icefx test <line>                  which messages a line matches
icefx update                       install the latest release if it is newer
icefx reload [latest|<file>|<url>] reinstall (see Updating)
```

## Fixing the state by hand

If a message is missed, use `icefx activate` or `icefx deactivate` to
correct an effect, or `icefx reset` to turn everything off. In these
cases the package doesn't know when the effect really started. The
button then shows the elapsed time as a minimum (`≥1:05 / ~5:00`), and
the run isn't saved. The next refresh message restarts the clock from a
known point, and runs are saved normally again.

## Package updates and built-in effects

The first time the package loads a built-in effect, it copies that
effect into your own definitions, and from then on only your copy is
used. So an update never overwrites your changes. It also means fixes
to a built-in's messages don't reach you automatically.

When an update changes a built-in effect and your copy no longer
matches the new version, the package says so once, when it loads:

```
[icefx] the package changed 1 built-in effect(s) you have: Essence of the nether — icefx migrate to compare
```

`icefx migrate` lists every built-in whose copy differs from the
package, with the differences:

```
 1  Essence of the nether
      effect.label  Essence → Essence of the nether
      effect.off  - Extra off.
      effect.off  + You feel essence of the nether leave your body.
```

`-` marks a message only your copy has, and `+` marks a message only
the package has. To take the package's version, use `icefx migrate 1`
(or the effect's name) for one effect, or `icefx migrate all` for all
of them. Migration replaces the label, the timed setting and the
messages. Recorded runs and alert settings are kept.

The list also includes effects you changed on purpose, so you can
ignore those. The load message only appears when the package's version
of an effect has changed since the last load. New built-in effects are
added automatically. Built-in effects you removed stay removed.

## Starting over

`icefx reset-to-baseline` puts the saved data back to how a fresh
install starts:
- only the built-in effects, with their shipped messages;
- no recorded runs;
- no alert settings;
- nothing active.

Effects you added are deleted, and built-in effects you removed come
back. The command name is long on purpose, so you don't run it by
accident.

Before the reset, the old data is saved to `IcesusEffects.backup.lua`
in your profile directory. To undo the reset, copy that file over
`IcesusEffects.lua` and run `icefx reload`. The saved `icefx reload`
source is kept.

## Syncing with `effects`

`icefx sync` sends the game's `effects` command. Typing `effects`
yourself does the same thing. The package rewrites the output into
columns:

```
Beneficial effects affecting you:
 ON   Mantle of darkness             3:29 / ?
 ON   Fleshcraft
 ON   Essence of the nether          3:35 / ~9:24
No visible harmful effects affect you.
Tracked, now off:
 OFF  Presence of the dark master    ended 2:10 ago
```

- The game's own lines are replaced by `ON` rows with the elapsed time
  and the estimate. Effects without a timer have an empty time column.
  If an effect isn't being tracked yet, the elapsed time shows as `?`.
- The "Tracked, now off" rows list effects the package has seen this
  session that the game no longer shows. `dropped` means the package
  still had the effect on, so this sync turns it off.
- These rows come straight after `No visible harmful effects affect
  you.` If the game lists harmful effects, the rows appear after the
  listing ends instead, below the next prompt. Mudlet can't add lines
  in the middle of game output.

The tracker is then updated to match the output:
- Effects in the list are turned on.
- Active effects missing from the list are turned off.
- Names the package hasn't seen before are added as new effects, with
  no messages yet. Give them messages with `icefx config`.

The package prints a sync line only when something changed. `icefx
sync` always prints a line.

## For script writers

The package raises these Mudlet events. Each event's argument is the
effect's key, which is its lower-case name:

- `icesusfx.on`
- `icesusfx.refresh`
- `icesusfx.off`

```lua
registerAnonymousEventHandler("icesusfx.off", function(_, key)
  if key == "essence of the nether" then send("invoke essence of the nether") end
end)
```

Layout settings are in `icesusfx.config`: `width`, `rowH`, `gap`,
`marginRight`, `maxSamples` and others.

## Development

```
luajit tests/test_effects.lua   # unit tests, mocked Mudlet API (Mudlet runs Lua 5.1)
./build/build.sh                # dist/IcesusEffects.mpackage
```

After a rebuild, run `icefx reload <path to dist/IcesusEffects.mpackage>`
in Mudlet. The path is saved, so after that `icefx reload` is
enough. Your effect definitions, saved runs and active effects are kept.

The source is in `src/`, as four files that load in this order:

| file | what it holds |
| ---- | ------------- |
| `builtins.lua` | the effects that ship with the package (`fx.BUILTIN`); data only |
| `data.lua` | effect definitions, saved runs and estimates, on/off state; no Mudlet UI |
| `ui.lua` | the floating buttons: what each one shows (`fx.view`) and the Geyser widgets (`fx.render`) |
| `controller.lua` | triggers, the `effects` listing, `icefx` commands, install and teardown |

Functions in `data.lua` only change state. The controller calls
`fx.render()` after each change. The build script wraps the four
files and the `icefx` alias into the package XML.

## License

MIT, see [LICENSE](LICENSE).
