-- live object heap traversal functions

local assert = assert
local dgetmetatable = debug.getmetatable
local rawget = rawget
local sfind = string.find
local sformat = string.format
local type = type
local unpack = table.unpack

local iter = require 'iter'
local queue = require 'queue'

local AWESOME_TYPES = {
  key    = true,
  screen = true,
  drawin = true,
  button = true,
  tag = true,
  client = true,
  drawable = true,
}

local SIMPLE_TYPES = {
  ['nil'] = true,
  number = true,
  boolean = true,
  string = true, -- XXX we want to track # of strings though
}

local function live_objects()
  -- XXX make this into a ring buffer later? (just trimming it for now)
  local pending = {
    _G,
    -- XXX stacks of running coroutines?
    -- debug.getregistry(), -- XXX do this later?
  }

  -- XXX do I want a canary/sentinel __gc value to detect GCs? Would that be called at the beginning of the GC process, or the end?

  -- XXX __mode = 'k'?
  local seen = {} -- XXX these tables *are* getting cleaned up, right?
  seen[seen] = true

  local next_index = 1
  while next_index <= #pending do
    -- trim pending array
    if next_index >= 10000 then
      -- print(sformat('trimming pending (#pending = %d, #pending - next_index = %d)', #pending, #pending - next_index))
      local new_pending = {}

      for i = next_index, #pending do
        new_pending[#new_pending + 1] = pending[i]
      end

      pending = new_pending
      next_index = 1
    end

    local next = pending[next_index]
    next_index = next_index + 1

    if next == pending or seen[next] then
      goto continue
    end

    seen[next] = true

    local t = type(next)

    if t == 'table' then
      local weak_keys
      local weak_values

      local mt = dgetmetatable(next)

      if mt then
        if not seen[mt] then
          pending[#pending + 1] = mt
        end

        local mode = rawget(mt, '__mode') or ''
        weak_keys = string.find(mode, 'k')
        weak_values = string.find(mode, 'v')
      end

      -- XXX rawpairs?
      -- XXX do I want to treat weak tables differently?
      if weak_keys and not weak_values then
        for _, v in pairs(next) do
          if not seen[v] and not SIMPLE_TYPES[type(v)] then
            pending[#pending + 1] = v
          end
        end
      elseif not weak_keys and weak_values then
        for k in pairs(next) do
          if not seen[k] and not SIMPLE_TYPES[type(k)] then
            pending[#pending + 1] = k
          end
        end
      elseif not weak_keys and not weak_values then
        for k, v in pairs(next) do
          -- XXX only do this for unseen values?
          --     only do this for non-number/boolean/etc values?

          if not seen[k] and not SIMPLE_TYPES[type(k)] then
            pending[#pending + 1] = k
          end
          if not seen[v] and not SIMPLE_TYPES[type(v)] then
            pending[#pending + 1] = v
          end
        end
      end
    elseif t == 'function' then
      -- XXX mark things from debug.getinfo?
      local upvalue_index = 1
      while true do
        local name, value = debug.getupvalue(next, upvalue_index)
        if not name then
          break
        end

        upvalue_index = upvalue_index +  1

        if not seen[name] then
          pending[#pending + 1] = name
        end

        if not seen[value] and not SIMPLE_TYPES[type(value)] then
          pending[#pending + 1] = value
        end
      end
    elseif t == 'userdata' or AWESOME_TYPES[t] then
      -- Awesome types are actually userdata!
      -- XXX the closer I get to extracting "real" edges from userdata, rather than
      -- just waiting for values to be crawled via the registry, likely the better?
      local mt = dgetmetatable(next)
      if mt and not seen[mt] then
        pending[#pending + 1] = mt
      end

      local uv = debug.getuservalue(next)
      if uv and not seen[uv] and not SIMPLE_TYPES[type(uv)] then
        pending[#pending + 1] = uv
      end
    elseif t == 'thread' then
      -- XXX if there are C functions on the stack, I have no visibility into what Lua values are there, right?
      local level = 0
      while true do
        local info = debug.getinfo(next, level, 'f')
        if not info then
          break
        end

        local local_idx = 1
        while true do
          local name, value = debug.getlocal(next, level, local_idx)
          if not name then
            break
          end

          local_idx = local_idx + 1

          if not seen[name] then
            pending[#pending + 1] = name
          end

          if not seen[value] and not SIMPLE_TYPES[type(value)] then
            pending[#pending + 1] = value
          end
        end

        level = level + 1

        if not seen[info.func] then
          pending[#pending + 1] = info.func
        end
      end
    elseif t == 'string' or t == 'number' or t == 'boolean' then
      -- XXX treat long/short strings differently?
      -- do nothing (right?)
    else
      error(sformat('unhandled type: %s', t))
    end

    ::continue::
  end

  return seen
end

local function path_append(path, elem)
  return {
    elem = tostring(elem),
    tail = path,
  }
end

local function path_format(path)
  local elems = {}
  while path do
    elems[#elems + 1] = path.elem
    path = path.tail
  end
  return table.concat(elems, ' ')
end

local function path_to_object_helper(target, seen, current_path, obj)
  if obj == nil then
    return
  end

  if type(obj) == type(target) and obj == target then
    return current_path
  end

  if seen[obj] then
    return
  end
  seen[obj] = true

  local t = type(obj)

  if t == 'table' then
    local weak_keys
    local weak_values

    local mt = dgetmetatable(obj)

    if mt then
      if not seen[mt] then
        local path = path_to_object_helper(target, seen, path_append(current_path, '(metatable)'), mt)
        if path then
          return path
        end
      end

      local mode = rawget(mt, '__mode') or ''
      weak_keys = string.find(mode, 'k')
      weak_values = string.find(mode, 'v')
    end

    if weak_keys and not weak_values then
      for k, v in pairs(obj) do
        if not seen[v] and not SIMPLE_TYPES[type(v)] then
          local path = path_to_object_helper(target, seen, path_append(current_path, k), v)
          if path then
            return path
          end
        end
      end
    elseif not weak_keys and weak_values then
      for k in pairs(obj) do
        if not seen[k] and not SIMPLE_TYPES[type(k)] then
          local path = path_to_object_helper(target, seen, path_append(current_path, k), k)
          if path then
            return path
          end
        end
      end
    elseif not weak_keys and not weak_values then
      for k, v in pairs(obj) do
        if not seen[k] and not SIMPLE_TYPES[type(k)] then
          local path = path_to_object_helper(target, seen, path_append(current_path, k), k)
          if path then
            return path
          end
        end

        if not seen[v] and not SIMPLE_TYPES[type(v)] then
          local path = path_to_object_helper(target, seen, path_append(current_path, k), v)
          if path then
            return path
          end
        end
      end
    end
  elseif t == 'function' then
    local upvalue_index = 1
    while true do
      local name, value = debug.getupvalue(obj, upvalue_index)
      if not name then
        break
      end

      if not seen[name] then
        -- it's a string, so unless we're looking for strings we can omit this, right?
        local path = path_to_object_helper(target, seen, path_append(current_path, sformat('(upvalue %d: %q)', upvalue_index, name)), name)
        if path then
          return path
        end
      end

      if not seen[value] and not SIMPLE_TYPES[type(value)] then
        local path = path_to_object_helper(target, seen, path_append(current_path, sformat('(upvalue %d: %q)', upvalue_index, name)), value)
        if path then
          return path
        end
      end

      upvalue_index = upvalue_index +  1
    end
  elseif t == 'userdata' or AWESOME_TYPES[t] then
    -- Awesome types are actually userdata!
    -- XXX the closer I get to extracting "real" edges from userdata, rather than
    -- just waiting for values to be crawled via the registry, likely the better?
    local mt = dgetmetatable(obj)
    if mt and not seen[mt] then
      local path = path_to_object_helper(target, seen, path_append(current_path, '(metatable)'), mt)
      if path then
        return path
      end
    end

    local uv = debug.getuservalue(obj)
    if uv and not seen[uv] and not SIMPLE_TYPES[type(uv)] then
      local path = path_to_object_helper(target, seen, path_append(current_path, '(uservalue)'), uv)
      if path then
        return path
      end
    end
  elseif t == 'thread' then
    -- XXX if there are C functions on the stack, I have no visibility into what Lua values are there, right?
    local level = 0
    while true do
      local info = debug.getinfo(obj, level, 'f')
      if not info then
        break
      end

      local local_idx = 1
      while true do
        local name, value = debug.getlocal(obj, level, local_idx)
        if not name then
          break
        end

        local_idx = local_idx + 1

        if not seen[name] then
          local path = path_to_object_helper(target, seen, path_append(current_path, name), name)
          if path then
            return path
          end
        end

        if not seen[value] and not SIMPLE_TYPES[type(value)] then
          local path = path_to_object_helper(target, seen, path_append(current_path, name), value)
          if path then
            return path
          end
        end
      end

      level = level + 1

      if not seen[info.func] then
        local path = path_to_object_helper(target, seen, path_append(current_path, '(thread function)'), info.func)
        if path then
          return path
        end
      end
    end
  elseif t == 'string' or t == 'number' or t == 'boolean' then
    -- do nothing (right?)
  else
    error(sformat('unhandled type: %s', t))
  end
end

-- just returns the first path
local function path_to_object(target)
  local seen = {} -- XXX probably should be __mode = 'k', right?
  seen[seen] = true

  local roots = { _G } -- XXX registry too?

  for i = 1, #roots do
    local path = path_to_object_helper(target, seen, nil, roots[i])
    if path then
      return path
    end
  end
end

local QUEUE_FUNCTIONS = {}

-- XXX pass callback instead? (callback should enqueue after checking seen[value] and type(value) against SIMPLE_TYPES)
-- XXX if you're not including strings, you can avoid emitting them from these functions
function QUEUE_FUNCTIONS.table(seen, q, obj) -- XXX rename
  local mt = dgetmetatable(obj)
  local weak_keys
  local weak_values

  if mt then
    local mode = rawget(mt, '__mode') or ''
    weak_keys = sfind(mode, 'k')
    weak_values = sfind(mode, 'v')
  end

  if weak_keys then
    if not weak_values then
      -- XXX "rawpairs"
      for _, outgoing in pairs(obj) do
        if not seen[outgoing] and not SIMPLE_TYPES[type(outgoing)] then
          q:push(outgoing)
        end
      end
    end -- if weak keys and weak values, do nothing (maybe changing my mind in the future)
  else
    if weak_values then
      -- XXX "rawpairs"
      for outgoing in pairs(obj) do
        if not seen[outgoing] and not SIMPLE_TYPES[type(outgoing)] then
          q:push(outgoing)
        end
      end
    else
      -- XXX "rawpairs"
      for k, v in pairs(obj) do
        if not seen[k] and not SIMPLE_TYPES[type(k)] then
          q:push(k)
        end

        if not seen[v] and not SIMPLE_TYPES[type(v)] then
          q:push(v)
        end
      end
    end
  end
end

QUEUE_FUNCTIONS['function'] = function(seen, q, fn)
  -- XXX mark things from debug.getinfo?
  local upvalue_index = 1
  while true do
    local name, value = debug.getupvalue(fn, upvalue_index)
    if not name then
      break
    end

    upvalue_index = upvalue_index +  1

    --[[
    if not seen[name] then
      q:push(name)
    end
    ]]

    if not seen[value] and not SIMPLE_TYPES[type(value)] then
      q:push(value)
    end
  end
end

function QUEUE_FUNCTIONS.thread(seen, q, th)
  -- XXX if there are C functions on the stack, I have no visibility into what Lua values are there, right?
  local level = 0
  while true do
    local info = debug.getinfo(th, level, 'f')
    if not info then
      break
    end

    local local_idx = 1
    while true do
      local name, value = debug.getlocal(th, level, local_idx)
      if not name then
        break
      end

      local_idx = local_idx + 1

      --[[
      if not seen[name] then
        pending[#pending + 1] = name
      end
      ]]

      if not seen[value] and not SIMPLE_TYPES[type(value)] then
        q:push(value)
      end
    end

    level = level + 1

    if not seen[info.func] then
      q:push(info.func)
    end
  end
end

function QUEUE_FUNCTIONS.userdata(seen, q, udata)
  local mt = dgetmetatable(udata)
  if mt and not seen[mt] then
    q:push(mt)
  end

  local uv = debug.getuservalue(udata)
  if uv and not seen[uv] then
    q:push(uv)
  end
end

for t in pairs(AWESOME_TYPES) do
  QUEUE_FUNCTIONS[t] = QUEUE_FUNCTIONS.userdata
end

local function new_live_objects(options)
  options = options or {}
  -- XXX optimization
  -- XXX "should I traverse weak keys/values" option
  -- XXX include strings or something
  -- XXX "step size"?
  -- XXX custom root set? "is reachable"

  local roots = { _G }
  if options.registry then
    roots[#roots + 1] = debug.getregistry()
  end

  local q = queue:new(roots)
  local seen = setmetatable({}, {__mode = 'k'})
  seen[seen] = true -- XXX is this necessary?

  while true do
    local obj = q:pop()
    if not obj then
      break
    end

    -- XXX is the obj == q thing necessary?
    if obj == q or seen[obj] then
      goto continue
    end
    seen[obj] = true

    local t = type(obj)
    if not SIMPLE_TYPES[t] then
      local queue_f = assert(QUEUE_FUNCTIONS[t], sformat('unhandled type: %s', t))

      queue_f(seen, q, obj)
    end

    ::continue::
  end

  seen[seen] = nil
  return seen
end

return {
  live_objects   = live_objects,
  path_to_object = path_to_object,
}
