-- Explicit pins and capped, two-step Chinese selection preferences.
-- Rime's separate user dictionary handles ordinary frequency learning.
local M = {}
local fuzzy = require("academic_fuzzy")
local rules, approved = {}, {}
local learned, serial, max_chars = {}, 0, 8
local learned_index = {}
local guard, path, writable
local sessions = 0

local function read_word_list(name, words, header)
  local file, _, err = io.open(rime_api.get_user_data_dir() .. "/" .. name, "r")
  if not file and err == 2 then
    file = io.open(rime_api.get_shared_data_dir() .. "/" .. name, "r")
  end
  if not file then return nil end
  local body = false
  for line in file:lines() do
    if body then
      local word = line:match("^([^#%s][^\t]*)\t[a-z]")
      if word then words[word] = true end
    elseif line:match(header or "^%.%.%.%s*$") then
      body = true
    end
  end
  file:close()
  return body
end

local function read_words(include_mixed)
  local words = {}
  for _, name in ipairs({"academic_terms.dict.yaml", "daily_words.dict.yaml", "personal_terms.dict.yaml"}) do
    -- An incomplete deployment must never prune valid rules from the snapshot.
    if not read_word_list(name, words) then return nil end
  end
  if include_mixed and not read_word_list("en_dicts/personal_mixed.txt", words, "^#@/db_type\ttabledb%s*$") then
    return nil
  end
  return words
end

