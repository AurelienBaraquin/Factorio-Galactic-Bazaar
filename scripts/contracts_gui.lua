-- The Contracts tab of the Galactic Bazaar window (#76, #78, #96, scripts/bazaar_gui.lua): a force's
-- offers and active contracts from counterparties (incoming contracts, machine rentals, leases and
-- loans). Offers can be accepted (an incoming contract's ingredients are shipped to the window's hub)
-- or declined; active contracts show their progress and deadline and can be abandoned, loans repaid;
-- every one of these actions, and borrowing, needs the window's hub within reach. Its credit line
-- shows the force's debt and borrows a principal tier.
-- Rows are built once and updated in place, so a refresh never destroys a button a player is
-- clicking (multiplayer latency). Interface state is the tab's view in storage.bazaar_gui.
local bazaar_gui = require("scripts.bazaar_gui")
local catalog = require("scripts.core.catalog")
local contracts = require("scripts.contracts")
local core = require("scripts.core.contracts")
local finance = require("scripts.finance")
local incoming = require("scripts.incoming_contracts")
local loans = require("scripts.loans")
local loans_core = require("scripts.core.loans")
local planets = require("scripts.planets")
local rental = require("scripts.rental")

local contracts_gui = {}

contracts_gui.ROWS = contracts.MAX_LISTED

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

-- Why a loan action (Borrow, or any refused abandon: a loan's Repay included) is refused, as a
-- localised string; the credit technology's name is its parameter (used by `not-researched`, ignored
-- by the other reasons).
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

local function refresh(player, view)
  local elements = view.elements
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
      row.time.caption = offered
        and { "gb-contracts.offer-ends", catalog.format_duration(contract.accept_by - game.tick) }
        or { "gb-contracts.due-in", catalog.format_duration(contract.due_tick - game.tick) }
      row.primary.caption = offered and { "gb-contracts.accept" } or { "gb-contracts.abandon" }
      row.primary.tags = { gb_action = offered and "contract-accept" or "contract-abandon", id = contract.id }
      row.primary.tooltip = ""
      -- The Decline cell stays in place, empty and disabled, for an active contract: hiding a cell of
      -- a table would shift every later cell into the wrong column.
      row.secondary.caption = offered and { "gb-contracts.decline" } or ""
      row.secondary.enabled = offered
      row.secondary.tags = offered and { gb_action = "contract-decline", id = contract.id } or {}
      if contract.kind == "loan" and not offered then refresh_loan_row(row, contract) end
    end
  end
end

local function build(_, container, view)
  local elements = {}
  local body = container.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  elements.reputation = body.add({ type = "label", style = "bold_label" })
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
      secondary = list.add({ type = "button", style = "red_button" }),
    }
  end
  view.elements = elements
end

local actions = {}

actions["contract-accept"] = function(player, tags, hub)
  local contract = contracts.get(player.force_index, tags.id)
  local ok, reason
  if contract and contract.kind == "rental" then
    ok, reason = rental.accept(player.force_index, tags.id)
  else
    ok, reason = incoming.accept(player.force_index, tags.id, hub.unit_number)
  end
  if not ok then player.print({ "gb-contracts.refused-" .. reason }) end
end

actions["contract-decline"] = function(player, tags)
  contracts.decline(player.force_index, tags.id)
end

actions["contract-abandon"] = function(player, tags)
  local outcome, reason = contracts.abandon(player.force_index, tags.id)
  if not outcome and reason then player.print(loan_refusal(reason)) end
end

actions["loan-borrow"] = function(player, tags)
  local id, reason = loans.borrow(player.force_index, tags.tier)
  if not id then return player.print(loan_refusal(reason)) end
  local contract = contracts.get(player.force_index, id)
  player.print({ "gb-loans.borrowed-message", catalog.format_credits(contract.advance),
    catalog.format_credits(contract.charge), contract.installment_ticks / 3600, loans_core.periods() })
end

-- Every action commits the force (accept, decline, abandon, repay, borrow): it needs the window's
-- hub, the player's force's and within reach (GUI events are player input), or the player is told
-- why and nothing changes. Each action is followed by a refresh of the tab, which shows its outcome.
local tab_actions = {}
for name, action in pairs(actions) do
  tab_actions[name] = function(player, view, tags, window)
    local hub = bazaar_gui.hub(player, window)
    if hub then
      action(player, tags, hub)
    else
      player.print(bazaar_gui.no_hub_message(player))
    end
    refresh(player, view)
  end
end

bazaar_gui.register_tab({ name = "contracts", order = 30, build = build, refresh = refresh, actions = tab_actions })

return contracts_gui
