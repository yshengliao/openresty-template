local NULL = ngx.null

local _M = {}


do
  -- misc
  do
    function _M.coalesce(...)
      local arg = {...}
      if arg then
        if type(arg) == "table" and next(arg) then
          for i = 1, #arg do
            if arg[i] and arg[i] ~= NULL then
              return arg[i]
            end
          end
        end
      end
      return nil
    end

    function _M.join_path(dir, path)
      if path == nil  or  path == "" then
        return dir
      end
      if dir == nil  or  dir == "" then
        return path
      end
      if type(dir)~="string" or  type(path)~="string"  then
        return nil
      end

      if string.sub(path, 1, 1) == "/"  or  string.sub(path, 1, 1) == "\\"  then
        if string.sub(dir, -1) == "/"  or  string.sub(dir, -1) == "\\"  then
          return string.sub(dir, 1, -2) .. path
        end
        return dir .. path
      end
      if string.sub(dir, -1) == "/"  or  string.sub(dir, -1) == "\\"  then
        return dir .. path
      end
      return dir .. "/" .. path
    end
  end


  -- string
  do
    function _M.string_start_with(s, prefix)
      return string.sub(s, 1, string.len(prefix)) == prefix
    end


    function _M.is_nil_or_empty_string(v)
      return (v == nil) or (v == "")
    end


    function _M.string_split(str,reps)
      local resultStrList = {}
      if _M.is_nil_or_empty_string(str) then
        return resultStrList
      end

      string.gsub(str,'[^'..reps..']+',function (w)
          table.insert(resultStrList,w)
      end)
      return resultStrList
    end
  end


  -- table
  do
    -- table dump_proc
    local dump_proc
    do
      local _dump   -- use dump()
      local dump_array_elem = function(k, v) return _dump(v) end
      local dump_map_entry  = function(k, v) return string.format("%s: %s", k, _dump(v)) end


      local function is_array(t)
        assert(type(t)=="table", "specified argument t must be of type array")
        return #t > 0
      end


      local function dump(t)
        if type(t) == 'table' then
          local dump_elem = is_array(t) and dump_array_elem or dump_map_entry
          local set  = {}
          for k,v in pairs(t) do
            set[#set+1] = dump_elem(k, v)
          end

          local content = table.concat(set, ", ")
          if is_array(t) then
            return "[" .. content .. "]"
          end
          return "{" .. content .. "}"
        end
        return tostring(t)
      end

      -- set _dump
      _dump = dump

      -- export
      dump_proc = dump
    end


    function _M.normalize_field_value_args(args, fields)
      if type(args) ~= "table" then
        return
      end

      local result = {}
      if #args > 0 then
        for i = 1, #args, 2 do
          local k, v = args[i], args[i+1]
          if v then
            result[#result+1] = k
            result[#result+1] = v
          end
        end
      else
        if fields  and  type(fields) == "table"  then
          for i = 1, #fields do
            local k = fields[i]
            local v = args[k]
            if v then
              result[#result+1] = k
              result[#result+1] = v
            end
          end
        else
          for k, v in pairs(args) do
            if v then
              result[#result+1] = k
              result[#result+1] = v
            end
          end
        end
      end
      return result
    end


    function _M.merge_table(...)
      local argv   = {...}

      if #argv == 0 then
        return nil
      end
      if #argv == 1 then
        return argv[1]
      end

      local result = { unpack(argv[1]) }
      for i = 2, #argv do
        local array = argv[i]
        if type(array)=="table" then
          for ii = 1, #array do
            result[#result+1] = array[ii]
          end
        end
      end
      return result
    end


    function _M.deep_clone(v)
      local function _copy(obj, seen)
        -- Handle non-tables and previously-seen tables.
        if type(obj) ~= 'table' then
          return obj
        end
        if seen and seen[obj] then
          return seen[obj]
        end

        -- New table; mark it as seen an copy recursively.
        local s = seen or {}
        local res = {}
        s[obj] = res
        for key, val in next, obj do
          res[_copy(key, s)] = _copy(val, s)
        end
        return setmetatable(res, getmetatable(obj))
      end
      return _copy(v)
    end


    function _M.reverse_items(t)
      local n = #t
      for i = 1, n/2 do
        t[i],t[n] = t[n],t[i]

        n = n - 1
      end
    end


    function _M.dump_table(t)
      return dump_proc(t)
    end
  end
end
return _M
