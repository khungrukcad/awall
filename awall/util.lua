--[[
Utility module for Alpine Wall
Copyright (C) 2012-2013 Kaarle Ritvanen
See LICENSE file for license details
]]--


module(..., package.seeall)

function split(s, sep)
   if s == '' then return {} end
   local res = {}
   while true do
      local si, ei = string.find(s, sep, 1, true)
      if not si then
	 table.insert(res, s)
	 return res
      end
      table.insert(res, string.sub(s, 1, si - 1))
      s = string.sub(s, ei + 1, -1)
   end
end

function list(var)
   if not var then return {} end
   if type(var) ~= 'table' then return {var} end
   if not next(var) then return {} end
   return var[1] and var or {var}
end

function listpairs(var)
   return ipairs(list(var))
end

function filter(var, func)
   local res = {}
   for i, v in ipairs(var) do if func(v) then table.insert(res, v) end end
   return res
end

function map(var, func)
   local res = {}
   for k, v in pairs(var) do res[k] = func(v) end
   return res
end

function maplist(var, func)
   if not var then return var end
   return map(list(var), func)
end

function contains(tbl, value)
   for k, v in listpairs(tbl) do if v == value then return true end end
   return false
end

function keys(tbl)
   local res = {}
   for k, v in pairs(tbl) do table.insert(res, k) end
   return res
end

function values(tbl)
   local res = {}
   for k, v in pairs(tbl) do table.insert(res, v) end
   return res   
end

function sortedkeys(tbl)
   local res = keys(tbl)
   table.sort(res)
   return ipairs(res)
end

function extend(tbl1, tbl2)
   for i, var in listpairs(tbl2) do table.insert(tbl1, var) end
end

function update(tbl1, tbl2)
   if tbl2 then for k, v in pairs(tbl2) do tbl1[k] = v end end
   return tbl1
end

function copy(tbl) return update({}, tbl) end

function compare(a, b)
   local t = type(a)
   if t ~= type(b) then return false end
   if t ~= 'table' then return a == b end

   local keys = {}
   for k, v in pairs(a) do
      if not compare(v, b[k]) then return false end
      table.insert(keys, k)
   end
   for k, v in pairs(b) do
      if not contains(keys, k) then return false end
   end
   return true
end

function printtabulars(tables)
   local colwidth = {}
   for i, tbl in ipairs(tables) do
      for j, row in ipairs(tbl) do
	 for k, col in ipairs(row) do
	    colwidth[k] = math.max(colwidth[k] or 0, string.len(col))
	 end
      end
   end
   for i, tbl in ipairs(tables) do
      for j, row in ipairs(tbl) do
	 for k = 1,#row do
	    if k > 1 then io.write('  ') end
	    io.write(row[k])
	    if k < #row then
	       for l = 1,colwidth[k] - string.len(row[k]) do io.write(' ') end
	    end
	 end
	 io.write('\n')
      end
      io.write('\n')
   end
end

function printtabular(tbl) printtabulars({tbl}) end
