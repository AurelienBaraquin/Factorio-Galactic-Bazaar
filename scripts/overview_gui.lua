-- The Overview tab of the Galactic Bazaar window (#105, scripts/bazaar_gui.lua): the force's account
-- (balance, overdraft used and left, interest and the next charge), its reputation and what it
-- changes (freight fees, contract sizes, loan rate and cap), its solvency (insolvency, bankruptcy,
-- credit ban and debt) and a summary of its open contracts, leases and loans. The figures come from
-- scripts/core/overview.lua; every line has a tooltip that explains it. Rows are built once and
-- updated in place. Read only: it works anywhere.
local bazaar_gui = require("scripts.bazaar_gui")
local catalog = require("scripts.core.catalog")
local insolvency = require("scripts.core.insolvency")
local loans = require("scripts.core.loans")
local overview = require("scripts.core.overview")
local reputation = require("scripts.core.reputation")

local overview_gui = {}

-- Contract kinds summed on each commitments line.
local GROUPS = {
  contracts = { "incoming", "rental" },
  leases = { "concession", "outsourcing" },
}

local WARNING = { r = 1, g = 0.4, b = 0.3 }
local NORMAL = { r = 1, g = 1, b = 1 }

-- Sections and their lines, in order; each line's name and tooltip are the locale keys
-- `gb-overview.<line>` and `gb-overview.<line>-tooltip`.
local SECTIONS = {
  { name = "account", lines = { "balance", "overdraft", "interest", "next-interest" } },
  { name = "reputation", lines = { "score", "fees", "contract-size", "loan-terms" } },
  { name = "solvency", lines = { "state", "credit" } },
  { name = "commitments", lines = { "offers", "contracts", "leases", "loans", "next-due" } },
}

local function percent(share)
  return string.format("%.4g", share * 100)
end

local function credits(amount)
  return catalog.format_credits(amount)
end

-- Parameters of the tooltips that state a rule's figures, by line.
local function tooltip_parameters()
  local lowest_size = math.ceil((reputation.MIN_SIZE - 1) / reputation.SIZE_STEP)
  return {
    fees = { string.format("%.4g", reputation.FEE_STEP), string.format("%.4g", reputation.fee_factor(reputation.MAX)),
      reputation.MAX, string.format("%.4g", reputation.fee_factor(reputation.MIN)), reputation.MIN },
    ["contract-size"] = { string.format("%.4g", reputation.SIZE_STEP), percent(reputation.MIN_SIZE), lowest_size,
      string.format("%.4g", reputation.contract_scale(reputation.MAX)), reputation.MAX },
    ["loan-terms"] = { percent(loans.BASE_RATE), percent(loans.RATE_STEP), credits(loans.DEBT_CAP) },
  }
end

local function build(_, container, view)
  local elements = { values = {} }
  local body = container.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  local parameters = tooltip_parameters()
  for _, section in ipairs(SECTIONS) do
    body.add({ type = "label", style = "caption_label", caption = { "gb-overview.section-" .. section.name } })
    local list = body.add({ type = "table", column_count = 2 })
    for _, line in ipairs(section.lines) do
      local name = list.add({ type = "label", caption = { "gb-overview." .. line } })
      name.style.width = 200
      elements.values[line] = list.add({ type = "label" })
      elements.values[line].tooltip = { "gb-overview." .. line .. "-tooltip", table.unpack(parameters[line] or {}) }
      name.tooltip = elements.values[line].tooltip
    end
  end
  view.elements = elements
end

local function refresh_account(values, figures)
  values.balance.caption = { "gb-overview.credits", credits(figures.balance) }
  values.overdraft.caption = { "gb-overview.overdraft-value", credits(figures.overdraft_used),
    credits(figures.overdraft_limit), credits(figures.overdraft_left) }
  values.interest.caption = { "gb-overview.interest-value", percent(figures.interest_rate),
    figures.interest_ticks / 3600 }
  values["next-interest"].caption = figures.interest_due > 0
    and { "gb-overview.next-interest-value", credits(figures.interest_due),
      catalog.format_duration(figures.interest_in) }
    or { "gb-overview.next-interest-none", catalog.format_duration(figures.interest_in) }
end

local function refresh_reputation(values, figures)
  values.score.caption = { "gb-overview.score-value", figures.reputation, reputation.MIN, reputation.MAX }
  values.fees.caption = { "gb-overview.percent", percent(figures.fee_factor) }
  values["contract-size"].caption = { "gb-overview.percent", percent(figures.contract_scale) }
  values["loan-terms"].caption = { "gb-overview.loan-terms-value", percent(figures.loan_rate),
    loans.TERM_TICKS / 3600, credits(figures.loan_cap) }
end

local function refresh_solvency(values, solvency)
  local state = values.state
  if solvency.name == "insolvent" then
    state.caption = solvency.recovering_left
      and { "gb-overview.recovering", catalog.format_duration(solvency.recovering_left),
        catalog.format_duration(solvency.grace_left) }
      or { "gb-overview.insolvent", catalog.format_duration(solvency.grace_left),
        credits(solvency.recovery_balance), insolvency.RECOVERY_TICKS / 3600 }
  else
    state.caption = { "gb-overview.solvent", solvency.bankruptcies }
  end
  state.style.font_color = solvency.name == "insolvent" and WARNING or NORMAL
  local credit = values.credit
  if not solvency.ban_left then
    credit.caption = { "gb-overview.credit-open" }
  elseif solvency.ban_left > 0 and solvency.debt > 0 then
    credit.caption = { "gb-gui.credit-ban", catalog.format_duration(solvency.ban_left), credits(solvency.debt) }
  elseif solvency.ban_left > 0 then
    credit.caption = { "gb-gui.credit-ban-time", catalog.format_duration(solvency.ban_left) }
  else
    credit.caption = { "gb-gui.credit-ban-debt", credits(solvency.debt) }
  end
  credit.style.font_color = solvency.ban_left and WARNING or NORMAL
end

-- Active contracts of the kinds of a group.
local function active_count(commitments, kinds)
  local active = 0
  for _, kind in ipairs(kinds) do
    local count = commitments[kind]
    if count then active = active + count.active end
  end
  return active
end

local function refresh_commitments(values, figures)
  local offers = 0
  for _, count in pairs(figures.commitments) do offers = offers + count.offered end
  values.offers.caption = tostring(offers)
  values.contracts.caption = tostring(active_count(figures.commitments, GROUPS.contracts))
  values.leases.caption = tostring(active_count(figures.commitments, GROUPS.leases))
  local loans_active = active_count(figures.commitments, { "loan" })
  values.loans.caption = figures.arrears > 0
    and { "gb-overview.loans-arrears", loans_active, credits(figures.loan_debt), credits(figures.arrears) }
    or { "gb-overview.loans-value", loans_active, credits(figures.loan_debt) }
  values["next-due"].caption = figures.next_due
    and { "gb-overview.next-due-value", catalog.format_duration(figures.next_due.ticks),
      { "gb-notify.kind-" .. figures.next_due.kind } }
    or { "gb-overview.next-due-none" }
end

local function refresh(player, view)
  local figures = overview.figures(storage.forces[player.force_index], game.tick)
  local values = view.elements.values
  refresh_account(values, figures)
  refresh_reputation(values, figures)
  refresh_solvency(values, figures.solvency)
  refresh_commitments(values, figures)
end

bazaar_gui.register_tab({ name = "overview", order = 10, build = build, refresh = refresh })

return overview_gui
