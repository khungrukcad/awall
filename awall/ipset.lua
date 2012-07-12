--[[
Ipset file dumper for Alpine Wall
Copyright (C) 2012 Kaarle Ritvanen
Licensed under the terms of GPL2
]]--


module(..., package.seeall)

require 'awall.object'

IPSet = awall.object.class(awall.object.Object)

function IPSet:init(config) self.config = config end

function IPSet:commands()
   local res = {}
   if self.config then
      for name, ipset in pairs(self.config) do
	 if not ipset.type then ipset:error('Type not defined') end
	 if not ipset.family then ipset:error('Family not defined') end
	 table.insert(res,
		      'create '..name..' '..ipset.type..' family '..ipset.family..'\n')
      end
   end
   return res
end

function IPSet:create()
   for i, line in ipairs(self:commands()) do
      local pid, stdin = lpc.run('ipset', '-!', 'restore')
      stdin:write(line)
      stdin:close()
      if lpc.wait(pid) ~= 0 then
	 io.stderr:write('ipset command failed: '..line)
      end
   end
end

function IPSet:dump(ipsfile)
   local file = io.output(ipsfile)
   for i, line in ipairs(self:commands()) do file:write(line) end
   file:close()
end
