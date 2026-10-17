-- Checks the system flake and the running system once a minute, and on
-- request from the widget. Everything it reads is local (flake.lock, two
-- symlink trees, git), so a check costs a few milliseconds.
--
-- State channel:
--   "nix.request"  set by the widget: { action = "check"|"update", n }
--   "nix.status"   set here, see check() for the fields

-- The system flake; nh's own NH_OS_FLAKE points at the same place.
local FLAKE = "$HOME/src/nixos"
-- A nixpkgs pin older than this many days gets the accent color.
local STALE_DAYS = 14
local CHECK_INTERVAL_S = 60

-- Prints key=value lines, then "lock" and flake.lock itself. $1 is FLAKE,
-- expanded by this shell.
local PROBE = [[
f=$(eval echo "$1")
printf 'flake=%s\n' "$f"
printf 'version=%s\n' "$(cat /run/current-system/nixos-version)"
for x in kernel initrd kernel-modules; do
  [ "$(readlink /run/booted-system/$x)" = "$(readlink /run/current-system/$x)" ] ||
    printf 'changed=%s\n' "$x"
done
git -C "$f" diff --quiet -- flake.lock 2>/dev/null || printf 'dirty=1\n'
echo lock
cat "$f/flake.lock"
]]

local lastCheck = 0
local lastRequest = 0
local checking = false

local function days(seconds)
  return math.floor(seconds / 86400)
end

-- The root's direct inputs, oldest pin first.
local function inputs(lock, now)
  local list = {}
  local nodes = lock.nodes or {}
  local root = nodes[lock.root or "root"] or {}
  for name, ref in pairs(root.inputs or {}) do
    -- A follows (an array path) has no lock of its own.
    local node = type(ref) == "string" and nodes[ref] or nil
    local locked = node and node.locked
    if locked and locked.lastModified then
      table.insert(list, {
        name = name,
        rev = locked.rev and string.sub(locked.rev, 1, 7) or "",
        date = os.date("%Y-%m-%d", locked.lastModified),
        age = days(now - locked.lastModified),
      })
    end
  end
  table.sort(list, function(a, b) return a.age > b.age end)
  return list
end

local function publish(status)
  status.checkedAt = os.date("%H:%M")
  noctalia.state.set("nix.status", status)
end

local function check()
  if checking then
    return
  end
  checking = true
  lastCheck = os.time()
  noctalia.runAsync({ "sh", "-c", PROBE, "sh", FLAKE }, function(res)
    checking = false
    local out = res.stdout or ""
    local header, body = string.match(out, "^(.-)\nlock\n(.*)$")
    local lock = body and noctalia.json.decode(body)
    if res.timedOut or not lock then
      publish({ ok = false, err = res.timedOut and "check timed out" or "couldn't read flake.lock" })
      return
    end

    local status = { ok = true, changed = {}, dirty = false }
    for key, value in string.gmatch(header, "([%w]+)=([^\n]*)") do
      if key == "changed" then
        table.insert(status.changed, value)
      elseif key == "dirty" then
        status.dirty = true
      else
        status[key] = value
      end
    end

    local now = os.time()
    status.inputs = inputs(lock, now)
    for _, input in ipairs(status.inputs) do
      if input.name == "nixpkgs" then
        status.nixpkgsAge = input.age
        status.nixpkgsDate = input.date
        -- nixos-version ends with the nixpkgs revision the system was built
        -- from: a mismatch means flake.lock moved without a switch.
        local built = string.match(status.version or "", "%.(%x+)$")
        status.switchPending = built ~= nil and built ~= input.rev
      end
    end
    status.stale = (status.nixpkgsAge or 0) >= STALE_DAYS
    status.reboot = #status.changed > 0
    publish(status)
  end, 10000)
end

local function runUpdate()
  -- nh builds in the terminal; sudo is passwordless on wheel. The widget
  -- picks up the result at the next check. Wrapped in sh -c so FLAKE's
  -- $HOME expands whatever the terminal runs commands with.
  local script = "nh os switch --update " .. FLAKE
    .. "; echo; printf 'Press Enter to close'; read _"
  local cmd = "sh -c '" .. string.gsub(script, "'", "'\\''") .. "'"
  if not noctalia.runInTerminal(cmd) then
    noctalia.notifyError("Nix Status", "No terminal to run the update in")
  end
end

noctalia.state.watch("nix.request", function(req)
  if type(req) ~= "table" or (req.n or 0) <= lastRequest then
    return
  end
  lastRequest = req.n
  if req.action == "update" then
    runUpdate()
  else
    check()
  end
end)

-- Called by the host on the interval below.
function update()
  if os.time() - lastCheck >= CHECK_INTERVAL_S then
    check()
  end
end

noctalia.setUpdateInterval(5000)
check()
