-- =============================================================
-- Icesus Effects — builtins.lua: the effects that ship with the
-- package. Data only; loaded first.
--
-- Each built-in is copied into the player's own definitions the first
-- time the package sees it (data.lua, fx.seedBuiltins), and the copy
-- is what runs from then on. Changing an entry here therefore reaches
-- existing players only through `icefx migrate`; a new entry is added
-- for them automatically on the next load.
--
-- Entry fields:
--   label    the name as the game's `effects` command lists it; the
--            key is the same name in lower case
--   timed    true when the effect has a duration to learn
--   on, refresh, off
--            messages. Each is the START of a sentence of game output:
--            plain text matches at the start of a line or right after
--            ". ", "! " or "? " (fx.SENTENCE_START), so the same words
--            in a say or a channel line don't fire it. Mudlet matches
--            the whole line the game sent, before wrapping it for
--            display, and a spell's flavour text often comes first on
--            the same line. "re:" makes it a PCRE regex, where a leading
--            ^ means a sentence start too. A sentence that begins with
--            someone's name needs a regex: "re:^[A-Z][a-z]+ creates a
--            ...". The beginning of a long message is enough.
--
-- Messages in the IceTF section are from IceTF, Kili's TinyFugue
-- scripts for Icesus (https://github.com/icekili/IceTF,
-- icetf-effects.tf), turned into this format.
-- =============================================================
icesusfx = icesusfx or {}
local fx = icesusfx

fx.BUILTIN = {
  -- Scions

  ["essence of the nether"] = {
    label   = "Essence of the nether",
    timed   = true,
    on      = { "You are suddenly enveloped into coldness of netherplane" },
    refresh = { "Essence of the nether around you rapidly replenishes its power." },
    off     = { "You feel essence of the nether leave your body." },
  },
  ["fleshcraft"] = {
    label   = "Fleshcraft",
    timed   = false,
    on      = { "Rapidly your fingers lengthen and become razor-sharp tools of destruction." },
    refresh = {},
    off     = { "By using fleshcraft you turn your lengthened, razor-sharp fingers rapidly back to normal shape." },
  },
  ["mantle of darkness"] = {
    label   = "Mantle of darkness",
    timed   = true,
    on      = { "Shadows around you flicker and grow and start moving like a pitch black ooze spreading itself" },
    refresh = { "Shadows around you take tighter grasp of you." },
    off     = { "Shadows enveloping you disperse." },
  },
  ["presence of the dark master"] = {
    label   = "Presence of the dark master",
    timed   = true,
    on      = { "Air around you ripples for a second with dark energies as you connect to the netherplane and a" },
    refresh = {},
    off     = { "Your overpowering presence fades away." },
  },

  -- Priest of air
  ["life boost"] = {
    label   = "Life boost",
    timed   = true,
    on      = { "re:^You feel (much )?safer\\." },
    refresh = {},
    off     = { "The life boost fades, making you feel threatened." },
  },

  -- Teaching of elements
  ["aspect of elements"] = {
    label   = "Aspect of elements",
    timed   = true,
    on      = { "You open your mouth and utter 'Adefyv Peiadc'" },
    refresh = { "You replenish elemental aspect." },
    off     = { "You turn back into your normal form." },
  },
  ["gift of elements"] = {
    label   = "Gift of elements",
    timed   = true,
    on      = {
      "The essence of Pthuule fills your spirit and you feel gifted",
      "The essence of Dhubr fills your spirit and you feel gifted",
    },
    refresh = {},
    off     = { "You feel a loss as gift of elements ceases to affect you." },
  },

  -- Sorcerer
  ["sphere of protection"] = {
    label   = "Sphere of protection",
    timed   = true,
    on      = { "A smoky, red-hued sphere of protection surrounds you." },
    refresh = {},
    off     = { "The sphere of protection around your body fades away." },
  },
  ["sphere of warding"] = {
    label   = "Sphere of warding",
    timed   = true,
    on      = { "A crystal-clear sphere of warding surrounds you." },
    refresh = { "re:^Your sphere of warding glimmers a second as [A-Z][a-z]+ replenishes it\\." },
    off     = { "The sphere of warding around you fades away." },
  },

  -- Priest of water
  ["thirst for knowledge"] = {
    label   = "Thirst for knowledge",
    timed   = true,
    on      = { "You feel sudden thirst for new knowledge and feel a bit wiser." },
    refresh = {},
    off     = { "You don't feel so interested about new things anymore." },
  },
  ["embrace of the rimewind"] = {
    label   = "Embrace of the rimewind",
    timed   = true,
    on      = { "Massive glacial gales heed your call and start to blow" },
    refresh = {},
    off     = { "The glacial winds howling around you settle." },
  },

  -- Gaesati shapeshifters
  ["spectral claws"] = {
    label   = "Spectral claws",
    timed   = true,
    on      = {
      "Suddenly the air around your claws turns extremely chilly!",
      "Suddenly your claws burst into fire!",
      "Suddenly your claws start to crackle as lightning field",
      "Suddenly corrosive acid starts dripping from your claws!",
    },
    refresh = {},
    off     = { "Your claws turn normal as your spell ends." },
  },
  ["senses of a beast"] = {
    label   = "Senses of a beast",
    timed   = true,
    on      = { "Suddenly your vision flashes for a second but then returns" },
    refresh = {},
    off     = { "Your eyes tickle for a second and you notice that your abnormal" },
  },

  -- Templars
  ["elemental shield of water"] = {
    label   = "Elemental shield of water",
    timed   = true,
    on      = { "Your skin gets a blue hue as a layer of elemental energy" },
    refresh = {},
    off     = { "The hue of blue disappears from your skin as the layer of" },
  },

  -- Priest of fire
  ["flagellation"] = {
    label   = "Flagellation",
    timed   = true,
    on      = { "You feel fervent in your devotion." },
    refresh = {},
    off     = { "Effects of your flagellation wear out." },
  },
  ["martyrdom"] = {
    label   = "Martyrdom",
    timed   = true,
    on      = { "Your faith is your armor and no mortal danger can steer you" },
    refresh = { "You feel your faith strenghten." },
    off     = { "You feel the effects of your martyrdom wane." },
  },
}
