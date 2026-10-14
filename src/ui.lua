-- =============================================================
-- Icesus Effects — ui.lua: the floating buttons.
--
-- One button per effect along the right edge of the main
-- (scrolling) console: what each button says is worked out by
-- fx.view() as plain data, then fx.render() pushes it to Geyser
-- widgets. Reads the state in data.lua; never changes it except
-- through data.lua's functions.
-- =============================================================
icesusfx = icesusfx or {}
local fx = icesusfx

-- Colours: the HUD's palette when it is loaded, these otherwise.
local DEFAULT_PALETTE = {
  bgDeep = "#0c0e1a", bgMain = "#131629", border = "#2a2f4e",
  text = "#c8cdd8", textDim = "#8b90a5", textBright = "#eef0f6",
  ice = "#7dd3fc", green = "#3ddc84", red = "#f87171", amber = "#fbbf24",
}
local DEFAULT_FONT = '"JetBrains Mono", "DejaVu Sans Mono", "Courier New", monospace'

local function palette()
  local p = icesus and icesus.palette
  if type(p) ~= "table" then return DEFAULT_PALETTE end
  return setmetatable({}, { __index = function(_, k) return p[k] or DEFAULT_PALETTE[k] end })
end

local function fontStack()
  return (icesus and type(icesus.fontStack) == "string") and icesus.fontStack or DEFAULT_FONT
end

-- =============================================================
-- Formatting.
-- =============================================================
local function fmtTime(s)
  s = math.max(0, math.floor(s + 0.5))
  local h, m = math.floor(s / 3600), math.floor(s / 60) % 60
  if h > 0 then return string.format("%d:%02d:%02d", h, m, s % 60) end
  return string.format("%d:%02d", m, s % 60)
end
fx.fmtTime = fmtTime

local function esc(s)
  return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

