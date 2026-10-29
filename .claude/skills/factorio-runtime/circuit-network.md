# Circuit network (Factorio 2.1.24)

Verified in `runtime-api.json` 2.1.24. Since 2.0, wires attach to **wire connectors** identified by
`defines.wire_connector_id`: `circuit_red`, `circuit_green` (single-connector entities: chests, poles,
constant combinators...), `combinator_input_red/green`, `combinator_output_red/green` (arithmetic,
decider, selector), `pole_copper`, `power_switch_left_copper`, `power_switch_right_copper`.

## Signals

- `SignalID` = `{type = ?, name = ?, quality = ?}`; `type` ∈ `"item"` (default; **read back as nil**),
  `"fluid"`, `"virtual"`, `"entity"`, `"recipe"`, `"space-location"`, `"asteroid-chunk"`, `"quality"`.
  `quality` defaults to normal.
- `Signal` = `{signal = SignalID, count = int32}`.
- **Values are int32** (−2,147,483,648 … 2,147,483,647). Credits, prices × quantities and fluid
  amounts overflow easily. Always clamp before writing and choose a scale (e.g. price in centi-credits,
  credits in thousands) documented in the GUI/tooltip.

```lua
local INT32_MAX, INT32_MIN = 2147483647, -2147483648
local function to_signal(n)
  n = math.floor(n + 0.5)
  if n > INT32_MAX then return INT32_MAX elseif n < INT32_MIN then return INT32_MIN end
  return n
end
```

## Reading

```lua
local W = defines.wire_connector_id
-- Sum of red + green on one entity (single call):
local orders = entity.get_signals(W.circuit_red, W.circuit_green)        -- array of Signal or nil
local want = entity.get_signal({type = "item", name = "iron-plate", quality = "normal"},
                               W.circuit_red, W.circuit_green)            -- int32
-- Or via the network object (one colour):
local net = entity.get_circuit_network(W.circuit_red)                     -- LuaCircuitNetwork or nil
if net then
  local v = net.get_signal({type = "virtual", name = "signal-A"})
  local all = net.signals                                                 -- array of Signal or nil
end
-- Cheap change detection before a full read (2.1):
if entity.get_signals_changed(W.circuit_red, storage.last_read_tick) then
  orders = entity.get_signals(W.circuit_red, W.circuit_green)
end
storage.last_read_tick = game.tick
```

- `get_signals` / `signals` return `nil` when nothing is connected or the network is empty: guard it.
- Combinators read inputs on `combinator_input_*`, emit on `combinator_output_*`.
- Item signals read back with `signal.type == nil`; normalise `type = sig.signal.type or "item"`.
- Signals have a one-tick propagation delay per combinator; orders read from circuits are naturally
  "last tick's" values — fine for a market, but do not expect same-tick round trips.

## Writing: constant combinator sections

The terminal emits prices/stock by owning a (hidden) constant combinator and writing its sections.

```lua
local function write_prices(combinator, price_signals)   -- price_signals: { {name=, quality=, value=}, ... }
  local cb = combinator.get_or_create_control_behavior() -- LuaConstantCombinatorControlBehavior
  local section = cb.get_section(1) or cb.add_section()  -- add_section(group?) -> LuaLogisticSection
  local filters = {}
  for i, p in ipairs(price_signals) do
    filters[i] = {
      value = {type = "item", name = p.name, quality = p.quality or "normal", comparator = "="},
      min = to_signal(p.value),                          -- min = emitted signal value (int32)
    }
  end
  section.filters = filters                              -- bulk write; only on manual sections
  cb.enabled = true
end
```

API facts:
- `LuaConstantCombinatorControlBehavior`: `enabled` (RW), `sections`, `sections_count`,
  `add_section(group?)`, `get_section(i)`, `remove_section(i)`.
- `LuaLogisticSection`: `filters` (RW array of `LogisticFilter`), `set_slot(i, filter)`,
  `get_slot(i)`, `clear_slot(i)`, `active` (RW), `multiplier` (RW float), `group` (RW string),
  `is_manual`, `type` (`defines.logistic_section_type`), `filters_count`, `index`, `owner`.
- `LogisticFilter` = `{value = SignalFilter, min = int32, max = ?, ...}`. `SignalFilter` =
  `{name, type?, quality?, comparator?}`; when `min ~= 0`, **`quality` is mandatory and `comparator`
  must be `"="`**.
- `filters` and `set_slot` only work on **manual** sections (`section.is_manual`).
- The constant combinator output value is the filter's `min`: confirmed by real mods
  (sosciencity `city-combinator.lua`, warptorio-space-age `warp_constant_combinator.lua`) — the API doc
  only describes `min` as "minimum amount to satisfy". Some mods also set `max = min`; not required as
  far as the docs show (UNVERIFIED either way; test in game).
- `set_slot`'s doc says it "will silently fail if personal logistics are not researched yet" — written
  for character/logistic points; whether it also affects constant combinators is UNVERIFIED. Prefer
  writing `section.filters` and verify in game.
- A section `group` name makes it a shared logistic group across all entities using it — **never set
  `group` on our hidden combinators** (would leak into player groups of the force).
- Write only when values change (keep a hash/last-written table in storage) — rewriting thousands of
  filters every tick is a UPS sink.

## Wires by script

```lua
local a = hub.get_wire_connector(defines.wire_connector_id.circuit_red, true)   -- or_create = true
local b = port.get_wire_connector(defines.wire_connector_id.circuit_red, true)
a.connect_to(b, false, defines.wire_origin.script)   -- (target, reach_check?, origin?) -> boolean
-- wire_origin.player: normal visible wire players can edit;
-- wire_origin.script: only scripts/game can modify it and it is never drawn -> ideal for hub<->port links
```

`LuaWireConnector`: `connect_to`, `disconnect_from`, `disconnect_all`, `is_connected_to`,
`connections`, `connection_count`, `network_id`, `wire_type`, `owner`, `valid`.

## Decider combinator (2.0+ conditions/outputs)

`LuaDeciderCombinatorControlBehavior.parameters` = `{conditions = {...}, outputs = {...},
else_outputs = {...}}`, plus `add_/get_/set_/remove_condition`, `..._output`, and (2.1)
`..._else_output`. Prefer reading
signals directly in Lua instead of building logic with script-owned deciders.
