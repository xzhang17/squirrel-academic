-- Chinese usage preferences with one second-place trial for a new manual choice.
-- Native learning remains intact; these scores keep established choices stable.
local M = {}
local fuzzy = require("zenfire_fuzzy")
local rules, approved = {}, {}
local learned, serial, max_chars = {}, 0, 8
local learned_index = {}
local guard, path, writable
local sessions = 0
local decay, min_lead, lead_ratio = 0.995, 2, 1.2

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
  for _, name in ipairs({
    "dicts/cn_dicts/daily_words.dict.yaml",
    "dicts/cn_dicts/personal_terms.dict.yaml",
  }) do
    -- An incomplete deployment must never prune valid rules from the snapshot.
    if not read_word_list(name, words) then return nil end
  end
  -- Read the same enabled academic files as the native dictionary. Disabled
  -- subjects stay on disk without becoming curated candidates in this session.
  local dictionary = Config()
  if not dictionary:load_from_file(rime_api.get_user_data_dir() .. "/zenfire_pinyin.dict.yaml") then
    return nil
  end
  local tables = dictionary:get_list("import_tables")
  if not tables then return nil end
  for i = 0, tables.size - 1 do
    local name = dictionary:get_string("import_tables/@" .. i)
    if not name then return nil end
    if name:match("^dicts/academic_dicts/[a-z0-9_]+$") and
        not read_word_list(name .. ".dict.yaml", words) then return nil end
  end
  if include_mixed and not read_word_list("dicts/cn_dicts/personal_mixed.txt", words, "^#@/db_type\ttabledb%s*$") then
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
      selections[#selections+1] = table.concat({"usage/" .. key, word, entry.count,
          string.format("%.9g", entry.score), entry.position,
          (entry.manual and "1" or "0") .. (entry.trial and "1" or "0") .. (entry.seeded and "1" or "0"),
          entry.order, entry.reading or ""}, "\t") .. "\n"
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

local function pending_spelling(input)
  -- A selected prefix can include its trailing syllable separator. Internal
  -- separators still distinguish readings such as fan'gan and fang'an.
  return input:gsub("'+$", "")
end

local function spelling(input)
  -- Explicit syllable separators are significant. Legacy unseparated keys
  -- can still match separated input through a verified syllable reading.
  return pending_spelling(input):gsub("([sc])h", "%1")
end

local function reindex()
  learned_index = {}
  for key, entries in pairs(learned) do
    local initial = key:sub(1, 1)
    learned_index[initial] = learned_index[initial] or {}
    for word, entry in pairs(entries) do
      learned_index[initial][#learned_index[initial]+1] = {
        key = key, normalized = spelling(key), word = word, entry = entry, pattern = fuzzy.pattern(entry.reading)
      }
    end
  end
end

