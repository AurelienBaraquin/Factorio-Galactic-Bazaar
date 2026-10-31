-- The item detail of the Market tab (#110, scripts/market_gui.lua): for the selected key, its
-- prices and why they are what they are (base value, gap from it, liquidity, spread, NPC drift and
-- reversion), the impact of the quantity typed, the price history (telecommunications 2) and why
-- the base value is what it is. The figures come from scripts/core/item_detail.lua; only the
-- selected key is read, once per refresh. Elements are built once and updated in place.
local catalog = require("scripts.core.catalog")
local item_detail = require("scripts.core.item_detail")
local market = require("scripts.market")
local npc_market = require("scripts.core.npc_market")
local pricing = require("scripts.pricing")
local telecom = require("scripts.telecom")
local telecom_core = require("scripts.core.telecom")
local valuation = require("scripts.core.valuation")

local item_detail_gui = {}

-- Ingredient lines of the breakdown; a recipe with more shows how many are left out.
item_detail_gui.MAX_INPUTS = 10
-- Price history points shown (one per NPC step).
local HISTORY_WIDTH = 30
-- Width of the text of the panel, in pixels: long lines wrap.
local TEXT_WIDTH = 400
-- The market figures, in display order.
local FIGURES = { "buy", "sell", "mid", "base", "gap", "liquidity", "spread", "drift", "reversion", "seen" }

local function percent(ratio, signed)
  return string.format(signed and "%+.1f" or "%.1f", ratio * 100)
end

local function amount(number)
  return string.format("%.4g", number)
end

-- The market part of the detail: see item_detail_gui.read.
local function read_market(force, kind, name, quality_name, quantity)
  local base_value, live, params = market.position(force.index, kind, name, quality_name)
  if not base_value then return nil end
  local level = telecom.level(force)
  local period = telecom_core.period(level)
  local seen = pricing.key(kind, name, quality_name) == pricing.key(kind, name)
    and telecom.quote(force.index, kind, name, period) or nil
  local displacement = seen and item_detail.displacement_from_buy(base_value, seen.buy, params) or live
  return {
    figures = item_detail.market(base_value, displacement, params, npc_market.DEFAULTS),
    seen_tick = seen and seen.tick,
    period = period,
    level = level,
    history = seen and telecom_core.shows_history(level) and seen.history or nil,
    impact = quantity and item_detail.impact(base_value, live, quantity, params),
  }
end

-- Why a tradeable key is worth its base value: item_detail.breakdown and the quality ladder.
local function read_breakdown(kind, name, quality_name)
  local normal_key = pricing.key(kind, name)
  local _, ratio = pricing.key_value(pricing.key(kind, name, quality_name))
  local source = pricing.value_source(normal_key)
  local breakdown = item_detail.breakdown(source, {
    value = storage.base_values[normal_key], ratio = ratio,
    multiplier = settings.startup[pricing.MULTIPLIER_SETTING].value,
    override = storage.value_overrides and storage.value_overrides[normal_key],
    tier = source and source.tier or valuation.MAIN,
  })
  return breakdown, kind == "item" and item_detail.quality_ladder(storage.quality_levels or {}) or {}
end

--- The detail figures of `kind`/`name` (quality `quality_name`, default normal) for `force`, with
--- the impact of an order of `quantity` units (optional): {figures (item_detail.market, from the
--- prices the force sees: its telecommunications feed for the normal quality, live otherwise),
--- seen_tick, period, level, history, impact (live), breakdown (item_detail.breakdown), ladder}; nil
--- when the key is not tradeable.
function item_detail_gui.read(force, kind, name, quality_name, quantity)
  local detail = read_market(force, kind, name, quality_name, quantity)
  if detail then detail.breakdown, detail.ladder = read_breakdown(kind, name, quality_name) end
  return detail
end

local function add_label(parent, caption, style)
  local label = parent.add({ type = "label", caption = caption, style = style })
  label.style.single_line = false
  label.style.maximal_width = TEXT_WIDTH
  return label
end

--- Adds the detail's elements to `detail` (the Market tab's detail frame) and their references to
--- `elements.info`.
function item_detail_gui.build(detail, elements)
  local info = {}
  local impact = detail.add({ type = "table", column_count = 2 })
  for _, side in ipairs({ "buy", "sell" }) do
    info["impact_" .. side .. "_label"] = impact.add({ type = "label", style = "bold_label",
      tooltip = { "gb-detail.impact-rule" } })
    info["impact_" .. side] = impact.add({ type = "label", tooltip = { "gb-detail.impact-rule" } })
  end

  add_label(detail, { "gb-detail.market-title" }, "caption_label")
  local figures = detail.add({ type = "table", column_count = 2 })
  info.figures, info.figure_labels = {}, {}
  for _, id in ipairs(FIGURES) do
    info.figure_labels[id] = figures.add({ type = "label", caption = { "gb-detail.figure-" .. id } })
    info.figures[id] = figures.add({ type = "label" })
  end

  info.history_title = add_label(detail, { "gb-detail.history-title" }, "caption_label")
  info.history_title.tooltip = { "gb-detail.history-rule" }
  elements.history = detail.add({ type = "label", tooltip = { "gb-detail.history-rule" } })
  info.history_scale = add_label(detail, "")
  info.history_note = add_label(detail, "")

  info.breakdown_title = add_label(detail, "", "caption_label")
  info.source = add_label(detail, "")
  info.inputs = {}
  for i = 1, item_detail_gui.MAX_INPUTS do info.inputs[i] = add_label(detail, "") end
  info.more = add_label(detail, "")
  info.cost = add_label(detail, "")
  info.per_unit = add_label(detail, "")
  info.factor = add_label(detail, "")
  info.tier = add_label(detail, "")
  info.multiplier = add_label(detail, "")
  info.ladder = add_label(detail, "")
  elements.info = info
