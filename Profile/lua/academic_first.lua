local preferences = require("academic_preferences")

local function eligible(input)
  return #input <= 128 and input:match("^[a-z][a-z']*$")
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
            and kind ~= "table" and kind ~= "user_table" and kind ~= "academic_first"
            and kind ~= "academic_rank" then return nil end
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
  local already_first = not lookup and #parts == 1 and first_candidate and first_candidate.text == text
  return text, deliberate or #parts > 1 or lookup, already_first,
      reading_complete and table.concat(readings, " ") or nil, input
end

local processor = {}
function processor.init(env)
  local config = env.engine.schema.config
  env.max_chars = config:get_int("chinese_learning/max_chars") or 8
  preferences.init(config:get_string("personal_mixed/user_dict") == "en_dicts/personal_mixed", env.max_chars)
  env.connection = env.engine.context.commit_notifier:connect(function(ctx)
    local explicit_input = env.explicit_input
    env.explicit_input = nil
    if ctx:get_option("incognito_mode") or ctx:get_option("ascii_mode") then return end
    local word, deliberate, already_first, reading, input = selected_phrase(ctx)
    if word and (deliberate or explicit_input == input) then preferences.learn(input, word, already_first, reading) end
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
  local ctx = env.engine.context
  env.explicit_input = nil
  if key:release() or not ctx:has_menu() then return 2 end
  local key_name = key:repr()
  local can_save = eligible(ctx.input) and not ctx:get_option("incognito_mode")
      and not ctx:get_option("_extended_lookup") and not ctx:get_option("ascii_mode")
  if not can_save then return 2 end
  if key_name:match("^[1-9]$") then
    env.explicit_input = ctx.input
  end
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
  local pinned, first, second
  if eligible(input) and segment and segment.start == 0 and segment._end == #input
      and segment:has_tag("abc") and not ctx:get_option("incognito_mode") then
    pinned = preferences.get(input)
    first, second = preferences.ranked(input)
    first = pinned or first
    if first == second then second = nil end
  end
  if not first and not second then
    for candidate in translation:iter() do yield(candidate) end
    return
  end

  -- Preserve genuine candidates so selections still update the user dictionary.
  -- Bound look-ahead on very large candidate lists.
  local buffer, matches = {}, {}
  for candidate in translation:iter() do
    buffer[#buffer+1] = candidate
    if candidate.start == 0 and candidate._end == #input
        and (candidate.text == first or candidate.text == second) then
      matches[candidate.text] = matches[candidate.text] or candidate
    end
    if #buffer >= 64 or (#buffer >= 2 and (not first or matches[first])
        and (not second or matches[second])) then break end
  end
  local seen, emitted = {}, 0
  local function emit(word, pin)
    if not word or seen[word] then return end
    local candidate = matches[word]
    if candidate then
      if pin then candidate = ShadowCandidate(candidate, "academic_first", word, " ★") end
    else
      candidate = Candidate(pin and "academic_first" or "academic_rank", 0, #input, word, pin and " ★" or "")
    end
    yield(candidate)
    seen[word], emitted = true, emitted + 1
  end
  emit(first, pinned ~= nil)
  local function ordinary(candidate)
    local full = candidate.start == 0 and candidate._end == #input
    if full and (candidate.text == first or candidate.text == second or seen[candidate.text]) then return end
    yield(candidate)
    if full then seen[candidate.text] = true end
    emitted = emitted + 1
    if emitted == 1 then emit(second, false) end
  end
  if emitted == 1 then emit(second, false) end
  for _, candidate in ipairs(buffer) do ordinary(candidate) end
  for candidate in translation:iter() do ordinary(candidate) end
  if second and not seen[second] then emit(second, false) end
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
