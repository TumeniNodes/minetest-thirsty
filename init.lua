--[[

Thirsty mod [thirsty]
==========================

A mod that adds a "thirst" mechanic, similar to hunger.

Copyright (C) 2015 Ben Deutsch <ben@bendeutsch.de>

License
-------

This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Lesser General Public
License as published by the Free Software Foundation; either
version 2.1 of the License, or (at your option) any later version.

This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public
License along with this library; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301
USA

Terminology: "Thirst" vs. "hydration"
-------------------------------------

"Thirst" is the absence of "hydration" (a term suggested by
everamzah on the Minetest forums, thanks!). The overall mechanic
is still called "thirst", but the visible bar is that of
"hydration", filled with "hydro points".

]]

-- the main module variable
thirsty = {

    -- Configuration variables
    tick_time = 0.5,
    thirst_per_second = 1.0 / 20.0,
    damage_per_second = 1.0 / 10.0, -- when out of hydration
    stand_still_for_drink = 1.0,
    stand_still_for_afk = 120.0, -- 2 Minutes

    -- which nodes can we drink from (given containers)
    node_drinkable = {
        ['default:water_source'] = true,
        ['default:water_flowing'] = true,
        ['thirsty:drinking_fountain'] = true,
    },

    regen_from_node = {
        -- value: hydration regen per second
        ['default:water_source'] = 0.5,
        ['default:water_flowing'] = 0.5,
    },

    drink_from_container = {
        -- value: max hydration when drinking with item
        ['thirsty:wooden_bowl'] = 25,
        ['thirsty:steel_canteen'] = 25,
        ['thirsty:bronze_canteen'] = 25,
    },

    container_capacity = {
        -- value: hydro capacity in item
        ['thirsty:steel_canteen'] = 40,
        ['thirsty:bronze_canteen'] = 60,
    },

    drink_from_node = {
        -- value: max hydration when drinking from node
        ['thirsty:drinking_fountain'] = 30,
    },

    -- the players' values
    players = {
        --[[
        name = {
            hydro = 20,
            last_pos = '-10:3',
            time_in_pos = 0.0,
            pending_dmg = 0.0,
        }
        ]]
    },

    -- water fountains
    fountains = {
        --[[
        x:y:z = {
            pos = { x=x, y=y, z=z },
            level = 4,
            -- something about times
        }
        ]]
    },

    stash_filename = 'thirsty.dat',

    -- general settings
    time_next_tick = 0.0,
}

thirsty.time_next_tick = thirsty.tick_time

--[[

HUD definitions

Optionally from one of the supported mods

]]

function thirsty.hud_clamp(value)
    if value < 0 then
        return 0
    elseif value > 20 then
        return 20
    else
        return math.ceil(value)
    end
end

if minetest.get_modpath("hudbars") then
    hb.register_hudbar('thirst', 0xffffff, "Hydration", {
        bar = 'thirsty_hudbars_bar.png',
        icon = 'thirsty_cup_100_16.png'
    }, 20, 20, false)
    function thirsty.hud_init(player)
        local name = player:get_player_name()
        hb.init_hudbar(player, 'thirst',
            thirsty.hud_clamp(thirsty.players[name].hydro),
        20, false)
    end
    function thirsty.hud_update(player, value)
        local name = player:get_player_name()
        hb.change_hudbar(player, 'thirst', thirsty.hud_clamp(value), 20)
    end
elseif minetest.get_modpath("hud") then
    -- default positions follow [hud] defaults
    local position = HUD_THIRST_POS or { x=0.5, y=1 }
    local offset   = HUD_THIRST_OFFSET or { x=15, y=-133} -- above AIR
    hud.register('thirst', {
        hud_elem_type = "statbar",
        position = position,
        text = "thirsty_cup_100_24.png",
        background = "thirsty_cup_0_24.png",
        number = 20,
        max = 20,
        size = HUD_SD_SIZE, -- by default { x=24, y=24 },
        offset = offset,
    })
    function thirsty.hud_init(player)
        -- automatic by [hud]
    end
    function thirsty.hud_update(player, value)
        hud.change_item(player, 'thirst', {
            number = thirsty.hud_clamp(value)
        })
    end
