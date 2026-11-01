-- The rendered graphics (#48): every file the prototypes reference exists, has the size its sprite
-- description declares (a missing or mis-sized file stops the game at load), no frame was cut off by
-- the render canvas (each frame keeps a transparent border), icons carry their four mipmaps, and
-- nothing unreferenced ships under graphics/. Reads the files from the repository root, where busted
-- runs.
-- luacheck: read globals io
local lfs = require("lfs")
local png = require("spec.support.png")
local sprites = require("prototypes.sprites")

local MOD_PREFIX = "__galactic-bazaar__/"
local ICON_SIZE = 64
local ICON_MIPMAPS = 4

-- Frames in the sheet, and frames per row (line_length 0 or absent: all in one row).
local function layout(sprite)
  local frames = sprite.frame_count or 1
  local per_line = sprite.line_length or 0
  if per_line == 0 then per_line = frames end
  return frames, per_line
end

-- The first frame whose outermost rows or columns are not fully transparent, or nil.
local function cut_frame(path, sprite)
  local _, _, alpha = png.read(path)
  local frames, per_line = layout(sprite)
  local w, h = sprite.width, sprite.height
  for index = 0, frames - 1 do
    local x0, y0 = (index % per_line) * w, math.floor(index / per_line) * h
    for x = x0, x0 + w - 1 do
      if alpha(x, y0) ~= 0 or alpha(x, y0 + h - 1) ~= 0 then return index + 1 end
    end
    for y = y0, y0 + h - 1 do
      if alpha(x0, y) ~= 0 or alpha(x0 + w - 1, y) ~= 0 then return index + 1 end
    end
  end
  return nil
end

local function local_path(filename)
  assert.are.equal(MOD_PREFIX, filename:sub(1, #MOD_PREFIX), filename .. " is not a file of this mod")
  return filename:sub(#MOD_PREFIX + 1)
end

-- Every "__galactic-bazaar__/..." path named by a data-stage file.
local function referenced_in_prototypes()
  local found = {}
  for entry in lfs.dir("prototypes") do
    if entry:match("%.lua$") then
      local source = assert(io.open("prototypes/" .. entry)):read("*a")
      for path in source:gmatch('"(' .. MOD_PREFIX:gsub("%-", "%%-") .. '[^"]+)"') do found[path] = true end
    end
  end
  return found
end

local function files_under(folder, list)
  for entry in lfs.dir(folder) do
    if entry ~= "." and entry ~= ".." then
      local path = folder .. "/" .. entry
      if lfs.attributes(path, "mode") == "directory" then
        files_under(path, list)
      else
        list[#list + 1] = path
      end
    end
  end
  return list
end

describe("rendered graphics", function()
  it("describe at least one building", function()
    assert.is_not_nil(next(sprites))
  end)

  for name, spec in pairs(sprites) do
    describe(name, function()
      for _, layer in ipairs({ "main", "shadow" }) do
        it("has a " .. layer .. " sheet of the declared size", function()
          local sprite = spec[layer]
          local width, height = png.size(local_path(sprite.filename))
          assert.is_not_nil(width, sprite.filename .. " is missing or not a PNG")
          local frames, per_line = layout(sprite)
          assert.are.equal(sprite.width * math.min(frames, per_line), width)
          assert.are.equal(sprite.height * math.ceil(frames / per_line), height)
          assert.is_true(sprite.width <= 4096 and sprite.height <= 4096)
        end)

        it("has a " .. layer .. " sheet no frame of which is cut off", function()
          local sprite = spec[layer]
          local frame = cut_frame(local_path(sprite.filename), sprite)
          assert.is_nil(frame, sprite.filename .. ": frame " .. tostring(frame) .. " touches its edge")
        end)
      end

      it("has a 64 px icon with four mipmaps", function()
        assert.are.equal(ICON_SIZE, spec.icon.icon_size)
        local width, height = png.size(local_path(spec.icon.filename))
        assert.is_not_nil(width, spec.icon.filename .. " is missing or not a PNG")
        local expected = 0
        for level = 0, ICON_MIPMAPS - 1 do expected = expected + ICON_SIZE / 2 ^ level end
        assert.are.equal(expected, width)
        assert.are.equal(ICON_SIZE, height)
      end)
    end)
  end

  it("references only files that exist", function()
    for path in pairs(referenced_in_prototypes()) do
      local file = io.open(local_path(path), "rb")
      assert.is_not_nil(file, path .. " does not exist")
      file:close()
    end
  end)

  it("ships no graphics file that no sprite description names", function()
    local named = {}
    for _, spec in pairs(sprites) do
      named[local_path(spec.main.filename)] = true
      named[local_path(spec.shadow.filename)] = true
      named[local_path(spec.icon.filename)] = true
    end
    for _, path in ipairs(files_under("graphics", {})) do
      assert.is_true(named[path] == true, path .. " is not named by prototypes/sprites.lua")
    end
  end)
end)
