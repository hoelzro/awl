-- live object heap traversal functions

local function live_objects()
  print 'would traverse live objects as I know them'
end

return {
  live_objects = live_objects,
}
