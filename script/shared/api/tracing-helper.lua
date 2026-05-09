local attr = require("opentelemetry.attribute")
local util = require("shared.api.util")


local _M = { _VERSION = "0.1" }

-- event
do
  local EVENT = {}
  local EVENT_mt = { __index = EVENT }

  function EVENT.new(span)
    return setmetatable({
      span     = span,
      sequence = 0,
    }, EVENT_mt)
  end

  function EVENT.add_event(self, event, attributes)
    assert(self)
    assert(type(event) == 'string')

    local attrs = {}
    if type(attributes) == 'table' then
      for k, v in pairs(attributes) do
        if type(v) == 'boolean' then
          attrs[#attrs+1] = attr.bool(k, v)
        elseif type(v) == 'number' then
          attrs[#attrs+1] = attr.double(k, v)
        elseif type(v) == 'string' then
          attrs[#attrs+1] = attr.string(k, v)
        else
          attrs[#attrs+1] = attr.string(k, util.dump_table(v))
        end
      end
    end
    self.span:add_event(string.format("%d:%s", self.sequence, event), {attributes = attrs})
    self.sequence = self.sequence + 1
  end

  -- exports
  _M.event = EVENT
end

return _M
