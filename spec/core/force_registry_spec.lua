local force_registry = require("scripts.core.force_registry")

local function new_state()
  return {
    balance = 0, journal = {}, markets = {}, reputation = 0, contracts = { open = {}, history = {} },
    reservations = {},
  }
end

describe("force_registry.ensure", function()
  it("creates a missing state with its account", function()
    local forces = {}
    local state = force_registry.ensure(forces, 1)
    assert.are.same(new_state(), state)
    assert.are.equal(state, forces[1])
  end)

  it("returns the existing state, filling in fields it lacks", function()
    local existing = { marker = true }
    local forces = { [1] = existing }
    assert.are.equal(existing, force_registry.ensure(forces, 1))
    assert.is_true(existing.marker)
    assert.are.equal(0, existing.balance)
  end)
end)

describe("force_registry.sync", function()
  it("creates states for new forces and keeps existing ones", function()
    local existing = { marker = true, balance = 5, journal = {}, markets = {} }
    local forces = { [1] = existing }
    force_registry.sync(forces, { 1, 2, 3 })
    assert.are.equal(existing, forces[1])
    assert.are.same(new_state(), forces[2])
    assert.are.same(new_state(), forces[3])
  end)

  it("drops states of forces that no longer exist", function()
    local forces = { [1] = new_state(), [4] = new_state(), [7] = new_state() }
    force_registry.sync(forces, { 1 })
    assert.are.same({ [1] = new_state() }, forces)
  end)
end)

describe("force_registry.merge", function()
  it("removes the source and keeps the destination state", function()
    local destination = { marker = true, balance = 0, journal = {}, markets = {} }
    local forces = { [1] = destination, [2] = new_state() }
    force_registry.merge(forces, 2, 1)
    assert.is_nil(forces[2])
    assert.are.equal(destination, forces[1])
  end)

  it("adds the source balance to the destination", function()
    local forces = {
      [1] = { balance = 10, journal = {}, markets = {} },
      [2] = { balance = 32, journal = {}, markets = {} },
    }
    force_registry.merge(forces, 2, 1)
    assert.are.equal(42, forces[1].balance)
  end)

  it("creates the destination state when it is missing", function()
    local forces = { [2] = new_state() }
    force_registry.merge(forces, 2, 1)
    assert.are.same({ [1] = new_state() }, forces)
  end)

  it("carries the source's open contracts and reputation debt into the destination", function()
    local forces = { [1] = new_state(), [2] = new_state() }
    forces[2].contracts.open[9] = { id = 9 }
    forces[2].reservations[1] = { planet = "a", contract = 9 }
    forces[1].reputation, forces[2].reputation = 1, -2
    force_registry.merge(forces, 2, 1)
    assert.are.same({ id = 9 }, forces[1].contracts.open[9])
    assert.are.same({ { planet = "a", contract = 9 } }, forces[1].reservations)
    assert.are.equal(-1, forces[1].reputation)
  end)
end)

describe("force_registry.ensure on a state saved before contracts", function()
  it("adds the contract book and the reputation", function()
    local forces = { [1] = { balance = 5, journal = {}, markets = {} } }
    force_registry.ensure(forces, 1)
    assert.are.same({ open = {}, history = {} }, forces[1].contracts)
    assert.are.equal(0, forces[1].reputation)
    assert.are.same({}, forces[1].reservations)
  end)

  it("brings a reputation saved without bounds within them", function()
    local forces = { [1] = { balance = 5, journal = {}, markets = {}, reputation = 35 } }
    force_registry.ensure(forces, 1)
    assert.are.equal(20, forces[1].reputation)
  end)
end)
