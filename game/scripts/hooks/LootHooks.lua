--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type HookUtils
local HookUtils = ModRequire "../HookUtils.lua"
---@type HeroContext
local HeroContext = ModRequire "../HeroContext.lua"
---@type HeroContextProxy
local HeroContextProxy = ModRequire "../HeroContextProxy.lua"
---@type CoopPlayers
local CoopPlayers = ModRequire "../CoopPlayers.lua"

---@class LootHooks
local LootHooks = {}

---@private
---@type table | nil
LootHooks.ForceNextLootHero = nil

---@private
LootHooks.LootHeroCount = 1

---@private
LootHooks.LootCounter = 1

function LootHooks.InitHooks()
    -- Select hero for blind loot
    HookUtils.onPreFunction("UnwrapRandomLoot", function()
        LootHooks.ForceNextLootHero = CurrentRun.Hero
    end)

    HookUtils.onPostFunction("UnwrapRandomLoot", function()
        for lootId, lootData in pairs(LootObjects) do
            if not lootData.Cost then
                CoopUseItem(CurrentRun.Hero.ObjectId, lootId)
                return
            end
        end
    end)

    HookUtils.wrap("GiveLoot", LootHooks.GiveLootHook)

    -- Select a player for room reward
    HookUtils.wrap("DoUnlockRoomExits", LootHooks.DoUnlockRoomExitsHook)

    -- Spawns room reward for a player selected by room
    HookUtils.wrap("SpawnRoomReward", LootHooks.SpawnRoomRewardHook)
end

---@param heroesCount number
function LootHooks.Reset(heroesCount)
    HeroContextProxy.Make(CurrentRun.LootTypeHistory)
    LootHooks.LootHeroCount = heroesCount
    LootHooks.LootCounter = RandomInt(1, heroesCount)
end

---@private
function LootHooks.GiveLootHook(baseFun, args)
    local hero = LootHooks.UseForcedLootHero()
    if hero then
        return HeroContext.RunWithHeroContextReturn(hero, baseFun, args)
    else
        return baseFun(args)
    end
end

---@private
function LootHooks.UseForcedLootHero()
    if LootHooks.ForceNextLootHero then
        local hero = LootHooks.ForceNextLootHero
        LootHooks.ForceNextLootHero = nil
        return hero
    end
end

---@private
---@return number | nil
function LootHooks.UseNextHeroForLoot()
    if LootHooks.LootHeroCount <= 1 then
        return
    end

    local startPos = LootHooks.LootCounter
    local playerIndex = startPos + 1
    while true do
        if playerIndex > LootHooks.LootHeroCount then
            playerIndex = 1
        end

        if playerIndex == startPos then
            return
        end

        local hero = CoopPlayers.GetHero(playerIndex)
        if not hero.IsDead then
            LootHooks.LootCounter = playerIndex
            return playerIndex
        end

        playerIndex = playerIndex + 1
    end
end

---@private
function LootHooks.DoUnlockRoomExitsHook(baseFun, run, room)
    if not LootHooks.NeedsCurrentRoomExitRewards() then
        return baseFun(run, room)
    end

    local playerIndex = LootHooks.UseNextHeroForLoot()
    if playerIndex then
        room.CoopModPlayerId = playerIndex
        HeroContext.RunWithHeroContext(CoopPlayers.GetHero(playerIndex), baseFun, run, room)
    else
        baseFun(run, room)
    end
end

---@private
function LootHooks.SpawnRoomRewardHook(baseFun, ...)
    local room = CurrentRun.CurrentRoom
    local roomRewardPredefinedPlayerId = room.CoopModPlayerId

    -- Fix #16
    room.DisableRewardMagnetisim = true

    local hero = roomRewardPredefinedPlayerId and CoopPlayers.GetHero(roomRewardPredefinedPlayerId) or CurrentRun.Hero

    if hero.IsDead then
        local alternativePlayerIndex
        if roomRewardPredefinedPlayerId then
            alternativePlayerIndex = LootHooks.UseNextHeroForLoot()

            if not alternativePlayerIndex then
                DebugPrint { Text = "Cannot spawn a loot for a player. Cannot choose alternative hero" }
                return baseFun(...)
            end

            hero = CoopPlayers.GetHero(alternativePlayerIndex)
        else
            hero = CoopPlayers.GetAliveHeroes()[1]

            if not hero then
                DebugPrint { Text = "Cannot spawn a loot for a player. All players are dead" }
                return baseFun(...)
            end
        end
    end

    HeroContext.RunWithHeroContext(hero, baseFun, ...)
    
    -- Generate a second reward for player 2 if they exist and are alive
    LootHooks.SpawnSecondPlayerReward()