else
    -- 'builtin' hud
    function thirsty.hud_init(player)
        -- above breath bar, for now
        local name = player:get_player_name()
        thirsty.players[name].hud_id = player:hud_add({
            hud_elem_type = "statbar",
            position = { x=0.5, y=1 },
            text = "thirsty_cup_100_24.png",
            number = thirsty.hud_clamp(thirsty.players[name].hydro),
            direction = 0,
            size = { x=24, y=24 },
            offset = { x=25, y=-(48+24+16+32)},
        })
    end
    function thirsty.hud_update(player, value)
        local name = player:get_player_name()
        local hud_id = thirsty.players[name].hud_id
        player:hud_change(hud_id, 'number', thirsty.hud_clamp(value))
    end
end


minetest.register_on_joinplayer(function(player)
    local name = player:get_player_name()
    -- default entry for new players
    if not thirsty.players[name] then
        local pos = player:getpos()
        thirsty.players[name] = {
            hydro = 20,
            last_pos = math.floor(pos.x) .. ':' .. math.floor(pos.z),
            time_in_pos = 0.0,
            pending_dmg = 0.0,
        }
    end
    thirsty.hud_init(player)
end)

minetest.register_on_dieplayer(function(player)
    local name = player:get_player_name()
    -- fill after death
    thirsty.players[name].hydro = 20;
end)

--[[

Main Loop (Tier 0)

]]


minetest.register_globalstep(function(dtime)
    -- get thirsty
    thirsty.time_next_tick = thirsty.time_next_tick - dtime
    while thirsty.time_next_tick < 0.0 do
        -- time for thirst
        thirsty.time_next_tick = thirsty.time_next_tick + thirsty.tick_time
        for _,player in ipairs(minetest.get_connected_players()) do

            if player:get_hp() <= 0 then
                -- dead players don't get thirsty, or full for that matter :-P
                break
            end

            local name = player:get_player_name()
            local pos  = player:getpos()
            local pl = thirsty.players[name]

            -- how long have we been standing "here"?
            -- (the node coordinates in X and Z should be enough)
            local pos_hash = math.floor(pos.x) .. ':' .. math.floor(pos.z)
            if pl.last_pos == pos_hash then
                pl.time_in_pos = pl.time_in_pos + thirsty.tick_time
            else
                -- you moved!
                pl.last_pos = pos_hash
                pl.time_in_pos = 0.0
            end
            local pl_standing = pl.time_in_pos > thirsty.stand_still_for_drink
            local pl_afk      = pl.time_in_pos > thirsty.stand_still_for_afk
            --print("Standing: " .. (pl_standing and 'true' or 'false' ) .. ", AFK: " .. (pl_afk and 'true' or 'false'))

            pos.y = pos.y + 0.1
            local node = minetest.get_node(pos)
            local drink_per_second = thirsty.regen_from_node[node.name] or 0

            -- fountaining (uses pos, slight changes ok)
            for k, fountain in pairs(thirsty.fountains) do
                local dx = fountain.pos.x - pos.x
                local dy = fountain.pos.y - pos.y
                local dz = fountain.pos.z - pos.z
                local dist2 = dx * dx + dy * dy + dz * dz
                local fdist = fountain.level * 5 -- max 100 nodes radius
                --print (string.format("Distance from %s (%d): %f out of %f", k, fountain.level, math.sqrt(dist2), fdist ))
                if dist2 < fdist * fdist then
                    -- in range, drink as if standing (still) in water
                    drink_per_second = math.max(thirsty.regen_from_node['default:water_source'] or 0, drink_per_second)
                    pl_standing = true
                    break -- no need to check the other fountains
                end
            end

            if drink_per_second > 0 and pl_standing then
                pl.hydro = pl.hydro + drink_per_second * thirsty.tick_time
                -- Drinking from the ground won't give you more than max
                if pl.hydro > 20 then pl.hydro = 20 end
                --print("Raising hydration by "..(drink_per_second*thirsty.tick_time).." to "..pl.hydro)
            else
                if not pl_afk then
                    -- only get thirsty if not AFK
                    pl.hydro = pl.hydro - thirsty.thirst_per_second * thirsty.tick_time
                    if pl.hydro < 0 then pl.hydro = 0 end
                    --print("Lowering hydration by "..(thirsty.thirst_per_second*thirsty.tick_time).." to "..pl.hydro)
                end
            end


            -- should we only update the hud on an actual change?
            thirsty.hud_update(player, pl.hydro)

            -- damage, if enabled
            if minetest.setting_getbool("enable_damage") then
                -- maybe not the best way to do this, but it does mean
                -- we can do anything with one tick loop
                if pl.hydro <= 0.0 and not pl_afk then
                    pl.pending_dmg = pl.pending_dmg + thirsty.damage_per_second * thirsty.tick_time
                    --print("Pending damage at " .. pl.pending_dmg)
                    if pl.pending_dmg > 1.0 then
                        local dmg = math.floor(pl.pending_dmg)
                        pl.pending_dmg = pl.pending_dmg - dmg
                        player:set_hp( player:get_hp() - dmg )
                    end
                else
                    -- forget any pending damage when not thirsty
                    pl.pending_dmg = 0.0
                end
            end
        end
    end
end)

