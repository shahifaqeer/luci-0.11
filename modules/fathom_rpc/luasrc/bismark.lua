--[[
LuCI - Lua Configuration Interface

Copyright 2008 Steven Barth <steven@midlink.org>
Copyright 2008 Jo-Philipp Wich <xm@leipzig.freifunk.net>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

]]--


local io     = require "io"
local os     = require "os"
local table  = require "table"
local nixio  = require "nixio"
local fs     = require "nixio.fs"
local uci    = require "luci.model.uci"
local string = require "string"
--local json = require("dkjson")

local luci   = {}
luci.util    = require "luci.util"
luci.ip      = require "luci.ip"
luci.sys     = require "luci.sys"

local tonumber, ipairs, pairs, pcall, type, next, setmetatable, require, select =
        tonumber, ipairs, pairs, pcall, type, next, setmetatable, require, select

module "luci.bismark"
--- Execute a given shell command and return the error code
-- @class               function
-- @name                call
-- @param               ...             Command to call
-- @return              Error code of the command
function call(...)
        return os.execute(...) / 256
end

--- Execute a given shell command and capture its standard output
-- @class               function
-- @name                exec
-- @param command       Command to call
-- @return                      String containg the return the output of the command
exec = luci.util.exec

active = {}

--[[
    SIMPLE COMMANDS: ping, alive, arp
]]--
function active.pingtest(host, count)
    return luci.util.exec("ping -c"..count.." '"..host:gsub("'", '').."'")
end

function active.alive(host)
    -- return 0 if successful (alive) else 256/256 = 1
    return os.execute("ping -c1 -W1 '"..host:gsub("'", '').."' >/dev/null 2>&1") / 256
end

