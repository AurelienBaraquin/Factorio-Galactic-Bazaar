-- The manifold module (#63): two storage tanks that trade fluids with the market, tinted orange
-- (export) and green (import), derived from the base storage tank.
local MANIFOLDS = {
  { name = "gb-fluid-export", tint = { 1, 0.6, 0.2, 1 }, order = "c[manifold]-a[export]" },
  { name = "gb-fluid-import", tint = { 0.4, 1, 0.5, 1 }, order = "c[manifold]-b[import]" },
}

-- The storage tank's picture is a Sprite4Way of sheets (one image per direction pair).
local function tint_sheets(picture, tint)
  for _, sheet in pairs(picture.sheets or { picture }) do
    if not sheet.draw_as_shadow then sheet.tint = tint end
  end
end

for _, spec in ipairs(MANIFOLDS) do
  local entity = table.deepcopy(data.raw["storage-tank"]["storage-tank"])
  entity.name = spec.name
  entity.icons = { { icon = "__base__/graphics/icons/storage-tank.png", tint = spec.tint } }
  entity.icon = nil
  entity.minable = { mining_time = 0.5, result = spec.name }
  entity.fast_replaceable_group = nil
  entity.next_upgrade = nil
  tint_sheets(entity.pictures.picture, spec.tint)
  data:extend({
    entity,
    {
      type = "item",
      name = spec.name,
      icons = entity.icons,
      subgroup = "galactic-bazaar",
      order = spec.order,
      place_result = spec.name,
      stack_size = 10,
    },
    {
      type = "recipe",
      name = spec.name,
      enabled = false,
      energy_required = 3,
      ingredients = {
        { type = "item", name = "storage-tank", amount = 1 },
        { type = "item", name = "electronic-circuit", amount = 10 },
      },
      results = { { type = "item", name = spec.name, amount = 1 } },
    },
  })
end
