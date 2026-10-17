--!nonstrict
-- Nix Status bar widget: a renderer over the service's "nix.status".
--
-- Glyph color, most urgent first: error (the check failed), warning (reboot
-- needed, a test still live, or flake.lock moved without a switch), primary (the nixpkgs pin
-- is stale), on_surface (all current). The text is the nixpkgs pin's age.
--
-- Left click: the panel
-- Right click: check now, GitHub included

local status = nil

local function request(action)
  local prev = noctalia.state.get("nix.request")
  local n = (type(prev) == "table" and tonumber(prev.n) or 0) + 1
  noctalia.state.set("nix.request", { n = n, action = action })
end

local function render()
  barWidget.setGlyph("snowflake")

  if status == nil then
    barWidget.setGlyphColor("on_surface")
    barWidget.setText("")
    barWidget.setTooltip({ { key = "Nix", value = "checking..." } })
    return
  end

  if not status.ok then
    barWidget.setGlyphColor("error")
    barWidget.setText("")
    barWidget.setTooltip({ { key = "Nix", value = status.err or "check failed" } })
    return
  end

  if status.reboot or status.switchPending or status.testing then
    barWidget.setGlyphColor("warning")
  elseif status.stale then
    barWidget.setGlyphColor("primary")
  else
    barWidget.setGlyphColor("on_surface")
  end
  local age = status.nixpkgsAge
  barWidget.setText(age and not barWidget.isVertical() and `{age}d` or "")

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
