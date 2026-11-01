-- Pure layout of the in-game check's scene (tests/ingame_check/init.lua, docs/ingame-check.md):
-- buildings in rows, with an empty lane between rows where substations power them.
local plan = {}

--- Places `entries` ({width, height} in tiles, in order) left to right from (0, 0), wrapping before
--- `max_width`; rows are `lane` tiles apart and buildings `gap` tiles apart. Returns
--- `{positions = {{x, y}...}, lanes = {y...}, width, height}`: entity centres, the centre line of a
--- lane above each row and below the last, and the size of the whole scene.
function plan.layout(entries, max_width, gap, lane)
  local positions, lanes = {}, { -lane / 2 }
  local x, y, row_height, width = 0, 0, 0, 0
  for index, entry in ipairs(entries) do
    if x > 0 and x + entry.width > max_width then
      y = y + row_height + lane
      lanes[#lanes + 1] = y - lane / 2
      x, row_height = 0, 0
    end
    positions[index] = { x = x + entry.width / 2, y = y + entry.height / 2 }
    x = x + entry.width + gap
    width = math.max(width, x - gap)
    row_height = math.max(row_height, entry.height)
  end
  lanes[#lanes + 1] = y + row_height + lane / 2
  return { positions = positions, lanes = lanes, width = width, height = y + row_height }
end

--- Substation positions along each lane, `spacing` tiles apart, covering x from 0 to `width`.
function plan.substations(layout, spacing)
  local list = {}
  for _, y in ipairs(layout.lanes) do
    for x = 0, layout.width + spacing - 1, spacing do list[#list + 1] = { x = x, y = y } end
  end
  return list
end

--- Hub positions along each lane, halfway between substations `spacing` tiles apart, so that every
--- building is near one.
function plan.hubs(layout, spacing)
  local list = {}
  for _, y in ipairs(layout.lanes) do
    for x = spacing / 2, layout.width, spacing do list[#list + 1] = { x = x, y = y } end
  end
  return list
end

--- The values of `list` whose `key(value)` was not seen before, in order.
function plan.unique(list, key)
  local seen, result = {}, {}
  for _, value in ipairs(list) do
    local k = key(value)
    if not seen[k] then
      seen[k] = true
      result[#result + 1] = value
    end
  end
  return result
end

return plan
