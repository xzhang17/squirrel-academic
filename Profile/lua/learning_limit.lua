-- Keep long dictionary candidates usable without handing their phrase objects
-- to native Memory. max_word_length alone can still update long components.
local M = {}

function M.original_type(candidate)
  local kind = candidate:get_genuine().type
  return kind:match("^learning_limit/([^/]+)/") or kind
end

function M.init(env)
  env.limit = env.engine.schema.config:get_int("chinese_learning/max_chars") or 8
  env.native_limit = env.engine.schema.config:get_int("translator/max_word_length") or 0
end

local function safe_components(candidate, limit, native_limit)
  local sentence = candidate:to_sentence()
  if not sentence or native_limit <= 0 or candidate:spans().count <= native_limit then return false end
  -- Native max_word_length will reject the complete sentence. It may update
  -- its existing components, so every component must also fit the char cap.
  for _, entry in ipairs(sentence.entrys) do
    if utf8.len(entry.text) > limit then return false end
  end
  return true
end

function M.func(translation, env)
  for candidate in translation:iter() do
    local genuine = candidate:get_genuine()
    local native_phrase = genuine.type == "phrase" or genuine.type == "user_phrase" or genuine.type == "sentence"
    local blocked = false
    if native_phrase then
      local length = utf8.len(candidate.text)
      if length > env.limit then
        blocked = not safe_components(genuine, env.limit, env.native_limit)
      elseif length > genuine:spans().count then
        -- Extra text, such as a middle dot in a name, must not let several
        -- individually short segments exceed the character cap when joined.
        blocked = true
      end
    end
    if blocked then
      -- Simple candidates intentionally carry no native Memory entry. Retain
      -- the original syllable vertices in their internal type for navigation.
      local kind = "learning_limit/" .. genuine.type .. "/" .. table.concat(genuine:spans().vertices, ",")
      local plain = Candidate(kind, candidate.start, candidate._end, candidate.text, candidate.comment)
      plain.preedit = candidate.preedit
      plain.quality = candidate.quality
      yield(plain)
    else
      yield(candidate)
    end
  end
end

function M.tags_match(segment)
  return segment:has_tag("abc")
end

local processor = {}
function processor.func(key, env)
  if key:release() then return 2 end
  local name = key:repr()
  if name ~= "Tab" then return 2 end
  local ctx = env.engine.context
  local candidate = ctx:get_selected_candidate()
  if not candidate then return 2 end
  local encoded = candidate and candidate:get_genuine().type:match("^learning_limit/[^/]+/([%d,]+)$")
  local vertices = {}
  if encoded then
    for vertex in encoded:gmatch("%d+") do vertices[#vertices+1] = tonumber(vertex) end
  else
    vertices = candidate:spans().vertices
  end
  local caret, target = ctx.caret_pos, nil
  -- Handle plain Tab directly; do not manufacture a Shift+Right shortcut.
  for _, pos in ipairs(vertices) do
    if pos > caret then target = pos; break end
  end
  if not target then return 2 end
  ctx.caret_pos = target
  return 1
end

M.processor = processor
return M
