-- Reorder actual candidates only. The regular filter has already applied
-- exact private phrases and the six shared exceptions. Personal pins run last.
local preferences = require("academic_preferences")
local M = {}
local index, sessions = nil, 0

function M.init(env)
  env.page_size = env.engine.schema.config:get_int("menu/page_size") or 7
  sessions = sessions + 1
  if index then return end
  index = {english = {}, rare = {}, common = {}, links = {}, syllables = {}}
  local file = io.open(rime_api.get_user_data_dir() .. "/en_dicts/english_evidence.txt", "r")
  if not file then return end
  for line in file:lines() do
    local kind, key, value = line:match("^([ERCBS])\t([^\t]+)\t?(.*)$")
    if kind == "E" then index.english[key] = "\t" .. value .. "\t"
    elseif kind == "R" then index.rare[key .. "\t" .. value] = true
    elseif kind == "C" then index.common[key] = true
    elseif kind == "B" then index.links[key] = true
    elseif kind == "S" then index.syllables[key] = true end
  end
  file:close()
end

function M.fini()
  sessions = sessions - 1
  if sessions == 0 then index = nil end
end

-- Can a fully spelled composition be read as a sequence of familiar Chinese
-- words? Test word boundaries instead of rejecting a sentence because Rime
-- assembled it. Only short, ambiguous candidate pages need this calculation.
local function familiar_chunks(text, boundaries)
  local reachable = {[1] = true}
  for i = 1, #boundaries - 1 do
    local pair = i > 1 and text:sub(boundaries[i-1], boundaries[i+1] - 1)
    -- Frequent characters alone do not make 蓝 + 瓜葛 a plausible phrase.
    if reachable[i] and (not pair or index.common[pair] or index.links[pair]) then
      for j = i + 1, math.min(#boundaries, i + 8) do
        if index.common[text:sub(boundaries[i], boundaries[j] - 1)] then reachable[j] = true end
      end
    end
  end
  return reachable[#boundaries]
end

local function weak_chinese(cand, input)
  local kind, text = cand:get_genuine().type, cand.text
  if cand.start ~= 0 or (kind ~= "sentence" and kind ~= "phrase") or index.common[text]
      or preferences.is_curated(text) ~= false then return false end
  local boundaries = {}
  for pos, cp in utf8.codes(text) do
    if not ((cp >= 0x3400 and cp <= 0x9fff) or (cp >= 0x20000 and cp <= 0x323af)) then return false end
    boundaries[#boundaries + 1] = pos
  end
  if #boundaries < 3 then return false end
  if kind == "phrase" then
    return cand._end == #input and index.rare[input .. "\t" .. text] or false
  end
  if cand._end < #input then return true end
  for syllable in (cand.preedit or ""):gmatch("[^ '%s]+") do
    if not index.syllables[syllable] then return true end
  end
  boundaries[#boundaries + 1] = #text + 1
  return not familiar_chunks(text, boundaries)
end

-- Skip the Lua translation pass entirely on ordinary pinyin, word prefixes,
-- and already confirmed segments.
function M.tags_match(seg, env)
  local ctx = env.engine.context
  local input = ctx.input
  return index ~= nil and index.english[input] ~= nil and seg.start == 0 and seg._end == #input
      and seg:has_tag("abc") and not ctx:get_option("ascii_mode")
end

function M.func(translation, env)
  local input = env.engine.context.input
  local forms = index and index.english[input]
  if not forms then
    for cand in translation:iter() do yield(cand) end
    return
  end

  local page, exact = {}, nil
  local function release(promote)
    if promote and exact then yield(page[exact]) end
    for i, cand in ipairs(page) do
      if not promote or i ~= exact then yield(cand) end
    end
    page = nil
  end
  for cand in translation:iter() do
    if not page then
      yield(cand)
    else
      page[#page + 1] = cand
      if #page == 1 and not weak_chinese(cand, input) then
        release(false)  -- includes explicit choices and existing English-first results
      elseif cand.start == 0 and cand._end == #input then
        if cand:get_genuine().type == "user_table" and forms:find("\t" .. cand.text .. "\t", 1, true) then
          exact = exact or #page
        elseif #page > 1 and not (cand:get_genuine().type == "user_table" and cand.text:match("^[%w%p ]+$"))
            and not weak_chinese(cand, input) then
          release(false)  -- a real Chinese alternative on the page protects Chinese priority
        end
      end
      if page and #page == env.page_size then release(true) end
    end
  end
  if page then release(true) end
end

return M
