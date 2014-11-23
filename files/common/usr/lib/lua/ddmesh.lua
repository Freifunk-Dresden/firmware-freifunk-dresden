--[[----------------------------------------------------------------------------------------
ddmesh.lua
library for different freifunk functions
version: 10 

    0 - 99		vserver
 1000		spezial:start point for registrator
 1001 - 50999	Knotennummer für Firmware: vergeben durch registrator
51000 - 59999   Knotennummer für eigen Aufgebaute Knoten
60000 - 65278	Reserviert
65279		broadcast (10.200.255.255)
-------------------------------------------------------------------------------------------]]

----------------- ipcalc ---------------
ipcalc={}
ipcalc.data={}
ipcalc.data.min=1001
ipcalc.data.max=59999

function split(str, delim, maxNb)
    -- Eliminate bad cases...
    if string.find(str, delim) == nil then
        return { str }
    end
    if maxNb == nil or maxNb < 1 then
        maxNb = 0    -- No limit
    end
    local result = {}
    local pat = "(.-)" .. delim .. "()"
    local nb = 0
    local lastPos
    for part, pos in string.gfind(str, pat) do
        nb = nb + 1
        result[nb] = part
        lastPos = pos
        if nb == maxNb then break end
    end
    -- Handle the last field
    if nb ~= maxNb then
        result[nb + 1] = string.sub(str, lastPos)
    end
    return result
end

function ipcalc.rCalcIp(ip)
    if ip==nil or ip=="" then return -1 end
    a = split(ip, "[.]")
    if #a ~= 4 then return -1 end
    if a[1]==nil or a[1]=="" or tonumber(a[1]) ~= 10 then return -1 end
    if a[2]==nil or a[2]=="" or tonumber(a[2]) ~= 200 and tonumber(a[2]) ~= 201 then return -1 end
    if a[3]==nil or a[3]=="" or tonumber(a[3]) < 0 or tonumber(a[3]) > 255 then return -1 end
    if a[4]==nil or a[4]=="" or tonumber(a[4]) <= 0 or tonumber(a[4]) > 255 then return -1 end

    node=(a[3]*255) + (a[4]-1)
    if node < 0 or node > ipcalc.data.max then return -1 end
    return node
end

function ipcalc.calc(node)
    if node==nil or node=="" then return -1 end
    node=tonumber(node)
    if node==nil or node=="" then return -1 end
    if node < 0 or node > ipcalc.data.max then return -1 end

    local domain	= "freifunk-dresden.de"

    --local major   = 200 + math.floor(node / (256 * 255)) % 256
    local primary_major   = 200
    local nonprimary_major   = 201
    local middle  =       math.floor(node / 255) % 256
    local minor   = (node % 255) + 1 

    local meshnet	= "10"
    local nodeip  	= meshnet .. "." .. primary_major .. "." .. middle .. "." .. minor 
    local nonprimary_ip = meshnet .. "." .. nonprimary_major .. "." .. middle .. "." .. minor
    local meshnetmask	= "255.255.0.0"
    local meshpre 	= 16
    local meshbroadcast = "10.255.255.255"

    local mesh6pre	= "48"
    local mesh6net	= "fd11:11ae:7466::"
    -- client range
    local mesh6nodenet= "fd11:11ae:7466:" .. string.format("%x", node) .. "::"
    local mesh6ip	= mesh6nodenet .. "1" 
    local mesh6nodepre= "64"

    ipcalc.data.node               = node
    ipcalc.data.domain             = domain 
    ipcalc.data.hostname           = "r" .. node
    ipcalc.data.ip                 = nodeip 
    ipcalc.data.nonprimary_ip      = nonprimary_ip 
    ipcalc.data.netpre             = meshpre
    ipcalc.data.netmask            = meshnetmask 
    ipcalc.data.broadcast          = meshbroadcast 
    ipcalc.data.mesh6ip		   = mesh6ip
    ipcalc.data.mesh6net	   = mesh6net
    ipcalc.data.mesh6pre	   = mesh6pre
    ipcalc.data.mesh6nodenet	   = mesh6nodenet
    ipcalc.data.mesh6nodepre	   = mesh6nodepre
end

function ipcalc.print(node)

    if node==nil or node=="" then print("ERROR"); return -1 end
    node=tonumber(node)
    if node==nil then print("ERROR"); return -1 end
    if node < 0 or node > ipcalc.data.max then return -1 end
    ipcalc.calc(node)

    for k,v in pairs(ipcalc.data)
    do
        print("export _ddmesh_"..k.."="..v)
    end
end

function iplookup(ip)
	if ip==nil then return -1 end
	return ipcalc.rCalcIp(ip)
end

function lookup(node)
	if node==nil then return -1 end
	if string.sub(node,1,1) == "r" then 
		n=tonumber(string.sub(node,2)) 
	else 
		n=tonumber(node)
	end
	if n==nil then return -1 end
	if n < 0 or n > ipcalc.data.max then return -1 end
	ipcalc.calc(n)
	return ipcalc.data.ip
end