--[[

Stash: persist the hydration values in a file in the world directory.

If this is missing or corrupted, then no worries: nobody's thirsty ;-)

]]

function thirsty.read_stash()
    local filename = minetest.get_worldpath() .. "/" .. thirsty.stash_filename
    local file, err = io.open(filename, "r")
    if not file then
        -- no problem, it's just not there
        -- TODO: or parse err?
        return
    end
    thirsty.players = {}
    for line in file:lines() do
        if string.match(line, '^%-%-') then
            -- comment, ignore
        elseif string.match(line, '^P [%d.]+ [%d.]+ .+') then
            -- player line
            -- is matching again really the best solution?
            local hydro, dmg, name = string.match(line, '^P ([%d.]+) ([%d.]+) (.+)')
            thirsty.players[name] = {
                hydro = tonumber(hydro),
                last_pos = '0:0', -- not true, but no matter
                time_in_pos = 0.0,
                pending_dmg = tonumber(dmg),
            }
        end
    end
    file:close()
end

function thirsty.write_stash()
    local filename = minetest.get_worldpath() .. "/" .. thirsty.stash_filename
    local file, err = io.open(filename, "w")
    if not file then
        minetest.log("error", "Thirsty: could not write " .. thirsty.stash_filename .. ": " ..err)
        return
    end
    file:write('-- Stash file for Minetest mod [thirsty] --\n')
    -- write players:
    -- P <hydro> <pending_dmg> <name>
    file:write('-- Player format: "P <hydro> <pending damage> <name>"\n')
    for name, data in pairs(thirsty.players) do
        file:write("P " .. data.hydro .. " " .. data.pending_dmg .. " " .. name .. "\n")
    end
    file:close()
end

--[[

General handler

Most tools, nodes and craftitems use the same code, so here it is:

]]

function thirsty.drink_handler(player, itemstack, node)
    local pl = thirsty.players[player:get_player_name()]
    local old_hydro = pl.hydro

    -- selectors, always true, to make the following code easier
    local item_name = itemstack and itemstack:get_name() or ':'
    local node_name = node      and node.name            or ':'

    if thirsty.node_drinkable[node_name] then
        -- we found something to drink!
        local cont_level = thirsty.drink_from_container[item_name] or 0
        local node_level = thirsty.drink_from_node[node_name] or 0
        -- drink until level
        local level = math.max(cont_level, node_level)
        --print("Drinking to level " .. level)
        if pl.hydro < level then
            pl.hydro = level
        end

        -- fill container, if applicable
        if thirsty.container_capacity[item_name] then
            --print("Filling a " .. item_name .. " to " .. thirsty.container_capacity[item_name])
            itemstack:set_wear(1) -- "looks full"
        end

    elseif thirsty.container_capacity[item_name] then
        -- drinking from a container
        if itemstack:get_wear() ~= 0 then
            local capacity = thirsty.container_capacity[item_name]
            local hydro_missing = 20 - pl.hydro;
            if hydro_missing > 0 then
                local wear_missing = hydro_missing / capacity * 65535.0;
                local wear         = itemstack:get_wear()
                local new_wear     = math.ceil(math.max(wear + wear_missing, 1))
                if (new_wear > 65534) then
                    wear_missing = 65534 - wear
                    new_wear = 65534
                end
                itemstack:set_wear(new_wear)
                if wear_missing > 0 then -- rounding glitches?
                    pl.hydro = pl.hydro + (wear_missing * capacity / 65535.0)
                end
            end
        end
    end

    -- update HUD if value changed
    if pl.hydro ~= old_hydro then
        thirsty.hud_update(player, pl.hydro)
    end
