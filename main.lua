local heap = require 'heap'

local objects = heap.live_objects()
local count = 0
for _ in pairs(objects) do
  count = count + 1
end
print(count)
