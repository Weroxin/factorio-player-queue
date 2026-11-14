-- Player Queue: nobody plays until enough players are online.
-- While waiting: players are locked and biters are frozen; factories, labs and trains keep running.
-- All state lives in `storage`, all work happens in events/commands: multiplayer-deterministic.
local GROUP = "player-queue-waiting"
local OUT = "player-queue/events.jsonl" -- relative to the server's script-output dir

local function cfg(name) return settings.global["pq-" .. name].value end

-- Blocks every input action except chat/commands and admin mod-setting changes
-- (so a locked admin can still lower min-players from the settings GUI).
local function setup_group()
  local g = game.permissions.get_group(GROUP) or game.permissions.create_group(GROUP)
  for _, action in pairs(defines.input_action) do g.set_allows_action(action, false) end
  g.set_allows_action(defines.input_action.write_to_console, true)
  g.set_allows_action(defines.input_action.mod_settings_changed, true)
  return g
end

local function in_group(p) return p.permission_group and p.permission_group.name == GROUP end

local function counted_players()
  local wl = {}
  for name in cfg("allowed-players"):gmatch("[^,%s]+") do wl[name:lower()] = true end
  local use_wl, admins = next(wl) ~= nil, cfg("count-admins")
  local names = {}
  for _, p in pairs(game.connected_players) do
    if (admins or not p.admin) and (not use_wl or wl[p.name:lower()]) then names[#names + 1] = p.name end
  end
  return names
end

-- Stop whatever the player was doing when the lock hit. Their input is blocked
-- afterwards, so a state set here sticks until release.
local function halt(p)
  p.opened = nil
  local c = p.character
  if not c then return end
  c.walking_state = {walking = false, direction = defines.direction.north} -- also stops a driven spidertron
  c.shooting_state = {state = defines.shooting.not_shooting, position = c.position}
  local v = c.vehicle
  if not v then return end
  if v.type == "spider-vehicle" then
    v.autopilot_destination = nil
    v.follow_target = nil
  elseif v.type == "car" then
    local d = v.get_driver()
    if d == c or d == p then c.riding_state = {acceleration = defines.riding.acceleration.braking, direction = defines.riding.direction.straight} end
  elseif v.train and v.train.manual_mode then
    -- manual train would keep its last throttle input; automatic trains are production, leave them
    v.train.speed = 0
    c.driving = false
  end
end

local function lock(p, g)
  if in_group(p) then return end
  storage.prev_group[p.index] = p.permission_group and p.permission_group.name
  g.add_player(p)
  halt(p)
end

local function unlock(p)
  if not in_group(p) then return end
  local perms = game.permissions
  local g = perms.get_group(storage.prev_group[p.index] or "Default") or perms.get_group("Default")
  g.add_player(p)
  storage.prev_group[p.index] = nil
end

-- Biters: enemy force cease-fires every player force (one-way, so turrets still
-- shoot biters and asteroids), evolution and expansion off. Originals restored on release.
-- ponytail: pollution still sends (harmless) attack groups; turrets clear them or they attack after release.
local function freeze_force(f)
  local b = storage.biters
  if not b or f.name == "enemy" or f.name == "neutral" or b.cease[f.name] ~= nil then return end
  local enemy = game.forces.enemy
  b.cease[f.name] = enemy.get_cease_fire(f)
  enemy.set_cease_fire(f, true)
end

local function set_biters_frozen(frozen)
  local ms = game.map_settings
  if frozen and not storage.biters then
    storage.biters = {expansion = ms.enemy_expansion.enabled, evolution = ms.enemy_evolution.enabled, cease = {}}
    ms.enemy_expansion.enabled = false
    ms.enemy_evolution.enabled = false
    for _, f in pairs(game.forces) do freeze_force(f) end
  elseif not frozen and storage.biters then
    local b = storage.biters
    ms.enemy_expansion.enabled = b.expansion
    ms.enemy_evolution.enabled = b.evolution
    for name, was in pairs(b.cease) do
      if game.forces[name] then game.forces.enemy.set_cease_fire(name, was) end
    end
    storage.biters = nil
  end
end

-- event: "join" | "leave" | "settings"; who: player name for join/leave
local function sync(event, who)
  local names = counted_players()
  local n, need, online = #names, cfg("min-players"), #game.connected_players

  local released = storage.released
  if online == 0 then released = false -- session over: next session queues again
  elseif n >= need then released = true
  elseif cfg("relock-on-drop") then released = false end

  if released ~= storage.released and online > 0 then
    event = released and "released" or "relocked"
    game.print(released
      and ("[Player Queue] %d/%d players online. GO!"):format(n, need)
      or ("[Player Queue] Dropped to %d/%d players. Everyone is locked until more join."):format(n, need),
      {color = released and {0.3, 1, 0.3} or {1, 0.4, 0.3}})
  end
  storage.released = released
  set_biters_frozen(not released)

  local status = ("Waiting for players: %d/%d"):format(n, need)
  if released then
    for _, p in pairs(game.players) do
      unlock(p)
      if p.gui.top.pq_status then p.gui.top.pq_status.destroy() end
    end
  else
    local g = game.permissions.get_group(GROUP) or setup_group()
    for _, p in pairs(game.connected_players) do
      lock(p, g)
      local f = p.gui.top.pq_status or p.gui.top.add{type = "frame", name = "pq_status"}
      f.caption = status
    end
    if event == "join" or event == "leave" then game.print("[Player Queue] " .. status) end
  end

  if event ~= "settings" then
    helpers.write_file(OUT, helpers.table_to_json{
      event = event, player = who, count = n, needed = need, players = names, released = released,
    } .. "\n", true, 0) -- 0 = written on the server only
  end
end

local function init()
  storage.prev_group = storage.prev_group or {}
  storage.released = storage.released or false
  setup_group() -- re-run on updates so newly added input actions get blocked too
  sync("settings")
end
script.on_init(init)
script.on_configuration_changed(init)

script.on_event(defines.events.on_player_joined_game, function(e) sync("join", game.get_player(e.player_index).name) end)
script.on_event(defines.events.on_player_left_game, function(e) sync("leave", game.get_player(e.player_index).name) end)
script.on_event({defines.events.on_player_promoted, defines.events.on_player_demoted}, function() sync("settings") end)
script.on_event(defines.events.on_force_created, function(e) freeze_force(e.force) end)
script.on_event(defines.events.on_runtime_mod_setting_changed, function(e)
  if e.setting:sub(1, 3) == "pq-" then sync("settings") end
end)

-- Headless-friendly control: works from the server console, RCON, or in-game chat,
-- and unlike /c it doesn't disable achievements.
local OPTIONS = {min = "min-players", relock = "relock-on-drop", admins = "count-admins", allow = "allowed-players"}
local BOOL = {on = true, ["true"] = true, off = false, ["false"] = false}
commands.add_command("queue", "Queue status. Admins: /queue min <n> | relock on|off | admins on|off | allow <names, or - for everyone>", function(cmd)
  local caller = cmd.player_index and game.get_player(cmd.player_index)
  local function reply(msg)
    if caller then caller.print(msg) else rcon.print(msg); print(msg) end
  end
  local key, val = (cmd.parameter or ""):match("^(%S+)%s*(.-)%s*$")
  if key then
    local name = OPTIONS[key]
    if not name then return reply("Unknown option '" .. key .. "'. Use min, relock, admins or allow.") end
    if caller and not caller.admin then return reply("Only admins can change queue settings.") end
    local cur, v = cfg(name), nil
    if type(cur) == "number" then
      v = tonumber(val)
      if not v or v < 1 or v % 1 ~= 0 then return reply("min needs a whole number >= 1") end
    elseif type(cur) == "boolean" then
      v = BOOL[val]
      if v == nil then return reply(key .. " needs on or off") end
    else
      v = val == "-" and "" or val
    end
    settings.global["pq-" .. name] = {value = v}
    sync("settings")
  end
  local names = counted_players()
  reply(("[Player Queue] %s, %d/%d counted online (%s). relock=%s admins=%s allow=%s"):format(
    storage.released and "running" or "waiting (players locked, biters frozen)",
    #names, cfg("min-players"), table.concat(names, ", "),
    tostring(cfg("relock-on-drop")), tostring(cfg("count-admins")),
    cfg("allowed-players") == "" and "everyone" or cfg("allowed-players")))
end)