end

--[[

Adapters for drink_handler to on_use and on_rightclick slots.
These close over the next handler to call in a chain, if desired.

]]

function thirsty.on_use( old_on_use )
    return function(itemstack, player, pointed_thing)
        local node = nil
        if pointed_thing and pointed_thing.type == 'node' then
            node = minetest.get_node(pointed_thing.under)
        end

        thirsty.drink_handler(player, itemstack, node)

        -- call original on_use, if provided
        if old_on_use ~= nil then
            return old_on_use(itemstack, player, pointed_thing)
        else
            return itemstack
        end
    end
end

function thirsty.on_rightclick( old_on_rightclick )
    return function(pos, node, player, itemstack, pointed_thing)

        thirsty.drink_handler(player, itemstack, node)

        -- call original on_rightclick, if provided
        if old_on_rightclick ~= nil then
            return old_on_rightclick(pos, node, player, itemstack, pointed_thing)
        else
            return itemstack
        end
    end
end


--[[

Drinking containers (Tier 1)

Defines a simple wooden bowl which can be used on water to fill
your hydration.

Optionally also augments the nodes from vessels to enable drinking
on use.

]]

function thirsty.augment_node_for_drinking( nodename, level )
    local new_definition = {}
    -- we need to be able to point at the water
    new_definition.liquids_pointable = true
    -- call closure generator with original on_use handler
    new_definition.on_use = thirsty.on_use(
        minetest.registered_nodes[nodename].on_use
    )
    -- overwrite the node definition with almost the original
    minetest.override_item(nodename, new_definition)

    -- add configuration settings
    thirsty.drink_from_container[nodename] = level
end

if (minetest.get_modpath("vessels")) then
    -- add "drinking" to vessels
    thirsty.augment_node_for_drinking('vessels:drinking_glass', 22)
    thirsty.augment_node_for_drinking('vessels:glass_bottle', 24)
    thirsty.augment_node_for_drinking('vessels:steel_bottle', 26)
end

-- our own simple wooden bowl
minetest.register_craftitem('thirsty:wooden_bowl', {
    description = "Wooden bowl",
    inventory_image = "thirsty_bowl_16.png",
    liquids_pointable = true,
    on_use = thirsty.on_use(nil),
})

minetest.register_craft({
    output = "thirsty:wooden_bowl",
    recipe = {
        {"group:wood", "", "group:wood"},
        {"", "group:wood", ""}
    }
})

--[[

Hydro containers (Tier 2)

Defines canteens (currently two types, with different capacities),
tools which store hydro. They use wear to show their content
level in their durability bar; they do not disappear when used up.

Wear corresponds to hydro level as follows:
- a wear of 0     shows no durability bar       -> empty (initial state)
- a wear of 1     shows a full durability bar   -> full
- a wear of 65535 shows an empty durability bar -> empty

]]

minetest.register_tool('thirsty:steel_canteen', {
    description = 'Steel canteen',
    inventory_image = "thirsty_steel_canteen_16.png",
    liquids_pointable = true,
    stack_max = 1,
    on_use = thirsty.on_use(nil),
})

minetest.register_tool('thirsty:bronze_canteen', {
    description = 'Bronze canteen',
    inventory_image = "thirsty_bronze_canteen_16.png",
    liquids_pointable = true,
    stack_max = 1,
    on_use = thirsty.on_use(nil),
})

minetest.register_craft({
    output = "thirsty:steel_canteen",
    recipe = {
        { "group:wood", ""},
        { "default:steel_ingot", "default:steel_ingot"},
        { "default:steel_ingot", "default:steel_ingot"}
    }
})
minetest.register_craft({
    output = "thirsty:bronze_canteen",
    recipe = {
        { "group:wood", ""},
        { "default:bronze_ingot", "default:bronze_ingot"},
        { "default:bronze_ingot", "default:bronze_ingot"}
    }
})

