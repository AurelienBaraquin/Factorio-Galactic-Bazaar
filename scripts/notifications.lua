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

-- The throttle logs, created when missing: a save made before notifications has none until
-- on_configuration_changed, which a save of the same mod version never runs. Called from events only.
local function logs()
  storage.notifications = storage.notifications or {}
  return storage.notifications
end

--- on_init and on_configuration_changed: creates the throttle logs.
function notifications.init()
  logs()
end

--- on_forces_merged: the merged force's throttle log is folded into the destination's, so that what
--- one of them was told is not told again; the source's goes, so that a force created later under its
--- index starts afresh.
function notifications.on_forces_merged(event)
  local all = logs()
  local source = all[event.source_index]
  if not source then return end
  local destination = event.destination.index
  all[destination] = all[destination] or {}
  core.merge(all[destination], source)
  all[event.source_index] = nil
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
--- entity's unit number, otherwise the force. `params.count` (optional) is how many things the event
--- stands for: a throttled event's count is carried to the next one told for its group, and the total
--- is added as the last parameter. The alert points at `entity` (optional) or the nearest hub of the
--- player's force. Players who turned the kind's category off see nothing, but the chat line of a
--- `chat_always` kind. Returns how many players were told.
function notifications.notify(target, kind, params, entity)
  local spec = core.KINDS[kind]
  local force, players = resolve(target)
  if not force then return 0 end
  params = params or {}
  local group = params.group or (entity and entity.valid and entity.unit_number) or "force"
  local all = logs()
  all[force.index] = all[force.index] or {}
  local admitted, total = core.admit(all[force.index], kind, group, game.tick, params.count)
  if not admitted then return 0 end
  local list = { table.unpack(params) }
  if total then list[#list + 1] = total end
  local setting = core.CATEGORIES[spec.category]
  local message = { "gb-notify." .. kind, table.unpack(list) }
  local chat = spec.chat and { spec.chat, table.unpack(list) }
  local told = 0
  for _, player in ipairs(players) do
    local shown = player.mod_settings[setting].value
    local at = shown and alert_entity(player, entity)
    if at then player.add_custom_alert(at, spec.icon, message, true) end
    local printed = chat and (shown or spec.chat_always)
    if printed then player.print(chat, { color = spec.color }) end
    if at or printed then told = told + 1 end
  end
  return told
end

-- The goods a contract still needs, as rich text: "[item=iron-gear-wheel] 4", with the quality when
-- it is not normal ("[item=iron-gear-wheel,quality=rare] 4").
local function owed_text(contract)
  local parts = {}
  local remaining = contracts_core.remaining(contract)
  for _, goods in ipairs(contract.requires) do
    local owed = remaining[contracts_core.key(goods)]
    if owed > 0 then
      local quality = goods.quality and goods.quality ~= "normal" and ",quality=" .. goods.quality or ""
      parts[#parts + 1] = "[" .. goods.kind .. "=" .. goods.name .. quality .. "] " .. math.ceil(owed)
    end
  end
  return table.concat(parts, "  ")
end

--- Tells a force of an event of `kind` about `contract`, with the parameters every contract message
--- may use: __1__ the kind of contract, __2__ the time left (to accept an offer, or to its deadline),
--- __3__ the goods still owed, __4__ its guarantee; for an offer, __5__ how many offers it stands for
--- (`count`, 1 by default). Offers are grouped by kind of contract, other events by contract. Returns
--- how many players were told.
function notifications.contract(force_index, kind, contract, entity, count)
  local tick = game.tick
  local ends = contract.state == contracts_core.OFFERED and contract.accept_by or contract.due_tick or tick
  return notifications.notify(force_index, kind, {
    { "gb-notify.kind-" .. contract.kind }, catalog.format_duration(ends - tick), owed_text(contract),
    catalog.format_credits(contracts_core.guarantee(contract)),
    group = kind == "contract-offer" and contract.kind or contract.id,
    count = kind == "contract-offer" and (count or 1) or nil,
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
