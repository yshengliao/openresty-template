local _M = { _VERSION = "0.1" }

local ngx_null      = _G.ngx  and  _G.ngx.null  or  nil
local band          = bit.band
local tostring      = tostring
local tonumber      = tonumber
local byte          = string.byte
local char          = string.char
local gsub          = string.gsub
local gmatch        = string.gmatch
local pairs         = pairs
local ipairs        = ipairs
local table_concat  = table.concat
local sort          = table.sort


local ERR_INVALID_JSON       = 'ERR_INVALID_JSON'
local ERR_INVALID_ESCAPE     = 'ERR_INVALID_ESCAPE'
local ERR_INVALID_UNICODE    = 'ERR_INVALID_UNICODE'
local ERR_MISSING_CLOSE      = 'ERR_MISSING_CLOSE'
local ERR_UNSUPPORTED_TYPE   = 'ERR_UNSUPPORTED_TYPE'
local ERR_UNSUPPORTED_MAPPER = 'ERR_UNSUPPORTED_MAPPER'
local ERR_INVALID_MAPPER     = 'ERR_INVALID_MAPPER'
local ERR_INVALID_NUMBER     = 'ERR_INVALID_NUMBER'

local TYPE_SCALAR_MAPPER = 'scalar'
local TYPE_ARRAY_MAPPER  = 'array'
local TYPE_OBJECT_MAPPER = 'object'


local _new_table
-- Utf8
local _utf8
-- Number
local _is_number
local _create_number
-- Mapper
local _is_mapper

-- new_table
do
  local ok, new_table = pcall(require, "table.new")
  if not ok then
    new_table = function (narr, nrec) return {} end
  end

  -- export
  _new_table = new_table
end

-- Utf8
do
  local bytemarkers = { {0x7FF,192}, {0xFFFF,224}, {0x1FFFFF,240} }
  local function utf8(decimal)
    if decimal<128 then return char(decimal) end
    local charbytes = {}
    for bytes,vals in ipairs(bytemarkers) do
      if decimal<=vals[1] then
        for b=bytes+1,2,-1 do
          local mod = decimal%64
          decimal = (decimal-mod)/64
          charbytes[b] = char(128+mod)
        end
        charbytes[1] = char(vals[2]+decimal)
        break
      end
    end
    return table_concat(charbytes)
  end

  -- exports
  _utf8 = utf8
end


-- Number
do
  local NUMBER = {}
  local NUMBER_mt = { __index = NUMBER }


  local function _get_invalid_number_error(v)
    return string.format("[%s] %% invalid number '%s'", ERR_INVALID_NUMBER, v)
  end


  local function _create(v)
    if type(v) == 'nil' then
      v = nil
    elseif _is_number(v) then
      return v
    elseif type(v) == 'number' then
      v = tostring(v)
    elseif type(v) == 'string' then
      if v:len() == 0  or  v == 'null' then
        v = nil
      elseif tonumber(v) then
        v = v
      else
        return nil, _get_invalid_number_error(v)
      end
    else
      return nil, _get_invalid_number_error(v)
    end
    return setmetatable({
      v = v,
    }, NUMBER_mt)
  end

  function NUMBER.number(self)
    assert(self)

    if self.v then
      return tonumber(self.v)
    end
    return nil
  end

  function NUMBER.string(self)
    assert(self)

    if self.v then
      return tostring(self.v)
    end
    return nil
  end

  function NUMBER.is_zero(self)
    assert(self)

    if self.v then
      return tonumber(self.v) == 0
    end
    return false
  end

  function NUMBER.equals(self, another)
    if self then
      if _is_number(another) then
        return self.v == another.v
      end
    end
    return false
  end

  function NUMBER_mt.__tostring(self)
    return NUMBER.string(self)
  end

  function NUMBER_mt.__eq(self, another)
    return NUMBER.equals(self, another)
  end

  -- implement
  _create_number = _create
  _is_number = function(obj)
    return type(obj) == 'table'  and  getmetatable(obj) == NUMBER_mt
  end


  -- exports
  _M.Number = NUMBER