end

---@private
function LootHooks.SpawnSecondPlayerReward()
    local player2 = CoopPlayers.GetHero(2)
    
    -- Only proceed if player 2 exists and is alive
    if not player2 or player2.IsDead then
        return
    end
    
    local currentRoom = CurrentRun.CurrentRoom
    
    -- Don't spawn a reward if we're in a shop or if no reward type is available
    if currentRoom.ChosenRewardType == nil or currentRoom.ChosenRewardType == "Shop" or currentRoom.ChosenRewardType == "Story" or currentRoom.DeferReward then
        return
    end
    
    -- List of reward types that should be doubled for player 2
    local doubledRewardTypes = {
        "Boon",
        "RoomRewardMaxHealthDrop",
        "StackUpgrade", 
        "WeaponUpgrade", 
        "HermesUpgrade",
        "TrialUpgrade"
    }
    
    -- Check if player 1's reward should be doubled
    local shouldDoubleReward = false
    for _, rewardType in ipairs(doubledRewardTypes) do
        if currentRoom.ChosenRewardType == rewardType then
            shouldDoubleReward = true
            break
        end
    end
    
    -- If reward type shouldn't be doubled, return without creating a reward for player 2
    if not shouldDoubleReward then
        DebugPrint { Text = "Player 1 got a reward type that is not doubled for Player 2: " .. currentRoom.ChosenRewardType }
        return
    end
    
    -- Use player 2's hero as the spawn point
    local spawnPointId = player2.ObjectId
    
    -- Generate the same reward for player 2 (except for Boons, which get a random god)
    local reward
    DebugPrint { Text = "Player 1 got " .. currentRoom.ChosenRewardType .. ", giving Player 2 the same type" }
    
    HeroContext.RunWithHeroContext(player2, function()
        if currentRoom.ChosenRewardType == "Boon" then
            -- For Boons, select any random god (may potentially be the same as player 1)
            local godOptions = {"ZeusUpgrade", "PoseidonUpgrade", "AthenaUpgrade", "AphroditeUpgrade", 
                               "AresUpgrade", "ArtemisUpgrade", "DionysusUpgrade", "DemeterUpgrade"}
            
            local selectedGod = godOptions[RandomInt(1, #godOptions)]
            reward = GiveLoot({ ForceLootName = selectedGod, SpawnPoint = spawnPointId, SuppressSpawnSounds = false })
        elseif currentRoom.ChosenRewardType == "StackUpgrade" then
            reward = CreateStackLoot({ SpawnPoint = spawnPointId, SuppressSpawnSounds = false })
        elseif currentRoom.ChosenRewardType == "WeaponUpgrade" then
            reward = CreateWeaponLoot({ SpawnPoint = spawnPointId, SuppressSpawnSounds = false })
        elseif currentRoom.ChosenRewardType == "HermesUpgrade" then
            reward = GiveLoot({ ForceLootName = "HermesUpgrade", SpawnPoint = spawnPointId, SuppressSpawnSounds = false })
        elseif currentRoom.ChosenRewardType == "TrialUpgrade" then
            reward = GiveLoot({ ForceLootName = "TrialUpgrade", SpawnPoint = spawnPointId, SuppressSpawnSounds = false })
        elseif currentRoom.ChosenRewardType == "RoomRewardMaxHealthDrop" then
            -- Max Health upgrade
            local consumableId = SpawnObstacle({ Name = "RoomRewardMaxHealthDrop", DestinationId = spawnPointId, Group = "Standing" })
            reward = CreateConsumableItem(consumableId, "RoomRewardMaxHealthDrop", 0)
            if reward ~= nil then
                ApplyConsumableItemResourceMultiplier(currentRoom, reward)
                ExtractValues(CurrentRun.Hero, reward, reward)
                ActivatedObjects[consumableId] = reward

                if reward.SpawnSound ~= nil then
                    PlaySound({ Name = reward.SpawnSound, Id = reward.ObjectId })
                end
            end
        end
        
        -- Disable reward magnetism to prevent confusion
        if reward and reward.ObjectId then
            SetObstacleProperty({ Property = "MagnetismWhileBlocked", Value = 0, DestinationId = reward.ObjectId })
        end
    end)
end

---@private
function LootHooks.NeedsCurrentRoomExitRewards()
    for _, door in pairs(OfferedExitDoors) do
        if door.NeedsReward then
            return true
        end
    end
    return false
end

return LootHooks