local function matching(input, word)
  input = pending_spelling(input)
  local matches, key = {}, spelling(input)
  for _, record in ipairs(learned_index[input:sub(1, 1)] or {}) do
    if (not word or word == record.word) and
        (record.normalized == key or (record.pattern and input:match(record.pattern))) then
      matches[#matches+1] = record
    end
  end
  return matches
end

function M.chinese_length(word)
  if not word or word == "" then return nil end
  local length = 0
  for _, cp in utf8.codes(word) do
    if not fuzzy.is_han(cp) then return nil end
    length = length + 1
  end
  return length
end

function M.init(include_mixed, limit, settings)
  sessions = sessions + 1
  -- Multiple app sessions share one Lua state and one lock/snapshot.
  if sessions > 1 then return end
  max_chars = limit or 8
  decay = settings and settings.decay or 0.995
  min_lead = settings and settings.min_lead or 2
  lead_ratio = settings and settings.lead_ratio or 1.2
  if decay <= 0 or decay > 1 then decay = 0.995 end
  if min_lead < 1 then min_lead = 2 end
  if lead_ratio < 1 then lead_ratio = 1.2 end
  approved = read_words(include_mixed)
  local user_dir = rime_api.get_user_data_dir()
  -- Keep the tabular contents in a top-level .txt file so Rime sync copies it.
  path = user_dir .. "/zenfire_preferences.txt"
  writable, rules, learned, serial, learned_index = false, {}, {}, 0, {}
  if not approved then return end
  if not guard then
    local lock = LevelDb("zenfire_pref_guard")
    if lock and lock:open() then guard = lock end
  end
  -- A second live engine using the same directory may read the last snapshot.
  -- Only the owner can replace it or clean up an interrupted write.
  if guard then os.remove(path .. ".new") end
  local f, _, err = io.open(path, "rb")
  local migrated_from
  -- Older manual backups used these names. Prefer the current snapshot.
  for _, name in ipairs({"academic_preferences.txt", "academic_preferences.tsv"}) do
    if f or err ~= 2 then break end
    local old_path = user_dir .. "/" .. name
    local old_file, _, old_err = io.open(old_path, "rb")
    f, err = old_file, old_err
    if f then migrated_from = old_path end
  end
  if not f then
    writable = guard ~= nil and err == 2 -- missing file, not a read failure
    return
  end
  local data = f:read("*a")
  f:close()
  -- Preserve unreadable snapshots rather than replacing them on the next commit.
  if not data or not utf8.len(data) or data:find("%z") then return end
  data = data:gsub("^\239\187\191", "")
  local prune = false
  for row in data:gmatch("[^\r\n]+") do
    local key, word = row:match("^([^\t]+)\t([^\t]+)$")
    local code, chosen, count, order, reading = row:match("^learn/([a-z][a-z']*)\t([^\t]+)\t([12])\t(%d+)\t?(.*)$")
    local position, score, flags
    if not code then
      code, chosen, count, score, position, flags, order, reading = row:match(
          "^usage/([a-z][a-z']*)\t([^\t]+)\t(%d+)\t([%d.eE+%-]+)\t(%d+)\t([01][01][01])\t(%d+)\t?(.*)$")
      score, position = tonumber(score), tonumber(position)
      if code and (not score or score < 0 or score == math.huge or not position or position < 1) then code = nil end
    end
    if code and M.chinese_length(chosen) and M.chinese_length(chosen) <= max_chars then
      if not fuzzy.pattern(reading) then
        reading = fuzzy.infer(code, chosen)
        if reading then prune = true end -- migrate the existing count/order intact
      end
      learned[code] = learned[code] or {}
      learned[code][chosen] = {count = tonumber(count), order = tonumber(order), reading = reading,
          score = score or tonumber(count), position = position,
          manual = not flags or flags:sub(1, 1) == "1",
          trial = flags and flags:sub(2, 2) == "1" or not flags and count == "1",
          seeded = flags and flags:sub(3, 3) == "1" or false}
      if not flags then prune = true end
      serial = math.max(serial, tonumber(order))
    elseif key and (approved[word] or M.chinese_length(word)) and
        (key:match("^exact/[a-z][a-z']*$") or key:match("^family/[a-z][a-z']*$")) then
      rules[key] = word
    else
      prune = true
    end
  end
  -- The old counter was capped at two, so it is not a historical usage total.
  -- Preserve its order initially; actual native counts seed scores on next use.
  for _, entries in pairs(learned) do
    local legacy = {}
    for word, entry in pairs(entries) do
      if not entry.position then legacy[#legacy+1] = {word = word, entry = entry} end
    end
    table.sort(legacy, function(a, b)
      if a.entry.trial ~= b.entry.trial then return not a.entry.trial end
      if a.entry.order ~= b.entry.order then return a.entry.order > b.entry.order end
      return a.word < b.word
    end)
    for i, record in ipairs(legacy) do record.entry.position = i end
  end
  reindex()
  writable = guard ~= nil
  if not writable then return end
  if (prune or migrated_from) and not save() then
    writable = false
    return
  end
  if migrated_from then os.remove(migrated_from) end
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

local function ordered(input)
  local records, seen = {}, {}
  for _, record in ipairs(matching(input)) do
    local old = seen[record.word]
    if not old or record.entry.order > old.entry.order then seen[record.word] = record end
  end
  for _, record in pairs(seen) do
    records[#records+1] = {key = record.key, word = record.word, entry = record.entry}
  end
  table.sort(records, function(a, b)
    if a.entry.position ~= b.entry.position then return a.entry.position < b.entry.position end
    if a.entry.order ~= b.entry.order then return a.entry.order > b.entry.order end
    return a.word < b.word
  end)
  return records
end

function M.has(input)
  return #matching(input) > 0
end

function M.revision()
  return serial
end

-- Called only for an actual commit, never while displaying or cancelling input.
-- candidates contains pre-commit native counts and the visible Chinese leaders.
function M.commit(input, word, deliberate, already_first, reading, candidates, trial_cutoff)
  if not writable then return false end
  input = pending_spelling(input)
  local length = M.chinese_length(word)
  if not length or length > max_chars then word, deliberate = nil, false end
  local records = ordered(input)
  if #records == 0 and not (word and deliberate) then return false end
  local before, previous_serial = {}, serial
  local function touch(key)
    if before[key] ~= nil then return end
    before[key] = learned[key] or false
    local copy = {}
    for text, entry in pairs(learned[key] or {}) do
      local item = {}; for k, v in pairs(entry) do item[k] = v end
      copy[text] = item
    end
    learned[key] = copy
  end
  local by_word, pending, key = {}, {}, spelling(input)
  for _, record in ipairs(records) do
    touch(record.key)
    record.entry = learned[record.key][record.word]
    by_word[record.word] = record
    if record.entry.trial then pending[record.word] = true end
  end
  -- Older snapshots can contain overlapping fuzzy spellings of one word.
  -- Keep the strongest accumulated evidence when consolidating those aliases.
  for _, old in ipairs(matching(input)) do
    local entry = by_word[old.word].entry
    entry.count = math.max(entry.count, old.entry.count)
    entry.score = math.max(entry.score, old.entry.score)
    entry.manual = entry.manual or old.entry.manual
    entry.seeded = entry.seeded or old.entry.seeded
  end
  local function add(text, native, pronunciation, baseline)
    if by_word[text] then return by_word[text] end
    touch(key)
    local entry = {count = native or 0, score = native or 0, position = #records + 1,
        manual = false, trial = false, seeded = native ~= nil, order = serial,
        reading = pronunciation or fuzzy.infer(input, text)}
    learned[key][text] = entry
    local record = {key = key, word = text, entry = entry}
    local position = #records + 1
    if baseline then
      for i, old in ipairs(records) do
        if pending[old.word] then position = i; break end
      end
    end
    table.insert(records, position, record)
    by_word[text] = record
    return record
  end
  -- Recover A/B before expiring a legacy trial that never stored its leaders.
  -- The displayed trial itself is not an established second-place baseline.
  local native_candidates, leaders = {}, 0
  local capture_leaders = deliberate or next(pending) ~= nil
  for _, candidate in ipairs(candidates or {}) do
    native_candidates[candidate.word] = candidate
    local record = by_word[candidate.word]
    if capture_leaders and not pending[candidate.word] and leaders < 2 then
      leaders = leaders + 1
      record = record or add(candidate.word, candidate.count, candidate.reading, true)
    end
    if record and candidate.count ~= nil and
        (not record.entry.seeded or candidate.count > record.entry.count) then
      -- Native learning can also advance outside an explicitly ranked input.
      -- Import only the new count; retain decay and avoid counting it twice.
      local extra = math.max(0, candidate.count - record.entry.count)
      record.entry.count = record.entry.count + extra
      record.entry.score = record.entry.score + extra
      record.entry.seeded = true
    end
  end
  if word and not by_word[word] then
    local native = native_candidates[word]
    add(word, native and native.count, reading)
  end
  -- Expire trials from before this composition. Repeated components must not
  -- consume a trial that an earlier component has only just created.
  for _, record in ipairs(records) do
    if not trial_cutoff or record.entry.order <= trial_cutoff then record.entry.trial = false end
    if word then record.entry.score = record.entry.score * decay end
  end
  if word then
    local entry = by_word[word].entry
    serial = serial + 1
    entry.count, entry.score, entry.order = entry.count + 1, entry.score + 1, serial
    if fuzzy.pattern(reading) then entry.reading = reading end
    if deliberate and not entry.manual then
      entry.manual = true
      entry.trial = not already_first
    end
  end
  -- Stable insertion: a clear lead is required to pass each established word.
  -- A trial is displayed separately and cannot jump straight to first place.
  for i = 2, #records do
    local j = i
    while j > 1 do
      local challenger, incumbent = records[j].entry, records[j-1].entry
      if challenger.trial or challenger.score < incumbent.score +
          math.max(min_lead, incumbent.score * (lead_ratio - 1)) then break end
      records[j], records[j-1] = records[j-1], records[j]
      j = j - 1
    end
  end
  for i, record in ipairs(records) do record.entry.position = i end
  -- Merge overlapping fuzzy aliases without adding their old counts twice.
  for _, old in ipairs(matching(input)) do
    if by_word[old.word].key ~= old.key then
      touch(old.key); learned[old.key][old.word] = nil
    end
  end
  if save() then reindex(); return true end
  for code, entries in pairs(before) do learned[code] = entries or nil end
  serial = previous_serial
  return false
end

function M.ranked(input)
  local first, trial, trial_order, words = nil, nil, -1, {}
  local records = ordered(input)
  for _, record in ipairs(records) do
    local word, entry = record.word, record.entry
    words[#words+1] = word
    if not first and not entry.trial then first = word end
    if entry.trial and entry.order > trial_order then trial, trial_order = word, entry.order end
  end
  -- With no saved leader, one completed trial alone does not earn first place.
  -- Let the native order decide until this word has further usage evidence.
  if #records == 1 and not trial and records[1].entry.manual and records[1].entry.count < 2 then first = nil end
  return first, trial, words
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
