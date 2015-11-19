
-- {{{ my widgets
-- 
-- {{{ Volume Control Display
local wibox = require("wibox")
local fixwidthtextbox = require("fixwidthtextbox")
local awful = require("awful")

--volume_widget = wibox.widget.textbox()
volume_widget = fixwidthtextbox()
volume_widget.width = 40
volume_widget:set_align("center")

function update_volume(widget)
   local fd = io.popen("amixer sget Master")
   local status = fd:read("*all")
   fd:close()

   local volume = string.match(status, "(%d?%d?%d)%%")
   volume = string.format("%d", volume)

   status = string.match(status, "%[(o[^%]]*)%]")

   if string.find(status, "on", 1, true) then
   -- For the volume number percentage 
       volume = ' ♪<span color="#903090">' .. volume .. '%</span>'
   else
   -- For displaying the mute status.
       volume = ' ♪<span color="#903090">' .. volume .. '</span><span color="#aa0000">M</span>'
   end

   widget:set_markup(volume)
end

update_volume(volume_widget)

mytimer = timer({ timeout = 10 })
mytimer:connect_signal("timeout", function () update_volume(volume_widget) end)
mytimer:start()
--- }}}


-- {{{ Network speed indicator

--net_widget= wibox.widget.textbox()
net_widget = fixwidthtextbox()

function update_netstat()
    local interval = netwidget_clock.timeout
    local netif, text
    local f = io.open('/proc/net/route')
    for line in f:lines() do
        netif = line:match('^(%w+)%s+00000000%s')
        if netif then
            break
        end
    end
    f:close()

    if netif then
        local down, up
        f = io.open('/proc/net/dev')
        for line in f:lines() do
            -- Match wmaster0 as well as rt0 (multiple leading spaces)
            local name, recv, send = string.match(line, "^%s*(%w+):%s+(%d+)%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+(%d+)")
            if name == netif then
                if netdata[name] == nil then
                    -- Default values on the first run
                    netdata[name] = {}
                    down, up = 0, 0
                else
                    down = (recv - netdata[name][1]) / interval
                    up   = (send - netdata[name][2]) / interval
                end
                netdata[name][1] = recv
                netdata[name][2] = send
                break
            end
        end
        f:close()
        down = string.format('%.1f', down / 1024)
        up = string.format('%.1f', up / 1024)
        text = '↓<span color="#5798d9">'.. down ..'</span> ↑<span color="#c2ba62">'.. up ..' </span>'
    else
        netdata = {} -- clear as the interface may have been reset
        text = '[No network] '
    end
    net_widget:set_markup(text)
end
netdata = {}
net_widget.width = 100
net_widget:set_align('center')
netwidget_clock = timer({ timeout = 2 })
netwidget_clock:connect_signal("timeout", update_netstat)
netwidget_clock:start()
update_netstat()
-- }}}


-- {{{ memory usage indicator
--mem_widget = wibox.widget.textbox()
mem_widget = fixwidthtextbox()
mem_widget.width = 70
mem_widget.set_align('center')

-- {{{ Functions
function get_memory_usage()
    local ret = {}
    for l in io.lines('/proc/meminfo') do
        local k, v = l:match("([^:]+):%s+(%d+)")
        ret[k] = tonumber(v)
    end
    return ret
end

function update_memwidget()
    local meminfo = get_memory_usage()
    local free
    if meminfo.MemAvailable then
        -- Linux 3.14+
        free = meminfo.MemAvailable
    else
        free = meminfo.MemFree + meminfo.Buffers + meminfo.Cached
    end
    local total = meminfo.MemTotal
    local percent = 100 - math.floor(free / total * 100 + 0.5)
    mem_widget:set_markup(' Mem<span color="#408080">'.. percent ..'%</span>')
end
update_memwidget()
mem_clock = timer({ timeout = 5 })
mem_clock:connect_signal("timeout", update_memwidget)
mem_clock:start()
-- }}}

-- {{{ CPU Temperature
--cputemp_widget = wibox.widget.textbox()
cputemp_widget = fixwidthtextbox('cputemp')
cputemp_widget.width = 70
cputemp_widget.set_align('center')

function update_cputemp()
    local pipe = io.popen('sensors coretemp-isa-0000')
    if not pipe then
        cputemp_widget:set_markup('CPU<span color="#ff0000">ERR</span>℃')
        return
    end
    local temp = 0
    for line in pipe:lines() do
        local newtemp = line:match('^Core [^:]+:%s+%+([0-9.]+)°C')
        if newtemp then
            newtemp = tonumber(newtemp)
            if temp < newtemp then
                temp = newtemp
            end
        end
    end
    pipe:close()
    cputemp_widget:set_markup('CPU<span color="#A26565">'..temp..'℃ </span>')
end
update_cputemp()
cputemp_clock = timer({ timeout = 5 })
cputemp_clock:connect_signal("timeout", update_cputemp)
cputemp_clock:start()
-- }}}

--{{{ battery indicator 
batwidget = fixwidthtextbox()
batwidget.width = 65
batwidget:set_align('center')
local battery_state = {
    Unknown     = 'Bat<span color="yellow">? ',
    Full        = 'Bat<span color="#0000ff">↯',
    Charging    = 'Bat<span color="green">+',
    Discharging = 'Bat<span color="#1e90ff">–',
}

-- status     capacity    capacity_level
-- 充电时 >95
--  Full        101        Full
-- 充电时 <95
--  Charging    93         Full
-- 不充电时 
--Discharging    94        Normal
function batteryInfo()
    bat_dir = "/sys/class/power_supply/BAT0/"    
    local f = io.open(bat_dir .. 'status')
    if not f then
        batwidget:set_markup(' Bat<span color="#ff0000">ERR</span>')
        return
    end
    local state = f:read('*l')
    f:close()
    local state_text = battery_state[state] or battery_state.Unknown

    local f = io.open(bat_dir.."capacity")
    local percent = tonumber(f:read('*l'))
    f:close()
    
    if percent <= 20 then
        if state == 'Discharging' then
            local t = os.time()
            if t - last_bat_warning > 60 * 5 then
                naughty.notify{
                    preset = naughty.config.presets.critical,
                    title = "Battery Warning",
                    text = 'Battery low: ' .. percent .. '% percent',
                }
                last_bat_warning = t
            end
            if percent <= 20 and not dont_hibernate then
                awful.util.spawn("systemctl hibernate")
            end
        end
        percent = '<span color="#ff0000">'..percent..'%</span>'
    elseif percent >=100 then 
        percent = 'Full'
    end
    batwidget:set_markup(' '..state_text .. percent .. '</span>')
end
batteryInfo()
battery_timer = timer({timeout = 10})
battery_timer:connect_signal("timeout", batteryInfo)
battery_timer:start()