-- Active effects first in the order they went up, then expired ones
-- newest first.
function fx.entries()
  local act, gone = {}, {}
  for _, e in pairs(fx.live) do
    if e.ended then gone[#gone + 1] = e else act[#act + 1] = e end
  end
  table.sort(act, function(a, b) return a.since < b.since end)
  table.sort(gone, function(a, b) return a.ended > b.ended end)
  for _, e in ipairs(gone) do act[#act + 1] = e end
  return act
end

-- Short-lived cues, keyed by effect: when an expired button stops
-- flashing. Banners are a list of { text, colour, untilT }.
fx.cues = fx.cues or { flash = {}, banners = {} }

-- Pulses alternate twice a second.
local function pulsePhase(t) return math.floor(t * 2) % 2 == 0 end

-- Everything one button shows, as plain data — kept apart from the
-- widgets so it can be tested without Mudlet.
function fx.view(e, t)
  local def = fx.data.defs[e.key] or {}
  local timed = def.timed ~= false
  local v = { key = e.key, name = fx.label(e.key), timed = timed, expired = e.ended ~= nil }
  local est = fx.estimate(e.key)
  if v.expired then
    v.state = "expired"
    if timed and e.lasted then v.right = fmtTime(e.lasted) end
    v.ago = t - e.ended
    if (fx.cues.flash[e.key] or 0) > t then
      v.state = "flash"
      v.pulse = pulsePhase(t)
    end
    return v
  end
  v.state = "active"
  if not timed then return v end
  local el = t - e.started
  v.elapsed = el
  v.est = est
  v.partial = e.partial
  -- Unknown real start: the elapsed time is at least this much, and the
  -- bar shows the most that can be left.
  local elText = (e.partial and "≥" or "") .. fmtTime(el)
  if est then
    v.right = elText .. " / ~" .. fmtTime(est)
    v.remain = math.max(0, 1 - el / est)
    if el > est then v.state = "overdue" end
  else
    v.right = elText .. " / ?"
  end
  -- alert.warn: pulse from N seconds before the estimated end until
  -- it is refreshed or falls off.
  local warn = fx.alerts(e.key).warn
  local left = fx.remaining(e, t)
  if warn and left and left <= warn then
    v.warning = true
    v.pulse = pulsePhase(t)
  end
  return v
end

local function rowStyle(v)
  local P = palette()
  local accent, bg, fg, bd
  if v.state == "flash" then
    accent, fg, bd = P.red, P.textBright, P.red
    bg = v.pulse and "rgba(220,38,38,0.55)" or "rgba(127,29,29,0.75)"
  elseif v.state == "expired" then
    accent, bg, fg, bd = "#4b5563", "rgba(12,14,26,0.70)", P.textDim, "rgba(42,47,78,0.6)"
  elseif v.warning then
    accent, fg, bd = P.amber, P.textBright, P.amber
    bg = v.pulse and "rgba(180,83,9,0.55)" or "rgba(19,22,41,0.90)"
  elseif v.state == "overdue" then
    accent, bg, fg, bd = P.amber, "rgba(19,22,41,0.90)", P.textBright, P.border
  else
    accent, bg, fg, bd = P.ice, "rgba(19,22,41,0.90)", P.textBright, P.border
  end
  local padB = v.timed and 9 or 0
  return string.format([[
    background: %s; color: %s;
    border: 1px solid %s; border-left: 3px solid %s; border-radius: 4px;
    padding: 0px 6px %dpx 6px;
    font-family: %s; font-size: %dpt;
  ]], bg, fg, bd, accent, padB, fontStack(), fx.config.fontSize)
end

local function barColour(remain)
  local P = palette()
  if remain > 0.5 then return P.green end
  if remain > 0.2 then return P.amber end
  return P.red
end

local function rowHtml(v)
  local P = palette()
  local name = esc(v.name)
  if v.expired then name = "<s>" .. name .. "</s>" end
  local right = v.right and esc(v.right) or ""
  if v.state == "overdue" then
    right = string.format('<span style="color:%s">%s</span>', P.amber, right)
  end
  return string.format(
    '<table width="100%%" cellspacing="0" cellpadding="0"><tr>'
    .. '<td align="left"><b>%s</b></td><td align="right">%s</td></tr></table>',
    name, right)
end

local function makeRow(i)
  local box = fx.ui.box
  local r = {}
  local W = fx.config.width
  r.c = Geyser.Container:new({
    name = "icesusfx.row" .. i, x = 0, y = 0, width = W, height = fx.config.rowH,
  }, box)
  r.bg = Geyser.Label:new({
    name = "icesusfx.row" .. i .. ".bg", x = 0, y = 0, width = W, height = fx.config.rowH,
  }, r.c)
  r.back = Geyser.Label:new({
    name = "icesusfx.row" .. i .. ".back", x = 8, y = fx.config.rowH - 9,
    width = W - 14, height = 4,
  }, r.c)
  r.fill = Geyser.Label:new({
    name = "icesusfx.row" .. i .. ".fill", x = 8, y = fx.config.rowH - 9,
    width = 0, height = 4,
  }, r.c)
  r.back:setStyleSheet("background: rgba(255,255,255,0.08); border-radius: 2px;")
  for _, w in ipairs({ r.bg, r.back, r.fill }) do
    w:setClickCallback(function() fx.onClick(i) end)
  end
  r.cache = {}
  return r
end

function fx.buildUI()
  if fx.ui then return end
  fx.ui = { rows = {}, shown = {} }
  fx.ui.box = Geyser.Container:new({
    name = "icesusfx.box", x = 0, y = 0, width = fx.config.width, height = 10,
  })
  fx.ui.box:hide()
end

-- Main console bounds, live: the HUD (or the player) may move the
-- borders at any time, so this is read on every render.
local function consoleRect()
  local w, h = getMainWindowSize()
  local bl = getBorderLeft and getBorderLeft() or 0
  local br = getBorderRight and getBorderRight() or 0
  local bt = getBorderTop and getBorderTop() or 0
  local bb = getBorderBottom and getBorderBottom() or 0
  return bl, bt, w - br, h - bb
end

-- Set a widget property only when it changed — every tick re-renders.
local function cached(r, k, val, apply)
  if r.cache[k] == val then return end
  r.cache[k] = val
  apply(val)
end

function fx.render()
  if not fx.ui then return end
  local C = fx.config
  local t = fx.now()
  local _, top, right, bottom = consoleRect()
  local maxH = bottom - top - C.marginTop * 2
  local list = fx.entries()

  local y, n = 0, 0
  fx.ui.shown = {}
  for _, e in ipairs(list) do
    local v = fx.view(e, t)
    local h = v.timed and C.rowH or C.rowHPlain
    if y + h > maxH then break end
    n = n + 1
    local r = fx.ui.rows[n]
    if not r then r = makeRow(n); fx.ui.rows[n] = r end
    fx.ui.shown[n] = e.key
    cached(r, "y", y, function(val) r.c:move(0, val) end)
    cached(r, "h", h, function(val)
      r.c:resize(C.width, val); r.bg:resize(C.width, val)
    end)
    cached(r, "style", rowStyle(v), function(val) r.bg:setStyleSheet(val) end)
    cached(r, "html", rowHtml(v), function(val) r.bg:echo(val) end)
    local tip = fx.tooltip(v)
    cached(r, "tip", tip, function(val)
      if r.bg.setToolTip then r.bg:setToolTip(val) end
    end)
    local barOn = v.timed and not v.expired
    cached(r, "bar", barOn, function(on)
      if on then r.back:show() else r.back:hide(); r.fill:hide() end
    end)
    if barOn then
      local frac = v.remain or 0
      local px = math.floor((C.width - 14) * frac + 0.5)
      cached(r, "fillW", px, function(val)
        if val > 0 then r.fill:resize(val, 4); r.fill:show() else r.fill:hide() end
      end)
      cached(r, "fillC", barColour(frac), function(val)
        r.fill:setStyleSheet("background: " .. val .. "; border-radius: 2px;")
      end)
    else
      r.cache.fillW = nil
    end
    r.c:show()
    y = y + h + C.gap
  end
  for i = n + 1, #fx.ui.rows do fx.ui.rows[i].c:hide() end

  fx.renderBanner()
  if n == 0 then fx.ui.box:hide(); return end
  local x = right - C.width - C.marginRight
  local bx, by, bh = x, top + C.marginTop, y - C.gap
  if fx.ui.pos ~= bx .. "," .. by .. "," .. bh then
    fx.ui.pos = bx .. "," .. by .. "," .. bh
    fx.ui.box:move(bx, by)
    fx.ui.box:resize(C.width, bh)
  end
  fx.ui.box:show()
end

-- =============================================================
-- `effects` listing rows — the game's listing rewritten as columns:
--   ON   Essence of the nether         3:35 / ~9:24
-- =============================================================
local function nameWidth()
  local w = 24
  for key in pairs(fx.data.defs) do w = math.max(w, #fx.label(key)) end
  return w + 2
end

-- One row as cecho text. hot = warning or overdue (timer in amber).
function fx.effectsRow(on, name, timer, hot)
  local pad = string.rep(" ", math.max(1, nameWidth() - #name))
  return string.format(" %s  %s%s%s%s<reset>",
    on and "<green>ON <reset>" or "<grey>OFF<reset>",
    on and "<white>" or "<grey>", name, pad,
    (hot and "<orange>" or "<grey>") .. (timer or ""))
end

-- =============================================================
-- Banner — big text across the middle of the console for alerts.
-- =============================================================
function fx.flash(key)
  fx.cues.flash[key] = fx.now() + fx.config.flashSecs
end

function fx.banner(text, colour)
  table.insert(fx.cues.banners, { text = text, colour = colour or palette().red,
    untilT = fx.now() + fx.config.bannerSecs })
  while #fx.cues.banners > 3 do table.remove(fx.cues.banners, 1) end
  fx.renderBanner()
end

function fx.renderBanner()
  if not fx.ui then return end
  local t = fx.now()
  local live = {}
  for _, b in ipairs(fx.cues.banners) do
    if b.untilT > t then live[#live + 1] = b end
  end
  fx.cues.banners = live
  for key, untilT in pairs(fx.cues.flash) do
    if untilT <= t then fx.cues.flash[key] = nil end
  end
  local w = fx.ui.banner
  if #live == 0 then
    if w then w:hide() end
    return
  end
  if not w then
    w = Geyser.Label:new({ name = "icesusfx.banner", x = 0, y = 0, width = 10, height = 10 })
    fx.ui.banner = w
  end
  local left, top, right, bottom = consoleRect()
  local bw = math.min(640, right - left - 40)
  local bh = 24 + 34 * #live
  w:move(left + math.floor((right - left - bw) / 2), top + math.floor((bottom - top) * 0.3))
  w:resize(bw, bh)
  -- The newest banner sets the frame; it dims in its last second.
  local newest = live[#live]
  local fading = newest.untilT - t <= 1
  local P = palette()
  w:setStyleSheet(string.format([[
    background: rgba(12,14,26,%s); border: 2px solid %s; border-radius: 8px;
    font-family: %s; font-size: 20pt; font-weight: bold;
  ]], fading and "0.45" or "0.85", newest.colour, fontStack()))
  local lines = {}
  for _, b in ipairs(live) do
    lines[#lines + 1] = string.format('<span style="color:%s">%s</span>',
      fading and P.textDim or b.colour, esc(b.text))
  end
  w:echo('<center>' .. table.concat(lines, "<br>") .. '</center>')
  w:show()
  if w.raise then w:raise() end
end

function fx.tooltip(v)
  local lines = { v.name }
  local st = fx.data.stats[v.key]
  if v.expired then
    lines[#lines + 1] = "ended " .. fmtTime(v.ago) .. " ago — click to dismiss"
  elseif v.timed then
    local n = st and #st.samples or 0
    if n == 0 then
      lines[#lines + 1] = "no estimate yet: learns from the first full run"
    else
      local lo, hi = math.huge, 0
      for _, s in ipairs(st.samples) do lo = math.min(lo, s); hi = math.max(hi, s) end
      lines[#lines + 1] = string.format("estimate from %d run%s (%s – %s)",
        n, n == 1 and "" or "s", fmtTime(lo), fmtTime(hi))
    end
  end
  return table.concat(lines, "\n")
end

-- Clicking an expired button dismisses it.
function fx.onClick(i)
  local key = fx.ui and fx.ui.shown[i]
  if key and fx.dismiss(key) then fx.render() end
end
