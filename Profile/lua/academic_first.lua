local preferences = require("academic_preferences")

local function eligible(input)
  return #input <= 64 and input:match("^[a-z][a-z']*$")
end

-- Only a single, full-input dictionary candidate may create a preference.
-- A sentence assembled by the engine, a partial match, or a raw commit cannot.
local function selected_word(ctx)
  local segment = ctx.composition:back()
  if not segment or not segment:has_tag("abc") or segment.start ~= 0 or
      segment._end ~= #ctx.input then return nil end
  local candidate = ctx:get_selected_candidate()
  if not candidate or candidate.start ~= 0 or candidate._end ~= #ctx.input then return nil end
  local kind = candidate:get_genuine().type
  -- Squirrel labels exact candidates from a read-only text table "user_table".
  if kind == "phrase" or kind == "table" or kind == "user_table" or kind == "academic_first" then
    return candidate.text
  end
end

local processor = {}
function processor.init(env)
  preferences.init(env.engine.schema.config:get_string("personal_mixed/user_dict") == "en_dicts/personal_mixed")
  env.connection = env.engine.context.commit_notifier:connect(function(ctx)
    local explicit = env.explicit_input == ctx.input
    env.explicit_input = nil
    if ctx:get_option("incognito_mode") or not eligible(ctx.input) then return end
    local segment = ctx.composition:back()
    if not segment or (segment.selected_index == 0 and not explicit) then return end
    local word = selected_word(ctx)
    if word and word == ctx:get_commit_text() then
      preferences.change(ctx.input, word, "learn")
    end
  end)
end

function processor.fini(env)
  env.connection:disconnect()
  preferences.fini()
end

function processor.func(key, env)
  local ctx = env.engine.context
  env.explicit_input = nil
  if not ctx:has_menu() then return 2 end
  local key_name = key:repr()
  local can_save = eligible(ctx.input) and not ctx:get_option("incognito_mode") and
      not ctx:get_option("_extended_lookup")
  if key_name == "Control+p" then
    local word = can_save and selected_word(ctx)
    if word and preferences.change(ctx.input, word, "pin") then ctx:refresh_non_confirmed_composition() end
    return 1 -- keep the highlight in place even when the word cannot be pinned
  end
  if not can_save then return 2 end
  if key_name:match("^[1-9]$") then
    env.explicit_input = ctx.input
  elseif key_name == "Control+u" and preferences.change(ctx.input, nil, "forget") then
    ctx:refresh_non_confirmed_composition()
    return 1 -- handled
  end
  return 2
end

local filter = {}
function filter.func(translation, env)
  local ctx = env.engine.context
  local input = ctx.input
  local segment = ctx.composition:back()
  local pinned
  if eligible(input) and segment and segment.start == 0 and segment._end == #input and
      segment:has_tag("abc") and not ctx:get_option("incognito_mode") then
    pinned = preferences.get(input)
  end
  if pinned then yield(Candidate("academic_first", 0, #input, pinned, " ★")) end
  for candidate in translation:iter() do
    if candidate.text ~= pinned or candidate._end ~= #input then yield(candidate) end
  end
end

return { processor = processor, filter = filter }
