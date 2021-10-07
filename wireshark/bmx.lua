-- Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de
-- GNU General Public License Version 3

-- This is a simple wireshark dissection lua function to display bmx packages
-- Copy it to ~/.local/lib/wireshark/plugins


-- declare our protocol
bmx_proto = Proto("BMX","BMX Protocol")


-- define fields that can be used for searching/filtering.
-- So it can be filtered I have use these filter to add in the tree below.
f_netid=ProtoField.uint16("bmx.netid", "Network ID") 
f_ogm_package_size=ProtoField.uint16("bmx.ogm.size", "Packet size")

-- flags: create a bool. 1: name of filter; 2: displayed text; 3: bytes that hold the flags;
-- 4: if the mask delivers true, then display either of one strings
--  5: bitmask
f_flag_uni=ProtoField.bool("bmx.ogm.flag.uni", "Flag: Uni-directional",8,{"YES","no"},0x01)
f_flag_direct=ProtoField.bool("bmx.ogm.flag.direct", "Flag: direct-link",8,{"YES","no"},0x02)
f_flag_clone=ProtoField.bool("bmx.ogm.flag.clone", "Flag: clone",8,{"YES","no"},0x04)

f_pws=ProtoField.uint8("bmx.ogm.pws", "PWS")
f_cpu=ProtoField.uint8("bmx.ogm.cpu", "CPU")
f_ttl=ProtoField.uint8("bmx.ogm.ttl", "TTL")
f_prevHopId=ProtoField.uint8("bmx.ogm.hopID", "Previous Hop ID")
f_orig=ProtoField.ipv4("bmx.ogm.orig.addr","Originator IP")
f_seqno=ProtoField.uint16("bmx.ogm.seqno", "Sequence number")

f_ext_gw_addr=ProtoField.ipv4("bmx.ogm.ext.gw.addr","Gateway IP")
f_ext_gw_class=ProtoField.uint8("bmx.ogm.ext.gw.class", "Gateway Class")
f_ext_gw_flag_community=ProtoField.bool("bmx.ogm.ext.gw.flag.community", "Flag: Community Gateway",8,{"YES","no"}, 0x01)
f_ext_gw_flag_owt=ProtoField.bool("bmx.ogm.ext.gw.flag.owt", "Flag: One Way Tunnel",8,{"YES","no"}, 0x02)

f_ext_pip_addr=ProtoField.ipv4("bmx.ogm.ext.pip.addr","Primary interface packet IP")
f_ext_pip_seqno=ProtoField.uint16("bmx.ogm.ext.pip.seqno", "Sequence number")

bmx_proto.fields={f_orig, f_seqno,f_prevHopId, f_ttl, f_cpu, f_pws, f_flag_uni
		, f_flag_direct, f_flag_clone, f_ogm_package_size
		, f_ext_gw_addr, f_ext_gw_class, f_ext_gw_flag_community, f_ext_gw_flag_owt
		, f_ext_pip_addr, f_ext_pip_seqno, f_netid}


function ipStr(number)
	n1=bit.band(number, 0xff)
	n2=bit.band(bit.rshift(number, 8), 0xff)
	n3=bit.band(bit.rshift(number, 16), 0xff)
	n4=bit.band(bit.rshift(number, 24), 0xff)
	return n4.."."..n3.."."..n2.."."..n1
end

