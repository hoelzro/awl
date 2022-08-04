local iter = require 'iter'

local function meta_plus_keys(t)
  local mt = getmetatable(t)
  assert(mt)

  return iter.chain({iter.singleton(mt)}, {pairs(t)})
end

local function meta_plus_values(t)
  local mt = getmetatable(t)
  assert(mt)

  return iter.chain({iter.singleton(mt)}, {iter.select(2, pairs(t))})
end

local function keys_plus_values(t)
  return iter.chain({pairs(t)}, {iter.select(2, pairs(t))})
end

local function meta_plus_keys_plus_values(t)
  local mt = getmetatable(t)
  assert(mt)

  return iter.chain({iter.singleton(mt)}, {pairs(t)}, {iter.select(2, pairs(t))})
end

local mt = {}
local t = setmetatable({10, 11, 12, 13}, mt)

print '--- iter.singleton ---'
for value in iter.singleton(1) do
  print(value)
end

print ''
print '--- iter.select ---'
for k, v in iter.select(1, pairs(t)) do
  print(k, v)
end

print '----'
for v in iter.select(2, pairs(t)) do
  print(v)
end

print ''
print '--- meta_plus_keys ---'

for value in meta_plus_keys(t) do
  print(value)
end

print ''
print '--- meta_plus_values ---'

for value in meta_plus_values(t) do
  print(value)
end

print ''
print '--- keys_plus_values ---'

for value in keys_plus_values(t) do
  print(value)
end

print ''
print '--- meta_plus_keys_plus_values ---'

for value in meta_plus_keys_plus_values(t) do
  print(value)
end

local function function_local_iterator(state, local_idx)
  -- print('coro: ', state.co)
  -- print('level: ', state.level)
  -- print('index: ', local_idx)
  local name, value = debug.getlocal(state.co, state.level, local_idx + 1)
  if not name then
    return
  end

  return local_idx + 1, name, value
end

local function function_locals(co, level)
  -- XXX if co is the running coroutine, this will be fucked up!
  assert(co ~= coroutine.running())

  return function_local_iterator, {
    co    = co,
    level = level,
  }, 0
end

local function stack_frame_iterator(co, level)
  local info = debug.getinfo(co, level + 1, 'f')
  if not info then
    return
  end

  return level + 1, info.func
end

local function stack_frames(co)
  -- XXX if co is the running coroutine, this will be fucked up!
  assert(co ~= coroutine.running())

  return stack_frame_iterator, co, 0
end

do
  local function baz(d)
    local c = 'string'
    coroutine.yield()
  end

  local function bar()
    local b = 17
    baz(b)
  end

  local function foo()
    bar()
  end

  local function coro_main()
    local a = 18
    foo()
  end

  print ''
  print '--- coroutine traversal ---'

  local co = coroutine.create(coro_main)
  coroutine.resume(co)

  -- XXX add a partial application function
  -- XXX ...or account for this in the subiter API
  local function co_function_locals(level)
    return function_locals(co, level)
  end

  for name, value in iter.select(4, iter.subiter({stack_frames(co)}, co_function_locals)) do
    print(name, value)
  end
end
