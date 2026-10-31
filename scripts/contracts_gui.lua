-- The contracts window (#76, #78, #96): a force's offers and active contracts from counterparties
-- (incoming contracts, machine rentals, leases and loans), opened from the market window of a hub
-- within reach. Offers can be accepted (an incoming contract's ingredients are shipped to that hub) or
-- declined; active contracts show their progress and deadline and can be abandoned, loans repaid. Its
-- credit line shows the force's debt and borrows a principal tier. Rows are built once and updated in
-- place, so a refresh never destroys a button a player is clicking (multiplayer latency). Interface
-- state lives in storage.contracts_gui.
local catalog = require("scripts.core.catalog")
local contracts = require("scripts.contracts")
local core = require("scripts.core.contracts")
local finance = require("scripts.finance")
local hubs = require("scripts.hubs")
local incoming = require("scripts.incoming_contracts")
local loans = require("scripts.loans")
local loans_core = require("scripts.core.loans")
local planets = require("scripts.planets")
local rental = require("scripts.rental")

local contracts_gui = {}

contracts_gui.ROWS = contracts.MAX_LISTED
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

-- Why a loan action is refused, as a localised string; the credit technology's name is its parameter
-- (used by `not-researched`, ignored by the other reasons).
local function loan_refusal(reason)
  return { "gb-loans.refused-" .. reason, prototypes.technology[finance.CREDIT_TECHNOLOGY].localised_name }
end

-- The credit line: the force's debt against its cap, arrears if any, and a button per principal tier
-- with its terms, enabled when the force may borrow it.
local function refresh_credit(player, elements)
  local state = storage.forces[player.force_index]
  local debt, cap = loans.debt(player.force_index)
  local arrears = state.arrears or 0
  elements.debt.caption = arrears > 0
    and { "gb-loans.debt-arrears", catalog.format_credits(debt), catalog.format_credits(cap),
      catalog.format_credits(arrears) }
    or { "gb-loans.debt", catalog.format_credits(debt), catalog.format_credits(cap) }
  for tier, offer in ipairs(loans.offers(player.force_index)) do
    local button = elements.borrow[tier]
    button.enabled = offer.refusal == nil
    button.tooltip = { "", { "gb-loans.borrow-terms", string.format("%.4g", offer.rate * 100),
      loans_core.TERM_TICKS / 3600, catalog.format_credits(offer.charge), loans_core.periods(),
      loans_core.PERIOD_TICKS / 3600, catalog.format_credits(offer.charge * loans_core.periods()) },
      offer.refusal and { "", "\n", loan_refusal(offer.refusal) } or "" }
  end
end

-- What a row shows of a loan, in place of goods and terms.
local function refresh_loan_row(row, contract)
  local minutes_per_period = contract.installment_ticks / 3600
  row.who.caption = { "gb-loans.lender" }
  row.who.tooltip = { "gb-contracts.kind-loan", minutes_per_period }
  row.provides.caption = { "gb-loans.borrowed", catalog.format_credits(contract.advance) }
  row.requires.caption = { "gb-loans.left", catalog.format_credits(core.payoff(contract)) }
  row.terms.caption = { "gb-loans.installment", catalog.format_credits(contract.charge), minutes_per_period }
  row.primary.caption = { "gb-loans.repay" }
  row.primary.tooltip = { "gb-loans.repay-tooltip", catalog.format_credits(core.payoff(contract)) }
end

local function refresh(player, data)
  local elements = data.elements
  local list = contracts.listed(player.force_index)
  elements.reputation.caption = { "gb-contracts.reputation", storage.forces[player.force_index].reputation }
  refresh_credit(player, elements)
  elements.empty.visible = #list == 0
  for i, row in ipairs(elements.rows) do
    local contract = list[i]
    for _, cell in pairs(row) do cell.visible = contract ~= nil end
    if contract then
      local offered = contract.state == core.OFFERED
      row.who.caption = (contract.kind == "concession" or contract.kind == "outsourcing")
        and planets.caption(contract.counterparty) or contract.counterparty
      row.who.tooltip = { "gb-contracts.kind-" .. contract.kind }
      row.provides.caption = goods_text(contract.provides)
      row.requires.caption = goods_text(contract.requires, not offered and contract.delivered or nil)
      row.terms.caption = contract.charge
        and { "gb-contracts.charge-terms", string.format("%.0f", contract.charge),
          string.format("%.0f", core.guarantee(contract)) }
        or { "gb-contracts.terms", string.format("%.0f", contract.reward),
          string.format("%.0f", core.guarantee(contract)) }
      row.time.caption = offered and { "gb-contracts.offer-ends", minutes(contract.accept_by - game.tick) }
        or { "gb-contracts.due-in", minutes(contract.due_tick - game.tick) }
      row.primary.caption = offered and { "gb-contracts.accept" } or { "gb-contracts.abandon" }
      row.primary.tags = { gb_action = offered and "contract-accept" or "contract-abandon", id = contract.id }
      row.primary.tooltip = ""
      row.secondary.visible = offered
      row.secondary.tags = { gb_action = "contract-decline", id = contract.id }
      if contract.kind == "loan" and not offered then refresh_loan_row(row, contract) end
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
  local credit = body.add({ type = "flow", direction = "horizontal" })
  elements.debt = credit.add({ type = "label" })
  elements.borrow = {}
  for tier, principal in ipairs(loans_core.TIERS) do
    elements.borrow[tier] = credit.add({ type = "button", caption = { "gb-loans.borrow",
      catalog.format_credits(principal) }, tags = { gb_action = "loan-borrow", tier = tier } })
  end
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

-- Whether the window's hub still exists, is the player's force's and within reach (GUI events are
-- player input); when not, the window closes and the player is told why.
local function hub_usable(player, data)
  local hub = hubs.get(data.hub)
  if hub and hub.force == player.force and player.can_reach_entity(hub) then return true end
  contracts_gui.close(player.index)
  player.print({ "gb-contracts.hub-unavailable" })
  return false
end

actions["contract-accept"] = function(player, data, tags)
  if not hub_usable(player, data) then return end
  local contract = contracts.get(player.force_index, tags.id)
  local ok, reason
  if contract and contract.kind == "rental" then
    ok, reason = rental.accept(player.force_index, tags.id)
  else
    ok, reason = incoming.accept(player.force_index, tags.id, data.hub)
  end
  if not ok then player.print({ "gb-contracts.refused-" .. reason }) end
end

actions["contract-decline"] = function(player, _, tags)
  contracts.decline(player.force_index, tags.id)
end

actions["contract-abandon"] = function(player, data, tags)
  local contract = contracts.get(player.force_index, tags.id)
  if contract and contract.kind == "loan" and not hub_usable(player, data) then return end
  local outcome, reason = contracts.abandon(player.force_index, tags.id)
  if not outcome and reason then player.print(loan_refusal(reason)) end
end

actions["loan-borrow"] = function(player, data, tags)
  if not hub_usable(player, data) then return end
  local id, reason = loans.borrow(player.force_index, tags.tier)
  if not id then return player.print(loan_refusal(reason)) end
  local contract = contracts.get(player.force_index, id)
  player.print({ "gb-loans.borrowed-message", catalog.format_credits(contract.advance),
    catalog.format_credits(contract.charge), contract.installment_ticks / 3600, loans_core.periods() })
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

--- A hub is gone: the contracts windows opened from it close.
function contracts_gui.on_hub_removed(hub_unit_number)
  local closing = {}
  for player_index, data in pairs(storage.contracts_gui) do
    if data.hub == hub_unit_number then closing[#closing + 1] = player_index end
  end
  for _, player_index in ipairs(closing) do contracts_gui.close(player_index) end
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
