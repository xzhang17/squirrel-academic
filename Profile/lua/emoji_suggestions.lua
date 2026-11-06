-- Join emoji to a Chinese word actually offered by Rime. The cheap spelling
-- key below is only a prefilter; the syllable patterns make the final decision.
local M = {}
local fuzzy = require("zenfire_fuzzy")
local index, sessions = nil, 0

local function key(pinyin)
  return (pinyin:gsub("[ 'hg]", ""))
end

local function reading(pinyin)
  return {exact = "^" .. pinyin:gsub(" ", "'?") .. "$", fuzzy = fuzzy.pattern(pinyin)}
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

local protected_types = {
  user_table = true, mixed_separated = true, zenfire_first = true, zenfire_rank = true, english_first = true,
  symbol_label = true, symbol_suggestion = true,
}

local function protected(cand)
  return protected_types[cand.type] or protected_types[cand:get_genuine().type]
end

function M.func(translation, env)
  local input = env.engine.context.input
  local width, quota = env.page_size, 2
  local text_slots = width - quota
  local seen, visible = {}, 0
  local search, alternatives = true, true
  local glyphs, next_glyph = nil, 1
  local tail, tail_count = {}, 0

  local function emit(cand, fresh)
    if fresh then visible = visible + 1 end
    yield(cand)
  end

  local function offer(slots)
    while slots > 0 and next_glyph <= #glyphs do
      local g = glyphs[next_glyph]
      next_glyph = next_glyph + 1
      if not seen[g] then
        seen[g] = true
        emit(Candidate("emoji_suggestion", 0, #input, g, ""), true)
        slots = slots - 1
      end
    end
    if next_glyph > #glyphs then glyphs = nil end
  end

  -- Wait only for the last two distinct text choices. A full page can share
  -- those slots with emoji; on a short page all text keeps its place.
  local function flush_tail(full)
    local keep = #tail
    if full then
      keep = 0
      for i, row in ipairs(tail) do if row.protected then keep = i end end
    end
    for i = 1, keep do emit(tail[i].cand, tail[i].fresh) end
    if full and visible % width > 0 then offer(width - visible % width) end
    for i = keep + 1, #tail do emit(tail[i].cand, tail[i].fresh) end
    tail, tail_count = {}, 0
  end

  for cand in translation:iter() do
    if not search and not glyphs then
      yield(cand)
    else
      local fresh = not seen[cand.text]
      seen[cand.text] = true
      if search then
        if fresh then
          if visible == 0 then alternatives = not protected(cand) end
          if visible == 0 or alternatives then glyphs = matches(cand, input, visible == 0) end
          search = not glyphs and alternatives and visible + 1 < text_slots
        end
        emit(cand, fresh)
      elseif visible % width < text_slots then
        emit(cand, fresh)
      else
        tail[#tail+1] = {cand = cand, fresh = fresh, protected = protected(cand)}
        if fresh then tail_count = tail_count + 1 end
        if visible % width + tail_count == width then flush_tail(true) end
      end
    end
  end
  if #tail > 0 then flush_tail(false) end
  local column = visible % width
  if glyphs and column > 0 then offer(math.min(quota, width - column)) end
end

return M
