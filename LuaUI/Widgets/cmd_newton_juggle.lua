function widget:GetInfo()
  return {
    name      = "Newton Juggle v0.1",
    desc      = "All hail the mighty Juggler!",
    author    = "Klon",
    date      = "16 Jul 2015",
    license   = "GNU GPL, v2 or later",
    layer     = 0,
    enabled   = true  --  loaded by default?
  }
end

--------------------------------------------------------------------------------
-- Epic Menu Options
--------------------------------------------------------------------------------

options_path = 'Game/Newton Juggle'
options_order = {'settingslabel', 'checkrate', 'short_range_priority_modifier', 'long_range_priority_modifier', 'retarget_treshold', 'prioritizeaircraft', 'addnewtons', 'aircraftlabel'}
options = {
	settingslabel = {name = "settingslabel", type = 'label', value = "General Settings", path = options_path},
	checkrate = {
		name = "Update frequency",
        type = 'number',
        value = 1,
        min = 1,
        max = 15,
        step = 1,
        path = "Game/Newton Juggle/General Settings",
	},
	short_range_priority_modifier = {
		name = "Short distance priority modifier",
        type = 'number',
        value = 2,
        min = 1,
        max = 10,
        step = 0.1,
        path = "Game/Newton Juggle/General Settings",
	},
	long_range_priority_modifier = {
		name = "Long distance priority modifier",
        type = 'number',
        value = 3,
        min = 1,
        max = 10,
        step = 0.1,
        path = "Game/Newton Juggle/General Settings",
	},
	retarget_treshold = {
		name = "Retarget treshold priority factor",
        type = 'number',
        value = 3,
        min = 1,
        max = 10,
        step = 0.1,
        path = "Game/Newton Juggle/General Settings",
	},
	prioritizeaircraft = {
		name = 'Prioritize aircraft',
		desc = 'Newtons will always prefer aircraft over other targets if enabled.',
		type = 'bool',
		value = true,
		path = "Game/Newton Juggle/General Settings",	
	},
	addnewtons = {
		name = 'Enable on all Newtons',
		desc = 'Check to activate aircraft juggling on all newly built Newtons.',
		type = 'bool',
		value = true,
		path = "Game/Newton Juggle/General Settings",
	},	
	aircraftlabel = {name = "aircraftlabel", type = 'label', value = "Aircraft Settings", path = options_path},
}

local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitVelocity = Spring.GetUnitVelocity
local spGetUnitDefID = Spring.GetUnitDefID
local spGetSelectedUnits = Spring.GetSelectedUnits
local spGiveOrderToUnit = Spring.GiveOrderToUnit
local spGiveOrderToUnitArray = Spring.GiveOrderToUnitArray
local spValidUnitID = Spring.ValidUnitID
local spUnitActive = Spring.GetUnitIsActive
local spTryTarget = Spring.GetUnitWeaponTryTarget

local myTeam = Spring.GetMyTeamID()

local newtonUnitDefID = UnitDefNames["corgrav"].id
local newtonUnitDefRange = UnitDefNames["corgrav"].maxWeaponRange -- 460 / 440
local sumoUnitDefID = UnitDefNames["corsumo"].id
local sumoUnitDefRange = UnitDefNames["corsumo"].maxWeaponRange -- 460 / 440

local cullFromListIDs = {
	[UnitDefNames["bomberassault"].id] = true,
	[UnitDefNames["bomberlaser"].id] = true,
	[UnitDefNames["bomberstrike"].id]= true,
	[UnitDefNames["chicken_blimpy"].id] = true,
	[UnitDefNames["chicken_pigeon"].id] = true,
	[UnitDefNames["chicken_roc"].id] = true,
	[UnitDefNames["chickenf"].id] = true,
	[UnitDefNames["chickenflyerqueen"].id] = true,
	[UnitDefNames["cobtransport"].id] = true,
	[UnitDefNames["fakeunit_aatarget"].id] = true,
	[UnitDefNames["fakeunit_los"].id] = true,
	[UnitDefNames["nebula"].id] = true,
	[UnitDefNames["fighterdrone"].id] = true,
	[UnitDefNames["corshad"].id] = true,
}

