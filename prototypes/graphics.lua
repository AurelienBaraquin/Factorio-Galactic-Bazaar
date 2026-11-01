-- The mod's own rendered graphics (docs/graphics-pipeline.md): turns the descriptions that
-- tools/graphics/render.py generates in prototypes/sprites.lua into Factorio sprite, animation and
-- icon tables. Every layer is a high-resolution render (64 px per tile) drawn at scale 0.5.
local sprites = require("prototypes.sprites")

local graphics = {}

local function described(name)
  return sprites[name] or error("no rendered graphics for " .. name .. ": run tools/graphics/render.py")
end

local function layer(spec, animated, shadow)
  local result = {
    filename = spec.filename,
    width = spec.width,
    height = spec.height,
    shift = { spec.shift[1], spec.shift[2] },
    scale = 0.5,
    priority = "high",
    draw_as_shadow = shadow or nil,
  }
  if animated then
    result.frame_count = spec.frame_count
    result.line_length = spec.line_length
    result.animation_speed = spec.animation_speed
    result.run_mode = spec.run_mode
  end
  return result
end

-- A still picture: the building and its shadow.
function graphics.sprite(name)
  local spec = described(name)
  return { layers = { layer(spec.main, false, false), layer(spec.shadow, false, true) } }
end

-- An animation: the building's frames and its shadow's.
function graphics.animation(name)
  local spec = described(name)
  return { layers = { layer(spec.main, true, false), layer(spec.shadow, true, true) } }
end

-- How far the rendered building rises above its selection box, in tiles (for entity tooltips).
function graphics.vertical_extension(name)
  return described(name).drawing_box_vertical_extension
end

-- The icon, with its mipmaps in the same file (the game infers their count from its width).
function graphics.icons(name)
  local icon = described(name).icon
  return { { icon = icon.filename, icon_size = icon.icon_size } }
end

return graphics
