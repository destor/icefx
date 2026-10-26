-- =============================================================
-- Icesus Effects — text-triggered effect tracker for Icesus MUD.
--
-- data.lua: effect definitions, saved runs and estimates, and the
-- live on/off state. No widgets and no triggers — ui.lua draws this
-- state and controller.lua changes it. Loaded after builtins.lua,
-- which holds the shipped effects (fx.BUILTIN).
--
-- Watches the main console for each effect's "on", "refresh" and
-- "off" messages and shows one floating button per effect along the
-- right edge of the main (scrolling) console. Timed effects get a
-- draining bar, the elapsed time, and an expiry estimate averaged
-- from the previous applications — those samples persist across
-- sessions in getMudletHomeDir()/IcesusEffects.lua.
--
-- Companion to the official Icesus package, not part of it: works
-- with or without the HUD, and borrows its palette and font when the
-- HUD is loaded.
-- =============================================================

icesusfx = icesusfx or {}
local fx = icesusfx

fx.version = "0.4.0"
fx.PACKAGE = "IcesusEffects"

-- Layout (ui.lua) and learning (here) settings in one place.
fx.config = {
  width       = 220,  -- button width (px)
  rowH        = 40,   -- timed button height: text + bar
  rowHPlain   = 26,   -- untimed button height: text only
  gap         = 4,
  marginRight = 22,   -- keeps the buttons clear of the console scrollbar
  marginTop   = 8,
  maxSamples  = 10,   -- applications averaged into the estimate
  minSample   = 2,    -- seconds; shorter runs are misfires, not samples
  flashSecs   = 5,    -- alert.flash: how long an expired button pulses
  bannerSecs  = 3,    -- alert.banner: how long a banner stays up
  fontSize    = 10,
}

-- fx.BUILTIN, the shipped effect definitions, lives in builtins.lua.

fx.KINDS = { "on", "refresh", "off" }

function fx.now()
  return getEpoch and getEpoch() or os.time()
end

-- =============================================================
-- Persistence — definitions and duration samples.
-- =============================================================
local function dataPath()
  return getMudletHomeDir() .. "/IcesusEffects.lua"
end

function fx.load()
  local t = {}
  if io.exists and io.exists(dataPath()) then
    local ok = pcall(table.load, dataPath(), t)
    if not ok then t = {} end
  end
  fx.data = {
    defs   = type(t.defs) == "table" and t.defs or {},
    stats  = type(t.stats) == "table" and t.stats or {},
    seeded = type(t.seeded) == "table" and t.seeded or {},
    -- Signature of each shipped definition as of the last load, so an
    -- update that changes one can be noticed (see fx.checkShipped).
    shipped = type(t.shipped) == "table" and t.shipped or {},
    -- Where `icefx reload` reinstalls the package from.
    packagePath = type(t.packagePath) == "string" and t.packagePath or nil,
  }
  local seeded = fx.seedBuiltins()
  local changed = fx.checkShipped()
  if seeded or changed then fx.save() end
end

-- Add each shipped effect not seeded before. Returns true if any was.
function fx.seedBuiltins()
  local changed = false
  for key, def in pairs(fx.BUILTIN) do
    if not fx.data.seeded[key] then
      fx.data.seeded[key] = true
      if not fx.data.defs[key] then
        fx.data.defs[key] = {
          label = def.label, timed = def.timed,
          on = { unpack(def.on or {}) },
          refresh = { unpack(def.refresh or {}) },
          off = { unpack(def.off or {}) },
        }
      end
      changed = true
    end
  end
  return changed
end

-- Back to a fresh install: only the shipped effects, as shipped, with
-- no recorded runs, alerts or live state. The data being replaced is
-- saved to IcesusEffects.backup.lua first; the reload path is kept,
-- since it is not effect data.
function fx.resetToBaseline()
  local backup = getMudletHomeDir() .. "/IcesusEffects.backup.lua"
  pcall(table.save, backup, fx.data)
  fx.data = { defs = {}, stats = {}, seeded = {}, shipped = {},
    packagePath = fx.data.packagePath }
  fx.seedBuiltins()
  fx.checkShipped()
  fx.live = {}
  fx.save()
  return backup
end

function fx.save()
  if fx.data then pcall(table.save, dataPath(), fx.data) end
end

-- =============================================================
-- Duration estimate.
-- =============================================================
function fx.addSample(key, seconds)
  local st = fx.data.stats[key] or { samples = {} }
  fx.data.stats[key] = st
  table.insert(st.samples, seconds)
  while #st.samples > fx.config.maxSamples do table.remove(st.samples, 1) end
  fx.save()
end

