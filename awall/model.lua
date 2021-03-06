--[[
Base data model for Alpine Wall
Copyright (C) 2012-2014 Kaarle Ritvanen
See LICENSE file for license details
]]--


module(..., package.seeall)

require 'awall'
require 'awall.host'
require 'awall.iptables'
require 'awall.object'
require 'awall.optfrag'
require 'awall.uerror'
require 'awall.util'

local util = awall.util
local combinations = awall.optfrag.combinations

class = awall.object.class

require 'stringy'


ConfigObject = class()

function ConfigObject:init(context, location)
   if context then
      self.context = context
      self.root = context.objects
   end
   self.location = location
end

function ConfigObject:create(cls, params)
   if type(cls) == 'string' then
      local name = cls
      cls = awall.loadclass(cls)
      if not cls then
	 self:error('Support for '..name..' objects not installed')
      end
   end
   return cls.morph(params, self.context, self.location)
end

function ConfigObject:error(msg)
   awall.uerror.raise(self.location..': '..msg)
end

function ConfigObject:warning(msg)
   io.stderr:write(self.location..': '..msg..'\n')
end

function ConfigObject:trules() return {} end

function ConfigObject:info()
   local res = {}
   for i, trule in ipairs(self:trules()) do
      table.insert(res,
		   {'  '..awall.optfrag.location(trule),
		    (trule.opts and trule.opts..' ' or '')..'-j '..trule.target})
   end
   return res
end


Zone = class(ConfigObject)

function Zone:optfrags(dir)
   local iopt, aopt, iprop, aprop
   if dir == 'in' then
      iopt, aopt, iprop, aprop = 'i', 's', 'in', 'src'
   elseif dir == 'out' then
      iopt, aopt, iprop, aprop = 'o', 'd', 'out', 'dest'
   else assert(false) end

   local aopts = nil
   if self.addr then
      aopts = {}
      for i, hostdef in util.listpairs(self.addr) do
	 for i, addr in ipairs(awall.host.resolve(hostdef, self)) do
	    table.insert(aopts,
			 {family=addr[1],
			  [aprop]=addr[2],
			  opts='-'..aopt..' '..addr[2]})
	 end
      end
   end

   return combinations(util.maplist(self.iface,
				    function(x)
				       return {[iprop]=x,
					       opts='-'..iopt..' '..x}
				    end),
		       aopts)
end


fwzone = Zone.new()


IPSet = class(ConfigObject)

function IPSet:init(...)
   ConfigObject.init(self, unpack(arg))

   if not self.type then self:error('Type not defined') end

   if stringy.startswith(self.type, 'bitmap:') then
      if not self.range then self:error('Range not defined') end
      self.options = {self.type, 'range', self.range}
      self.family = 'inet'

   elseif stringy.startswith(self.type, 'hash:') then
      if not self.family then self:error('Family not defined') end
      self.options = {self.type, 'family', self.family}

   elseif self.type == 'list:set' then self.options = {self.type}

   else self:error('Invalid type: '..self.type) end
end


Rule = class(ConfigObject)


function Rule:init(...)
   ConfigObject.init(self, unpack(arg))

   self.newchains = {}

   for i, prop in ipairs({'in', 'out'}) do
      self[prop] = self[prop] and util.maplist(self[prop],
					       function(z)
						  if type(z) ~= 'string' then return z end
						  return z == '_fw' and fwzone or
						     self.root.zone[z] or
						     self:error('Invalid zone: '..z)
					       end)
   end

   if self.service then
      if type(self.service) == 'string' then self.label = self.service end
      self.service = util.maplist(self.service,
				  function(s)
				     if type(s) ~= 'string' then return s end
				     return self.root.service[s] or self:error('Invalid service: '..s)
				  end)
   end
end


function Rule:direction(dir)
   if dir == 'in' then return self.reverse and 'out' or 'in' end
   if dir == 'out' then return self.reverse and 'in' or 'out' end
   self:error('Invalid direction: '..dir)
end


