-- Checks the system flake and the running system once a minute, the
-- nixpkgs branch on GitHub once an hour, and both on request.
--
-- State channel:
--   "nix.request"  set by the widget and panel:
--                  { action = "check"|"update"|"switch", n }
--   "nix.status"   set here, see localCheck() and remoteCheck() for the fields

-- The system flake; nh's own NH_OS_FLAKE points at the same place.
local FLAKE = "$HOME/src/nixos"
-- A nixpkgs pin older than this many days gets the accent color.
local STALE_DAYS = 14
local LOCAL_INTERVAL_S = 60
-- GitHub allows 60 unauthenticated API requests an hour.
local REMOTE_INTERVAL_S = 3600

-- Prints key=value lines, then "lock" and flake.lock itself. $1 is FLAKE,
-- expanded by this shell. All local, so it takes milliseconds.
local PROBE = [[
f=$(eval echo "$1")
printf 'flake=%s\n' "$f"
printf 'version=%s\n' "$(cat /run/current-system/nixos-version)"
for x in kernel initrd kernel-modules; do
  [ "$(readlink /run/booted-system/$x)" = "$(readlink /run/current-system/$x)" ] ||
    printf 'changed=%s\n' "$x"
done
git -C "$f" diff --quiet -- flake.lock 2>/dev/null || printf 'dirty=1\n'
if [ -e /etc/nixos/flake.lock ]; then
  cmp -s /etc/nixos/flake.lock "$f/flake.lock" && echo built=same || echo built=differs
fi
echo lock
cat "$f/flake.lock"
]]

-- The newest commit on a branch: "<sha> <epoch>". $1 is owner/repo, $2 the
-- branch. The commits list, unlike the single-commit endpoint, leaves out
-- the changed files.
local REMOTE_PROBE = [[
curl -fsS --max-time 15 -H 'Accept: application/vnd.github+json' \
  "https://api.github.com/repos/$1/commits?sha=$2&per_page=1" |
  jq -r '.[0] | "\(.sha) \(.commit.committer.date | fromdate)"'
]]

local status = { ok = false }
local remote = nil
local lastLocal = 0
local lastRemote = 0
local lastRequest = 0
local checkingLocal = false
local checkingRemote = false

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
        modified = locked.lastModified,
        original = node.original,
      })
    end
  end
  table.sort(list, function(a, b) return a.age > b.age end)
  return list
end

local function publish()
  status.remote = remote
  -- Behind the branch when GitHub has a different, newer head.
  status.behind = remote ~= nil and remote.ok and status.nixpkgsRev ~= nil
    and remote.rev ~= status.nixpkgsRev
  noctalia.state.set("nix.status", status)
end

local function remoteCheck()
  local repo, branch = status.nixpkgsRepo, status.nixpkgsBranch
  if checkingRemote or not repo or not branch then
    return
  end
  checkingRemote = true
  lastRemote = os.time()
  noctalia.runAsync({ "sh", "-c", REMOTE_PROBE, "sh", repo, branch }, function(res)
    checkingRemote = false
    local sha, epoch = string.match(res.stdout or "", "^(%x+) (%d+)")
    if res.exitCode ~= 0 or not sha then
      remote = { ok = false, err = "couldn't reach GitHub", checkedAt = os.date("%H:%M") }
    else
      local modified = tonumber(epoch)
      remote = {
        ok = true,
        branch = branch,
        rev = string.sub(sha, 1, 7),
        date = os.date("%Y-%m-%d", modified),
        age = days(os.time() - modified),
        checkedAt = os.date("%H:%M"),
      }
    end
    publish()
  end, 20000)
end

local function localCheck(thenRemote)
  if checkingLocal then
    return
  end
  checkingLocal = true
  lastLocal = os.time()
  noctalia.runAsync({ "sh", "-c", PROBE, "sh", FLAKE }, function(res)
    checkingLocal = false
    local out = res.stdout or ""
    local header, body = string.match(out, "^(.-)\nlock\n(.*)$")
    local lock = body and noctalia.json.decode(body)
    if res.timedOut or not lock then
      status = { ok = false, err = res.timedOut and "check timed out" or "couldn't read flake.lock" }
      publish()
      return
    end

    local s = { ok = true, changed = {}, dirty = false }
    for key, value in string.gmatch(header, "([%w]+)=([^\n]*)") do
      if key == "changed" then
        table.insert(s.changed, value)
      elseif key == "dirty" then
        s.dirty = true
      else
        s[key] = value
      end
    end

    s.inputs = inputs(lock, os.time())
    for _, input in ipairs(s.inputs) do
      if input.name == "nixpkgs" then
        s.nixpkgsAge = input.age
        s.nixpkgsDate = input.date
        s.nixpkgsRev = input.rev
        local o = input.original
        if type(o) == "table" and o.type == "github" then
          s.nixpkgsRepo = `{o.owner}/{o.repo}`
          s.nixpkgsBranch = o.ref or "master"
        end
        if s.built then
          -- The system ships the flake.lock it was built from
          -- (environment.etc."nixos/flake.lock"): any input moving counts.
          s.switchPending = s.built == "differs"
        else
          -- Otherwise only nixpkgs can be told apart: nixos-version ends
          -- with the nixpkgs revision the system was built from.
          local built = string.match(s.version or "", "%.(%x+)$")
          s.switchPending = built ~= nil and built ~= input.rev
        end
      end
      input.original = nil
    end
    s.stale = (s.nixpkgsAge or 0) >= STALE_DAYS
    s.reboot = #s.changed > 0
    s.checkedAt = os.date("%H:%M")
    status = s
    publish()
    if thenRemote then
      remoteCheck()
    end
  end, 10000)
end

-- nh builds in the terminal; sudo is passwordless on wheel. The next local
-- check (within a minute) picks up the result. Wrapped in sh -c so FLAKE's
-- $HOME expands whatever the terminal runs commands with.
local function runInTerminal(nhArgs)
  local script = "nh os switch " .. nhArgs .. FLAKE
    .. "; echo; printf 'Press Enter to close'; read _"
  local cmd = "sh -c '" .. string.gsub(script, "'", "'\\''") .. "'"
  if not noctalia.runInTerminal(cmd) then
    noctalia.notifyError("Nix Status", "No terminal to run nh in")
  end
end

-- Start from the request already in state, so a reload doesn't replay the
-- last one (an update would open a terminal).
do
  local prev = noctalia.state.get("nix.request")
  lastRequest = type(prev) == "table" and tonumber(prev.n) or 0
end

noctalia.state.watch("nix.request", function(req)
  if type(req) ~= "table" or (req.n or 0) <= lastRequest then
    return
  end
  lastRequest = req.n
  if req.action == "update" then
    runInTerminal("--update ")
  elseif req.action == "switch" then
    runInTerminal("")
  else
    localCheck(true)
  end
end)

-- Called by the host on the interval below.
function update()
  local now = os.time()
  if now - lastLocal >= LOCAL_INTERVAL_S then
    localCheck(now - lastRemote >= REMOTE_INTERVAL_S)
  end
end

noctalia.setUpdateInterval(5000)
localCheck(true)