-- Mean of the remembered samples, or nil before the first one.
function fx.estimate(key)
  local st = fx.data.stats[key]
  if not st or #st.samples == 0 then return nil end
  local sum = 0
  for _, s in ipairs(st.samples) do sum = sum + s end
  return sum / #st.samples
end

-- =============================================================
-- Live state.
--
-- One entry per effect seen this session:
--   since    first application (orders the buttons; a refresh keeps it)
--   started  last (re)application — what the estimate counts from
--   ended    expiry time, nil while active
--   lasted   started → ended; nil when we never saw it start
--   partial  true when the real start is unknown (forced on, or found
--            by `effects` output): the clock is a lower bound, and the
--            run is not learned from. A refresh clears it.
-- =============================================================
fx.live = fx.live or {}

local function emit(name, key)
  if raiseEvent then pcall(raiseEvent, name, key) end
end

function fx.fire(key, kind)
  local def = fx.data.defs[key]
  if not def then return end
  local t = fx.now()
  local e = fx.live[key]
  local active = e and not e.ended

  if kind == "on" or kind == "refresh" then
    if active then
      -- A refresh (or recasting over a running effect) restores the
      -- full duration, so the clock restarts from here.
      e.started = t
      e.partial = nil
      e.refreshes = (e.refreshes or 0) + 1
      emit("icesusfx.refresh", key)
    else
      -- A refresh with no live entry means the effect was up before we
      -- were watching; it still restarts the clock, so track from here.
      fx.live[key] = { key = key, since = t, started = t, refreshes = 0 }
      emit("icesusfx.on", key)
    end
  elseif kind == "off" then
    if active then
      e.ended = t
      if not e.partial then
        e.lasted = t - e.started
        if def.timed ~= false and e.lasted >= fx.config.minSample then
          fx.addSample(key, e.lasted)
        end
      end
    else
      -- Ended without us seeing it start: show it expired, learn nothing.
      fx.live[key] = { key = key, since = t, started = t, ended = t }
    end
    emit("icesusfx.off", key)
  end
end

-- Forced on/off, for when a trigger missed. Neither learns a run: we
-- don't know when the effect really started.
function fx.activate(key)
  local e = fx.live[key]
  if e and not e.ended then return false end
  local t = fx.now()
  fx.live[key] = { key = key, since = t, started = t, refreshes = 0, partial = true }
  emit("icesusfx.on", key)
  return true
end

function fx.deactivate(key)
  local e = fx.live[key]
  if not e or e.ended then return false end
  e.ended = fx.now()
  e.partial = true
  emit("icesusfx.off", key)
  return true
end

function fx.isActive(key)
  local e = fx.live[key]
  return e ~= nil and not e.ended
end

-- Everything off and every button gone. Learns nothing.
function fx.reset()
  for key, e in pairs(fx.live) do
    if not e.ended then emit("icesusfx.off", key) end
  end
  fx.live = {}
end

-- Drop an expired effect's entry (its button goes with it).
function fx.dismiss(key)
  local e = fx.live[key]
  if not e or not e.ended then return false end
  fx.live[key] = nil
  return true
end

function fx.clearExpired()
  for key, e in pairs(fx.live) do
    if e.ended then fx.live[key] = nil end
  end
end

-- Where a message may begin: the start of a sentence. Mudlet runs
-- triggers on the whole line the game sent, before wrapping it for
-- display, and the game puts several sentences on one line — a spell's
-- flavour text followed by its effect message, say. Requiring a
-- sentence start still keeps "Bob says: You feel ..." and channel
-- lines from firing a message.
fx.SENTENCE_START = [[(?:^|[.!?]\s+)]]

-- The PCRE a message is matched with.
--   plain text   a sentence starts with it
--   re:<regex>   the regex as written, except that a leading ^ means
--                "at a sentence start" too
function fx.messageRegex(pat)
  if pat:sub(1, 3) == "re:" then
    local re = pat:sub(4)
    if re:sub(1, 1) == "^" then return fx.SENTENCE_START .. re:sub(2) end
    return re
  end
  return fx.SENTENCE_START .. (pat:gsub("[%^%$%.%|%?%*%+%(%)%[%]%{%}\\]", "\\%0"))
end

