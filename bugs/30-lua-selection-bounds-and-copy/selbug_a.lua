-- (a) stale bounds: points set after a clear are outside the cached bounds
local s = selection.new()
s:set(5,5); s:set(5,5,0); s:set(20,6)
local u = s | selection.new()
nh.pline("SELBUG a1 union=" .. u:numpoints() .. " of " .. s:numpoints())

local t = selection.new()
t:set(3,3,0); t:set(20,6)          -- clearing an unset point also goes stale
local v = t | selection.new()
nh.pline("SELBUG a2 union=" .. v:numpoints() .. " of " .. t:numpoints())