--[[

Tier 3

]]

minetest.register_node('thirsty:drinking_fountain', {
    description = 'Drinking fountain',
    drawtype = 'nodebox',
    tiles = {
        -- top, bottom, right, left, front, back
        'thirsty_drinkfount_top.png',
        'thirsty_drinkfount_bottom.png',
        'thirsty_drinkfount_side.png',
        'thirsty_drinkfount_side.png',
        'thirsty_drinkfount_side.png',
        'thirsty_drinkfount_side.png',
    },
    paramtype = 'light',
	groups = { cracky = 2 },
    node_box = {
        type = "fixed",
        fixed = {
            { -3/16, -8/16, -3/16, 3/16, 3/16, 3/16 },
            { -8/16, 3/16, -8/16, 8/16, 6/16, 8/16 },
            { -8/16, 6/16, -8/16, 8/16, 8/16, -6/16 },
            { -8/16, 6/16, 6/16, 8/16, 8/16, 8/16 },
            { -8/16, 6/16, -6/16, -6/16, 8/16, 6/16 },
            { 6/16, 6/16, -6/16, 8/16, 8/16, 6/16 },
        },
    },
    selection_box = {
        type = "regular",
    },
    collision_box = {
        type = "regular",
    },
    on_rightclick = thirsty.on_rightclick(nil),
})

minetest.register_craft({
    output = "thirsty:drinking_fountain",
    recipe = {
        { "default:stone", "bucket:bucket_water", "default:stone"},
        { "", "default:stone", ""},
        { "", "default:stone", ""}
    }
})

--[[

Tier 4+: the water fountains, plus extenders

]]

minetest.register_node('thirsty:water_fountain', {
    description = 'Water fountain',
    tiles = {
        -- top, bottom, right, left, front, back
        'thirsty_waterfountain_top.png',
        'thirsty_waterfountain_top.png',
        'thirsty_waterfountain_side.png',
        'thirsty_waterfountain_side.png',
        'thirsty_waterfountain_side.png',
        'thirsty_waterfountain_side.png',
    },
    paramtype = 'light',
    groups = { cracky = 2 },
})

minetest.register_node('thirsty:water_extender', {
    description = 'Water fountain extender',
    tiles = {
        'thirsty_waterextender_top.png',
        'thirsty_waterextender_top.png',
        'thirsty_waterextender_side.png',
        'thirsty_waterextender_side.png',
        'thirsty_waterextender_side.png',
        'thirsty_waterextender_side.png',
    },
    paramtype = 'light',
    groups = { cracky = 2 },
})


minetest.register_abm({
    nodenames = {'thirsty:water_fountain'},
    interval = 2,
    chance = 1,
    action = function(pos, node)
        local fountain_count = 0
        local water_count = 0
        local total_count = 0
        for y = 0, 4 do
            for x = -y, y do
                for z = -y, y do
                    local n = minetest.get_node({
                        x = pos.x + x,
                        y = pos.y - y + 1, -- start one *above* the fountain
                        z = pos.z + z
                    })
                    if n then
                        --print(string.format("%s at %d:%d:%d", n.name, pos.x+x, pos.y-y+1, pos.z+z)) 
                        total_count = total_count + 1
                        if n.name == 'thirsty:water_fountain' or n.name == 'thirsty:water_extender' then
                            fountain_count = fountain_count + 1
                        elseif n.name == 'default:water_source' or n.name == 'default:water_flowing' then
                            water_count = water_count + 1
                        end
                    end
                end
            end
        end
        --print(string.format("All the counts: %d + %d / %d", fountain_count, water_count, total_count))
        local level = math.min(20, math.min(fountain_count, water_count))
        thirsty.fountains[string.format("%d:%d:%d", pos.x, pos.y, pos.z)] = {
            pos = { x=pos.x, y=pos.y, z=pos.z },
            level = level,
        }
    end
})

-- read on startup
thirsty.read_stash()
-- write on shutdown
minetest.register_on_shutdown(thirsty.write_stash)