end


-- Mapper
do
  local MAPPER = {}
  local MAPPER_mt = {}

  function MAPPER.scalar(name)
    return setmetatable({
      type = TYPE_SCALAR_MAPPER,
      name = name,
    }, MAPPER_mt)
  end

  function MAPPER.array(name, elem_mapper)
    return setmetatable({
      type = TYPE_ARRAY_MAPPER,
      name = name,
      mapper = elem_mapper,
    }, MAPPER_mt)
  end

  function MAPPER.object(name, mappers)
    if mappers then
      assert(type(mappers)=='table', "argument 'mappers' must be type 'table'")
      if next(mappers) then
        assert(#mappers > 0, "argument 'mappers' must be array")
      end
    end

    return setmetatable({
      type = TYPE_OBJECT_MAPPER,
      name = name,
      mapper = mappers or {},
    }, MAPPER_mt)
  end


  -- implement
  _is_mapper = function(obj, typ)
    local ok = (type(obj) == 'table'  and  getmetatable(obj) == MAPPER_mt)
    if ok then
      if typ then
        return obj.type == typ
      end
    end
    return ok
  end

  -- exports
  _M.Mapper = MAPPER
end


-- decode
do
  local OBJECT_START_DELIM = '{'
  local OBJECT_CLOSE_DELIM = '}'

  local ARRAY_START_DELIM  = '['
  local ARRAY_CLOSE_DELIM  = ']'

  local STRING_START_DELIM = '"'
  local STRING_CLOSE_DELIM = '"'

  local ESCAPE_CHAR = '\\'
  local PLUS_CHAR   = '+'
  local MINUS_CHAR  = '-'
  local ZERO_CHAR   = '0'
  local NINE_CHAR   = '9'
  local DOT_CHAR    = '.'
  local COLON_CHAR  = ':'
  local COMMA_CHAR  = ','
  local EXPONENT_LOWER_CHAR = 'e'
  local EXPONENT_UPPER_CHAR = 'E'

  local SPACE   = 'SPACE'
  local KEYWORD = 'KEYWORD'
  local NUMBER  = 'NUMBER'
  local STRING  = 'STRING'
  local ARRAY   = 'ARRAY'
  local OBJECT  = 'OBJECT'

  local DELIMITER_TABLE = { false ,false  ,false ,false ,false ,false  ,false ,false ,SPACE ,SPACE  ,
                            false ,false  ,SPACE ,false ,false ,false  ,false ,false ,false ,false  ,
                            false ,false  ,false ,false ,false ,false  ,false ,false ,false ,false  ,
                            false ,SPACE  ,false ,STRING,false ,false  ,false ,false ,false ,false  ,
                            false ,false  ,false ,false ,NUMBER,false  ,false ,NUMBER,NUMBER,NUMBER ,
                            NUMBER,NUMBER ,NUMBER,NUMBER,NUMBER,NUMBER ,NUMBER,false ,false ,false  ,
                            false ,false  ,false ,false ,false ,false  ,false ,false ,false ,false  ,
                            false ,false  ,false ,false ,false ,false  ,false ,false ,false ,false  ,
                            false ,false  ,false ,false ,false ,false  ,false ,false ,false ,false  ,
                            ARRAY ,false  ,false ,false ,false ,false  ,false ,false ,false ,false  ,
                            false ,KEYWORD,false ,false ,false ,false  ,false ,false ,false ,KEYWORD,
                            false ,false  ,false ,false ,false ,KEYWORD,false ,false ,false ,false  ,
                            false ,false  ,OBJECT,false ,false ,false  ,false ,
                          }

  local ESCAPE_CHAR_TABLE = { false, false, false, false, false, false, false, false, false, false,
                              false, false, false, false, false, false, false, false, false, false,
                              false, false, false, false, false, false, false, false, false, false,
                              false, false, false, '"'  , false, false, false, false, false, false,
                              false, false, false, false, false, false, '/'  , false, false, false,
                              false, false, false, false, false, false, false, false, false, false,
                              false, false, false, false, false, false, false, false, false, false,
                              false, false, false, false, false, false, false, false, false, false,
                              false, false, false, false, false, false, false, false, false, false,
                              false, '\\' , false, false, false, false, false, '\b' , false, false,
                              false, '\f' , false, false, false, false, false, false, false, '\n' ,
                              false, false, false, '\r' , false, '\t' ,
                            }


  local RESERVED_WORDS = {
    ['n'] = 'null',
    ['f'] = 'false',
    ['t'] = 'true',
  }

  local KEYWORD_VALUES = {
    ['null' ] = nil,
    ['false'] = false,
    ['true' ] = true,
  }

  local NUMBER_RESOLVE_FLAG = {
    INTEGER          = 1,
    FRACTION         = 2,
    EXPONENT         = 3,
    EXPONENT_INTEGER = 4,
  }

  local ARRAY_RESOLVE_FLAG = {
    START = 0,
    ELEM  = 1,
    END   = 2,
  }

  local OBJECT_RESOLVE_FLAG = {
    START = 0,
    KEY   = 1,
    COLON = 2,
    VALUE = 3,
    END   = 4,
  }

  local decode
  do
    local function _get_token(c)
      return DELIMITER_TABLE[ byte(c) ]
    end

    local function _get_parser_error(err, chr, pos)
      return string.format("[%s] %% char(0x%x) at %d", err, byte(chr), pos)
    end

    local function _get_missing_close_error()
      return string.format("[%s] %% missing closing delimiter", ERR_MISSING_CLOSE)
    end

    -- State
    local STATE = {}
    do
      local STATE_mt = { __index = STATE }

      function STATE.new(opt)
        return setmetatable({
          resolver  = nil,
          states    = {},
          pos       = 0,
          eof       = false,
          opt       = opt or {},
        }, STATE_mt)
      end

      function STATE.is_empty(self)
        return (self.resolver == nil  and  #self.states == 0)
      end

      function STATE.get_resolver(self)
        return self.resolver
      end

      function STATE.set_resolver(self, resolver)
        if type(resolver) == 'function' then
          self.resolver = resolver
          return true
        end
        return false
      end

      function STATE.clear_resolver(self)
        self.resolver = nil
      end

      function STATE.get(self)
        local states = self.states
        return states[#states]
      end

      function STATE.push(self, state)
        assert(state ~= nil, "invalid argument 'state'")

        local states = self.states
        states[#states+1] = state
      end

      function STATE.pop(self)
        local states = self.states
        local state = states[#states]
        states[#states] = nil
        return state
      end
    end


    local RESOLVER
    do
      RESOLVER = {
        [SPACE] = function(state, c, write)
          return true
        end,
        [KEYWORD] = function(store, c, write, isnew)
          if isnew then
            store:push({
              buffer = ""
            })
          end
          local state = store:get()
          state.buffer = state.buffer..c
          local buffer = state.buffer

          local word = RESERVED_WORDS[ string.sub(buffer, 1, 1) ]
          if #buffer > 1 then
            if buffer == word  then
              store:pop()
              return write(KEYWORD_VALUES[word])
            elseif string.sub(word, 1, #buffer) ~= buffer then
              return nil, ERR_INVALID_JSON
            end
          elseif not word then
            return nil, ERR_INVALID_JSON
          end
          return false
        end,
        [NUMBER] = function(store, c, write, isnew)
          if isnew then
            store:push({
              flag   = nil,
              buffer = "",
            })
          end
          local state = store:get()

          do
            if not state.flag then
              state.flag = NUMBER_RESOLVE_FLAG.INTEGER
              if c == MINUS_CHAR then
                state.buffer = state.buffer..c
                return false
              end
            end

            if state.flag == NUMBER_RESOLVE_FLAG.INTEGER then
              if c >= ZERO_CHAR  and  c <= NINE_CHAR then
                if state.buffer == "-0" or state.buffer == "0" then
                  return nil, ERR_INVALID_JSON
                end
                state.buffer = state.buffer..c
                if store.eof then
                  goto process_write
                end
              elseif c == DOT_CHAR then
                state.buffer = state.buffer..c
                state.flag = NUMBER_RESOLVE_FLAG.FRACTION
              elseif c == EXPONENT_LOWER_CHAR  or  c == EXPONENT_UPPER_CHAR then
                state.buffer = state.buffer..c
                state.flag = NUMBER_RESOLVE_FLAG.EXPONENT
              else
                goto process_write
              end
              return false
            end

            if state.flag == NUMBER_RESOLVE_FLAG.FRACTION then
              if c >= ZERO_CHAR  and  c <= NINE_CHAR then
                state.buffer = state.buffer..c
                if store.eof then
                  goto process_write
                end
              elseif c == EXPONENT_LOWER_CHAR  or  c == EXPONENT_UPPER_CHAR then
                local buffer = state.buffer
                local rear = string.sub(buffer, -1)
                if #buffer == 0  or  rear < ZERO_CHAR  or  rear > NINE_CHAR then
                  return nil, ERR_INVALID_JSON
                end
                state.buffer = state.buffer..c
                state.flag = NUMBER_RESOLVE_FLAG.EXPONENT
              else
                goto process_write
              end
              return false
            end

            if state.flag == NUMBER_RESOLVE_FLAG.EXPONENT then
              state.flag = NUMBER_RESOLVE_FLAG.EXPONENT_INTEGER
              if c == MINUS_CHAR  or  c == PLUS_CHAR then
                state.buffer = state.buffer..c
                return false
              end
            end

            if state.flag == NUMBER_RESOLVE_FLAG.EXPONENT_INTEGER then
              if c >= ZERO_CHAR  and  c <= NINE_CHAR then
                state.buffer = state.buffer..c
                if store.eof then
                  goto process_write
                end
              else
                goto process_write
              end
            end
            return false
          end

          ::process_write::
          local buffer = state.buffer
          local rear = string.sub(buffer, -1)
          if #buffer == 0  or  rear < ZERO_CHAR  or  rear > NINE_CHAR then
            return nil, ERR_INVALID_JSON
          end

          local value
          if store.opt.use_json_number  then
            local err
            value, err = _create_number(buffer)
            if err then
              return nil, err
            end
          else
            value = tonumber(buffer, 10)
          end
          store:pop()
          if not store.eof or  c < ZERO_CHAR  or  c > NINE_CHAR then
            return write(value), c
          end
          return write(value)
        end,
        [STRING] = function(store, c, write, isnew)
          if isnew then
            store:push({
              start_delimiter = nil,    -- '"'
              escape          = nil,    -- '\' or 'u'
              escape_unicode  = "",
              buffer          = ""
            })
          end
          local state = store:get()

          if not state.start_delimiter then
            state.start_delimiter = c
            return false
          end

          if state.escape then
            if state.escape == 'u' then
              state.escape_unicode = (state.escape_unicode or "")..c
              if #state.escape_unicode == 4 then
                local code = tonumber(state.escape_unicode, 16)
                if not code then
                  return nil, ERR_INVALID_UNICODE -- invalid char %c at %d
                end
                state.escape_unicode = nil
                state.escape = nil
                state.buffer = state.buffer.._utf8(code)
              end
            else
              if c == 'u' then
                state.escape = c
              else
                local b = byte(c)
                c = ESCAPE_CHAR_TABLE[b]
                if not c then
                  return nil, ERR_INVALID_ESCAPE -- invalid char %c at %d
                end
                state.escape = nil
                state.buffer = state.buffer..c
              end
            end
            return false
          end

          if c == STRING_CLOSE_DELIM then
            local buffer = state.buffer
            store:pop()
            return write(buffer)
          elseif c == ESCAPE_CHAR then
            state.escape = c
          else
            state.buffer = state.buffer..c
          end
          return false
        end,
        [ARRAY] = function(store, c, write, isnew)
          if isnew then
            store:push({
              flag            = nil,
              store           = STATE.new(store.opt),
              buffer          = {},
            })
          end
          ::start::
          local state = store:get()
          -- populate 'pos' and 'eof' value form parent
          state.store.pos = store.pos
          state.store.eof = store.eof

          if not state.flag then
            -- assert(c == ARRAY_START_DELIM)
            state.flag = ARRAY_RESOLVE_FLAG.START
            return false
          end

          if state.flag == ARRAY_RESOLVE_FLAG.START then
            if c == ARRAY_CLOSE_DELIM then
              store:pop()
              return write(state.buffer)
            else
              local token = _get_token(c)
              if token == SPACE then
                return false
              elseif token then
                state.flag = ARRAY_RESOLVE_FLAG.ELEM
              end
            end
          end

          -- resolve elem
          if state.flag == ARRAY_RESOLVE_FLAG.ELEM then
            local elem_writer = function(v)
              state.buffer[#state.buffer+1] = v
              return true
            end

            local is_new_token = false
            local resolve = state.store:get_resolver()
            if not resolve then
              local token = _get_token(c)
              if token == SPACE then
                return false
              end
              if not token then
                return nil, ERR_INVALID_JSON
              end

              resolve = RESOLVER[token]
              -- assert(resolve, "'resolve' should not be nil")
              is_new_token = state.store:set_resolver(resolve)
            end

            -- assert(resolve, "'resolve' should not be nil")
            local ok, res = resolve(state.store, c, elem_writer, is_new_token)
            if not ok then
              local err = res
              if err then
                return nil, err
              end
              if store.eof then
                return nil, ERR_INVALID_JSON
              end
            end

            if ok then
              state.store:clear_resolver()
              state.flag = ARRAY_RESOLVE_FLAG.END
              if res then
                goto start
              end
            end
            return false
          end

          if state.flag == ARRAY_RESOLVE_FLAG.END then
            if c == ARRAY_CLOSE_DELIM then
              store:pop()
              return write(state.buffer)
            elseif c == COMMA_CHAR then
              state.flag = ARRAY_RESOLVE_FLAG.ELEM
              return false
            else
              local token = _get_token(c)
              if token == SPACE then
                return false
              end
              if not token then
                return nil, ERR_INVALID_JSON.."_487"
              end
            end
          end

        end,
        [OBJECT] = function(store, c, write, isnew)
          if isnew then
            store:push({
              flag            = nil,
              candidate_key   = nil,
              store           = STATE.new(store.opt),
              buffer          = {},
            })
          end
          ::start::
          local state = store:get()
          -- populate 'pos' and 'eof' value form parent
          state.store.pos = store.pos
          state.store.eof = store.eof

          if not state.flag then
            -- assert(c == OBJECT_START_DELIM)
            state.flag = OBJECT_RESOLVE_FLAG.START
            return false
          end

          if state.flag == OBJECT_RESOLVE_FLAG.START then
            if c == OBJECT_CLOSE_DELIM then
              store:pop()
              return write(state.buffer)
            else
              local token = _get_token(c)
              if token == SPACE then
                return false
              elseif token == STRING then
                state.flag = OBJECT_RESOLVE_FLAG.KEY
              else
                return nil, ERR_INVALID_JSON
              end
            end
          end

          -- resolve key
          if state.flag == OBJECT_RESOLVE_FLAG.KEY then
            local key_writer = function(v)
              state.candidate_key = v
              return true
            end

            local is_new_token = false
            local resolve = state.store:get_resolver()
            if not resolve then
              local token = _get_token(c)
              if token == SPACE then
                return false
              end
              if not token then
                return nil, ERR_INVALID_JSON
              end

              if token ~= STRING then
                return nil, ERR_INVALID_JSON
              end

              resolve = RESOLVER[token]
              -- assert(resolve, "'resolve' should not be nil")
              is_new_token = state.store:set_resolver(resolve)
            end

            -- assert(resolve, "'resolve' should not be nil")
            local ok, res = resolve(state.store, c, key_writer, is_new_token)
            if not ok then
              local err = res
              if err then
                return nil, err
              end
              if store.eof then
                return nil, ERR_INVALID_JSON
              end
            end

            if ok then
              state.store:clear_resolver()
              state.flag = OBJECT_RESOLVE_FLAG.COLON
            end
            return false
          end

          -- resolve colon
          if state.flag == OBJECT_RESOLVE_FLAG.COLON then
            if c == COLON_CHAR then
              state.flag = OBJECT_RESOLVE_FLAG.VALUE
              return false
            end

            local token = _get_token(c)
            if token == SPACE then
              return false
            end
            if not token then
              return nil, ERR_INVALID_JSON
            end
          end

          -- resolve value
          if state.flag == OBJECT_RESOLVE_FLAG.VALUE then
            local value_writer = function(v)
              local key = state.candidate_key
              state.candidate_key = nil
              state.buffer[key] = v
              return true
            end

            local is_new_token = false
            local resolve = state.store:get_resolver()
            if not resolve then
              local token = _get_token(c)
              if token == SPACE then
                return false
              end
              if not token then
                return nil, ERR_INVALID_JSON
              end

              resolve = RESOLVER[token]
              -- assert(resolve, "'resolve' should not be nil")
              is_new_token = state.store:set_resolver(resolve)
            end
            -- assert(resolve, "'resolve' should not be nil")
            local ok, res = resolve(state.store, c, value_writer, is_new_token)
            if not ok then
              local err = res
              if err then
                return nil, err
              end
              if store.eof then
                return nil, ERR_INVALID_JSON
              end
            end

            if ok then
              state.store:clear_resolver()
              state.flag = OBJECT_RESOLVE_FLAG.END
              if res then
                goto start
              end
            end
            return false
          end

          if state.flag == OBJECT_RESOLVE_FLAG.END then
            if c == OBJECT_CLOSE_DELIM then
              store:pop()
              return write(state.buffer)
            elseif c == COMMA_CHAR then
              state.flag = OBJECT_RESOLVE_FLAG.KEY
              return false
            else
              local token = _get_token(c)
              if token == SPACE then
                return false
              end
              if not token then
                return nil, ERR_INVALID_JSON
              end
            end
          end

        end,
      }
    end


    local function parse(str, opt)
      local started = false
      local store = STATE.new(opt)
      local reminder

      local result
      local writer = function(v)
        result = v
        return true
      end

      for c in gmatch(str, ".") do
        store.pos = store.pos + 1
        store.eof = store.pos >= #str

        local is_new_token = false
        if not started then
          local token = _get_token(c)
          if not token then
            return nil, _get_parser_error(ERR_INVALID_JSON, c, store.pos)
          end

          if token ~= SPACE then
            local resolve = RESOLVER[token]
            -- assert(resolve, "'resolve' should not be nil")
            is_new_token = store:set_resolver(resolve)
            started = true
          end
        end

        local resolve = store:get_resolver()
        if resolve then
          -- assert(resolve, "'resolve' should not be nil")
          local ok, res = resolve(store, c, writer, is_new_token)

          if not ok then
            local err = res
            if err then
              return nil, _get_parser_error(err, c, store.pos)
            end

            if store.eof then
              return nil, _get_parser_error(ERR_INVALID_JSON, c, store.pos)
            end
          end

          if ok then
            store:clear_resolver()
            reminder = res
            if not res then
              if not store.eof then
                store.pos = store.pos + 1
              end
            end
            break
          end
        end
      end

      if not store:is_empty() then
        return nil, _get_missing_close_error()
      end

      -- check if reminder characters are all white spaces
      if not store.eof then
        local tail = string.sub(str, store.pos)

        for c in gmatch(tail, '.') do
          local token = _get_token(c)
          if token ~= SPACE then
            return nil, _get_parser_error(ERR_INVALID_JSON, c, store.pos)
          end
          store.pos = store.pos + 1
        end
      end

      if reminder then
        local token = _get_token(reminder)
        if token ~= SPACE then
          return nil, _get_parser_error(ERR_INVALID_JSON, reminder, store.pos)
        end
      end

      if not started then
        return nil, _get_missing_close_error()
      end

      return result
    end


    -- https://www.ietf.org/rfc/rfc4627.txt
    decode = function(str, opt)
      -- Insignificant whitespace is allowed before or after any of the six
      -- structural characters
      -- These are the six structural characters:

      --  begin-array     = ws %x5B ws  ; [ left square bracket
      --  begin-object    = ws %x7B ws  ; { left curly bracket
      --  end-array       = ws %x5D ws  ; ] right square bracket
      --  end-object      = ws %x7D ws  ; } right curly bracket
      --  name-separator  = ws %x3A ws  ; : colon
      --  value-separator = ws %x2C ws  ; , comma

      local size = #str
      if size == 0 then
        return nil, ERR_INVALID_JSON
      end

      return parse(str, opt)
    end
  end


  -- exports
  _M.decode = decode
end


-- encode
do
  local META_CHARS = {
    ['"' ] = '\\"',
    ["/" ] = "\\/",
    ["\\"] = "\\\\",
    ['\r'] = '\\r',
    ['\n'] = '\\n',
    ['\t'] = '\\t',
    ['\b'] = '\\b',
  }

  local TYPE_NIL         = type(nil)
  local TYPE_BOOLEAN     = type(true)
  local TYPE_NUMBER      = type(0)
  local TYPE_STRING      = type("")
  local TYPE_JSON_NUMBER = "json_number"
  local TYPE_TABLE       = type({})
  local TYPE_USERDATA    = "userdata"


  local VALUE_TYPE_FLAGS = {
    [TYPE_NIL        ] = 0x01,
    [TYPE_BOOLEAN    ] = 0x02,
    [TYPE_NUMBER     ] = 0x04,
    [TYPE_STRING     ] = 0x08,
    [TYPE_JSON_NUMBER] = 0x10,
    [TYPE_TABLE      ] = 0x20,
  }

  local MAPPER_TYPE_MASKS = {
    [TYPE_SCALAR_MAPPER] = VALUE_TYPE_FLAGS[TYPE_NIL]
                         + VALUE_TYPE_FLAGS[TYPE_BOOLEAN]
                         + VALUE_TYPE_FLAGS[TYPE_NUMBER]
                         + VALUE_TYPE_FLAGS[TYPE_STRING]
                         + VALUE_TYPE_FLAGS[TYPE_JSON_NUMBER],
    [TYPE_ARRAY_MAPPER ] = VALUE_TYPE_FLAGS[TYPE_TABLE],
    [TYPE_OBJECT_MAPPER] = VALUE_TYPE_FLAGS[TYPE_TABLE],
  }

  local NULL_LITERAL = 'null'


  local function _encode_str(s)
      -- XXX we will rewrite this when string.buffer is implemented
      -- in LuaJIT 2.1 because string.gsub cannot be JIT compiled.
      return gsub(s, '["/\\\r\n\t\b]', META_CHARS)
  end

  local function _is_array(t)
      local exp = 1
      for k, _ in pairs(t) do
          if k ~= exp then
              return nil
          end
          exp = exp + 1
      end
      return exp - 1
  end

  local function _get_type(v)
    if v == ngx_null then
      return TYPE_NIL
    end
    if _is_number(v) then
      return TYPE_JSON_NUMBER
    end
    return type(v)
  end

  local function _check_value_mapper(v, mapper_type)
    local valut_type = _get_type(v)
    local flag = VALUE_TYPE_FLAGS[valut_type]
    assert(flag, string.format("unknown value type %s", valut_type))
    local mask = MAPPER_TYPE_MASKS[mapper_type]
    assert(mask, string.format("unknown mapper type %s", mapper_type))

    return flag == band(flag, mask)
  end

  local encode
  do
    local function _get_unsupported_type_error(typ)
      return string.format("[%s] %% unsupported type '%s'", ERR_UNSUPPORTED_TYPE, typ)
    end

    local function _get_unsupported_mapper_error(field, typ)
      if not field then
        return string.format("[%s] %% unsupported mapper '%s' on root", ERR_UNSUPPORTED_MAPPER, typ)
      end
      return string.format("[%s] %% unsupported mapper '%s' on '%s'", ERR_UNSUPPORTED_MAPPER, typ, field)
    end

    local function _get_invalid_mapper_error(v, typ, mapper_type)
      return string.format("[%s] %% cannot encode %s '%s' with mapper '%s'", ERR_INVALID_MAPPER, typ, v, mapper_type)
    end


    local SCALAR_ENCODER = {
      [TYPE_NIL] = function(v)
        return NULL_LITERAL
      end,
      [TYPE_STRING] = function(v)
        return '"' .. _encode_str(v) .. '"'
      end,
      [TYPE_NUMBER] = function(v)
        return tostring(v)
      end,
      [TYPE_BOOLEAN] = function(v)
        return tostring(v)
      end,
      [TYPE_JSON_NUMBER] = function(v)
        return v:string()
      end,
      [TYPE_USERDATA] = function(v)
        return NULL_LITERAL
      end
    }


    encode = function(v, mapper)
      local typ = _get_type(v)
      local stringify = SCALAR_ENCODER[typ]
      if stringify then
        if not mapper  or  _is_mapper(mapper, TYPE_SCALAR_MAPPER) then
          return stringify(v)
        end
        if _is_mapper(mapper) then
          return nil, _get_invalid_mapper_error(v, typ, mapper.type)
        end
        return nil, ERR_INVALID_MAPPER
      end

      if typ == TYPE_TABLE then
        local n = _is_array(v)
        if n then
          if mapper then
            if not _is_mapper(mapper, TYPE_ARRAY_MAPPER) then
              local mapper_type = _is_mapper(mapper) and mapper.type or type(mapper)
              return nil, _get_invalid_mapper_error(v, typ, mapper_type)
            end
          end

          if (n > 0)  or  ( n == 0  and  _is_mapper(mapper, TYPE_ARRAY_MAPPER) ) then
            local elem_mapper = mapper and mapper.mapper or nil
            local bits = _new_table(n, 0)
            for i, elem in ipairs(v) do
              local value, err = encode(elem, elem_mapper)
              if err then
                return nil, err
              end
              bits[i] = value
            end
            return "[" .. table_concat(bits, ",") .. "]"
          end
        end

        if not mapper then
          local bits = {}
          local i = 0
          for key, value in pairs(v) do
            i = i + 1
            bits[i] = encode(key) .. ":" .. encode(value)
          end
          return "{" .. table_concat(bits, ",") .. "}"
        else
          local mappers
          if type(mapper) == TYPE_TABLE then
            if _is_mapper(mapper) then
              if mapper.type == TYPE_OBJECT_MAPPER then
                mappers = mapper.mapper
              else
                return nil, _get_invalid_mapper_error(v, typ, mapper.type)
              end
            else
              mappers = mapper
            end
          else
            return nil, _get_invalid_mapper_error(v, typ, type(mapper))
          end


          if type(mappers) == TYPE_TABLE  then
            local bits = {}
            for i, m in ipairs(mappers) do
              local key = m.name
              local t   = m.type
              local value = v[key]

              if not _check_value_mapper(value, t) then
                return nil, _get_invalid_mapper_error(value, type(value), t)
              end

              if not t  or  t == TYPE_SCALAR_MAPPER then
                bits[i] = encode(key) .. ":" .. encode(value)
              elseif t == TYPE_OBJECT_MAPPER then
                local str, err = encode(value, m.mapper)
                if err then
                  return nil, _get_invalid_mapper_error(value, typ, t)
                end
                bits[i] = encode(key) .. ":" .. str
              elseif t == TYPE_ARRAY_MAPPER then
                local str, err = encode(value, m)
                if err then
                  return nil, _get_invalid_mapper_error(value, typ, t)
                end
                bits[i] = encode(key) .. ":" .. str
              else
                return nil, _get_unsupported_mapper_error(t)
              end
            end
            return "{" .. table_concat(bits, ",") .. "}"
          end
        end
      end

      return nil, _get_unsupported_type_error(typ)
    end
  end


  -- exports
  _M.encode = encode
end


_M.number    = _create_number
_M.is_number = _is_number

return _M
