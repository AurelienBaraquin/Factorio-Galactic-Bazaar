#!/usr/bin/env python3
"""Writes tools/balance/values.lua, the balance simulation's snapshot of the game's base values.

  tools/balance/snapshot.py <vanilla-dump.json> <space-age-dump.json> > tools/balance/values.lua

Each dump is the JSON the game writes from storage.base_values, the stack sizes and the incoming
contract recipes (docs/balance.md, "Regenerating the snapshot"). Standard library only.
"""
import json
import sys

# Recipes of the snapshot: the incoming-contract candidates the simulation offers, from cheap and
# simple to dear and long, present in both games where they exist.
RECIPES = ['iron-gear-wheel', 'copper-cable', 'electronic-circuit', 'automation-science-pack',
           'logistic-science-pack', 'inserter', 'transport-belt', 'pipe', 'engine-unit', 'advanced-circuit',
           'electric-mining-drill', 'assembling-machine-2', 'solar-panel', 'flying-robot-frame',
           'low-density-structure', 'spidertron']
# Goods the scenarios trade, besides those of the recipes.
EXTRA = ['iron-ore', 'copper-ore', 'coal', 'stone', 'wood', 'iron-plate', 'copper-plate', 'steel-plate', 'plastic-bar',
         'stone-brick', 'sulfur', 'battery', 'processing-unit', 'rocket-fuel', 'electric-engine-unit',
         'military-science-pack', 'chemical-science-pack', 'production-science-pack', 'utility-science-pack',
         'space-science-pack', 'speed-module', 'tungsten-plate', 'holmium-plate', 'carbon-fiber', 'supercapacitor',
         'quantum-processor', 'superconductor', 'lithium-plate', 'metallurgic-science-pack',
         'electromagnetic-science-pack', 'agricultural-science-pack', 'cryogenic-science-pack',
         'promethium-science-pack', 'raw-fish']


def goods_list(entries):
    return ', '.join('{ "%s", %s }' % (g['name'], repr(g['count'])) for g in entries)


def snapshot(label, path, out):
    dump = json.load(open(path))
    values, stacks = dump['values'], dump['stack']
    recipes = sorted((r for r in dump['recipes'] if r['name'] in RECIPES), key=lambda r: r['name'])
    goods = set(name for name in EXTRA if 'item/' + name in values)
    for recipe in recipes:
        for entry in recipe['ingredients'] + recipe['products']:
            goods.add(entry['name'])
    out.append('  %s = {' % label)
    out.append('    values = {')
    out.extend('      ["%s"] = %s,' % (name, repr(round(values['item/' + name], 6))) for name in sorted(goods))
    out.append('    },')
    out.append('    stack_sizes = {')
    out.extend('      ["%s"] = %d,' % (name, stacks[name]) for name in sorted(goods))
    out.append('    },')
    out.append('    recipes = {')
    for recipe in recipes:
        out.append('      { name = "%s", energy = %s,' % (recipe['name'], repr(recipe['energy'])))
        out.append('        ingredients = { %s },' % goods_list(recipe['ingredients']))
        out.append('        products = { %s } },' % goods_list(recipe['products']))
    out.append('    },')
    out.append('  },')


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    out = ['-- Base values, stack sizes and incoming-contract recipes of Factorio 2.1.24 as the mod computes them',
           '-- (storage.base_values at multiplier 1), for the balance simulation (docs/balance.md). A snapshot:',
           '-- regenerate it as docs/balance.md says when the valuation (docs/pricing.md) or the game changes.',
           '-- luacheck: ignore 631 (generated data: recipe lines are long)',
           'return {']
    snapshot('vanilla', sys.argv[1], out)
    snapshot('space_age', sys.argv[2], out)
    out.append('}')
    print('\n'.join(out))


if __name__ == '__main__':
    main()