-- from net.arptable in sys.lua
function active.arptable(callback)
    local arp, e, r, v
    if fs.access("/proc/net/arp") then
        for e in io.lines("/proc/net/arp") do
            local r = { }, v
            for v in e:gmatch("%S+") do
                r[#r+1] = v
            end
            if r[1] ~= "IP" then
                local x = {
                    ["IP address"] = r[1],
                    ["HW type"]    = r[2],
                    ["Flags"]      = r[3],
                    ["HW address"] = r[4],
                    ["Mask"]       = r[5],
                    ["Device"]     = r[6],
                    ["Alive"]      = active.alive(r[1]),    -- ping device
                    ["Interface"]  = active.interface(r[4]) -- get state eth or wlan
                }

                if callback then
                    callback(x)
                else
                    arp = arp or { }
                    arp[#arp+1] = x
                end
            end
        end
    end
    return arp
end

--[[
    WIRELESS INFO
]]--
--XXX make parser

function active.iwstationdump()
    local station_dump = ""
    
    local wireless_dev = luci.util.exec("iw dev | grep 'Interface'")
    for _,lines in pairs(wireless_dev:split("\n")) do
        for intfce in lines:gmatch('Interface%s*(%a.*)') do
            station_dump = station_dump .. "\n".. luci.util.exec("iw dev "..intfce.." station dump")
        end
    end
    
    return station_dump
end

function active._wireless_interface()
    local wireless_dev = luci.util.exec("iw dev | grep 'Interface'")
    
    local Interface = { }
    local w = { }
    local i = 0
    
    for _,lines in pairs(wireless_dev:split("\n")) do
        for intfce in lines:gmatch('Interface%s*(%a.*)') do
            w[i] = luci.util.exec("iw dev "..intfce.." station dump | grep 'Station'" )
            for _,line in pairs(w[i]:split("\n")) do
                Interface[line:split(" ")[2]] = intfce
            end
            i = i+1
        end
    end
    return Interface
end


function active.interface(dev)
    
    local Interface = active._wireless_interface()
    
    if Interface[dev] then
        return Interface[dev]
    else
        return "eth"
    end
end


--[[
    BANDWIDTH TESTS
]]--

--function active.udpbandwidth(host, direction)
--    -- invoke shaperprobe server if direction = up and client if direction = dw
--    return luci.util.exec("nc '"..host:gsub("'", '').."'")
--end

----------------------------------------------------------------------------------------------
--- TCP BANDWIDTH TEST
-- direction: UP - make this more OOPs

function active.tcpserver(port_num, interval_time, window_size)
    -- currently use default parameters (-t, -P is set at client only)
    -- -i 10 -p 5001 -w 8.00 KByte
    -- try -w 1024k
    -- this should be called BEFORE iperf client starts on device
    port_num = port_num or 5001
    if window_size then
        w = (window_size/2)
    else
        w = 42.65 -- max window size on openwrt seems to be 320k, default 85.3k
    end
    
    if interval_time then
        os.execute("iperf -y C -s -i"..interval_time.." -w "..w.."k -p "..port_num.." >/tmp/iperf"..port_num..".temp &")
    else
        os.execute("iperf -y C -s -w "..w.."k -p "..port_num.." >/tmp/iperf"..port_num..".temp &")
    end
    -- TODO THESE OPTIONS ARE NOT WORKING. PGREP IS A TEMP SOLUTION TO GET iperf PID
    -- can use luaposix instead to call getpid() directly from lua
    
    -- os.execute("echo $! >/var/run/iperf"..port_num..".pid")
    -- return io.lines("/var/run/iperf"..port_num..".pid")
    
    -- return luci.util.exec("echo $!")
    
    return luci.util.exec("pgrep iperf")
end

-- direction: DW
function active.tcpclient(port_num, host, window_size, test_time, interval_time)
    -- currently use default parameters (-t, -P is set at client only)
    -- -i 10 -t 10 -p 5002 -w 8.00 KByte -P 1
    -- try -w 1024k, -P 4 etc
    -- return report if no errors, else return result
    port_num = port_num or 5002
    
    if window_size then
        w = (window_size/2)
    else
        w = 10.8 -- max seems to be 352k, default: 21.6k
    end
    test_time = test_time or 10
    interval = interval_time or test_time
    
    local result = os.execute("iperf -y C -c'"..host:gsub("'", '').."' -p "..port_num.." -w "..w.."k -t "..test_time.." -i "..interval.." >/tmp/iperf"..port_num..".temp")
    
    if result == 0 then
        return active.bandwidthreport(port_num)
    else
        return result
    end
end

--------------------------------------------------------------------------------
--- UDP BANDWIDTH TEST
-- direction: UP - make this more OOPs

function active.udpserver(port_num, interval_time, buffer_size, packet_size)
    -- currently use default parameters (-t, -P is set at client only)
    -- -i 10 -p 5003 -w 160 KByte
    -- try -w 1024k
    -- this should be called BEFORE iperf client starts on device
    port_num = port_num or 5003
    
    if window_size then
        w = (window_size/2)
    else
        w = 80 -- max window size on openwrt seems to be 320k, default 160k
    end
    
    packet_size = packet_size or 1470 -- datagram size expected
    
    if interval_time then
        os.execute("iperf -u -y C -s -i"..interval_time.." -w "..w.."k -l "..packet_size.." -p "..port_num.." >/tmp/iperf"..port_num..".temp &")
    else
        os.execute("iperf -u -y C -s -w "..w.."k -p "..port_num.." >/tmp/iperf"..port_num..".temp &")
    end
    -- TODO THESE OPTIONS ARE NOT WORKING. PGREP IS A TEMP SOLUTION TO GET iperf PID
    -- can use luaposix instead to call getpid() directly from lua
    
    -- os.execute("echo $! >/var/run/iperf"..port_num..".pid")
    -- return io.lines("/var/run/iperf"..port_num..".pid")
    
    -- return luci.util.exec("echo $!")
    
    return luci.util.exec("pgrep iperf")
end

-- direction: DW
function active.udpclient(port_num, host, bandwidth, window_size, test_time, interval_time)
    -- currently use default parameters (-t, -P is set at client only)
    -- -i 10 -t 10 -p 5004 -w 160 KByte; -b is compulsory
    -- try -w 1024k,
    -- always enter bandwidth in Mbps, socket buffer size in kb
    -- return report if no errors, else return result
    port_num = port_num or 5004
    
    packet_size = packet_size or 1470 -- default packet size
    
    if window_size then
        w = (window_size/2)
    else
        w = 80 -- max seems to be 352k, default: 160k
    end
    test_time = test_time or 10
    interval = interval_time or test_time
    
    local result = os.execute("iperf -u -y C -c'"..host:gsub("'", '').."' -p "..port_num.."  -b "..bandwidth.."m -w "..w.."k -l "..packet_size.." -t "..test_time.." -i "..interval.." >/tmp/iperf"..port_num..".temp")
    
    if result==0 then
        return active.bandwidthreport(port_num)
    else
        return result
    end
end

-------------------------------------------------------------------------------------------

function active.killserver(PID, port_num)
    -- send SIGTERM to iperf server process
    -- if success return bandwidth report, else return error code
    luci.sys.process.signal(PID, 15)
    return active.bandwidthreport(port_num)
end

function active.bandwidthreport(port_num)
    -- port_num = 5001 for server and 5002 for client TCP
    if fs.access("/tmp/iperf"..port_num..".temp") then
        local report = io.lines("/tmp/iperf"..port_num..".temp")
        os.execute("rm -f /tmp/iperf"..port_num..".temp")
        return report
    else
        return -1
    end
end

--------------------------------------------------------------------------------------------
--function active.tcpbandwidth(host, direction)
--    -- invoke iperf server if direction = up and client if direction = dw
--    if direction == "up" then
--        -- currently use default parameters (-t, -P is set at client only)
--        -- -i 10 -p 5001 -w 8.00 KByte
--        -- try -w 1024k
--        -- this should be called BEFORE iperf client starts on device
--        os.execute("iperf -s -i 2 -p 5001 >/tmp/iperfserver.temp &")
--        return luci.util.exec("echo $!")
--    else
--        -- currently use default parameters (-t, -P is set at client only)
--        -- -i 10 -t 10 -p 5001 -w 8.00 KByte -P 1
--        -- try -w 1024k, -P 4 etc
--        luci.util.exec("iperf -i 2 -c'"..host:gsub("'", '').."' -p 5003 >/tmp/iperfclient.temp")
--        return io.lines("/tmp/iperfclient.temp")
--    end
--end




--[[
    CONNTRACK
]]--
function active.saveconntrack()
    -- save /proc/net/nf_conntract > /tmp/<os.time>.conntrack
    local t1 = os.time()
    os.execute("cat /proc/net/nf_conntrack > /tmp/"..t1..".conntrack")

    return t1
    
end

function active.readconntrack(t1)
    -- send saved conntrack temp files to client and delete from Device
    if fs.access("/tmp/"..t1..".conntrack") then
        local report=io.lines("/tmp/"..t1..".conntrack")
        os.execute("rm -rf /tmp/"..t1..".conntrack")
        return report
    else
        return -1
    end
end

-- Returns conntrack information
-- @return	Table with the currently tracked IP connections

function active.conntrack(callback)
	local connt = {}
	if io.open("/proc/net/nf_conntrack", "r") then
            local i = 0
	    for line in io.lines("/proc/net/nf_conntrack") do
                --line = line:match("^(.-( [^ =]+=).-)%2")
                
    		local entry, flags = _parse_mixed_record(line, " +")
                -- don't neglect time wait either
                --if flags[6] ~= "TIME_WAIT" then
                entry.layer3 = flags[1]     -- ipv4
                entry.layer4 = flags[3]     -- udp/tcp
                entry.timeout = flags[5]    -- timeout value when connected or waiting
                if flags[6] then
                    entry.connstate = flags[6]
                end
                if flags[7] then
                    entry.r_connstate = flags[7]
                end
                
                -- not sure why we do this...
                for i=1, #entry do
                    entry[i] = nil
                end

                if callback then
                    callback(entry)
                else
                    --#connt = flow table entry number
                    connt[#connt+1] = entry
                end
                --end
	    end
            
	else
		return nil
	end
	return connt
end

-- Internal functions
function string:split(sep)
        local sep, fields = sep or ":", {}
        local pattern = string.format("([^%s]+)", sep)
        self:gsub(pattern, function(c) fields[#fields+1] = c end)
        return fields
end

function justWords(str)
  local t = {}
  local function helper(word) table.insert(t, word) return "" end
  if not str:gsub("%w+", helper):find"%S" then return t end
end

-- returns data,flags
-- data is table containing all values after "=" sign. if any key is repeated, append key string with "r" for reverse direction
-- flags is a table contains all values of string which were surrounded by spaces in order of occurance. the values without an "=" sign
function _parse_mixed_record(cnt, delimiter)
	delimiter = delimiter or "  "
	local data = {}
	local flags = {}

	for i, l in pairs(cnt:split("\n")) do
            for j, f in pairs(l:split(delimiter)) do
                local k, x, v = f:match('([^%s][^:=]*) *([:=]*) *"*([^\n"]*)"*')
                if k then
                    if x == "" then
                            table.insert(flags, k)
                    else
                        if data[k] then
                            k = 'r_'..k
                        end
                        data[k] = v
                    end
                end
            end
	end
        --for k_,v_ in pairs(data) do
        --    print("data ", k_, v_)
        --end
        --for k_,v_ in pairs(flags) do
        --    print("flags ", k_, v_)
        --end
	return data, flags
end