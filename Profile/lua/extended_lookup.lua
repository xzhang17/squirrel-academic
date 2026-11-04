-- Only the pending composition can activate this tag. The ordinary pinyin
-- translator never sees this segment, and the extended translator requires it.
local tag, option = "extended_lookup", "_extended_lookup"
local processor = {}

function processor.init(env)
  env.reset = env.engine.context.update_notifier:connect(function(ctx)
    if ctx.input == "" and ctx:get_option(option) then ctx:set_option(option, false) end
  end)
end

function processor.fini(env)
  env.reset:disconnect()
end

function processor.func(key, env)
  local ctx = env.engine.context
  local active = ctx:get_option(option)
  local name = key:repr()
  if active then
    if name == "bracketright" or name == "Escape" then
      ctx:set_option(option, false)
      return 1
    end
    if name == "bracketleft" then return 1 end
    if (name == "space" or name == "equal" or name == "minus" or name:match("^[1-9]$"))
        and not ctx:has_menu() then return 1 end
    return 2
  end
  if name ~= "bracketleft" or ctx:get_option("ascii_mode") or ctx.input == "" then return 2 end
  local start = ctx.composition:toSegmentation():get_confirmed_position()
  if not ctx.input:sub(start + 1):match("^[a-z][a-z']*$") then return 2 end
  ctx.caret_pos = #ctx.input
  ctx:set_option(option, true)
  return 1
end

local function segmentor(segmentation, env)
  if not env.engine.context:get_option(option) then return true end
  local start = segmentation:get_current_start_position()
  if start ~= segmentation:get_confirmed_position() then return true end
  local seg = Segment(start, #segmentation.input)
  seg.tags = Set{tag}
  seg.prompt = "〔扩展词库 · 无匹配，按 ] 返回〕"
  segmentation:add_segment(seg)
  return false
end

local filter = {}
function filter.tags_match(seg)
  return seg:has_tag(tag)
end

function filter.func(translation, env)
  local ctx = env.engine.context
  local seg = ctx.composition:back()
  for cand in translation:iter() do
    -- 8105 is only there to pronounce Tencent's words. Ignore its single
    -- characters, incomplete matches, and sentences assembled by the engine.
    if cand.start == seg.start and cand._end == #ctx.input and cand:get_genuine().type == "phrase" and
        utf8.len(cand.text) > 1 then
      seg.prompt = "〔扩展词库〕"
      yield(cand)
    end
  end
end

return {processor = processor, segmentor = segmentor, filter = filter}
