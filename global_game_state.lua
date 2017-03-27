_G._savedEnv = getfenv()
module( "global_game_state", package.seeall )

require( GetScriptDirectory().."/buildings_status" )
require( GetScriptDirectory().."/debugging" )
local gHero = require( GetScriptDirectory().."/global_hero_data" )
local utils = require( GetScriptDirectory().."/utility" )
local enemyData = require( GetScriptDirectory().."/enemy_data" )

local laneStates = {[LANE_TOP] = {dontdefend = false},
                    [LANE_MID] = {dontdefend = false},
                    [LANE_BOT] = {dontdefend = false}}

                    
local shrineStates = {
    [SHRINE_BASE_1]     = {handle = GetShrine(GetTeam(), SHRINE_BASE_1), pidsLookingForHeal = {}},
    [SHRINE_BASE_2]     = {handle = GetShrine(GetTeam(), SHRINE_BASE_2), pidsLookingForHeal = {}},
    [SHRINE_BASE_3]     = {handle = GetShrine(GetTeam(), SHRINE_BASE_3), pidsLookingForHeal = {}},
    [SHRINE_BASE_4]     = {handle = GetShrine(GetTeam(), SHRINE_BASE_4), pidsLookingForHeal = {}},
    [SHRINE_BASE_5]     = {handle = GetShrine(GetTeam(), SHRINE_BASE_5), pidsLookingForHeal = {}},
    [SHRINE_JUNGLE_1]   = {handle = GetShrine(GetTeam(), SHRINE_JUNGLE_1), pidsLookingForHeal = {}},
    [SHRINE_JUNGLE_2]   = {handle = GetShrine(GetTeam(), SHRINE_JUNGLE_2), pidsLookingForHeal = {}}
}

function GetShrineState(shrineID)
    return shrineStates[shrineID]
end

function RemovePIDFromShrine(shrineID, pid)
    local pidLoc = utils.PosInTable(shrineStates[shrineID].pidsLookingForHeal, pid)
    if pidLoc >= 0 then
        table.remove(shrineStates[shrineID].pidsLookingForHeal, pidLoc)
    end
end

-- TODO: used for reading and writing. not really good.
function LaneState(lane)
    return laneStates[lane]
end

-- Returns the closest building of team to a unit
function GetClosestBuilding(unit, team)
    local min_dist = 99999999
    local building = nil
    for _, id in pairs(buildings_status.GetStandingBuildingIDs(team)) do
        local vec = buildings_status.GetLocation(team, id)
        local d = GetUnitToLocationDistance(unit, vec)
        if d < min_dist then
            min_dist = d
            building = vec
        end
    end
    return id, building
end

