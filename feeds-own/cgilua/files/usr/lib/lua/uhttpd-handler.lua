#!/usr/bin/lua

-- Generic WSAPI CGI launcher, extracts application to launch
-- either from the command line (use #!wsapi in the script)
-- or from SCRIPT_FILENAME/PATH_TRANSLATED

local sapi = require "wsapi.sapi"
local cgi = require "wsapi.cgi"

local _env = {}


function trace (event)
 -- get info about 2. function in call stack.request name,
 local a=debug.getinfo(2)
 local f=a["short_src"]
 local l=a["currentline"]
 local n=a["name"]
 if n == nil then n="nil" end
 local w=a["namewhat"]
 print(f..":"..l..", func: "..n..", type: "..w)
end

function print_env(env)

 print("HTTP/1.0 200 OK\r\n")
 print("Content-Type: text/plain\r\n\r\n")
	
-- for n in pairs(uhttpd) do print(n) end
 print("docroot="..uhttpd.docroot)
 for n,k in pairs(env) do 
 	if type(k) == "table" then
 		for n2,k2 in pairs(k) do 
 			if k2 == nil then k2 = "nil" end
 			print(type(k2).."/"..n..":"..n2.." = "..k2)
 		end
 	else
 		if k == nil then k="nil" end
	 	print(type(k).."/"..n .. " = " .. k)
 	end
  end
 print("=========")
end

local function sapi_loader(wsapi_env)
	wsapi_env = _env	
	return sapi.run(wsapi_env)
end 

function handle_request(env)
	_env = env
--	print_env(_env)
--	debug.sethook(trace,"c")
	
	-- add missing variables	
	if not _env["PATH_INFO"] or _env["PATH_INFO"]=="" then _env["PATH_INFO"]="index.lp" end
 	_env["PATH_TRANSLATED"]=uhttpd.docroot.."/"..env["PATH_INFO"]
 	_env["SCRIPT_FILENAME"]=uhttpd.docroot.."/"..env["PATH_INFO"]
	_env["DOCUMENT_ROOT"]= uhttpd.docroot
	_env["REMOTE_HOST"]= env["REMOTE_ADDR"]
	cgi.run(sapi_loader)
end