end

-- A key's icon as rich text and its name, for the breakdown lines.
local function key_caption(key)
  local kind, name = key:match("^(%a+)/(.+)$")
  local group = kind == "item" and prototypes.item or kind == "fluid" and prototypes.fluid
  local prototype = group and group[name]
  if prototype then return "[" .. kind .. "=" .. name .. "]", prototype.localised_name end
  if kind == "energy" then return "", { "gb-detail.electricity" } end
  return "", key
end

local function refresh_impact(info, quantity, impact)
  for _, side in ipairs({ "buy", "sell" }) do
    local label, value = info["impact_" .. side .. "_label"], info["impact_" .. side]
    local result = impact and impact[side]
    label.caption = quantity and { "gb-detail.impact-" .. side, quantity } or ""
    if not result then
      value.caption = ""
    elseif result.reason then
      value.caption = { "gb-gui.refused-" .. result.reason }
    else
      value.caption = { "gb-detail.impact-value", catalog.format_credits(result.average),
        catalog.format_credits(result.next_price) }
    end
  end
end

local function gap_caption(figures)
  local units = catalog.format_units(math.abs(figures.displacement))
  local state = units == "0" and { "gb-detail.gap-balanced" }
    or figures.displacement < 0 and { "gb-detail.gap-shortage", units } or { "gb-detail.gap-surplus", units }
  return { "gb-detail.gap-value", percent(figures.gap, true), state }
end

-- The market figures' values: written when the prices the force sees change.
local function refresh_figures(info, detail)
  local figures, cells = detail.figures, info.figures
  local step = catalog.format_duration(figures.step_ticks)
  local values = {
    buy = catalog.format_credits(figures.buy),
    sell = catalog.format_credits(figures.sell),
    mid = catalog.format_credits(figures.mid),
    base = catalog.format_credits(figures.base_value),
    gap = gap_caption(figures),
    liquidity = { "gb-detail.liquidity-value", catalog.format_units(figures.max_buy),
      catalog.format_units(figures.max_sell) },
    spread = { "gb-detail.spread-value", percent(figures.spread), catalog.format_credits(figures.spread_credits) },
    drift = { "gb-detail.drift-value", catalog.format_units(figures.drift_units), percent(figures.drift_ratio), step },
    reversion = { "gb-detail.reversion-value", catalog.format_duration(figures.half_life_ticks),
      catalog.format_credits(figures.reverted_mid) },
  }
  for id, caption in pairs(values) do cells[id].caption = caption end
end