function Rule:zoneoptfrags()

   local function zonepair(zin, zout)

      local function zofs(zone, dir)
	 if not zone then return zone end
	 return zone:optfrags(dir)
      end

      local chain, ofrags

      if zin == fwzone or zout == fwzone then
	 if zin == zout then return {} end
	 local dir, z = 'in', zin
	 if zin == fwzone then dir, z = 'out', zout end
	 chain = string.upper(dir)..'PUT'
	 ofrags = zofs(z, dir)

      elseif not zin or not zout then

	 if zin then
	    chain = 'PREROUTING'
	    ofrags = zofs(zin, 'in')

	 elseif zout then
	    chain = 'POSTROUTING'
	    ofrags = zofs(zout, 'out')
	 end

      else
	 chain = 'FORWARD'
	 ofrags = combinations(zofs(zin, 'in'), zofs(zout, 'out'))

	 if ofrags and not zout['route-back'] then
	    ofrags = util.filter(ofrags,
				 function(of)
				    return not (of['in'] and of.out and
						of['in'] == of.out)
				 end)
	 end
      end

      return combinations(ofrags,
			  chain and {{chain=chain}} or {{chain='PREROUTING'},
							{chain='OUTPUT'}})
   end

   local res = {}
   local izones = self[self:direction('in')] or {}
   local ozones = self[self:direction('out')] or {}

   for i = 1,math.max(1, table.maxn(izones)) do
      for j = 1,math.max(1, table.maxn(ozones)) do
	 util.extend(res, zonepair(izones[i], ozones[j]))
      end
   end

   return res
end


function Rule:servoptfrags()

   if not self.service then return end

   local fports = {inet={}, inet6={}}
   local res = {}

   for i, serv in ipairs(self.service) do
      for i, sdef in util.listpairs(serv) do
	 if not sdef.proto then self:error('Protocol not defined') end

	 if util.contains({6, 'tcp', 17, 'udp'}, sdef.proto) then
	    for family, ports in pairs(fports) do
	       if not sdef.family or family == sdef.family then

		  local new = not ports[sdef.proto]
		  if new then ports[sdef.proto] = {} end

		  if new or ports[sdef.proto][1] then
		     if sdef.port then
			util.extend(
			   ports[sdef.proto],
			   util.maplist(
			      sdef.port,
			      function(p) return string.gsub(p, '-', ':') end
			   )
			)
		     else ports[sdef.proto] = {} end
		  end
	       end
	    end

	 else

	    local opts = '-p '..sdef.proto
	    local family = nil

	    -- TODO multiple ICMP types per rule
	    local oname
	    if util.contains({1, 'icmp'}, sdef.proto) then
	       family = 'inet'
	       oname = 'icmp-type'
	    elseif util.contains({58, 'ipv6-icmp', 'icmpv6'}, sdef.proto) then
	       family = 'inet6'
	       oname = 'icmpv6-type'
	    elseif sdef.type or sdef['reply-type'] then
	       self:error('Type specification not valid with '..sdef.proto)
	    end

	    if sdef.family then
	       if not family then family = sdef.family
	       elseif family ~= sdef.family then
		  self:error(
		     'Protocol '..sdef.proto..' is incompatible with '..sdef.family
		  )
	       end
	    end

	    if sdef.type then
	       opts = opts..' --'..oname..' '..(
		  self.reverse and sdef['reply-type'] or sdef.type
	       )
	    end
	    table.insert(res, {family=family, opts=opts})
	 end
      end
   end

   local popt = ' --'..(self.reverse and 's' or 'd')..'port'
   for family, pports in pairs(fports) do
      local ofrags = {}

      for proto, ports in pairs(pports) do
	 local propt = '-p '..proto

	 if ports[1] then
	    local len = #ports
	    repeat
	       local opts

	       if len == 1 then
		  opts = propt..popt..' '..ports[1]
		  len = 0

	       else
		  opts = propt..' -m multiport'..popt..'s '
		  local pc = 0
		  repeat
		     local sep = pc == 0 and '' or ','
		     local port = ports[1]
		     
		     pc = pc + (string.find(port, ':') and 2 or 1)
		     if pc > 15 then break end
		     
		     opts = opts..sep..port
		     
		     table.remove(ports, 1)
		     len = len - 1
		  until len == 0
	       end

	       table.insert(ofrags, {opts=opts})
	    until len == 0

	 else table.insert(ofrags, {opts=propt}) end
      end

      util.extend(res, combinations(ofrags, {{family=family}}))
   end

   return res
end

function Rule:destoptfrags()
   return self:create(Zone, {addr=self.dest}):optfrags(self:direction('out'))
end

function Rule:table() return 'filter' end

function Rule:position() return 'append' end

function Rule:target()
   -- alpine v2.7 compatibility
   if self.action == 'accept' then
      self:warning("'accept' action deprecated in favor of 'exclude'")
      self.action = 'exclude'
   end

   if self.action == 'exclude' then return 'ACCEPT' end
   if self.action and self.action ~= 'include' then
      self:error('Invalid action: '..self.action)
   end
end