local customRangeCategory = {
	[UnitDefNames["attackdrone"].id] = newtonUnitDefRange,
	[UnitDefNames["battledrone"].id] = newtonUnitDefRange,
	[UnitDefNames["carrydrone"].id] = newtonUnitDefRange,
	[UnitDefNames["armstiletto_laser"].id] = newtonUnitDefRange - 100,
	[UnitDefNames["bladew"].id] = newtonUnitDefRange - 100,
	[UnitDefNames["blastwing"].id] = newtonUnitDefRange,
	[UnitDefNames["corvalk"].id] = newtonUnitDefRange - 100,	
	[UnitDefNames["armbrawl"].id] = 0,
	[UnitDefNames["corcrw"].id] = newtonUnitDefRange - 100,
	[UnitDefNames["corvamp"].id] = 0,
	[UnitDefNames["fighter"].id] = 0,
	[UnitDefNames["gunshipaa"].id] = 0,
}

local customPriorityCategory = {
	[UnitDefNames["corvamp"].id] = 151,
	[UnitDefNames["corawac"].id] = 1998,
	[UnitDefNames["bladew"].id] = 298,
	[UnitDefNames["blastwing"].id] = 301,
	[UnitDefNames["corvalk"].id] = 299,
	[UnitDefNames["corbtrans"].id] = 10000,
	[UnitDefNames["armcsa"].id] = 1999,
}

local newtons = {}	--	[unitID] = {
					--		userMode := bool,
					--		currentTarget := unitID
					--		targetsInRangeList[unitID] = {
					--			ud := unitDefID,
					--			priority := number
					--			priorityBase := options[unitDef.name .. "_priority"],
					--			distance := number,
					--			isCurrent := bool
					--		},
					--	}
local targetList = {} -- unitID, unitDefID
local aircraftDefs = {} -- unitDefID, unitDef 

local CMD_NEWTON_JUGGLE = 10293

local cmdNewtonJuggle = {
	id      = CMD_NEWTON_JUGGLE,
	type    = CMDTYPE.ICON_UNIT_OR_AREA,
	tooltip = 'Juggle.',
	cursor  = 'Attack',
	action  = 'newtonjuggle',
	params  = { }, 
	texture = 'LuaUI/Images/commands/Bold/dgun.png',
	--pos     = {CMD_ONOFF,CMD_REPEAT,CMD_MOVE_STATE,CMD_FIRE_STATE, CMD_RETREAT},  
}

-------------------------------------------------------------------
-------------------------------------------------------------------
--- INIT
-------------------------------------------------------------------