-- How old the prices seen are: written on every refresh.
local function refresh_seen(info, detail)
  info.figures.seen.caption = detail.seen_tick and { "gb-detail.seen-value",
    catalog.format_duration(game.tick - detail.seen_tick), catalog.format_duration(detail.period) }
    or { "gb-detail.seen-live" }
end

-- The rule each figure follows, as tooltips: they depend on the key's base value only.
local function refresh_rules(info, detail)
  local figures = detail.figures
  local depth = catalog.format_units(figures.depth)
  local half_spread = percent(figures.spread / 2)
  local rules = {
    buy = { "gb-detail.figure-buy-rule", half_spread },
    sell = { "gb-detail.figure-sell-rule", half_spread },
    mid = { "gb-detail.figure-mid-rule", depth },
    base = { "gb-detail.figure-base-rule" },
    gap = { "gb-detail.figure-gap-rule", depth, catalog.format_credits(figures.depth * figures.base_value) },
    liquidity = { "gb-detail.figure-liquidity-rule", catalog.format_units(figures.bound_units),
      amount(figures.bound_units / figures.depth), catalog.format_credits(figures.floor),
      catalog.format_credits(figures.ceiling) },
    spread = { "gb-detail.figure-spread-rule" },
    drift = { "gb-detail.figure-drift-rule", catalog.format_duration(figures.step_ticks),
      percent(figures.drift_units / figures.depth) },
    reversion = { "gb-detail.figure-reversion-rule", catalog.format_duration(figures.half_life_ticks) },
    seen = { "gb-detail.figure-seen-rule" },
  }
  for _, id in ipairs(FIGURES) do info.figures[id].tooltip, info.figure_labels[id].tooltip = rules[id], rules[id] end
end

