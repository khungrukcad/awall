--[[
NAT module for Alpine Wall
Copyright (C) 2012-2013 Kaarle Ritvanen
Licensed under the terms of GPL2
]]--


module(..., package.seeall)

require 'awall.model'
require 'awall.util'

local model = awall.model


local NATRule = model.class(model.Rule)

-- alpine v2.4 compatibility
function NATRule:init(...)
   model.Rule.init(self, unpack(arg))
   local attrs = {['ip-range']='to-addr', ['port-range']='to-port'}
   for old, new in pairs(attrs) do
      if not self[new] and self[old] then
	 self:warning(old..' deprecated in favor of '..new)
	 self[new] = self[old]
      end
   end
end

function NATRule:trules()
   local res = {}
   for i, ofrags in ipairs(model.Rule.trules(self)) do
      if not awall.util.contains(self.params.chains, ofrags.chain) then
	 self:error('Inappropriate zone definitions for a '..self.params.target..' rule')
      end
      if ofrags.family == 'inet' then table.insert(res, ofrags) end
   end
   return res
end

function NATRule:table() return 'nat' end

function NATRule:target()
   if self.action then return model.Rule.target(self) end

   local addr = self['to-addr']
   local target
   if addr then
      target = self.params.target..' --to-'..self.params.subject..' '..addr
   else target = self.params.deftarget end

   if self['to-port'] then
      target = target..(addr and ':' or ' --to-ports ')..self['to-port']
   end
   return target
end


local DNATRule = model.class(NATRule)

function DNATRule:init(...)
   NATRule.init(self, unpack(arg))
   self.params = {forbidif='out', subject='destination',
		  chains={'INPUT', 'PREROUTING'},
		  target='DNAT', deftarget='REDIRECT'}
end


local SNATRule = model.class(NATRule)

function SNATRule:init(...)
   NATRule.init(self, unpack(arg))
   self.params = {forbidif='in', subject='source',
		  chains={'OUTPUT', 'POSTROUTING'},
		  target='SNAT', deftarget='MASQUERADE'}
end


export = {
   dnat={class=DNATRule},
   snat={class=SNATRule}
}
