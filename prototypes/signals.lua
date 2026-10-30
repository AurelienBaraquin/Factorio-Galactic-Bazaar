-- Circuit combinators of the terminal: price signal combinators (ADR-0010), constant combinators
-- whose signals the script writes (buy prices on one, sell prices on the other, plus the force's
-- balance on a signal of its own), and the order combinator (ADR-0011), which the script only reads.
local COMBINATORS = {
  { name = "gb-buy-price-combinator", tint = { 0.4, 1, 0.5, 1 }, order = "e[signals]-a[buy]" },
  { name = "gb-sell-price-combinator", tint = { 1, 0.6, 0.2, 1 }, order = "e[signals]-b[sell]" },
  { name = "gb-order-combinator", tint = { 0.4, 0.7, 1, 1 }, order = "e[signals]-c[order]" },
}

local function tint_layers(sprite, tint)
  for _, layer in pairs(sprite.layers or { sprite }) do
    if not layer.draw_as_shadow then layer.tint = tint end
  end
end

data:extend({
  {
    type = "virtual-signal",
    name = "gb-credits",
    icon = "__base__/graphics/icons/coin.png",
    icon_size = 64,
    subgroup = "virtual-signal",
    order = "z[galactic-bazaar]-a[credits]",
  },
  {
    type = "virtual-signal",
    name = "gb-budget",
    icon = "__base__/graphics/icons/coin.png",
    icon_size = 64,
    subgroup = "virtual-signal",
    order = "z[galactic-bazaar]-b[budget]",
  },
})

for _, spec in ipairs(COMBINATORS) do
  local entity = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
  entity.name = spec.name
  entity.icons = { { icon = "__base__/graphics/icons/constant-combinator.png", tint = spec.tint } }
  entity.icon = nil
  entity.minable = { mining_time = 0.1, result = spec.name }
  entity.fast_replaceable_group = nil
  entity.next_upgrade = nil
  for _, direction in pairs(entity.sprites) do tint_layers(direction, spec.tint) end
  data:extend({
    entity,
    {
      type = "item",
      name = spec.name,
      icons = entity.icons,
      subgroup = "galactic-bazaar",
      order = spec.order,
      place_result = spec.name,
      stack_size = 50,
    },
    {
      type = "recipe",
      name = spec.name,
      enabled = false,
      energy_required = 2,
      ingredients = {
        { type = "item", name = "constant-combinator", amount = 1 },
        { type = "item", name = "electronic-circuit", amount = 5 },
      },
      results = { { type = "item", name = spec.name, amount = 1 } },
    },
  })
end
