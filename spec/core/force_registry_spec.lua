local force_registry = require("scripts.core.force_registry")

describe("force_registry.ensure", function()
  it("creates a missing state", function()
    local forces = {}
    local state = force_registry.ensure(forces, 1)
    assert.are.same({}, state)
    assert.are.equal(state, forces[1])
  end)

  it("returns the existing state unchanged", function()
    local existing = { marker = true }
    local forces = { [1] = existing }
    assert.are.equal(existing, force_registry.ensure(forces, 1))
  end)
end)

describe("force_registry.sync", function()
  it("creates states for new forces and keeps existing ones", function()
    local existing = { marker = true }
    local forces = { [1] = existing }
    force_registry.sync(forces, { 1, 2, 3 })
    assert.are.equal(existing, forces[1])
    assert.are.same({}, forces[2])
    assert.are.same({}, forces[3])
  end)

  it("drops states of forces that no longer exist", function()
    local forces = { [1] = {}, [4] = {}, [7] = {} }
    force_registry.sync(forces, { 1 })
    assert.are.same({ [1] = {} }, forces)
  end)
end)

describe("force_registry.merge", function()
  it("removes the source and keeps the destination state", function()
    local destination = { marker = true }
    local forces = { [1] = destination, [2] = {} }
    force_registry.merge(forces, 2, 1)
    assert.is_nil(forces[2])
    assert.are.equal(destination, forces[1])
  end)

  it("creates the destination state when it is missing", function()
    local forces = { [2] = {} }
    force_registry.merge(forces, 2, 1)
    assert.are.same({ [1] = {} }, forces)
  end)
end)
