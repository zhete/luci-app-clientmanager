--[[
Client Manager Settings Model
Configuration page for the client management plugin
]]--

local m, s, o

m = Map("clientmanager", translate("Client Manager Settings"),
    translate("Configure global settings for client management"))

s = m:section(TypedSection, "global", translate("Global Settings"))
s.anonymous = true
s.addremove = false

o = s:option(Flag, "enabled", translate("Enable Client Manager"))
o.default = 1
o.rmempty = false

o = s:option(Flag, "autoblock", translate("Auto-block new devices"))
o.default = 0
o.rmempty = false
o.description = translate("Automatically block new devices connecting to the network")

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
