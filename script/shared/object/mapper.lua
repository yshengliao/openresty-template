local _M = {}

local TYPE_STRING   = type("")
local TYPE_TABLE    = type({})
local TYPE_FUNCTION = type(function() end)


do
  local function _get_mapper(obj)
    if type(obj) == TYPE_TABLE  and  type(obj.tovalue) == TYPE_FUNCTION then
      return obj
    end
  end


  function _M.map(obj, struct)
    local mapper = _get_mapper(struct)
    if mapper then
      return mapper.tovalue(obj)
    elseif type(struct) == TYPE_TABLE then
      local item = {}
      for k, v in pairs(struct) do
        local item_mapper = _get_mapper(v)
        if item_mapper then
          item[k] = item_mapper.tovalue(obj)
        elseif type(v) == TYPE_TABLE then
          item[k] = _M.map(obj, v)
        elseif type(v) == TYPE_STRING then
          item[k] = obj[v]
        end
      end
      -- has items?
      if next(item) then
        return item
      end
    end
  end

  function _M.Action(action)
    return {
      tovalue = action
    }
  end

  function _M.path(...)
    local args = {...}
    return {
      tovalue = function(obj)
        if type(obj) == TYPE_TABLE then
          local node = obj
          for _, k in ipairs(args) do
            if node == nil then
              break
            end
            node = node[k]
          end
          return node
        end
      end
    }
  end

  function _M.StringMapper(field)
    return {
      tovalue = function(obj)
        if type(obj) == TYPE_TABLE then
          return tostring(obj[field])
        end
      end
    }
  end

  function _M.ScalarMapper(field)
    return {
      tovalue = function(obj)
        if type(obj) == TYPE_TABLE then
          return obj[field]
        end
      end
    }
  end

  function _M.ObjectMapper(field, struct)
    assert(type(struct) == TYPE_TABLE, "parameter 'struct' must be of type table")

    return {
      tovalue = function(obj)
        if type(obj) ~= TYPE_TABLE then
          return
        end

        local source = obj[field]
        if type(source) == TYPE_TABLE then
          local reply = {}

          for k, v in pairs(struct) do
            local mapper = _get_mapper(v)
            if mapper then
              reply[k] = mapper.tovalue(source)
            elseif type(v) == TYPE_STRING then
              reply[k] = source[v]
            end
          end
          return reply
        end
      end
    }
  end

  function _M.ListMapper(field, struct)
    return {
      tovalue = function(obj)
        if type(obj) ~= TYPE_TABLE then
          return
        end

        local source
        if field == nil then
          source = obj
        elseif type(field) == TYPE_STRING  then
          source = obj[field]
        end
        if type(source) == TYPE_TABLE then
          local reply = {}

          local mapper = _get_mapper(struct)
          if mapper then
            for _, elem in ipairs(source) do
              reply[#reply+1] = mapper.tovalue(elem)
            end
          elseif type(struct) == TYPE_TABLE then
            for _, elem in ipairs(source) do
              local item = _M.map(elem, struct)
              -- has items?
              if next(item) then
                reply[#reply+1] = item
              end
            end
          end
          return reply
        end
      end
    }
  end
end
return _M
