--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type CoopPlayers
local CoopPlayers = ModRequire "CoopPlayers.lua"
---@type HeroContext
local HeroContext = ModRequire "HeroContext.lua"

---@class ResurrectionSystem
local ResurrectionSystem = {}

-- Time in seconds before a player is resurrected after death
ResurrectionSystem.ResurrectionDelay = 2.0

-- Percentage of max health to restore on resurrection (0.0 to 1.0)
ResurrectionSystem.HealthRestorePercent = 0.3

-- Minimum health to restore on resurrection
ResurrectionSystem.MinHealthRestore = 30

-- Duration of invulnerability after resurrection in seconds
ResurrectionSystem.InvulnerabilityDuration = 1.5

-- Stores the position where each player died
ResurrectionSystem.DeathPositions = {}
-- Keep a global reference to death markers so they don't get garbage collected
ResurrectionSystem.DeathMarkers = {}

-- Resurrects a hero
function ResurrectionSystem.ReviveHero(hero, playerId)
    if not hero or not playerId then return end
    
    -- Set player as not dead
    hero.IsDead = false
    
    -- Restore some health
    hero.Health = math.max(hero.MaxHealth * ResurrectionSystem.HealthRestorePercent, ResurrectionSystem.MinHealthRestore)
    
    -- Get the death marker
    local deathPos = ResurrectionSystem.DeathPositions[playerId]
    local deathMarker = ResurrectionSystem.DeathMarkers[playerId]
    
    if playerId == 1 then
        -- Main player revival
        SetColor { Id = hero.ObjectId, Color = { 255, 255, 255, 255 } }
        
        -- Teleport to death position if available
        if deathPos and deathMarker then
            DebugPrint({ Text = "Teleporting player " .. playerId .. " to death position ID:" .. tostring(deathPos) })
            Teleport({ Id = hero.ObjectId, DestinationId = deathPos })
            
            -- Destroy the ghost spawned at death
            if hero.DeathGhost then
                DebugPrint({ Text = "Destroying ghost for player " .. playerId .. " at ID:" .. tostring(hero.DeathGhost) })
                Destroy({ Id = hero.DeathGhost })
                hero.DeathGhost = nil
            end
            
            -- Destroy the death marker after use
            Destroy({ Id = deathMarker })
        else
            -- Fallback to room spawn
            if CurrentRun.CurrentRoom and CurrentRun.CurrentRoom.HeroEndPoint then
                Teleport({ Id = hero.ObjectId, DestinationId = CurrentRun.CurrentRoom.HeroEndPoint })
            end
        end
        
        HeroContext.SetDefaultHero(hero)
        
        -- Restore player 1's input controls
        SwitchActiveUnit { PlayerIndex = 1, Id = hero.ObjectId }
        hero.BlockStatusAnimations = false
        
        -- Remove any input blocks that might have been added
        RemoveInputBlock({ Name = "DeathInput" })
        RemoveInputBlock({ Name = "MoveHeroToRoomPosition" })
        RemoveInputBlock({ PlayerIndex = 1, Name = "DeathInput" })
        RemoveInputBlock({ PlayerIndex = 1, Name = "MoveHeroToRoomPosition" })
        
        -- Ensure weapons are re-equipped
        local weaponsToRestore = { "RangedWeapon" }
        for _, weaponName in ipairs(WeaponSets.HeroMeleeWeapons) do
            if hero.Weapons and hero.Weapons[weaponName] then
                table.insert(weaponsToRestore, weaponName)
            end
        end
        EquipWeapon({ DestinationId = hero.ObjectId, Names = weaponsToRestore })
    else
        -- Re-create co-op player
        CoopPlayers.InitCoopUnit(playerId)
        
        -- Teleport to death position if available
        if deathPos and deathMarker then
            DebugPrint({ Text = "Teleporting player " .. playerId .. " to death position ID:" .. tostring(deathPos) })
            Teleport({ Id = hero.ObjectId, DestinationId = deathPos })
            
            -- Destroy the ghost spawned at death
            if hero.DeathGhost then
                DebugPrint({ Text = "Destroying ghost for player " .. playerId .. " at ID:" .. tostring(hero.DeathGhost) })
                Destroy({ Id = hero.DeathGhost })
                hero.DeathGhost = nil
            end
            
            -- Destroy the death marker after use
            Destroy({ Id = deathMarker })
        else
            -- Fallback to room spawn point
            if CurrentRun.CurrentRoom and CurrentRun.CurrentRoom.HeroEndPoint then
                DebugPrint({ Text = "No death marker found, teleporting player " .. playerId .. " to room spawn" })
                Teleport({ Id = hero.ObjectId, DestinationId = CurrentRun.CurrentRoom.HeroEndPoint })
            else
                Teleport({ Id = hero.ObjectId, DestinationId = CurrentRun.Hero.ObjectId })
            end
        end
        
        -- Remove any input blocks for the co-op player
        RemoveInputBlock({ PlayerIndex = playerId, Name = "DeathInput" })
        RemoveInputBlock({ PlayerIndex = playerId, Name = "MoveHeroToRoomPosition" })
    end
    
    -- Invulnerability effect for a moment
    SetUnitInvulnerable({ Id = hero.ObjectId, InvulnerableTimeout = ResurrectionSystem.InvulnerabilityDuration })
    
    -- Visual effect for revival
    CreateAnimation({ Name = "RadialNovaSuper", DestinationId = hero.ObjectId })
    Flash({ Id = hero.ObjectId, Speed = 2, MinFraction = 0, MaxFraction = 0.8, Color = Color.Green, Duration = 0.5 })

    -- Death Defiance full effect (after resurrection is complete)
    thread(PlayerLastStandPresentationStart, {})
    SetAnimation({ Name = "ZagreusWrath", DestinationId = hero.ObjectId })
    thread(PlayerLastStandPresentationEnd)
    
    -- Clean up death markers
    if ResurrectionSystem.DeathMarkers[playerId] then
        Destroy({ Id = ResurrectionSystem.DeathMarkers[playerId] })
        ResurrectionSystem.DeathMarkers[playerId] = nil
    end
    ResurrectionSystem.DeathPositions[playerId] = nil
end

return ResurrectionSystem 