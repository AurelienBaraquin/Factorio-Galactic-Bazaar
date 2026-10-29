# Entity I/O: items (with quality), fluids, electricity — Factorio 2.1.24

All signatures verified in `runtime-api.json` 2.1.24. Always check `entity.valid` first.

## Inventories

```lua
local inv = entity.get_inventory(defines.inventory.chest)   -- LuaControl::get_inventory; nil if none
-- containers: defines.inventory.chest; crafting machines (2.1): crafter_input / crafter_output /
-- crafter_modules / crafter_trash (assembling_machine_* and furnace_* no longer exist)
```

`LuaInventory` (selected):

| Call | Notes |
|---|---|
| `inv.get_item_count(item?)` | `item`: `ItemWithQualityID` = name string (**normal quality only**), `LuaItemPrototype`, `LuaItemStack`, or `{name=, quality=}`. No argument = all items. |
| `inv.get_item_quality_counts(item?)` | `{[quality_name] = count}` for one item |
| `inv.get_contents()` | **array** of `{name, quality, count}` (`ItemWithQualityCount`) — not a dictionary |
| `inv.insert(items)` → uint32 inserted | `items`: `ItemStackIdentification` = name (full stack!), `{name=, count=, quality=}` (`ItemStackDefinition`), or a `LuaItemStack` |
| `inv.remove(items)` → uint32 removed | same argument shapes |
| `inv.can_insert(items)`, `inv.get_insertable_count(item)` | check before taking money |
| `inv.find_item_stack(item)`, `inv.is_empty()`, `inv.is_full()`, `inv.count_empty_stacks()` | |
| `inv.transfer_from_inventory(src, filter?)`, `transfer_from_stack(stack)` | 2.1 additions |
| `inv.get_bar()/set_bar()`, `get_filter/set_filter` | for `with_bar` / filtered containers |

Selling items (atomic pattern — remove first, pay what was actually removed):

```lua
local function sell(force_index, inv, name, quality, wanted)
  local removed = inv.remove({name = name, quality = quality, count = wanted})
  if removed > 0 then
    local acct = storage.forces[force_index]
    acct.credits = acct.credits + removed * economy.price(force_index, name, quality)
  end
  return removed
end
```

Buying: compute `inv.get_insertable_count({name=, quality=})`, charge for `min(wanted, insertable,
affordable)`, then `inv.insert{...}` and **refund the difference** if `insert` returned less.

- Passing a bare string to `insert`/`remove` means one **full stack** of normal quality — always pass a
  table with `count`.
- Quality names: `"normal"` always exists; others (`"uncommon"`, ...) only if a quality mod is active
  — enumerate `prototypes.quality` (skip `"quality-unknown"`; check `.hidden`) instead of hardcoding.
- Item spoilage (Space Age): stacks carry `spoil_percent`; inserting `{..., spoil_percent = x}` is
  possible (`ItemStackDefinition`).
- A script-only buffer inventory: `game.create_inventory(size)` (persisted, store it in `storage`,
  call `.destroy()` when done; resizable with `resize`).

## Fluids (2.1 API — no `fluidbox`)

```text
entity.fluids_count                          -- number of fluid storages (FluidStorageIndex 1..n)
entity.get_fluid(i)                          -- Fluid {name, amount, temperature} or nil
entity.get_fluid_capacity(i)
entity.get_fluid_count(name?)                -- total amount, any temperature
entity.get_fluid_contents()                  -- {[name] = amount}
entity.insert_fluid({name = "water", amount = 1000, temperature = 15})  -- returns amount inserted
entity.extract_fluid{name = "water", amount = 500}                       -- returns amount removed
-- optional: minimum_temperature, maximum_temperature, temperature (exact)
entity.remove_fluid(i, amount)               -- by storage index, returns Fluid removed
entity.set_fluid(i, fluid)                   -- 2nd arg mandatory in 2.1; returns FluidAmount set
entity.clear_fluid(i), entity.clear_fluids()
entity.set_fluid_filter(i, "water")          -- lock a tank/port to one fluid
```

- **2.1 trap**: name-based removal is `extract_fluid{...}` (table argument); `remove_fluid(index, amount)`
  is index-based. 2.0 code `entity.fluidbox[1]` / `remove_fluid{name=...}` no longer works.
