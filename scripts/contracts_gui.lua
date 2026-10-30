-- The contracts window (#76): a force's incoming contract offers and active contracts, opened from
-- the market window of a hub within reach. Offers can be accepted at that hub (their ingredients
-- are shipped to it) or declined; active contracts show their progress and deadline and can be
-- abandoned. Rows are built once and updated in place, so a refresh never destroys a button a
-- player is clicking (multiplayer latency). Interface state lives in storage.contracts_gui.
local contracts = require("scripts.contracts")
local core = require("scripts.core.contracts")
local hubs = require("scripts.hubs")
local incoming = require("scripts.incoming_contracts")

local contracts_gui = {}

contracts_gui.ROWS = 8
contracts_gui.REFRESH_TICKS = 60

local WINDOW = "gb_contracts"

local function window_of(player_index)
  local data = storage.contracts_gui[player_index]
  local window = data and data.elements.window
  return window and window.valid and window or nil
end

-- "[item=iron-plate] 200, [item=copper-plate] 100", with what is delivered when `delivered` is given.
local function goods_text(list, delivered)
  local parts = {}
  for _, goods in ipairs(list) do
    local count = goods.count
    local text = "[" .. goods.kind .. "=" .. goods.name .. "] "
    if delivered then
      text = text .. math.floor(delivered[core.key(goods)] or 0) .. " / " .. count
    else
      text = text .. count
    end
    parts[#parts + 1] = text
  end
  return table.concat(parts, "  ")
end

local function minutes(ticks)
  local seconds = math.max(0, math.floor(ticks / 60))
  return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- The force's offers and active incoming contracts, by id.
local function listed(force_index)
  local state = storage.forces[force_index]
  local list = {}
  for _, contract in pairs(state and state.contracts and state.contracts.open or {}) do
    if contract.kind == "incoming" then list[#list + 1] = contract end
  end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

local function refresh(player, data)
  local elements = data.elements
  local list = listed(player.force_index)
  elements.reputation.caption = { "gb-contracts.reputation", storage.forces[player.force_index].reputation }
  elements.empty.visible = #list == 0
  for i, row in ipairs(elements.rows) do
    local contract = list[i]
    for _, cell in pairs(row) do cell.visible = contract ~= nil end
    if contract then
      local offered = contract.state == core.OFFERED
      row.who.caption = contract.counterparty
      row.provides.caption = goods_text(contract.provides)
      row.requires.caption = goods_text(contract.requires, not offered and contract.delivered or nil)
      row.terms.caption = { "gb-contracts.terms", string.format("%.0f", contract.reward),
        string.format("%.0f", core.guarantee(contract)) }
      row.time.caption = offered and { "gb-contracts.offer-ends", minutes(contract.accept_by - game.tick) }
        or { "gb-contracts.due-in", minutes(contract.due_tick - game.tick) }
      row.primary.caption = offered and { "gb-contracts.accept" } or { "gb-contracts.abandon" }
      row.primary.tags = { gb_action = offered and "contract-accept" or "contract-abandon", id = contract.id }
      row.secondary.visible = offered
      row.secondary.tags = { gb_action = "contract-decline", id = contract.id }
    end
  end
end

local function build(player)
  local window = player.gui.screen.add({ type = "frame", name = WINDOW, direction = "vertical",
    caption = { "gb-contracts.title" } })
  local elements = { window = window }
  local body = window.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  local head = body.add({ type = "flow", direction = "horizontal" })
  elements.reputation = head.add({ type = "label", style = "bold_label" })
  head.add({ type = "button", caption = { "gb-contracts.close" }, tags = { gb_action = "contract-close" } })
  elements.empty = body.add({ type = "label", caption = { "gb-contracts.none" } })
  local list = body.add({ type = "table", column_count = 7 })
  elements.rows = {}
  for i = 1, contracts_gui.ROWS do
    elements.rows[i] = {
      who = list.add({ type = "label", style = "bold_label" }),
      provides = list.add({ type = "label" }),
      requires = list.add({ type = "label" }),
      terms = list.add({ type = "label" }),
      time = list.add({ type = "label" }),
      primary = list.add({ type = "button", style = "green_button" }),
      secondary = list.add({ type = "button", style = "red_button", caption = { "gb-contracts.decline" } }),
    }
  end
  window.force_auto_center()
  return elements
end

--- Opens the contracts window of a player at a hub.
function contracts_gui.open(player, hub_unit_number)
  contracts_gui.close(player.index)
  local data = { hub = hub_unit_number, elements = build(player) }
  storage.contracts_gui[player.index] = data
  refresh(player, data)
end

function contracts_gui.close(player_index)
  local window = window_of(player_index)
  if window then window.destroy() end
  storage.contracts_gui[player_index] = nil
end

local actions = {}

actions["contract-close"] = function(player)
  contracts_gui.close(player.index)
end

actions["contract-accept"] = function(player, data, tags)
  local hub = hubs.get(data.hub)
  if not (hub and hub.force == player.force and player.can_reach_entity(hub)) then
    return player.print({ "gb-gui.hub-unavailable" })
  end
  local ok, reason = incoming.accept(player.force_index, tags.id, data.hub)
  if not ok then player.print({ "gb-contracts.refused-" .. reason }) end
end

actions["contract-decline"] = function(player, _, tags)
  contracts.decline(player.force_index, tags.id)
end

actions["contract-abandon"] = function(player, _, tags)
  contracts.abandon(player.force_index, tags.id)
end

--- on_gui_click: runs the action of one of this window's buttons.
function contracts_gui.on_gui_click(event)
  local element = event.element
  if not (element and element.valid and element.get_mod() == script.mod_name) then return end
  local action = actions[element.tags.gb_action]
  local data = storage.contracts_gui[event.player_index]
  if not (action and data and window_of(event.player_index)) then return end
  local player = game.get_player(event.player_index)
  action(player, data, element.tags)
  if window_of(event.player_index) then refresh(player, data) end
end

--- on_nth_tick(REFRESH_TICKS): refreshes the open windows of connected players.
function contracts_gui.on_refresh_tick()
  for player_index, data in pairs(storage.contracts_gui) do
    local player = game.get_player(player_index)
    if player and player.connected and window_of(player_index) then refresh(player, data) end
  end
end

--- on_player_left_game, on_player_changed_force and on_player_removed: the window no longer applies.
function contracts_gui.on_player_event(event)
  contracts_gui.close(event.player_index)
end

--- on_init and on_configuration_changed: creates the state and closes every window.
function contracts_gui.init()
  storage.contracts_gui = storage.contracts_gui or {}
  local open = {}
  for player_index in pairs(storage.contracts_gui) do open[#open + 1] = player_index end
  for _, player_index in ipairs(open) do contracts_gui.close(player_index) end
end

return contracts_gui