-- create a function to dissect it
function bmx_proto.dissector(buffer,pinfo,tree)
	length = buffer:len()
	if length == 0 then return end

	-- simply use name from above. pinfo.cols represends the colums in 
	-- paket list of the window in wireshare window
	pinfo.cols.protocol = bmx_proto.name

	-- add a tree for protocol (there are different "add" funtions, that can be used)
	-- the differnt add function can add prepared objects (called fields) how values
	-- are displayed. see definition above
	local subtree = tree:add(bmx_proto,buffer(),"BMX Routing Protocol Data")

	-- bat_header
	local bmx_ver=buffer(0,1):uint()
	local netid=buffer(1,2):uint()
	-- take size byte and multiply it with 4 to get the size including the bat header
	local packet_size = buffer(3,1):uint() * 4 
	local line = string.format("Ver: 0x%2.2x, NetworkId: %u, Data Size: %d", bmx_ver, netid, packet_size - 4)

	local tree_bat_header = subtree:add(buffer(0,4),"Header:" .. line)
	-- add() is for bigendian; add_le() is for little endian
	tree_bat_header:add(buffer(0,1),"version: " .. bmx_ver)
	tree_bat_header:add(f_netid,buffer(1,2))
	tree_bat_header:add(buffer(3,1), "Size:", packet_size - 4)

	-- check coded size against buffer (packet_size contains the bat_header too, so 
	-- I can check against the buffer length
	if packet_size > length then return end

	-- process all objects; packet_size will be decremented
	local offset = 4
	while (offset+4) <= packet_size 
	do
		-- extract object header (big endian)
		local tmp = buffer(offset,1):uint()
		local ext_msg = bit.band(bit.rshift(tmp,7),1)
		local tmp_type = bit.band(bit.rshift(tmp,4), 0x07)
		local bat_type = "Unknown"
		if tmp_type == 0 then bat_type = "OGM" end
		-- ext_msg of the header is not used. to detect an extension I have to check the size


		-- includes size of bat_packet_common
		local size = buffer(offset+1, 1):uint() * 4
		if size > packet_size then return end

		if tmp_type == 0 then
			-- OGM
		
			-- check if we have an extension or more
			-- the normal OGM has 12 bytes. If size is greater it has extensions, but this must be multiple of 8
			-- which is sizeof(ext_packet)
			local ext_size=0
			local ext_str=""
			if size > 12 then
				ext_size=size-12
				ext_str="{ EXTENSION }"
			end

			ogm_flag_clone = bit.band(bit.rshift(tmp,2),1)
			ogm_flag_direct = bit.band(bit.rshift(tmp,1),1) 
			ogm_flag_unidir = bit.band(tmp,1)
	
			ogm_pws = buffer(offset+2, 1):uint()
			ogm_misc = buffer(offset+3, 1):uint() -- hold cpu load stuff
			ogm_ttl = buffer(offset+4, 1):uint()
			ogm_prevHopId = buffer(offset+5, 1):uint()
			ogm_seqno = buffer(offset+6, 2):uint()
			ogm_orig = buffer(offset+8, 4):uint()

		
			local line = string.format("Data (offset:%3d, len:%3d): OGM %-15.15s, ttl:%02d, seqno:%5d, pwd:%3d, cpu:%3d, prvHopId:%3d, unidirect:%d, direct:%d, clone:%d %s"
					, offset, size 
					, ipStr(ogm_orig), ogm_ttl, ogm_seqno, ogm_pws, ogm_misc
					, ogm_prevHopId, ogm_flag_unidir, ogm_flag_direct, ogm_flag_clone, ext_str)

			local tree_bat_packet = subtree:add(buffer(offset,size), line)
			-- the size filed is coded and must be lshifted by 2, To display the correct value and
			-- still have the byte marked in wireshark when I click on "Packet size", I simply add 
			-- the value as third paramter. (don't know why this works).
			tree_bat_packet:add(f_ogm_package_size, buffer(offset+1,1), size )
			tree_bat_packet:add(f_flag_clone,buffer(offset,1))
			tree_bat_packet:add(f_flag_direct,buffer(offset,1))
			tree_bat_packet:add(f_flag_uni,buffer(offset,1))
			tree_bat_packet:add(f_pws,buffer(offset+2,1) )
			tree_bat_packet:add(f_cpu,buffer(offset+3,1))
			tree_bat_packet:add(f_ttl,buffer(offset+4,1))
			tree_bat_packet:add(f_prevHopId, buffer(offset+5,1))
			tree_bat_packet:add(f_seqno,buffer(offset+6,2))
			tree_bat_packet:add(f_orig,buffer(offset+8,4))

			-- extension
			if ext_size > 0 then
				ext_offset = offset+12
				ext_end=offset+size
--				local exttree=tree_bat_packet:add(buffer(ext_offset,ext_size),"Extensions (offset: "..ext_offset..")")
				local exttree=tree_bat_packet

				-- run through extensions, all do have a fix size of 8 bytes
				while ext_offset+8 <= ext_end 
				do
					-- big endian
					local tmp = buffer(ext_offset,1):uint()
					local ext_msg = bit.band(bit.rshift(tmp,7),0x01) -- must be 1
					local ext_type = bit.band(bit.rshift(tmp, 2),0x1f)
					local ext_releated = bit.band(tmp,3)

					local d8 = buffer(ext_offset+1,1):uint()
					local d16 = buffer(ext_offset+2,2):uint()
					local d32 = buffer(ext_offset+4,4):uint()

					-- extension types: look for EXT_TYPE_64B_GW, EXT_TYPE_64B_PIP, EXT_TYPE_64B_NETID
					if ext_type == 0 then 
						-- EXT_TYPE_64B_GW
						gw_type = ""
						if bit.band(ext_releated, 0x01) == 0x01 then gw_type = gw_type .. " Community-Gateway" end
						if bit.band(ext_releated, 0x02) == 0x02 then gw_type = gw_type .. " One-Way-Tunnel" end
						
						local line = string.format("(offset: %3d) Gateway: %s, %s", ext_offset, ipStr(d32), gw_type)
						local exttree2=exttree:add(buffer(ext_offset, 8), line)
						exttree2:add(f_ext_gw_flag_community, buffer(ext_offset,1))
						exttree2:add(f_ext_gw_flag_owt, buffer(ext_offset,1))

						exttree2:add(f_ext_gw_class, buffer(ext_offset+1,1))
						exttree2:add(buffer(ext_offset+2,2),"Extension: GW port:" .. d16)
						exttree2:add(f_ext_gw_addr, buffer(ext_offset+4,4))

					elseif ext_type == 2 then
					-- EXT_TYPE_64B_PIP
						local line = string.format("Primary interface: %s, seqno:%d", ipStr(d32), d16)
						local exttree2=exttree:add(buffer(ext_offset, 8), line)
						exttree2:add(f_ext_pip_seqno, buffer(ext_offset+2,2))
						exttree2:add(f_ext_pip_addr, buffer(ext_offset+4,4))

--					elseif ext_type == 3 then
--					-- EXT_TYPE_64B_NETID
--						local line = string.format("Network ID: %d", d32)
--						local exttree2=exttree:add(buffer(ext_offset, 8), line)
--						exttree2:add(f_ext_netid, buffer(ext_offset+2,2))
					else
						-- unknown
					end
					ext_offset = ext_offset + 8
				end

			end

		else
			-- unknown type
			tree_bat_packet:add(buffer(offset,1),"bat_type: " .. bat_type)
			tree_bat_packet:add(buffer(offset+1,1),"size: " .. size)
			tree_bat_packet:add(buffer(offset,size),"data: " .. buffer(offset,size))
		end


		offset = offset + size


		
	end

end
-- load the udp.port table
udp_table = DissectorTable.get("udp.port")
-- register our protocol to handle udp port 
udp_table:add(4305,bmx_proto)

