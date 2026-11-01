# Notifications

How the mod tells players what happened (#107): game alerts and chat lines, their grouping, and the
per-player settings that turn them off. Code: `scripts/core/notifications.lua` (kinds, categories,
throttling, pure) and `scripts/notifications.lua` (the entry point features call, and the output).

## What a player sees

An **alert** in the alert bar above the minimap: its icon, its message on hover; a click opens the map
at the building it points at. Kinds that have one also print a **chat line**, the alert's longer
version, which stays in the console once the alert is gone.

- The game keeps one custom alert per building and player: a later alert at the same building
  replaces the earlier one. The chat line keeps every message.
- The game removes custom alerts on its own after a short time (measured: gone within 1 200 ticks).
- The alert points at the building given by the feature (a rental assembler or rental warehouse for its offer, the hub a
  delivery landed at); otherwise at the hub of the player's force nearest to the player on the
  player's surface (on another surface, the lowest unit number); otherwise at the player's
  character. A player with none of these gets only the chat line, when the kind has one.

## Kinds

| Kind | Category | When | Icon | Chat | Grouping |
|---|---|---|---|---|---|
| `contract-offer` | contracts | an incoming offer is made (`incoming.make_offer`), or a rental offer pass offers machines or warehouses (`rental.on_offer_tick`, `warehouses.on_offer_tick`: one notification per force per pass, counting the buildings offered, the alert at the first) | `signal-info` | yes: how many offers, the kind of contract and how long the offer stands | once per minute per kind of contract (incoming, rental, warehouse), the count carried |
| `contract-due` | contracts | at a contract settlement, an active contract that requires goods is due within `DUE_SOON_TICKS` (2 min) and not complete | `signal-hourglass` | yes: time left, goods still owed, the guarantee at stake | once per contract |
| `contract-fulfilled` | contracts | the settlement fulfils a contract | `signal-check` | yes | none (bounded by the Contracts tab's 8 rows) |
| `contract-failed` | contracts | the settlement fails a contract (deadline passed, or a charge the force could not pay) | `signal-deny` | yes | none |
| `loan-defaulted` | finance | a loan installment could not be paid: the loan fails, the rest becomes arrears | `signal-exclamation-mark` | yes: the arrears | none |
| `delivery-landed` | deliveries | an unloading pass finished unloading shipments of the force at a hub | the hub's icon | no | one alert per hub per pass; at most one per hub every 30 s, counting every shipment that finished landing since the last alert |
| `insolvent` | finance | the insolvency check finds the force insolvent | `signal-alert` | always: the balance to reach, the grace left | none (a state change) |
| `recovered` | finance | the force is solvent again | `signal-green` | yes | none |
| `bankrupt` | finance | the force goes bankrupt | `signal-skull` | always: what ended, what it owes, the ban | none |
| `credit-restored` | finance | the credit ban ends | `signal-unlock` | yes | none |

The insolvency chat lines are the messages the insolvency check printed before #107
([contracts.md](contracts.md#insolvency-and-bankruptcy)), unchanged. Not told: expired or declined
offers, contracts a player abandons or repays from the Contracts tab (the window prints the
result), contracts voided because their goods left the game, and contracts a bankruptcy ends (the
bankruptcy message counts them). A shipment that landed but waits for room in the import chests or
manifolds is told only once it has finished unloading. Goods owed are shown with their quality when
it is not normal (`[item=name,quality=rare]`).

Each kind has one icon of its own, a base virtual signal or the hub item: Space Age is not needed.

## Settings

Per player, in *Settings → Mod settings → Per player* (`settings.lua`, `runtime-per-user`, all on by
default):

| Setting | Turns off |
|---|---|
| `gb-notify-contracts` | offers, contracts due, fulfilled and failed |
| `gb-notify-deliveries` | deliveries landed |
| `gb-notify-finance` | loan default, insolvency, recovery, bankruptcy, credit restored |

A category turned off hides both the alert and the chat line of its kinds for that player only,
except the chat lines marked *always* above (`chat_always`): insolvency and bankruptcy are printed
to every player of the force, the setting then hiding only their alert.

## Module API

```lua
local notifications = require("scripts.notifications")
notifications.notify(target, kind, params, entity)
```

- `target`: a `LuaForce`, a `LuaPlayer` (that player only) or a force index. The connected players of
  the force are told.
- `kind`: a key of `KINDS` in `scripts/core/notifications.lua`; a new kind needs an entry there (its
  category, icon, period, chat key, colour and `chat_always`) and the locale key `gb-notify.<kind>` in
  English and French.
- `params`: the locale parameters of the alert message and chat line (an array); `params.group`
  (optional) names the group throttling counts in; `params.count` (optional) is how many things the
  event stands for: a throttled event's count is carried to the next one told for its group, and the
  total is added as the last parameter.
- `entity` (optional): the building the alert points at; without `params.group`, its unit number is
  the group. Without either, the group is the force.
- Returns how many players were told: 0 when the event was throttled, and 0 for a force with no
  connected player, whose event still uses up the throttle.

Helpers for contracts: `notifications.contract(force_index, kind, contract, entity, count)` fills the
parameters every contract message may use (__1__ the kind of contract, __2__ the time left, __3__ the
goods still owed, __4__ the guarantee; for an offer, __5__ how many offers, `count`, 1 by default); `notifications.check_due(force_index, contract)` tells a
contract due soon; `notifications.contract_settled(force_index, contract, outcome)` tells an outcome of
the contract engine.

## Throttling and determinism

A kind with a period is told at most once per period for each group of a force: the first event is
told, later ones in the period are not, their counts kept as `pending` and added to the next event
told for that group (`notifications.admit`). The throttle log of each force lives in
`storage.notifications` ([data-model.md](data-model.md#storagenotifications)) and only holds groups
still within their period or with a count pending, so it stays small. It is created at the first
notification when a save lacks it. On a force merge the source's log is folded into the
destination's (`notifications.merge`: latest tick, pending counts added), so a contract due is not
told twice. What is told is decided for the force, the same
on every peer; each player's settings only decide what that player is shown. Notifications change no
other state: no economy value, contract or building depends on them.