-- Replace a current snapshot, without a chronological selection log.
-- The LevelDB handle is an interprocess lock, not the learned-word store.
local function save()
  local keys = {}
  for key in pairs(rules) do keys[#keys+1] = key end
  table.sort(keys)
  local rows = {}
  for i, key in ipairs(keys) do rows[i] = key .. "\t" .. rules[key] .. "\n" end
  local selections = {}
  for key, entries in pairs(learned) do
    for word, entry in pairs(entries) do
      selections[#selections+1] = "learn/" .. key .. "\t" .. word .. "\t" .. entry.count .. "\t" .. entry.order
          .. (entry.reading and "\t" .. entry.reading or "") .. "\n"
    end
  end
  table.sort(selections)
  for _, row in ipairs(selections) do rows[#rows+1] = row end
  local tmp = path .. ".new"
  local f = io.open(tmp, "wb")
  if not f then return false end
  local wrote = f:write(table.concat(rows))
  local closed = f:close()
  if wrote and closed and os.rename(tmp, path) then return true end
  os.remove(tmp)
  return false
end

local function spelling(input)
  -- Explicit syllable separators are significant. Legacy unseparated keys
  -- can still match separated input through a verified syllable reading.
  return input:gsub("([sc])h", "%1")
end

local function reindex()
  learned_index = {}
  for key, entries in pairs(learned) do
    local initial = key:sub(1, 1)
    learned_index[initial] = learned_index[initial] or {}
    for word, entry in pairs(entries) do
      learned_index[initial][#learned_index[initial]+1] = {
        key = key, word = word, entry = entry, pattern = fuzzy.pattern(entry.reading)
      }
    end
  end
end

local function matching(input, word)
  local matches, key = {}, spelling(input)
  for _, record in ipairs(learned_index[input:sub(1, 1)] or {}) do
    if (not word or word == record.word) and
        (record.key == key or (record.pattern and input:match(record.pattern))) then
      matches[#matches+1] = record
    end
  end
  return matches
end

function M.chinese_length(word)
  if not word or word == "" then return nil end
  local length = 0
  for _, cp in utf8.codes(word) do
    if not ((cp >= 0x3400 and cp <= 0x9fff) or (cp >= 0x20000 and cp <= 0x323af)
        or (cp >= 0xf900 and cp <= 0xfaff)) then return nil end
    length = length + 1
  end
  return length
end

function M.init(include_mixed, limit)
  sessions = sessions + 1
  -- Multiple app sessions share one Lua state and one lock/snapshot.
  if sessions > 1 then return end
  max_chars = limit or 8
  approved = read_words(include_mixed)
  local user_dir = rime_api.get_user_data_dir()
  -- Keep the tabular contents in a top-level .txt file so Rime sync copies it.
  path = user_dir .. "/academic_preferences.txt"
  writable, rules, learned, serial, learned_index = false, {}, {}, 0, {}
  if not approved then return end
  if not guard then
    local lock = LevelDb("academic_pref_guard")
    if lock and lock:open() then guard = lock end
  end
  -- A second live engine using the same directory may read the last snapshot.
  -- Only the owner can replace it or clean up an interrupted write.
  local legacy = user_dir .. "/academic_preferences.tsv"
  if guard then
    os.remove(path .. ".new")
    os.remove(legacy .. ".new")
  end
  local f, _, err = io.open(path, "rb")
  local migrating = false
  if not f and err == 2 then
    f, _, err = io.open(legacy, "rb")
    migrating = f ~= nil
  end
  if not f then
    writable = guard ~= nil and err == 2 -- missing file, not a read failure
    return
  end
  local data = f:read("*a")
  f:close()
  if not data then return end
  local prune = false
  for row in data:gmatch("[^\n]+") do
    local key, word = row:match("^([^\t]+)\t([^\t]+)$")
    local code, chosen, count, order, reading = row:match("^learn/([a-z][a-z']*)\t([^\t]+)\t([12])\t(%d+)\t?(.*)$")
    if code and M.chinese_length(chosen) and M.chinese_length(chosen) <= max_chars then
      if not fuzzy.pattern(reading) then
        reading = fuzzy.infer(code, chosen)
        if reading then prune = true end -- migrate the existing count/order intact
      end
      learned[code] = learned[code] or {}
      learned[code][chosen] = {count = tonumber(count), order = tonumber(order), reading = reading}
      serial = math.max(serial, tonumber(order))
    elseif key and (approved[word] or M.chinese_length(word)) and
        (key:match("^exact/[a-z][a-z']*$") or key:match("^family/[a-z][a-z']*$")) then
      rules[key] = word
    else
      prune = true
    end
  end
  reindex()
  writable = guard ~= nil
  if not writable then return end
  if (prune or migrating) and not save() then
    writable = false
    return
  end
  -- An existing current snapshot, including an empty one, supersedes the old
  -- copy even if an earlier migration was interrupted just before cleanup.
  os.remove(legacy)
end

function M.fini()
  sessions = sessions - 1
  -- Native sync tears down all sessions before backing up the databases.
  if sessions == 0 then
    if guard then guard:close(); guard = nil end
    writable = false
  end
end

local function family(input)
  return "family/" .. input:gsub("([sc])h", "%1")
end

function M.learn(input, word, already_first, reading)
  local length = M.chinese_length(word)
  if not writable or not length or length > max_chars then return false end
  local key = spelling(input)
  local previous_count, newest = 0, -1
  for _, record in ipairs(matching(input, word)) do
    previous_count = math.max(previous_count, record.entry.count)
    if record.entry.order > newest then key, newest = record.key, record.entry.order end
  end
  local entries = learned[key] or {}
  local old, previous_serial = entries[word], serial
  if not fuzzy.pattern(reading) then reading = old and old.reading or fuzzy.infer(input, word) end
  serial = serial + 1
  entries[word] = {count = already_first and 2 or math.min(2, previous_count + 1), order = serial, reading = reading}
  learned[key] = entries
  if save() then reindex(); return true end
  entries[word], serial = old, previous_serial
  return false
end

-- The most recently deliberately selected twice-learned word wins.
-- A once-selected word occupies second place until selected again.
function M.ranked(input)
  local first, second, first_order, second_order = nil, nil, -1, -1
  for _, record in ipairs(matching(input)) do
    local word, entry = record.word, record.entry
    if entry.count == 2 and entry.order > first_order then
      first, first_order = word, entry.order
    elseif entry.count == 1 and entry.order > second_order then
      second, second_order = word, entry.order
    end
  end
  return first, second
end

function M.get(input)
  return rules["exact/" .. input] or rules[family(input)]
end

-- nil means the authored dictionaries could not be loaded. Callers can keep
-- the existing ranking in that case.
function M.is_curated(word)
  return approved and approved[word] == true
end

-- Native candidate deletion is word-specific. Clear every matching automatic
-- alias and active pin for that word, preserving unrelated choices.
function M.forget_word(input, word)
  if not writable or not word then return false end
  local removed, pins, group = matching(input, word), {}, family(input)
  for key, value in pairs(rules) do
    local code = key:match("^exact/(.+)$") or key:match("^family/(.+)$")
    if value == word and code and family(code) == group then pins[key] = value end
  end
  for key in pairs(pins) do rules[key] = nil end
  if #removed == 0 and next(pins) == nil then return false end
  for _, record in ipairs(removed) do learned[record.key][record.word] = nil end
  if save() then reindex(); return true end
  for key, value in pairs(pins) do rules[key] = value end
  for _, record in ipairs(removed) do learned[record.key][record.word] = record.entry end
  return false
end

return M
