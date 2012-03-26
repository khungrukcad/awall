--[[
Iptables file dumper for Alpine Wall
Copyright (C) 2012 Kaarle Ritvanen
Licensed under the terms of GPL2
]]--


module(..., package.seeall)

require 'lpc'

require 'awall.object'
require 'awall.util'

local class = awall.object.class
local contains = awall.util.contains


local families = {inet={cmd='iptables', file='rules-save'},
		  inet6={cmd='ip6tables', file='rules6-save'}}

local builtin = {'INPUT', 'FORWARD', 'OUTPUT',
		 'PREROUTING', 'POSTROUTING'}

local backupdir = '/var/run/awall'


local BaseIPTables = class(awall.object.Object)

function BaseIPTables:dump(dir)
   for family, tbls in pairs(families) do
      local file = io.output(dir..'/'..families[family].file)
      self:dumpfile(family, file)
      file:close()
   end
end

function BaseIPTables:restore(...)
   for family, params in pairs(families) do
      local pid, stdin, stdout = lpc.run(params.cmd..'-restore', unpack(arg))
      stdout:close()
      self:dumpfile(family, stdin)
      stdin:close()
      assert(lpc.wait(pid) == 0)
   end
end

function BaseIPTables:activate() self:restore() end

function BaseIPTables:test() self:restore('-t') end


IPTables = class(BaseIPTables)

function IPTables:init()
   self.config = {}
   setmetatable(self.config,
		{__index=function(t, k)
			    t[k] = {}
			    setmetatable(t[k], getmetatable(t))
			    return t[k]
			 end})
end

function IPTables:dumpfile(family, iptfile)
   iptfile:write('# '..families[family].file..' generated by awall\n')
   for tbl, chains in pairs(self.config[family]) do
      iptfile:write('*'..tbl..'\n')
      for chain, rules in pairs(chains) do
	 iptfile:write(':'..chain..' '..(contains(builtin, chain) and
				      'DROP' or '-')..' [0:0]\n')
      end
      for chain, rules in pairs(chains) do
	 for i, rule in ipairs(rules) do
	    iptfile:write('-A '..chain..' '..rule..'\n')
	 end
      end
      iptfile:write('COMMIT\n')
   end
end


local Current = class(BaseIPTables)

function Current:dumpfile(family, iptfile)
   local pid, stdin, stdout = lpc.run(families[family].cmd..'-save')
   stdin:close()
   for line in stdout:lines() do iptfile:write(line..'\n') end
   stdout:close()
   assert(lpc.wait(pid) == 0)
end


local Backup = class(BaseIPTables)

function Backup:dumpfile(family, iptfile)
   for line in io.lines(backupdir..'/'..families[family].file) do
      iptfile:write(line..'\n')
   end
end


function backup()
   Current.new():dump(backupdir)
end

function revert()
   Backup.new():activate()
end
