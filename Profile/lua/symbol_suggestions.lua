-- Pinyin names and exact English Greek names offer symbols from slot two.
-- Keep ordinary ranking except for named anchors and catalog keywords.
local fuzzy = require("academic_fuzzy")
local M = {}

-- This profile has one punctuation mode. Reject stale saved/app overrides
-- as well as explicit attempts to enable Rime's automatic width conversion.
local processor = {}
function processor.init(env)
  local ctx = env.engine.context
  ctx:set_option("full_shape", false)
  env.width_guard = ctx.option_update_notifier:connect(function(context, name)
    if name == "full_shape" and context:get_option(name) then context:set_option(name, false) end
  end)
end
function processor.fini(env)
  env.width_guard:disconnect()
end
function processor.func()
  return 2
end
M.processor = processor

local weekdays = {"星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"}
local function weekday()
  return weekdays[tonumber(os.date("%w")) + 1]
end

local entries = {
  {"ri qi", function() return os.date("%Y-%m-%d") end, "日期"},
  {"xing qi", weekday, "星期"},
  {"shi jian", function() return os.date("%H:%M:%S") end},
  {"mei yuan", "$"},
  {"ren min bi", "￥"},
  {"ou yuan", "€"},
  {"ying bang", "£"},
  {"ri yuan", "¥"},
  {"han yuan", "₩"},
  {"xin bi", "S$"},
  {"jia", "+", group = "math"},
  {"jian", "−", group = "math"},
  {"cheng", "×", group = "math"},
  {"chu", "÷", group = "math"},
  {"deng yu", "=", group = "math"},
  {"bu deng yu", "≠", group = "math"},
  {"yue deng yu", "≈", group = "math"},
  {"xiao yu deng yu", "≤", group = "math"},
  {"da yu deng yu", "≥", group = "math"},
  {"zheng fu hao", "±", group = "math"},
  {"bai fen hao", "%", group = "math"},
  {"wu qiong da", "∞", group = "math"},
  {"yuan zhou lv", "π", group = "math"},
  {"du", "°", "度", group = "math"},
  {"she shi du", "℃"},
  {"hua shi du", "℉"},
  {"alpha", "α", exact = true, group = "greek"},
  {"beta", "β", exact = true, group = "greek"},
  {"gamma", "γ", exact = true, group = "greek"},
  {"delta", {"δ", "Δ"}, exact = true, group = "greek"},
  {"epsilon", "ε", exact = true, group = "greek"},
  {"theta", {"θ", "Θ"}, exact = true, group = "greek"},
  {"lambda", {"λ", "Λ"}, exact = true, group = "greek"},
  {"mu", "μ", exact = true, group = "greek"},
  {"sigma", {"σ", "Σ"}, exact = true, group = "greek"},
  {"phi", {"φ", "Φ"}, exact = true, group = "greek"},
  {"omega", {"ω", "Ω"}, exact = true, group = "greek"},
  {"nabla", "∇", exact = true, group = "math"},
  {"ping fang mi", "m²"},
  {"li fang mi", "m³"},
  {"wei mi", "μm"},
  {"jian tou", "→", group = "math"},
  {"zuo jian tou", "←", group = "math"},
  {"shang jian tou", "↑", group = "math"},
  {"xia jian tou", "↓", group = "math"},
  {"gou hao", "✓"},
  {"cha hao", "✗"},
  {"ban quan", "©"},
  {"shang biao", "™"},
  {"zhu ce shang biao", "®"},
}

-- Build browsing menus from existing entries so trigger names and available
-- symbols stay consistent. A catalog does not introduce another symbol set.
local function catalog(name)
  local result = {name, {}, name, exact = true, labels = {}}
  for _, entry in ipairs(entries) do
    if entry.group == name then
      local choices = type(entry[2]) == "table" and entry[2] or {entry[2]}
      for _, text in ipairs(choices) do
        if not result.labels[text] then
          result[2][#result[2]+1] = text
          result.labels[text] = entry[1]:gsub(" ", "")
        end
      end
    end
  end
  return result
end
entries[#entries+1] = catalog("greek")
entries[#entries+1] = catalog("math")

for _, entry in ipairs(entries) do
  entry.pattern = entry.exact and ("^" .. entry[1] .. "$") or fuzzy.pattern(entry[1])
end

local function matching(input)
  for _, entry in ipairs(entries) do
    if input:match(entry.pattern) then return entry end
  end
end

function M.tags_match(segment, env)
  local ctx = env.engine.context
  return not ctx:get_option("ascii_mode") and segment:has_tag("abc")
      and segment.start == 0 and segment._end == #ctx.input
      and matching(ctx.input) ~= nil
end

function M.func(translation, env)
  local input = env.engine.context.input
  local entry = matching(input)
  local value = entry and entry[2]
  local generated = type(value) == "function" and value() or value
  if not generated then
    for candidate in translation:iter() do yield(candidate) end
    return
  end
  local choices = type(generated) == "table" and generated or {generated}
  local generated_text = {}
  for _, text in ipairs(choices) do generated_text[text] = true end
  local offered, anchor = false, entry[3]
  local function offer(candidate)
    local full = candidate.start == 0 and candidate._end == #input
    if not full or (not generated_text[candidate.text] and (not offered or candidate.text ~= anchor)) then
      yield(candidate)
      if not offered then
        -- A plain candidate has no native user-dictionary entry. Its distinct
        -- type also excludes it from the custom Chinese learning rule.
        for _, text in ipairs(choices) do
          yield(Candidate("symbol_suggestion", 0, #input, text,
              entry.labels and entry.labels[text] or ""))
        end
        offered = true
      end
    end
  end
  if anchor then
    local buffer, primary = {}, nil
    for candidate in translation:iter() do
      if candidate.text == anchor and candidate.start == 0 and candidate._end == #input then
        primary = candidate
        break
      end
      buffer[#buffer+1] = candidate
      if #buffer >= 64 then break end
    end
    -- Reuse the genuine Chinese candidate whenever available so its native
    -- learning remains intact. The fallback only supplies a missing label.
    offer(primary or Candidate("symbol_label", 0, #input, anchor, ""))
    for _, candidate in ipairs(buffer) do offer(candidate) end
  end
  for candidate in translation:iter() do offer(candidate) end
end

return M
