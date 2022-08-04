local queue_methods = {}
local queue_mt = {__index = queue_methods}

-- XXX less dumb impl later
function queue_methods:new(values)
  local q = setmetatable({_counter = 1}, queue_mt)
  for i = 1, #values do
    q:push(values[i])
  end
  return q
end

function queue_methods:push(value)
  assert(value ~= nil)
  self[#self + 1] = value
end

function queue_methods:pop()
  local value = self[self._counter]
  if value ~= nil then
    self._counter = self._counter + 1
  end
  return value
end

return setmetatable({}, queue_mt)
