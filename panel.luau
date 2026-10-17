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

-- One line with a colored glyph.
local function line(glyph, color, text)
  return ui.row({ gap = 8, align = "center" }, {
    ui.glyph({ name = glyph, size = 16, color = color }),
    ui.label({ text = text, fontSize = 12 }),
  })
end

local function card(children)
  return ui.column({ fill = CARD, radius = 8, paddingV = 8, paddingH = 10, gap = 6 }, children)
end

-- What needs doing, most urgent first, or one line saying nothing does.
local function attention(s)
  local rows = {}
  if s.reboot then
    table.insert(rows, line("power", "warning",
      `Reboot needed: the {table.concat(s.changed, ", ")} changed since boot`))
  end
  if s.switchPending then
    table.insert(rows, line("refresh-alert", "warning",
      "flake.lock is newer than the running system: switch to apply it"))
  end
  if s.dirty then
    table.insert(rows, line("git-commit", "primary", "flake.lock has uncommitted changes"))
  end
  if s.behind then
    table.insert(rows, line("download", "primary",
      `{s.remote.branch} has moved ({s.remote.date}): update to get it`))
  end
  if #rows == 0 then
    table.insert(rows, line("circle-check", "primary",
      "Up to date: running what flake.lock pins, no reboot needed"))
  end
  return card(rows)
end

local function inputRows(s)
  local rows = {}
  for _, input in ipairs(s.inputs or {}) do
    table.insert(rows, ui.row({ justify = "space_between", align = "center" }, {
      ui.label({ text = input.name, fontSize = 12, fontWeight = "semibold" }),
      ui.label({ text = `{input.rev}  {input.date}  ({ago(input.age)})`, fontSize = 12, color = "on_surface/0.7" }),
    }))
  end
  return card(rows)
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

  local buttons = {
    ui.button({ text = "Check", glyph = "search", flexGrow = 1, variant = "outline", onClick = "onCheckClicked" }),
  }
  if s.switchPending then
    table.insert(buttons, ui.button({
      text = "Switch", glyph = "player-play", flexGrow = 1, variant = "primary", onClick = "onSwitchClicked",
    }))
  end
  table.insert(buttons, ui.button({
    text = "Update",
    glyph = "progress-down",
    flexGrow = 1,
    variant = (s.behind and not s.switchPending) and "primary" or "outline",
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
    ui.label({ text = `Running {s.version or "?"} · {checked}`, fontSize = 11, color = "on_surface/0.7" }),
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
