-- A small PNG reader for the graphics spec: 8-bit RGBA, non-interlaced, as the render pipeline
-- writes them. Inflates the image data (RFC 1951, after puff by Mark Adler) and undoes the row
-- filters, so the spec can look at actual pixels without Blender or a zlib binding.
-- luacheck: read globals io
local png = {}

local LENGTH_BASE = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115,
  131, 163, 195, 227, 258 }
local LENGTH_EXTRA = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DISTANCE_BASE = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537,
  2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577 }
local DISTANCE_EXTRA = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12,
  13, 13 }
local CODE_LENGTH_ORDER = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }

-- Canonical Huffman table from code lengths (lengths[0..n-1]).
local function huffman(lengths, n)
  local count, offsets, symbols = {}, {}, {}
  for length = 0, 15 do count[length] = 0 end
  for symbol = 0, n - 1 do count[lengths[symbol]] = count[lengths[symbol]] + 1 end
  offsets[1] = 0
  for length = 1, 14 do offsets[length + 1] = offsets[length] + count[length] end
  for symbol = 0, n - 1 do
    local length = lengths[symbol]
    if length ~= 0 then
      symbols[offsets[length]] = symbol
      offsets[length] = offsets[length] + 1
    end
  end
  return { count = count, symbols = symbols }
end

local function inflate(data)
  local position, buffer, buffered = 3, 0, 0 -- skip the 2-byte zlib header
  local out, size = {}, 0

  local function bits(n)
    while buffered < n do
      buffer = buffer + data:byte(position) * 2 ^ buffered
      position = position + 1
      buffered = buffered + 8
    end
    local value = buffer % 2 ^ n
    buffer = (buffer - value) / 2 ^ n
    buffered = buffered - n
    return value
  end

  local function decode(table_)
    local code, first, index = 0, 0, 0
    for length = 1, 15 do
      code = code + bits(1)
      local count = table_.count[length]
      if code - count < first then return table_.symbols[index + code - first] end
      index = index + count
      first = (first + count) * 2
      code = code * 2
    end
    error("invalid Huffman code")
  end

  local function codes(literals, distances)
    while true do
      local symbol = decode(literals)
      if symbol < 256 then
        size = size + 1
        out[size] = symbol
      elseif symbol == 256 then
        return
      else
        local index = symbol - 256
        local length = LENGTH_BASE[index] + bits(LENGTH_EXTRA[index])
        local slot = decode(distances) + 1
        local distance = DISTANCE_BASE[slot] + bits(DISTANCE_EXTRA[slot])
        for _ = 1, length do
          size = size + 1
          out[size] = out[size - distance]
        end
      end
    end
  end

  local fixed_literals, fixed_distances
  repeat
    local last = bits(1)
    local kind = bits(2)
    if kind == 0 then
      buffer, buffered = 0, 0
      local length = data:byte(position) + data:byte(position + 1) * 256
      position = position + 4
      for i = 0, length - 1 do
        size = size + 1
        out[size] = data:byte(position + i)
      end
      position = position + length
    elseif kind == 1 then
      if not fixed_literals then
        local lengths = {}
        for symbol = 0, 287 do
          lengths[symbol] = symbol < 144 and 8 or symbol < 256 and 9 or symbol < 280 and 7 or 8
        end
        fixed_literals = huffman(lengths, 288)
        local distance_lengths = {}
        for symbol = 0, 29 do distance_lengths[symbol] = 5 end
        fixed_distances = huffman(distance_lengths, 30)
      end
      codes(fixed_literals, fixed_distances)
    elseif kind == 2 then
      local literal_count, distance_count, code_count = bits(5) + 257, bits(5) + 1, bits(4) + 4
      local code_lengths = {}
      for i = 0, 18 do code_lengths[i] = 0 end
      for i = 1, code_count do code_lengths[CODE_LENGTH_ORDER[i]] = bits(3) end
      local code_table = huffman(code_lengths, 19)
      local lengths, index = {}, 0
      while index < literal_count + distance_count do
        local symbol = decode(code_table)
        if symbol < 16 then
          lengths[index] = symbol
          index = index + 1
        else
          local value, repeat_count = 0
          if symbol == 16 then
            value, repeat_count = lengths[index - 1], 3 + bits(2)
          elseif symbol == 17 then
            repeat_count = 3 + bits(3)
          else
            repeat_count = 11 + bits(7)
          end
          for _ = 1, repeat_count do
            lengths[index] = value
            index = index + 1
          end
        end
      end
      local distance_lengths = {}
      for i = 0, distance_count - 1 do distance_lengths[i] = lengths[literal_count + i] end
      codes(huffman(lengths, literal_count), huffman(distance_lengths, distance_count))
    else
      error("invalid deflate block type")
    end
  until last == 1
  return out
end

local function u32(text, offset)
  local a, b, c, d = text:byte(offset, offset + 3)
  return ((a * 256 + b) * 256 + c) * 256 + d
end

-- Width and height from the IHDR chunk, or nil when the file is missing or not a PNG.
function png.size(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local header = file:read(24)
  file:close()
  if not header or #header < 24 or header:sub(1, 8) ~= "\137PNG\r\n\26\n" or header:sub(13, 16) ~= "IHDR" then
    return nil
  end
  return u32(header, 17), u32(header, 21)
end

-- Decodes an RGBA PNG: returns width, height and alpha(x, y) (0-based, top-left origin, 0-255).
function png.read(path)
  local file = assert(io.open(path, "rb"))
  local content = file:read("*a")
  file:close()
  local width, height = u32(content, 17), u32(content, 21)
  assert(content:byte(25) == 8 and content:byte(26) == 6 and content:byte(29) == 0,
    path .. ": not an 8-bit RGBA non-interlaced PNG")
  local chunks, position = {}, 9
  while position <= #content do
    local length = u32(content, position)
    if content:sub(position + 4, position + 7) == "IDAT" then
      chunks[#chunks + 1] = content:sub(position + 8, position + 7 + length)
    end
    position = position + 12 + length
  end
  local raw = inflate(table.concat(chunks))
  local stride = width * 4
  local rows, previous = {}, {}
  for x = 1, stride do previous[x] = 0 end
  for y = 0, height - 1 do
    local base = y * (stride + 1) + 1
    local filter, row = raw[base], {}
    for x = 1, stride do
      local value = raw[base + x]
      local left = x > 4 and row[x - 4] or 0
      local up = previous[x]
      if filter == 1 then
        value = value + left
      elseif filter == 2 then
        value = value + up
      elseif filter == 3 then
        value = value + math.floor((left + up) / 2)
      elseif filter == 4 then
        local up_left = x > 4 and previous[x - 4] or 0
        local p = left + up - up_left
        local pa, pb, pc = math.abs(p - left), math.abs(p - up), math.abs(p - up_left)
        value = value + ((pa <= pb and pa <= pc) and left or (pb <= pc and up or up_left))
      end
      row[x] = value % 256
    end
    rows[y] = row
    previous = row
  end
  return width, height, function(x, y) return rows[y][x * 4 + 4] end
end

return png
