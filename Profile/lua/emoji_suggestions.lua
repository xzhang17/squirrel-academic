-- Join emoji to a Chinese word actually offered by Rime. The cheap spelling
-- key below is only a prefilter; the syllable patterns make the final decision.
local M = {}
local index, sessions = nil, 0

local function key(pinyin)
  return (pinyin:gsub("[ 'hg]", ""))
end

local function reading(pinyin)
  local fuzzy = {}
  for syllable in pinyin:gmatch("[a-z]+") do
    -- s/sh, c/ch and z/zh are separate pairs. Only syllable-final n/ng varies.
    local f = syllable:gsub("^([scz])h?", "%1h?"):gsub("([aeio])ng?$", "%1ng?")
    fuzzy[#fuzzy+1] = f
  end
  return {exact = "^" .. pinyin:gsub(" ", "'?") .. "$", fuzzy = "^" .. table.concat(fuzzy, "'?") .. "$"}
end

function M.init(env)
  env.page_size = math.max(3, env.engine.schema.config:get_int("menu/page_size") or 7)
  sessions = sessions + 1
  if index then return end
  index = {words = {}, keys = {}}
  local file = io.open(rime_api.get_user_data_dir() .. "/opencc/emoji_candidates.txt", "r")
  if not file then return end
  for line in file:lines() do
    local pinyin, word, values = line:match("^([a-z ]+)\t([^\t]+)\t([^\t]+)$")
    if pinyin then
      local entry = index.words[word]
      if not entry then
        entry = {glyphs = {}, readings = {}}
        for glyph in values:gmatch("%S+") do entry.glyphs[#entry.glyphs+1] = glyph end
        index.words[word] = entry
      end
      entry.readings[#entry.readings+1] = reading(pinyin)
      index.keys[key(pinyin)] = true
    end
  end
  file:close()
end

function M.fini()
  sessions = sessions - 1
  if sessions == 0 then index = nil end
end

function M.tags_match(seg, env)
  local ctx = env.engine.context
  local input = ctx.input
  return index ~= nil and seg:has_tag("abc") and seg.start == 0 and seg._end == #input
      and not ctx:get_option("ascii_mode") and input:match("^[a-z][a-z']*$") ~= nil
      and index.keys[key(input)] == true
end

local function matches(cand, input, leading)
  if cand.start ~= 0 or cand._end ~= #input then return nil end
  local entry = index.words[cand.text]
  if not entry then return nil end
  for _, form in ipairs(entry.readings) do
    if input:match(leading and form.fuzzy or form.exact) then return entry.glyphs end
  end
end

function M.func(translation, env)
  local input = env.engine.context.input
  local width, quota = env.page_size, 2
  local text_slots = width - quota
  local seen, visible = {}, 0
  local search, alternatives = true, true
  local glyphs, next_glyph = nil, 1

  local function offer(slots)
    while slots > 0 and next_glyph <= #glyphs do
      local g = glyphs[next_glyph]
      next_glyph = next_glyph + 1
      if not seen[g] then
        seen[g] = true
        visible = visible + 1
        slots = slots - 1
        yield(Candidate("emoji_suggestion", 0, #input, g, ""))
      end
    end
    if next_glyph > #glyphs then glyphs = nil end
  end

  for cand in translation:iter() do
    if (search or glyphs) and not seen[cand.text] then
      local kind = cand:get_genuine().type
      local reserved = kind == "user_table" or kind == "academic_first" or kind == "english_first"
      if search then
        if visible == 0 then alternatives = not reserved end
        if visible == 0 or alternatives then glyphs = matches(cand, input, visible == 0) end
        search = not glyphs and alternatives and visible + 1 < text_slots
      elseif glyphs and not reserved and visible % width >= text_slots then
        offer(width - visible % width)
      end
      seen[cand.text] = true
      visible = visible + 1
    end
    yield(cand)
  end
  -- A short page puts all its text first. Never pad it or create a page just
  -- to reserve space for emoji.
  if glyphs then offer(math.min(quota, width - visible % width)) end
end

return M
