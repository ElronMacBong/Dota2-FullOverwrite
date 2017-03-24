-------------------------------------------------------------------------------
--- AUTHOR: Nostrademous
--- GITHUB REPO: https://github.com/Nostrademous/Dota2-FullOverwrite
-------------------------------------------------------------------------------

BotsInit = require( "game/botsinit" )
local linaAbility = BotsInit.CreateGeneric()

local utils = require( GetScriptDirectory().."/utility" )
local gHeroVar = require( GetScriptDirectory().."/global_hero_data" )

function setHeroVar(var, value)
    local bot = GetBot()
    gHeroVar.SetVar(bot:GetPlayerID(), var, value)
end

function getHeroVar(var)
    local bot = GetBot()
    return gHeroVar.GetVar(bot:GetPlayerID(), var)
end

local abilityQ = ""
local abilityW = ""
local abilityE = ""
local abilityR = ""

local castLSADesire = 0
local castDSDesire  = 0
local castLBDesire  = 0

local function nukeDamage( bot, enemy )
    if not utils.ValidTarget(enemy) then return 0, {}, 0, 0, 0 end

    local comboQueue = {}
    local manaAvailable = bot:GetMana()
    local dmgTotal = 0
    local castTime = 0
    local stunTime = 0
    local slowTime = 0
    local engageDist = 10000

    local magicImmune = utils.IsTargetMagicImmune(enemy)

    -- Check Laguna Blade
    if abilityR:IsFullyCastable() then
        local manaCostR = abilityR:GetManaCost()
        if manaCostR <= manaAvailable then
            if bot:HasScepter() then
                manaAvailable = manaAvailable - manaCostR
                dmgTotal = dmgTotal + abilityR:GetAbilityDamage()
                castTime = castTime + abilityR:GetCastPoint()
                engageDist = Min(engageDist, abilityR:GetCastRange())
                table.insert(comboQueue, abilityR)
            else
                if not magicImmune then
                    manaAvailable = manaAvailable - manaCostR
                    dmgTotal = dmgTotal + enemy:GetActualIncomingDamage(abilityR:GetAbilityDamage(), DAMAGE_TYPE_MAGICAL)
                    castTime = castTime + abilityR:GetCastPoint()
                    engageDist = Min(engageDist, abilityR:GetCastRange())
                    table.insert(comboQueue, abilityR)
                end
            end
        end
    end

    -- Check Dragon Slave
    if abilityQ:IsFullyCastable() then
        local manaCostQ = abilityQ:GetManaCost()
        if manaCostQ <= manaAvailable then
            if not magicImmune then
                manaAvailable = manaAvailable - manaCostQ
                dmgTotal = dmgTotal + enemy:GetActualIncomingDamage(abilityQ:GetAbilityDamage(), DAMAGE_TYPE_MAGICAL)
                castTime = castTime + abilityQ:GetCastPoint()
                engageDist = Min(engageDist, abilityQ:GetCastRange())
                table.insert(comboQueue, 1, abilityQ)
            end
        end
    end

    -- Check Light Strike Array
    if abilityW:IsFullyCastable() then
        local manaCostW = abilityW:GetManaCost()
        if manaCostW <= manaAvailable then
            if not magicImmune then
                manaAvailable = manaAvailable - manaCostW
                dmgTotal = dmgTotal + enemy:GetActualIncomingDamage(abilityW:GetAbilityDamage(), DAMAGE_TYPE_MAGICAL)
                castTime = castTime + abilityW:GetCastPoint()
                stunTime = stunTime + abilityW:GetSpecialValueFloat("light_strike_array_stun_duration")
                engageDist = Min(engageDist, abilityW:GetCastRange())
                table.insert(comboQueue, 1, abilityW)
                
                --[[
                local euls = utils.IsItemAvailable("item_cyclone")
                if euls then
                    engageDist = 575
                    table.insert(comboQueue, 1, bot:ActionPush_Delay())
                    table.insert(comboQueue, 1, euls)
                end
                --]]
            end
        end
    end

    return dmgTotal, comboQueue, castTime, stunTime, slowTime, engageDist
end

