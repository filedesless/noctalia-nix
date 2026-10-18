--!nonstrict
-- Nix Status bar widget: a renderer over the service's "nix.status".
--
-- A snowflake, red if the check failed, then a glyph per flag (the panel's)
-- in a fixed place: lit when set, dimmed when not. Then the nixpkgs pin's
-- age.
--
-- Left click: the panel
-- Right click: check now, GitHub included

local status = nil

local function request(action)
  local prev = noctalia.state.get("nix.request")
  local n = (type(prev) == "table" and tonumber(prev.n) or 0) + 1
  noctalia.state.set("nix.request", { n = n, action = action })
end

-- An unset flag's glyph stays in place, dimmed, so the bar doesn't shift.
local ON = "on_surface"
local OFF = "on_surface/0.4"

-- Every flag's glyph, in the panel's order and with its glyphs: lit when
-- set, dimmed when not or when there's no status to read. Each one says on
-- hover what it means and whether it's set.
local function flags(s)
  local function flag(glyph, on, yes, no)
    return { glyph = glyph, color = on and ON or OFF, tooltip = on and yes or no }
  end
  s = s or {}
  local changed = table.concat(s.changed or {}, ", ")
  return {
    flag("power", s.reboot,
      `Reboot needed: {changed} changed`, "Reboot: not needed"),
    flag("flask", s.testing,
      "Testing a build, not the boot default", "Test: none running"),
    flag("refresh-alert", s.switchPending,
      "Switch pending: flake.lock changed, not built yet", "Switch: none pending"),
    flag("git-commit", s.dirty,
      "flake.lock has uncommitted changes", "flake.lock: committed"),
    flag("download", s.behind,
      "GitHub has a newer nixpkgs: update to get it", "nixpkgs: no newer version on GitHub"),
  }
end

local function draw(color, list, text)
  local container = barWidget.isVertical() and ui.column or ui.row
  local children = { ui.glyph({ name = "snowflake", color = color }) }
  for _, flag in ipairs(list) do
    -- A glyph takes no tooltip; a row around it does, but then the row is
    -- its own hover target and needs the click (and pointer) back. A row
    -- has no onRightClick, so right-clicking an icon does nothing.
    table.insert(children, ui.row({ tooltip = flag.tooltip, onClick = "onClick" }, {
      ui.glyph({ name = flag.glyph, size = 11, color = flag.color }),
    }))
  end
  if text ~= "" then
    table.insert(children, ui.label({ text = text }))
  end
  barWidget.render(container({ gap = 4, align = "center" }, children))
end

local function render()
  if status == nil then
    draw(ON, flags(nil), "")
    barWidget.setTooltip({ { key = "Nix", value = "checking..." } })
    return
  end

  if not status.ok then
    draw("error", flags(nil), "")
    barWidget.setTooltip({ { key = "Nix", value = status.err or "check failed" } })
    return
  end

  local age = status.nixpkgsAge
  draw(ON, flags(status), age and not barWidget.isVertical() and `{age}d` or "")

  local rows = {}
  if status.reboot then
    table.insert(rows, { key = "Reboot", value = "needed: " .. table.concat(status.changed, ", ") .. " changed" })
  end
  if status.testing then
    table.insert(rows, { key = "Testing", value = "running a build that isn't the boot default" })
  end
  if status.switchPending then
    table.insert(rows, { key = "Switch", value = "pending: flake.lock is newer than the running system" })
  end
  if status.dirty then
    table.insert(rows, { key = "flake.lock", value = "not committed" })
  end
  local remote = status.remote
  if remote ~= nil and remote.ok then
    table.insert(rows, { key = "GitHub", value = status.behind
      and `{remote.branch} moved to {remote.rev} ({remote.date})`
      or `{remote.branch} is still at {remote.rev}` })
  end
  for _, input in ipairs(status.inputs or {}) do
    table.insert(rows, { key = input.name, value = `{input.date} ({input.age}d) {input.rev}` })
  end
  table.insert(rows, { key = "Running", value = status.version or "?" })
  table.insert(rows, { key = "Checked", value = status.checkedAt or "?" })
  table.insert(rows, { key = "", value = "Left click: details · Right click: check" })
  barWidget.setTooltip(rows)
end

noctalia.state.watch("nix.status", function(value)
  if type(value) == "table" then
    status = value
    render()
  end
end)

function update()
  render()
end

function onClick()
  noctalia.togglePanel("filedesless/nix-status:panel")
end

function onRightClick()
  request("check")
end

noctalia.setUpdateInterval(5000)
status = noctalia.state.get("nix.status")
render()
