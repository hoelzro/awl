local iter = {}

local function singleton_iterator(state, value)
  if state.done then
    return
  end

  state.done = true

  return value
end

function iter.singleton(value)
  return singleton_iterator, {}, value
end

local function select_iterator(state)
  local next_values = {state.inner_f(state.inner_s, state.inner_v)}
  state.inner_v = next_values[1]

  return select(state.index, table.unpack(next_values))
end

function iter.select(index, inner_f, inner_s, inner_v)
  local state = {
    index = index,

    inner_f = inner_f,
    inner_s = inner_s,
    inner_v = inner_v,
  }

  return select_iterator, state
end

local function chain_iterator(chain, value)
  local values = {chain.func(chain.state, value)}

  while values[1] == nil and chain.next do
    chain.func = chain.next.func
    chain.state = chain.next.state
    chain.value = chain.next.value
    chain.next = chain.next.next

    values = {chain.func(chain.state, chain.value)}
  end

  return table.unpack(values)
end

function iter.chain(...)
  local iterators = {...}
  local chain
  for i = #iterators, 1, -1 do
    chain = {
      func = iterators[i][1],
      state = iterators[i][2],
      value = iterators[i][3],

      next = chain,
    }
  end

  if not chain then
    return iter.singleton(nil)
  end

  return chain_iterator, chain, chain.value
end

local function subiter_iterator(state)
  local inner_values = {state.inner_f(state.inner_state, state.inner_value)}
  while inner_values[1] == nil do
    local first_inner_value

    state.outer_values = {state.outer_f(state.outer_state, state.outer_values[1])}
    if state.outer_values[1] == nil then
      return
    end

    state.inner_f, state.inner_state, first_inner_value = state.create_inner_iter(table.unpack(state.outer_values))

    inner_values = {state.inner_f(state.inner_state, first_inner_value)}
  end

  state.inner_value = inner_values[1]

  local all_values = {table.unpack(state.outer_values)}
  for i = 1, #inner_values do
    all_values[#all_values + 1] = inner_values[i]
  end

  return table.unpack(all_values)
end

function iter.subiter(outer_iter, iter_f)
  local outer_f, outer_state, outer_value = table.unpack(outer_iter)
  local outer_values = {outer_f(outer_state, outer_value)}
  local inner_f, inner_state, first_inner_value = iter_f(table.unpack(outer_values))

  -- XXX if outer_values[1] is nil, do we abort early here?

  local state = {
    outer_f = outer_f,
    outer_state = outer_state,
    outer_values = outer_values,

    create_inner_iter = iter_f,
    inner_f = inner_f,
    inner_state = inner_state,
    inner_value = first_inner_value,
  }

  return subiter_iterator, state
end

return iter