- `FluidAmount` is a fixed-point 64-bit value (smallest step 1/2^24): compare with a tolerance, round
  before pricing.
- Fluid temperature matters for price (steam). Read `temperature` from `get_fluid`; when inserting,
  give an explicit temperature (`prototypes.fluid[name].default_temperature` if unsure).
- A fluid port of the terminal can be a storage-tank-like entity or a crafting machine with fluid
  boxes; script reads/writes it with the calls above on a batched schedule.

## Electricity — electric-energy-interface (EEI)

Runtime members (`LuaEntity`, EEI-specific where noted):

| Member | R/W | Notes |
|---|---|---|
| `energy` | RW | energy currently in the buffer (J) |
| `electric_buffer_size` | RW (write: EEI only) | buffer capacity (J) |
| `power_production` | RW, EEI | production setting |
| `power_usage` | RW, EEI | consumption setting |
| `electric_interface_mode` | RW, 2.1 | `defines.electric_interface_mode.{primary_input, primary_output, secondary_input, secondary_output, tertiary_input, tertiary_output, tertiary_input_output, accumulator, solar_output}` |
| `input_flow_limit`, `output_flow_limit` | RW, 2.1 | per-entity flow limits |
| `electric_network`, `electric_network_id`, `is_connected_to_electric_network()` | R | connectivity checks |

Units: prototype `Energy` strings are converted to **joules per tick** (W / 60). The runtime
`power_production` / `power_usage` attributes are documented without a unit; treat them as **J/tick**
(consistent with the prototype) — **UNVERIFIED, confirm in game** with `/measured-command` or by reading
`energy` deltas before balancing prices.

Robust metering pattern (independent of the exact unit semantics): measure the buffer delta.

```lua
-- Buying power FROM the player's grid (player sells to the bazaar):
-- EEI as an input (e.g. mode tertiary_input or prototype usage_priority "secondary-input"),
-- buffer fills from the network; every N ticks credit what accumulated and empty it.
local function meter_sell(port, force_index, price_per_joule)
  local joules = port.energy
  if joules > 0 then
    port.energy = 0
    storage.forces[force_index].credits = storage.forces[force_index].credits + joules * price_per_joule
  end
end

-- Selling power TO the player's grid: pre-pay a block, put it in the buffer as an output.
local function meter_buy(port, force_index, joules, price_per_joule)
  local acct = storage.forces[force_index]
  local room = port.electric_buffer_size - port.energy
  local amount = math.min(joules, room, acct.credits / price_per_joule)
  if amount > 0 then
    acct.credits = acct.credits - amount * price_per_joule
    port.energy = port.energy + amount
  end
end
```

- Keep `power_production = 0` / `power_usage = 0` when using pure buffer metering so the EEI does not
  create or destroy energy on its own.
- Switching between buying and selling at runtime: `electric_interface_mode` (2.1) — or use two EEIs
  with fixed prototype priorities (simpler, also works the same in reasoning about priority).
- Network-wide flow graphs: `electric_network_statistics` (`LuaFlowStatistics`) exists on **electric
  poles**, not on the EEI; meter the EEI yourself (above) for per-terminal stats.

## Entities created by script (hub modules / hidden ports)

```lua
local port = entity.surface.create_entity{
  name = "gb-power-port", position = entity.position, force = entity.force,
  raise_built = false,             -- our own helper; we track it ourselves
}
storage.terminals[entity.unit_number].power_port = port
```

- Destroy helpers when the hub is removed (`port.destroy()` after `.valid` check), in the
  `on_object_destroyed` handler of the hub.
- Hidden helpers should not be minable/blueprintable (prototype flags) so players cannot desync our
  bookkeeping by removing them; still guard every access with `.valid`.

`LuaSurface.create_entity{...}` (table form, 2.1.24): required `name`, `position`; optional
`direction`, `mirror`, `quality`, `force`, `target`, `source`, `cause`, `snap_to_grid`, `fast_replace`,
`player`, `character`, `spill`, `raise_built`, `create_build_effect_smoke`, `spawn_decorations`,
`move_stuck_players`, `item`, `preserve_ghosts_and_corpses`, ... (plus type-specific extras).