local function refresh_history(info, elements, detail)
  local summary = detail.history and item_detail.history(detail.history)
  elements.history.visible = summary ~= nil
  info.history_scale.visible = summary ~= nil
  info.history_note.visible = summary == nil
  if summary then
    elements.history.caption = { "gb-gui.history", telecom_core.sparkline(detail.history, HISTORY_WIDTH) }
    local steps = math.min(#detail.history, HISTORY_WIDTH)
    info.history_scale.caption = { "gb-detail.history-scale", catalog.format_credits(summary.low),
      catalog.format_credits(summary.high), catalog.format_credits(summary.last), percent(summary.change, true),
      amount((steps - 1) * npc_market.DEFAULTS.step_ticks / 3600) }
  elseif detail.level >= telecom_core.HISTORY_LEVEL then
    info.history_note.caption = { "gb-detail.history-empty" }
  else
    info.history_note.caption = { "gb-detail.history-locked",
      prototypes.technology[telecom.TECHNOLOGIES[telecom_core.HISTORY_LEVEL]].localised_name }
  end
end

-- The line naming the source of a base value.
local function source_caption(breakdown)
  local kind, name = breakdown.kind, breakdown.name
  if kind == "fixed" then return { "gb-detail.source-fixed", catalog.format_credits(breakdown.fixed) } end
  if kind == "unknown" then return { "gb-detail.source-unknown" } end
  if kind == "recipe" then
    local recipe = prototypes.recipe[name]
    return { "gb-detail.source-recipe", "[recipe=" .. name .. "]", recipe and recipe.localised_name or name }
  end
  if kind == "mine" then
    local entity = prototypes.entity[name]
    local thing = entity and { "", "[entity=" .. name .. "] ", entity.localised_name }
      or prototypes.asteroid_chunk[name] and prototypes.asteroid_chunk[name].localised_name or name
    return { breakdown.tier == valuation.NATURAL and "gb-detail.source-gather" or "gb-detail.source-mine", thing }
  end
  local icon, label = key_caption((kind == "pump" and "fluid/" or "item/") .. name)
  return { "gb-detail.source-" .. kind, { "", icon, " ", label } }
end

local function set_line(label, caption)
  label.visible = caption ~= nil
  if caption then label.caption = caption end
end

local function ladder_caption(ladder, normal_value)
  if #ladder == 0 then return nil end
  local steps = { "" }
  for i, step in ipairs(ladder) do
    if i > 9 then break end
    if i > 1 then steps[#steps + 1] = ", " end
    local prototype = prototypes.quality[step.name]
    steps[#steps + 1] = { "gb-detail.quality-step", prototype and prototype.localised_name or step.name,
      amount(step.ratio), catalog.format_credits(normal_value * step.ratio) }
  end
  return { "gb-detail.quality-ladder", steps }
end

local function refresh_breakdown(info, detail)
  local breakdown = detail.breakdown
  info.breakdown_title.caption = { "gb-detail.breakdown-title", catalog.format_credits(breakdown.value) }
  info.source.caption = source_caption(breakdown)
  for i, label in ipairs(info.inputs) do
    local input = breakdown.inputs[i]
    label.visible = input ~= nil
    if input then
      local icon, name = key_caption(input.key)
      label.caption = { "gb-detail.ingredient", icon, name, amount(input.amount), catalog.format_credits(input.value),
        catalog.format_credits(input.total) }
    end
  end
  local hidden = #breakdown.inputs - #info.inputs
  set_line(info.more, hidden > 0 and { "gb-detail.more-ingredients", hidden } or nil)
  local cost
  if breakdown.seconds then
    cost = { "gb-detail." .. (breakdown.kind == "mine" and "mining-time" or "crafting-time"), amount(breakdown.seconds),
      catalog.format_credits(breakdown.cost / breakdown.seconds), catalog.format_credits(breakdown.cost) }
  elseif breakdown.kind == "pump" then
    cost = { "gb-detail.pumping-cost", catalog.format_credits(breakdown.cost) }
  end
  set_line(info.cost, cost)
  set_line(info.per_unit, breakdown.graph_value and { "gb-detail.per-unit",
    catalog.format_credits(breakdown.graph_value * breakdown.share * breakdown.amount), breakdown.share,
    amount(breakdown.amount), catalog.format_credits(breakdown.graph_value) })
  set_line(info.factor, breakdown.factor and { "gb-detail.factor", amount(breakdown.factor),
    catalog.format_credits(breakdown.normal_value) })
  local fallback = breakdown.tier == valuation.FALLBACK and breakdown.kind ~= "fixed"
  set_line(info.tier, fallback and { "gb-detail.fallback-note" } or nil)
  local multiplied = breakdown.multiplier ~= 1
  set_line(info.multiplier, multiplied and { "gb-detail.multiplier", amount(breakdown.multiplier) } or nil)
  set_line(info.ladder, breakdown.ratio ~= 1 and { "gb-detail.quality-ratio", amount(breakdown.ratio),
    catalog.format_credits(breakdown.normal_value) } or ladder_caption(detail.ladder, breakdown.normal_value))
end

--- Updates the detail's elements for `kind`/`name` and `quantity` (nil when none is typed). Reads
--- the key's market once (ADR-0004). Only what may have changed is written: the order impact and
--- the age of the prices on every refresh, the market figures and the history when the price seen
--- or the research changes, the breakdown and the rules when the key or its base value changes. The
--- marks of what is shown are kept in `elements.info`.
function item_detail_gui.refresh(player, elements, kind, name, quantity)
  local detail = read_market(player.force, kind, name, nil, quantity)
  if not detail then return end
  local info = elements.info
  -- Marks of the breakdown, cheaper than the breakdown: it is known once a source or a fixed value is.
  local key, value = pricing.key(kind, name), detail.figures.base_value
  local override = storage.value_overrides and storage.value_overrides[key]
  local known = pricing.value_source(key) ~= nil or (override ~= nil and override.value ~= nil)
  local new_key = info.key ~= key or info.value ~= value or info.known ~= known
  refresh_impact(info, quantity, detail.impact)
  refresh_seen(info, detail)
  if new_key or info.buy ~= detail.figures.buy or info.level ~= detail.level then
    refresh_figures(info, detail)
    refresh_history(info, elements, detail)
  end
  if new_key then
    detail.breakdown, detail.ladder = read_breakdown(kind, name)
    refresh_rules(info, detail)
    refresh_breakdown(info, detail)
  end
  info.key, info.value, info.known, info.buy, info.level = key, value, known, detail.figures.buy, detail.level
end

return item_detail_gui
