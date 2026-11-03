-- Only entries in the curated or personal word lists are eligible.
-- The general pinyin dictionary and its generated sentences remain usable.
local M = {}
local rules, approved = {}, {}
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

-- Replace the current rules atomically. No append log, usage count, or choice
-- timestamp. The LevelDB handle is only an interprocess lock and stays empty.
local function save()
  local keys = {}
  for key in pairs(rules) do keys[#keys+1] = key end
  table.sort(keys)
  local rows = {}
  for i, key in ipairs(keys) do rows[i] = key .. "\t" .. rules[key] .. "\n" end
  local tmp = path .. ".new"
  local f = io.open(tmp, "wb")
  if not f then return false end
  local wrote = f:write(table.concat(rows))
  local closed = f:close()
  if wrote and closed and os.rename(tmp, path) then return true end
  os.remove(tmp)
  return false
end

function M.init(include_mixed)
  sessions = sessions + 1
  approved = read_words(include_mixed)
  local user_dir = rime_api.get_user_data_dir()
  -- Keep the tabular contents in a top-level .txt file so Rime sync copies it.
  path = user_dir .. "/academic_preferences.txt"
  writable, rules = false, {}
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
    if key and approved[word] and
        (key:match("^exact/[a-z][a-z']*$") or key:match("^family/[a-z][a-z']*$")) then
      rules[key] = word
    else
      prune = true
    end
  end
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

function M.get(input)
  return rules["exact/" .. input] or rules[family(input)]
end

-- nil means the authored dictionaries could not be loaded. Callers can keep
-- the existing ranking in that case.
function M.is_curated(word)
  return approved and approved[word] == true
end

function M.change(input, word, action)
  if not writable or (action ~= "forget" and not approved[word]) then return false end
  local group, exact = family(input), "exact/" .. input
  local key = group
  if action == "learn" then
    if M.get(input) then return true end
  elseif action == "pin" and rules[group] then
    key = exact
  elseif action == "forget" and rules[exact] then
    key = exact
  end
  local old = rules[key]
  if old == word then return true end
  rules[key] = word
  if save() then return true end
  rules[key] = old
  return false
end

return M
