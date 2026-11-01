-- The locale files (#111): Factorio refuses to load a mod whose .cfg repeats a key, every in-game
-- text ships in English and French, and a key the code names but no locale defines shows as
-- "Unknown key" in game. Reads the files from the repository root, where busted runs.
-- luacheck: read globals io
local lfs = require("lfs")

local LANGUAGES = { "en", "fr" }

-- {[section] = {[key] = text}} of a .cfg file, and the "section.key" entries found twice.
local function parse(path)
  local sections, duplicates, section = {}, {}, ""
  for line in io.lines(path) do
    local header = line:match("^%[([^%]]+)%]%s*$")
    if header then
      section = header
      sections[section] = sections[section] or {}
    else
      local key, text = line:match("^([^#;=][^=]*)=(.*)$")
      if key then
        sections[section] = sections[section] or {}
        if sections[section][key] then duplicates[#duplicates + 1] = section .. "." .. key end
        sections[section][key] = text
      end
    end
  end
  return sections, duplicates
end

-- The parameters a text uses ("__1__", "__2__"...), sorted and without repeats, as one string.
local function placeholders(text)
  local found, list = {}, {}
  for number in text:gmatch("__(%d+)__") do
    if not found[number] then
      found[number] = true
      list[#list + 1] = tonumber(number)
    end
  end
  table.sort(list)
  return table.concat(list, ",")
end

local function read_locale(language)
  local merged, duplicates = {}, {}
  for file in lfs.dir("locale/" .. language) do
    if file:match("%.cfg$") then
      local sections, found = parse("locale/" .. language .. "/" .. file)
      for name, keys in pairs(sections) do
        merged[name] = merged[name] or {}
        for key, text in pairs(keys) do
          if merged[name][key] then found[#found + 1] = name .. "." .. key end
          merged[name][key] = text
        end
      end
      for _, entry in ipairs(found) do duplicates[#duplicates + 1] = entry end
    end
  end
  return merged, duplicates
end

-- Every "section.key" of a locale, sorted.
local function entries(locale)
  local list = {}
  for section, keys in pairs(locale) do
    for key in pairs(keys) do list[#list + 1] = section .. "." .. key end
  end
  table.sort(list)
  return list
end

-- The Lua files shipped with the mod.
local function lua_files()
  local files = { "control.lua", "data.lua", "settings.lua" }
  local function walk(folder)
    for name in lfs.dir(folder) do
      local path = folder .. "/" .. name
      if name:match("%.lua$") then
        files[#files + 1] = path
      elseif name ~= "." and name ~= ".." and lfs.attributes(path, "mode") == "directory" then
        walk(path)
      end
    end
  end
  walk("scripts")
  walk("prototypes")
  return files
end

-- Every string literal "section.key" of the code whose section a locale defines; a literal ending in
-- "-" or "." is the start of a key built at run time and is skipped.
local function literal_keys(locale)
  local found = {}
  for _, path in ipairs(lua_files()) do
    local source = assert(io.open(path)):read("*a")
    for literal in source:gmatch('"([^"\n]*)"') do
      local section, key = literal:match("^([%w%-]+)%.([%w%-]+)$")
      if section and locale[section] and not key:match("%-$") then found[#found + 1] = { path, section, key } end
    end
  end
  return found
end

describe("locale files", function()
  local locales, duplicates = {}, {}
  for _, language in ipairs(LANGUAGES) do locales[language], duplicates[language] = read_locale(language) end

  it("repeat no key, which would stop the mod from loading", function()
    for _, language in ipairs(LANGUAGES) do assert.are.same({}, duplicates[language], language) end
  end)

  it("define the same keys in English and French", function()
    assert.are.same(entries(locales.en), entries(locales.fr))
  end)

  it("use the same parameters (__1__, __2__...) in English and French for each key", function()
    local differ = {}
    for section, keys in pairs(locales.en) do
      for key, text in pairs(keys) do
        local french = locales.fr[section] and locales.fr[section][key]
        if french and placeholders(text) ~= placeholders(french) then
          differ[#differ + 1] = section .. "." .. key
        end
      end
    end
    table.sort(differ)
    assert.are.same({}, differ)
  end)

  it("define every key the code names", function()
    local missing = {}
    for _, use in ipairs(literal_keys(locales.en)) do
      if not locales.en[use[2]][use[3]] then missing[#missing + 1] = use[1] .. ": " .. use[2] .. "." .. use[3] end
    end
    assert.are.same({}, missing)
  end)

  it("name and describe every tips and tricks entry, with and without Space Age and quality", function()
    for _, flags in ipairs({ { space_age = false, quality = false }, { space_age = true, quality = true } }) do
      local defined = {}
      rawset(_G, "mods", flags.space_age and { ["space-age"] = "2.1.24" } or {})
      rawset(_G, "feature_flags", { quality = flags.quality })
      rawset(_G, "data", { extend = function(_, list)
        for _, prototype in ipairs(list) do defined[#defined + 1] = prototype end
      end })
      package.loaded["prototypes.tips_and_tricks"] = nil
      require("prototypes.tips_and_tricks")
      local items = 0
      for _, prototype in ipairs(defined) do
        if prototype.type == "tips-and-tricks-item" then
          items = items + 1
          for _, language in ipairs(LANGUAGES) do
            assert.is_truthy(locales[language]["tips-and-tricks-item-name"][prototype.name], prototype.name)
            assert.is_truthy(locales[language]["tips-and-tricks-item-description"][prototype.name], prototype.name)
          end
        end
      end
      assert.is_true(items > 0)
    end
    rawset(_G, "mods", nil)
    rawset(_G, "feature_flags", nil)
    rawset(_G, "data", nil)
    package.loaded["prototypes.tips_and_tricks"] = nil
  end)

  it("name and describe every technology by its own key (#129)", function()
    local defined = {}
    local items = setmetatable({}, { __index = function() return { icons = {} } end })
    rawset(_G, "data", {
      raw = { item = items },
      extend = function(_, list)
        for _, prototype in ipairs(list) do defined[#defined + 1] = prototype end
      end,
    })
    finally(function()
      rawset(_G, "data", nil)
      package.loaded["prototypes.technologies"] = nil
    end)
    package.loaded["prototypes.technologies"] = nil
    require("prototypes.technologies")
    local wrong = {}
    for _, prototype in ipairs(defined) do
      for _, language in ipairs(LANGUAGES) do
        for _, section in ipairs({ "technology-name", "technology-description" }) do
          if not locales[language][section][prototype.name] then
            wrong[#wrong + 1] = language .. ": " .. section .. "." .. prototype.name
          end
        end
      end
      -- Factorio drops a trailing "-<number>" from a technology's name to find its keys, unless the
      -- prototype names them.
      if prototype.name:match("%-%d+$") then
        local fields = { localised_name = "technology-name", localised_description = "technology-description" }
        for field, section in pairs(fields) do
          local value = prototype[field]
          if not (type(value) == "table" and value[1] == section .. "." .. prototype.name and #value == 1) then
            wrong[#wrong + 1] = prototype.name .. ": " .. field
          end
        end
      end
    end
    assert.is_true(#defined > 0)
    table.sort(wrong)
    assert.are.same({}, wrong)
  end)
end)
