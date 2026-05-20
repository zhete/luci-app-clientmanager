module("luci.controller.clientmanager", package.seeall)

function index()
	local page = entry({"admin", "services", "clientmanager"},
		firstchild(),
		_("客户端管理"),
		60)
	page.dependent = false
	page.acl_depends = { "luci-app-clientmanager" }

	entry({"admin", "services", "clientmanager", "overview"},
		call("action_overview"),
		_("设备概览"),
		1)

	entry({"admin", "services", "clientmanager", "control"},
		call("action_control"),
		_("访问控制"),
		2)

	entry({"admin", "services", "clientmanager", "statistics"},
		call("action_statistics"),
		_("流量统计"),
		3)

	entry({"admin", "services", "clientmanager", "settings"},
		cbi("clientmanager/settings"),
		_("设置"),
		4)

	entry({"admin", "services", "clientmanager", "api", "devices"},
		call("api_devices"))

	entry({"admin", "services", "clientmanager", "api", "block"},
		call("api_block_device"))

	entry({"admin", "services", "clientmanager", "api", "unblock"},
		call("api_unblock_device"))

	entry({"admin", "services", "clientmanager", "api", "limit"},
		call("api_limit_speed"))

	entry({"admin", "services", "clientmanager", "api", "traffic"},
		call("api_traffic_data"))

	entry({"admin", "services", "clientmanager", "api", "reset"},
		call("api_reset_stats"))

	entry({"admin", "services", "clientmanager", "api", "export"},
		call("api_export_traffic"))

	entry({"admin", "services", "clientmanager", "api", "alias"},
		call("api_set_alias"))

	entry({"admin", "services", "clientmanager", "api", "schedule"},
		call("api_schedule"))

	entry({"admin", "services", "clientmanager", "api", "history"},
		call("api_connection_history"))

	entry({"admin", "services", "clientmanager", "api", "realtime"},
		call("api_realtime_speed"))
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
	local allowed_devices = uci:get_list("clientmanager", "global", "allowed") or {}
	local mode = uci:get("clientmanager", "global", "mode") or "blacklist"
	local limited_devices = {}
	local scheduled_devices = {}

	uci:foreach("clientmanager", "limit", function(s)
		if s.mac and s.mac ~= "" then
			limited_devices[s.mac:lower()] = {
				download = s.download or "0",
				upload = s.upload or "0"
			}
		end
	end)

	uci:foreach("clientmanager", "schedule", function(s)
		if s.mac and s.mac ~= "" then
			table.insert(scheduled_devices, {
				mac = s.mac,
				name = s.name or s.mac,
				action = s.action or "block",
				mon = format_schedule_range(s.mon_start, s.mon_end),
				tue = format_schedule_range(s.tue_start, s.tue_end),
				wed = format_schedule_range(s.wed_start, s.wed_end),
				thu = format_schedule_range(s.thu_start, s.thu_end),
				fri = format_schedule_range(s.fri_start, s.fri_end),
				sat = format_schedule_range(s.sat_start, s.sat_end),
				sun = format_schedule_range(s.sun_start, s.sun_end),
			})
		end
	end)

	luci.template.render("clientmanager/control", {
		blocked_devices = blocked_devices,
		allowed_devices = allowed_devices,
		limited_devices = limited_devices,
		scheduled_devices = scheduled_devices,
		mode = mode
	})
end

function action_statistics()
	local stats = get_traffic_statistics()
	luci.template.render("clientmanager/statistics", {
		statistics = stats
	})
end

