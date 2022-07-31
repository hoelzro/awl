-- live object heap traversal functions

local dgetmetatable = debug.getmetatable
local sformat = string.format

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
  number = true,
  boolean = true,
  -- string = true, -- XXX we want to track # of strings though
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

        local mode = mt.__mode or ''
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
      else
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

return {
  live_objects = live_objects,
}
