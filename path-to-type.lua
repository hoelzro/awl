local heap = require 'heap'

local function count(t)
  local c = 0

  for _ in pairs(t) do
    c = c + 1
  end

  return c
end

local types_to_check = {}
for i = 1, #arg do
  types_to_check[arg[i]] = true
end

local objects = heap.live_objects()

local targets = {}
for obj in pairs(objects) do
  if types_to_check[type(obj)] then
    targets[obj] = true
  end
end

for t in pairs(targets) do
  print(t)
  local path = heap.path_to_object(t)
  while path do
    print(string.format('  %s', path.elem))
    path = path.tail
  end
end
