-- Circuit signal values for market data (ADR-0010). Pure Lua.
--
-- Circuit signals are 32-bit integers. Prices are emitted in milli-credits (a price of 1.32 credits
-- is 1320), so that cheap goods such as water (0.001 credit) still read as a positive number; the
-- balance is emitted in whole credits. Values beyond the int32 range are clamped to it.
local signals = {}

signals.INT32_MAX = 2147483647
signals.INT32_MIN = -2147483648
-- Milli-credits per credit in a price signal.
signals.PRICE_SCALE = 1000

--- `n` rounded to the nearest integer and clamped to the int32 range.
function signals.to_int32(n)
  if n ~= n then return 0 end
  n = math.floor(n + 0.5)
  if n > signals.INT32_MAX then return signals.INT32_MAX end
  if n < signals.INT32_MIN then return signals.INT32_MIN end
  return n
end

--- Signal value of a price in credits per unit.
function signals.price(credits)
  return signals.to_int32(credits * signals.PRICE_SCALE)
end

--- Signal value of a balance in credits.
function signals.balance(credits)
  return signals.to_int32(credits)
end

return signals