local function queueNuke(bot, enemy, castQueue, engageDist)
    if not utils.ValidTarget(enemy) then return false end
    
    local dist = GetUnitToUnitDistance(bot, enemy)

    -- if out of range, attack move for one hit to get in range
    if dist < engageDist then
        bot:Action_ClearActions(false)
        utils.AllChat("Killing "..utils.GetHeroName(enemy).." softly with my song")
        utils.myPrint("Queue Nuke Damage: ", utils.GetHeroName(enemy))
        for i = #castQueue, 1, -1 do
            local skill = castQueue[i]
            local behaviorFlag = skill:GetBehavior()

            --utils.myPrint(" - skill '", skill:GetName(), "' has BehaviorFlag: ", behaviorFlag)

            if skill:GetName() == "lina_light_strike_array" then
                if utils.IsCrowdControlled(enemy) then
                    gHeroVar.HeroPushUseAbilityOnLocation(bot, skill, enemy:GetLocation())
                else
                    gHeroVar.HeroPushUseAbilityOnLocation(bot, skill, enemy:GetExtrapolatedLocation(0.95))
                end
            elseif skill:GetName() == "lina_dragon_slave" then
                if utils.IsCrowdControlled(enemy) then
                    gHeroVar.HeroPushUseAbilityOnLocation(bot, skill, enemy:GetLocation())
                else
                    -- account for 0.45 cast point and speed of wave (1200) needed to travel the distance between us
                    gHeroVar.HeroPushUseAbilityOnLocation(bot, skill, enemy:GetExtrapolatedLocation(0.45 + dist/1200))
                end
            elseif skill:GetName() == "lina_laguna_blade" then
                gHeroVar.HeroPushUseAbilityOnEntity(bot, skill, enemy)
            end
        end
        return true
    end
    return false
end

