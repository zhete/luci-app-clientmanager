--[[
Client Manager Settings Model
Configuration page for the client management plugin
]]--

local m, s, o

-- Map for the configuration file
m = Map("clientmanager", translate("Client Manager Settings"),
    translate("Configure global settings for client management"))

-- Global settings section
s = m:section(TypedSection, "global", translate("Global Settings"))
s.anonymous = true
s.addremove = false

-- Enable/disable the plugin
o = s:option(Flag, "enabled", translate("Enable Client Manager"))
o.default = 1
o.rmempty = false

-- Auto-block new devices
o = s:option(Flag, "autoblock", translate("Auto-block new devices"))
o.default = 0
o.rmempty = false
o.description = translate("Automatically block new devices connecting to the network")

-- Enable traffic monitoring
o = s:option(Flag, "traffic_monitor", translate("Enable traffic monitoring"))
o.default = 1
o.rmempty = false

-- Traffic data retention (days)
o = s:option(Value, "data_retention", translate("Data retention (days)"))
o.default = 30
o.datatype = "range(1,365)"
o.description = translate("Number of days to keep traffic history")

-- Scan interval
o = s:option(ListValue, "scan_interval", translate("Device scan interval"))
o.default = 60
o:value(30, translate("30 seconds"))
o:value(60, translate("1 minute"))
o:value(300, translate("5 minutes"))
o:value(600, translate("10 minutes"))

-- Section for notification settings
s = m:section(TypedSection, "notification", translate("Notifications"))
s.anonymous = true
s.addremove = false

-- Enable notifications
o = s:option(Flag, "enabled", translate("Enable notifications"))
o.default = 0

-- Notify on new device
o = s:option(Flag, "new_device", translate("Notify on new device"))
o.default = 1
o:depends("enabled", "1")

-- Notify on device blocked
o = s:option(Flag, "device_blocked", translate("Notify when device blocked"))
o.default = 1
o:depends("enabled", "1")

-- Email for notifications
o = s:option(Value, "email", translate("Notification email"))
o.datatype = "email"
o:depends("enabled", "1")

return m
