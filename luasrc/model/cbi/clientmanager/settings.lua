local m, s, o

m = Map("clientmanager", translate("Client Manager Settings"),
    translate("Configure global settings for client management"))

s = m:section(TypedSection, "global", translate("Global Settings"))
s.anonymous = true
s.addremove = false

o = s:option(Flag, "enabled", translate("Enable Client Manager"))
o.default = 1
o.rmempty = false

o = s:option(ListValue, "mode", translate("Access control mode"))
o.default = "blacklist"
o:value("blacklist", translate("Blacklist (block listed devices)"))
o:value("whitelist", translate("Whitelist (allow only listed devices)"))
o.description = translate("Blacklist blocks specified devices; Whitelist only allows specified devices")

o = s:option(Flag, "autoblock", translate("Auto-block new devices"))
o.default = 0
o.rmempty = false
o.description = translate("Automatically block new devices connecting to the network")
o:depends("mode", "blacklist")

o = s:option(Flag, "new_device_alert", translate("Alert on new device"))
o.default = 0
o.rmempty = false
o.description = translate("Show alert when a new device connects to the network")

o = s:option(Flag, "traffic_monitor", translate("Enable traffic monitoring"))
o.default = 1
o.rmempty = false

o = s:option(Value, "data_retention", translate("Data retention (days)"))
o.default = 30
o.datatype = "range(1,365)"
o.description = translate("Number of days to keep traffic history")

o = s:option(ListValue, "scan_interval", translate("Device scan interval"))
o.default = 60
o:value(30, translate("30 seconds"))
o:value(60, translate("1 minute"))
o:value(300, translate("5 minutes"))
o:value(600, translate("10 minutes"))

s = m:section(TypedSection, "notification", translate("Notifications"))
s.anonymous = true
s.addremove = false

o = s:option(Flag, "enabled", translate("Enable notifications"))
o.default = 0

o = s:option(Flag, "new_device", translate("Notify on new device"))
o.default = 1
o:depends("enabled", "1")

o = s:option(Flag, "device_blocked", translate("Notify when device blocked"))
o.default = 1
o:depends("enabled", "1")

o = s:option(Value, "email", translate("Notification email"))
o.datatype = "email"
o:depends("enabled", "1")

s = m:section(TypedSection, "schedule", translate("Scheduled Blocking"),
    translate("Configure time-based access control for devices"))
s.anonymous = true
s.addremove = true
s.template = "cbi/tblsection"
s.sectiontitle = function(self, section)
    local name = self.map:get(section, "name") or ""
    local mac = self.map:get(section, "mac") or ""
    if name ~= "" then
        return name .. " (" .. mac .. ")"
    end
    return mac
end

o = s:option(Value, "mac", translate("MAC Address"))
o.datatype = "macaddr"
o.rmempty = false

o = s:option(Value, "name", translate("Device Name"))
o.rmempty = true

o = s:option(ListValue, "action", translate("Action"))
o.default = "block"
o:value("block", translate("Block"))
o:value("unblock", translate("Allow"))

o = s:option(Value, "mon_start", translate("Mon Start"))
o:depends("action", "block")
o.placeholder = "09:00"

o = s:option(Value, "mon_end", translate("Mon End"))
o:depends("action", "block")
o.placeholder = "18:00"

o = s:option(Value, "tue_start", translate("Tue Start"))
o.placeholder = "09:00"

o = s:option(Value, "tue_end", translate("Tue End"))
o.placeholder = "18:00"

o = s:option(Value, "wed_start", translate("Wed Start"))
o.placeholder = "09:00"

o = s:option(Value, "wed_end", translate("Wed End"))
o.placeholder = "18:00"

o = s:option(Value, "thu_start", translate("Thu Start"))
o.placeholder = "09:00"

o = s:option(Value, "thu_end", translate("Thu End"))
o.placeholder = "18:00"

o = s:option(Value, "fri_start", translate("Fri Start"))
o.placeholder = "09:00"

o = s:option(Value, "fri_end", translate("Fri End"))
o.placeholder = "18:00"

o = s:option(Value, "sat_start", translate("Sat Start"))
o.placeholder = ""

o = s:option(Value, "sat_end", translate("Sat End"))
o.placeholder = ""

o = s:option(Value, "sun_start", translate("Sun Start"))
o.placeholder = ""

o = s:option(Value, "sun_end", translate("Sun End"))
o.placeholder = ""

s = m:section(TypedSection, "device", translate("Device Aliases"))
s.anonymous = true
s.addremove = true
s.template = "cbi/tblsection"
s.sectiontitle = function(self, section)
    local mac = self.map:get(section, "mac") or ""
    local alias = self.map:get(section, "alias") or ""
    if alias ~= "" then
        return alias .. " (" .. mac .. ")"
    end
    return mac
end

o = s:option(Value, "mac", translate("MAC Address"))
o.datatype = "macaddr"
o.rmempty = false

o = s:option(Value, "alias", translate("Alias"))
o.rmempty = false

o = s:option(Value, "name", translate("Device Name"))
o.rmempty = true

return m
