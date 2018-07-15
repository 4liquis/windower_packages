local os = require("os")
local ui = require("ui")
local string = require("string")
local command = require("command")
local packets = require("packets")
local settings = require("settings")
local treasure = require("treasure")

local pt_settings = {
    ui = {
        x = 145,
        y = 440,
        enabled = true,
    },
    auto = {
        accept_invites = true,   -- also for auto sending invites upon party requests
        decline_invites = false, -- also ignores party requests from players on blacklists
    },
    blacklist = {}, 
    whitelist = {},
}

pt_settings = settings.load(pt_settings, 'settings.lua')

local invite_dialog = {}
local invite_dialog_state = {
    title = 'Party Invite',
    style = 'normal',
    x = pt_settings.ui.x,
    y = pt_settings.ui.y,
    width = 179,
    height = 96,
    resizable = false,
    moveable = true,
    closable = true,
}
local unhandled_requests = {}
local unhandeled_invite = false


local alias = {
    add = {
        ['add'] = true,
        ['a'] = true,
        ['+'] = true,
    },
    remove = {
        ['remove'] = true,
        ['rm'] = true,
        ['r'] = true,
        ['-'] = true,
    },
    on = {
        ['true'] = true,
        ['yes'] = true,
        ['on'] = true,
        ['y'] = true,
    },
    off = {
        ['false'] = true,
        ['off'] = true,
        ['no'] = true,
        ['n'] = true,
    }
}

-- Command Arg Types
-- Create and Register types
command.arg.register('names', '<names:string(%a+)>*')

command.arg.register_type('boolean', {
    check = function(str)
        if alias.on[str] then
            return true
        elseif alias.off[str] then
            return false
        end

        error('Expected a boolean value.')
    end
})

-- Addon Command Handlers
-- Seven main commands additoinal sub_commands within
local pt_command = command.new("pt")

function join(name)
    command.input("/prcmd add " .. name)
end

pt_command:register("j", join, '<name:string>')
pt_command:register("join", join, '<name:string>')


function invite(...)
    for _, name in pairs({...}) do
        command.input("/pcmd add " .. name)
        name = name:gsub("^%l", string.upper)
        if unhandled_requests[name] then
            unhandled_requests[name] = nil
        end
    end
end

pt_command:register("i", invite, '{names}')
pt_command:register("invite", invite, '{names}')


function blacklist(section, sub_cmd, ...)
    local names = {...}
    if alias.add[sub_cmd] then
        for _, name in pairs(names) do
            pt_settings.blacklist[section][name] = true
        end
    elseif alias.remove[sub_cmd] then
        for _, name in pairs(names) do
            pt_settings.blacklist[section][name] = nil
        end
    end
    settings.save(pt_settings)
end

pt_command:register("b", blacklist, '<sub_cmd:one_of(add,a,+,remove,rm,r,-)> {names}')
pt_command:register("blacklist", blacklist, '<sub_cmd:one_of(add,a,+,remove,rm,r,-)> {names}')


function whitelist(sub_cmd, ...)
    local names = {...}
    if alias.add[sub_cmd] then
        for _, name in pairs(names) do
            pt_settings.whitelist[name] = true
        end
    elseif alias.remove[sub_cmd] then
        for _, name in pairs(names) do
            pt_settings.whitelist[name] = nil
        end
    end
    settings.save(pt_settings)
end

pt_command:register("w", whitelist, '<sub_cmd:one_of(add,a,+,remove,rm,r,-)> {names}')
pt_command:register("whitelist", whitelist, '<sub_cmd:one_of(add,a,+,remove,rm,r,-)> {names}')


function ui_enable(bool)
    pt_settings.ui.enabled = bool
    settings.save(pt_settings)
end

pt_command:register("ui_enable", ui_enable, '<enabled:boolean>')


function auto_accept_enable(bool)
    pt_settings.auto.accept_invites = bool
    settings.save(pt_settings)
end

pt_command:register("auto_accept", auto_accept_enable, '<enabled:boolean>')


function auto_decline_enable(bool)
    pt_settings.auto.decline_invites = bool
    settings.save(pt_settings)
end

pt_command:register("auto_decline", auto_decline_enable, '<enabled:boolean>')