function linaAbility:AbilityUsageThink(bot)
    -- Check if we're already using an ability
    if utils.IsBusy(bot) then return true end
    
    if utils.IsUnableToCast(bot) then return false end
    
    if abilityQ == "" then abilityQ = bot:GetAbilityByName( "lina_dragon_slave" ) end
    if abilityW == "" then abilityW = bot:GetAbilityByName( "lina_light_strike_array" ) end
    if abilityE == "" then abilityE = bot:GetAbilityByName( "lina_fiery_soul" ) end
    if abilityR == "" then abilityR = bot:GetAbilityByName( "lina_laguna_blade" ) end
    
    local nearbyEnemyHeroes = gHeroVar.GetNearbyEnemies(bot, 1200)
    local nearbyEnemyCreep = gHeroVar.GetNearbyEnemyCreep(bot, 1200)
    
    if ( #nearbyEnemyHeroes == 0 and #nearbyEnemyCreep == 0 ) then return false end

    if #nearbyEnemyHeroes == 1 and nearbyEnemyHeroes[1]:GetHealth() > 0 then
        local enemy = nearbyEnemyHeroes[1]
        local dmg, castQueue, castTime, stunTime, slowTime, engageDist = nukeDamage( bot, enemy )

        local rightClickTime = stunTime + 0.5*slowTime
        if rightClickTime > 0.5 then
            dmg = dmg + fight_simul.estimateRightClickDamage( bot, enemy, rightClickTime )
        end

        -- magic immunity is already accounted for by nukeDamage()
        if dmg > enemy:GetHealth() then
            local bKill = queueNuke(bot, enemy, castQueue, engageDist)
            if bKill then
                setHeroVar("Target", enemy)
                return true
            end
        end
    end

    -- Consider using each ability
    castLBDesire, castLBTarget = ConsiderLagunaBlade(nearbyEnemyHeroes)

    local target = getHeroVar("Target")
    if utils.ValidTarget(target) then
        castLSADesire, castLSALocation = ConsiderLightStrikeArrayFighting(target)
    else
        castLSADesire, castLSALocation = ConsiderLightStrikeArray(nearbyEnemyHeroes)
    end

    if utils.ValidTarget(target) then
        castDSDesire, castDSLocation = ConsiderDragonSlaveFighting(target)
    else
        castDSDesire, castDSLocation = ConsiderDragonSlave()
    end

    --utils.myPrint("LB Desire: ", castLBDesire)
    --utils.myPrint("LSA Desire: ", castLSADesire)
    --utils.myPrint("DS Desire: ", castDSDesire)
    
    if castLBDesire > castLSADesire and 
        castLBDesire > castDSDesire then
        --utils.myPrint( "I Desired a LB Hit" )
        gHeroVar.HeroUseAbilityOnEntity(bot,  abilityR, castLBTarget )
        return true
    end

    if castLSADesire > 0 then
        --utils.myPrint( "I Desired a LSA Hit" )
        gHeroVar.HeroUseAbilityOnLocation(bot,  abilityW, castLSALocation )
        return true
    end

    if castDSDesire > 0 then
        --utils.myPrint( "I Desired a DS Hit" )
        gHeroVar.HeroUseAbilityOnLocation(bot,  abilityQ, castDSLocation )
        return true
    end

    return false
end

----------------------------------------------------------------------------------------------------

local function CanCastLightStrikeArrayOnTarget( npcTarget )
    return npcTarget:IsHero() and not utils.IsTargetMagicImmune(npcTarget)
end

local function CanCastLagunaBladeOnTarget( npcTarget )
    return npcTarget:IsHero() and ( GetBot():HasScepter() or not npcTarget:IsMagicImmune() ) and not npcTarget:IsInvulnerable()
end

----------------------------------------------------------------------------------------------------

function ConsiderLightStrikeArrayFighting(enemy)
    if not utils.ValidTarget(enemy) then return BOT_ACTION_DESIRE_NONE, 0 end

    local bot = GetBot()

    if not abilityW:IsFullyCastable() then
        return BOT_ACTION_DESIRE_NONE, 0
    end

    local nRadius = abilityW:GetSpecialValueInt( "light_strike_array_aoe" )
    local nCastRange = abilityW:GetCastRange()

    -- NOTE: LSA cast point is 0.45, hit delay is 0.50
    local locDelta = enemy:GetExtrapolatedLocation(0.95 + getHeroVar("AbilityDelay"))
    local EnemyLocation = locDelta

    if utils.IsCrowdControlled(enemy) then
        EnemyLocation = enemy:GetLocation()
    end

    local d = GetUnitToLocationDistance(bot, EnemyLocation)

    if d < (nCastRange + nRadius) and not utils.IsTargetMagicImmune( enemy ) then
        return BOT_ACTION_DESIRE_HIGH, EnemyLocation
    end
    return BOT_ACTION_DESIRE_NONE, 0
end


function ConsiderLightStrikeArray(nearbyEnemyHeroes)
    local bot = GetBot()

    -- Make sure it's castable
    if not abilityW:IsFullyCastable() then
        return BOT_ACTION_DESIRE_NONE, 0
    end

    -- Get some of its values
    local nRadius = abilityW:GetSpecialValueInt( "light_strike_array_aoe" )
    local nCastRange = abilityW:GetCastRange()
    local nDamage = abilityW:GetAbilityDamage()

    --------------------------------------
    -- Global high-priorty usage
    --------------------------------------

    -- Check for a channeling enemy
    for _, npcEnemy in pairs( nearbyEnemyHeroes ) do
        if utils.ValidTarget(npcEnemy) and npcEnemy:IsChanneling() and 
            GetUnitToUnitDistance(bot, npcEnemy) < (nCastRange + nRadius + 200) then
            if CanCastLightStrikeArrayOnTarget( npcEnemy ) then
                return BOT_ACTION_DESIRE_HIGH, npcEnemy:GetLocation()
            end
        end
    end

    --------------------------------------
    -- Mode based usage
    --------------------------------------

    -- If we're farming and can kill 3+ creeps with LSA
    local locationAoE = bot:FindAoELocation( true, false, bot:GetLocation(), nCastRange, nRadius, abilityW:GetCastPoint(), nDamage )

    if ( locationAoE.count >= 3 ) then
        return BOT_ACTION_DESIRE_LOW, locationAoE.targetloc
    end

    if bot.SelfRef:getCurrentMode():GetName() == "pushlane" and (bot:GetMana()/bot:GetMaxMana()) >= 0.4 then
        locationAoE = bot:FindAoELocation( true, false, bot:GetLocation(), nCastRange, nRadius, abilityW:GetCastPoint(), 0 )

        if ( locationAoE.count >= 2 ) then
            return BOT_ACTION_DESIRE_MODERATE, locationAoE.targetloc
        end
    end

    -- If we're seriously retreating, see if we can land a stun on someone who's damaged us recently
    for _, npcEnemy in pairs( nearbyEnemyHeroes ) do
        if utils.ValidTarget(npcEnemy) and GetUnitToUnitDistance(bot, npcEnemy) < (nCastRange + nRadius + 200) then
            -- FIXME: This logic will fail against Heartstopper Aura or Radiance probably making us LSA all the time
            --        as we take damage and are below 50% health
            if bot:WasRecentlyDamagedByHero( npcEnemy, 2.0 ) and (bot:GetHealth()/bot:GetMaxHealth()) < 0.5 then
                if CanCastLightStrikeArrayOnTarget( npcEnemy ) and abilityW:GetCastRange() > GetUnitToUnitDistance(bot, npcEnemy) then
                    -- NOTE: LSA cast point is 0.45, hit delay is 0.50
                    local locDelta = npcEnemy:GetExtrapolatedLocation(0.95 + getHeroVar("AbilityDelay"))
                    return BOT_ACTION_DESIRE_MODERATE, locDelta
                end
            end
        end
    end

    return BOT_ACTION_DESIRE_NONE, 0
end

----------------------------------------------------------------------------------------------------

function ConsiderDragonSlaveFighting(enemy)
    if not utils.ValidTarget(enemy) then return BOT_ACTION_DESIRE_NONE, 0 end
    
    local bot = GetBot()

    if not abilityQ:IsFullyCastable() then
        return BOT_ACTION_DESIRE_NONE, 0
    end

    local nCastRange = abilityQ:GetCastRange()
    local d = GetUnitToUnitDistance(bot, enemy)

    if d < nCastRange and not utils.IsTargetMagicImmune( enemy ) then
        if utils.IsCrowdControlled(enemy) then
            return BOT_ACTION_DESIRE_HIGH, enemy:GetLocation()
        else
            -- NOTE: cast point is 0.45, speed is 1200
            local locDelta = enemy:GetExtrapolatedLocation(0.45 + d/1200 + getHeroVar("AbilityDelay"))
            return BOT_ACTION_DESIRE_HIGH, locDelta
        end
    end

    return BOT_ACTION_DESIRE_NONE, 0
end

function ConsiderDragonSlave()

    local bot = GetBot()

    if not abilityQ:IsFullyCastable() then
        return BOT_ACTION_DESIRE_NONE, 0
    end

    -- Get some of its values
    local nRadius = abilityQ:GetSpecialValueInt( "dragon_slave_width_end" )
    local nCastRange = abilityQ:GetCastRange()
    local nDamage = abilityQ:GetAbilityDamage()
    --print("dragon_slave damage:" .. nDamage)

    -- If we're farming and can kill 2+ creeps with DS when we have plenty mana
    local locationAoE = bot:FindAoELocation( true, false, bot:GetLocation(), nCastRange, nRadius, 0, nDamage )

    if ( locationAoE.count >= 2 ) then
        return BOT_ACTION_DESIRE_LOW, locationAoE.targetloc
    end

    -- If we're pushing or defending a lane and can hit 3+ creeps, go for it
    -- wasting mana banned!
    if bot.SelfRef:getCurrentMode():GetName() == "defendlane" or 
        (bot.SelfRef:getCurrentMode():GetName() == "pushlane" and bot:GetMana() / bot:GetMaxMana() >= 0.4) then
        local locationAoE = bot:FindAoELocation( true, false, bot:GetLocation(), nCastRange, nRadius, 0, 0 )

        if ( locationAoE.count >= 3 ) then
            return BOT_ACTION_DESIRE_LOW, locationAoE.targetloc
        end
    end

    -- If we have plenty mana and high level DS
    if(bot:GetMana() / bot:GetMaxMana() > 0.6 and nDamage > 300) then
        local locationAoE = bot:FindAoELocation( true, true, bot:GetLocation(), nCastRange, nRadius, 0, 0 )

        -- hit heros
        if locationAoE.count >= 1 then
            return BOT_ACTION_DESIRE_LOW, locationAoE.targetloc
        end
    end

    return BOT_ACTION_DESIRE_NONE, 0
end


----------------------------------------------------------------------------------------------------

function ConsiderLagunaBlade(nearbyEnemyHeroes)

    local bot = GetBot()

    -- Make sure it's castable
    if not abilityR:IsFullyCastable() then
        return BOT_ACTION_DESIRE_NONE, 0
    end

    -- Get some of its values
    local nCastRange = abilityR:GetCastRange()
    local nDamage = abilityR:GetSpecialValueInt( "damage" )
    local eDamageType = DAMAGE_TYPE_MAGICAL
    if bot:HasScepter() then
        eDamageType = DAMAGE_TYPE_PURE
    end

    -- If a mode has set a target, and we can kill them, do it
    if #nearbyEnemyHeroes > 0 then
        for _, npcEnemy in pairs( nearbyEnemyHeroes ) do
            if utils.ValidTarget(npcEnemy) and GetUnitToUnitDistance(bot, npcEnemy) < (nCastRange + 200) and 
                CanCastLagunaBladeOnTarget(npcEnemy) then
                if npcEnemy:GetActualIncomingDamage( nDamage, eDamageType ) > npcEnemy:GetHealth() then
                    return BOT_ACTION_DESIRE_MODERATE, npcEnemy
                end
            end
        end
    end

    return BOT_ACTION_DESIRE_NONE, 0
end

return linaAbility