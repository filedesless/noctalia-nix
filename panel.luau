--!nonstrict
-- Nix Status panel: a renderer over the service's "nix.status", like the
-- widget, plus the buttons. Layout borrowed from nix-monitor's panel.

local CARD = "surface_variant/0.7"

local status = nil

local function request(action)
  local prev = noctalia.state.get("nix.request")
  local n = (type(prev) == "table" and tonumber(prev.n) or 0) + 1
  noctalia.state.set("nix.request", { n = n, action = action })
end

local function ago(age)
  if age == nil then
    return ""
  elseif age == 0 then
    return "today"
  elseif age == 1 then
    return "1 day ago"
  end
  return `{age} days ago`
end

-- A big card: glyph, revision, caption, date.
local function revBox(caption, glyph, rev, detail)
  return ui.column({
    fill = CARD,
    flexGrow = 1,
    height = 104,
    radius = 8,
    align = "center",
    padding = 10,
    justify = "space_between",
  }, {
    ui.glyph({ name = glyph, size = 26 }),
    ui.label({ text = rev, fontWeight = "bold" }),
    ui.label({ text = caption, fontSize = 12, fontWeight = "medium" }),
    ui.label({ text = detail, fontSize = 11, color = "on_surface/0.7" }),
  })
end

-- One line per flag, lit when set and dimmed when not, like the bar's glyphs.
local OFF = "on_surface/0.4"
local function line(glyph, on, color, text)
  return ui.row({ gap = 8, align = "center" }, {
    ui.glyph({ name = glyph, size = 16, color = on and color or OFF }),
    ui.label({ text = text, fontSize = 12, color = on and "on_surface" or OFF }),
  })
end

local function card(children)
  return ui.column({ fill = CARD, radius = 8, paddingV = 8, paddingH = 10, gap = 6 }, children)
end

-- What needs doing: every flag, always, so the panel's height never changes
-- (it's fixed in plugin.toml and doesn't follow the content).
local function attention(s)
  local remote = s.remote
  local rows = {
    line("power", s.reboot, "tertiary", s.reboot
      and `Reboot needed: the {table.concat(s.changed, ", ")} changed`
      or "No reboot needed"),
    line("flask", s.testing, "tertiary", s.testing
      and `Testing a build; the boot default is generation {s.generation or "?"}`
      or "No test running"),
    line("refresh-alert", s.switchPending, "tertiary", s.switchPending
      and "The flake changed, not built yet: switch to apply it"
      or "No switch pending"),
    line("git-commit", s.dirty, "primary", s.dirty
      and "The flake has uncommitted changes"
      or "Flake committed"),
    line("download", s.behind, "primary", s.behind
      and `{remote.branch} has moved ({remote.date}): update to get it`
      or "No newer nixpkgs on GitHub"),
  }
  return card(rows)
end

-- Every input's pin, in a card of fixed height that scrolls past six, so the
-- panel's height doesn't depend on how many inputs the flake has.
local function inputRows(s)
  local rows = {}
  for _, input in ipairs(s.inputs or {}) do
    table.insert(rows, ui.row({ justify = "space_between", align = "center" }, {
      ui.label({ text = input.name, fontSize = 12, fontWeight = "semibold" }),
      ui.label({ text = `{input.rev}  {input.date}  ({ago(input.age)})`, fontSize = 12, color = "on_surface/0.7" }),
    }))
  end
  return ui.column({ fill = CARD, radius = 8, paddingV = 4, paddingH = 4, height = 144 }, {
    ui.scroll({ flexGrow = 1 }, { ui.column({ gap = 6 }, rows) }),
  })
end

local function render()
  local s = status
  if s == nil or not s.ok then
    panel.render(ui.column({ gap = 8 }, {
      ui.label({ text = "NixOS", fontSize = 16 }),
      ui.label({ text = s and s.err or "Checking...", fontSize = 12 }),
      ui.button({ text = "Check", glyph = "search", variant = "outline", onClick = "onCheckClicked" }),
    }))
    return
  end

  local remote = s.remote
  local remoteRev, remoteDetail = "...", "checking"
  if remote ~= nil and remote.ok then
    remoteRev = remote.rev
    remoteDetail = `{remote.date} ({ago(remote.age)})`
  elseif remote ~= nil then
    remoteRev, remoteDetail = "?", remote.err
  end

  -- Check is a bare icon; then Switch, which makes the system match the repo
  -- for good whatever is pending or being tested, Back, which drops a test,
  -- and Update, always there.
  local buttons = {
    ui.button({ glyph = "refresh", variant = "outline", onClick = "onCheckClicked", tooltip = "Check now" }),
  }
  if s.switchPending or s.testing then
    table.insert(buttons, ui.button({
      text = "Switch", glyph = "player-play", flexGrow = 1, variant = "primary", onClick = "onSwitchClicked",
    }))
  end
  if s.testing then
    table.insert(buttons, ui.button({
      text = "Back", glyph = "arrow-back-up", flexGrow = 1, variant = "outline", onClick = "onBackClicked",
    }))
  end
  table.insert(buttons, ui.button({
    text = "Update",
    glyph = "progress-down",
    flexGrow = 1,
    variant = (s.behind and not s.switchPending and not s.testing) and "primary" or "outline",
    onClick = "onUpdateClicked",
  }))

  local checked = `Checked {s.checkedAt or "?"}`
  if remote ~= nil and remote.checkedAt then
    checked ..= ` · GitHub {remote.checkedAt}`
  end

  panel.render(ui.column({ gap = 8 }, {
    ui.row({ justify = "space_between", align = "center" }, {
      ui.label({ text = "NixOS", fontSize = 16 }),
      ui.label({ text = s.nixpkgsBranch or "", fontSize = 12 }),
    }),
    ui.separator({ thickness = 2, orientation = "horizontal", spacing = 4 }),
    ui.row({ gap = 8, align = "center", justify = "space_between" }, {
      revBox("pinned nixpkgs", "devices-pc", s.nixpkgsRev or "?", `{s.nixpkgsDate or "?"} ({ago(s.nixpkgsAge)})`),
      revBox("latest on GitHub", "world", remoteRev, remoteDetail),
    }),
    attention(s),
    inputRows(s),
    -- One line: the commit says more than the version, which only names nixpkgs.
    ui.label({
      text = s.revision and `Built from {s.revision} · {checked}` or `Running {s.version or "?"} · {checked}`,
      fontSize = 11,
      color = "on_surface/0.7",
    }),
    ui.row({ gap = 8, align = "center", justify = "space_between" }, buttons),
  }))
end

noctalia.state.watch("nix.status", function(value)
  if type(value) == "table" then
    status = value
    render()
  end
end)

function onOpen(_ctx)
  status = noctalia.state.get("nix.status")
  render()
end

function update()
  render()
end

function onCheckClicked()
  request("check")
end

function onUpdateClicked()
  panel.close()
  request("update")
end

function onSwitchClicked()
  panel.close()
  request("switch")
end

function onBackClicked()
  panel.close()
  request("back")
end
