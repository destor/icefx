-- =============================================================
-- Icesus Effects — controller.lua: wiring. Loaded last.
--
-- Turns game output (effect messages, the `effects` listing) and
-- `icefx` commands into changes to the state in data.lua, then has
-- ui.lua redraw. Also owns install / teardown.
-- =============================================================
icesusfx = icesusfx or {}
local fx = icesusfx

local fmtTime, trim = fx.fmtTime, fx.trim

local function say(s) cecho("\n<SkyBlue>[icefx]<reset> " .. s .. "\n") end

-- =============================================================
-- Triggers — one temp trigger per pattern of each enabled effect,
-- rebuilt on any change.
-- =============================================================
fx.triggerIds = fx.triggerIds or {}

function fx.killTriggers()
  for _, id in ipairs(fx.triggerIds) do pcall(killTrigger, id) end
  fx.triggerIds = {}
end

function fx.rebuildTriggers()
  fx.killTriggers()
  for key, def in pairs(fx.data.defs) do
    for _, kind in ipairs(fx.isEnabled(key) and fx.KINDS or {}) do
      for _, pat in ipairs(def[kind] or {}) do
        local fn = function()
          fx.fire(key, kind)
          if kind == "off" then fx.cueExpired(key) end
          fx.render()
        end
        -- A bad regex must not take every other trigger down with it.
        local ok, id = pcall(tempRegexTrigger, fx.messageRegex(pat), fn)
        if ok and id then
          fx.triggerIds[#fx.triggerIds + 1] = id
        else
          say(string.format("<red>bad message for %s: %s<reset>", fx.label(key), pat))
        end
      end
    end
  end
  for _, id in ipairs(fx.effectsTriggers()) do
    fx.triggerIds[#fx.triggerIds + 1] = id
  end
end

-- =============================================================
-- Alerts — per-effect cues configured under alert.* (see data.lua).
-- =============================================================
function fx.cueExpired(key)
  local a = fx.alerts(key)
  if a.flash then fx.flash(key) end
  if a.banner then fx.banner(fx.label(key) .. " — off") end
end

-- alert.warn: the pulse itself is drawn by fx.view; this raises the
-- one-off banner, once per (re)application.
fx.warned = fx.warned or {}

function fx.checkWarnings()
  local t = fx.now()
  for key, e in pairs(fx.live) do
    local a = fx.alerts(key)
    local left = a.warn and fx.remaining(e, t)
    if left and left <= a.warn and fx.warned[key] ~= e.started then
      fx.warned[key] = e.started
      if a.banner then
        fx.banner(string.format("%s — %s left", fx.label(key), fmtTime(math.max(0, left))),
          "#fbbf24")
      end
    end
  end
end

-- =============================================================
-- `effects` output — the game's own list of what is on you.
--
--   Beneficial effects affecting you:
--    Fleshcraft
--    Essence of the nether
--   No visible harmful effects affect you.
--
-- Each entry line is rewritten as an ON row with our timing, effects
-- we tracked this session that the game no longer lists follow the
-- listing as OFF rows, and when the listing ends the tracker is synced
-- to it: listed effects go on, unlisted active ones go off, and names
-- we have never seen become new definitions.
-- =============================================================
local EFFECTS_HEADER = "^%a+ effects affecting you:$"
local EFFECTS_NONE   = "^No visible %a+ effects affect you%.$"

fx.capture = nil   -- { names = {}, sync = bool } while a listing arrives

-- The row an entry line is rewritten to.
function fx.entryRow(name)
  local key = name:lower()
  local def = fx.data.defs[key]
  if not def then return fx.effectsRow(true, name, "") end
  local timer, hot = "", false
  if def.timed ~= false then
    local e = fx.live[key]
    if e and not e.ended then
      local v = fx.view(e, fx.now())
      timer, hot = v.right or "", v.warning or v.state == "overdue"
    else
      -- Not tracked yet: the elapsed time is unknown until sync.
      local est = fx.estimate(key)
      timer = "? / " .. (est and ("~" .. fmtTime(est)) or "?")
    end
  end
  return fx.effectsRow(true, fx.label(key), timer, hot)
end

-- OFF rows for what we tracked this session that the listing so far
-- did not mention, as a block to echo after a line; nil when none.
function fx.offBlock(c)
  local seen = {}
  for _, name in ipairs(c.names) do seen[name:lower()] = true end
  local t = fx.now()
  local keys = {}
  for key in pairs(fx.live) do
    if not seen[key] then keys[#keys + 1] = key end
  end
  if #keys == 0 then return nil end
  table.sort(keys, function(a, b) return fx.label(a) < fx.label(b) end)
  local out = { "\n<grey>Tracked, now off:<reset>" }
  for _, key in ipairs(keys) do
    local e = fx.live[key]
    local timer = e.ended and ("ended " .. fmtTime(t - e.ended) .. " ago") or "dropped"
    out[#out + 1] = "\n" .. fx.effectsRow(false, fx.label(key), timer)
  end
  return table.concat(out)
end

-- Feed one line of output. Returns:
--   "listing", block  a header or "No visible ..." line; block is the
--                     OFF rows to echo after it, when it ends the listing
--   "entry", row      an effect line and the row to replace it with
--   "end"             a line that closes an open listing
--   nil               no listing open
function fx.effectsLine(line)
  if line:match(EFFECTS_HEADER) or line:match(EFFECTS_NONE) then
    if not fx.capture then
      fx.capture = { names = {}, sync = fx.pendingSync }
      fx.pendingSync = nil
    end
    local c = fx.capture
    fx.armEffectsFallback()
    -- Harmful effects come last, so "No visible harmful ..." is the
    -- final line: the OFF rows go right after it. A listing that ends
    -- in harmful entries gets them when it closes instead.
    local block
    if line:match(EFFECTS_NONE) and line:find("harmful", 1, true) and not c.offShown then
      c.offShown = true
      block = fx.offBlock(c)
    end
    return "listing", block
  end
  if not fx.capture then return nil end
  local name = line:match("^ (%S.-)%s*$")
  if not name then
    fx.finishEffects()
    return "end"
  end
  table.insert(fx.capture.names, name)
  fx.armEffectsFallback()
  return "entry", fx.entryRow(name)
end

-- A listing normally ends at the next non-entry line; this catches the
-- case where nothing follows it for a while.
function fx.armEffectsFallback()
  if not fx.capture then return end
  if fx.capture.timer then pcall(killTimer, fx.capture.timer) end
  fx.capture.timer = tempTimer(1, function() fx.finishEffects() end)
end

function fx.finishEffects()
  local c = fx.capture
  if not c then return end
  fx.capture = nil
  if c.timer then pcall(killTimer, c.timer) end
  if not c.offShown then
    local block = fx.offBlock(c)
    if block then cecho(block .. "\n") end
  end

  local seen, added, on, off = {}, {}, {}, {}
  for _, name in ipairs(c.names) do
    local key = name:lower()
    seen[key] = true
    if fx.define(name) then added[#added + 1] = name end
    if fx.isEnabled(key) and fx.activate(key) then on[#on + 1] = fx.label(key) end
  end
  for key, e in pairs(fx.live) do
    if not e.ended and not seen[key] and fx.deactivate(key) then
      off[#off + 1] = fx.label(key)
      fx.cueExpired(key)
    end
  end
  if #added > 0 then fx.save() end
  fx.render()

  if c.sync or #on + #off + #added > 0 then
    if #on + #off + #added == 0 then return say("sync: already up to date") end
    if #on > 0 then say("sync: on — " .. table.concat(on, ", ")) end
    if #off > 0 then say("sync: off — " .. table.concat(off, ", ")) end
    if #added > 0 then
      say("sync: new — " .. table.concat(added, ", ")
        .. '  <grey>(give them messages: icefx config <effect> effect.on="...")<reset>')
    end
  end
end

-- Mudlet side: the header / "none" lines start a chain of one-line
-- triggers that follows the listing until a line is not an entry.
local function show(kind, text)
  if kind == "entry" then
    if creplaceLine then creplaceLine("main", text) else cecho("  " .. text) end
  elseif kind == "listing" and text then
    cecho(text)
  end
end

local function followEffects()
  tempLineTrigger(1, 1, function()
    local kind, text = fx.effectsLine(line)
    show(kind, text)
    if kind == "entry" then followEffects() end
  end)
end

function fx.effectsTriggers()
  local function start()
    show(fx.effectsLine(line))
    followEffects()
  end
  return {
    tempRegexTrigger([[^\w+ effects affecting you:$]], start),
    tempRegexTrigger([[^No visible \w+ effects affect you\.$]], start),
  }
end

-- =============================================================
-- `icefx` command.
-- =============================================================
local function need(name)
  local key, why = fx.resolve(name)
  if not key then
    say(string.format("<red>%s effect: %s<reset>", why or "no such", trim(name or "")))
  end
  return key
end

local function labels(keys)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = fx.label(k) end
  return table.concat(out, ", ")
end

local function listRow(i, key, t)
  local def = fx.data.defs[key]
  local e = fx.live[key]
  local state = (e and not e.ended) and "<green>ON <reset>" or "<grey>off<reset>"
  local est = fx.estimate(key)
  local st = fx.data.stats[key]
  local info
  if not fx.isEnabled(key) then
    info = "<red>disabled"
  elseif def.timed == false then
    info = "<grey>no timer"
  elseif e and not e.ended then
    info = fx.view(e, t).right
  elseif est then
    info = string.format("~%s <grey>(%d run%s)", fmtTime(est),
      #st.samples, #st.samples == 1 and "" or "s")
  else
    info = "<grey>no estimate yet"
  end
  local tags = fx.tagsOf(key)
  local tagText = #tags > 0 and ("  <grey>[" .. table.concat(tags, " ") .. "]") or ""
  cecho(string.format("  <cyan>%2d<reset>  %-28s %s  %s<reset>%s<reset>\n",
    i, fx.label(key), state, info, tagText))
end

-- `icefx list [all|unseen|off|<tag>]`. Numbers are always positions
-- in the full list, so `icefx config 7` means the same effect in every
-- view. The default view is enabled effects that have been seen.
local function cmdList(arg)
  local view = trim(arg or ""):lower()
  local keys = fx.sortedKeys()
  local tag
  if view ~= "" and view ~= "all" and view ~= "unseen" and view ~= "off" then
    tag = view
    local known = false
    for _, k in ipairs(keys) do if fx.hasTag(k, tag) then known = true; break end end
    if not known then return say("<red>no effect has the tag " .. tag .. "<reset> — icefx tags lists them") end
  end
  local t = fx.now()
  local shown, unseen, off = 0, 0, 0
  for i, key in ipairs(keys) do
    local g = fx.listGroup(key)
    local show
    if view == "all" then show = true
    elseif tag then show = fx.hasTag(key, tag)
    elseif view == "" then show = g == nil
    else show = g == view end
    if show then
      if shown == 0 then
        say(view == "" and "effects" or ("effects: " .. view))
      end
      shown = shown + 1
      listRow(i, key, t)
    elseif view == "" then
      if g == "unseen" then unseen = unseen + 1 else off = off + 1 end
    end
  end
  if shown == 0 then say(view == "" and "no effects seen yet" or ("no effects: " .. view)) end
  local more = {}
  if unseen > 0 then more[#more + 1] = string.format("%d not seen yet (icefx list unseen)", unseen) end
  if off > 0 then more[#more + 1] = string.format("%d disabled (icefx list off)", off) end
  if #more > 0 then cecho("  <grey>+" .. table.concat(more, ", ") .. "<reset>\n") end
end

-- Switch every effect with a tag on or off (`icefx enable|disable <tag>`).
local function setTag(tag, on)
  local keys = fx.setTagEnabled(tag, on)
  if not keys then return say("<red>no effect has the tag " .. tag .. "<reset>") end
  fx.save()
  fx.rebuildTriggers()
  fx.render()
  if not on then
    return say(string.format("%s: disabled — %d effect(s): %s", tag, #keys, labels(keys)))
  end
  local still = {}
  for _, k in ipairs(keys) do if not fx.isEnabled(k) then still[#still + 1] = k end end
  say(tag .. ": enabled")
  if #still > 0 then
    say("<grey>still disabled by another tag or on their own: " .. labels(still) .. "<reset>")
  end
end

-- `icefx tags`: every tag with its count. `tags on|off <tag>` is the
-- old spelling of `enable|disable <tag>`.
local function cmdTags(arg)
  local verb, tag = trim(arg or ""):lower():match("^(%S*)%s*(.-)$")
  if verb == "on" or verb == "off" then
    if tag == "" then return say("<red>usage: icefx disable <tag><reset>") end
    return setTag(tag, verb == "on")
  end
  local tags = fx.allTags()
  if #tags == 0 then return say('no tags yet — icefx config <effect> effect.tags+="<tag>"') end
  say(string.format("%d tag(s)", #tags))
  for _, x in ipairs(tags) do
    cecho(string.format("  %-24s %s  <grey>%d effect%s<reset>\n", x.tag,
      x.on and "<green>on <reset>" or "<red>off<reset>", x.count, x.count == 1 and "" or "s"))
  end
  cecho("  <grey>icefx list <tag> shows a tag's effects; icefx disable <tag> stops tracking them<reset>\n")
end

-- `icefx enable|disable <effect|tag>`. A number or an effect's full
-- name means the effect; then a tag's full name; then the start of an
-- effect's name.
local function cmdEnable(arg, verb)
  local on = verb == "enable"
  local name = trim(arg or ""):lower()
  if name == "" then return say("<red>usage: icefx " .. verb .. " <effect|tag><reset>") end
  if not (name:match("^%d+$") or fx.data.defs[name]) then
    for _, x in ipairs(fx.allTags()) do
      if x.tag == name then return setTag(name, on) end
    end
  end
  local key, why = fx.resolve(name)
  if not key then
    return say(string.format("<red>%s effect or tag: %s<reset>", why or "no such", name))
  end
  fx.setEnabled(key, on)
  fx.save()
  fx.rebuildTriggers()
  fx.render()
  say(fx.label(key) .. ": " .. verb .. "d")
  if on and not fx.isEnabled(key) then
    local off = {}
    for _, t in ipairs(fx.tagsOf(key)) do
      if fx.data.tagsOff[t] then off[#off + 1] = t end
    end
    say("<grey>still disabled by its tag " .. table.concat(off, ", ")
      .. " — icefx enable " .. off[1] .. "<reset>")
  end
end

local function cmdShow(name)
  local key = need(name); if not key then return end
  local id
  for i, k in ipairs(fx.sortedKeys()) do if k == key then id = i end end
  say(string.format("<white>%s<reset> <grey>(#%d — change with icefx config %d <setting>=<value>)<reset>",
    fx.label(key), id, id))
  for _, kv in ipairs(fx.settingLines(key)) do
    cecho(string.format("  <cyan>%-18s<reset> = %s\n", kv[1], kv[2]))
  end
  local st = fx.data.stats[key]
  if st and #st.samples > 0 then
    local parts = {}
    for _, s in ipairs(st.samples) do parts[#parts + 1] = fmtTime(s) end
    cecho(string.format("  <grey>runs: %s (estimate ~%s)<reset>\n",
      table.concat(parts, ", "), fmtTime(fx.estimate(key))))
  end
end

-- Split "<effect> a.b=1 c.d+=\"some text\"" into the effect name and
-- assignments. A value in quotes runs to the quote that ends the
-- line or is followed by the next setting, so quotes inside a game
-- message need no escaping.
local SETTING = "[%a]+%.[%a]+[%.%d]*"

function fx.parseConfig(text)
  local at = text:find("%s" .. SETTING .. "%+?=") or (text:find("^" .. SETTING .. "%+?=") and 0)
  local name = at and trim(text:sub(1, at)) or trim(text)
  if not at then return name, {} end
  local rest = text:sub(at + 1)
  local out = {}
  while true do
    rest = rest:gsub("^%s+", "")
    if rest == "" then break end
    local path, op, after = rest:match("^(" .. SETTING .. ")(%+?=)(.*)$")
    if not path then return name, nil, "can't read: " .. rest end
    local value
    if after:sub(1, 1) == '"' then
      local stop
      local from = 2
      while true do
        local q = after:find('"', from, true)
        if not q then return name, nil, "missing closing quote for " .. path end
        local tail = after:sub(q + 1)
        if tail:match("^%s*$") or tail:match("^%s+" .. SETTING .. "%+?=") then stop = q; break end
        from = q + 1
      end
      value, rest = after:sub(2, stop - 1), after:sub(stop + 1)
    else
      value, rest = after:match("^(%S*)(.*)$")
    end
    out[#out + 1] = { path = path:lower(), op = op, value = value }
  end
  return name, out
end

-- What `icefx config help` lists. effect.enabled is set with
-- `icefx enable|disable`, so the list leaves it out.
local SETTING_HELP = {
  { "effect.label",   '"Name"',     "display name" },
  { "effect.timed",   "true|false", "it has a duration" },
  { "effect.on",      '"text"',     "start messages (see below)" },
  { "effect.refresh", '"text"',     "refresh messages, the same way" },
  { "effect.off",     '"text"',     "expiry messages, the same way" },
  { "effect.tags",    '"a b"',      "tags, the same way; = and += take several" },
  { "alert.flash",    "true|false", "flash the button red when it falls off" },
  { "alert.banner",   "true|false", "banner on the screen when it falls off" },
  { "alert.warn",     "10|off",     "pulse the button 10 s before the estimated end" },
  { "effect.enabled", "true|false", "false: not tracked (icefx enable|disable)", hidden = true },
}

-- `icefx config <effect> <setting>`: its value(s) and what it does.
local function showSetting(key, path)
  local base = path:match("^(%a+%.%a+)")
  local found = false
  for _, kv in ipairs(fx.settingLines(key)) do
    if kv[1] == path or kv[1]:sub(1, #base + 1) == base .. "." or kv[1] == base then
      if not found then say(fx.label(key)) end
      found = true
      cecho(string.format("  <cyan>%-18s<reset> = %s\n", kv[1], kv[2]))
    end
  end
  if not found then return say("<red>unknown setting: " .. path .. "<reset> — icefx config help") end
  for _, h in ipairs(SETTING_HELP) do
    if h[1] == base then cecho("  <grey>" .. h[3] .. "<reset>\n") end
  end
end

local function settingsHelp()
  local out = {}
  for _, h in ipairs(SETTING_HELP) do
    if not h.hidden then
      out[#out + 1] = string.format("%-34s %s", h[1] .. "=" .. h[2], h[3])
    end
  end
  local tail = {
    "",
    'effect.on="text"                   replace the list with this one message ("" clears it)',
    'effect.on+="text"                  add a message',
    'effect.on.2="text"                 replace message 2 (effect.on.2= removes it)',
    "",
    "icefx config <effect> <setting>    show one setting",
    "A message is the start of a sentence of output; start it with re: for a regex.",
    "Quotes are needed only when a value has spaces.",
  }
  for _, l in ipairs(tail) do out[#out + 1] = l end
  return out
end

local function cmdConfig(text)
  local name, sets, err = fx.parseConfig(text)
  if err then return say("<red>" .. err .. "<reset>") end
  if #sets == 0 then
    local n, path = name:match("^(.-)%s+(" .. SETTING .. ")$")
    if n and n ~= "" and fx.resolve(n) then return showSetting(fx.resolve(n), path:lower()) end
  end
  local key = need(name); if not key then return end
  if #sets == 0 then return cmdShow(key) end
  for _, a in ipairs(sets) do
    local ok, why = fx.setSetting(key, a.path, a.op, a.value)
    if not ok then
      say("<red>" .. why .. "<reset>")
    else
      say(string.format("%s: %s %s %s", fx.label(key), a.path, a.op,
        a.value == "" and "<grey>(cleared)<reset>" or a.value))
    end
  end
  fx.save()
  fx.rebuildTriggers()
  fx.render()
end

local function listId(key)
  for i, k in ipairs(fx.sortedKeys()) do if k == key then return i end end
end

-- `icefx migrate`: list differing built-ins with their changes;
-- `icefx migrate <effect>|all`: take the package's version.
local function cmdMigrate(arg)
  arg = trim(arg or "")
  if arg == "" then
    local keys = fx.migratable()
    if #keys == 0 then return say("every built-in effect matches the package") end
    say(string.format("%d built-in effect(s) differ from the package — <white>local<reset> → <white>package<reset>:", #keys))
    for _, key in ipairs(keys) do
      cecho(string.format("  <cyan>%2d<reset>  <white>%s<reset>\n", listId(key), fx.label(key)))
      for _, d in ipairs(fx.builtinDiff(key)) do
        if d.from then
          cecho(string.format("      <cyan>%s<reset>  %s → %s\n", d.field, d.from, d.to))
        elseif #d.removed + #d.added == 0 then
          cecho(string.format("      <cyan>%s<reset>  <grey>same messages, different order<reset>\n", d.field))
        else
          for _, m in ipairs(d.removed) do
            cecho(string.format("      <cyan>%s<reset>  <red>- %s<reset>\n", d.field, m))
          end
          for _, m in ipairs(d.added) do
            cecho(string.format("      <cyan>%s<reset>  <green>+ %s<reset>\n", d.field, m))
          end
        end
      end
    end
    return cecho("  <grey>icefx migrate <effect> or icefx migrate all takes the package version; runs and alerts are kept<reset>\n")
  end

  local keys
  if arg:lower() == "all" then
    keys = fx.migratable()
    if #keys == 0 then return say("every built-in effect matches the package") end
  else
    local key = need(arg); if not key then return end
    if not fx.BUILTIN[key] then return say(fx.label(key) .. " is not a built-in effect") end
    if not fx.builtinDiff(key) then return say(fx.label(key) .. " already matches the package") end
    keys = { key }
  end
  for _, key in ipairs(keys) do fx.migrate(key) end
  fx.save()
  fx.rebuildTriggers()
  fx.render()
  say("migrated to the package version: " .. labels(keys))
end

-- =============================================================
-- Reload and update — reinstall from a local build, a URL, or the
-- latest GitHub release.
-- =============================================================
fx.REPO        = "destor/icefx"
fx.RELEASE_URL = "https://github.com/" .. fx.REPO .. "/releases/latest/download/IcesusEffects.mpackage"
fx.LATEST_API  = "https://api.github.com/repos/" .. fx.REPO .. "/releases/latest"

-- Download url to path, then call onDone(path) or onErr(message).
-- The handlers live outside the package, so they survive a reinstall.
local function fetch(url, path, onDone, onErr)
  local doneH, errH
  local function cleanup()
    if doneH then pcall(killAnonymousEventHandler, doneH) end
    if errH then pcall(killAnonymousEventHandler, errH) end
  end
  doneH = registerAnonymousEventHandler("sysDownloadDone", function(_, file)
    if file ~= path then return end
    cleanup()
    onDone(path)
  end)
  errH = registerAnonymousEventHandler("sysDownloadError", function(_, msg, file)
    if file and file ~= path then return end
    cleanup()
    onErr(tostring(msg))
  end)
  local ok, err = pcall(downloadFile, path, url)
  if not ok then cleanup(); onErr(tostring(err)) end
end

-- Swap the installed package for the .mpackage at path. Deferred:
-- this can run inside the package's own alias, which the uninstall
-- removes.
local function installFrom(path)
  fx.reloading = true
  tempTimer(0, function()
    uninstallPackage(fx.PACKAGE)
    installPackage(path)
  end)
end

-- Downloads go to their own folder under the exact package file name,
-- so Mudlet sees the same package whatever the URL was called.
local function downloadPath()
  local dir = getMudletHomeDir() .. "/IcesusEffects.download"
  if lfs and lfs.mkdir then pcall(lfs.mkdir, dir) end
  return dir .. "/IcesusEffects.mpackage"
end

-- `icefx update [latest|<file>|<url>]` with a source, or a saved one:
--   (nothing)  the saved file or URL, else the latest release
--   latest     the latest release, leaving the saved source alone
--   <source>   that file or URL, saved for next time
-- A URL is downloaded first, and the installed package is only
-- replaced once the download succeeded.
function fx.reinstall(arg)
  arg = trim(arg or "")
  local src, remember
  if arg:lower() == "latest" then
    src = fx.RELEASE_URL
  elseif arg ~= "" then
    src, remember = arg, true
  else
    src = fx.data.packagePath or fx.RELEASE_URL
  end

  if src:match("^https?://") then
    say("downloading " .. src)
    fetch(src, downloadPath(), function(path)
      if remember then fx.data.packagePath = src; fx.save() end
      say("downloaded; reinstalling")
      installFrom(path)
    end, function(msg)
      say("<red>download failed: " .. msg .. "<reset> — the installed package is unchanged")
    end)
    return
  end

  local path = src:gsub("^~", os.getenv("HOME") or "~")
  if not (io.exists and io.exists(path)) then
    return say("<red>no such file: " .. path .. "<reset>")
  end
  if remember then fx.data.packagePath = path; fx.save() end
  say("reinstalling from " .. path)
  installFrom(path)
end

-- `icefx update`: ask GitHub for the latest release and install it if
-- it is newer than this version.
function fx.update()
  local path = getMudletHomeDir() .. "/IcesusEffects.latest.json"
  say("checking " .. fx.REPO .. " for a newer release")
  fetch(fx.LATEST_API, path, function()
    local f = io.open(path, "r")
    local body = f and f:read("*a") or ""
    if f then f:close() end
    pcall(os.remove, path)
    local latest = body:match('"tag_name"%s*:%s*"v?([^"]+)"')
    if not latest then
      return say("<red>couldn't read the latest release from GitHub<reset>")
    end
    if fx.versionNewer(latest, fx.version) then
      say(string.format("v%s is out (you have v%s) — installing", latest, fx.version))
      fx.reinstall("latest")
    else
      say(string.format("up to date: v%s (latest release v%s)", fx.version, latest))
    end
  end, function(msg)
    say("<red>couldn't reach GitHub: " .. msg .. "<reset>")
  end)
end

local function changed()
  fx.save()
  fx.rebuildTriggers()
  fx.render()
end

local function cmdOnOff(rest, verb)
  local key = need(rest); if not key then return end
  local ok
  if verb == "on" then ok = fx.activate(key) else ok = fx.deactivate(key) end
  fx.render()
  if ok then return say(fx.label(key) .. ": " .. verb) end
  say(fx.label(key) .. " is already " .. verb)
end

local function cmdUpdate(rest)
  if trim(rest) == "" and not fx.data.packagePath then return fx.update() end
  fx.reinstall(rest)
end

local function cmdBaseline()
  local backup = fx.resetToBaseline()
  fx.warned = {}
  fx.cues.flash, fx.cues.banners = {}, {}
  fx.rebuildTriggers()
  fx.render()
  say("back to the shipped effects; runs and settings wiped")
  say("<grey>the old data is in " .. backup .. "<reset>")
end

local function cmdAdd(rest)
  local label = trim(rest)
  if label == "" then return say("<red>usage: icefx add <name><reset>") end
  local key = fx.define(label)
  if not key then return say("already defined: " .. fx.label(label:lower())) end
  changed()
  local id = listId(key)
  say(string.format('added <white>%s<reset> as #%d — now give it messages: icefx config %d effect.on="..." effect.off="..."', label, id, id))
end

local function cmdTest(rest)
  local hits = fx.matchLine(rest)
  if #hits == 0 then return say("no message matches that line") end
  for _, h in ipairs(hits) do
    say(string.format("%s → %s%s", fx.label(h.key), h.kind,
      h.off and " <red>(disabled: no trigger)<reset>" or ""))
  end
end

-- Every command, in help order. `names` share one handler, which gets
-- the name typed; `aliases` are older spellings, mapped to a name and
-- left out of the help. `main` commands are what plain `icefx` lists;
-- `icefx help all` lists the rest too, and `icefx <command> help` or
-- `icefx help <command>` prints `help`, as does a `needsArg` command
-- typed with nothing after it.
local cmdHelp
fx.COMMANDS = {
  { names = { "list" }, main = true,
    usage = "list [all|unseen|off|<tag>]", summary = "your effects",
    help = {
      "Without an argument: the effects you have seen that are enabled.",
      "all: every effect. unseen: not seen yet. off: disabled. <tag>: effects with the tag.",
      "An effect keeps its number in every view; use it wherever <effect> is asked for.",
    },
    run = function(rest) cmdList(rest) end },
  { names = { "show" }, needsArg = true, main = true,
    usage = "show <effect>", summary = "its settings and recorded runs",
    help = { "<effect> is its number in icefx list, its name, or the start of the name." },
    run = function(rest) cmdShow(rest) end },
  { names = { "add" }, needsArg = true, main = true,
    usage = "add <name>", summary = "track a new effect",
    help = { 'Then give it messages: icefx config <effect> effect.on="..." effect.off="..."' },
    run = cmdAdd },
  { names = { "config" }, aliases = { set = "config" }, needsArg = true, main = true,
    usage = "config <effect> <setting>=<value>", summary = "change settings (icefx config help)",
    help = settingsHelp,
    run = function(rest) cmdConfig(rest) end },
  { names = { "on", "off" }, aliases = { activate = "on", deactivate = "off" }, needsArg = true, main = true,
    usage = "on|off <effect>", summary = "fix its state when a message was missed",
    help = { "The real start is unknown, so the button shows a minimum (≥1:05) and the run isn't learned." },
    run = cmdOnOff },
  { names = { "clear" }, main = true,
    usage = "clear", summary = "dismiss expired buttons",
    help = { "Clicking an expired button dismisses just that one." },
    run = function() fx.clearExpired(); fx.render(); say("expired effects cleared") end },
  { names = { "enable", "disable" }, needsArg = true, main = true,
    usage = "enable|disable <effect|tag>", summary = "start / stop tracking it",
    help = {
      "A disabled effect has no triggers and no button, and icefx list leaves it out.",
      "An effect is disabled when it, or any one of its tags, is disabled.",
      "A number or an effect's full name means the effect; then a tag's full name;",
      "then the start of an effect's name.",
    },
    run = cmdEnable },
  { names = { "tags" }, main = true,
    usage = "tags", summary = "tags and how many effects have each",
    help = {
      "icefx list <tag> shows a tag's effects; icefx disable <tag> stops tracking them.",
      'Change an effect\'s tags with icefx config <effect> effect.tags="a b".',
    },
    run = cmdTags },
  { names = { "update" }, aliases = { reload = "update" }, main = true,
    usage = "update [latest|<file>|<url>]", summary = "install the latest release",
    help = {
      "No argument: reinstall from the file or URL saved last time; with nothing",
      "saved, install the latest release if it is newer than this version.",
      "latest: install the latest release now. The saved file or URL stays saved.",
      "<file> or <url>: install that .mpackage, and save it for next time.",
      "A URL is downloaded before anything is uninstalled; your data is kept.",
    },
    run = cmdUpdate },
  { names = { "remove" }, needsArg = true,
    usage = "remove <effect>", summary = "delete it",
    help = { "A removed built-in stays removed; icefx reset-to-baseline brings it back." },
    run = function(rest)
      local key = need(rest); if not key then return end
      local label = fx.label(key)
      fx.undefine(key)
      changed()
      say(label .. ": removed")
    end },
  { names = { "forget" }, needsArg = true,
    usage = "forget <effect>", summary = "wipe its recorded runs",
    run = function(rest)
      local key = need(rest); if not key then return end
      fx.forget(key)
      changed()
      say(fx.label(key) .. ": recorded runs wiped")
    end },
  { names = { "reset" },
    usage = "reset", summary = "everything off, all buttons gone",
    help = { "Nothing is learned from the runs it ends." },
    run = function() fx.reset(); fx.render(); say("all effects off") end },
  { names = { "reset-to-baseline" },
    usage = "reset-to-baseline", summary = "back to a fresh install",
    help = {
      "Only the shipped effects remain, as shipped: no runs, alerts, tags or effects of your own.",
      "The old data is saved to IcesusEffects.backup.lua first.",
    },
    run = cmdBaseline },
  { names = { "sync" },
    usage = "sync", summary = "run `effects` and match it",
    help = { "Listed effects go on, unlisted ones off, and unknown names become new effects." },
    run = function() fx.pendingSync = true; send("effects", false) end },
  { names = { "migrate" },
    usage = "migrate [<effect>|all]", summary = "compare built-ins with the package / take its version",
    help = {
      "No argument: the built-ins whose copy differs from the package, and how.",
      "<effect> or all: take the package's label, timed setting, messages and tags.",
      "Runs, alerts and enable/disable are kept.",
    },
    run = function(rest) cmdMigrate(rest) end },
  { names = { "test" }, needsArg = true,
    usage = "test <line>", summary = "which messages a line matches",
    help = { "A message is the start of a sentence of output; start it with re: for a regex." },
    run = cmdTest },
  { names = { "help" },
    usage = "help [all|<command>]", summary = "this list, every command, or one in detail",
    run = function(rest) cmdHelp(rest) end },
}

-- name or alias → { command, the name its handler gets }
local COMMAND_INDEX = {}
for _, c in ipairs(fx.COMMANDS) do
  for _, n in ipairs(c.names) do COMMAND_INDEX[n] = { c, n } end
  for a, n in pairs(c.aliases or {}) do COMMAND_INDEX[a] = { c, n } end
end

-- Commands are dim cyan, which cecho has no name for, so their lines
-- go through decho and its <r,g,b> colours.
local CMD_RGB, GREY_RGB = "0,139,139", "160,160,160"

local function usageLine(c)
  decho(string.format("  <%s>%-40s<r> %s\n", CMD_RGB, "icefx " .. c.usage, c.summary))
end

--
-- Usage:
--   icefx show <effect>  — its settings and recorded runs
--   <help lines>
--
local function commandHelp(c)
  cecho("\n<white>Usage:<reset>\n")
  decho(string.format("  <%s>icefx %s<r>  <%s>— %s<r>\n", CMD_RGB, c.usage, GREY_RGB, c.summary))
  local lines = type(c.help) == "function" and c.help() or c.help or {}
  for _, l in ipairs(lines) do cecho("  " .. l .. "\n") end
  local old = {}
  for a in pairs(c.aliases or {}) do old[#old + 1] = a end
  table.sort(old)
  if #old > 0 then cecho("  <grey>also: " .. table.concat(old, ", ") .. "<reset>\n") end
  cecho("\n")
end

cmdHelp = function(arg)
  local what = trim(arg or ""):lower()
  if what ~= "" and what ~= "all" then
    local hit = COMMAND_INDEX[what]
    if not hit then return say("<red>no such command: " .. what .. "<reset> — icefx help all") end
    return commandHelp(hit[1])
  end
  say(string.format("Icesus Effects v%s", fx.version))
  for _, c in ipairs(fx.COMMANDS) do
    if c.main then usageLine(c) end
  end
  if what == "all" then
    cecho("\n")
    for _, c in ipairs(fx.COMMANDS) do
      if not c.main then usageLine(c) end
    end
    decho(string.format("\n  <%s>icefx <command> help<r><%s> shows one command in detail<r>\n",
      CMD_RGB, GREY_RGB))
  else
    decho(string.format("\n  <%s>icefx help all<r><%s> lists every command; <r><%s>icefx <command> help<r><%s> shows one in detail<r>\n",
      CMD_RGB, GREY_RGB, CMD_RGB, GREY_RGB))
  end
end

function fx.command(args)
  args = trim(args or "")
  local verb, rest = args:match("^(%S+)%s*(.*)$")
  if not verb then return cmdHelp("") end
  local hit = COMMAND_INDEX[verb:lower()]
  if not hit then
    return say("<red>unknown command: " .. verb .. "<reset> — icefx help")
  end
  if rest:lower() == "help" or (hit[1].needsArg and rest == "") then
    return commandHelp(hit[1])
  end
  hit[1].run(rest, hit[2])
end

-- =============================================================
-- Lifecycle.
-- =============================================================
function fx.install()
  fx.load()
  fx.live = fx.live or {}
  fx.buildUI()
  fx.rebuildTriggers()
  fx.handlers = {
    registerAnonymousEventHandler("sysWindowResizeEvent", function() fx.render() end),
    -- The HUD moves the console borders when it (re)builds.
    registerAnonymousEventHandler("icesus.hudReady", function() fx.render() end),
    registerAnonymousEventHandler("sysExitEvent", function() fx.save() end),
    registerAnonymousEventHandler("sysUninstallPackage", function(_, pkg)
      if pkg == fx.PACKAGE then fx.teardown() end
    end),
  }
  -- Twice a second, so alert pulses can alternate.
  fx.timer = tempTimer(0.5, function()
    fx.checkWarnings()
    fx.render()
  end, true)
  fx.render()
  if fx.reloading then
    fx.reloading = nil
    cecho(string.format("\n<SkyBlue>[icefx]<reset> Icesus Effects v%s reloaded.\n", fx.version))
  end
  if fx.updated and #fx.updated > 0 then
    say(string.format("the package changed %d built-in effect(s) you have: %s — <white>icefx migrate<reset> to compare",
      #fx.updated, labels(fx.updated)))
  end
end

function fx.teardown()
  if fx.timer then pcall(killTimer, fx.timer); fx.timer = nil end
  for _, h in ipairs(fx.handlers or {}) do pcall(killAnonymousEventHandler, h) end
  fx.handlers = {}
  fx.killTriggers()
  if fx.ui then
    for _, r in ipairs(fx.ui.rows) do pcall(function() r.c:hide() end) end
    pcall(function() fx.ui.box:hide() end)
    if fx.ui.banner then pcall(function() fx.ui.banner:hide() end) end
    fx.ui = nil
  end
  fx.save()
end

-- A re-run (package reinstall, or an edit to this script in Mudlet's
-- editor) must not leave the previous instance's triggers, timer and
-- widgets behind.
pcall(fx.teardown)
fx.install()