function Rule:trules()

   local function tag(ofrags, tag, value)
      for i, ofrag in ipairs(ofrags) do
	 assert(not ofrag[tag])
	 ofrag[tag] = value
      end
   end

   local families

   local function setfamilies(ofrags)
      if ofrags then
	 families = {}
	 for i, ofrag in ipairs(ofrags) do
	    if not ofrag.family then
	       families = nil
	       return
	    end
	    table.insert(families, ofrag.family)
	 end
      else families = nil end
   end

   local function ffilter(ofrags)
      if not ofrags or not ofrags[1] or not families then return ofrags end
      return util.filter(ofrags,
			 function(of)
			    return not of.family or util.contains(families,
								  of.family)
			 end)
   end

   local res = self:zoneoptfrags()

   if self.ipset then
      local ipsetofrags = {}
      for i, ipset in util.listpairs(self.ipset) do
	 if not ipset.name then self:error('Set name not defined') end

	 local setdef = self.root.ipset and self.root.ipset[ipset.name]
	 if not setdef then self:error('Invalid set name') end

	 if not ipset.args then
	    self:error('Set direction arguments not defined')
	 end

	 local setopts = '-m set --match-set '..ipset.name..' '
	 setopts = setopts..table.concat(util.map(util.list(ipset.args),
						  function(a)
						     if self:direction(a) == 'in' then
							return 'src'
						     end
						     return 'dst'
						  end),
					 ',')
	 table.insert(ipsetofrags, {family=setdef.family, opts=setopts})
      end
      res = combinations(res, ipsetofrags)
   end

   if self.ipsec then
      res = combinations(res,
			 {{opts='-m policy --pol ipsec --dir '..self:direction(self.ipsec)}})
   end

   res = combinations(res, self:servoptfrags())

   setfamilies(res)

   local addrofrags = combinations(self:create(Zone,
					       {addr=self.src}):optfrags(self:direction('in')),
				   self:destoptfrags())
   local combined = res

   if addrofrags then
      addrofrags = ffilter(addrofrags)
      setfamilies(addrofrags)
      res = ffilter(res)

      combined = {}
      for i, ofrag in ipairs(res) do
	 local aofs = combinations(addrofrags, {{family=ofrag.family}})
	 local cc = combinations({ofrag}, aofs)
	 if #cc < #aofs then
	    combined = nil
	    break
	 end
	 util.extend(combined, cc)
      end
   end

   local target
   if combined then
      target = self:target()
      res = combined
   else
      target = self:newchain('address')
   end

   tag(res, 'position', self:position())

   res = combinations(res, {{target=target}})

   if not combined then
      util.extend(
	 res,
	 combinations(addrofrags, {{chain=target, target=self:target()}})
      )
   end

   util.extend(res, self:extraoptfrags())

   local tbl = self:table()

   local function convertchains(ofrags)
      local res = {}

      for i, ofrag in ipairs(ofrags) do

	 if util.contains(awall.iptables.builtin[tbl], ofrag.chain) then
	    table.insert(res, ofrag)

	 else
	    local ofs, recursive
	    if ofrag.chain == 'PREROUTING' then
	       ofs = {{chain='FORWARD'}, {chain='INPUT'}}
	    elseif ofrag.chain == 'POSTROUTING' then
	       ofs = {{chain='FORWARD'}, {chain='OUTPUT'}}
	       recursive = true
	    elseif ofrag.chain == 'INPUT' then
	       ofs = {{opts='-m addrtype --dst-type LOCAL', chain='PREROUTING'}}
	    elseif ofrag.chain == 'FORWARD' then
	       ofs = {
		  {opts='-m addrtype ! --dst-type LOCAL', chain='PREROUTING'}
	       }
	    end

	    if ofs then
	       ofrag.chain = nil
	       ofs = combinations(ofs, {ofrag})
	       if recursive then ofs = convertchains(ofs) end
	       util.extend(res, ofs)

	    else table.insert(res, ofrag) end
	 end
      end

      return res
   end

   res = convertchains(ffilter(res))
   tag(res, 'table', tbl, false)

   local function checkzof(ofrag, dir, chains)
      if ofrag[dir] and util.contains(chains, ofrag.chain) then
	 self:error('Cannot specify '..dir..'bound interface ('..ofrag[dir]..')')
      end
   end

   for i, ofrag in ipairs(res) do
      checkzof(ofrag, 'in', {'OUTPUT', 'POSTROUTING'})
      checkzof(ofrag, 'out', {'INPUT', 'PREROUTING'})
   end
   
   return combinations(res, ffilter({{family='inet'}, {family='inet6'}}))
end

function Rule:extraoptfrags() return {} end

function Rule:newchain(key)
   if self.newchains[key] then return self.newchains[key] end

   if not self.context.lastid then self.context.lastid = {} end
   local lastid = self.context.lastid

   local res = key
   if self.label then res = res..'-'..self.label end
   if not lastid[res] then lastid[res] = -1 end
   lastid[res] = lastid[res] + 1
   res = res..'-'..lastid[res]

   self.newchains[key] = res
   return res
end


export = {zone={class=Zone}, ipset={class=IPSet, before='%modules'}}
