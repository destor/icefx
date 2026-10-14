#!/usr/bin/env luajit
-- Unit tests for src/{builtins,data,ui,controller}.lua under a mocked Mudlet API.
--
-- Mudlet runs Lua 5.1, so run these with LuaJIT:
--   luajit tests/test_effects.lua
-- Exits non-zero if any check fails.

local REPO = (arg[0]:gsub("/tests/test_effects%.lua$", ""))
if REPO == arg[0] then REPO = "." end
local HOME = os.getenv("TMPDIR") and (os.getenv("TMPDIR") .. "/icesusfx-test-home")
  or "/tmp/icesusfx-test-home"
os.execute("rm -rf '" .. HOME .. "' && mkdir -p '" .. HOME .. "'")

-- ----------------------------------------------------------------
-- Mocked Mudlet.
-- ----------------------------------------------------------------
local W = { clock = 1000, triggers = {}, events = {}, echoes = {}, widgets = {},
            borders = { top = 92, right = 360, bottom = 64, left = 0 },
            win = { 1600, 1000 } }

function getEpoch() return W.clock end
function getMudletHomeDir() return HOME end
function getMainWindowSize() return W.win[1], W.win[2] end
function getBorderTop() return W.borders.top end
function getBorderRight() return W.borders.right end
function getBorderBottom() return W.borders.bottom end
function getBorderLeft() return W.borders.left end
function cecho(s) W.echoes[#W.echoes + 1] = s end
function raiseEvent(name, ...) W.events[#W.events + 1] = { name, ... } end
W.handlers, W.nextHandler, W.downloads = {}, 0, {}
function registerAnonymousEventHandler(ev, fn)
  W.nextHandler = W.nextHandler + 1
  W.handlers[W.nextHandler] = { ev = ev, fn = fn }
  return W.nextHandler
end
function killAnonymousEventHandler(id) W.handlers[id] = nil end
-- Raise a Mudlet event at every handler registered for it.
local function fire(ev, ...)
  local list = {}
  for id, h in pairs(W.handlers) do if h.ev == ev then list[#list + 1] = h.fn end end
  for _, fn in ipairs(list) do fn(ev, ...) end
end
function downloadFile(path, url) W.downloads[#W.downloads + 1] = { path = path, url = url } end
lfs = { mkdir = function() end }
W.timers = {}
function tempTimer(_, fn) W.timers[#W.timers + 1] = fn; return #W.timers end
function tempLineTrigger() return 1 end
function send(cmd) W.sent = cmd end
function uninstallPackage(name) W.uninstalled = name end
function installPackage(path) W.installed = path end
function killTimer() end

local nextTrig = 0
local function addTrig(kind, pat, fn)
  nextTrig = nextTrig + 1
  W.triggers[nextTrig] = { kind = kind, pat = pat, fn = fn }
  return nextTrig
end
function tempTrigger(pat, fn) return addTrig("sub", pat, fn) end
function tempRegexTrigger(pat, fn) return addTrig("re", pat, fn) end
function killTrigger(id) W.triggers[id] = nil end

-- A stand-in for Mudlet's PCRE (rex.match), covering the regex the
-- package generates and the built-ins use: ^ and $, \-escapes, \w,
-- [..] classes, and the . + * ? quantifiers on one item. Anything else
-- (groups, alternation) raises, so a test can't pass by accident on a
-- pattern this doesn't support.
local function pcreToLua(re)
  local out, i = {}, 1
  while i <= #re do
    local c = re:sub(i, i)
    if c == "\\" then
      local n = re:sub(i + 1, i + 1)
      out[#out + 1] = (n == "w") and "[%w_]" or (n:match("%p") and "%" .. n or n)
      i = i + 2
    elseif c == "[" then
      local j = re:find("]", i + 1, true)
      out[#out + 1] = re:sub(i, j)
      i = j + 1
    elseif c == "(" or c == "|" or c == "{" then
      error("pcre stand-in can't handle: " .. re)
    elseif c == "^" and i == 1 or c == "$" and i == #re or c:match("[%.%+%*%?]") then
      out[#out + 1] = c
      i = i + 1
    else
      out[#out + 1] = c:match("%p") and "%" .. c or c
      i = i + 1
    end
  end
  return table.concat(out)
end
rex = { match = function(subject, re) return subject:match(pcreToLua(re)) end }

-- Deliver a line the way Mudlet's trigger engine would.
local function deliver(s)
  line = s   -- Mudlet's global for the current line
  for _, t in pairs(W.triggers) do
    local hit
    if t.kind == "sub" then
      hit = s:find(t.pat, 1, true)
    else
      local ok, m = pcall(rex.match, s, t.pat)
      hit = ok and m
    end
    if hit then t.fn() end
  end
end

io.exists = function(p) local f = io.open(p, "r"); if f then f:close() end; return f ~= nil end

local function ser(v, ind)
  if type(v) == "table" then
    local out = { "{\n" }
    for k, x in pairs(v) do
      local key = type(k) == "string" and string.format("[%q]", k) or "[" .. k .. "]"
      out[#out + 1] = ind .. "  " .. key .. " = " .. ser(x, ind .. "  ") .. ",\n"
    end
    out[#out + 1] = ind .. "}"
    return table.concat(out)
  elseif type(v) == "string" then return string.format("%q", v) end
  return tostring(v)
end
function table.save(path, t)
  local f = assert(io.open(path, "w")); f:write("return " .. ser(t, "")); f:close()
end
function table.load(path, into)
  local t = assert(loadfile(path))()
  for k, v in pairs(t) do into[k] = v end
end

-- Geyser: record what the render did to each widget.
local function widget(cons)
  local w = { name = cons.name, x = cons.x, y = cons.y, width = cons.width,
              height = cons.height, visible = true }
  W.widgets[cons.name] = w
  function w:move(x, y) self.x, self.y = x, y end
  function w:resize(a, b) self.width, self.height = a, b end
  function w:show() self.visible = true end
  function w:hide() self.visible = false end
  function w:echo(s) self.text = s end
  function w:setStyleSheet(s) self.style = s end
  function w:setToolTip(s) self.tip = s end
  function w:setClickCallback(fn) self.click = fn end
  return w
end
Geyser = { Container = {}, Label = {} }
function Geyser.Container:new(c) return widget(c) end
function Geyser.Label:new(c) return widget(c) end

-- ----------------------------------------------------------------
-- Harness.
-- ----------------------------------------------------------------
local fails, checks = 0, 0
local function check(cond, msg)
  checks = checks + 1
  if not cond then fails = fails + 1; print("FAIL: " .. msg) end
end
local function eq(a, b, msg) check(a == b, msg .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end

local function boot()
  icesusfx = nil
  W.triggers = {}
  W.widgets = {}
  for _, f in ipairs({ "builtins", "data", "ui", "controller" }) do
    dofile(REPO .. "/src/" .. f .. ".lua")
  end
  return icesusfx
end

local line = deliver

-- An effect's number in `icefx list`, as a string for commands.
local function idOf(fx, key)
  for i, k in ipairs(fx.sortedKeys()) do if k == key then return tostring(i) end end
end

-- Message patterns across all definitions: one trigger each.
local function patternCount(fx)
  local n = 0
  for _, def in pairs(fx.data.defs) do
    for _, kind in ipairs(fx.KINDS) do n = n + #(def[kind] or {}) end
  end
  return n
end
local ON  = "You are suddenly enveloped into coldness of netherplane that feels like it would suck out your"
local REF = "Essence of the nether around you rapidly replenishes its power."
local OFF = "You feel essence of the nether leave your body."
local KEY = "essence of the nether"

-- ----------------------------------------------------------------
-- Tests.
-- ----------------------------------------------------------------
local fx = boot()

-- Builtin seeded and wired.
check(fx.data.defs[KEY] ~= nil, "builtin essence seeded")
eq(#fx.triggerIds, patternCount(fx) + 2, "one trigger per pattern, plus two for effects output")
check(io.exists(HOME .. "/IcesusEffects.lua"), "data file written on first run")

-- First application: no estimate yet.
line(ON)
local e = fx.live[KEY]
check(e and not e.ended, "on message starts the effect")
W.clock = W.clock + 65
local v = fx.view(e, W.clock)
eq(v.right, "1:05 / ?", "first run shows elapsed and unknown estimate")
eq(v.est, nil, "no estimate before first sample")
check(W.widgets["icesusfx.box"].visible, "box shown with an active effect")

-- Refresh restarts the clock; the run is measured from the refresh.
line(REF)
eq(e.started, W.clock, "refresh restarts the clock")
eq(e.refreshes, 1, "refresh counted")
W.clock = W.clock + 300
line(OFF)
check(e.ended ~= nil, "off message ends it")
eq(e.lasted, 300, "lasted measured from last refresh")
eq(fx.estimate(KEY), 300, "first sample becomes the estimate")

-- Expired stays visible, struck through, until dismissed.
fx.render()
local bg = W.widgets["icesusfx.row1.bg"]
check(bg.visible and bg.text:find("<s>Essence of the nether</s>", 1, true), "expired row shown struck")
check(bg.text:find("5:00", 1, true), "expired row shows how long it lasted")
check(not W.widgets["icesusfx.row1.back"].visible, "expired row hides the bar")

-- Second run: estimate available, bar drains.
line(ON)
e = fx.live[KEY]
check(not e.ended, "re-application replaces the expired entry")
W.clock = W.clock + 150
v = fx.view(e, W.clock)
eq(v.right, "2:30 / ~5:00", "estimate shown")
eq(v.remain, 0.5, "half remaining")
fx.render()
eq(W.widgets["icesusfx.row1.fill"].width, math.floor((fx.config.width - 14) * 0.5 + 0.5), "fill width tracks remaining")
check(W.widgets["icesusfx.row1.back"].visible, "active timed row shows bar")

W.clock = W.clock + 200
v = fx.view(e, W.clock)
eq(v.state, "overdue", "past the estimate is overdue")
eq(v.remain, 0, "overdue bar empty")
line(OFF)
eq(fx.estimate(KEY), 325, "estimate is the mean of runs")

-- Misfire too short to be a sample.
line(ON); W.clock = W.clock + 1; line(OFF)
eq(#fx.data.stats[KEY].samples, 2, "sub-minimum run not recorded")

-- Off without a seen start: expired, nothing learned.
fx.live = {}
line(OFF)
check(fx.live[KEY] and fx.live[KEY].ended and not fx.live[KEY].lasted, "unseen start shows expired with no duration")
eq(#fx.data.stats[KEY].samples, 2, "unseen start not recorded")

-- Click dismisses an expired button.
fx.render()
W.widgets["icesusfx.row1.bg"].click()
eq(fx.live[KEY], nil, "click dismisses expired")
check(not W.widgets["icesusfx.box"].visible, "box hidden when empty")

-- Placement: right edge of the main console, clear of the HUD column.
line(ON); fx.render()
local box = W.widgets["icesusfx.box"]
eq(box.x, 1600 - 360 - fx.config.width - fx.config.marginRight, "box hugs console right edge")
eq(box.y, 92 + fx.config.marginTop, "box below the banner")
W.borders.right = 0; fx.render()
eq(box.x, 1600 - fx.config.width - fx.config.marginRight, "box follows a border change")

-- Samples persist across sessions.
local samplesBefore = #fx.data.stats[KEY].samples
fx = boot()
eq(#fx.data.stats[KEY].samples, samplesBefore, "samples reloaded")
eq(fx.estimate(KEY), 325, "estimate survives reload")

-- Commands: define an untimed effect from the command line.
fx.command("add Stone skin")
fx.command('config stone effect.on="Your skin turns to stone." effect.off="Your skin softens." effect.timed=false')
local def = fx.data.defs["stone skin"]
eq(def.on[1], "Your skin turns to stone.", "on pattern added via prefix")
eq(def.timed, false, "timer off")
line("Your skin turns to stone.")
v = fx.view(fx.live["stone skin"], W.clock)
eq(v.right, nil, "untimed effect shows no times")
fx.render()
check(W.widgets["icesusfx.row1"].height == fx.config.rowHPlain, "untimed row is short")
W.clock = W.clock + 100
line("Your skin softens.")
eq(fx.data.stats["stone skin"], nil, "untimed effect records no samples")

local hits = fx.matchLine("Your skin softens.")
eq(#hits, 1, "fx test finds the pattern"); eq(hits[1].kind, "off", "fx test reports the kind")

fx.command("config stone effect.off.1=")
eq(#def.off, 0, "drop removes a pattern")
fx.command("add Ess")              -- now "ess" is both a key and a prefix of essence
eq(fx.resolve("ess"), "ess", "exact key wins over prefix")
fx.command("remove ess")
eq(fx.resolve("ess"), KEY, "unique prefix resolves")
local _, why = fx.resolve("e")
eq(why, "ambiguous", "ambiguous prefix reported")
fx.command("forget essence")
eq(fx.estimate(KEY), nil, "forget wipes samples")
fx.command("remove stone")
eq(fx.data.defs["stone skin"], nil, "remove deletes definition")

-- Removing a builtin sticks across reloads.
fx.command("remove essence")
fx = boot()
eq(fx.data.defs[KEY], nil, "removed builtin is not re-seeded")


-- ----------------------------------------------------------------
-- icefx commands: activate / deactivate / reset / list ids.
-- ----------------------------------------------------------------
os.remove(HOME .. "/IcesusEffects.lua")
fx = boot()
fx.command("add Fleshcraft")
fx.command("add Stone skin")
fx.command("set stone effect.timed=off")
eq(fx.resolve(idOf(fx, "fleshcraft")), "fleshcraft", "list number resolves")
fx.command("activate " .. idOf(fx, KEY))
e = fx.live[KEY]
check(e and not e.ended and e.partial, "forced activation is partial")
fx.addSample(KEY, 300)
W.clock = W.clock + 60
eq(fx.view(e, W.clock).right, "≥1:00 / ~5:00", "partial shows lower bound")
W.clock = W.clock + 60
line(OFF)
eq(#fx.data.stats[KEY].samples, 1, "partial run not learned")
eq(fx.live[KEY].lasted, nil, "partial run has no duration")

fx.command("activate essence")
line(REF)
check(not fx.live[KEY].partial, "refresh makes the start known")
W.clock = W.clock + 280
line(OFF)
eq(#fx.data.stats[KEY].samples, 2, "run after refresh is learned")

fx.command("activate stone")
fx.command("deactivate stone")
check(fx.live["stone skin"].ended, "deactivate ends it")
fx.command("activate flesh")
fx.command("reset")
check(next(fx.live) == nil, "reset clears everything")

W.echoes = {}
fx.command("")
check(table.concat(W.echoes):find("icefx activate", 1, true), "no args prints help")
W.echoes = {}
fx.command("activate " .. idOf(fx, "fleshcraft")); fx.command("list")
local out = table.concat(W.echoes)
check(out:find("Fleshcraft%s+<green>ON"), "list shows on")
check(out:find("Essence of the nether%s+<grey>off"), "list shows off")
check(out:find("~4:50", 1, true), "list shows estimate")

-- ----------------------------------------------------------------
-- `effects` output: entries rewritten as rows, OFF rows after, sync.
-- ----------------------------------------------------------------
fx.reset()
fx.command("activate stone")          -- on, but the game won't list it
fx.command("sync")
eq(W.sent, "effects", "sync sends effects")
local k, note
eq(fx.effectsLine("Beneficial effects affecting you:"), "listing", "header opens listing")
k, note = fx.effectsLine(" Fleshcraft")
eq(k, "entry", "entry line")
check(note:find("^ <green>ON <reset>  <white>Fleshcraft%s+<grey><reset>$"), "untimed row: ON, name, no timer")
k, note = fx.effectsLine(" Essence of the nether")
check(note:find("? / ~4:50", 1, true), "untracked timed row shows estimate, unknown elapsed")
k, note = fx.effectsLine(" Sanctuary")
check(note:find("Sanctuary", 1, true), "unknown name still gets a row")
local block
k, block = fx.effectsLine("No visible harmful effects affect you.")
eq(k, "listing", "none line keeps listing")
check(block and block:find("Tracked, now off", 1, true), "OFF block after the last line")
check(block:find("<grey>OFF<reset>  <grey>Stone skin", 1, true), "tracked-but-unlisted effect is an OFF row")
check(block:find("dropped", 1, true), "still-active-in-tracker shows dropped")
k, block = fx.effectsLine("No visible harmful effects affect you.")
eq(block, nil, "OFF block only once (trigger + line chain both see the line)")
W.echoes = {}
eq(fx.effectsLine("> "), "end", "prompt ends listing")
check(fx.isActive("fleshcraft") and fx.isActive(KEY), "listed effects turned on")
check(fx.live[KEY].partial, "synced effects are partial")
check(not fx.isActive("stone skin"), "unlisted effect turned off")
check(fx.data.defs["sanctuary"] and fx.data.defs["sanctuary"].label == "Sanctuary", "unknown effect added")
out = table.concat(W.echoes)
check(out:find("sync: new", 1, true) and out:find("sync: off", 1, true), "sync reports changes")

-- Row of an active entry; a listing ending in harmful entries gets
-- its OFF rows when it closes.
W.clock = W.clock + 30
fx.effectsLine("Beneficial effects affecting you:")
k, note = fx.effectsLine(" Essence of the nether")
check(note:find("≥0:30 / ~4:50", 1, true), "active row shows timing")
fx.effectsLine(" Fleshcraft"); fx.effectsLine(" Sanctuary")
k, block = fx.effectsLine("Harmful effects affecting you:")
eq(block, nil, "no OFF block at a harmful header")
fx.effectsLine(" Poisoned")
W.echoes = {}
fx.effectsLine("> ")
out = table.concat(W.echoes)
check(out:find("Stone skin%s+<grey>ended 0:30 ago"), "OFF block at close, with time since it ended")
fx.command("remove poisoned")
eq(fx.effectsLine(" Essence of the nether"), nil, "entries ignored outside a listing")

-- Manual `effects` with no changes says nothing.
W.echoes = {}
fx.effectsLine("Beneficial effects affecting you:")
fx.effectsLine(" Fleshcraft"); fx.effectsLine(" Essence of the nether"); fx.effectsLine(" Sanctuary")
fx.effectsLine("No visible harmful effects affect you.")
fx.finishEffects()
eq(#W.echoes, 0, "quiet when nothing changed")

-- ----------------------------------------------------------------
-- reload
-- ----------------------------------------------------------------
-- Nothing saved: download the latest release, install once it lands.
W.echoes, W.downloads, W.timers, W.installed, W.uninstalled = {}, {}, {}, nil, nil
fx.command("reload")
local dl = W.downloads[1]
eq(dl and dl.url, fx.RELEASE_URL, "reload with nothing saved fetches the latest release")
check(dl.path:find("/IcesusEffects%.mpackage$"), "download keeps the package file name")
eq(#W.timers, 0, "nothing uninstalled before the download finishes")
fire("sysDownloadDone", "/some/other/file")
eq(#W.timers, 0, "other downloads are ignored")
fire("sysDownloadDone", dl.path)
W.timers[#W.timers]()
eq(W.uninstalled, "IcesusEffects", "uninstalled after download")
eq(W.installed, dl.path, "installed from the downloaded file")
eq(fx.data.packagePath, nil, "the default source is not saved")

-- A failed download leaves the installed package alone.
W.echoes, W.downloads, W.timers, W.installed, W.uninstalled = {}, {}, {}, nil, nil
fx.command("reload latest")
fire("sysDownloadError", "404 not found", W.downloads[1].path)
eq(W.uninstalled, nil, "failed download: nothing uninstalled")
check(table.concat(W.echoes):find("download failed", 1, true), "failed download reported")
fire("sysDownloadDone", W.downloads[1].path)
eq(#W.timers, 0, "handlers removed after an error")

-- An explicit URL is saved for next time.
W.downloads, W.timers = {}, {}
fx.command("reload https://example.org/x.mpackage")
eq(W.downloads[1].url, "https://example.org/x.mpackage", "explicit URL fetched")
fire("sysDownloadDone", W.downloads[1].path)
eq(fx.data.packagePath, "https://example.org/x.mpackage", "explicit URL remembered")
W.downloads = {}
fx.command("reload latest")
eq(W.downloads[1].url, fx.RELEASE_URL, "reload latest ignores the saved source")
eq(fx.data.packagePath, "https://example.org/x.mpackage", "reload latest keeps the saved source")
fire("sysDownloadDone", W.downloads[1].path)

-- update: compare with the latest release tag.
local function latestIs(tag)
  W.echoes, W.downloads, W.timers = {}, {}, {}
  fx.command("update")
  local api = W.downloads[1]
  eq(api.url, fx.LATEST_API, "update asks the releases API")
  local f = io.open(api.path, "w")
  f:write('{"url":"x","tag_name": "' .. tag .. '","name":"y"}'); f:close()
  fire("sysDownloadDone", api.path)
end
latestIs("v" .. fx.version)
eq(#W.downloads, 1, "same version: nothing downloaded")
check(table.concat(W.echoes):find("up to date", 1, true), "same version: up to date")
latestIs("v0.0.1")
eq(#W.downloads, 1, "older release: nothing downloaded")
latestIs("v99.0.0")
eq(W.downloads[2] and W.downloads[2].url, fx.RELEASE_URL, "newer release: downloads it")
check(table.concat(W.echoes):find("v99.0.0 is out", 1, true), "newer release announced")
fire("sysDownloadDone", W.downloads[2].path)

check(fx.versionNewer("0.10.0", "0.9.9"), "versions compare numerically")
check(not fx.versionNewer("0.3.0", "0.3.0"), "equal is not newer")
check(fx.versionNewer("1.0", "0.9.9"), "shorter version compares")
check(not fx.versionNewer("junk", "0.1.0"), "junk is never newer")

-- A local file.
local pkg = HOME .. "/IcesusEffects.mpackage"
io.open(pkg, "w"):close()
W.timers = {}
fx.command("reload " .. pkg)
W.timers[#W.timers]()
eq(W.uninstalled, "IcesusEffects", "reload uninstalls")
eq(W.installed, pkg, "reload installs from path")
fx = boot()
eq(fx.data.packagePath, pkg, "reload path remembered")


-- ----------------------------------------------------------------
-- icefx config: parsing and settings.
-- ----------------------------------------------------------------
os.remove(HOME .. "/IcesusEffects.lua")
fx = boot()
local name, sets, err = fx.parseConfig('1 effect.on="He said "hi" to you" alert.flash=on effect.off+="Bye."')
eq(name, "1", "parse: effect name")
eq(err, nil, "parse: no error")
eq(#sets, 3, "parse: three assignments")
eq(sets[1].value, 'He said "hi" to you', "parse: quotes inside a quoted value")
eq(sets[2].value, "on", "parse: unquoted value")
eq(sets[3].op, "+=", "parse: append op")
name, sets = fx.parseConfig("essence of the nether alert.warn=10")
eq(name, "essence of the nether", "parse: multi-word name")
name, sets = fx.parseConfig("essence")
eq(#sets, 0, "parse: no settings means show")
name, sets, err = fx.parseConfig('1 effect.on="unterminated')
check(err and err:find("quote"), "parse: unterminated quote reported")

fx.command('config essence effect.on+="Second start." alert.flash=true alert.banner=yes alert.warn=10s')
local d = fx.data.defs[KEY]
eq(#d.on, 2, "+= appends")
eq(d.on[2], "Second start.", "appended message")
local al = fx.alerts(KEY)
check(al.flash and al.banner and al.warn == 10, "alerts set")
eq(#fx.triggerIds, patternCount(fx) + 2, "triggers rebuilt for new message")
fx.command('config essence effect.on.2="Changed start."')
eq(d.on[2], "Changed start.", ".N replaces")
fx.command('config essence effect.on="Only start."')
eq(#d.on, 1, "= replaces the whole list"); eq(d.on[1], "Only start.", "replaced value")
local ok, why = fx.setSetting(KEY, "alert.flash", "=", "maybe")
check(not ok and why:find("true or false"), "bad bool rejected")
ok, why = fx.setSetting(KEY, "alert.warn", "+=", "5")
check(not ok, "+= rejected for scalar")
ok, why = fx.setSetting(KEY, "effect.nope", "=", "x")
check(not ok and why:find("unknown"), "unknown setting rejected")
W.echoes = {}
fx.command("show essence")
out = table.concat(W.echoes)
check(out:find("alert.warn", 1, true) and out:find('"Only start."', 1, true), "show prints settings")
fx.command("config essence alert.warn=off")
eq(fx.alerts(KEY).warn, nil, "warn off")
fx.command('config essence effect.on="You are suddenly enveloped into coldness of netherplane"')

-- ----------------------------------------------------------------
-- Alerts: flash and banner on expiry, warning before it.
-- ----------------------------------------------------------------
fx.addSample(KEY, 100)
fx.command("config essence alert.warn=10")
line(ON)
e = fx.live[KEY]
W.clock = W.clock + 80
fx.checkWarnings()
v = fx.view(e, W.clock)
check(not v.warning, "no warning before the window")
eq(#fx.cues.banners, 0, "no banner yet")
W.clock = W.clock + 12           -- 8 s left
fx.checkWarnings()
v = fx.view(e, W.clock)
check(v.warning, "warning inside the window")
eq(#fx.cues.banners, 1, "warning banner raised")
check(fx.cues.banners[1].text:find("0:08 left", 1, true), "warning banner says time left")
fx.checkWarnings()
eq(#fx.cues.banners, 1, "warning banner only once")
fx.render()
check(W.widgets["icesusfx.row1.bg"].style:find("251,191,36", 1, true) or
      W.widgets["icesusfx.row1.bg"].style:find("#fbbf24", 1, true), "warning row styled amber")
line(REF)                        -- refresh: warning cleared, can fire again
v = fx.view(e, W.clock)
check(not v.warning, "refresh clears warning")

W.clock = W.clock + 50
fx.cues.banners = {}
line(OFF)
v = fx.view(fx.live[KEY], W.clock)
eq(v.state, "flash", "expired button flashes")
eq(#fx.cues.banners, 1, "expiry banner raised")
check(fx.cues.banners[1].text:find("— off", 1, true), "expiry banner text")
check(W.widgets["icesusfx.banner"].visible, "banner widget shown")
W.clock = W.clock + fx.config.flashSecs + 1
fx.render()
eq(fx.view(fx.live[KEY], W.clock).state, "expired", "flash stops")
check(not W.widgets["icesusfx.banner"].visible, "banner hidden after its time")

-- No alerts configured: nothing fires.
fx.command("config essence alert.flash=false alert.banner=false alert.warn=off")
line(ON); W.clock = W.clock + 5; line(OFF)
eq(fx.view(fx.live[KEY], W.clock).state, "expired", "no flash when off")
eq(#fx.cues.banners, 0, "no banner when off")


-- ----------------------------------------------------------------
-- reset-to-baseline
-- ----------------------------------------------------------------
fx.command("add Custom thing")
fx.command("config essence alert.flash=on")
fx.addSample(KEY, 123)
line(ON)
fx.command("remove fleshcraft")
fx.data.packagePath = pkg
fx.command("reset-to-baseline")
eq(fx.data.defs["custom thing"], nil, "baseline drops user effects")
check(fx.data.defs["fleshcraft"] ~= nil, "baseline restores removed builtins")
eq(fx.estimate(KEY), nil, "baseline wipes runs")
eq(fx.alerts(KEY).flash, false, "baseline wipes alerts")
check(next(fx.live) == nil, "baseline clears live state")
eq(fx.data.packagePath, pkg, "baseline keeps the reload path")
local bk = {}
table.load(HOME .. "/IcesusEffects.backup.lua", bk)
check(bk.defs["custom thing"] ~= nil, "old data backed up")
local n = 0
for _ in pairs(fx.BUILTIN) do n = n + 1 end
local m = 0
for _ in pairs(fx.data.defs) do m = m + 1 end
eq(m, n, "only builtins remain")
eq(#fx.triggerIds, patternCount(fx) + 2, "triggers match baseline")


-- ----------------------------------------------------------------
-- migrate: local copies of built-ins vs the package.
-- ----------------------------------------------------------------
os.remove(HOME .. "/IcesusEffects.lua")
fx = boot()
eq(#fx.updated, 0, "fresh install announces nothing")
eq(#fx.migratable(), 0, "fresh install: everything matches")
local ship = fx.BUILTIN[KEY]
fx.command('config essence effect.label="Essence" effect.off+="Extra off." effect.timed=false')
fx.addSample(KEY, 200)
fx.command("config essence alert.flash=on")
local diff = fx.builtinDiff(KEY)
eq(#diff, 3, "label, timed and off differ")
eq(diff[1].field, "effect.label", "label diff"); eq(diff[1].to, ship.label, "label diff target")
eq(diff[3].field, "effect.off", "off diff")
eq(diff[3].added[1], nil, "nothing to add")
eq(diff[3].removed[1], "Extra off.", "local-only message would be removed")

-- Reload with an unchanged package: customised, but no announcement.
fx = boot()
eq(#fx.updated, 0, "customised but package unchanged: quiet")
eq(fx.migratable()[1], KEY, "still listed by icefx migrate")

-- Package update: the shipped definition changed since last load.
fx.data.shipped[KEY] = "an older package"
fx.save()
W.echoes = {}
fx = boot()
eq(fx.updated[1], KEY, "changed shipped effect announced")
check(table.concat(W.echoes):find("icefx migrate", 1, true), "announcement printed on load")
fx = boot()
eq(#fx.updated, 0, "announced only once")

W.echoes = {}
fx.command("migrate")
out = table.concat(W.echoes)
check(out:find("- Extra off.", 1, true) and out:find("effect.timed", 1, true), "migrate lists the changes")
fx.command("migrate essence")
eq(fx.builtinDiff(KEY), nil, "migrated effect matches the package")
eq(fx.label(KEY), ship.label, "label restored")
eq(fx.estimate(KEY), 200, "runs kept")
eq(fx.alerts(KEY).flash, true, "alerts kept")
eq(#fx.data.defs[KEY].off, #ship.off, "messages restored")
check(fx.data.defs[KEY].off ~= ship.off, "migrated lists are copies")

fx.command('config fleshcraft effect.timed=true')
fx.command('config mantle effect.on+="More shadows."')
eq(#fx.migratable(), 2, "two differ")
fx.command("migrate all")
eq(#fx.migratable(), 0, "migrate all fixes every one")
fx.command("add Homemade")
W.echoes = {}
fx.command("migrate homemade")
check(table.concat(W.echoes):find("not a built-in", 1, true), "user effects can't be migrated")


-- ----------------------------------------------------------------
-- Messages are bound to the start of the line.
-- ----------------------------------------------------------------
os.remove(HOME .. "/IcesusEffects.lua")
fx = boot()
eq(fx.messageRegex("A (b).c"), "^A \\(b\\)\\.c", "plain text escaped and anchored")
eq(fx.messageRegex("re:^Foo"), "^Foo", "regex used as written")
line("Bob says: " .. OFF)
eq(fx.live[KEY], nil, "message inside a say does not fire")
line("[party] Bob: " .. ON)
eq(fx.live[KEY], nil, "message inside a channel line does not fire")
line("> " .. ON)
eq(fx.live[KEY], nil, "anything before the message: no match")
line(ON)
check(fx.isActive(KEY), "message at line start fires")
line(OFF)
check(fx.live[KEY].ended, "plain line fires")
line("Kili creates a subdimensional rift around you, speeding up the universe inside it.")
check(fx.isActive("haste"), "caster-name regex fires")
line("Bob says: Kili creates a subdimensional rift around you, speeding up")
eq(#fx.matchLine("Bob says: You feel fervent in your devotion."), 0, "icefx test agrees: not at line start")
eq(fx.matchLine("You feel fervent in your devotion.")[1].key, "flagellation", "icefx test: at line start")


-- Every shipped plain message matches a line that starts with it.
for key, def in pairs(fx.BUILTIN) do
  for _, kind in ipairs(fx.KINDS) do
    for _, m in ipairs(def[kind] or {}) do
      if m:sub(1, 3) ~= "re:" then
        check(rex.match(m .. " and more", fx.messageRegex(m)), "builtin " .. key .. " " .. kind .. " matches itself")
      end
    end
  end
end

eq(fx.fmtTime(3725), "1:02:05", "hours format")
eq(fx.fmtTime(59.6), "1:00", "rounding")

print(string.format("%d/%d checks passed", checks - fails, checks))
os.exit(fails == 0 and 0 or 1)