-- Get the position between buildings (0 = sitting on teams tower, 1 = sitting on enemy's tower)
function GetPositionBetweenBuildings(unit, team)
    local _, allied_building = GetClosestBuilding(unit, team)
    local d_allied = GetUnitToLocationDistance(unit, allied_building)
    local _, enemy_building = GetClosestBuilding(unit, utils.GetOppositeTeamTo(team))
    local d_enemy = GetUnitToLocationDistance(unit, enemy_building)

    return d_allied / (d_allied + d_enemy)
end

function nearBuilding(unitLoc, buildingLoc)
    return utils.GetDistance(unitLoc, buildingLoc) <= 1000
end

function numEnemiesNearBuilding(building)
    local num = 0
    local enemies = GetUnitList(UNIT_LIST_ENEMY_HEROES)
    for _, enemy in pairs(enemies) do
        if nearBuilding(enemy:GetLocation(), buildings_status.GetLocation(GetTeam(), building)) then
            num = num + 1
        end
    end
    return num
end

-- Detect if a tower is being pushed
function DetectEnemyPushMid()
    local building = buildings_status.GetVulnerableBuildingIDs(GetTeam(), LANE_MID)[1]

    local hBuilding = buildings_status.GetHandle(GetTeam(), building)

    if hBuilding == nil then return 0, building end

    if hBuilding and hBuilding:TimeSinceDamagedByAnyHero() < 1.5 then
        local num = numEnemiesNearBuilding(building)
        return num, building
    end
    return 0, building
end

function DetectEnemyPushTop()
    local building = buildings_status.GetVulnerableBuildingIDs(GetTeam(), LANE_TOP)[1]

    local hBuilding = buildings_status.GetHandle(GetTeam(), building)

    if hBuilding == nil then return 0, building end

    if hBuilding and hBuilding:TimeSinceDamagedByAnyHero() < 1.5 then
        local num = numEnemiesNearBuilding(building)
        return num, building
    end
    return 0, building
end

function DetectEnemyPushBot()
    local building = buildings_status.GetVulnerableBuildingIDs(GetTeam(), LANE_BOT)[1]

    local hBuilding = buildings_status.GetHandle(GetTeam(), building)

    if hBuilding == nil then return 0, building end

    if hBuilding and hBuilding:TimeSinceDamagedByAnyHero() < 1.5 then
        local num = numEnemiesNearBuilding(building)
        return num, building
    end
    return 0, building
end

local lastPushCheck = -1000.0
function DetectEnemyPush()
    local bUpdate, newTime = utils.TimePassed(lastPushCheck, 0.5)
    if bUpdate then
        local numMid, midBuilding = DetectEnemyPushMid()
        local numTop, topBuilding = DetectEnemyPushTop()
        local numBot, botBuilding = DetectEnemyPushBot()
        if numMid > 0 then
            return LANE_MID, midBuilding, numMid
        elseif numTop > 0 then
            return LANE_TOP, topBuilding, numTop
        elseif numBot > 0 then
            return LANE_BOT, botBuilding, numBot
        end
        lastPushCheck = newTime
    end
    return nil, nil, nil
end

local lastBuildingUpdate = -1000.0
local vulnEnemyBuildings = nil
function GetLatestVulnerableEnemyBuildings()
    local bUpdate, newTime = utils.TimePassed(lastBuildingUpdate, 3.0)
    if bUpdate then
        vulnEnemyBuildings = buildings_status.GetDestroyableTowers(utils.GetOtherTeam())
        lastBuildingUpdate = newTime
    end
    return vulnEnemyBuildings
end

local lastGlobalFightDetermination = -1000.0
function GlobalFightDetermination()
    local bUpdate, newTime = utils.TimePassed(lastGlobalFightDetermination, 0.25)
    if bUpdate then lastGlobalFightDetermination = newTime else return end

    local eyeRange = 1200
    local listAllies = GetUnitList(UNIT_LIST_ALLIED_HEROES)
    for _, ally in pairs(listAllies) do
        if ally:IsAlive() and ally:IsBot() and ally:GetHealth()/ally:GetMaxHealth() > 0.4 and not ally:IsIllusion()
            and gHero.HasID(ally:GetPlayerID()) and gHero.GetVar(ally:GetPlayerID(), "Target").Id == 0 then

            local totalNukeDmg = 0

            local numEnemiesThatCanAttackMe = 0
            local numAlliesThatCanHelpMe = 0

            for k, enemy in pairs(enemyData) do
                -- get a valid enemyData enemy
                if type(k) == "number" and enemy.Alive then
                    local distance = 100000
                    if enemy.Obj then
                        distance = GetUnitToUnitDistance(ally, enemy.Obj)
                    else
                        if GetHeroLastSeenInfo(k).time == -1 then break end

                        if GetHeroLastSeenInfo(k).time <= 0.5 then
                            distance = GetUnitToLocationDistance(ally, enemy.LocExtra1)
                        elseif GetHeroLastSeenInfo(k).time <= 3.0 then
                            distance = GetUnitToLocationDistance(ally, enemy.LocExtra2)
                        else
                            break --distance = GetUnitToLocationDistance(ally, GetHeroLastSeenInfo(k).location)
                        end
                    end

                    local theirTimeToReachMe = distance/enemy.MoveSpeed

                    local timeToReach = distance/ally:GetCurrentMovementSpeed()
                    local myNukeDmg, myActionQueue, myCastTime, myStun, mySlow, myEngageDist = gHero.GetVar(ally:GetPlayerID(), "Self"):GetNukeDamage( ally, enemy.Obj )

                    -- update our total nuke damage
                    totalNukeDmg = totalNukeDmg + myNukeDmg

                    if distance <= eyeRange then
                        numEnemiesThatCanAttackMe = numEnemiesThatCanAttackMe + 1
                        --utils.myPrint(utils.GetHeroName(ally), " sees "..enemy.Name.." ", distance, " units away. Time to reach: ", timeToReach)

                        local allAllyStun = 0
                        local allAllySlow = 0
                        local myTimeToKillTarget = 0.0
                        if utils.ValidTarget(enemy) then
                            myTimeToKillTarget = fight_simul.estimateTimeToKill(ally, enemy.Obj)
                        else
                            myTimeToKillTarget = enemy.Health/(ally:GetAttackDamage()/ally:GetSecondsPerAttack())/0.75
                        end

                        local totalTimeToKillTarget = myTimeToKillTarget

                        local participatingAllies = {}
                        local globalAllies = {}

                        for _, ally2 in pairs(listAllies) do
                            -- this 'if' is for non-implemented bot heroes that are on our team
                            if ally2:IsAlive() and ally2:IsBot() and not ally2:IsIllusion() and not gHero.HasID(ally2:GetPlayerID()) then
                                local distToEnemy = 100000
                                if enemy.Obj then
                                    distToEnemy = GetUnitToUnitDistance(ally2, enemy.Obj)
                                else
                                    if GetHeroLastSeenInfo(k) == nil then break end

                                    if GetHeroLastSeenInfo(k).time <= 0.5 then
                                        distToEnemy = GetUnitToLocationDistance(ally2, enemy.LocExtra1)
                                    elseif GetHeroLastSeenInfo(k).time <= 3.0 then
                                        distToEnemy = GetUnitToLocationDistance(ally2, enemy.LocExtra2)
                                    else
                                        break --distToEnemy = GetUnitToLocationDistance(ally2, GetHeroLastSeenInfo(k).location)
                                    end
                                end
                                local allyTimeToReach = distToEnemy/ally2:GetCurrentMovementSpeed()

                                local globalAbility = gHero.GetVar(ally2:GetPlayerID(), "HasGlobal")

                                if distToEnemy <= 2*eyeRange then
                                    --utils.myPrint("ally ", utils.GetHeroName(ally2), " is ", distToEnemy, " units away. Time to reach: ", allyTimeToReach)
                                    totalTimeToKillTarget = totalTimeToKillTarget + 8.0
                                    table.insert(participatingAllies, {ally2, {}, 500})
                                elseif globalAbility and globalAbility[1]:IsFullyCastable() then
                                    table.insert(globalAllies, {ally2, globalAbility})
                                end
                            -- this 'elseif' is for implemented bot heroes on our team
                            elseif ally2:IsAlive() and not ally2:IsIllusion() and ally2:GetPlayerID() ~= ally:GetPlayerID() and gHero.GetVar(ally2:GetPlayerID(), "Target").Id == 0
                                and (gHero.GetVar(ally2:GetPlayerID(), "GankTarget").Id == 0 or gHero.GetVar(ally2:GetPlayerID(), "GankTarget").Id == k) then
                                local distToEnemy = 100000
                                if enemy.Obj then
                                    distToEnemy = GetUnitToUnitDistance(ally2, enemy.Obj)
                                else
                                    if GetHeroLastSeenInfo(k).time <= 0.5 then
                                        distToEnemy = GetUnitToLocationDistance(ally2, enemy.LocExtra1)
                                    elseif GetHeroLastSeenInfo(k).time <= 3.0 then
                                        distToEnemy = GetUnitToLocationDistance(ally2, enemy.LocExtra2)
                                    else
                                        --distToEnemy = GetUnitToLocationDistance(ally2, GetHeroLastSeenInfo(k).location)
                                        break
                                    end
                                end

                                if GetUnitToUnitDistance(ally, ally2) < eyeRange then
                                    numAlliesThatCanHelpMe = numAlliesThatCanHelpMe + 1
                                end

                                local allyTimeToReach = distToEnemy/ally2:GetCurrentMovementSpeed()
                                local allyNukeDmg, allyActionQueue, allyCastTime, allyStun, allySlow, allyEngageDist = gHero.GetVar(ally2:GetPlayerID(), "Self"):GetNukeDamage( ally2, enemy.Obj )

                                -- update our total nuke damage
                                totalNukeDmg = totalNukeDmg + allyNukeDmg

                                local globalAbility = gHero.GetVar(ally2:GetPlayerID(), "HasGlobal")
                                if allyTimeToReach <= 6.0 then
                                    --utils.myPrint("ally ", utils.GetHeroName(ally2), " is ", distToEnemy, " units away. Time to reach: ", allyTimeToReach)

                                    allAllyStun = allAllyStun + allyStun
                                    allAllySlow = allAllySlow + allySlow
                                    local allyTimeToKillTarget = 0.0
                                    if utils.ValidTarget(enemy) then
                                        allyTimeToKillTarget = fight_simul.estimateTimeToKill(ally2, enemy.Obj)
                                    else
                                        allyTimeToKillTarget = enemy.Health /(ally2:GetAttackDamage()/ally2:GetSecondsPerAttack())/0.75
                                    end
                                    totalTimeToKillTarget = totalTimeToKillTarget + allyTimeToKillTarget
                                    table.insert(participatingAllies, {ally2, allyActionQueue, allyEngageDist})
                                elseif globalAbility and globalAbility[1]:IsFullyCastable() then
                                    table.insert(globalAllies, {ally2, globalAbility})
                                end
                            end
                        end

                        local numAttackers = #participatingAllies+1
                        local anticipatedTimeToKill = (totalTimeToKillTarget/numAttackers) - 2*#globalAllies
                        local totalStun = myStun + allAllyStun
                        local totalSlow = mySlow + allAllySlow
                        local timeToKillBonus = numAttackers*(totalStun + 0.5*totalSlow)

                        if utils.ValidTarget(enemy) then
                            -- if global we picked a 1v? fight then let it work out at the hero-level
                            if numAttackers == 1 then break end

                            if totalNukeDmg/#gHeroVar.GetNearbyEnemies(ally, 1200) >= enemy.Obj:GetHealth() then
                                utils.myPrint(#participatingAllies+1, " of us can Nuke ", enemy.Name)
                                utils.myPrint(utils.GetHeroName(ally), " - Engaging!")

                                local allyID = ally:GetPlayerID()
                                gHero.SetVar(allyID, "Target", {Obj=enemy.Obj, Id=k})
                                gHero.GetVar(allyID, "Self"):AddMode(constants.MODE_FIGHT)
                                gHero.GetVar(allyID, "Self"):QueueNuke(ally, enemy.Obj, myActionQueue, myEngageDist)

                                for _, v in pairs(participatingAllies) do
                                    if gHero.GetVar(v[1]:GetPlayerID(), "GankTarget").Id == 0 then
                                        gHero.SetVar(v[1]:GetPlayerID(), "Target", {Obj=enemy.Obj, Id=k})
                                        gHero.GetVar(v[1]:GetPlayerID(), "Self"):AddMode(constants.MODE_FIGHT)
                                        if #v[2] > 0 and GetUnitToUnitDistance(v[1], enemy.Obj) < v[3] then
                                            gHero.GetVar(v[1]:GetPlayerID(), "Self"):QueueNuke(v[1], enemy.Obj, v[2], v[3])
                                        elseif #v[2] > 0 then
                                            gHero.HeroAttackUnit(v[1], enemy.Obj, true)
                                        end
                                    end
                                end

                                for _, v in pairs(globalAllies) do
                                    gHero.SetVar(v[1]:GetPlayerID(), "UseGlobal", {v[2][1], enemy.Obj})
                                    utils.myPrint(utils.GetHeroName(v[1]).." casting global skill.")
                                end

                                return
                            elseif (anticipatedTimeToKill - timeToKillBonus) < 6.0/#gHeroVar.GetNearbyEnemies(ally, 1200) then
                                utils.myPrint(#participatingAllies+#globalAllies+1, " of us can Stun for: ", totalStun, " and Slow for: ", totalSlow, ". AnticipatedTimeToKill ", enemy.Name ,": ", anticipatedTimeToKill)
                                utils.myPrint(utils.GetHeroName(ally), " - Engaging! Anticipated Time to kill: ", anticipatedTimeToKill)
                                gHero.SetVar(ally:GetPlayerID(), "Target", {Obj=enemy.Obj, Id=k})
                                gHero.GetVar(ally:GetPlayerID(), "Self"):AddMode(constants.MODE_FIGHT)
                                for _, v in pairs(participatingAllies) do
                                    if gHero.GetVar(v[1]:GetPlayerID(), "GankTarget").Id == 0 then
                                        gHero.SetVar(v[1]:GetPlayerID(), "Target", {Obj=enemy.Obj, Id=k})
                                        gHero.GetVar(v[1]:GetPlayerID(), "Self"):AddMode(constants.MODE_FIGHT)
                                        if #v[2] > 0 and GetUnitToUnitDistance(v[1], enemy.Obj) < v[3] then
                                            gHero.GetVar(v[1]:GetPlayerID(), "Self"):QueueNuke(v[1], enemy.Obj, v[2], v[3])
                                        elseif #v[2] > 0 then
                                            gHero.HeroAttackUnit(v[1], enemy.Obj, true)
                                        end
                                    end
                                end

                                for _, v in pairs(globalAllies) do
                                    gHero.SetVar(v[1]:GetPlayerID(), "UseGlobal", {v[2][1], enemy.Obj})
                                    utils.myPrint(utils.GetHeroName(v[1]).." casting global skill.")
                                end

                                return
                            end
                        end
                    end
                end
            end

            if numEnemiesThatCanAttackMe > numAlliesThatCanHelpMe then
                --utils.myPrint(utils.GetHeroName(ally), "This is a bad idea")
                --ally:Action_ClearActions(false)
            end
        end
    end
end

for k,v in pairs( global_game_state ) do _G._savedEnv[k] = v end