-- Packet Event Handlers
-- Recieve Invite & Recieve Request
packets.incoming[0x0DC]:register(function(p)
    if pt_settings.auto.accept_invites and pt_settings.whitelist[p.player_name] then
        coroutine.schedule(function()
            local clock = os.clock()
            repeat
                if (os.clock() - clock) > 90 then
                    return
                end
                coroutine.sleep_frame()
            until(#treasure == 0)
            command.input("/join")
        end)
    elseif pt_settings.auto.decline_invites and pt_settings.blacklist[p.player_name] then
        command.input("/decline")
    else
        invite_dialog = {
            state = invite_dialog_state,
            add_to_whitelist = false,
            name = p.player_name,
        }
        unhandeled_invite = true
    end
end)

packets.incoming[0x11D]:register(function(p)
    if pt_settings.auto.accept_invites and pt_settings.whitelist[p.player_name] then
        command.input("/pcmd add "..p.player_name)
    elseif pt_settings.blacklist[p.player_name] ~= true then
        unhandled_requests[p.player_name] = {
            state = {
                title = 'Party Request',
                style = 'normal',
                x = pt_settings.ui.x,
                y = pt_settings.ui.y,
                width = 179,
                height = 96,
                resizable = false,
                moveable = true,
                closable = true,
            },
            add_to_whitelist = false,
        }
    end
end)

packets.outgoing[0x074]:register(function(p)
    unhandeled_invite = false
end)

-- User Interface for Accepting|Declining
-- Pop-Up menus Invites & Requests.
ui.display(function()
    if pt_settings.ui.enabled then
        if unhandeled_invite then
            invite_dialog.state, invite_dialog.closed = ui.window('invite_dialog', invite_dialog.state, function()

                ui.location(11, 5)
                ui.text(invite_dialog.name .. ' has invited\nyou to join their party')
                
                ui.location(11, 50)
                if pt_settings.auto.accept then
                    if ui.check('add_to_whitelist', 'Remember ' .. invite_dialog.name, invite_dialog.add_to_whitelist) then
                        invite_dialog.add_to_whitelist = not invite_dialog.add_to_whitelist
                    end
                else
                    if ui.check('add_to_whitelist', 'Turn auto accept on ', pt_settings.auto.accept) then
                        pt_settings.auto.accept = true
                    end
                end

                ui.location(11,72)
                if ui.button('accept', 'Accept') then
                    command.input("/join")
                    unhandeled_invite = false
                    if invite_dialog.add_to_whitelist then
                        pt_settings.whitelist[invite_dialog.name] = true
                        settings.save(pt_settings)
                    end
                end
                ui.location(93,72)
                if ui.button('decline', 'Decline') then
                    command.input("/decline")
                    unhandeled_invite = false
                end
                    
            end)
            if invite_dialog.closed then
                invite_dialog.closed = nil
                unhandeled_invite = false
            end
            if invite_dialog.state.x ~= pt_settings.ui.x or invite_dialog.state.y ~= pt_settings.ui.y then
                pt_settings.ui.x = invite_dialog.state.x
                pt_settings.ui.y = invite_dialog.state.y
                invite_dialog_state.x = invite_dialog.state.x
                invite_dialog_state.y = invite_dialog.state.y
                settings.save(pt_settings)
            end
        end

        local closed_dialogs = {}
        for id, request_dialog in pairs(unhandled_requests) do 
            request_dialog.state, request_dialog.close = ui.window(id, request_dialog.state, function()
                ui.location(11, 5)
                ui.text(id .. ' has requested\nto join your party')
                
                ui.location(11, 50)
                if pt_settings.auto.accept then
                    if ui.check('add_to_whitelist', 'Remember ' .. id, request_dialog.add_to_whitelist) then
                        request_dialog.add_to_whitelist = not request_dialog.add_to_whitelist
                    end
                else
                    if ui.check('add_to_whitelist', 'Turn auto accept on ', pt_settings.auto.accept) then
                        pt_settings.auto.accept = true
                    end
                end

                ui.location(11,72)
                if ui.button('invite', 'Invite') then
                    command.input("/pcmd add " .. id)
                    closed_dialogs[#closed_dialogs + 1] = id
                    if request_dialog.add_to_whitelist then
                        print(id)
                        pt_settings.whitelist[id] = true
                        settings.save(pt_settings)
                    end
                end
                ui.location(93,72)
                if ui.button('ignore', 'Ignore') then
                    closed_dialogs[#closed_dialogs + 1] = id
                end
            end)
            if request_dialog.close then
                closed_dialogs[#closed_dialogs + 1] = id
            end
            if request_dialog.state.x ~= pt_settings.ui.x or request_dialog.state.y ~= pt_settings.ui.y then
                pt_settings.ui.x = request_dialog.state.x
                pt_settings.ui.y = request_dialog.state.y
                invite_dialog_state.x = request_dialog.state.x
                invite_dialog_state.y = request_dialog.state.y
                settings.save(pt_settings)
            end
        end

        for _, id in pairs(closed_dialogs) do
            unhandled_requests[id] = nil
        end
    end
end)

--[[
Copyright © 2018, Windower Dev Team
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of the Windower Dev Team nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE WINDOWER DEV TEAM BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]
