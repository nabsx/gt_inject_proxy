--====================================================================
--  NabanGacor Proxy v2.6.2 (/cd instant drop)
--  + Path toast, dialog inputs, whitelist, webhook, tracker
--  + Gems checker fixed, path preview, /move, /goto
--====================================================================

local TAG = "`0[ `3NabanGacor `0] "

----------------------------------------------------------------------
-- 1. HELPER UMUM
----------------------------------------------------------------------
local function strip(s) return (s:gsub("`.", "")) end
local function say(m)   SendVarlist({[0]="OnConsoleMessage", [1]=TAG.."`9"..m, netid=-1}) end
local function toast(m) SendVarlist({[0]="OnTextOverlay", [1]="`9"..m, netid=-1}) end
local function bubble(m)
    SendVarlist({[0]="OnTalkBubble", [1]=GetLocal().netid, [2]=m, [3]=0, [4]=0, netid=-1})
end
local function sendPkt(t) SendPacket(2, t) end
local function count(id) return math.floor(GetItemCount(id)) end
local function fx(x, y, id)
    SendVarlist({[0]="OnParticleEffect", [1]=id, [2]={x*32+16, y*32+16}, [3]=0, [4]=0, netid=-1})
end
local function embed(d, key) return d:match("embed_data|"..key.."|(%d+)") end

local hooks = {}
local function hook(name, kind, fn)
    if hooks[name] then RemoveCallback(name) end
    hooks[name] = true
    AddCallback(name, kind, fn)
end
local function unhook(name)
    if hooks[name] then RemoveCallback(name); hooks[name] = nil end
end

local function dialog(name, body, cancel, ok)
    SendVarlist({
        [0] = "OnDialogRequest",
        [1] = "set_default_color|`o\n"..body.."\nadd_quick_exit|\nend_dialog|"..name.."|"..(cancel or "`4Tutup").."|"..(ok or "").."|\n",
        netid = -1,
    })
end

local function FaceSide(side)
    SendPacketRaw({type=0, pos_x=GetLocal().pos_x, pos_y=GetLocal().pos_y, flags=(side=="left") and 48 or 32})
end

----------------------------------------------------------------------
-- 2. STATE
----------------------------------------------------------------------
local state = {}
state.pathtoast = true
state.confirmdrop = false     -- <<< default OFF = instant drop

local mode  = {}
local cfg = {
    tax = 5, dropTax = 0, side = "right",
    hostWorld = nil, saveWorld = nil,
    harvestId = 243, harvestDelay = 200,
    spamText = "Set your spam text!", spamDelay = 5,
    vendBuy = 1,
    visualSpin = nil,
    webhook = "",
    seedId = nil,
    confirmThreshold = 100,
}
local VIS_SPIN_COLOR = {
    [0]=2, [1]=4, [2]="b", [3]=4, [4]="b", [5]=4, [6]="b", [7]=4, [8]="b", [9]=4,
    [10]="b", [11]="b", [12]=4, [13]="b", [14]=4, [15]="b", [16]=4, [17]="b", [18]=4,
    [19]=4, [20]="b", [21]=4, [22]="b", [23]=4, [24]="b", [25]=4, [26]="b", [27]=4,
    [28]="b", [29]="b", [30]=4, [31]="b", [32]=4, [33]="b", [34]=4, [35]="b", [36]=4,
}
local pos = {{}, {}, {}, {}, back = {}}
local allowPick = {}
local whitelist = {}
local tracker   = {}
local recentCmds = {}
local pendingDrop = nil
local pendingPath = nil
local gemsStats = {total = 0}

local function setPos(k)
    local me = GetLocal()
    pos[k] = {x = math.floor(me.pos_x/32), y = math.floor(me.pos_y/32)}
    fx(pos[k].x, pos[k].y, 354)
    say("Pos `3"..tostring(k).." `9diset ke `3"..pos[k].x.." `9, `3"..pos[k].y)
end

local function webhookLog(title, desc, color)
    if not cfg.webhook or cfg.webhook == "" then return end
    local safe = tostring(desc):gsub('"', "'")
    local json = '{"embeds":[{"title":"'..title..'","description":"'..safe..'","color":'..(color or 5814783)..'}]}'
    pcall(function() SendWebhook(cfg.webhook, json) end)
end

local function isWhitelisted(name)
    return whitelist[strip(name):lower()] == true
end

