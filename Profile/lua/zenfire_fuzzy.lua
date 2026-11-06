-- Match the same per-syllable fuzzy pairs as the spelling prism.
-- Explicit apostrophes must fall between the recorded syllables.
local M = {}
local characters

function M.is_han(cp)
  return (cp >= 0x3400 and cp <= 0x9fff) or (cp >= 0x20000 and cp <= 0x323af)
      or (cp >= 0xf900 and cp <= 0xfaff)
end

function M.pattern(reading)
  if not reading or not reading:match("^[a-z]+[a-z ]*$") then return nil end
  local parts = {}
  for syllable in reading:gmatch("[a-z]+") do
    parts[#parts+1] = syllable:gsub("^([scz])h?", "%1h?"):gsub("([aeio])ng?$", "%1ng?")
  end
  return "^" .. table.concat(parts, "'?") .. "$"
end

local function load_characters()
  if characters then return characters end
  local f = io.open(rime_api.get_user_data_dir() .. "/dicts/cn_dicts/8105.dict.yaml", "r")
  if not f then return end
  local readings = {}
  local body = false
  for line in f:lines() do
    if body then
      local word, code = line:match("^([^#\t]+)\t([a-z]+)\t")
      if word and utf8.len(word) == 1 then
        readings[word] = readings[word] or {}
        readings[word][#readings[word]+1] = code
      end
    elseif line:match("^%.%.%.%s*$") then body = true end
  end
  f:close()
  -- An empty or incomplete dictionary may be replaced during deployment.
  if next(readings) then characters = readings end
  return characters
end

local function variants(syllable)
  local forms, seen = {}, {}
  local function add(value)
    if not seen[value] then seen[value] = true; forms[#forms+1] = value end
  end
  add(syllable)
  if syllable:match("^[scz]h") then add((syllable:gsub("^([scz])h", "%1")))
  elseif syllable:match("^[scz]") then add((syllable:gsub("^([scz])", "%1h"))) end
  local count = #forms
  for i = 1, count do
    if forms[i]:match("[aeio]ng$") then add((forms[i]:gsub("g$", "")))
    elseif forms[i]:match("[aeio]n$") then add(forms[i] .. "g") end
  end
  -- Preserve the actual abbreviated spelling when migrating a legacy rule.
  local full = {}
  for _, value in ipairs(forms) do full[#full+1] = {value, syllable} end
  full[#full+1] = {syllable:sub(1, 1), syllable:sub(1, 1)}
  if syllable:match("^[scz]h") then full[#full+1] = {syllable:sub(1, 2), syllable:sub(1, 2)} end
  return full
end

-- Older four-column snapshots have no syllable boundaries. Recover those
-- boundaries using the selected Chinese characters, not a blind n/ng rewrite.
function M.infer(input, word)
  local readings = load_characters()
  if not readings then return nil end
  local chars = {}
  for _, cp in utf8.codes(word) do chars[#chars+1] = utf8.char(cp) end
  local failed = {}
  local function visit(index, pos)
    -- A supplied separator can only be crossed at a character/syllable
    -- boundary. Do not erase it and guess a conflicting reading.
    if index > 1 and input:sub(pos, pos) == "'" then pos = pos + 1 end
    if index > #chars then return pos == #input + 1 and {} or nil end
    local key = index .. ":" .. pos
    if failed[key] then return nil end
    for _, syllable in ipairs(readings[chars[index]] or {}) do
      for _, form in ipairs(variants(syllable)) do
        if input:sub(pos, pos + #form[1] - 1) == form[1] then
          local rest = visit(index + 1, pos + #form[1])
          if rest then table.insert(rest, 1, form[2]); return rest end
        end
      end
    end
    failed[key] = true
  end
  local found = visit(1, 1)
  return found and table.concat(found, " ") or nil
end

return M