function format_schedule_range(start_time, end_time)
	if not start_time or start_time == "" then
		return "-"
	end
	return (start_time or "?") .. "-" .. (end_time or "?")
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
		log_event("block", mac, name)
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

	if success then
		log_event("unblock", mac, "")
	end

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
		http.write("Device Name,MAC Address,IP Address,Download (bytes),Upload (bytes),Total (bytes),Online Hours,Last Seen\n")
		if stats and stats.devices then
			for _, dev in ipairs(stats.devices) do
				http.write(string.format('%s,%s,%s,%d,%d,%d,%.1f,%s\n',
					dev.hostname or "Unknown",
					dev.mac or "",
					dev.ip or "",
					tonumber(dev.download) or 0,
					tonumber(dev.upload) or 0,
					(tonumber(dev.download) or 0) + (tonumber(dev.upload) or 0),
					tonumber(dev.online_hours) or 0,
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

function api_schedule()
	local http = require("luci.http")
	http.prepare_content("application/json")

	local action_type = http.formvalue("action_type")

	if action_type == "add" then
		local mac = http.formvalue("mac")
		local name = http.formvalue("name") or ""
		local sched_action = http.formvalue("sched_action") or "block"
		local days = {"mon", "tue", "wed", "thu", "fri", "sat", "sun"}

		if not mac or not validate_mac(mac) then
			http.write_json({ success = false, error = "Invalid MAC address" })
			return
		end

		local uci = require("luci.model.uci").cursor()
		local section = uci:add("clientmanager", "schedule")
		uci:set("clientmanager", section, "mac", mac:lower())
		uci:set("clientmanager", section, "name", name)
		uci:set("clientmanager", section, "action", sched_action)

		for _, day in ipairs(days) do
			local start_val = http.formvalue(day .. "_start") or ""
			local end_val = http.formvalue(day .. "_end") or ""
			if start_val ~= "" then
				uci:set("clientmanager", section, day .. "_start", start_val)
			end
			if end_val ~= "" then
				uci:set("clientmanager", section, day .. "_end", end_val)
			end
		end

		uci:commit("clientmanager")
		http.write_json({ success = true, message = "Schedule added" })

	elseif action_type == "delete" then
		local mac = http.formvalue("mac")
		if not mac then
			http.write_json({ success = false, error = "MAC required" })
			return
		end

		local uci = require("luci.model.uci").cursor()
		uci:foreach("clientmanager", "schedule", function(s)
			if s.mac and s.mac:lower() == mac:lower() then
				uci:delete("clientmanager", s[".name"])
			end
		end)
		uci:commit("clientmanager")
		http.write_json({ success = true, message = "Schedule removed" })

	else
		local uci = require("luci.model.uci").cursor()
		local schedules = {}
		uci:foreach("clientmanager", "schedule", function(s)
			if s.mac and s.mac ~= "" then
				table.insert(schedules, {
					mac = s.mac,
					name = s.name or s.mac,
					action = s.action or "block",
					mon = format_schedule_range(s.mon_start, s.mon_end),
					tue = format_schedule_range(s.tue_start, s.tue_end),
					wed = format_schedule_range(s.wed_start, s.wed_end),
					thu = format_schedule_range(s.thu_start, s.thu_end),
					fri = format_schedule_range(s.fri_start, s.fri_end),
					sat = format_schedule_range(s.sat_start, s.sat_end),
					sun = format_schedule_range(s.sun_start, s.sun_end),
				})
			end
		end)
		http.write_json({ success = true, schedules = schedules })
	end
end

function api_connection_history()
	local http = require("luci.http")
	http.prepare_content("application/json")

	local mac = http.formvalue("mac")
	local limit = tonumber(http.formvalue("limit")) or 50

	local history = read_connection_history(mac, limit)

	http.write_json({
		success = true,
		history = history
	})
end

function api_realtime_speed()
	local http = require("luci.http")
	http.prepare_content("application/json")

	local sys = require("luci.sys")
	local result = sys.exec("/usr/libexec/clientmanager-traffic.sh realtime 2>/dev/null") or ""

	local devices = {}
	if result ~= "" then
		local json = require("luci.jsonc")
		local data = json.parse(result)
		if data and data.devices then
			devices = data.devices
		end
	end

	http.write_json({
		success = true,
		devices = devices,
		timestamp = os.time()
	})
end

function get_connected_devices()
	local devices = {}
	local sys = require("luci.sys")
	local uci = require("luci.model.uci").cursor()

	local mode = uci:get("clientmanager", "global", "mode") or "blacklist"

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

	local allowed_set = {}
	local allowed_list = uci:get_list("clientmanager", "global", "allowed") or {}
	for _, amac in ipairs(allowed_list) do
		if amac and amac ~= "" then
			allowed_set[amac:lower()] = true
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

			local is_blocked = false
			if mode == "whitelist" then
				is_blocked = not allowed_set[mac_lower]
			else
				is_blocked = blocked_set[mac_lower] or false
			end

			local online_hours = get_online_hours(mac_lower)

			table.insert(devices, {
				mac = mac_lower,
				ip = ip,
				hostname = display_name,
				vendor = vendor,
				interface = device or "br-lan",
				online = is_online,
				blocked = is_blocked,
				last_seen = dhcp_info.expires and os.date("%Y-%m-%d %H:%M:%S", dhcp_info.expires) or "Unknown",
				type = guess_device_type(vendor, hostname or ""),
				online_hours = online_hours,
				mode = mode
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
	local db_path = "/usr/share/clientmanager/oui.txt"
	local fs = require("nixio").fs

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
		return "手机"
	end
	if h:match("ipad") or h:match("tablet") then
		return "平板"
	end
	if h:match("tv") or h:match("roku") or h:match("chromecast") or h:match("fire%-tv") then
		return "智能电视"
	end
	if h:match("echo") or h:match("home") or h:match("nest") or h:match("ring") or h:match("smart") then
		return "物联网设备"
	end
	if v:match("mikrotik") or v:match("ubiquiti") or v:match("tp%-link") or v:match("netgear") or v:match("asus") then
		return "路由器"
	end
	if h:match("playstation") or h:match("xbox") or h:match("nintendo") or h:match("switch") then
		return "游戏机"
	end
	if v:match("apple") and not h:match("tv") then
		return "手机"
	end
	if v:match("samsung") or v:match("huawei") or v:match("xiaomi") then
		return "手机"
	end
	if v:match("vmware") or v:match("virtual") then
		return "虚拟设备"
	end

	return "电脑"
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

function get_online_hours(mac)
	local sys = require("luci.sys")
	local history_file = "/etc/clientmanager/online.db"

	if not nixio.fs.access(history_file) then
		return 0
	end

	local total_seconds = 0
	local f = io.open(history_file, "r")
	if not f then return 0 end

	for line in f:lines() do
		local entry_mac, start_ts, end_ts = line:match("^(%S+)|(%d+)|(%d+)$")
		if entry_mac and entry_mac:lower() == mac:lower() and start_ts and end_ts then
			total_seconds = total_seconds + (tonumber(end_ts) - tonumber(start_ts))
		end
	end

	f:close()
	return math.floor(total_seconds / 3600 * 10 + 0.5) / 10
end

function log_event(event_type, mac, name)
	local log_dir = "/etc/clientmanager"
	local log_file = log_dir .. "/events.log"

	require("nixio").fs.mkdir(log_dir)

	local f = io.open(log_file, "a")
	if f then
		f:write(string.format("%s|%s|%s|%s\n",
			os.date("%Y-%m-%d %H:%M:%S"),
			event_type,
			mac or "",
			name or ""))
		f:close()
	end
end

function read_connection_history(mac, limit)
	local sys = require("luci.sys")
	local history = {}
	local history_file = "/etc/clientmanager/events.log"

	if not nixio.fs.access(history_file) then
		return history
	end

	limit = limit or 50

	local f = io.open(history_file, "r")
	if not f then return history end

	local lines = {}
	for line in f:lines() do
		table.insert(lines, line)
	end
	f:close()

	local start_idx = math.max(1, #lines - limit + 1)
	for i = start_idx, #lines do
		local line = lines[i]
		local timestamp, event, entry_mac, name = line:match("^(%S+ %S+)|(%S+)|(%S+)|(.*)$")
		if timestamp then
			if not mac or (entry_mac and entry_mac:lower() == mac:lower()) then
				table.insert(history, {
					timestamp = timestamp,
					event = event,
					mac = entry_mac or "",
					name = name or ""
				})
			end
		end
	end

	return history
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
