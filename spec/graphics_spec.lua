-- The rendered graphics (#48): every file the prototypes reference exists, has the size its sprite
-- description declares (a missing or mis-sized file stops the game at load), icons carry their four
-- mipmaps, and nothing unreferenced ships under graphics/. Reads the files from the repository root,
-- where busted runs.
-- luacheck: read globals io
local lfs = require("lfs")
local sprites = require("prototypes.sprites")

local MOD_PREFIX = "__galactic-bazaar__/"
local ICON_SIZE = 64
local ICON_MIPMAPS = 4

-- Width and height of a PNG file, read from its IHDR chunk; nil if it is not a PNG.
local function png_size(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local header = file:read(24)
  file:close()
  if not header or #header < 24 or header:sub(1, 8) ~= "\137PNG\r\n\26\n" or header:sub(13, 16) ~= "IHDR" then
    return nil
  end
  local function u32(offset)
    local a, b, c, d = header:byte(offset, offset + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
  end
  return u32(17), u32(21)
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
          local width, height = png_size(local_path(sprite.filename))
          assert.is_not_nil(width, sprite.filename .. " is missing or not a PNG")
          local frames = sprite.frame_count or 1
          local per_line = sprite.line_length or 1
          assert.are.equal(sprite.width * math.min(frames, per_line), width)
          assert.are.equal(sprite.height * math.ceil(frames / per_line), height)
          assert.is_true(sprite.width <= 4096 and sprite.height <= 4096)
        end)
      end

      it("has a 64 px icon with four mipmaps", function()
        assert.are.equal(ICON_SIZE, spec.icon.icon_size)
        local width, height = png_size(local_path(spec.icon.filename))
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