-- Feed one line through every pattern, as the triggers would. Used by
-- `icefx test` and the unit tests; live matching is Mudlet's trigger
-- engine, with the same regexes.
function fx.matchLine(line)
  local hits = {}
  if not (rex and rex.match) then return hits end
  for key, def in pairs(fx.data.defs) do
    for _, kind in ipairs(fx.KINDS) do
      for _, pat in ipairs(def[kind] or {}) do
        local ok, m = pcall(rex.match, line, fx.messageRegex(pat))
        if ok and m ~= nil then hits[#hits + 1] = { key = key, kind = kind } end
      end
    end
  end
  return hits
end

function fx.label(key)
  local def = fx.data.defs[key]
  return (def and def.label) or key
end

-- =============================================================
-- Definitions — the model the `icefx` commands edit. Callers save
-- and rebuild triggers afterwards (see controller.lua).
-- =============================================================
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
fx.trim = trim

function fx.sortedKeys()
  local keys = {}
  for k in pairs(fx.data.defs) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

-- A number from `icefx list`, an exact name, or the one name the text
-- is the start of. Returns nil plus "ambiguous" when several match.
function fx.resolve(name)
  name = trim(name or ""):lower()
  if name == "" then return nil end
  if name:match("^%d+$") then return fx.sortedKeys()[tonumber(name)] end
  if fx.data.defs[name] then return name end
  local found
  for key in pairs(fx.data.defs) do
    if key:sub(1, #name) == name then
      if found then return nil, "ambiguous" end
      found = key
    end
  end
  return found
end

-- New timed effect with no messages. Returns its key, or nil if the
-- name is taken.
function fx.define(label)
  local key = label:lower()
  if fx.data.defs[key] then return nil end
  fx.data.defs[key] = { label = label, timed = true, on = {}, refresh = {}, off = {} }
  return key
end

function fx.undefine(key)
  fx.data.defs[key] = nil
  fx.data.stats[key] = nil
  fx.live[key] = nil
end

function fx.forget(key)
  fx.data.stats[key] = nil
end

-- Seconds left by the estimate (negative once overdue), or nil when
-- there is no estimate or the effect is not running.
function fx.remaining(e, t)
  local est = fx.estimate(e.key)
  if not est or e.ended then return nil end
  return est - (t - e.started)
end

-- =============================================================
-- Settings — what `icefx config` writes and `icefx show` prints.
--
--   effect.label            display name
--   effect.timed            has a duration (true/false)
--   effect.on / .refresh / .off
--                           message lists: = replaces the list with one
--                           message (empty clears it), += appends,
--                           .N = replaces message N (empty removes it)
--   alert.flash             pulse the button red when it falls off
--   alert.banner            banner across the console when it falls
--                           off (and at the warning, if alert.warn)
--   alert.warn              seconds before the estimated end to start
--                           warning; nil = off
-- =============================================================
local BOOL = {
  ["true"] = true, on = true, yes = true, ["1"] = true,
  ["false"] = false, off = false, no = false, ["0"] = false,
}

function fx.alerts(key)
  local a = (fx.data.defs[key] or {}).alert or {}
  return { flash = a.flash == true, banner = a.banner == true, warn = tonumber(a.warn) }
end

local function alertOf(def)
  def.alert = def.alert or {}
  return def.alert
end

-- Apply one setting. op is "=" or "+=". Returns true, or nil and why.
function fx.setSetting(key, path, op, value)
  local def = fx.data.defs[key]
  local group, name, idx = path:match("^(%a+)%.(%a+)%.?(%d*)$")
  idx = tonumber(idx)
  if not group then return nil, "unknown setting: " .. path end

  if group == "effect" and (name == "on" or name == "refresh" or name == "off") then
    def[name] = def[name] or {}
    local list = def[name]
    if idx then
      if op ~= "=" then return nil, "use = with a numbered message" end
      if not list[idx] then return nil, "no message " .. path end
      if value == "" then table.remove(list, idx) else list[idx] = value end
    elseif op == "+=" then
      if value == "" then return nil, "nothing to add to " .. path end
      table.insert(list, value)
    else
      def[name] = (value == "") and {} or { value }
    end
    return true
  end

  if idx or op ~= "=" then
    return nil, "only effect.on, effect.refresh and effect.off take += or a number"
  end

  if group == "effect" and name == "label" then
    if value == "" then return nil, "effect.label can't be empty" end
    def.label = value
    return true
  end

  if (group == "effect" and name == "timed")
      or (group == "alert" and (name == "flash" or name == "banner")) then
    local b = BOOL[value:lower()]
    if b == nil then return nil, path .. " takes true or false" end
    if group == "effect" then def.timed = b else alertOf(def)[name] = b end
    return true
  end

  if group == "alert" and name == "warn" then
    local v = value:lower()
    if v == "" or v == "off" or v == "false" or v == "0" then
      alertOf(def).warn = nil
      return true
    end
    local n = tonumber(v:match("^(%d+)s?$") or "")
    if not n then return nil, "alert.warn takes seconds, or off" end
    alertOf(def).warn = n
    return true
  end

  return nil, "unknown setting: " .. path
end

-- Every setting of one effect as { path, shown value } pairs, in the
-- form `icefx config` accepts back.
function fx.settingLines(key)
  local def = fx.data.defs[key]
  local a = fx.alerts(key)
  local function q(s) return '"' .. s .. '"' end
  local out = {
    { "effect.label", q(fx.label(key)) },
    { "effect.timed", tostring(def.timed ~= false) },
  }
  for _, kind in ipairs(fx.KINDS) do
    local list = def[kind] or {}
    if #list == 0 then out[#out + 1] = { "effect." .. kind, '""' } end
    for i, pat in ipairs(list) do
      out[#out + 1] = { "effect." .. kind .. "." .. i, q(pat) }
    end
  end
  out[#out + 1] = { "alert.flash", tostring(a.flash) }
  out[#out + 1] = { "alert.banner", tostring(a.banner) }
  out[#out + 1] = { "alert.warn", a.warn and tostring(a.warn) or "off" }
  return out
end

-- =============================================================
-- Migration — local copies of shipped effects vs the package.
--
-- A built-in is copied into the player's definitions once and edited
-- there from then on, so a package update never overwrites it. These
-- compare the copy with the shipped version, and copy the shipped
-- label, timed flag and messages over it on request. Runs and alerts
-- are the player's and are never touched.
-- =============================================================
local function timedOf(def) return def.timed ~= false end

local function signature(def)
  local parts = { def.label or "", tostring(timedOf(def)) }
  for _, kind in ipairs(fx.KINDS) do
    parts[#parts + 1] = table.concat(def[kind] or {}, "\0")
  end
  return table.concat(parts, "\1")
end

-- Differences between the local copy and the shipped definition, as
-- { field, from, to } for label/timed and { field, removed, added }
-- message lists for on/refresh/off. nil when they match, or when the
-- effect is not shipped or was removed locally.
function fx.builtinDiff(key)
  local ship, mine = fx.BUILTIN[key], fx.data.defs[key]
  if not ship or not mine or signature(ship) == signature(mine) then return nil end
  local out = {}
  if (mine.label or key) ~= ship.label then
    out[#out + 1] = { field = "effect.label", from = mine.label or key, to = ship.label }
  end
  if timedOf(mine) ~= timedOf(ship) then
    out[#out + 1] = { field = "effect.timed", from = tostring(timedOf(mine)), to = tostring(timedOf(ship)) }
  end
  for _, kind in ipairs(fx.KINDS) do
    local a, b = mine[kind] or {}, ship[kind] or {}
    local inA, inB = {}, {}
    for _, m in ipairs(a) do inA[m] = true end
    for _, m in ipairs(b) do inB[m] = true end
    local removed, added = {}, {}
    for _, m in ipairs(a) do if not inB[m] then removed[#removed + 1] = m end end
    for _, m in ipairs(b) do if not inA[m] then added[#added + 1] = m end end
    -- Same messages in a different order still count as a change.
    if #removed + #added > 0 or table.concat(a, "\0") ~= table.concat(b, "\0") then
      out[#out + 1] = { field = "effect." .. kind, removed = removed, added = added }
    end
  end
  return out
end

-- Keys of built-ins whose local copy differs from the package, sorted
-- like `icefx list`.
function fx.migratable()
  local out = {}
  for _, key in ipairs(fx.sortedKeys()) do
    if fx.builtinDiff(key) then out[#out + 1] = key end
  end
  return out
end

-- Copy the shipped label, timed flag and messages over the local copy.
function fx.migrate(key)
  local ship, mine = fx.BUILTIN[key], fx.data.defs[key]
  if not ship or not mine then return false end
  mine.label, mine.timed = ship.label, ship.timed
  for _, kind in ipairs(fx.KINDS) do mine[kind] = { unpack(ship[kind] or {}) } end
  return true
end

-- Note which shipped definitions changed since the last load and now
-- differ from the local copy, into fx.updated (announced at install).
-- Returns true when the stored signatures changed.
function fx.checkShipped()
  fx.updated = {}
  local changed = false
  for _, key in ipairs(fx.sortedKeys()) do
    local ship = fx.BUILTIN[key]
    if ship then
      local sig = signature(ship)
      if fx.data.shipped[key] ~= sig then
        if fx.builtinDiff(key) then fx.updated[#fx.updated + 1] = key end
        fx.data.shipped[key] = sig
        changed = true
      end
    end
  end
  return changed
end

-- =============================================================
-- Versions — "0.10.0" > "0.9.1", which a string compare gets wrong.
-- =============================================================
local function versionParts(s)
  local out = {}
  for n in tostring(s or ""):gmatch("%d+") do out[#out + 1] = tonumber(n) end
  return out
end

function fx.versionNewer(a, b)
  local pa, pb = versionParts(a), versionParts(b)
  if #pa == 0 or #pb == 0 then return false end
  for i = 1, math.max(#pa, #pb) do
    local x, y = pa[i] or 0, pb[i] or 0
    if x ~= y then return x > y end
  end
  return false
end
