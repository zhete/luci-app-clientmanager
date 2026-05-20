--[[
Client Manager Controller
Handles routing and page logic for the client management plugin
]]--

module("luci.controller.clientmanager", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/clientmanager") then
		return
	end

	local page = entry({"admin", "network", "clientmanager"},
		firstchild(),
		_("Client Manager"),
		60)
	page.dependent = false
	page.acl_depends = { "luci-app-clientmanager" }

	entry({"admin", "network", "clientmanager", "overview"},
		call("action_overview"),
		_("Device Overview"),
		1)

	entry({"admin", "network", "clientmanager", "control"},
		call("action_control"),
		_("Access Control"),
		2)

	entry({"admin", "network", "clientmanager", "statistics"},
		call("action_statistics"),
		_("Traffic Statistics"),
		3)

	entry({"admin", "network", "clientmanager", "settings"},
		cbi("clientmanager/settings"),
		_("Settings"),
		4)

	entry({"admin", "network", "clientmanager", "api", "devices"},
		call("api_devices"))

	entry({"admin", "network", "clientmanager", "api", "block"},
		call("api_block_device"))

	entry({"admin", "network", "clientmanager", "api", "unblock"},
		call("api_unblock_device"))

	entry({"admin", "network", "clientmanager", "api", "limit"},
		call("api_limit_speed"))

	entry({"admin", "network", "clientmanager", "api", "traffic"},
		call("api_traffic_data"))

	entry({"admin", "network", "clientmanager", "api", "reset"},
		call("api_reset_stats"))

	entry({"admin", "network", "clientmanager", "api", "export"},
		call("api_export_traffic"))

	entry({"admin", "network", "clientmanager", "api", "alias"},
		call("api_set_alias"))
end

function action_overview()
	local devices = get_connected_devices()
	luci.template.render("clientmanager/overview", {
		devices = devices,
		total_devices = #devices
	})
end

function action_control()
	local uci = require("luci.model.uci").cursor()
	local blocked_devices = uci:get_list("clientmanager", "global", "blocked") or {}
	local limited_devices = {}

	uci:foreach("clientmanager", "limit", function(s)
		if s.mac and s.mac ~= "" then
			limited_devices[s.mac:lower()] = {
				download = s.download or "0",
				upload = s.upload or "0"
			}
		end
	end)

	luci.template.render("clientmanager/control", {
		blocked_devices = blocked_devices,
		limited_devices = limited_devices
	})
end

function action_statistics()
	local stats = get_traffic_statistics()
	luci.template.render("clientmanager/statistics", {
		statistics = stats
	})
end

function api_devices()
	luci.http.prepare_content("application/json")
	local devices = get_connected_devices()
	luci.http.write_json({
		success = true,
		devices = devices,
		total = #devices
	})
end

function api_block_device()
	local http = require("luci.http")
	http.prepare_content("application/json")

	local mac = http.formvalue("mac")
	local name = http.formvalue("name") or "Unknown"

	if not mac or not validate_mac(mac) then
		http.write_json({ success = false, error = "Invalid MAC address" })
		return
	end

	local sys = require("luci.sys")
	local result = sys.exec("/usr/libexec/clientmanager-block.sh %s block 2>&1" % { mac_quote(mac) })
	local success = (result:find("successfully") ~= nil)

	if success then
		local uci = require("luci.model.uci").cursor()
		if name and name ~= "Unknown" then
			uci:foreach("clientmanager", "device", function(s)
				if s.mac and s.mac:lower() == mac:lower() then
					uci:set("clientmanager", s[".name"], "name", name)
				end
			end)
			uci:commit("clientmanager")
		end
	end

	http.write_json({
		success = success,
		message = success and "Device blocked successfully" or "Failed to block device"
	})
end

function api_unblock_device()
	local http = require("luci.http")
	http.prepare_content("application/json")

	local mac = http.formvalue("mac")

	if not mac or not validate_mac(mac) then
		http.write_json({ success = false, error = "Invalid MAC address" })
		return
	end

	local sys = require("luci.sys")
	local result = sys.exec("/usr/libexec/clientmanager-block.sh %s unblock 2>&1" % { mac_quote(mac) })
	local success = (result:find("successfully") ~= nil)

	http.write_json({
		success = success,
		message = success and "Device unblocked successfully" or "Failed to unblock device"
	})
end

function api_limit_speed()
	local http = require("luci.http")
	http.prepare_content("application/json")

	local mac = http.formvalue("mac")
	local download = http.formvalue("download") or "0"
	local upload = http.formvalue("upload") or "0"

	if not mac or not validate_mac(mac) then
		http.write_json({ success = false, error = "Invalid MAC address" })
		return
	end

	if not download:match("^%d+$") or not upload:match("^%d+$") then
		http.write_json({ success = false, error = "Invalid speed value" })
		return
	end

	local sys = require("luci.sys")
	local result = sys.exec("/usr/libexec/clientmanager-speedlimit.sh %s %s %s 2>&1" % {
		mac_quote(mac), download, upload
	})
	local success = (result:find("applied") ~= nil or result:find("removed") ~= nil)

	http.write_json({
		success = success,
		message = success and "Speed limit applied" or "Failed to apply speed limit"
	})
end

function api_traffic_data()
	luci.http.prepare_content("application/json")
	local stats = get_traffic_statistics()
	luci.http.write_json({
		success = true,
		data = stats
	})
end

function api_reset_stats()
	local http = require("luci.http")
	http.prepare_content("application/json")

	local sys = require("luci.sys")
	sys.exec("/usr/libexec/clientmanager-traffic.sh reset 2>&1")

	http.write_json({
		success = true,
		message = "Statistics reset successfully"
	})
end

function api_export_traffic()
	local http = require("luci.http")
	local sys = require("luci.sys")
	local format = http.formvalue("format") or "csv"

	local stats = get_traffic_statistics()

	if format == "json" then
		http.prepare_content("application/json")
		http.header("Content-Disposition", 'attachment; filename="traffic_stats.json"')
		http.write_json(stats)
	else
		http.prepare_content("text/csv")
		http.header("Content-Disposition", 'attachment; filename="traffic_stats.csv"')
		http.write("Device Name,MAC Address,IP Address,Download (bytes),Upload (bytes),Total (bytes),Last Seen\n")
		if stats and stats.devices then
			for _, dev in ipairs(stats.devices) do
				http.write(string.format('%s,%s,%s,%d,%d,%d,%s\n',
					dev.hostname or "Unknown",
					dev.mac or "",
					dev.ip or "",
					tonumber(dev.download) or 0,
					tonumber(dev.upload) or 0,
					(tonumber(dev.download) or 0) + (tonumber(dev.upload) or 0),
					dev.last_seen or ""
				))
			end
		end
	end
end

function api_set_alias()
	local http = require("luci.http")
	http.prepare_content("application/json")

	local mac = http.formvalue("mac")
	local alias = http.formvalue("alias") or ""

	if not mac or not validate_mac(mac) then
		http.write_json({ success = false, error = "Invalid MAC address" })
		return
	end

	local uci = require("luci.model.uci").cursor()
	local found = false

	uci:foreach("clientmanager", "device", function(s)
		if s.mac and s.mac:lower() == mac:lower() then
			uci:set("clientmanager", s[".name"], "alias", alias)
			found = true
		end
	end)

	if not found then
		local section = uci:add("clientmanager", "device")
		uci:set("clientmanager", section, "mac", mac:lower())
		uci:set("clientmanager", section, "alias", alias)
	end

	uci:commit("clientmanager")

	http.write_json({
		success = true,
		message = "Alias saved"
	})
end

function get_connected_devices()
	local devices = {}
	local sys = require("luci.sys")
	local uci = require("luci.model.uci").cursor()

	local leases_file = sys.exec("cat /tmp/dhcp.leases 2>/dev/null") or ""
	local dhcp_leases = {}

	for line in leases_file:gmatch("[^\r\n]+") do
		local timestamp, mac, ip, name, id = line:match("^(%d+) (%S+) (%S+) (%S+) (%S+)")
		if mac and ip then
			dhcp_leases[mac:lower()] = {
				ip = ip,
				name = (name ~= "*" and name) or nil,
				expires = tonumber(timestamp) or 0
			}
		end
	end

	local aliases = {}
	uci:foreach("clientmanager", "device", function(s)
		if s.mac and s.alias and s.alias ~= "" then
			aliases[s.mac:lower()] = s.alias
		end
	end)

	local blocked_set = {}
	local blocked_list = uci:get_list("clientmanager", "global", "blocked") or {}
	for _, bmac in ipairs(blocked_list) do
		if bmac and bmac ~= "" then
			blocked_set[bmac:lower()] = true
		end
	end

	local arp_table = sys.exec("cat /proc/net/arp 2>/dev/null") or ""

	for line in arp_table:gmatch("[^\r\n]+") do
		local ip, hw_type, flags, mac, mask, device = line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
		if mac and mac:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") and mac ~= "00:00:00:00:00:00" then
			local mac_lower = mac:lower()
			local dhcp_info = dhcp_leases[mac_lower] or {}

			local is_online = (flags == "0x2" or flags == "0x6")

			local hostname = dhcp_info.name
			if not hostname then
				if validate_ip(ip) then
					hostname = sys.exec("nslookup %s 127.0.0.1 2>/dev/null | grep 'name =' | head -1 | awk '{print $4}' | sed 's/\\.$//'" % { ip }) or ""
					if hostname == "" then hostname = nil end
				end
			end

			local oui = mac:sub(1, 8):gsub(":", "-"):upper()
			local vendor = get_vendor_by_oui(oui) or "Unknown"

			local display_name = aliases[mac_lower] or hostname or "Unknown"

			table.insert(devices, {
				mac = mac_lower,
				ip = ip,
				hostname = display_name,
				vendor = vendor,
				interface = device or "br-lan",
				online = is_online,
				blocked = blocked_set[mac_lower] or false,
				last_seen = dhcp_info.expires and os.date("%Y-%m-%d %H:%M:%S", dhcp_info.expires) or "Unknown",
				type = guess_device_type(vendor, hostname or "")
			})
		end
	end

	table.sort(devices, function(a, b)
		if a.online ~= b.online then
			return a.online and not b.online
		end
		if a.blocked ~= b.blocked then
			return not a.blocked
		end
		return a.ip < b.ip
	end)

	return devices
end

function get_vendor_by_oui(oui)
	local nixio = require("nixio")
	local db_path = "/usr/share/clientmanager/oui.txt"
	local fs = nixio.fs

	if not fs.access(db_path) then
		return nil
	end

	local f = io.open(db_path, "r")
	if not f then return nil end

	for line in f:lines() do
		line = line:match("^%s*(.-)%s*$")
		if line ~= "" and line:sub(1, 1) ~= "#" then
			local prefix, vendor = line:match("^(%S*)%s+(.+)$")
			if prefix == oui then
				f:close()
				return vendor
			end
		end
	end

	f:close()
	return nil
end

function guess_device_type(vendor, hostname)
	vendor = vendor or ""
	hostname = hostname or ""

	local v = vendor:lower()
	local h = hostname:lower()

	if h:match("iphone") or h:match("android") or h:match("galaxy") or h:match("pixel") or h:match("huawei%-") or h:match("redmi") then
		return "Mobile"
	end

	if h:match("ipad") or h:match("tablet") then
		return "Tablet"
	end

	if h:match("tv") or h:match("roku") or h:match("chromecast") or h:match("fire%-tv") then
		return "Smart TV"
	end

	if h:match("echo") or h:match("home") or h:match("nest") or h:match("ring") or h:match("smart") then
		return "IoT Device"
	end

	if v:match("router") or v:match("mikrotik") or v:match("ubiquiti") or v:match("tp%-link") or v:match("netgear") or v:match("asus") then
		return "Router"
	end

	if h:match("playstation") or h:match("xbox") or h:match("nintendo") or h:match("switch") then
		return "Game Console"
	end

	if v:match("apple") and not h:match("tv") then
		return "Mobile"
	end

	if v:match("samsung") then
		return "Mobile"
	end

	if v:match("huawei") then
		return "Mobile"
	end

	if v:match("xiaomi") then
		return "Mobile"
	end

	if v:match("vmware") or v:match("virtual") then
		return "Virtual"
	end

	return "Computer"
end

function get_traffic_statistics()
	local sys = require("luci.sys")
	local result = sys.exec("/usr/libexec/clientmanager-traffic.sh stats json 2>/dev/null") or ""

	if result == "" then
		return { devices = {} }
	end

	local json = require("luci.jsonc")
	local data = json.parse(result)

	if not data or not data.devices then
		return { devices = {} }
	end

	return data
end

function validate_mac(mac)
	if not mac then return false end
	return mac:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") ~= nil
end

function validate_ip(ip)
	if not ip then return false end
	local a, b, c, d = ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
	if not a then return false end
	a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
	return a and b and c and d and
		a >= 0 and a <= 255 and
		b >= 0 and b <= 255 and
		c >= 0 and c <= 255 and
		d >= 0 and d <= 255
end

function mac_quote(mac)
	return "'" .. mac:gsub("'", "'\\''") .. "'"
end