local function GetAircraftData()
	for i = 1, #UnitDefs do
		local ud = UnitDefs[i]
		if ud.isAirUnit then --and not cullFromListIDs[i] then
			aircraftDefs[i] = ud
			local optRange = customRangeCategory[i] or (ud.maxWeaponRange < newtonUnitDefRange and ud.maxWeaponRange or newtonUnitDefRange)
			local basePrio = customPriorityCategory[i] or ud.metalCost
			
			path = "Game/Newton Juggle/Aircraft Settings"
			options[ud.name .. "_label"] = {
				name = "name",
				type = 'label',
				value = ud.humanName,
				path = path,
			}
			options_order[#options_order+1] = ud.name .. "_label"
			
			options[ud.name .. "_priority"] = {
				name = "Priority",
				--desc = "Current: "..options[ud.name .. "_priority"].value,
				type = 'number',
				value = basePrio,
				min = 0,
				max = 10000,
				step = 5,
				path = path,
			}
			options_order[#options_order+1] = ud.name .. "_priority"
			
			options[ud.name .. "_range"] = {
				name = "Desired Range",
				--desc = "Current: "..options[ud.name .. "_priority"].value,
				type = 'number',
				value = optRange,
				min = 0, 
				max = newtonUnitDefRange,
				step = 1,
				path = path,
			}
			options_order[#options_order+1] = ud.name .. "_range"
		end
	end
end

function widget:Initialize()
	GetAircraftData()
end


-------------------------------------------------------------------
-------------------------------------------------------------------
--- CALLINS
-------------------------------------------------------------------

function widget:UnitFinished(unitID, unitDefID, unitTeam)
	if unitTeam == myTeam then
		if unitDefID == newtonUnitDefID then
			newtons[unitID] = {userMode = spUnitActive(unitID), currentTarget = nil, targetsInRangeList = {}}			
		end
	end
end

function widget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
	if newTeam == myTeam then
		if newtons[unitID] then -- should not happen
			Spring.Echo("newton was given but already in the list")
		else
			newtons[unitID] = {userMode = spUnitActive(unitID), currentTarget = nil, targetsInRangeList = {}}			
		end
	elseif newtons[unitID] then newtons[unitID] = nil
	end	
end

function widget:UnitTaken(unitID, unitDefID, oldTeam, newTeam)
		if newTeam == myTeam then
		if newtons[unitID] then -- should not happen
			Spring.Echo("newton was taken but already in the list")
		else
			newtons[unitID] = {userMode = spUnitActive(unitID), currentTarget = nil, targetsInRangeList = {}}			
		end
	elseif newtons[unitID] then newtons[unitID] = nil
	end	
end

function widget:UnitEnteredLos(unitID)
	local ud = Spring.GetUnitDefID(unitID)
	if aircraftDefs[ud] then		
		targetList[unitID] = ud		
	end	
end

function widget:UnitLeftLos(unitID)
	if targetList[unitID] then targetList[unitID] = nil end
end

function widget:UnitDestroyed(unitID)
	if targetList[unitID] then targetList[unitID] = nil end
	if newtons[unitID] then newtons[unitID] = nil end
end

function widget:CommandNotify(id, params, cmdOptions)    
	if id == CMD.ONOFF and not cmdOptions.internal then        
		local units = Spring.GetSelectedUnits()
        for i = 1, #units do
            local unitID = units[i]
            if newtons[unitID] then
				newtons[unitID].userMode = params[1] == 1 and true
				if newtons[unitID].currentTarget then return true end
			end
		end
	end
	return false
end

-------------------------------------------------------------------
-------------------------------------------------------------------
--- UPDATE
-------------------------------------------------------------------

local function GetDistance (source, target)	
	local sx,_,sz = spGetUnitPosition(source)
	local tx,_,tz = spGetUnitPosition(target)
	local dx = sx - tx
	local dz = sz - tz
	return math.sqrt(dx*dx + dz*dz)
end


local function GetPriorityModifier(target)
	local optRange = options[aircraftDefs[target.ud].name..'_range'].value
	local rangeMod =  target.distance - optRange
		
	if rangeMod < 0 then
		return (rangeMod/optRange) * options.short_range_priority_modifier.value
	else
		return (rangeMod/((newtonUnitDefRange - optRange) or 0)) * options.long_range_priority_modifier.value
	end
end


function widget:GameFrame(n)
	
	if (n%options.checkrate.value ~= 0) then return end	
	if newtons then
		for nid, nParams in pairs(newtons) do		
			local targetsInRangeList = nParams.targetsInRangeList
			local bestTarget
			--local currentTarget = nid.currentTarget
			
			-- check if any known planes entered a newtons range
			for tid, tDefID in pairs(targetList) do
				if spValidUnitID(tid) then
					local dist = GetDistance(nid,tid)
					if dist<=newtonUnitDefRange then
						if targetsInRangeList[tid] == nil then							
							targetsInRangeList[tid] = {}
							targetsInRangeList[tid].ud  = tDefID
							targetsInRangeList[tid].priorityBase = options[aircraftDefs[tDefID].name.."_priority"].value
							targetsInRangeList[tid].priority = targetsInRangeList[tid].priorityBase
						end
						targetsInRangeList[tid].distance = dist
					else 
						targetsInRangeList[tid] = nil
						if nParams.currentTarget == tid then nParams.currentTarget = nil end
					end
				end
			end
			
			-- check for best target from targets in range
			for tid, params in pairs(targetsInRangeList) do
				if spValidUnitID(tid) then					
					local prio = GetPriorityModifier(params)
					params.priority = params.priorityBase + math.abs(prio)					
					params.isPush = prio < 0
					
					if bestTarget == nil or params.priority > targetsInRangeList[bestTarget].priority then
						if spTryTarget(nid, 1, tid) then
							bestTarget = tid
						elseif currentTarget == tid then currentTarget = nil
						end
					end					
				else 
					targetsInRangeList[tid] = nil
					if nParams.currentTarget == tid then nParams.currentTarget = nil end
				end				
			end
			
			local newtonIsPush = spUnitActive(nid)
			if bestTarget then							
				
				local targetNeedsPush
				--Spring.Echo(targetsInRangeList[bestTarget].isPush and "true" or "false")
				local currentTarget = nParams.currentTarget				
				
				if currentTarget and (currentTarget == bestTarget or 
					(targetsInRangeList[bestTarget].priority < targetsInRangeList[currentTarget].priority * options.retarget_treshold.value)) then
					targetNeedsPush = targetsInRangeList[currentTarget].isPush
					if targetNeedsPush ~= newtonIsPush then
						spGiveOrderToUnit(nid, CMD.ONOFF, {targetNeedsPush and 1 or 0}, CMD.OPT_INTERNAL)
					end
				else
					nParams.currentTarget = bestTarget
					targetNeedsPush = targetsInRangeList[bestTarget].isPush
					if targetNeedsPush ~= newtonIsPush then
						spGiveOrderToUnit(nid, CMD.ONOFF, {targetNeedsPush and 1 or 0}, CMD.OPT_INTERNAL)
					end
					spGiveOrderToUnit(nid, CMD.ATTACK, {bestTarget}, CMD.OPT_INTERNAL)
				end
				
			else 
				nParams.currentTarget = nil -- found absolutely no target so our current one must be gone too
				if nParams.userMode ~= newtonIsPush then 
					spGiveOrderToUnit(nid, CMD.ONOFF, {nParams.userMode and 1 or 0}, CMD.OPT_INTERNAL)
				end
			end	
		end	
	end	
end




--[[
local aircraftDefData = { --unitDefID, {minRange, movementSafetyTreshold, priority}
	[UnitDefNames["corvamp"].id] = {0, UnitDefNames["corvamp"].maxVelocity * checkRate, 1}, 
	[UnitDefNames["fighter"].id] = {0, UnitDefNames["fighter"].maxVelocity * checkRate, 1},								-- swift
	[UnitDefNames["corhurc2"].id] = {0, UnitDefNames["corhurc2"].maxVelocity * checkRate, 2},							-- phoenix
	[UnitDefNames["corshad"].id] = {10, UnitDefNames["corshad"].maxVelocity * checkRate, 3},							-- raven
	[UnitDefNames["armstiletto_laser"].id] = {newtonUnitDefRange, 30, 3},
	[UnitDefNames["corawac"].id] = {0, 40, 10}, 							-- vulture
	[UnitDefNames["armcybr"].id] = {newtonUnitDefRange, 30, 4},				-- wyvern
	
	[UnitDefNames["blackdawn"].id] = {300, 10, 1},
	[UnitDefNames["armkam"].id] = {240, 20, 1},								-- banshee
	[UnitDefNames["gunshipsupport"].id] = {360, 10, 1}, 					-- rapier
	[UnitDefNames["armbrawl"].id] = {650, 10, 1}, 
	[UnitDefNames["bladew"].id] = {newtonUnitDefRange, 40, 1}, 				-- gnat
	[UnitDefNames["blastwing"].id] = {newtonUnitDefRange, 30, 1}, 
	[UnitDefNames["cobtransport"].id] = {newtonUnitDefRange, 40, 9}, 		-- valk
	[UnitDefNames["corbtrans"].id] = {100, 30, 10}, 						-- vindi
	[UnitDefNames["corcrw"].id] = {450, 10, 1}, 							-- krow
	[UnitDefNames["gunshipaa"].id] = {0, 20, 1}, 							-- trident
	
	[UnitDefNames["armca2"].id] = {0, 20, 1},								-- con
	[UnitDefNames["armcsa"].id] = {0, 20, 1},								-- athena
	
	[UnitDefNames["attackdrone"].id] = {newtonUnitDefRange, 20, 1},
	[UnitDefNames["battledrone"].id] = {newtonUnitDefRange, 20, 1},
	[UnitDefNames["carrydrone"].id] = {newtonUnitDefRange, 20, 1},
	
	--[UnitDefNames["nebula"].id] = {0, 20, 1}, 		-- flying carrier	
	--[UnitDefNames["fighterdrone"].id] = {0, 20, 1}, 	-- some drone
	--[UnitDefNames["bomberstrike"].id] = {0, 20, 1}, 	-- mission drone?
	--[UnitDefNames["bomberassault"].id] = {0, 20, 1},	-- mission drone?
}
--]]


			--[[
			options[ud.name .. "_pushpull"] = {
				name = "Newton control",
				type = 'radioButton',				
				items = {
					{ key = 'range', name = 'Use desired range'},
					{ key = 'push', name = 'Always push'},
					{ key = 'pull', name = 'Always pull'},
				},
				path = path,
				value = 'range',				
			}
			options_order[#options_order+1] = ud.name .. "_pushpull"
			
			options[ud.name .. "_isPush"] = {
				name = "Push",
				desc = "push if enabled, pull if disabled.",
				type = 'bool', 
				value = true,
				path = path,
			}
			options_order[#options_order+1] = ud.name .. "_isPush"
			--]]
			
