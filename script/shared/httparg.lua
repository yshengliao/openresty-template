local _M = { _VERSION = "0.1" }

local cjson     = require "cjson.safe"
local multipart = require "resty.multipart.parser"

local ngx_re_match = ngx.re.match
local NULL         = ngx.null

local TYPE_NAME = { TABLE    = 'table',
                    FUNCTION = 'function',
                    STRING   = 'string',
                    NUMBER   = 'number',
                    BOOLEAN  = 'boolean',
                    NIL      = 'nil' }

local ERROR_CODE = {
  INVALID_ARGUMENT        = 'INVALID_ARGUMENT',
  DUPLICATED_PART_NAME    = 'DUPLICATED_PART_NAME',
  INVALID_HANDLER_TYPE    = 'INVALID_HANDLER_TYPE',
  INVALID_HTTPARG_HANDLER = 'INVALID_HTTPARG_HANDLER',
}

--[[
  handler   (function)
  argument:
    input   (any)
  return:
    value   (any)
    (error)
    NOTE: if return value is
            nil        indicate the handler without change the input value
            (other)    indicate the handler change the input to another
    NOTE: if you want change the value to nil, you can return the value
          with ngx.null
]]
local HANDLER = {
  ['date'] = function(input, _key, opt)
    if input == nil then
      return nil
    end

    if type(input)==TYPE_NAME.STRING then
      local matcher, err = ngx.re.gmatch(input, "^(\\d{4})-(\\d{1,2})-(\\d{1,2})$")
      if err  or  not matcher  then
        return nil, {
          code    = ERROR_CODE.INVALID_ARGUMENT,
          message = "specified argument '%s' value '"..tostring(input).."' is invalid date"
        }
      end
      assert(matcher)

      local m, err = matcher()  -- m['0']="1990-05-01", m['1']="1990", m['2']="05", m['3']="01"
      if err  or  m == nil  or  #m ~= 3 then
        return nil, {
          code    = ERROR_CODE.INVALID_ARGUMENT,
          message = "specified argument '%s' value '"..tostring(input).."' is invalid date"
        }
      end

      local date = os.time({
        year  = m[1],
        month = m[2],
        day   = m[3],
      })

      if type(date) ~= "number" then
        return nil, {
          code    = ERROR_CODE.INVALID_ARGUMENT,
          message = "specified argument '%s' value '"..tostring(input).."' is invalid date"
        }
      end
      return date
    end

    return nil, {
      code    = ERROR_CODE.INVALID_ARGUMENT,
      message = "specified argument '%s' cannot convert from "..type(input).." to date"
    }
  end,
  ['datetime'] = function(input, _key, opt)
    if input == nil then
      return nil
    end

    if type(input)==TYPE_NAME.STRING then
      local matcher, err = ngx.re.gmatch(input, "^(\\d{4})-(\\d{1,2})-(\\d{1,2}) (\\d{1,2}):(\\d{1,2}):(\\d{1,2})$")
      if err  or  not matcher  then
        return nil, {
          code    = ERROR_CODE.INVALID_ARGUMENT,
          message = "specified argument '%s' value '"..tostring(input).."' is invalid datetime"
        }
      end
      assert(matcher)

      local m, err = matcher()  -- m['0']="1990-05-01 13:45:51", m['1']="1990", m['2']="05", m['3']="01", m['4']="13", m['5']="45", m['6']="51"
      if err  or  m == nil  or  #m ~= 6 then
        return nil, {
          code    = ERROR_CODE.INVALID_ARGUMENT,
          message = "specified argument '%s' value '"..tostring(input).."' is invalid datetime"
        }
      end

      local datetime = os.time({
        year  = m[1],
        month = m[2],
        day   = m[3],
        hour  = m[4],
        min   = m[5],
        sec   = m[6],
      })

      if type(datetime) ~= "number" then
        return nil, {
          code    = ERROR_CODE.INVALID_ARGUMENT,
          message = "specified argument '%s' value '"..tostring(input).."' is invalid datetime"
        }
      end
      return datetime
    end

    return nil, {
      code    = ERROR_CODE.INVALID_ARGUMENT,
      message = "specified argument '%s' cannot convert from "..type(input).." to datetime"
    }
  end,
  ['any'] = function(input, _key, opt)
    if input == nil then
      return nil
    end

    return input
  end,
  ['json'] = function(input, _key, opt)
    if input == nil then
      return nil
    end

    local v = opt.json_decoder(input)
    if v == nil then
      return nil, {
        code    = ERROR_CODE.INVALID_ARGUMENT,
        message = "specified argument '%s' is not a json document"
      }
    end
    return v
  end,
  ['number'] = function(input, _key, opt)
    if input == nil then
      return nil
    end

    local v = opt.number_decoder(input)
    if not v then
      return nil, {
        code    = ERROR_CODE.INVALID_ARGUMENT,
        message = "specified argument '%s' is not of type number"
      }
    end
    return v
  end,
  ['boolean'] = function(input, _key, _opt)
    if input == nil then
      return false
    end

    if type(input) == TYPE_NAME.BOOLEAN then
      return input
    elseif type(input) == TYPE_NAME.NUMBER then
      return input ~= 0
    elseif type(input) == TYPE_NAME.STRING then
      if    string.upper(input) == "FALSE"
         or string.upper(input) == "NO"
         or string.upper(input) == "OFF" then
        return false
      end
      return true
    elseif input then
      return true
    end

    return nil, {
      code    = ERROR_CODE.INVALID_ARGUMENT,
      message = "specified argument '%s' is not of type boolean"
    }
  end,
  ['string'] = function(input, _key, _opt)
    if input == nil then
      return nil
    end

    if type(input)==TYPE_NAME.STRING then
      return input
    elseif type(input)==TYPE_NAME.BOOLEAN  or  type(input)==TYPE_NAME.NUMBER  then
      return tostring(input)
    end

    return nil, {
      code    = ERROR_CODE.INVALID_ARGUMENT,
      message = "specified argument '%s' cannot convert from "..type(input).." to string"
    }
  end,
  ['array'] = function(input, _key, _opt)
    if input == nil then
      return nil
    end

    if type(input)==TYPE_NAME.TABLE then
      if    not next(input)
        or  (next(input)  and  #input > 0) then
        return input
      end
    end

    return nil, {
      code    = ERROR_CODE.INVALID_ARGUMENT,
      message = "specified argument '%s' is not of type array"
    }
  end,
  ['map'] = function(input, _key, _opt)
    if input == nil then
      return nil
    end

    if type(input)==TYPE_NAME.TABLE then
      if next(input)  and  #input == 0 then
        return input
      end
    end

    return nil, {
      code    = ERROR_CODE.INVALID_ARGUMENT,
      message = "specified argument '%s' is not of type map"
    }
  end,
  ['required'] = function(input, _key)
    if input == nil then
      return nil, {
        code    = 'MISSING_ARGUMENT',
        message = "missing required argument '%s'"
      }
    end
    return nil
  end,
  [':as_null'] = function( _input )
    return NULL
  end,
  [':as_value'] = function( input )
    return input
  end,
  [':as_array'] = function( input )
    if input == NULL  or  type(input) == TYPE_NAME.NIL  then
      return input
    elseif  type(input) == TYPE_NAME.BOOLEAN or
            type(input) == TYPE_NAME.NUMBER or
            type(input) == TYPE_NAME.STRING
      then
      return { input }
    elseif type(input) == TYPE_NAME.TABLE then
      if next(input) and #input == 0 then
        return { input }
      end
      return input
    end
    error(
      string.format("cannot cast type to array from %s", type(input))
    )
  end,
}


local Assertion = {}
do
  local ASSERTION = Assertion

  local function is_nan(v)
    return v ~= v
  end

  local function is_infinity(v)
    return math.abs(v) == math.huge
  end


  function ASSERTION.number_not_in(...)
    local seeds = {...}

    return function(input)
      local num = tonumber(input)
      if num then
        for i = 1, #seeds do
          local v = seeds[i]
          if num == v then
            return nil, {
              code    = ERROR_CODE.INVALID_ARGUMENT,
              message = "specified argument '%s' out of range"
            }
          end
        end
      end
      return input
    end
  end


  function ASSERTION.max(v)
    assert(type(v)=="number", "must be a 'number'")

    return function(input)
      local num = tonumber(input)
      if num then
        return math.min(num, v)
      end
      return input
    end
  end


  function ASSERTION.string_should_in(...)
    local candidates = {...}

    return function(input)
      local argv = input
      if argv then
        local result = false
        for i = 1, #candidates do
          local v = candidates[i]
          if argv == v then
            result = true
            break
          end
        end
        if not result then
          return nil, {
            code    = ERROR_CODE.INVALID_ARGUMENT,
            message = "specified argument '%s' value '"..input.."' out of range"
          }
        end
      end
      return input
    end
  end


  function ASSERTION.non_empty_string()
    return function(input)
      if TYPE_NAME.STRING == type(input) then
        if input == "" then
          return nil, {
            code    = ERROR_CODE.INVALID_ARGUMENT,
            message = "specified argument '%s' cannot be an empty string"
          }
        end
      end
      return input
    end
  end


  function ASSERTION.non_nan_nor_inf()
    return function(input)
      if TYPE_NAME.NUMBER == type(input) then
        if is_nan(input) or is_infinity(input) then
          return nil, {
            code    = ERROR_CODE.INVALID_ARGUMENT,
            message = "specified argument '%s' cannot be -inf, +inf or nan"
          }
        end
      end
      return input
    end
  end


  function ASSERTION.non_negative_number()
    return function(input)
      if TYPE_NAME.NUMBER == type(input) then
        if  0 > input then
          return nil, {
            code    = ERROR_CODE.INVALID_ARGUMENT,
            message = "specified argument '%s' should be a non-negative number"
          }
        end
      end
      return input
    end
  end


  function ASSERTION.non_empty_array()
    return function(input)
      if TYPE_NAME.TABLE == type(input) then
        if not next(input) then
          return nil, {
            code    = ERROR_CODE.INVALID_ARGUMENT,
            message = "specified argument '%s' cannot be an empty array"
          }
        end
      end
      return input
    end
  end

end


local Processor = {}
do
  local PROCESSOR = Processor

  --[[
    argument:
      value       (map)
      key         (string)
      handlers    (array)
      handler_opt (table)
    return:
      value      (any)
      <error>
  ]]
  local function _process(value, key, handlers, handler_opt, depth)
    if type(handlers)==TYPE_NAME.TABLE  and   next(handlers) then
      for _, h in ipairs(handlers) do
        local handler
        if type(h) == TYPE_NAME.STRING then
          handler = HANDLER[h]
          if not handler then
            return nil, {
              code    = ERROR_CODE.INVALID_HANDLER_TYPE,
              message = string.format("unknown handler '%s'", h),
            }
          end
        elseif type(h) == TYPE_NAME.FUNCTION then
          handler = h
        elseif type(h) == TYPE_NAME.TABLE  then
          if depth ~= 0 then
            error(
              string.format("unsupported handler type %s", type(h))
            )
          end
          if next(h) and #h == 0 then
            error(
              string.format("unsupported handler type %s", type(h))
            )
          end

          if value ~= nil then
            local value_handlers, err
            local mixed_handlers = h
            for _, elem_handlers in ipairs(mixed_handlers) do
              if type(elem_handlers) ~= TYPE_NAME.TABLE then
                error(
                  string.format("unsupported handler type %s", type(elem_handlers))
                )
              end

              local r
              r, err = _process(value, key, { elem_handlers[1] }, handler_opt, depth + 1)
              if r ~= nil then
                value_handlers = elem_handlers
                break
              end
            end
            -- nothing handlers match
            if not value_handlers then
              return nil, err
            end

            local res, err = _process(value, key, value_handlers, handler_opt, depth+1)
            if err then
              return nil, err
            end
            if res ~= nil then
              value = res
            end
          end

          handler = HANDLER.any
        else
          return nil, {
            code    = ERROR_CODE.INVALID_HTTPARG_HANDLER,
            message = string.format("unknown handler '%s'", h),
          }
        end

        local res, err = handler(value, key, handler_opt)
        if err then
          return nil, err
        end
        if res ~= nil then
          value = res
        end
      end
    end
    if value == NULL then
      return nil
    end
    return value
  end


  --[[
    argument:
      value       (map)
      key         (string)
      handlers    (array)
      handler_opt (table)
    return:
      value      (any)
      <error>
  ]]
  local function process(value, key, handlers, handler_opt)
    return _process(value, key, handlers, handler_opt, 0)
  end


  local function create_dummy_parttag( tag, name )
    local parttag = tag:create_parttag(NULL)

    local current_processor
    do
      current_processor = setmetatable({}, {
        __index = function(_, key)
          local processor = Processor[key]
          if processor then
            return processor(parttag, current_processor)
          end
        end,
        __call = function(_, ...)
          local handlers = {...}
          local _, err = process(nil, name, handlers, tag.decoder)
          if err then
            return tag:throw(err.code, err.message, name)
          end
          return nil
        end
      })
    end
    return current_processor
  end


  local function create_nested_object( tag, content, key, parent )
    local self = {
      content = content,
      parent  = parent  and  parent.."."..key  or key,
    }
    return setmetatable({}, {
      __index = function( _, field)
        local value
        if TYPE_NAME.TABLE == type(self.content) then
          value = self.content[key]
        end
        if value == NULL then
          value = nil
        end
        value = value or NULL
        return create_nested_object(tag, value, field, self.parent)
      end,
      __call = function( _, ...)
        if self.content  and  self.content ~= NULL  then
          local handlers = {...}
          local content
          if type(self.content)==TYPE_NAME.TABLE  then
            content = self.content[key]
          end
          if content == NULL then
            content = nil
          end
          local value, err = process(content, self.parent, handlers, tag.decoder)
          if err then
            return tag:throw(err.code, err.message, self.parent)
          end
          return value
        end
        return nil
      end
    })
  end


  PROCESSOR.process = function( tag, parent_field )
    local args = tag.content

    return setmetatable({}, {
      __index = function( _, field )
        return create_nested_object(tag, args, field, parent_field)
      end
    })
  end


  PROCESSOR.validate = function( _tag, parent_processor )
    local processor
    do
      processor = setmetatable({}, {
        __call = function(_, ...)
          if parent_processor ~= nil then
            parent_processor(...)
          else
            local processors = {...}
            return setmetatable({}, {
              __call = function(_, ...)
                for _, p in ipairs(processors) do
                  if p then
                    p.validate(...)
                  end
                end
                return nil
              end
            })
          end
          return nil
        end
      })
    end
    return processor
  end


  PROCESSOR.assert = function( tag )
    return function(...)
      for _, validate in ipairs({...}) do
        local err = validate(tag)
        if err then
          return tag:throw(err.code, err.message)
        end
      end
    end
  end


  PROCESSOR.default = function()
    return HANDLER[':as_value']
  end


  PROCESSOR.text = function( tag )
    local content
    if type(tag)==TYPE_NAME.TABLE then
      content = tag.content
    end
    if content == nil then
      ngx.req.read_body()
      content = ngx.req.get_body_data()
    end

    return setmetatable({}, {
      __call = function(_, ...)
        if content then
          local handlers = {...}
          local res, err = process(content, nil, handlers, tag.decoder)
          if err then
            return tag:throw(err.code, err.message, "[body]")
          end
          return res
        end
        return nil
      end
    })
  end


  PROCESSOR.part = function( tag )
    local args
    do
      local content_type = ngx.req.get_headers()["content-type"]
      if content_type then
        if ngx_re_match(content_type, [[^multipart/\S+;\s*boundary\s*=\s*(?:"([^"]+)"|([-|+*$&!.%'`~^\#\w]+))]]) then
          ngx.req.read_body()
          local body = ngx.req.get_body_data()
          local parts, err = multipart.new(body, content_type)
          if err then
            return tag:throw("INVALID_MULTIPART", err)
          end

          args = {}
          while true do
            local content, name, _mime, _filename = parts:parse_part()
            if not content then
              break
            end
            if name  and  string.len(name) > 0  then
              -- exist?
              if args[name] then
                return tag:throw(ERROR_CODE.DUPLICATED_PART_NAME,
                  string.format("the same part name '%s' already exists", name))
              end
              -- assign processors
              local parttag = tag:create_parttag(content or NULL)
              local current_processor
              do
                current_processor = setmetatable({}, {
                  __index = function(obj, key)
                    local processor = Processor[key]
                    if processor then
                      local p = processor(parttag, current_processor)
                      rawset(obj, key, p)
                      return p
                    end
                  end,
                  __call = function(_, ...)
                    if type(args)==TYPE_NAME.TABLE then
                      local handlers = {...}
                      local v = content
                      if v then
                        local res, err = process(v, name, handlers, tag.decoder)
                        if err then
                          return tag:throw(err.code, err.message, name)
                        end
                        return res
                      end
                      return nil
                    end
                  end
                })
              end
              args[name] = current_processor
            end
          end
        end
      end
    end

    return setmetatable({}, {
      __index = function( _, part )
        if type(args)==TYPE_NAME.TABLE then
          local obj = args[part]
          if obj then
            return obj
          end
        end
        return create_dummy_parttag(tag, part)
      end
    })
  end


  PROCESSOR.query = function( tag )
    local args
    do
      args = ngx.req.get_uri_args()
    end

    return setmetatable({}, {
      __index = function( _, field )
        return function(...)
          if type(args)==TYPE_NAME.TABLE then
            local handlers = {...}
            local value, err = process(args[field], field, handlers, tag.decoder)
            if err then
              return tag:throw(err.code, err.message, field)
            end
            return value
          end
          return nil
        end
      end,
      __call = function( _, ...)
        if args then
          local value = nil
          if next(args) then
            value = args
          end
          for _, h in ipairs({...}) do
            if h == "raw" then
              value = ngx.var.args
            else
              local res, err = process(value, nil, {h}, tag.decoder)
              if err then
                return tag:throw(err.code, err.message, "[query]")
              end
              value = res
            end
          end
          return value
        end
        return nil
      end
    })
  end


  PROCESSOR.form = function( tag )
    local args
    do
      ngx.req.read_body()
      args = ngx.req.get_post_args()
    end

    return setmetatable({}, {
      __index = function( _, field )
        return function(...)
          if type(args)==TYPE_NAME.TABLE then
            local handlers = {...}
            local value, err = process(args[field], field, handlers, tag.decoder)
            if err then
              return tag:throw(err.code, err.message, field)
            end
            return value
          end
          return nil
        end
      end,
      __call = function( _, handler)
        local h = handler

        if     (h == nil  ) then  return args
        elseif (h == "raw") then  return ngx.req.get_body_data()
        end

        local err = {
          code    = "INVALID_HANDLER_TYPE",
          message = string.format("unknown handler '%s'", h),
        }
        return tag:throw(err.code, err.message)
      end
    })
  end


  PROCESSOR.json = function( tag )
    local args
    do
      local content = tag.content
      if not content then
        ngx.req.read_body()
        content = ngx.req.get_body_data()
      end
      args = tag.decoder.json_decoder(content) or NULL
    end

    return setmetatable({}, {
      __index = function( _, field )
        return create_nested_object(tag, args, field)
      end,
      __call = function()
        return args
      end
    })
  end


  PROCESSOR.header = function( tag )
    local args
    do
      args = ngx.req.get_headers()
    end

    return setmetatable({}, {
      __index = function( _, field )
        return function(...)
          if type(args)==TYPE_NAME.TABLE then
            local handlers = {...}
            local value, err = process(args[field], field, handlers, tag.decoder)
            if err then
              return tag:throw(err.code, err.message, field)
            end
            return value
          end
          return nil
        end
      end
    })
  end


  PROCESSOR.body = function( tag )
    local args
    do
      local content = tag.content
      if not content then
        ngx.req.read_body()
        content = ngx.req.get_body_data()
      end
      args = content
    end

    return function(...)
      local handlers = {...}
      local value, err = process(args, nil, handlers, tag.decoder)
      if err then
        return tag:throw(err.code, err.message, "[body]")
      end
      return value
    end
  end


  PROCESSOR.error = function(tag)
    return tag.error_handler
  end
end


local Tag = {}
do
  local TAG = Tag
  local TAG_mt = { __index = TAG }

  function TAG.new( opt )
    if opt.json_decoder then
      assert(type(opt.json_decoder)=='function', "opt.json_decoder should be function")
    end
    if opt.number_decoder then
      assert(type(opt.number_decoder)=='function', "opt.number_decoder should be function")
    end

    return setmetatable({
      error_handler = opt.error_handler,
      content       = opt.content,
      decoder = {
        json_decoder   = opt.json_decoder    or  cjson.decode,
        number_decoder = opt.number_decoder  or  tonumber,
      },
    }, TAG_mt)
  end


  function TAG.throw( self, code, message, ... )
    if self  and  type(self.error_handler)==TYPE_NAME.FUNCTION  then
      if message then
        message = string.format(message, ...)
      end
      self.error_handler(code, message)
    end
  end


  function TAG.create_prototype( self )
    if self then
      return setmetatable({
        error_handler = self.error_handler,
      }, TAG_mt)
    end
  end

  function TAG.create_parttag( self, content )
    if self then
      return setmetatable({
        error_handler = self.error_handler,
        content       = content,
        decoder       = self.decoder,
      }, TAG_mt)
    end
  end
end


-- module
do
  function _M.tag( opt )
    opt = opt or {}
    local tag = Tag.new(opt)

    if opt.content then
      return Processor.process(tag, opt.content_name)
    end

    return setmetatable({}, {
      __index = function(obj, key)
        local processor = Processor[key]
        if processor then
          local p = processor(tag)
          rawset(obj, key, p)
          return p
        end
      end
    })
  end
end

_M.assertion = Assertion
return _M
