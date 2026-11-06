local preferences = require("zenfire_preferences")

local function eligible(input)
  return #input <= 128 and input:match("^[a-z][a-z']*$")
end

local function candidate_reading(ctx, candidate)
  local parts, vertices = {}, candidate:spans().vertices
  if #vertices - 1 ~= preferences.chinese_length(candidate.text) then return nil end
  for i = 1, #vertices - 1 do
    local part = ctx.input:sub(vertices[i] + 1, vertices[i+1]):gsub("'", "")
    if not part:match("^[a-z]+$") then return nil end
    parts[#parts+1] = part
  end
  return table.concat(parts, " ")
end

local function native_count(candidate)
  local count
  for _, genuine in ipairs(candidate:get_genuines()) do
    local phrase = genuine:to_phrase()
    if phrase and phrase.entry then count = math.max(count or 0, phrase.entry.commit_count or 0) end
  end
  return count
end

local function menu_counts(ctx, segment, start, finish, limit)
  local candidates, seen = {}, {}
  for i = 0, 6 do
    local candidate = segment:get_candidate_at(i)
    if not candidate then break end
    local length = preferences.chinese_length(candidate.text)
    if candidate.start == start and candidate._end == finish and length and length <= limit
        and not seen[candidate.text] then
      candidates[#candidates+1] = {word = candidate.text, count = native_count(candidate),
          reading = candidate_reading(ctx, candidate)}
      seen[candidate.text] = true
    end
  end
  local chosen = segment:get_selected_candidate()
  local length = chosen and preferences.chinese_length(chosen.text)
  if chosen and chosen.start == start and chosen._end == finish and length and length <= limit
      and not seen[chosen.text] then
    candidates[#candidates+1] = {word = chosen.text, count = native_count(chosen),
        reading = candidate_reading(ctx, chosen)}
  end
  return candidates
end

-- Collect the completed composition, including separately selected pieces.
-- Trailing punctuation belongs to the output, not to the learned phrase.
-- Raw commits, English, and gaps in coverage cannot qualify.
local function selected_phrase(ctx)
  local segments = ctx.composition:toSegmentation()
  local parts, covered, deliberate, lookup = {}, 0, false, false
  local output, chinese_end, punctuation = {}, 0, false
  local readings, reading_complete = {}, true
  local first_candidate
  for i = 0, segments.size - 1 do
    local segment = segments:get_at(i)
    if segment._end > segment.start then
      if segment.start ~= covered then return nil end
      local candidate = segment:get_selected_candidate()
      if not candidate or candidate.start ~= covered then return nil end
      local kind = candidate:get_genuine().type
      if segment:has_tag("punct") and kind == "punct" and #parts > 0 then
        punctuation = true
      else
        if punctuation or not (segment:has_tag("abc") or segment:has_tag("extended_lookup"))
            or not preferences.chinese_length(candidate.text) then return nil end
        if kind ~= "phrase" and kind ~= "user_phrase" and kind ~= "sentence"
            and kind ~= "table" and kind ~= "user_table" and kind ~= "zenfire_first"
            and kind ~= "zenfire_rank" then return nil end
        lookup = lookup or segment:has_tag("extended_lookup")
        if #parts == 0 then first_candidate = segment:get_candidate_at(0) end
        parts[#parts+1] = candidate.text
        local vertices = candidate:spans().vertices
        if #vertices - 1 ~= preferences.chinese_length(candidate.text) then reading_complete = false end
        for j = 1, #vertices - 1 do
          local syllable = ctx.input:sub(vertices[j] + 1, vertices[j+1]):gsub("'", "")
          if not syllable:match("^[a-z]+$") then reading_complete = false end
          readings[#readings+1] = syllable
        end
        chinese_end = candidate._end
        deliberate = deliberate or segment.selected_index > 0
      end
      output[#output+1] = candidate.text
      covered = candidate._end
    end
  end
  if covered ~= #ctx.input or #parts == 0 then return nil end
  local text = table.concat(parts)
  if table.concat(output) ~= ctx:get_commit_text() then return nil end
  local input = ctx.input:sub(1, chinese_end)
  if not eligible(input) then return nil end
  local already_first = not lookup and first_candidate and first_candidate.text == text
      and first_candidate._end == chinese_end
  return text, deliberate or #parts > 1 or lookup, already_first,
      reading_complete and table.concat(readings, " ") or nil, input
end

local processor = {}
function processor.init(env)
  local config = env.engine.schema.config
  env.max_chars = config:get_int("chinese_learning/max_chars") or 8
  preferences.init(config:get_string("personal_mixed/user_dict") == "dicts/cn_dicts/personal_mixed", env.max_chars, {
    decay = config:get_double("chinese_learning/score_decay"),
    min_lead = config:get_double("chinese_learning/min_lead"),
    lead_ratio = config:get_double("chinese_learning/lead_ratio"),
  })
  env.connection = env.engine.context.commit_notifier:connect(function(ctx)
    if ctx:get_option("incognito_mode") or ctx:get_option("ascii_mode") or ctx:get_commit_text() == "" then return end
    local word, deliberate, already_first, reading, input = selected_phrase(ctx)
    local segments = ctx.composition:toSegmentation()
    local done = {}
    local trial_cutoff = preferences.revision()
    if word and (deliberate or preferences.has(input)) then
      local first_segment = segments:get_at(0)
      preferences.commit(input, word, deliberate, already_first, reading,
          menu_counts(ctx, first_segment, 0, #input, env.max_chars), trial_cutoff)
      done["0:" .. #input] = true
    end
    -- Existing component preferences also learn/consume a trial when committed
    -- inside a longer composition. Only already tracked spellings are handled.
    for i = 0, segments.size - 1 do
      local segment = segments:get_at(i)
      local choice = segment:get_selected_candidate()
      if choice and (segment:has_tag("abc") or segment:has_tag("extended_lookup")) then
        local spelling = ctx.input:sub(choice.start + 1, choice._end)
        local span = choice.start .. ":" .. choice._end
        if not done[span] and eligible(spelling) and preferences.has(spelling) then
          local first = segment:get_candidate_at(0)
          local chinese = preferences.chinese_length(choice.text) and choice.text or nil
          preferences.commit(spelling, chinese, segment.selected_index > 0,
              first and first.text == choice.text, candidate_reading(ctx, choice),
              menu_counts(ctx, segment, choice.start, choice._end, env.max_chars), trial_cutoff)
          done[span] = true
        end
      end
    end
  end)
  -- Run before native Memory deletion. Keep the current menu intact until
  -- native listeners have read its original selected candidate.
  env.deletion = env.engine.context.delete_notifier:connect(function(ctx)
    if ctx:get_option("incognito_mode") or ctx:get_option("ascii_mode") then return end
    local segment = ctx.composition:back()
    local candidate = ctx:get_selected_candidate()
    if not segment or not segment:has_tag("abc") or not candidate then return end
    local input = ctx.input:sub(candidate.start + 1, candidate._end)
    if eligible(input) then preferences.forget_word(input, candidate.text) end
  end, -1)
end

function processor.fini(env)
  env.connection:disconnect()
  env.deletion:disconnect()
  preferences.fini()
end

function processor.func(key, env)
  return 2
end

local filter = {}
function filter.init(env)
  -- Engine constructs filters after translators. An ungrouped connection here
  -- runs after native Memory and also refreshes custom-only synthetic choices.
  env.deletion = env.engine.context.delete_notifier:connect(function(ctx)
    if eligible(ctx.input) and not ctx:get_option("ascii_mode") and not ctx:get_option("incognito_mode") then
      ctx:refresh_non_confirmed_composition()
    end
  end)
end

function filter.fini(env)
  env.deletion:disconnect()
end

function filter.func(translation, env)
  local ctx = env.engine.context
  local input = ctx.input
  local segment = ctx.composition:back()
  if segment and segment:has_tag("punct") then
    -- Show punctuation as ordinary numbered choices, without width labels.
    for candidate in translation:iter() do
      if candidate:get_genuine().type == "punct" then candidate.comment = "" end
      yield(candidate)
    end
    return
  end
  local pinned, first, second, ranked
  local start = segment and segment.start
  if segment and segment._end == #input and segment:has_tag("abc")
      and not ctx:get_option("incognito_mode") and not ctx:get_option("ascii_mode")
      and (start == 0 or start == ctx.composition:toSegmentation():get_confirmed_position()) then
    -- Match only the pending spelling. All candidate offsets remain relative
    -- to the original input, including the already confirmed prefix.
    local spelling = input:sub(start + 1)
    if eligible(spelling) then
      pinned = preferences.get(spelling)
      first, second, ranked = preferences.ranked(spelling)
      first = pinned or first
      if first == second then second = nil end
    end
  end
  if not first and not second then
    for candidate in translation:iter() do yield(candidate) end
    return
  end

  local priority, wanted = {}, {}
  local function add(word)
    if word and not wanted[word] then
      priority[#priority+1], wanted[word] = word, true
    end
  end
  add(first)
  add(second)
  for _, word in ipairs(ranked or {}) do add(word) end

  -- Preserve genuine candidates so selections still update the user dictionary.
  -- Bound look-ahead on very large candidate lists.
  local buffer, matches = {}, {}
  for candidate in translation:iter() do
    -- An earlier segment's menu may also be read after the suffix is active.
    if #buffer == 0 and candidate.start ~= start then
      yield(candidate)
      for rest in translation:iter() do yield(rest) end
      return
    end
    buffer[#buffer+1] = candidate
    if candidate.start == start and candidate._end == #input
        and wanted[candidate.text] then
      matches[candidate.text] = matches[candidate.text] or candidate
    end
    local complete = #buffer >= 2
    for word in pairs(wanted) do if not matches[word] then complete = false; break end end
    if #buffer >= 64 or complete then break end
  end
  local seen, emitted = {}, 0
  local deferred_symbols
  local function flush_symbols()
    if not deferred_symbols then return end
    for _, candidate in ipairs(deferred_symbols) do yield(candidate) end
    deferred_symbols = nil
  end
  local function emit(word, pin)
    if not word or seen[word] then return end
    local candidate = matches[word]
    if candidate then
      if pin then candidate = ShadowCandidate(candidate, "zenfire_first", word, " ★") end
    else
      candidate = Candidate(pin and "zenfire_first" or "zenfire_rank", start, #input, word, pin and " ★" or "")
    end
    yield(candidate)
    seen[word], emitted = true, emitted + 1
  end
  local function emit_preferences()
    for _, word in ipairs(priority) do emit(word, word == pinned) end
  end
  if first then emit_preferences() end
  local function ordinary(candidate)
    local full = candidate.start == start and candidate._end == #input
    if full and (wanted[candidate.text] or seen[candidate.text]) then return end
    -- If native learning already put the once-selected word first, reserving
    -- it for slot two must not leave the clock or a symbol alone in slot one.
    if emitted == 0 and candidate.type == "symbol_suggestion" then
      deferred_symbols = deferred_symbols or {}
      deferred_symbols[#deferred_symbols+1] = candidate
      return
    end
    yield(candidate)
    if full then seen[candidate.text] = true end
    emitted = emitted + 1
    if emitted == 1 then
      emit_preferences()
      flush_symbols()
    end
  end
  for _, candidate in ipairs(buffer) do ordinary(candidate) end
  for candidate in translation:iter() do ordinary(candidate) end
  if second and not seen[second] then emit_preferences() end
  flush_symbols()
end

local shortcut_guard = {}
function shortcut_guard.func(key, env)
  -- Reject rather than consume: the application/macOS receives these keys.
  -- The native ascii composer runs first so a Shift combination cannot be
  -- mistaken for a lone Shift tap when Shift is subsequently released.
  if key:ctrl() or key:alt() or key:super() then return 0 end
  local code = key.keycode
  local shift_key = code == 0xffe1 or code == 0xffe2
  if code == 0xfe20 or (key:shift() and not shift_key and (code == 0x20 or code >= 0xff00)) then
    return 0
  end
  return 2
end

return { processor = processor, filter = filter, shortcut_guard = shortcut_guard }