-- ==================== PATH HELPERS ====================
local function dirStr(dx, dy)
    local parts = {}
    if dx ~= 0 then
        parts[#parts+1] = math.abs(dx).." blok "..(dx > 0 and "`2kanan" or "`4kiri")
    end
    if dy ~= 0 then
        parts[#parts+1] = math.abs(dy).." blok "..(dy > 0 and "`4bawah" or "`2atas")
    end
    if #parts == 0 then return "-" end
    return table.concat(parts, " `0, `9")
end

local function clampXY(x, y)
    return math.max(0, math.min(199, x)), math.max(0, math.min(199, y))
end

local function findPathTraced(x, y, label)
    x, y = math.floor(x), math.floor(y)
    local me = GetLocal()
    local cx, cy = math.floor(me.pos_x/32), math.floor(me.pos_y/32)
    local dist = math.abs(x-cx) + math.abs(y-cy)
    local t0 = os.clock()
    FindPath(x, y)
    local elapsed = os.clock() - t0
    local timeStr = string.format("%.3f", elapsed)
    local prefix = label and (label.." `0> `9") or ""
    local msg = prefix.."Pathfinding `3"..dist.." `9blocks `0(`3"..timeStr.."`0s)"
    say(msg)
    if state.pathtoast then toast(msg) end
    return dist, elapsed
end

local function pathPreview(tx, ty, mode)
    tx, ty = clampXY(math.floor(tx), math.floor(ty))
    local me = GetLocal()
    local cx, cy = math.floor(me.pos_x/32), math.floor(me.pos_y/32)
    local dx, dy = tx - cx, ty - cy
    local dist = math.abs(dx) + math.abs(dy)
    pendingPath = {x=tx, y=ty, mode=mode or "find"}
    local b = "add_label_with_icon|big|`3Path Preview|left|6016|\n"..
        "add_spacer|small|\n"..
        "add_smalltext|`9Dari : (`3"..cx.."`, `3"..cy.."`9)|left|\n"..
        "add_smalltext|`9Ke   : (`3"..tx.."`, `3"..ty.."`9)|left|\n"..
        "add_spacer|small|\n"..
        "add_smalltext|`9Arah : "..dirStr(dx, dy).."|left|\n"..
        "add_smalltext|`9Total : `3"..dist.." `9blok|left|\n"..
        "add_spacer|small|\n"..
        "add_button|nb_path_go|`2Go Sekarang|noflags|0|0|\n"..
        "add_button|nb_path_show|`9Preview Path (visual)|noflags|0|0|\n"..
        "add_button|nb_path_cancel|`4Cancel|noflags|0|0|"
    dialog("nab_pathpreview", b)
end

AddCallback("nb_pathbtn", "OnPacket", function(_, p)
    if not p:find("action|dialog_return", 1, true) then return end
    if p:find("buttonClicked|nb_path_go") and pendingPath then
        local t = pendingPath
        pendingPath = nil
        if t.mode == "show" and PathFind then
            pcall(function()
                local path = PathFind(t.x, t.y)
                if path and #path > 0 then
                    for _, tile in ipairs(path) do fx(tile.x, tile.y, 88) end
                    say("Path visual : `3"..#path.." `9blok")
                end
            end)
        end
        findPathTraced(t.x, t.y, "Go")
        return true
    end
    if p:find("buttonClicked|nb_path_show") and pendingPath then
        local t = pendingPath
        if PathFind then
            pcall(function()
                local path = PathFind(t.x, t.y)
                if path and #path > 0 then
                    for _, tile in ipairs(path) do fx(tile.x, tile.y, 88) end
                    say("Path preview: `3"..#path.." `9blok")
                else
                    say("`4No path found")
                end
            end)
        else
            say("`4PathFind tidak tersedia")
        end
        return true
    end
    if p:find("buttonClicked|nb_path_cancel") then
        pendingPath = nil
        say("`4Dibatalkan")
        return true
    end
end)

----------------------------------------------------------------------
-- 3. COMMAND REGISTRY
----------------------------------------------------------------------
local commands, aliases, order = {}, {}, {}
local cats = {
    {id="util",   title="Utility",    icon=5772},
    {id="world",  title="World",      icon=3802},
    {id="farm",   title="Farming",    icon=6950},
    {id="host",   title="Host",       icon=758},
    {id="auto",   title="Automation", icon=4318},
    {id="visual", title="Visual",     icon=9228},
}
local catById = {}
for _, c in ipairs(cats) do catById[c.id] = c end

local function cmd(names, cat, desc, fn, opt)
    desc = desc:gsub("|", "/")
    local main = names[1]
    commands[main] = {names=names, cat=cat, desc=desc, fn=fn, opt=opt}
    order[#order+1] = main
    for _, n in ipairs(names) do aliases[n] = main end
end

local function flip(key, label, onFn, offFn)
    state[key] = not state[key]
    if state[key] then if onFn then onFn() end else if offFn then offFn() end end
    say(label.." `9: "..(state[key] and "`2ON" or "`4OFF"))
end

local function toggleCmd(names, cat, desc, key, label, icon, onFn, offFn)
    cmd(names, cat, desc, function() flip(key, label, onFn, offFn) end,
        {tog=key, label=label, icon=icon})
end

AddCallback("nb_router", "OnPacket", function(_, packet)
    local body = packet:match("^action|input\n|text|/(.*)$")
    if not body then return end
    local name, args = body:match("^(%S*)%s*(.-)%s*$")
    local main = aliases[(name or ""):lower()]
    if not main then return end
    table.insert(recentCmds, 1, main)
    if #recentCmds > 5 then table.remove(recentCmds) end
    local ok, err = pcall(commands[main].fn, args or "")
    if not ok then say("`4Error `3"..main.."`4: "..tostring(err)) end
    return true
end)

----------------------------------------------------------------------
-- 4. MODE REGISTRY
----------------------------------------------------------------------
local modes = {}
local function defMode(key, title, icon, cat, opts, default)
    modes[key] = {title=title, icon=icon, cat=cat, opts=opts}
    mode[key] = default or "off"
end
local function setMode(key, opt)
    mode[key] = opt
    say(modes[key].title.." `9: `3"..opt)
end

defMode("wrench",   "Wrench Mode",  32,   "world", {"pull","kick","ban","off"})
defMode("join",     "Join Mode",    6,    "world", {"pull","kick","ban","off"})
defMode("ut",       "UT Mode",      6948, "farm",  {"add","empty","off"})
defMode("gaia",     "GAIA Mode",    6946, "farm",  {"add","empty","off"})
defMode("donation", "Donation Box", 1452, "farm",  {"add","empty","off"})
defMode("vend",     "Vend Mode",    2978, "farm",  {"empty","add","buy","off"})
defMode("spin",     "Spin Checker", 758,  "host",  {"check","qq","reme","all","off"}, "check")
defMode("safe",     "Safe Mode",    278,  "util",  {"banleave","unaccess","leave","off"}, "off")

----------------------------------------------------------------------
-- 5. DIALOG / MENU
----------------------------------------------------------------------
local menuHome, menuCat, menuMode, menuStatus

local function row(id, label) return "add_button|"..id.."|"..label.."|noflags|0|0|\n" end
local function onoff(on) return on and "`2● ON  `w" or "`4○ OFF `w" end
local function section(title, icon) return "add_spacer|small|\nadd_label_with_icon|small|`3"..title.."|left|"..icon.."|\n" end

menuHome = function()
    local me = GetLocal()
    local b = "add_label_with_icon|big|`3NabanGacor `9Proxy `0v2.6.2|left|1790|\n"..
        "add_spacer|small|\n"..
        "add_smalltext|`9World : `3"..me.world.."|left|\n"..
        "add_smalltext|`9Posisi : `3X "..math.floor(me.tile_x).."  Y "..math.floor(me.tile_y).."|left|\n"..
        "add_smalltext|`9Ping : `3"..math.floor(GetPing()).." ms|left|\n"..
        "add_smalltext|`9Tax : `3"..cfg.tax.."%|left|\n"..
        "add_smalltext|`9Whitelist : `3"..(function() local n=0 for _ in pairs(whitelist) do n=n+1 end return n end)().."|left|\n"..
        "add_smalltext|`9Gems session : `2"..gemsStats.total.."|left|\n"..
        "add_smalltext|`9Path toast : "..(state.pathtoast and "`2ON" or "`4OFF").."|left|\n"..
        "add_smalltext|`9Confirm drop : "..(state.confirmdrop and "`2ON" or "`4OFF").."|left|\n"..
        section("Menu", 5772)
    for _, c in ipairs(cats) do
        local n = 0
        for _, main in ipairs(order) do if commands[main].cat == c.id then n = n + 1 end end
        b = b..row("nb_c_"..c.id, "`w"..c.title.."  `0("..n.." command)")
    end
    if #recentCmds > 0 then
        b = b..section("Recent Commands", 758)
        for i, m in ipairs(recentCmds) do
            if commands[m] then
                b = b.."add_label_with_icon|small|`3/"..m.." `9- "..commands[m].desc.."|left|"..(commands[m].opt and commands[m].opt.icon or 758).."|\n"
            end
        end
    end
    b = b.."add_spacer|small|\n"..row("nb_status", "`2Status Fitur")
    b = b..row("nb_settings", "`2Settings (multi-toggle)")
    dialog("nab_menu", b)
end

menuCat = function(id)
    local c = catById[id]
    if not c then return menuHome() end
    local b = "add_label_with_icon|big|`3"..c.title.."|left|"..c.icon.."|\n"
    local toggles, mods = "", ""
    for _, main in ipairs(order) do
        local x = commands[main]
        if x.cat == id and x.opt then
            toggles = toggles..row("nb_t_"..main, onoff(state[x.opt.tog])..x.opt.label)
        end
    end
    for key, m in pairs(modes) do
        if m.cat == id then
            mods = mods..row("nb_mp_"..key, "`w"..m.title.."  `0: `3"..mode[key])
        end
    end
    if toggles ~= "" then b = b..section("Toggle", 1790)..toggles end
    if mods ~= "" then b = b..section("Pengaturan", 32)..mods end
    b = b..section("Daftar Command", 5772)
    for _, main in ipairs(order) do
        local x = commands[main]
        if x.cat == id then
            local iconId = x.opt and x.opt.icon or c.icon
            b = b.."add_label_with_icon|small|`0/"..table.concat(x.names, " `0atau `3/").." `0- `9"..x.desc.."|left|"..iconId.."|\n"
        end
    end
    b = b.."add_spacer|small|\n"..row("nb_home", "`@< Menu Utama")
    dialog("nab_menu", b)
end

menuMode = function(key)
    local m = modes[key]
    local b = "add_label_with_icon|big|`3"..m.title.."|left|"..m.icon.."|\n"..
              "add_smalltext|`9Saat ini : `3"..mode[key].."|left|\n"..section("Pilih mode", m.icon)
    for _, o in ipairs(m.opts) do
        b = b..row("nb_m_"..key.."_"..o, (mode[key] == o) and ("`2>  "..o.."  (aktif)") or ("`w"..o))
    end
    b = b.."add_spacer|small|\n"..row("nb_c_"..m.cat, "`@< Kembali")
    dialog("nab_menu", b)
end

menuStatus = function()
    local function st(on) return on and "`2ON" or "`4OFF" end
    local b = "add_label_with_icon|big|`9Status Fitur|left|1790|\n"..section("Toggle", 1790)
    for _, main in ipairs(order) do
        local x = commands[main]
        if x.opt then b = b.."add_smalltext|`w"..x.opt.label.." `0: "..st(state[x.opt.tog]).."|left|\n" end
    end
    b = b..section("Mode", 32)
    for key, m in pairs(modes) do
        b = b.."add_smalltext|`w"..m.title.." `0: `3"..mode[key].."|left|\n"
    end
    b = b..section("Info", 96)
    local wln = 0; for _ in pairs(whitelist) do wln = wln + 1 end
    local trn = 0; for _ in pairs(tracker) do trn = trn + 1 end
    b = b.."add_smalltext|`wWhitelist `0: `3"..wln.." player|left|\n"
    b = b.."add_smalltext|`wTracker `0: `3"..trn.." player|left|\n"
    b = b.."add_smalltext|`wWebhook `0: "..(cfg.webhook ~= "" and "`2SET" or "`4UNSET").."|left|\n"
    b = b.."add_smalltext|`wGems session `0: `2"..gemsStats.total.."|left|\n"
    b = b.."add_smalltext|`wPath toast `0: "..(state.pathtoast and "`2ON" or "`4OFF").."|left|\n"
    b = b.."add_smalltext|`wConfirm drop `0: "..(state.confirmdrop and "`2ON" or "`4OFF").."|left|\n"
    b = b.."add_spacer|small|\n"..row("nb_home", "`@< Menu Utama")
    dialog("nab_menu", b)
end

local function settingsDialog()
    local b = "add_label_with_icon|big|`3Settings Multi-Toggle|left|5772|\nadd_spacer|small|\n"
    local any = false
    for _, main in ipairs(order) do
        local x = commands[main]
        if x.opt then
            any = true
            b = b.."add_checkbox|chk_"..main.."|`w"..x.opt.label.."|"..(state[x.opt.tog] and "1" or "0").."|\n"
        end
    end
    if not any then b = b.."add_smalltext|`4No toggles available|left|\n" end
    b = b.."add_spacer|small|\nadd_button|nb_apply_chk|`2Apply All|noflags|0|0|\n"
    b = b.."add_button|nb_home|`@< Menu Utama|noflags|0|0|"
    dialog("nab_settings", b)
end

----------------------------------------------------------------------
-- 6. GROWSCAN
----------------------------------------------------------------------
local function showScan(title, data)
    local rows = {}
    for id, n in pairs(data) do
        id = math.floor(id)
        if id > 0 then rows[#rows+1] = {id, math.floor(n)} end
    end
    table.sort(rows, function(a, b) return a[2] > b[2] end)
    local b = "add_label_with_icon|big|`w"..title.."|left|6016|\nadd_spacer|small|\n"
    for _, r in ipairs(rows) do
        local info = GetIteminfo(r[1])
        b = b.."add_label_with_icon|small|`0"..(info and info.name or ("#"..r[1])).." `0: `2"..r[2].."``|left|"..r[1].."|\n"
    end
    b = b.."add_spacer|small|\nadd_button|nb_gs_menu|`@< Kembali|noflags|0|0|"
    dialog("nab_scan", b)
end
local function scanBlocks()
    local c = {}
    for _, t in pairs(GetTiles()) do
        c[t.fg] = (c[t.fg] or 0) + 1
        c[t.bg] = (c[t.bg] or 0) + 1
    end
    showScan("Placed Items", c)
end
local function scanFloat()
    local c = {}
    for _, o in pairs(GetObjects()) do c[o.id] = (c[o.id] or 0) + o.count end
    showScan("Floating Items", c)
end
local function scanMenu()
    dialog("nab_scan",
        "add_label_with_icon|big|`wGrowscan|left|6016|\nadd_spacer|small|\n"..
        "add_button|nb_gs_blocks|`9World Blocks|noflags|0|0|\n"..
        "add_button|nb_gs_float|`9Floating Items|noflags|0|0|")
end

----------------------------------------------------------------------
-- 7. BUTTON ROUTER
----------------------------------------------------------------------
AddCallback("nb_buttons", "OnPacket", function(_, p)
    if not p:find("action|dialog_return", 1, true) then return end
    if p:find("buttonClicked|nb_apply_chk") then
        for _, main in ipairs(order) do
            local x = commands[main]
            if x.opt then
                local v = p:match("chk_"..main.."|(%d+)")
                local want = (v == "1")
                if want ~= state[x.opt.tog] then commands[main].fn("") end
            end
        end
        say("Settings applied")
        return true
    end
    if p:find("buttonClicked|nb_conf_yes") and pendingDrop then
        local cb = pendingDrop.cb
        pendingDrop = nil
        cb()
        return true
    elseif p:find("buttonClicked|nb_conf_no") then
        pendingDrop = nil
        say("`4Dibatalkan")
        return true
    end
    local btn = p:match("buttonClicked|(nb_[%w_]+)")
    if not btn then return end
    local kind, rest = btn:match("^nb_(%a+)_?(.*)$")
    if kind == "home" then menuHome()
    elseif kind == "status" then menuStatus()
    elseif kind == "settings" then settingsDialog()
    elseif kind == "c" then menuCat(rest)
    elseif kind == "mp" then menuMode(rest)
    elseif kind == "t" then
        local c = commands[rest]
        if c then c.fn(""); menuCat(c.cat) end
    elseif kind == "m" then
        local k, o = rest:match("^(%a+)_(%a+)$")
        if k and modes[k] then setMode(k, o); menuMode(k) end
    elseif kind == "gs" then
        if rest == "blocks" then scanBlocks()
        elseif rest == "float" then scanFloat()
        else scanMenu() end
    else
        return
    end
    return true
end)

----------------------------------------------------------------------
-- 8. UTILITY
----------------------------------------------------------------------
cmd({"proxy", "commands", "menu"}, "util", "Buka menu utama", function() menuHome() end)
cmd({"info"}, "util", "Status semua fitur", function() menuStatus() end)
cmd({"settings", "stg"}, "util", "Settings multi-checkbox", function() settingsDialog() end)

cmd({"ping"}, "util", "Lihat ping", function()
    local p = GetPing()
    local c = p < 150 and "`2" or (p < 300 and "`9" or "`4")
    say("Ping kamu : "..c..math.floor(p).."ms")
end)

cmd({"xy"}, "util", "Posisi tile sekarang", function()
    local me = GetLocal()
    local x, y = math.floor(me.pos_x/32), math.floor(me.pos_y/32)
    say("X : `3"..x.." `9Y : `3"..y)
    toast("X : `3"..x.." `9Y : `3"..y)
end)

cmd({"balance", "bal"}, "util", "Total WL / DL / BGL di inventory", function()
    local s = "`9WL : `3"..count(242).." `1& `9DL : `3"..count(1796).." `1& `9BGL : `3"..count(7188)
    say(s); toast(s)
end)

cmd({"res"}, "util", "Respawn cepat", function() say("Respawning"); sendPkt("action|respawn") end)

cmd({"relog"}, "util", "Relog ke world sekarang", function()
    local w = GetLocal().world
    say("Relogging")
    SendPacket(3, "action|quit_to_exit")
    SendPacket(3, "action|join_request\nname|"..w.."\ninvitedWorld|0")
end)

cmd({"rndm"}, "util", "Warp ke world random", function()
    local t = {}
    for i = 1, 19 do t[i] = string.char(math.random(97, 122)) end
    local w = table.concat(t)
    say("Warping ke "..w)
    SendPacket(3, "action|join_request\nname|"..w)
end)

cmd({"door"}, "util", "Masuk door by id", function(a)
    if a == "" then return say("`4Pakai: /door ID") end
    say("Join door id : `3"..a)
    SendPacket(3, "action|join_request\nname|"..GetLocal().world.."|"..a.."\ninvitedWorld|0")
end)

cmd({"player"}, "util", "Teleport ke player (dengan preview)", function(a)
    for _, p in pairs(GetPlayers()) do
        if strip(p.name):lower() == a:lower() then
            say("Player ketemu")
            return pathPreview(math.floor(p.pos_x/32), math.floor(p.pos_y/32), "find")
        end
    end
    say("Player `4tidak ketemu")
end)

-- ==================== FIND PATH ====================
cmd({"findpath", "fp"}, "util", "Pathfind + preview jarak: /findpath X Y", function(a)
    local x, y = a:match("(%-?%d+)%s+(%-?%d+)")
    if not x then return say("`4Pakai: /findpath X Y") end
    pathPreview(tonumber(x), tonumber(y), "find")
end)

cmd({"goto"}, "util", "Langsung findpath + toast: /goto X Y", function(a)
    local x, y = a:match("(%-?%d+)%s+(%-?%d+)")
    if not x then return say("`4Pakai: /goto X Y") end
    x, y = clampXY(tonumber(x), tonumber(y))
    findPathTraced(x, y, "Goto")
end)

cmd({"showpath", "sp"}, "util", "Preview path visual: /showpath X Y", function(a)
    local x, y = a:match("(%-?%d+)%s+(%-?%d+)")
    if not x then return say("`4Pakai: /showpath X Y") end
    pathPreview(tonumber(x), tonumber(y), "show")
end)

toggleCmd({"pathtoast", "ptt"}, "util", "Toast tiap pathfinding (ON/OFF)", "pathtoast", "Path Toast", 6016)

-- ==================== MOVE ====================
cmd({"move", "mv"}, "util", "Move block: /move [up|down|left|right N] atau /move X Y", function(a)
    local dir, num = a:match("^(%a+)%s+(%-?%d+)$")
    if dir then
        local n = tonumber(num) or 0
        local me = GetLocal()
        local cx, cy = math.floor(me.pos_x/32), math.floor(me.pos_y/32)
        local dx, dy = 0, 0
        dir = dir:lower()
        if dir == "up" or dir == "u" then dy = -n
        elseif dir == "down" or dir == "d" then dy = n
        elseif dir == "left" or dir == "l" then dx = -n
        elseif dir == "right" or dir == "r" then dx = n
        else return say("`4Arah: up/down/left/right") end
        return pathPreview(cx + dx, cy + dy, "find")
    end
    local rx, ry = a:match("^(%-?%d+)%s+(%-?%d+)$")
    if rx then
        local me = GetLocal()
        local cx, cy = math.floor(me.pos_x/32), math.floor(me.pos_y/32)
        return pathPreview(cx + tonumber(rx), cy + tonumber(ry), "find")
    end
    local me = GetLocal()
    local cx, cy = math.floor(me.pos_x/32), math.floor(me.pos_y/32)
    local b = "add_label_with_icon|big|`3Move By Block|left|6016|\n"..
        "add_spacer|small|\n"..
        "add_smalltext|`9Posisi sekarang : (`3"..cx.."`, `3"..cy.."`9)|left|\n"..
        "add_spacer|small|\n"..
        "add_text_input|mv_x|Geser X (+kanan, -kiri)|0|6|\n"..
        "add_text_input|mv_y|Geser Y (+bawah, -atas)|0|6|\n"..
        "add_spacer|small|\n"..
        "add_smalltext|`9Contoh cepat:|left|\n"..
        "add_smalltext|`0/move up 5 `9- geser 5 blok ke atas|left|\n"..
        "add_smalltext|`0/move down 3 `9- geser 3 blok ke bawah|left|\n"..
        "add_smalltext|`0/move 10 5 `9- offset X=10, Y=5|left|\n"..
        "add_spacer|small|\n"..
        "add_button|nb_move_go|`2Preview|noflags|0|0|"
    dialog("nab_move", b)
end)

AddCallback("nb_movebtn", "OnPacket", function(_, p)
    if not p:find("action|dialog_return", 1, true) then return end
    if p:find("buttonClicked|nb_move_go") then
        local dx = tonumber(p:match("mv_x|(%-?%d+)")) or 0
        local dy = tonumber(p:match("mv_y|(%-?%d+)")) or 0
        local me = GetLocal()
        local cx, cy = math.floor(me.pos_x/32), math.floor(me.pos_y/32)
        pathPreview(cx + dx, cy + dy, "find")
        return true
    end
end)

cmd({"cid"}, "util", "Buat akun baru", function() say("Membuat akun baru.."); sendPkt("action|growid") end)
cmd({"fc"}, "util", "Matikan proxy", function() say("Menutup proxy."); RemoveCallbacks() end)

cmd({"warn"}, "util", "Notifikasi warning custom", function(a)
    SendVarlist({[0]="OnAddNotification", [1]="interface/atomic_button.rttex", [2]=a, [3]="audio/hub_open.wav", [4]=0, netid=-1})
end)

cmd({"gems"}, "util", "Total gems di world", function()
    local n = 0
    for _, o in pairs(GetObjects()) do if o.id == 112 then n = n + o.count end end
    toast("Gems di world : "..math.floor(n))
end)

cmd({"compress"}, "util", "Compress 100 WL jadi DL", function()
    if count(242) >= 100 then SendPacketRaw({type=10, int_data=242}) end
end)

cmd({"dropall"}, "util", "Drop semua item (risiko shadowban)", function()
    RunThread(function()
        say("Dropping semua item..")
        for _, v in ipairs(GetInventory()) do
            sendPkt("action|drop\n|itemID|"..v.id)
            sendPkt("action|dialog_return\ndialog_name|drop_item\nitemID|"..v.id.."|\ncount|"..v.count)
            Sleep(50)
        end
        say("Selesai")
    end)
end)

cmd({"buywl"}, "util", "Beli WL pakai semua gems", function()
    RunThread(function()
        local n = math.floor(GetLocal().gems / 2000)
        say("Membeli `3"..n.." `9wls")
        for _ = 1, n do sendPkt("action|buy\nitem|world_lock"); Sleep(10) end
        say("Selesai")
    end)
end)

toggleCmd({"modfly"}, "util", "Toggle mod fly", "modfly", "Mod Fly", 6016,
    function() EditToggle("ModFly", true) end,
    function() EditToggle("ModFly", false); EditToggle("Antibounce", false) end)

toggleCmd({"fd"}, "util", "Fast drop", "fd", "Fast Drop", 1796)
toggleCmd({"ft"}, "util", "Fast trash", "ft", "Fast Trash", 202)
hook("nb_fd", "OnVarlist", function(v)
    if state.fd and v[0] == "OnDialogRequest" and v[1]:find("end_dialog|drop_item|Cancel|OK|", 1, true) then
        sendPkt("action|dialog_return\ndialog_name|drop_item\nitemID|"..v[1]:match("itemID|(%d+)").."|\ncount|"..v[1]:match("count||(%d+)"))
        return true
    end
end)
hook("nb_ft", "OnVarlist", function(v)
    if state.ft and v[0] == "OnDialogRequest" and v[1]:find("end_dialog|trash_item|Cancel|OK|", 1, true) then
        sendPkt("action|dialog_return\ndialog_name|trash_item\nitemID|"..embed(v[1], "itemID").."|\ncount|"..v[1]:match("you have (%d+)"))
        return true
    end
end)

toggleCmd({"dialog"}, "util", "Sembunyikan dialog drop", "hidedrop", "Hide Drop Dialog", 1796)
hook("nb_hidedrop", "OnVarlist", function(v)
    if state.hidedrop and v[0] == "OnDialogRequest" and v[1]:find("end_dialog|drop_item|Cancel|OK|", 1, true) then
        return true
    end
end)

local function pickupHook(p)
    if state.nopickup and p.type == 11 then
        for _, o in pairs(GetObjects()) do
            if o.oid == p.int_data and not allowPick[math.floor(o.id)] then return true end
        end
    end
end
hook("nb_pickup", "OnRawPacket", pickupHook)
cmd({"nopickup"}, "util", "Toggle anti-pickup", function()
    flip("nopickup", "Anti-Pickup", function() allowPick = {} end)
end, {tog="nopickup", label="Anti Pickup", icon=202})
cmd({"pickup"}, "util", "Hanya pickup 1 item id", function(a)
    local id = tonumber(a)
    if not id then return say("`4Pakai: /pickup ID") end
    allowPick = {[id] = true}
    state.nopickup = true
    say("Hanya mengambil `3"..(GetIteminfo(id) and GetIteminfo(id).name or id))
end)

local function collectNear(rangeTiles)
    local r = (rangeTiles or 10) * 32
    local me = GetLocal()
    for _, o in pairs(GetObjects()) do
        if math.abs(me.pos_x - o.pos_x) < r and math.abs(me.pos_y - o.pos_y) < r then
            SendPacketRaw({type=11, int_data=o.oid, pos_x=o.pos_x, pos_y=o.pos_y})
        end
    end
end
cmd({"cc", "ccollect"}, "util", "Collect item di range", function(a)
    local r = tonumber(a) or 10
    say("Collect item range `3"..r)
    collectNear(r)
end)
toggleCmd({"autocollect", "ac"}, "util", "Toggle auto collect", "autocollect", "Auto Collect", 112,
    function()
        RunThread(function()
            while state.autocollect do collectNear(10); Sleep(50) end
        end)
    end)

local BLINK = {3370516479, 3033464831, 2864971775, 2527912447, 2190853119, 2022356223, 1685231359, 1348237567}
toggleCmd({"blink"}, "util", "Skin berkedip", "blink", "Blink Skin", 1784,
    function()
        RunThread(function()
            while state.blink do
                for i = 1, #BLINK do if not state.blink then break end
                    sendPkt("action|setSkin\ncolor|"..BLINK[i]); Sleep(150) end
                for i = #BLINK, 1, -1 do if not state.blink then break end
                    sendPkt("action|setSkin\ncolor|"..BLINK[i]); Sleep(150) end
            end
        end)
    end)

-- ==================== GEMS CHECKER ====================
cmd({"bjreset"}, "host", "Reset counter gems checker", function()
    gemsStats.total = 0
    say("Gems counter direset")
end)
cmd({"bjstats"}, "host", "Lihat total gems collected (session)", function()
    say("Gems collected : `2+"..gemsStats.total)
    say("Gems sekarang : `3"..GetLocal().gems)
end)

toggleCmd({"bj"}, "host", "Gems checker (visual + anti-double)", "bj", "Gems Checker", 112,
    function()
        RunThread(function()
            local lastGems = GetLocal().gems
            local pendingDiff = 0
            local lastChangeAt = 0
            local now = 0
            local SHORT_WINDOW = 500
            while state.bj do
                Sleep(100)
                now = now + 100
                if GetLocal().world ~= "EXIT" then
                    local cur = GetLocal().gems
                    if cur > lastGems then
                        pendingDiff = pendingDiff + (cur - lastGems)
                        lastGems = cur
                        lastChangeAt = now
                    elseif cur < lastGems then
                        lastGems = cur
                    end
                    if pendingDiff > 0 and (now - lastChangeAt >= SHORT_WINDOW or pendingDiff >= 100) then
                        local diff = pendingDiff
                        pendingDiff = 0
                        gemsStats.total = gemsStats.total + diff
                        local me = GetLocal()
                        fx(math.floor(me.pos_x/32), math.floor(me.pos_y/32), 112)
                        if diff >= 100 then
                            bubble("`0[`2+"..diff.." GEM!`0] `9total `2"..gemsStats.total)
                            SendVarlist({[0]="OnTextOverlay", [1]=
                                "`0+---------------+\n"..
                                "`0| `2GEM  JACKPOT  `0|\n"..
                                "`0| `w+"..diff.." `9gems     `0|\n"..
                                "`0| `9total `2"..gemsStats.total.."      `0|\n"..
                                "`0+---------------+", netid=-1})
                            webhookLog("Gems", "Jackpot! +"..diff.." gems (total "..gemsStats.total..")", 5763719)
                        elseif diff >= 10 then
                            bubble("`0[`3+"..diff.."`0] `9gems `0| `9sum `2"..gemsStats.total)
                        else
                            bubble("`0[`9+"..diff.."`0] `9gem  `0| `9sum `2"..gemsStats.total)
                        end
                    end
                else
                    lastGems = GetLocal().gems
                end
            end
        end)
    end)

toggleCmd({"fireban"}, "world", "Auto-ban troller pocket lighter", "fireban", "Auto Ban Fire", 3196)
hook("nb_fireban", "OnVarlist", function(v)
    if state.fireban and v[0] == "OnTalkBubble" and tostring(v[2]):find("`4MWAHAHAHA!!", 1, true) then
        local id = v[1]
        say("Player netid `3"..id.." `9pasang pocket lighter")
        sendPkt("action|wrench\n|netid|"..id)
        sendPkt("action|dialog_return\ndialog_name|popup\nnetID|"..id.."|\nbuttonClicked|worldban")
        webhookLog("AutoBan", "Banned netid "..id.." (fire troller)", 15158332)
        return true
    end
end)

toggleCmd({"autoaccess"}, "util", "Auto-terima akses lock (default OFF)", "autoaccess", "Auto Accept Access", 242)
hook("nb_access", "OnVarlist", function(v)
    if not state.autoaccess then return end
    if v[0] == "OnConsoleMessage" and tostring(v[1]):find("wants to add you to a", 1, true) then
        local id = GetLocal().netid
        sendPkt("action|wrench\n|netid|"..id)
        sendPkt("action|dialog_return\ndialog_name|popup\nnetID|"..id.."|\nbuttonClicked|acceptlock")
        sendPkt("action|dialog_return\ndialog_name|acceptaccess")
        return true
    elseif v[0] == "OnDialogRequest" and (v[1]:find("end_dialog|acceptaccess|No|Yes|", 1, true) or v[1]:find("add_button|acceptlock|", 1, true)) then
        return true
    end
end)

hook("nb_login", "OnPacket", function(_, p)
    if p:find("action|enter_game", 1, true) then
        say("Removing game freeze / crash..")
        sendPkt("action|enter_game")
        return true
    end
end)
hook("nb_welcome", "OnVarlist", function(v)
    if v[0] == "OnConsoleMessage" and tostring(v[1]):find("Welcome back,", 1, true) then
        say("Player Authentication `2Successful.")
        say("`9WL : `3"..count(242).." `1& `9DL : `3"..count(1796).." `1& `9BGL : `3"..count(7188))
    end
end)

-- ==================== WHITELIST ====================
cmd({"wl", "whitelist"}, "util", "Whitelist: /wl add|del|list nama", function(a)
    local act, name = a:match("^(%a+)%s*(.*)$")
    if act == "list" then
        local l = {}
        for k in pairs(whitelist) do l[#l+1] = k end
        return say("Whitelist : "..(table.concat(l, ", ") ~= "" and table.concat(l, ", ") or "-"))
    elseif act == "add" and name ~= "" then
        whitelist[strip(name):lower()] = true
        say("Whitelist tambah: `3"..name)
    elseif act == "del" and name ~= "" then
        whitelist[strip(name):lower()] = nil
        say("Whitelist hapus: `3"..name)
    else
        say("`4Pakai: /wl add|del|list nama")
    end
end)

-- ==================== TRACKER ====================
cmd({"track"}, "util", "Track player: /track add|del|list nama", function(a)
    local act, name = a:match("^(%a+)%s*(.*)$")
    if act == "list" then
        local l = {}
        for k in pairs(tracker) do l[#l+1] = k end
        return say("Tracked : "..(table.concat(l, ", ") ~= "" and table.concat(l, ", ") or "-"))
    elseif act == "add" and name ~= "" then
        tracker[strip(name):lower()] = true
        say("Track: `3"..name)
    elseif act == "del" and name ~= "" then
        tracker[strip(name):lower()] = nil
        say("Untrack: `3"..name)
    else
        say("`4Pakai: /track add|del|list nama")
    end
end)
hook("nb_track", "OnVarlist", function(v)
    if v[0] == "OnSpawn" and not tostring(v[1]):find("type|local", 1, true) then
        local raw = tostring(v[1]):match("name|(`.[^`]+)")
        if raw and tracker[strip(raw):lower()] then
            bubble("`9[TRACK] `3"..raw.." `9join!")
            webhookLog("Tracker", raw.." joined "..GetLocal().world, 3066993)
        end
    end
end)

-- ==================== WEBHOOK ====================
cmd({"webhook"}, "util", "Set Discord webhook: /webhook URL | /webhook off", function(a)
    if a == "off" or a == "" then
        cfg.webhook = ""
        return say("Webhook dihapus")
    end
    cfg.webhook = a
    say("Webhook diset")
    webhookLog("Connected", "Webhook online. World: "..GetLocal().world, 5763719)
end)

-- ==================== RECENT ====================
cmd({"recent"}, "util", "Lihat 5 command terakhir", function()
    if #recentCmds == 0 then return say("Belum ada command terpakai") end
    local l = {}
    for i, m in ipairs(recentCmds) do l[#l+1] = "/"..m end
    say("Recent : `3"..table.concat(l, " `0| `3"))
end)

----------------------------------------------------------------------
-- 9. WORLD
----------------------------------------------------------------------
local function eachPlayer(action, label)
    RunThread(function()
        say(label.." semua player")
        for _, p in pairs(GetPlayers()) do
            local n = strip(p.name)
            if action == "ban" and isWhitelisted(n) then
                say("`9Skip whitelist: `3"..n)
            else
                sendPkt("action|input\n|text|/"..action.." "..n)
            end
            Sleep(80)
        end
    end)
end
cmd({"pullall"},  "world", "Pull semua player",  function() eachPlayer("pull", "Pull") end)
cmd({"kickall"},  "world", "Kick semua player",  function() eachPlayer("kick", "Kick") end)
cmd({"banall"},   "world", "Ban semua player (skip whitelist)", function() eachPlayer("ban", "Ban") end)
cmd({"tradeall"}, "world", "Trade semua player", function() eachPlayer("trade", "Trade") end)

cmd({"world"}, "world", "Menu dialog World", function()
    local b = "add_label_with_icon|big|`!World Commands|left|3802|\nadd_spacer|small|\n"
    b = b.."add_button|nwx_pull|`9Pull all players|noflags|0|0|\n"
    b = b.."add_button|nwx_kick|`9Kick all players|noflags|0|0|\n"
    b = b.."add_button|nwx_trade|`9Trade all players|noflags|0|0|\n"
    b = b.."add_button|nwx_ban|`9Ban all players|noflags|0|0|\n"
    b = b.."add_button|nwx_unban|`@Unban World|noflags|0|0|"
    dialog("nab_world", b)
end)
AddCallback("nb_worldbtn", "OnPacket", function(_, p)
    if not p:find("action|dialog_return", 1, true) then return end
    if p:find("buttonClicked|nwx_pull") then eachPlayer("pull", "Pull")
    elseif p:find("buttonClicked|nwx_kick") then eachPlayer("kick", "Kick")
    elseif p:find("buttonClicked|nwx_trade") then eachPlayer("trade", "Trade")
    elseif p:find("buttonClicked|nwx_ban") then eachPlayer("ban", "Ban")
    elseif p:find("buttonClicked|nwx_unban") then sendPkt("action|input\n|text|/uba")
    else return end
    return true
end)

cmd({"wm", "wrench"}, "world", "Menu wrench mode", function() menuMode("wrench") end)
cmd({"wp"},   "world", "Wrench pull", function() setMode("wrench", "pull") end)
cmd({"wk"},   "world", "Wrench kick", function() setMode("wrench", "kick") end)
cmd({"wb"},   "world", "Wrench ban",  function() setMode("wrench", "ban") end)
cmd({"woff"}, "world", "Wrench off",  function() setMode("wrench", "off") end)
hook("nb_wrench", "OnVarlist", function(v)
    local m = mode.wrench
    if m == "off" or v[0] ~= "OnDialogRequest" or not v[1]:find("add_button|report_player|", 1, true) then return end
    local name = strip(v[1]):match("add_label_with_icon|big|(%w+)")
    if name then sendPkt("action|input\n|text|/"..m.." "..name) end
    return true
end)

cmd({"join", "j"}, "world", "Join mode: /j pull|kick|ban|off", function(a)
    if modes.join.opts and (a == "pull" or a == "kick" or a == "ban" or a == "off") then
        setMode("join", a)
    else
        menuMode("join")
    end
end)
hook("nb_join", "OnVarlist", function(v)
    if mode.join ~= "off" and v[0] == "OnSpawn" and not tostring(v[1]):find("type|local", 1, true) then
        local raw = tostring(v[1]):match("name|(`.[^`]+)")
        if raw then sendPkt("action|input\n|text|/"..mode.join.." "..raw:sub(3):lower()) end
    end
end)

cmd({"unbanall"}, "world", "Unban world", function() sendPkt("action|input\n|text|/uba") end)
cmd({"gs", "growscan"}, "world", "Growscan: /gs 1 blocks, /gs 2 floating", function(a)
    if a == "1" then scanBlocks() elseif a == "2" then scanFloat() else scanMenu() end
end)

----------------------------------------------------------------------
-- 10. FARMING
----------------------------------------------------------------------
local function modeCmds(key, a1, a2, a3, short)
    cmd({key}, "farm", modes[key].title.." menu / "..a1.."|"..a2.."|off", function(a)
        if a == a1 or a == a2 or a == "off" then setMode(key, a) else menuMode(key) end
    end)
    cmd({short[1]}, "farm", modes[key].title.." "..a1, function() setMode(key, a1) end)
    cmd({short[2]}, "farm", modes[key].title.." "..a2, function() setMode(key, a2) end)
    cmd({short[3]}, "farm", modes[key].title.." off",  function() setMode(key, "off") end)
end
modeCmds("ut",       "add", "empty", "off", {"ua", "ue", "uoff"})
modeCmds("gaia",     "add", "empty", "off", {"ga", "ge", "goff"})
modeCmds("donation", "add", "empty", "off", {"da", "de", "doff"})

hook("nb_sucker", "OnVarlist", function(v)
    if v[0] ~= "OnDialogRequest" then return end
    local d = v[1]
    local function stage1(dname, md)
        if md == "add" or md == "empty" then
            sendPkt("action|dialog_return\ndialog_name|"..dname.."\ntilex|"..embed(d, "tilex").."|\ntiley|"..embed(d, "tiley")..
                "|\nbuttonClicked|"..(md == "add" and "additem" or "retrieveitem").."\nchk_enablesucking|1")
            return true
        end
    end
    if d:find("end_dialog|itemsucker_block|Close|Update|", 1, true) then
        if stage1("itemsucker_block", mode.ut) then return true end
    elseif d:find("end_dialog|itemsucker_seed|Close|Update|", 1, true) then
        if stage1("itemsucker_seed", mode.gaia) then return true end
    elseif d:find("end_dialog|itemaddedtosucker|Close|Add|", 1, true) and (mode.ut == "add" or mode.gaia == "add") then
        sendPkt("action|dialog_return\ndialog_name|itemaddedtosucker\ntilex|"..embed(d, "tilex").."|\ntiley|"..embed(d, "tiley").."|\nitemtoadd|"..d:match("have (%d+)"))
        return true
    elseif d:find("end_dialog|itemremovedfromsucker|Close|Retrieve|", 1, true) and (mode.ut == "empty" or mode.gaia == "empty") then
        sendPkt("action|dialog_return\ndialog_name|itemremovedfromsucker\ntilex|"..embed(d, "tilex").."|\ntiley|"..embed(d, "tiley").."|\nitemtoremove|"..d:match("Amount:|(%d+)"))
        return true
    end
end)

hook("nb_donation", "OnVarlist", function(v)
    if v[0] ~= "OnDialogRequest" then return end
    local d = v[1]
    if mode.donation == "add" and d:find("end_dialog|give_item|||", 1, true) then
        sendPkt("action|dialog_return\ndialog_name|give_item\nitemID|"..embed(d, "itemID").."|\ntilex|"..embed(d, "tilex")..
            "|\ntiley|"..embed(d, "tiley").."|\nbuttonClicked|give\ncount|"..d:match("add_text_input|count|Count:|(%d+)").."\nsign_text|")
        return true
    elseif mode.donation == "empty" and d:find("end_dialog|donation_box_edit|Cancel||", 1, true) then
        sendPkt("action|dialog_return\ndialog_name|donation_box_edit\ntilex|"..embed(d, "tilex").."|\ntiley|"..embed(d, "tiley").."|\nbuttonClicked|clear")
        return true
    end
end)

cmd({"vend"}, "farm", "Menu vend mode", function() menuMode("vend") end)
cmd({"ve"},   "farm", "Fast empty vend", function() setMode("vend", "empty") end)
cmd({"va"},   "farm", "Fast stock vend", function() setMode("vend", "add") end)
cmd({"vb"},   "farm", "Fast beli vend: /vb jumlah", function(a)
    cfg.vendBuy = tonumber(a) or 1
    setMode("vend", "buy")
    say("Jumlah beli : `3"..cfg.vendBuy)
end)
cmd({"voff"}, "farm", "Vend mode off", function() setMode("vend", "off") end)
hook("nb_vend", "OnVarlist", function(v)
    if mode.vend == "off" or v[0] ~= "OnDialogRequest" then return end
    local d = v[1]
    local tx, ty = embed(d, "tilex"), embed(d, "tiley")
    if (mode.vend == "empty" or mode.vend == "add") and d:find("end_dialog|vending|Close|Update|", 1, true) then
        sendPkt("action|dialog_return\ndialog_name|vending\ntilex|"..tx.."|\ntiley|"..ty.."|\nbuttonClicked|"..(mode.vend == "empty" and "pullstock" or "addstock"))
        return true
    elseif mode.vend == "buy" and d:find("end_dialog|vending|Close|Buy|", 1, true) then
        local price = d:match("expectprice|([%d%-]+)")
        sendPkt("action|dialog_return\ndialog_name|vending\ntilex|"..tx.."|\ntiley|"..ty.."|\nexpectprice|"..price..
            "|\nexpectitem|"..embed(d, "expectitem").."|\nbuycount|"..cfg.vendBuy)
        return true
    elseif mode.vend == "buy" and d:find("end_dialog|vending|Cancel|OK|", 1, true) then
        local price = d:match("expectprice|([%d%-]+)")
        sendPkt("action|dialog_return\ndialog_name|vending\ntilex|"..tx.."|\ntiley|"..ty.."|\nverify|1|\nbuycount|"..embed(d, "buycount")..
            "|\nexpectprice|"..price.."|\nexpectitem|"..embed(d, "expectitem").."|")
        return true
    end
end)

cmd({"harvestid"}, "farm", "Set seed id (ganjil)", function(a)
    local id = tonumber(a)
    if not id or id % 2 == 0 then return say("Seed id harus angka `4ganjil") end
    cfg.harvestId = id
    say("Harvest id : `3"..(GetIteminfo(id) and GetIteminfo(id).name or id))
end)
cmd({"harvestdelay"}, "farm", "Set delay harvest (ms, min 150)", function(a)
    local n = tonumber(a)
    if not n or n < 150 then return say("Delay minimal `4150 ms") end
    cfg.harvestDelay = n
    say("Harvest delay : `3"..n.."ms")
end)
toggleCmd({"hv"}, "farm", "Toggle auto harvest", "harvest", "Auto Harvest", 1830,
    function()
        RunThread(function()
            while state.harvest do
                for _, t in pairs(GetTiles()) do
                    if not state.harvest then break end
                    if t.fg == cfg.harvestId and t.ready then
                        FindPath(t.pos_x, t.pos_y)
                        Sleep(cfg.harvestDelay)
                        SendPacketRaw({type=3, int_data=18, pos_x=GetLocal().pos_x, pos_y=GetLocal().pos_y, int_x=t.pos_x, int_y=t.pos_y})
                    end
                end
                Sleep(200)
            end
        end)
    end)

cmd({"spamtext", "spamt"}, "farm", "Set teks spam", function(a)
    cfg.spamText = a
    say("Spam text : `3"..a)
end)
cmd({"spamdelay", "sd"}, "farm", "Set delay spam (detik, min 3)", function(a)
    local n = tonumber(a)
    if not n or n <= 2 then return say("Delay minimal `43 detik") end
    cfg.spamDelay = n
    say("Spam delay : `3"..n.."s")
end)
toggleCmd({"/"}, "farm", "Toggle spam (ketik //)", "spam", "Auto Spam", 6272,
    function()
        RunThread(function()
            while state.spam do
                sendPkt("action|input\n|text|`"..math.random(1, 9)..cfg.spamText)
                Sleep(cfg.spamDelay * 1000)
            end
        end)
    end)

----------------------------------------------------------------------
-- 11. HOST
----------------------------------------------------------------------
local function blockDialogs(v) if v[0] == "OnDialogRequest" then return true end end

local function dropItem(id, amount)
    sendPkt("action|drop\n|itemID|"..id)
    sendPkt("action|dialog_return\ndialog_name|drop_item\nitemID|"..id.."|\ncount|"..amount)
end

local dropLocks

local function confirmDrop(amount, cb)
    pendingDrop = {amount=amount, cb=cb}
    local b = "add_label_with_icon|big|`4Konfirmasi Drop|left|1796|\nadd_spacer|small|\n"..
        "add_smalltext|`9Kamu akan drop `3"..amount.." `9locks|left|\n"..
        "add_smalltext|`4Yakin ingin melanjutkan?|left|\n"..
        "add_spacer|small|\n"..
        "add_button|nb_conf_yes|`2Ya, drop sekarang|noflags|0|0|\n"..
        "add_button|nb_conf_no|`4Batal|noflags|0|0|"
    dialog("nab_confirm", b)
end

dropLocks = function(amount, spot, skipConfirm)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return say("`4Jumlah tidak valid") end
    if state.confirmdrop and not skipConfirm and amount > cfg.confirmThreshold then
        return confirmDrop(amount, function() dropLocks(amount, spot, true) end)
    end
    RunThread(function()
        hook("nb_hideall", "OnVarlist", blockDialogs)
        if spot and spot.x then
            fx(spot.x, spot.y, 88)
            FindPath(spot.x, spot.y)
            FaceSide(cfg.side)
        end
        local needDl, needWl = amount // 100, amount % 100
        local wl, dl = count(242), count(1796)
        local ok = true
        if wl < needWl then
            if dl < needDl + 1 then ok = false
            else SendPacketRaw({type=10, int_data=1796}); Sleep(150) end
        elseif dl < needDl then ok = false end
        if not ok then
            say("`4Lock tidak cukup untuk drop `3"..amount)
            toast("Lock tidak cukup")
        else
            if needDl > 0 then dropItem(1796, needDl); Sleep(50) end
            if needWl > 0 then dropItem(242, needWl); Sleep(50) end
            say("Dropping `3"..needWl.." `9wls dan `3"..needDl.." `9dls")
            toast("Dropping `3"..needWl.." `9wls & `3"..needDl.." `9dls")
        end
        if spot and spot.x and pos.back.x then FindPath(pos.back.x, pos.back.y) end
        Sleep(800)
        unhook("nb_hideall")
    end)
end

cmd({"cd"}, "host", "Drop total WL: /cd 120 = 1 DL + 20 WL", function(a) dropLocks(a) end)

-- Toggle confirm drop (untuk safety jika dibutuhkan)
toggleCmd({"confirm"}, "host", "Dialog konfirmasi drop >100 (default OFF)", "confirmdrop", "Confirm Drop", 1796)

local function dropOne(id, name)
    return function(a)
        local n = tonumber(a)
        if not n or n <= 0 then return say("`4Pakai: /"..name.." jumlah") end
        if count(id) < n then return say("`4Jumlah "..name:upper().." tidak cukup") end
        RunThread(function()
            hook("nb_hideall", "OnVarlist", blockDialogs)
            say("Dropping `3"..n)
            dropItem(id, n)
            Sleep(1000)
            unhook("nb_hideall")
        end)
    end
end
cmd({"wd"}, "host", "Drop WL: /wd jumlah",  dropOne(242, "wd"))
cmd({"dd"}, "host", "Drop DL: /dd jumlah",  dropOne(1796, "dd"))
cmd({"bd"}, "host", "Drop BGL: /bd jumlah", dropOne(7188, "bd"))

local function dropAllOf(id, label)
    return function()
        local n = count(id)
        if n == 0 then return say("Kamu tidak punya "..label) end
        RunThread(function()
            hook("nb_hideall", "OnVarlist", blockDialogs)
            say("Dropping `3"..n.." `9"..label)
            dropItem(id, n)
            Sleep(1000)
            unhook("nb_hideall")
        end)
    end
end
cmd({"daw"}, "host", "Drop semua WL", dropAllOf(242, "wls"))
cmd({"dad"}, "host", "Drop semua DL", dropAllOf(1796, "dls"))

cmd({"side"}, "host", "Sisi drop: /side left|right", function(a)
    if a ~= "left" and a ~= "right" then return say("`4Pakai: /side left atau /side right") end
    cfg.side = a
    say("Sisi drop : `3"..a:upper())
end)

cmd({"sethost"}, "host", "Set host world", function(a) cfg.hostWorld = a; say("Host world : `3"..a) end)
cmd({"setsave"}, "host", "Set save world", function(a) cfg.saveWorld = a; say("Save world : `3"..a) end)
cmd({"host"}, "host", "Warp ke host world", function()
    if not cfg.hostWorld then return say("Host world belum diset") end
    say("Warp ke host world")
    SendPacket(3, "action|join_request\nname|"..cfg.hostWorld.."\ninvitedWorld|0")
end)
cmd({"save"}, "host", "Warp ke save world", function()
    if not cfg.saveWorld then return say("Save world belum diset") end
    say("Warp ke save world")
    SendPacket(3, "action|join_request\nname|"..cfg.saveWorld.."\ninvitedWorld|0")
end)

for i = 1, 4 do
    cmd({"setpos"..i, "sp"..i}, "host", "Set posisi player "..i, function() setPos(i) end)
    cmd({"pos"..i}, "host", "Ke posisi "..i, function()
        if not pos[i].x then return toast("`4Pos belum diset") end
        pathPreview(pos[i].x, pos[i].y, "find")
    end)
    cmd({"win"..i, "w"..i}, "host", "Drop lock ke winner "..i, function(a)
        if not pos[i].x then return toast("`4Pos belum diset") end
        dropLocks(a, pos[i])
    end)
    cmd({"dt"..i}, "host", "Drop tax ke winner "..i, function()
        if not pos[i].x then return toast("`4Pos belum diset") end
        dropLocks(cfg.dropTax % 10000, pos[i])
    end)
end
cmd({"setposback", "spb"}, "host", "Set posisi asal", function()
    local me = GetLocal()
    pos.back = {x = math.floor(me.pos_x/32), y = math.floor(me.pos_y/32)}
    fx(pos.back.x, pos.back.y, 356)
    say("Pos asal diset ke `3"..pos.back.x.." `9, `3"..pos.back.y)
end)
cmd({"back"}, "host", "Kembali ke posisi asal", function()
    if not pos.back.x then return toast("`4Pos belum diset") end
    pathPreview(pos.back.x, pos.back.y, "find")
end)

cmd({"settax"}, "host", "Set persen tax", function(a)
    local n = tonumber(a)
    if not n then return say("`4Pakai: /settax 5") end
    cfg.tax = n
    say("Tax diset ke `3"..n.."%")
end)
local function calcTax(total)
    local keep = math.floor(cfg.tax * (total / 100))
    cfg.dropTax = total - keep
    say("Jumlah drop : `3"..cfg.dropTax)
    say("Jumlah simpan : `3"..keep)
    SendVarlist({[0]="OnTextOverlay",
        [1]="     `3Tax Calculator`0\n`9Diambil : `3"..total.."\n`9Drop : `3"..cfg.dropTax.."\n`9Simpan : `3"..keep, netid=-1})
end
cmd({"tax"}, "host", "Hitung tax: /tax jumlah", function(a)
    local n = tonumber(a)
    if not n then return say("`4Pakai: /tax 100") end
    calcTax(math.floor(n))
end)

cmd({"collect", "tp"}, "host", "Collect lock dari semua posisi", function()
    RunThread(function()
        say("Collecting")
        local wl0, dl0 = count(242), count(1796)
        local spots = {}
        for i = 1, 4 do
            if pos[i].x then spots[#spots+1] = pos[i]; fx(pos[i].x, pos[i].y, 88) end
        end
        for _, off in ipairs({0, -1, 1}) do
            for _, o in pairs(GetObjects()) do
                for _, s in ipairs(spots) do
                    if (o.pos_x // 32) + off == s.x and (o.pos_y // 32) == s.y then
                        SendPacketRaw({type=11, int_data=o.oid, pos_x=o.pos_x, pos_y=o.pos_y})
                        break
                    end
                end
            end
        end
        Sleep(1300)
        local gw, gd = count(242) - wl0, count(1796) - dl0
        toast("Terkumpul : "..gw.." wls & "..gd.." dls")
        calcTax(gd * 100 + gw)
    end)
end)

local function digitSum(n) local s = 0; while n > 0 do s = s + n % 10; n = n // 10 end; return s end
hook("nb_spin", "OnVarlist", function(v)
    if v[0] ~= "OnTalkBubble" or v[3] == -1 then return end
    local raw = tostring(v[2])
    if not raw:find("spun the wheel and got", 1, true) then return end
    if cfg.visualSpin then
        if not raw:find("CP:", 1, true) then
            SendVarlist({[0]="OnTalkBubble", [1]=v[1],
                [2]="`7[``"..GetLocal().name.."`` spun the wheel and got `"
                    ..(VIS_SPIN_COLOR[cfg.visualSpin] or 4)..""..cfg.visualSpin.."``!`7]``",
                [3]=-1, netid=-1})
            return true
        end
    end
    if mode.spin == "off" then return end
    local out
    if raw:find("CP:", 1, true) then
        local _, e = raw:find("=", 1, true)
        out = "`0[ `4FAKE `0] "..(e and raw:sub(e + 1) or raw)
    else
        local n = tonumber(strip(raw):match("spun the wheel and got (%d+)"))
        if not n then return end
        local qq, reme = n % 10, digitSum(n) % 10
        if mode.spin == "check" then out = "`0[ `2REAL `0] "..raw
        elseif mode.spin == "qq" then out = raw.." `9QQ : `3"..qq
        elseif mode.spin == "reme" then out = raw.." `9REME : `3"..reme
        else
            out = "`0[ `1NabanGacor `0] `9CSN : `3"..n.." `0x `9QQ : `3"..qq.." `0x `9REME : `3"..reme
            say("CSN : `3"..n.." `0x `9QQ : `3"..qq.." `0x `9REME : `3"..reme)
        end
    end
    SendVarlist({[0]="OnTalkBubble", [1]=v[1], [2]=out, [3]=-1, netid=-1})
    return true
end)
cmd({"spin"}, "host", "Spin checker: /spin check|qq|reme|all|off", function(a)
    for _, o in ipairs(modes.spin.opts) do if a == o then return setMode("spin", a) end end
    menuMode("spin")
end)

cmd({"spinall"}, "host", "Spin semua wheel di world", function()
    RunThread(function()
        say("Spinning semua wheel")
        local list = {}
        for _, t in pairs(GetTiles()) do if t.fg == 758 then list[#list+1] = {t.pos_x, t.pos_y} end end
        for _, w in ipairs(list) do
            SendPacketRaw({type=3, int_data=3704, int_x=w[1], int_y=w[2], pos_x=GetLocal().pos_x, pos_y=GetLocal().pos_y})
            Sleep(200)
        end
    end)
end)

----------------------------------------------------------------------
-- 12. AUTOMATION
----------------------------------------------------------------------
local SURG_TOOL = {[1258]="Sponge", [1260]="Scalpel", [1262]="Anesthetic", [1266]="Antibiotic",
    [1268]="Splint", [1270]="Stitches", [1296]="Fix it", [4308]="Pins", [4310]="Transfusion",
    [4312]="Defibrillator", [4314]="Clamp", [4316]="Ultrasound", [4318]="Lab kit"}
local SURG = {
    {"`4The patient wakes up!", 1262}, {"`4The patient screams and flails!", 1262},
    {"Status: `4Heart stopped!", 4312}, {"Status: `6Coming to", 1262},
    {"Pulse: `4", 4310}, {"Temp: `[463]%d+", 1266}, {"Temp: `[463]%d+", 4318},
    {"Patient is losing blood `4very quickly!", 4314}, {"Patient is losing blood `4very quickly!", 1270},
    {"Patient is `6losing blood!", 4314}, {"Patient is `6losing blood!", 1270},
    {"Incisions: `[23]0", 1296}, {"The patient has not been diagnosed.", 4316},
    {"Status: `4Awake", 1262}, {"Bones: `[46].+ broken``", 1268},
    {"Patient broke his arm.", 1270}, {"Status: `3Awake", 1262}, {"Pulse: `6", 4310},
    {"`4You can't see what you are doing!", 1258}, {"tool1296", 1270},
    {"Bones: `[46].-shattered", 4308}, {"Bones: `[46].-shattered", 1260},
    {"Patient broke his leg.", 1270}, {"Patient is losing blood `3slowly.", 4314}, {"", 1260},
}
local function surgeryHook(v)
    if v[0] ~= "OnDialogRequest" then return end
    local d = v[1]
    if state.autosurg and d:find("end_dialog|surge|Cancel|Okay!|", 1, true) then
        sendPkt("action|dialog_return\ndialog_name|surge\ntilex|"..embed(d, "tilex").."|\ntiley|"..embed(d, "tiley"))
        return true
    end
    if not (state.autosurg or state.autosh) then return end
    for _, r in ipairs(SURG) do
        if d:find(r[1]) and d:find("tool"..r[2], 1, true) then
            local name = SURG_TOOL[r[2]]
            if state.autosurg then
                sendPkt("action|dialog_return\ndialog_name|surgery\nbuttonClicked|tool"..r[2])
                say(name)
                return true
            else
                say(name)
                MessageBox("Surgery Helper", "Use "..name)
                return
            end
        end
    end
end
hook("nb_surg", "OnVarlist", surgeryHook)
toggleCmd({"autosurg", "autos"}, "auto", "Auto surgery", "autosurg", "Auto Surgery", 1260)
toggleCmd({"autosurghelper", "autosh"}, "auto", "Helper surgery (popup alat)", "autosh", "Surgery Helper", 1262)

local cr = {c = {2298, 2308, 2320, 2324, 2332}, use = {}, step = "0", liq = "no", ban = "no"}
local function crimeHook(v)
    if not state.autocrime or v[0] ~= "OnDialogRequest" then return end
    local d = v[1]
    if d:find("Devil Ham``%'s `2Crush`` card `4melted") then cr.liq = "yes" end
    if d:find("Ms%. Terry") and d:find("Ban Hammer") then cr.ban = "yes" end
    if d:find("|Battle%!|") then
        cr.x, cr.y = d:match("tilex|(%d+)"), d:match("tiley|(%d+)")
        local vn = d:match("add_textbox|(.*)`` is")
        if vn then say("Villain : `3"..vn) end
        if d:find("Crime in Progress") then cr.c = {2298, 2308, 2320, 2324, 2332} end
        local c = cr.c
        if d:find("Jimmy Snow") then cr.use = {c[5], c[4], c[3]}
        elseif d:find("Big Bertha") then cr.use = {c[1], c[4], c[3]}
        elseif d:find("Shockinator") then cr.use = {c[4], c[3], c[1]}
        elseif d:find("The Firebug") then cr.use = {c[2], c[1], c[5]}
        elseif d:find("Generic Thug") or d:find("Kat 5") then cr.use = {c[4], c[3], c[2]}
        elseif d:find("Professor Pummel") then
            c = {2296, 2298, 2300, 2320, 2324}; cr.c = c; cr.use = {c[3], c[2], c[1]}
        elseif d:find("Z%. Everett Koop") then
            c = {2296, 2298, 2300, 2320, 2324}; cr.c = c; cr.use = {c[3], c[1], c[2]}
        elseif d:find("Dr%. Destructo") then
            c = {2298, 2308, 2310, 2314, 2316}; cr.c = c; cr.step = "0"; cr.use = {c[1], c[3], c[5]}
        elseif d:find("Dragon Hand") or d:find("Almighty Seth") then
            c = {2308, 2312, 2314, 2326, 2328}; cr.c = c; cr.use = {c[5], c[4], 6969}
        elseif d:find("Devil Ham") then
            c = {2298, 2332, 2334, 2336, 2338}; cr.c = c
            cr.use = {c[1], c[4], c[5], c[3], c[2]}; cr.liq = "no"; cr.step = "1"
        elseif d:find("Ms%. Terry") then
            c = {2294, 2316, 2322, 2328, 2338}; cr.c = c
            cr.use = {c[1], c[2], c[3], c[4], c[5]}; cr.ban = "no"
        end
        sendPkt("action|dialog_return\ndialog_name|crime_edit\ntilex|"..cr.x.."|\ntiley|"..cr.y.."|\nstate|0||\nbuttonClicked|button_ok\n\nc"..
            c[1].."|1\nc"..c[2].."|1\nc"..c[3].."|1\nc"..c[4].."|1\nc"..c[5].."|1\n")
        return true
    elseif d:find("Fighting Crime") then
        local u = cr.use
        local pick
        local function has(i) return u[i] and d:find("c"..u[i]) end
        if d:find("Devil Ham") then
            if cr.liq == "no" then pick = has(1) and u[1] or "passturn"
            elseif has(2) and cr.step == "0" then cr.step = "1"; pick = u[2]
            elseif has(3) then pick = u[3]
            elseif has(4) then pick = u[4]
            elseif has(5) then pick = u[5]
            else pick = "passturn" end
        elseif d:find("Ms%. Terry") then
            local nxt = d:match("is going to play `(%d)")
            if nxt then pick = ({["2"]=u[1], ["4"]=u[2], ["9"]=u[4], ["1"]=u[5]})[nxt] or "passturn"
            elseif has(3) then pick = u[3]
            elseif has(5) and cr.ban == "yes" then pick = u[5]
            elseif has(1) then pick = u[1]
            elseif has(4) then pick = u[4]
            elseif has(5) then pick = u[5]
            elseif has(2) then pick = u[2]
            else pick = "passturn" end
        elseif d:find("Dr%. Destructo") then
            if has(1) and cr.step == "0" then pick = u[1]; cr.step = "1"
            elseif has(2) then pick = u[2]
            elseif has(3) then pick = u[3]
            else pick = "passturn" end
        else
            if has(1) then pick = u[1] elseif has(2) then pick = u[2] elseif has(3) then pick = u[3] else pick = "passturn" end
        end
        toast("Please wait..")
        sendPkt("action|dialog_return\ndialog_name|crime_edit\ntilex|"..cr.x.."|\ntiley|"..cr.y.."|\nstate|1||\nbuttonClicked|c"..pick)
        return true
    end
end
hook("nb_crime", "OnVarlist", crimeHook)
toggleCmd({"autocrime", "autoc"}, "auto", "Auto crime", "autocrime", "Auto Crime", 2298)

local TOOL = {Drone=6532, Tele=6526, Doc=6534, Scan=6530, Torp=6540, Dip=6538, Sup=6536,
    Giga=6528, Shield=6518, AI=6520, Gala=6522, Meds=6524}
local TOOLNAME = {Drone="Tactical Drone", Tele="Teleporter Charge", Doc="Stellar Documents",
    Scan="Quadriscanner", Torp="Growton Torpedo", Dip="Cyborg Diplomat", Sup="Star Supplies",
    Giga="Gigablaster", Shield="HyperShields", AI="AI Brain", Gala="Galactibolt", Meds="Space Meds"}
local MISSIONS = {}
local function mission(seq, ...)
    for _, pat in ipairs({...}) do MISSIONS[#MISSIONS+1] = {pat, seq} end
end
local DELIVERY = {[0]="Drone", "Tele", "Scan", "Giga", "Sup", "Tele"}
mission({[0]="Drone", "Tele", "Scan", "Tele", "Doc"}, "%w+ Data")
mission({[0]="Drone", "Doc"}, "Set a Course")
mission({[0]="Drone", "Torp", "Dip", "Tele", "Doc", "Tele"}, "Outpost Attack", "One Angry Ship")
mission({[0]="Drone", "Torp", "Sup", "Torp", "Giga"}, "Starachnid Attack")
mission({[0]="Drone", "Shield", "Torp", "Torp"}, "%w+ Attack")
mission({[0]="Tele", "Scan", "Meds", "Sup"}, "Life Pod")
mission({[0]="Scan", "Giga", "Giga"}, "Boarding Party")
mission({[0]="Drone", "Tele", "Tele", "Tele"}, "Experimental Salvage")
mission({[0]="Drone", "Tele", "AI", "Torp", "Torp"}, "Dark Ship")
mission({[0]="Drone", "Tele", "Scan", "Giga", "Tele"}, "%w+ Hunt")
mission({[0]="Drone", "Tele", "Scan", "Tele"}, "Windy Days", "Salvage Run")
mission({[0]="Drone", "Dip", "Sup", "Doc"}, "Ancient Temple")
mission({[0]="Drone", "Shield", "Shield", "Shield", "Shield"}, "A Challenge")
mission({[0]="Gala", "Drone", "Tele", "Scan", "Tele", "Tele"}, "Miner Rescue")
mission({[0]="Drone", "AI", "Tele", "Giga", "Tele"}, "Hunter and Prey")
mission({[0]="Drone", "AI", "Shield", "Sup"}, "Giant Skeleton")
mission({[0]="Drone", "Tele", "Scan", "AI", "Giga", "Tele", "Scan", "Tele", "Torp"}, "Shadow Stalkers")
mission({[0]="Drone", "Tele", "AI", "Tele", "Shield", "Torp", "Tele"}, "Planet Calamity")
mission({[0]="Drone", "Dip", "Gala", "AI", "Doc"}, "A Strange One")
mission({[0]="Drone", "Tele", "Scan", "AI", "Scan", "Giga", "Tele"}, "Tasty Cakes")
mission({[0]="Drone", "Tele", "Giga", "Tele"}, "Taking Aim")
mission({[0]="Tele", "Dip", "Giga", "Doc"}, "Bad Taste")
mission({[0]="Shield", "Gala", "Meds", "AI", "Drone", "Gala", "Meds", "Gala"}, "Solar Impact!")
mission({[0]="AI", "Drone", "Torp", "AI"}, "Junk Punks")
mission({[0]="Tele", "Scan", "Giga", "Scan", "AI", "AI", "Shield", "Gala", "Doc", "Tele"}, "Cryonite Crisis")
mission({[0]="Gala", "Drone", "Tele", "Scan", "Meds", "Tele"}, "Ship Rescue")
mission({[0]="Tele", "Scan", "AI", "Doc"}, "Skeleton Crew")
mission({[0]="Drone", "Tele", "Scan", "Dip", "Doc", "Tele"}, "Ghost Ship")
mission({[0]="Drone", "Tele", "Scan", "Giga", "Tele", "Torp"}, "Pit o' Trouble")
mission({[0]="Drone", "AI", "Dip", "Dip", "Scan", "AI"}, "Close Encounter")
mission({[0]="Meds", "Drone", "Shield", "Tele", "Scan", "Giga", "Meds", "Scan", "Tele", "Torp"}, "Escape Pod")
mission({[0]="Shield", "Drone", "Dip", "Tele", "Doc", "Gala", "Sup"}, "Prevent War")
mission({[0]="Drone", "Tele", "Dip", "Meds", "Doc"}, "Mining Colony Rescue")
mission(DELIVERY, "Mining Colony Delivery")
mission({[0]="Drone", "Shield", "Torp", "AI", "Torp"}, "%w+ Duel")
mission(DELIVERY, "%w.- Delivery")
mission({[0]="Drone", "Tele", "Scan", "AI", "Scan", "Giga", "Tele"}, "Who's There", "She's Gonna Blow")

local st = {step = 0}
local function useTool(name)
    sendPkt("action|dialog_return\ndialog_name|startopia\nbuttonClicked|tool"..TOOL[name])
    say(TOOLNAME[name])
end
local function startopiaHook(v)
    if not state.autostartopia or v[0] ~= "OnDialogRequest" then return end
    local d = v[1]
    if d:find("end_dialog|startopia", 1, true) and d:find("Health", 1, true) then
        local found
        for _, m in ipairs(MISSIONS) do
            if d:find("add_label_with_icon|big|`w"..m[1]) then found = m; break end
        end
        if not found then return end
        local seq = found[2]
        if d:find("Skill Success", 1, true) or d:find("Skill Fail", 1, true) then
            if d:find("Skill Success", 1, true) then st.step = st.step + 1 end
            if seq[st.step] then useTool(seq[st.step]) end
        else
            st.step = 0
            say("Mission : `3"..(d:match("add_label_with_icon|big|`w([^`|]+)") or "?"))
            useTool(seq[0])
        end
        return true
    elseif d:find("Starship Helm", 1, true) then
        sendPkt("action|dialog_return\ndialog_name|startopia\nbuttonClicked|beginvoyage")
        return true
    elseif d:find("It is a good day to flee!", 1, true) then
        sendPkt("action|dialog_return\ndialog_name|startopia\nbuttonClicked|failmission")
        say("`4Fail")
        return true
    elseif d:find("The voyage continues!", 1, true) then
        sendPkt("action|dialog_return\ndialog_name|startopia\nbuttonClicked|finishmission")
        say("`2Success")
        st.step = 0
        return true
    end
end
hook("nb_startopia", "OnVarlist", startopiaHook)
toggleCmd({"autostartopia", "autost"}, "auto", "Auto startopia", "autostartopia", "Auto Startopia", 6532)

-- AUTO-FARM
cmd({"setseed"}, "auto", "Set seed id untuk autofarm (/setseed ID)", function(a)
    local id = tonumber(a)
    if not id or id % 2 == 0 then return say("`4Seed id harus ganjil (contoh: 3, 5, 7)") end
    cfg.seedId = id
    say("Seed autofarm : `3"..(GetIteminfo(id) and GetIteminfo(id).name or id))
end)
toggleCmd({"autofarm", "af"}, "auto", "Auto farm (harvest + plant)", "autofarm", "Auto Farm", 6950,
    function()
        if not cfg.seedId then say("`4Set dulu: /setseed ID") end
        RunThread(function()
            while state.autofarm do
                local me = GetLocal()
                local any = false
                for _, t in pairs(GetTiles()) do
                    if not state.autofarm then break end
                    if t.ready and t.fg > 0 and t.fg % 2 == 1 then
                        any = true
                        FindPath(t.pos_x, t.pos_y)
                        Sleep(150)
                        local me2 = GetLocal()
                        SendPacketRaw({type=3, int_data=18, pos_x=me2.pos_x, pos_y=me2.pos_y, int_x=t.pos_x, int_y=t.pos_y})
                        Sleep(200)
                    end
                end
                if not any and cfg.seedId then
                    for _, t in pairs(GetTiles()) do
                        if not state.autofarm then break end
                        if t.fg == 2 and t.bg == 2 and not t.ready then
                            FindPath(t.pos_x, t.pos_y)
                            Sleep(150)
                            local me2 = GetLocal()
                            SendPacketRaw({type=3, int_data=cfg.seedId, pos_x=me2.pos_x, pos_y=me2.pos_y, int_x=t.pos_x, int_y=t.pos_y})
                            Sleep(250)
                        end
                    end
                end
                Sleep(400)
            end
        end)
    end)

-- AUTO-FISH
toggleCmd({"autofish", "afish"}, "auto", "Auto fish (experimental)", "autofish", "Auto Fish", 340,
    function()
        RunThread(function()
            while state.autofish do
                local me = GetLocal()
                local found = false
                for _, t in pairs(GetTiles()) do
                    if not state.autofish then break end
                    if t.water then
                        found = true
                        SendPacketRaw({type=3, int_data=18, pos_x=me.pos_x, pos_y=me.pos_y, int_x=t.pos_x, int_y=t.pos_y})
                        Sleep(4000)
                        break
                    end
                end
                if not found then Sleep(1000) end
            end
        end)
    end)
hook("nb_fish", "OnVarlist", function(v)
    if not state.autofish then return end
    if v[0] ~= "OnDialogRequest" then return end
    local d = v[1]
    if d:find("end_dialog|fishing|", 1, true) then
        local tx = embed(d, "tilex")
        local ty = embed(d, "tiley")
        for _, btn in ipairs({"cast","fish","reel","pull","ready"}) do
            if d:find("add_button|"..btn.."|", 1, true) then
                sendPkt("action|dialog_return\ndialog_name|fishing\ntilex|"..tx.."|\ntiley|"..ty.."|\nbuttonClicked|"..btn)
                return true
            end
        end
    end
end)

----------------------------------------------------------------------
-- 13. VISUAL
----------------------------------------------------------------------
local cl = {hat=0, shirt=0, pant=0, shoes=0, hand=0, wing=0, hair=0, neck=0, ances=0}
local function wear()
    local me = GetLocal()
    fx(math.floor(me.pos_x/32), math.floor(me.pos_y/32), 73)
    sendPkt("action|setSkin\ncolor|3033464831")
    SendVarlist({[0]="OnSetClothing", [1]={cl.hat, cl.shirt, cl.pant}, [2]={cl.shoes, 0, cl.hand},
        [3]={cl.wing, cl.hair, cl.neck}, [4]=3033464831, [5]={cl.ances, 0, 0}, netid=me.netid})
    SendVarlist({[0]="OnPlayPositioned", [1]="audio/change_clothes.wav", netid=me.netid})
end
for _, slot in ipairs({"hat", "shirt", "pant", "shoes", "hand", "wing", "hair", "neck", "ances"}) do
    cmd({"v"..slot}, "visual", "Set visual "..slot.." (id)", function(a)
        cl[slot] = tonumber(a) or 0
        say(slot:gsub("^%l", string.upper).." : `3"..cl[slot])
        wear()
    end)
end
cmd({"clothe", "clothes"}, "visual", "Pakai set visual", function() say("Changing clothes"); wear() end)
toggleCmd({"saveclothe", "sc"}, "visual", "Pakai set visual tiap pindah world", "saveclothes", "Save Clothes", 1784)
hook("nb_saveclothes", "OnVarlist", function(v)
    if state.saveclothes and v[0] == "OnMagicCompassTrackingItemIDChanged" then wear(); return true end
end)
cmd({"load1", "load"}, "visual", "Preset outfit 1", function()
    cl.hat, cl.hair, cl.wing, cl.ances = 3042, 2872, 1784, 5134
    say("Preset outfit 1 dimuat")
    wear()
end)

local TITLES = {
    g4g = {"jo|donor"}, master = {"jo|master"}, maxlevel = {"jo|maxLevel"},
    doctor = {"jo|doctor", prefix = "Dr."}, legend = {"jo|doctor", suffix = " of Legend``"},
}
local function applyTitle(kind)
    local me = GetLocal()
    local n = strip(me.name)
    n = n:gsub(" of Legend", "")
    n = n:gsub("Dr%.", "")
    local t = TITLES[kind]
    if t then
        me.name = (t.prefix or "")..n..(t.suffix or "")
        SendVarlist({[0]="OnCountryState", [1]=t[1], netid=me.netid})
    else
        me.name = n
        SendVarlist({[0]="OnCountryState", [1]="jo|", netid=me.netid})
    end
end
local titleNow = "none"
for _, k in ipairs({"g4g", "master", "doctor", "maxlevel", "legend"}) do
    cmd(k == "legend" and {"oflegend", "legend"} or {k}, "visual", "Title "..k, function()
        titleNow = k; applyTitle(k); say("Title `3"..k.." `9aktif")
    end)
end
cmd({"titlereset"}, "visual", "Reset title", function() titleNow = "none"; applyTitle(nil); say("Title direset") end)
cmd({"title"}, "visual", "/title reset untuk reset", function(a)
    if a == "reset" then titleNow = "none"; applyTitle(nil); say("Title direset") else say("`4Pakai: /title reset") end
end)
cmd({"titles"}, "visual", "Menu pilih title", function()
    local b = "add_label_with_icon|big|`3Pilih Title|left|6276|\nadd_spacer|small|\n"
    for _, k in ipairs({"g4g", "master", "doctor", "maxlevel", "legend"}) do
        b = b.."add_button|nb_ti_"..k.."|`9"..k.."|noflags|0|0|\n"
    end
    b = b.."add_spacer|small|\nadd_button|nb_ti_reset|`@Reset Title|noflags|0|0|"
    dialog("nab_title", b)
end)
AddCallback("nb_titlebtn", "OnPacket", function(_, p)
    local k = p:match("buttonClicked|nb_ti_(%a+)")
    if not k then return end
    if k == "reset" then titleNow = "none"; applyTitle(nil) else titleNow = k; applyTitle(k) end
    say("Title `3"..k)
    return true
end)
toggleCmd({"st"}, "visual", "Pakai title tiap pindah world", "savetitle", "Save Title", 6276)
hook("nb_savetitle", "OnVarlist", function(v)
    if state.savetitle and v[0] == "OnMagicCompassTrackingItemIDChanged" then
        applyTitle(titleNow ~= "none" and titleNow or nil)
    end
end)

cmd({"flag"}, "visual", "Ganti bendera: /flag id", function(a)
    say("Flag : `3"..a)
    SendVarlist({[0]="OnCountryState", [1]=a, netid=GetLocal().netid})
end)
cmd({"guild"}, "visual", "Ganti guild icon: /guild id", function(a)
    local id = tonumber(a)
    if not id then return say("`4Pakai: /guild ID") end
    SendVarlist({[0]="OnGuildDataChanged", [1]=1, [2]=1, [3]=id, [4]=0, netid=GetLocal().netid})
end)
cmd({"weather"}, "visual", "Weather random", function()
    local x = math.random(1, 66)
    SendVarlist({[0]="OnSetCurrentWeather", [1]=x, netid=-1})
    say("Weather : `3"..x)
end)
cmd({"give"}, "visual", "Item visual: /give id jumlah", function(a)
    local id, n = a:match("(%d+)%s+(%d+)")
    if not id then return say("`4Pakai: /give ID JUMLAH") end
    id, n = tonumber(id), tonumber(n)
    local info = GetIteminfo(id)
    say("Menambah `3"..(info and info.name or id).." `9x`3"..n)
    SendPacketRawClient({type=13, int_data=id, count2=n})
end)
cmd({"name"}, "visual", "Ganti nama visual", function(a)
    say("Nama : "..a)
    SendVarlist({[0]="OnNameChanged", [1]=a, netid=GetLocal().netid})
end)
cmd({"hide"}, "visual", "Sembunyikan nama semua player", function()
    say("Menyembunyikan nama player")
    for _, p in pairs(GetPlayers()) do
        SendVarlist({[0]="OnNameChanged", [1]="`9[ HIDDEN ]", netid=p.netid})
    end
end)
cmd({"inv"}, "visual", "Kurangi lag (baju player dihapus)", function()
    say("Mengurangi lag..")
    for _, p in pairs(GetPlayers()) do
        SendVarlist({[0]="OnSetClothing", [1]={0,0,0}, [2]={0,0,0}, [3]={0,0,0}, [4]=2, [5]={0,0,0}, netid=p.netid})
    end
end)

----------------------------------------------------------------------
-- 13b. FITUR v1 YANG DIPINDAHKAN
----------------------------------------------------------------------
cmd({"donatewl"}, "visual", "Bubble palsu donate WL", function(a)
    if a == "" then return say("`4Pakai: /donatewl jumlah") end
    SendVarlist({[0]="OnTalkBubble", [1]=GetLocal().netid,
        [2]="`7[```5[``"..GetLocal().name.." places`5"..a.."`` `2World Lock`` into the Donation Box`5]```7]``",
        [3]=0, [4]=0, netid=-1})
    say("Fake donate WL : `3"..a)
end)
cmd({"donatedl"}, "visual", "Bubble palsu donate DL", function(a)
    if a == "" then return say("`4Pakai: /donatedl jumlah") end
    SendVarlist({[0]="OnTalkBubble", [1]=GetLocal().netid,
        [2]="`7[```5[``"..GetLocal().name.." places`5"..a.."`` `2Diamond Lock`` into the Donation Box`5]```7]``",
        [3]=0, [4]=0, netid=-1})
    say("Fake donate DL : `3"..a)
end)
cmd({"donatebgl"}, "visual", "Bubble palsu donate BGL", function(a)
    if a == "" then return say("`4Pakai: /donatebgl jumlah") end
    SendVarlist({[0]="OnTalkBubble", [1]=GetLocal().netid,
        [2]="`7[```5[``"..GetLocal().name.." places`5"..a.."`` `2Blue Gem Lock`` into the Donation Box`5]```7]``",
        [3]=0, [4]=0, netid=-1})
    say("Fake donate BGL : `3"..a)
end)

cmd({"visualspin", "vspin"}, "visual", "Set visual spin N (0-36)", function(a)
    if a == "off" or a == "reset" then
        cfg.visualSpin = nil
        return say("Visual spin : `4OFF")
    end
    local n = tonumber(a)
    if not n or n < 0 or n > 36 then
        return say("`4Pakai: /visualspin 0-36 (atau /visualspin off)")
    end
    cfg.visualSpin = math.floor(n)
    say("Visual spin : `3"..cfg.visualSpin)
end)

cmd({"fakeban", "fban"}, "util", "Fake perma ban by system", function()
    local name = GetLocal().name
    SendVarlist({[0]="OnConsoleMessage",
        [1]="Reality flickers as you begin to wake up. (`$Ban`` mod added, `$730 days`` left)", netid=-1})
    SendVarlist({[0]="OnAddNotification", [1]="interface/atomic_button.rttex",
        [2]="Warning from `4System``: You've been `4BANNED`` from `wGrowtopia`` for 730 days",
        [3]="audio/hub_open.wav", [4]=0, netid=-1})
    SendVarlist({[0]="OnConsoleMessage",
        [1]="Warning from `4System``: You've been `4BANNED`` from `wGrowtopia`` for 730 days", netid=-1})
    SendVarlist({[0]="OnConsoleMessage",
        [1]="`#** ```$The Ancients`` have used `#Ban`` on `w"..name.."``! `#**``", netid=-1})
    SendVarlist({[0]="OnConsoleMessage",
        [1]="`4** `$"..name.."`` AUTO-BANNED BY SYSTEM **`` (`$/rules`` to view rules)", netid=-1})
    say("Fake ban triggered")
    webhookLog("FakeBan", "Triggered fake ban", 15158332)
end)

local vaultPos = {x = nil, y = nil}
cmd({"vault"}, "util", "Set x/y vault (Safe Vault) untuk /bypass", function()
    for _, t in pairs(GetTiles()) do
        if t.fg == 8878 then
            vaultPos.x = math.floor(t.pos_x / 32)
            vaultPos.y = math.floor(t.pos_y / 32)
            fx(vaultPos.x, vaultPos.y, 354)
            say("Vault pos : `3"..vaultPos.x.." `0x `9"..vaultPos.y)
            return
        end
    end
    say("`4Safe Vault (id 8878) tidak ditemukan")
end)
cmd({"bypass"}, "util", "Auto bypass vault (butuh min 1 Dirt)", function()
    if not vaultPos.x then return say("`4Ketik /vault dulu") end
    sendPkt("action|dialog_return\ndialog_name|storageboxxtreme\ntilex|"..vaultPos.x..
        "|\ntiley|"..vaultPos.y.."|\nitemid|2|\nbuttonClicked|do_add\nitemcount|1")
    say("Bypass dikirim ke `3("..vaultPos.x..","..vaultPos.y..")")
end)

toggleCmd({"dial34"}, "util", "Auto dial -34 saat buka telepon", "dial34", "Auto Dial -34", 3288,
    function()
        hook("nb_dial34a", "OnVarlist", function(v)
            if v[0] ~= "OnDialogRequest" then return end
            if not tostring(v[1]):find("Dial a number to call somebody in Growtopia", 1, true) then return end
            sendPkt("action|dialog_return\ndialog_name|phonecall\ntilex|"..embed(v[1], "tilex")..
                "|\ntiley|"..embed(v[1], "tiley").."|\nnum|-34|\nbuttonClicked|chc0")
            return true
        end)
        hook("nb_dial34b", "OnVarlist", function(v)
            if v[0] == "OnDialogRequest"
                and tostring(v[1]):find("end_dialog|phonecall|Hang Up||", 1, true) then
                return true
            end
        end)
    end,
    function()
        unhook("nb_dial34a")
        unhook("nb_dial34b")
    end)

local function doSafeAction(kind, label)
    SendVarlist({[0]="OnAddNotification", [1]="interface/atomic_button.rttex",
        [2]="`#@"..label.." `4Just joined the world.",
        [3]="audio/hub_open.wav", [4]=0, netid=-1})
    say("`#@"..label.." `4joined! (safe mode)")
    bubble("`9Collecting..")
    local me = GetLocal()
    for _, o in pairs(GetObjects()) do
        if math.abs(me.pos_x - o.pos_x) < 320 and math.abs(me.pos_y - o.pos_y) < 320 then
            SendPacketRaw({type=11, int_data=o.oid, pos_x=o.pos_x, pos_y=o.pos_y})
        end
    end
    if kind == "ban_leave" then
        for _, p in pairs(GetPlayers()) do
            local n = strip(p.name)
            if not isWhitelisted(n) then
                sendPkt("action|input\n|text|/ban "..n)
            else
                say("`9Skip whitelist: `3"..n)
            end
        end
        sendPkt("action|input\n|text|/unaccess")
        sendPkt("action|dialog_return\ndialog_name|unaccess")
    elseif kind == "unaccess_leave" then
        sendPkt("action|input\n|text|/unaccess")
        sendPkt("action|dialog_return\ndialog_name|unaccess")
    end
    SendPacket(3, "action|quit_to_exit")
    SendPacket(3, "action|join_request\nname|"..(cfg.saveWorld or "EXIT").."\ninvitedWorld|0")
    webhookLog("SafeMode", label.." triggered "..kind.." in "..GetLocal().world, 15105570)
end

hook("nb_safe", "OnVarlist", function(v)
    if mode.safe == "off" then return end
    if v[0] ~= "OnGuildDataChanged" then return end
    local gid = v[3]
    if gid ~= 5956 and gid ~= 276 then return end
    local label = (gid == 5956) and "Moderator" or "Guardian"
    if mode.safe == "banleave" then doSafeAction("ban_leave", label)
    elseif mode.safe == "unaccess" then doSafeAction("unaccess_leave", label)
    elseif mode.safe == "leave" then doSafeAction("leave", label)
    end
    return true
end)

cmd({"safe"}, "util", "Safe mode: /safe 1|2|3|off", function(a)
    local map = {["1"]="banleave", ["2"]="unaccess", ["3"]="leave", ["off"]="off"}
    local opt = map[a] or a
    if opt == "banleave" or opt == "unaccess" or opt == "leave" or opt == "off" then
        setMode("safe", opt)
        if opt ~= "off" and not cfg.saveWorld then
            say("`4Catatan: /save belum diset, fallback ke EXIT")
        end
    else
        menuMode("safe")
    end
end)

cmd({"testmod"}, "util", "Test trigger safe mode", function()
    if mode.safe == "off" then
        return say("`4Aktifkan dulu: /safe 1|2|3")
    end
    if mode.safe == "banleave" then doSafeAction("ban_leave", "Moderator")
    elseif mode.safe == "unaccess" then doSafeAction("unaccess_leave", "Moderator")
    elseif mode.safe == "leave" then doSafeAction("leave", "Moderator")
    end
end)

----------------------------------------------------------------------
-- 13c. TEXT INPUT DIALOGS
----------------------------------------------------------------------
cmd({"taxui"}, "host", "GUI hitung tax (input langsung)", function()
    local b = "add_label_with_icon|big|`3Tax Calculator|left|758|\nadd_spacer|small|\n"..
        "add_smalltext|`9Tax saat ini : `3"..cfg.tax.."%|left|\n"..
        "add_text_input|tax_amt|Jumlah lock|100|6|\n"..
        "add_spacer|small|\n"..
        "add_button|nb_tax_go|`2Hitung|noflags|0|0|"
    dialog("nab_tax", b)
end)
cmd({"vbui"}, "farm", "GUI set jumlah beli vend", function()
    local b = "add_label_with_icon|big|`3Fast Buy Vend|left|2978|\nadd_spacer|small|\n"..
        "add_smalltext|`9Jumlah beli saat ini : `3"..cfg.vendBuy.."|left|\n"..
        "add_text_input|vb_amt|Jumlah beli|"..cfg.vendBuy.."|4|\n"..
        "add_spacer|small|\n"..
        "add_button|nb_vb_go|`2Set & Aktifkan|noflags|0|0|"
    dialog("nab_vb", b)
end)
cmd({"cdui"}, "host", "GUI drop locks", function()
    local b = "add_label_with_icon|big|`3Drop Locks|left|1796|\nadd_spacer|small|\n"..
        "add_smalltext|`9WL : `3"..count(242).." `1& `9DL : `3"..count(1796).."|left|\n"..
        "add_text_input|cd_amt|Total lock (WL)|100|7|\n"..
        "add_spacer|small|\n"..
        "add_button|nb_cd_go|`2Drop|noflags|0|0|"
    dialog("nab_cd", b)
end)

AddCallback("nb_textinput", "OnPacket", function(_, p)
    if not p:find("action|dialog_return", 1, true) then return end

    if p:find("buttonClicked|nb_tax_go") then
        local n = p:match("tax_amt|([%d%.]+)")
        if n and tonumber(n) then
            calcTax(math.floor(tonumber(n)))
        else
            say("`4Input tax tidak valid")
        end
        return true
    end

    if p:find("buttonClicked|nb_vb_go") then
        local n = p:match("vb_amt|([%d%.]+)")
        if n and tonumber(n) and tonumber(n) > 0 then
            cfg.vendBuy = math.floor(tonumber(n))
            setMode("vend", "buy")
            say("Jumlah beli : `3"..cfg.vendBuy)
        else
            say("`4Input vend tidak valid")
        end
        return true
    end

    if p:find("buttonClicked|nb_cd_go") then
        local n = p:match("cd_amt|([%d%.]+)")
        if n and tonumber(n) and tonumber(n) > 0 then
            dropLocks(math.floor(tonumber(n)))
        else
            say("`4Input lock tidak valid")
        end
        return true
    end
end)

----------------------------------------------------------------------
-- 14. START
----------------------------------------------------------------------
say("Ketik `3/proxy `9untuk membuka menu (v2.6.2)")
bubble("`9NabanGacor Proxy v2.6.2 berhasil di-inject.")