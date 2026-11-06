-- The native read-only tables look up exact spellings. Their high quality
-- makes matches available immediately even when pinyin has many candidates.
local M = {}

local function english_text(text)
  if not text:find("[A-Za-z]") then return false end
  for _, char in utf8.codes(text) do
    if char >= 0x2e80 then return false end  -- Keep entries such as X光 with Chinese.
  end
  return true
end

local function english_table_entry(cand, mixed)
  local kind = cand:get_genuine().type
  return kind == "mixed_separated" or (kind == "user_table" and
      ((mixed and mixed[cand.text]) or english_text(cand.text)))
end

local mixed_name = "dicts/cn_dicts/personal_mixed"
local personal = "# Personal entries below this line are preserved when rebuilding."
local indices, clients = {}, 0

local function init_mixed(env)
  clients = clients + 1
  if env.engine.schema.config:get_string("personal_mixed/user_dict") == mixed_name then
    env.mixed_path = rime_api.get_user_data_dir() .. "/" .. mixed_name .. ".txt"
  end
end

local function fini_mixed()
  clients = clients - 1
  if clients == 0 then indices = {} end
end

-- Both components use the same table. Keep one copy per active profile and
-- publish it only after a successful read so a missing file can be retried.
local function mixed_index(path)
  if indices[path] then return indices[path] end
  local file = io.open(path, "r")
  if not file then return nil end
  local index = {words = {}, readings = {}}
  local before_personal = true
  for line in file:lines() do
    if line:sub(1, 1) ~= "#" then
      local word, code = line:match("^([^\t]+)\t([a-z]+)\t")
      if code then
        index.words[code] = index.words[code] or {}
        index.words[code][word] = true
      end
    elseif before_personal then
      local comment = line:gsub("\r$", "")
      if comment == personal then
        before_personal = false
      else
        local word, forms = comment:match("^# syllables\t([^\t]+)\t(.+)$")
        if word then index.readings[word] = forms end
      end
    end
  end
  file:close()
  -- Legacy unmarked tables store joined spellings only.
  if before_personal then index.readings = {} end
  if next(index.words) then indices[path] = index end
  return indices[path]
end

local function accepts_boundaries(forms, input)
  if not forms then return false end
  for form in forms:gmatch("[a-z']+") do
    if input:match("^" .. form:gsub("'", "'?") .. "$") then return true end
  end
  return false
end

local separated = {init = init_mixed}
function separated.func(input, segment, env)
  if not env.mixed_path or not input:find("'", 1, true) or not segment:has_tag("abc")
      or segment.start ~= 0 or input ~= env.engine.context.input then return end
  local index = mixed_index(env.mixed_path)
  local code = input:gsub("'", "")
  local words = index and index.words[code]
  if not words then return end
  local allowed = {}
  for word in pairs(words) do
    if accepts_boundaries(index.readings[word], input) then allowed[word] = true end
  end
  if not next(allowed) then return end

  -- Query the same read-only table as joined input, retaining its weights,
  -- personal overrides and tie order. Only the candidate's input span changes.
  env.mixed_table = env.mixed_table or Component.Translator(env.engine, "", "table_translator@personal_mixed")
  if not env.mixed_table then return end
  local joined = Segment(0, #code)
  joined.tags = Set{"abc"}
  local translation = env.mixed_table:query(code, joined)
  if not translation then return end
  for candidate in translation:iter() do
    if candidate._end == #code and allowed[candidate.text] then
      local result = Candidate("mixed_separated", 0, segment._end, candidate.text, candidate.comment)
      result.quality, result.preedit = candidate.quality, input
      yield(result)
    end
  end
end
function separated.fini(env)
  env.mixed_table = nil
  fini_mixed()
end
M.separated = separated

-- Only entries intentionally written in this account's standard phrase table
-- get this priority. Preserve weights, and file order when weights are equal.
function M.init(env)
  -- A private exact-spelling table can offer X射线 and U盘 in the same slots
  -- as English. Explicit custom phrases still precede both tables.
  init_mixed(env)
  if env.mixed_path then mixed_index(env.mixed_path) end
  env.explicit = {}
  local file = io.open(rime_api.get_user_data_dir() .. "/custom_phrase.txt", "r")
  if not file then return end
  local order = 0
  for line in file:lines() do
    if line:sub(1, 1) ~= "#" then
      local word, code, weight = line:match("^([^\t]+)\t([a-z']+)\t?([^\t]*)$")
      if word then
        order = order + 1
        local entries = env.explicit[code] or {}
        entries[#entries+1] = {word = word, weight = tonumber(weight) or 0, order = order}
        env.explicit[code] = entries
      end
    end
  end
  file:close()
  for _, entries in pairs(env.explicit) do
    table.sort(entries, function(a, b)
      if a.weight == b.weight then return a.order < b.order end
      return a.weight > b.weight
    end)
  end
end

M.fini = fini_mixed

function M.func(translation, env)
  local ctx = env.engine.context
  local segment = ctx.composition:back()
  local input = ctx.input
  local index = env.mixed_path and indices[env.mixed_path]
  local mixed = index and index.words[input]
  if not segment or not segment:has_tag("abc") or segment.start ~= 0
      or segment._end ~= #input or not input:match("^[a-z][a-z']*$") then
    for cand in translation:iter() do
      if not english_table_entry(cand, mixed) then yield(cand) end
    end
    return
  end

  local priority = env.engine.schema.config:get_string("english_first/" .. input)
  local seen, pending, chinese = {}, {}, {}
  local count, emitted = 0, 0
  for _, row in ipairs(env.explicit[input] or {}) do
    if not seen[row.word] then
      seen[row.word] = true
      if not english_text(row.word) then
        chinese[row.word] = true
        count = count + 1
      end
      yield(Candidate("user_table", 0, #input, row.word, ""))
    end
  end
  if priority and not seen[priority] then
    yield(Candidate("english_first", 0, #input, priority, ""))
    seen[priority] = true
  end
  local function flush(limit)
    while emitted < #pending and emitted < limit do
      emitted = emitted + 1
      yield(pending[emitted])
    end
  end

  for cand in translation:iter() do
    local word = cand.text
    if english_table_entry(cand, mixed) then
      if cand.start == 0 and cand._end == #input and not seen[word] then
        seen[word] = true
        pending[#pending + 1] = cand
        if count >= 2 then flush(count >= 5 and #pending or 1) end
      end
    elseif not (seen[word] and cand.start == 0 and cand._end == #input) then
      yield(cand)
      if count < 5 and not chinese[word] then
        chinese[word] = true
        count = count + 1
        if count == 2 then flush(1) elseif count == 5 then flush(#pending) end
      end
    end
  end
  -- With fewer Chinese matches, use the available places on this page.
  flush(#pending)
end

return M
