-- Notifications (#107): the one way features tell players what happened, as a game alert (the icon
-- bar above the minimap, its message on hover, a click opens the map at its building) and, for kinds
-- that have one, a chat line. Kinds, categories and throttling are in scripts/core/notifications.lua;
-- each force's throttle log lives in storage.notifications[force_index]. What is told is decided for
-- the force, the same on every peer; each player's settings (gb-notify-<category>) only decide whether
-- that player sees it. Notifications never change any other state.
local catalog = require("scripts.core.catalog")
local contracts_core = require("scripts.core.contracts")
local core = require("scripts.core.notifications")

local notifications = {}

--- on_init and on_configuration_changed: creates the throttle logs.
function notifications.init()
  storage.notifications = storage.notifications or {}
end

--- on_forces_merged: the merged force's throttle log goes, so that a force created later under its
--- index starts afresh.
function notifications.on_forces_merged(event)
  storage.notifications[event.source_index] = nil
end

-- The force and the players a target (a LuaForce, a LuaPlayer or a force index) designates.
local function resolve(target)
  if type(target) == "number" then
    local force = game.forces[target]
    return force, force and force.connected_players
  end
  if target.object_name == "LuaPlayer" then return target.force, { target } end
  return target, target.connected_players
end

-- The building an alert points at for a player: `entity` when given, otherwise the hub of the
-- player's force nearest to the player on the player's surface (on another surface, the lowest unit
-- number), otherwise the player's character; nil when there is none (the chat line is all that player
-- gets).
local function alert_entity(player, entity)
  if entity and entity.valid then return entity end
  local best, best_rank
  for unit_number, hub in pairs(storage.hubs) do
    local candidate = hub.entity
    if candidate.valid and candidate.force_index == player.force_index then
      local rank = math.huge
      if candidate.surface_index == player.surface_index then
        local dx, dy = candidate.position.x - player.position.x, candidate.position.y - player.position.y
        rank = dx * dx + dy * dy
      end
      if not best or rank < best_rank or (rank == best_rank and unit_number < best.unit_number) then
        best, best_rank = candidate, rank
      end
    end
  end
  return best or player.character
end

--- Tells the players of `target` (a LuaForce, a LuaPlayer or a force index) of an event of `kind` (a
--- key of scripts/core/notifications.lua's KINDS): an alert with the message "gb-notify.<kind>" and,
--- for kinds that have one, a chat line, both given `params` (the locale parameters, an array). The
--- event is throttled by kind and group for the force: `params.group` when given, otherwise the
--- entity's unit number, otherwise the force. The alert points at `entity` (optional) or the nearest hub
--- of the player's force. Players who turned the kind's category off see nothing. Returns how many players
--- were told.
function notifications.notify(target, kind, params, entity)
  local spec = core.KINDS[kind]
  local force, players = resolve(target)
  if not force then return 0 end
  params = params or {}
  local group = params.group or (entity and entity.valid and entity.unit_number) or "force"
  local logs = storage.notifications
  logs[force.index] = logs[force.index] or {}
  if not core.admit(logs[force.index], kind, group, game.tick) then return 0 end
  local setting = core.CATEGORIES[spec.category]
  local message = { "gb-notify." .. kind, table.unpack(params) }
  local chat = spec.chat and { spec.chat, table.unpack(params) }
  local told = 0
  for _, player in ipairs(players) do
    if player.mod_settings[setting].value then
      local at = alert_entity(player, entity)
      if at then player.add_custom_alert(at, spec.icon, message, true) end
      if chat then player.print(chat, { color = spec.color }) end
      if at or chat then told = told + 1 end
    end
  end
  return told
end

-- The goods a contract still needs, as rich text: "[item=iron-gear-wheel] 4".
local function owed_text(contract)
  local parts = {}
  for _, goods in ipairs(contract.requires) do
    local owed = contracts_core.remaining(contract)[contracts_core.key(goods)]
    if owed > 0 then parts[#parts + 1] = "[" .. goods.kind .. "=" .. goods.name .. "] " .. math.ceil(owed) end
  end
  return table.concat(parts, "  ")
end

--- Tells a force of an event of `kind` about `contract`, with the parameters every contract message
--- may use: __1__ the kind of contract, __2__ the time left (to accept an offer, or to its deadline),
--- __3__ the goods still owed, __4__ its guarantee. Offers are grouped by kind of contract, other
--- events by contract. Returns how many players were told.
function notifications.contract(force_index, kind, contract, entity)
  local tick = game.tick
  local ends = contract.state == contracts_core.OFFERED and contract.accept_by or contract.due_tick or tick
  return notifications.notify(force_index, kind, {
    { "gb-notify.kind-" .. contract.kind }, catalog.format_duration(ends - tick), owed_text(contract),
    catalog.format_credits(contracts_core.guarantee(contract)),
    group = kind == "contract-offer" and contract.kind or contract.id,
  }, entity)
end

--- Tells a force that an active contract is due soon, once per contract (scripts/core/notifications.lua).
function notifications.check_due(force_index, contract)
  if core.due_soon(contract, game.tick) then notifications.contract(force_index, "contract-due", contract) end
end

--- Tells a force how a contract was settled (`outcome` from the contract engine): fulfilled or failed;
--- a failed loan is a default, with the arrears it left. Expired offers and other ends are not told.
function notifications.contract_settled(force_index, contract, outcome)
  if outcome.state == contracts_core.FAILED and contract.advance then
    notifications.notify(force_index, "loan-defaulted", { catalog.format_credits(outcome.arrears or 0),
      group = contract.id })
  elseif outcome.state == contracts_core.FULFILLED then
    notifications.contract(force_index, "contract-fulfilled", contract)
  elseif outcome.state == contracts_core.FAILED then
    notifications.contract(force_index, "contract-failed", contract)
  end
end

return notifications
