-- In-game check of the balance simulation (tools/balance/sim.lua, docs/balance.md, #122): the figures it
-- copies from adapters and prototypes, which it cannot read outside the game, are the game's own.
local cargo = require("scripts.cargo")
local contracts = require("scripts.contracts")
local incoming = require("scripts.incoming_contracts")
local sim = require("tools.balance.sim")

describe("balance simulation", function()
  test("copies the adapters' and prototypes' figures exactly", function()
    assert.are.equal(cargo.DEFAULT_MIN_PRICE_RATIO, sim.EXPORT_MIN_PRICE_RATIO)
    assert.are.equal(prototypes.entity["gb-rental-assembler"].get_crafting_speed(), sim.RENTAL_SPEED)
    assert.are.equal(prototypes.entity["gb-rental-warehouse"].get_inventory_size(defines.inventory.chest),
      sim.WAREHOUSE_SLOTS)
    assert.are.equal(60 * 3600 / incoming.OFFER_TICKS, sim.OFFERS_PER_HOUR)
    assert.are.equal(contracts.MAX_LISTED, sim.MAX_LISTED)
  end)
end)
