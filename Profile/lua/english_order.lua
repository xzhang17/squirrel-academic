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
  return cand:get_genuine().type == "user_table" and
      ((mixed and mixed[cand.text]) or english_text(cand.text))
end

-- Only entries intentionally written in this account's standard phrase table
-- get this priority. Preserve weights, and file order when weights are equal.
function M.init(env)
  -- A private exact-spelling table can offer X射线 and U盘 in the same slots
  -- as English. Explicit custom phrases still precede both tables.
  env.mixed = {}
  if env.engine.schema.config:get_string("personal_mixed/user_dict") == "en_dicts/personal_mixed" then
    local file = io.open(rime_api.get_user_data_dir() .. "/en_dicts/personal_mixed.txt", "r")
    if file then
      for line in file:lines() do
        local word, code = line:match("^([^#\t][^\t]*)\t([a-z]+)\t")
        if code then
          env.mixed[code] = env.mixed[code] or {}
          env.mixed[code][word] = true
        end
      end
      file:close()
    end
  end
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

function M.func(translation, env)
  local ctx = env.engine.context
  local segment = ctx.composition:back()
  local input = ctx.input
  local mixed = env.mixed[input]
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
