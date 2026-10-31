-- The Planets tab of the Galactic Bazaar window (#83, #85, scripts/bazaar_gui.lua), available once
-- the force has researched planetary concessions: the NPC planets, their distance, transit terms,
-- specialties and the slots free for the player's force. A resource specialty can be leased from it
-- (a mining concession delivered to the window's hub, which must be within reach), a crafting one
-- booked. Rows are built once and updated in place; each column's rule is the tooltip of its header
-- and cells. Interface state is the tab's view in storage.bazaar_gui.
local bazaar_gui = require("scripts.bazaar_gui")
local concessions = require("scripts.concessions")
local contracts = require("scripts.contracts")
local planets = require("scripts.planets")
local transit = require("scripts.core.transit")

local planets_gui = {}

-- How a specialty reads: an item icon for a resource, the category's name for crafting.
local function specialty_caption(specialty)
  if specialty.kind == "resource" then
    return { "", "[item=" .. specialty.name .. "] ", prototypes.item[specialty.name].localised_name }
  end
  local category = prototypes.recipe_category[specialty.name]
  return { "?", { "gb-planets.category-" .. specialty.name }, category and category.localised_name or specialty.name }
end

local function refresh(player, view)
  local can_lease = concessions.researched(player.force, concessions.CONCESSION_TECHNOLOGY)
  local can_book = concessions.researched(player.force, concessions.OUTSOURCING_TECHNOLOGY)
  for _, row in ipairs(view.elements.rows) do
    local free = planets.free(player.force_index, row.planet, row.kind, row.name) or 0
    row.slots.caption = { "gb-planets.slots", free, row.total }
    if row.lease then row.lease.enabled = can_lease and free > 0 end
    if row.book then
      row.book.enabled = can_book and free > 0
      row.book.tooltip = can_book and { "gb-planets.book-terms" } or { "gb-planets.book-locked" }
    end
  end
end

-- The tooltip of a lease button: what one slot ships, its charge and guarantee.
local function lease_tooltip(planet, resource)
  local spec = concessions.terms(planet.name, resource, 1)
  if not spec then return { "gb-planets.lease-unavailable" } end
  local terms = transit.terms(planet.distance)
  return { "gb-planets.lease-terms", spec.provides[1].count / (spec.duration_ticks / spec.installment_ticks),
    spec.installment_ticks / 3600, spec.duration_ticks / 3600, string.format("%.0f", spec.charge),
    string.format("%.0f", spec.deposit), string.format("%.4g", terms.max_loss * 100) }
end

-- The rule behind each column, as the tooltip of its header and of its cells.
local function column_tooltips()
  local per_unit = transit.terms(1)
  return {
    planet = { "gb-planets.column-planet-tooltip" },
    distance = { "gb-planets.column-distance-tooltip", string.format("%d", per_unit.delay_ticks / 60),
      string.format("%.4g", per_unit.max_loss * 100), string.format("%.4g", transit.MAX_LOSS * 100) },
    transit = { "gb-planets.column-transit-tooltip" },
    specialty = { "gb-planets.column-specialty-tooltip" },
    free = { "gb-planets.column-free-tooltip" },
    lease = { "gb-planets.column-lease-tooltip" },
  }
end

-- The rows are taken from the catalog when the tab is first shown; the catalog only changes on
-- configuration change, which closes every window.
local function build(_, container, view)
  local elements = { rows = {} }
  local body = container.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  local list = body.add({ type = "table", column_count = 6 })
  local tooltips = column_tooltips()
  for _, header in ipairs({ "planet", "distance", "transit", "specialty", "free", "lease" }) do
    list.add({ type = "label", style = "bold_label", caption = { "gb-planets.column-" .. header },
      tooltip = tooltips[header] })
  end
  for _, planet in ipairs(planets.catalog()) do
    for _, specialty in ipairs(planet.specialties) do
      list.add({ type = "label", caption = planets.caption(planet.name), tooltip = tooltips.planet })
      list.add({ type = "label", caption = { "gb-planets.distance", planet.distance }, tooltip = tooltips.distance })
      local terms = transit.terms(planet.distance)
      list.add({ type = "label", caption = { "gb-planets.transit", string.format("%d", terms.delay_ticks / 60),
        string.format("%.4g", terms.max_loss * 100) }, tooltip = tooltips.transit })
      list.add({ type = "label", caption = specialty_caption(specialty), tooltip = tooltips.specialty })
      local row = {
        planet = planet.name, kind = specialty.kind, name = specialty.name, total = specialty.slots,
        slots = list.add({ type = "label", tooltip = tooltips.free }),
      }
      if specialty.kind == "resource" then
        row.lease = list.add({ type = "button", caption = { "gb-planets.lease" },
          tooltip = lease_tooltip(planet, specialty.name),
          tags = { gb_action = "planets-lease", planet = planet.name, resource = specialty.name } })
      else
        local cell = list.add({ type = "flow", direction = "horizontal" })
        row.recipe = cell.add({ type = "choose-elem-button", elem_type = "recipe",
          tooltip = { "gb-planets.book-recipe" } })
        row.book = cell.add({ type = "button", caption = { "gb-planets.book" }, tooltip = { "gb-planets.book-terms" },
          tags = { gb_action = "planets-book", planet = planet.name, category = specialty.name } })
      end
      elements.rows[#elements.rows + 1] = row
    end
  end
  view.elements = elements
end

-- Leases a slot from a lease or book button, at the window's hub, which must still be the player's
-- force's and within reach (GUI events are player input). A book button books its row's recipe.
local function lease(player, view, tags, window, element)
  local hub = bazaar_gui.hub(player, window)
  if not hub then return player.print(bazaar_gui.no_hub_message(player)) end
  local id, reason
  if tags.gb_action == "planets-book" then
    local recipe
    for _, row in ipairs(view.elements.rows) do
      if row.book == element then recipe = row.recipe.elem_value end
    end
    id, reason = concessions.book(player.force_index, hub.unit_number, tags.planet, tags.category, recipe)
  else
    id, reason = concessions.lease(player.force_index, hub.unit_number, tags.planet, tags.resource)
  end
  if id then
    local contract = contracts.get(player.force_index, id)
    local lease_record = storage.concessions[id]
    player.print({ "gb-planets.leased", planets.caption(tags.planet),
      lease_record.units, "[item=" .. lease_record.item .. "]", string.format("%.0f", contract.charge),
      string.format("%.0f", contract.deposit) })
  elseif reason == "not-researched" then
    local technology = tags.gb_action == "planets-book" and concessions.OUTSOURCING_TECHNOLOGY
      or concessions.CONCESSION_TECHNOLOGY
    player.print({ "gb-planets.refused-not-researched", prototypes.technology[technology].localised_name })
  else
    player.print({ "gb-planets.refused-" .. reason })
  end
  refresh(player, view)
end

bazaar_gui.register_tab({
  name = "planets", order = 40, build = build, refresh = refresh,
  actions = { ["planets-lease"] = lease, ["planets-book"] = lease },
  available = function(player) return concessions.researched(player.force, concessions.CONCESSION_TECHNOLOGY) end,
  locked_tooltip = function()
    return { "gb-bazaar.tab-locked", prototypes.technology[concessions.CONCESSION_TECHNOLOGY].localised_name }
  end,
})

return planets_gui
