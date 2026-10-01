-- The shape of nhcore.lua's callback table, nh_lua_variables["_CB_<event>"]:
-- function name -> true.  Print the order pairs() visits it in, which is
-- the order nh_callback_run() runs the callbacks in.
local cb = {}
for _, name in ipairs({"alpha","beta","gamma","delta","epsilon","zeta","eta","theta"}) do
   cb[name] = true
end
local order = {}
for k in pairs(cb) do order[#order + 1] = k end
print(table.concat(order, ","))
