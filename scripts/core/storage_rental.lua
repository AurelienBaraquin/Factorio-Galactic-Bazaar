-- Storage rental (#119, ADR-0024). Pure Lua: the terms of storage space rented in both directions,
-- as contract specs (ADR-0015), and the room a vault has left.
--
-- A vault (kind "storage") is space a NPC rents to the force: a service contract (ADR-0019) that
-- charges VAULT_SLOTS × SLOT_RENT × VAULT_MARKUP every period of its term, its guarantee one period's
-- charge; the goods it holds stay the force's and move outside the contract. A warehouse contract
-- (kind "warehouse") is the force's space a NPC rents: the NPC provides goods worth TARGET_VALUE ×
-- the force's contract scale, at most FILL_SHARE of the warehouse's slots, and requires the same
-- goods back at the end of the term; the rent, SLOT_RENT per stack and period, is the reward paid
-- when every unit is handed back, and the guarantee exceeds the goods' value: at acceptance its
-- penalty rises to what buying them all back on the market would cost (`warehouse_penalty`).
local contract_offers = require("scripts.core.contract_offers")
local contracts = require("scripts.core.contracts")

local storage_rental = {}

storage_rental.TERM_TICKS = 3600 * 30
storage_rental.PERIOD_TICKS = 3600 * 5
-- Credits a stack of storage earns for one period, what a NPC pays; a NPC's vault charges more.
storage_rental.SLOT_RENT = 2
storage_rental.VAULT_MARKUP = 1.5
storage_rental.VAULT_SLOTS = 50
-- Share of a warehouse's slots a NPC fills at most.
storage_rental.FILL_SHARE = 0.5
-- A warehouse's penalty at acceptance: the cost of buying its goods back times BUY_MARGIN; when the
-- market cannot sell that many, the offer's penalty times UNQUOTED_FACTOR, with the margin.
storage_rental.BUY_MARGIN = 1.1
storage_rental.UNQUOTED_FACTOR = 2

storage_rental.VAULT_OPERATORS = { "Ceres Deep Vaults", "Titan Bonded Storage", "Oort Depository Trust" }

--- Periods in a term.
function storage_rental.periods()
  return storage_rental.TERM_TICKS / storage_rental.PERIOD_TICKS
end

--- What a vault of `slots` stacks charges every period.
function storage_rental.vault_charge(slots)
  return slots * storage_rental.SLOT_RENT * storage_rental.VAULT_MARKUP
end

--- The vault operator `draw` (a number in [0, 1)) picks.
function storage_rental.vault_operator(draw)
  local list = storage_rental.VAULT_OPERATORS
  return list[math.min(#list, math.floor(draw * #list) + 1)]
end

--- The contract spec of a vault of `slots` stacks rented from `counterparty`.
function storage_rental.vault(counterparty, slots)
  local charge = storage_rental.vault_charge(slots)
  return {
    kind = "storage", counterparty = counterparty, provides = {}, requires = {},
    reward = 0, deposit = charge, penalty = 0, charge = charge,
    duration_ticks = storage_rental.TERM_TICKS, accept_ticks = 60,
    installment_ticks = storage_rental.PERIOD_TICKS,
  }
end

--- Stacks that `goods` ({[name] = units}) take, given each item's stack size in `stack_sizes`.
function storage_rental.stacks(goods, stack_sizes)
  local used = 0
  for name, units in pairs(goods) do used = used + math.ceil(units / stack_sizes[name]) end
  return used
end

--- Units of `name` a vault of `slots` stacks holding `goods` can still take.
function storage_rental.room(goods, stack_sizes, slots, name)
  local others = {}
  for other, units in pairs(goods) do
    if other ~= name then others[other] = units end
  end
  local free = slots - storage_rental.stacks(others, stack_sizes)
  return math.max(0, free * stack_sizes[name] - (goods[name] or 0))
end

--- Units of an item a vault of `slots` stacks can still take, from the stacks it uses in all
--- (`used`), the stacks that item takes (`own`), its `units` and its `stack_size`: what `room`
--- returns, without walking the goods.
function storage_rental.room_in(used, own, units, stack_size, slots)
  return math.max(0, (slots - used + own) * stack_size - units)
end

--- The contract spec of a NPC storing `item` (base value `value`, stacks of `stack_size`) in a
--- warehouse of `slots` stacks, its counterparty picked by `draw`, its size scaled by `scale` (the
--- force's contract scale); nil without a positive value or a stack to fill.
function storage_rental.warehouse(item, value, stack_size, slots, draw, scale)
  local fill = math.floor(slots * storage_rental.FILL_SHARE)
  if not (value and value > 0 and stack_size >= 1 and fill >= 1) then return nil end
  local units = math.min(fill * stack_size, math.max(1, math.ceil(contract_offers.TARGET_VALUE * scale / value)))
  local worth = value * units
  local counterparties = contract_offers.COUNTERPARTIES
  return {
    kind = "warehouse", custody = true,
    counterparty = counterparties[math.min(#counterparties, math.floor(draw * #counterparties) + 1)],
    provides = { { kind = "item", name = item, count = units } },
    requires = { { kind = "item", name = item, count = units } },
    reward = storage_rental.SLOT_RENT * math.ceil(units / stack_size) * storage_rental.periods(),
    deposit = contract_offers.DEPOSIT_SHARE * worth,
    penalty = contract_offers.PENALTY_SHARE * worth,
    duration_ticks = storage_rental.TERM_TICKS,
    accept_ticks = contract_offers.ACCEPT_TICKS,
  }
end

--- The penalty of a warehouse contract at acceptance, from the offer's `penalty` and `buy_cost`,
--- what buying all its goods on the force's market would cost now with the price impact (nil when
--- the market cannot sell that many): enough that keeping the goods never costs less than buying
--- them, within the contract model's bound.
function storage_rental.warehouse_penalty(penalty, buy_cost)
  local cost = buy_cost or penalty * storage_rental.UNQUOTED_FACTOR
  return math.min(contracts.MAX_CREDITS, math.max(penalty, cost * storage_rental.BUY_MARGIN))
end

return storage_rental
