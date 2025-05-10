--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--

---@type CoopPlayers
local CoopPlayers = ModRequire "../CoopPlayers.lua"
---@type HeroContext
local HeroContext = ModRequire "../HeroContext.lua"
---@type HookUtils
local HookUtils = ModRequire "../HookUtils.lua"
---@type CoopCamera
local CoopCamera = ModRequire "../CoopCamera.lua"
---@type EnemyAiHooks
local EnemyAiHooks = ModRequire "EnemyAiHooks.lua"
---@type LootHooks
local LootHooks = ModRequire "LootHooks.lua"
---@type CoopModConfig
local Config = ModRequire "../config.lua"
---@type SecondPlayerUi
local SecondPlayerUi = ModRequire "../SecondPlayerUI.lua"
---@type RunEx
local RunEx = ModRequire "../RunEx.lua"
---@type ResurrectionSystem
local ResurrectionSystem = ModRequire "../ResurrectionSystem.lua"
---@type CoopControl
local CoopControl = ModRequire "../CoopControl.lua"

---@class RunHooks
local RunHooks = {}

function RunHooks.InitHooks()
    RunHooks.CreateRoomHooks()
    HookUtils.onPreFunction("LeaveRoom", RunHooks.LeaveRoomHook)
    HookUtils.onPreFunction("DeathAreaRoomTransition", RunHooks.DeathAreaRoomTransitionPreHook)
    HookUtils.wrap("StartNewRun", RunHooks.StartNewRunWrapHook)
    HookUtils.wrap("StartRoom", RunHooks.StartRoomWrapHook)
    HookUtils.wrap("KillHero", RunHooks.KillHeroHook)
    HookUtils.wrap("CheckRoomExitsReady", RunHooks.CheckRoomExitsReadyHook)
    HookUtils.wrap("SetupHeroObject", RunHooks.SetupHeroObjectHook)
    HookUtils.wrap("CheckDistanceTrigger", RunHooks.CheckDistanceTriggerWrapHook)
    HookUtils.onPostFunction("StartNewGame", RunHooks.StartNewGameHook)
    HookUtils.onPostFunction("CheckForAllEnemiesDead", RunHooks.CheckForAllEnemiesDeadPostHook)
    HookUtils.onPostFunction("RestoreUnlockRoomExits", RunHooks.RestoreUnlockRoomExitsHook)
end

---@private
function RunHooks.DeathAreaRoomTransitionPreHook()
    if not HeroContext.GetDefaultHero() then
        HeroContext.InitRunHook()
    end
end

---@private
function RunHooks.CheckDistanceTriggerWrapHook(CheckDistanceTriggerFun, ...)
    -- TODO
    -- This hack fixes crashes like #21 when the player 1 is dead.
    -- The crash is caused by invalid reference to the second player.
    -- The game cannot find a player unit and triggers NotifyWithinDistance instantly without result
    HeroContext.RunWithHeroContext(CoopPlayers.GetMainHero(), CheckDistanceTriggerFun, ...)
end

---@private
function RunHooks.SetupHeroObjectHook(SetupHeroObjectFun, ...)
    local mainHero = CoopPlayers.GetMainHero()

    HeroContext.RunWithHeroContext(mainHero, SetupHeroObjectFun, ...)
    -- Fix unit -> hero table here
    CoopPlayers.UpdateMainHero()

    if Config.Player1HasOutline then
        AddOutline(
            MergeTables(Config.Player1Outline, { Id = mainHero.ObjectId })
        )
    end

    if mainHero.IsDead and not RunEx.IsRunEnded() then
        RunHooks.HideHero(mainHero)
    end
end

---@private
function RunHooks.StartRoomWrapHook(StartRoomFun, run, currentRoom)
    -- Initialization after save loading when encounter is active
    if not HeroContext.GetDefaultHero() then
        HeroContext.InitRunHook()
        CoopPlayers.SetMainHero(HeroContext.GetDefaultHero())
    end

    local overrides = currentRoom.EncounterSpecificDataOverwrites and currentRoom.EncounterSpecificDataOverwrites[currentRoom.Encounter.Name]

    local prevRoom = GetPreviousRoom(CurrentRun)
    local roomEntranceFunctionName = (overrides and overrides.EntranceFunctionName) or currentRoom.EntranceFunctionName or "RoomEntranceStandard"
    if prevRoom ~= nil and prevRoom.NextRoomEntranceFunctionName ~= nil then
        roomEntranceFunctionName = prevRoom.NextRoomEntranceFunctionName
    end
    local args = currentRoom.EntranceFunctionArgs

    HookUtils.onPostFunctionOnce(roomEntranceFunctionName, function()
        local entranceFunction = _G[roomEntranceFunctionName]
        --entranceFunction(currentRun, currentRoom, args)
        -- TODO ADD ENTER Animation
        for playerId = 2, CoopPlayers.GetPlayersCount() do
            local hero = CoopPlayers.GetHero(playerId)
            if not hero or (hero and not hero.IsDead) then
                CoopCamera.ForceFocus(true)
                CoopPlayers.InitCoopUnit(playerId)
            end
        end
        CoopPlayers.UpdateMainHero()

        local mainHero = CoopPlayers.GetMainHero()
        local isMainPlayerDead = mainHero and mainHero.IsDead

        if currentRoom.HeroEndPoint then
            for playerId = 2, CoopPlayers.GetPlayersCount() do
                local hero = CoopPlayers.GetHero(playerId)
                if not hero.IsDead then
                    Teleport({ Id = hero.ObjectId, DestinationId = currentRoom.HeroEndPoint })
                    if isMainPlayerDead then
                        RemoveInputBlock({ PlayerIndex = playerId,  Name = "MoveHeroToRoomPosition" })
                    end
                end
            end
        end
    end)

    HookUtils.onPostFunctionOnce("SwitchActiveUnit", function()
        SwitchActiveUnit { PlayerIndex = 1, Id = CoopPlayers.GetMainHero().ObjectId }
    end)

    if RunEx.IsRunEnded() then
        HeroContext.RunWithHeroContext(CoopPlayers.GetMainHero(), StartRoomFun, run, currentRoom)
    else
        local hero = CoopPlayers.GetAliveHeroes()[1] or CoopPlayers.GetMainHero()
        HeroContext.RunWithHeroContext(hero, StartRoomFun, run, currentRoom)
    end
end

---@private
function RunHooks.StartNewRunWrapHook(StartNewRunFun, prevRun, args)
    local isNewGame = RunEx.WasTheFirstRunStarted()
    local newRun = StartNewRunFun(prevRun, args)
    HeroContext.InitRunHook()
    LootHooks.Reset(CoopPlayers.GetPlayersCount())
    CoopPlayers.SetMainHero(HeroContext.GetDefaultHero())

    if not isNewGame then
        CoopPlayers.RecreateAllAdditionalPlayers()
    end

    return newRun
end

---@private
function RunHooks.CreateRoomHooks()
    _CreateRoom = CreateRoom
    CreateRoom = function(...)
        local room = _CreateRoom(...)
        if not room.ZoomFraction then
            room.ZoomFraction = 0.6
        elseif room.ZoomFraction > 0.5 then
            room.ZoomFraction = room.ZoomFraction * 0.6
        end

        return room
    end
end

--- Bypass IsAlive check with this hook
---@private
function RunHooks.CheckRoomExitsReadyHook(baseFun, ...)
    local aliveHero = CoopPlayers.GetAliveHeroes()[1]
    if aliveHero then
        local result = false
        HeroContext.RunWithHeroContext(aliveHero, function(...)
            result = baseFun(...)
        end, ...)

        return result
    else
        return baseFun(...)
    end
end

function RunHooks.KillHeroHook(baseFun, ...)
    CurrentRun.Hero.IsDead = true
    local deadHero = CurrentRun.Hero
    local playerKilled = CoopPlayers.GetPlayerByHero(deadHero)
    
    -- Create a marker at death location for all players
    local deathMarker = SpawnObstacle({ Name = "InspectPoint", DestinationId = deadHero.ObjectId })
    deadHero.DeathMarker = deathMarker
    DebugPrint({ Text = "Created death marker for player " .. playerKilled .. " at ID:" .. tostring(deathMarker) })

    -- Store death marker and position for resurrection system
    ResurrectionSystem.DeathMarkers[playerKilled] = deathMarker
    ResurrectionSystem.DeathPositions[playerKilled] = deathMarker
    DebugPrint({ Text = "Stored death marker for player " .. playerKilled .. " at ID:" .. tostring(deathMarker) })

    -- Make the marker interactable
    UseableOn({ Id = deathMarker })
    SetAnimation({ Name = "GiftFoundFx", DestinationId = deathMarker }) -- Add a glowing effect
    -- Attach a table to the marker for OnUsed logic
    local markerTable = {
        IsResurrectionMarker = true,
        DeadHero = deadHero,
        PlayerKilled = playerKilled,
        OnUsedFunctionName = "CoopResurrectionMarkerUsed",
        UseText = "InGameUI_Use",
    }
    AttachLua({ Id = deathMarker, Table = markerTable })
    ActivatedObjects[deathMarker] = markerTable

    -- Spawn a ghost at the death position
    local ghostId = SpawnUnit({ Name = "NPC_3DGhostAlt", Group = "Standing", DestinationId = deathMarker, Angle = 15 })
    SetAnimation({ DestinationId = ghostId, Name = "3DGhostAltIdle" }) -- Play idle animation
    deadHero.DeathGhost = ghostId
    DebugPrint({ Text = "Spawned ghost for player " .. playerKilled .. " at ID:" .. tostring(ghostId) })
    
    if not CoopPlayers.HasAlivePlayers() then
        -- Handle death for player 1 only
        local mainHero = CoopPlayers.GetMainHero()
        RunHooks.ShowHero(mainHero, CurrentRun.Hero.ObjectId)
        HeroContext.RunWithHeroContext(mainHero, baseFun, ...)
        CoopPlayers.OnAllPlayersDead()
        return
    end
    if CurrentRun.Hero == CoopPlayers.GetMainHero() then
        RunHooks.HideHero(CurrentRun.Hero)

        local heroToChange = CoopPlayers.GetAliveHeroes()[1]
        HeroContext.SetDefaultHero(heroToChange)
    else
        local playerId = CoopPlayers.GetPlayerByHero(CurrentRun.Hero)
        if playerId then
            CoopRemovePlayerUnit(playerId)
        end
    end
    -- Unstuck AI
    EnemyAiHooks.RefreshAI()
end

---@private
function RunHooks.LeaveRoomHook(currentRun, door)
    -- Disables an extit door after use
    door.ReadyToUse = false

    -- Updates traits and health
    local nextRoom = door.Room
    local currentHero = CurrentRun.Hero
    for _, hero in CoopPlayers.PlayersIterator() do
        if hero ~= currentHero and not hero.IsDead then
            ClearEffect({ Id = hero.ObjectId, All = true, BlockAll = true, })
            StopCurrentStatusAnimation(hero)
            hero.BlockStatusAnimations = true

            if not nextRoom.BlockDoorHealFromPrevious then
                HeroContext.RunWithHeroContext(hero, CheckDoorHealTrait, currentRun)
            end

            local removedTraits = {}
            for _, trait in pairs(hero.Traits) do
                if trait.RemainingUses ~= nil and trait.UsesAsRooms ~= nil and trait.UsesAsRooms then
                    UseTraitData(hero, trait)
                    if trait.RemainingUses ~= nil and trait.RemainingUses <= 0 then
                        table.insert(removedTraits, trait)
                    end
                end
            end
            for _, trait in pairs(removedTraits) do
                RemoveTraitData(hero, trait)
            end
        end
    end
end

-- Clrears poison effects
---@private
function RunHooks.CheckForAllEnemiesDeadPostHook()
    for playerID = 2, CoopPlayers.GetPlayersCount() do
        local hero = CoopPlayers.GetHero(playerID)
        if hero and not hero.IsDead and hero.ObjectId then
            ClearEffect({ Id = hero.ObjectId, Name = "StyxPoison" })
            ClearEffect({ Id = hero.ObjectId, Name = "DamageOverTime" })
        end
    end
end

---@private
---@param hero table
function RunHooks.HideHero(hero)
    local weaponsToHide = { "RangedWeapon" }
    for _, weaponName in ipairs(WeaponSets.HeroMeleeWeapons) do
        if hero.Weapons[weaponName] then
            table.insert(weaponsToHide, weaponName)
        end
    end

    UnequipWeapon{ DestinationId = hero.ObjectId, Names = weaponsToHide }
    SetColor{ Id = hero.ObjectId, Color = { 255, 255, 255, 0 } }
    Teleport{ Id = hero.ObjectId, DestinationId = hero.ObjectId, OffsetX = -10000 }
end

---@private
---@param hero table
---@param position number
function RunHooks.ShowHero(hero, position)
    SetColor { Id = hero.ObjectId, Color = { 255, 255, 255, 255 } }
    Teleport { Id = hero.ObjectId, DestinationId = position }
end

---@private
function RunHooks.StartNewGameHook()
    if not HeroContext.GetDefaultHero() then
        HeroContext.InitRunHook()
    end
    CoopPlayers.SetMainHero(HeroContext.GetDefaultHero())
end

---@private
function RunHooks.RestoreUnlockRoomExitsHook()
    if not HeroContext.GetDefaultHero() then
        HeroContext.InitRunHook()
    end
    CoopPlayers.SetMainHero(HeroContext.GetDefaultHero())

    local spawnPoint = CurrentRun.CurrentRoom.HeroEndPoint or CoopPlayers.GetMainHero().ObjectId
    for playerId = 2, CoopPlayers.GetPlayersCount() do
        CoopPlayers.RestoreSavedHero(playerId)
        Teleport { Id = CoopPlayers.GetHero(playerId).ObjectId, DestinationId = spawnPoint }
    end

    SecondPlayerUi.UpdateHealthUI()
    SecondPlayerUi.RecreateLifePips()
end

function OpenResurrectionMenu(deadHero, playerKilled, marker, user)
    -- Build a lootData-like table for the resurrection menu
    local lootData = {
        Name = "ResurrectionMenu",
        UpgradeOptions = {
            {
                ItemName = "ResurrectButton",
                Type = "Resurrect",
                Title = "Resurrect Player",
                Description = "Bring your fallen ally back to life!",
                DeadHero = deadHero,
                PlayerKilled = playerKilled,
                Marker = marker,
                User = user,
            },
            {
                ItemName = "ResurrectButton2",
                Type = "Resurrect",
                Title = "Resurrect Player",
                Description = "Bring your fallen ally back to life!",
                DeadHero = deadHero,
                PlayerKilled = playerKilled,
                Marker = marker,
                User = user,
            },
            {
                ItemName = "ResurrectButton3",
                Type = "Resurrect",
                Title = "Resurrect Player",
                Description = "Bring your fallen ally back to life!",
                DeadHero = deadHero,
                PlayerKilled = playerKilled,
                Marker = marker,
                User = user,
            }
        },
        MenuTitle = "Revive Fallen Ally",
        FlavorTextIds = { "Revive your teammate by channeling your will!" },
        Icon = "BoonSymbolZeus", -- Just a placeholder icon
        LightingColor = { 100, 255, 100, 255 },
        LootColor = { 100, 255, 100, 255 },
        BoonGetColor = { 100, 255, 100, 255 },
    }
    OpenResurrectionChoiceMenu(lootData, user)
end

function OpenResurrectionChoiceMenu(lootData, user)
    -- Mimic OpenUpgradeChoiceMenu but for resurrection
    OnScreenOpened({Flag = "ResurrectionMenu", PersistCombatUI = true })
    FreezePlayerUnit("ResurrectionMenuOpen", { PlayerIndex = user.PlayerIndex, DisableTray = false })
    SetPlayerInvulnerable("ResurrectionMenuOpen", { PlayerIndex = user.PlayerIndex })
    SetConfigOption({ Name = "UseOcclusion", Value = false })
    SetConfigOption({ Name = "FreeFormSelectWrapY", Value = true })
    SetConfigOption({ Name = "ExclusiveInteractGroup", Value = nil })

    ScreenAnchors.ResurrectionMenu = { Components = {} }
    local screen = ScreenAnchors.ResurrectionMenu
    screen.Name = "ResurrectionMenu"
    local components = screen.Components

    EnableShopGamepadCursor( screen.Name, { PlayerIndex = user.PlayerIndex })

    screen.SubjectName = lootData.Name
    components.ShopBackgroundDim = CreateScreenComponent({ Name = "rectangle01", Group = "Combat_Menu" })
    components.ShopBackground = CreateScreenComponent({ Name = "BoonBox", Group = "Combat_Menu" })
    SetScale({ Id = components.ShopBackgroundDim.Id, Fraction = 4 })
    SetColor({ Id = components.ShopBackgroundDim.Id, Color = {0.15, 0.15, 0.15, 0.7} })
    wait(0.15)
    -- Title
    CreateTextBox({ Id = components.ShopBackground.Id, Text = lootData.MenuTitle or "Revive Fallen Ally",
        FontSize = 32,
        OffsetX = 0, OffsetY = -465,
        Color = Color.White,
        Font = "SpectralSCLightTitling",
        ShadowBlur = 0, ShadowColor = {0,0,0,1}, ShadowOffset={0, 3},
        OutlineThickness = 3,
        Justification = "Center"
    })
    -- Flavor Text
    if lootData.FlavorTextIds ~= nil then
        local flavorText = lootData.FlavorTextIds[1]
        CreateTextBox({ Id = components.ShopBackground.Id, Text = flavorText,
                FontSize = 16,
                OffsetY = -410, Width = 1040,
                Color = {0.698, 0.902, 0.514, 1.0},
                Font = "AlegreyaSansSCRegular",
                ShadowBlur = 0, ShadowColor = {0,0,0,0}, ShadowOffset={0, 3},
                Justification = "Center" })
    end
    -- Three resurrect buttons
    local buttonY1 = 370
    local buttonY2 = 570
    local buttonY3 = 770
    local buttonX = ScreenCenterX
    -- First button
    components.ResurrectButton = CreateScreenComponent({ Name = "BoonSlot1", Group = "Combat_Menu", X = buttonX, Y = buttonY1 })
    SetAnimation({ DestinationId = components.ResurrectButton.Id, Name = lootData.Icon .. "_Large" })
    SetScale({ Id = components.ResurrectButton.Id, Fraction = 0.85 })
    components.ResurrectButton.OnPressedFunctionName = "HandleResurrectionMenuSelection"
    components.ResurrectButton.Data = lootData.UpgradeOptions[1]
    components[components.ResurrectButton.Id] = "ResurrectButton"
    CreateTextBox({ Id = components.ResurrectButton.Id, Text = "Resurrect (100 Gold)",
        FontSize = 27,
        OffsetX = 0, OffsetY = -55,
        Color = Color.White,
        Font = "AlegreyaSansSCLight",
        ShadowBlur = 0, ShadowColor = {0,0,0,1}, ShadowOffset = {0, 2},
        Justification = "Center"
    })
    CreateTextBox({ Id = components.ResurrectButton.Id, Text = "Pay 100 gold to bring your fallen ally back to life!",
        OffsetX = 0, OffsetY = -30,
        Width = 675,
        Justification = "Center",
        VerticalJustification = "Top",
        LineSpacingBottom = 8,
        UseDescription = true,
        Format = "BaseFormat",
        TextSymbolScale = 0.8,
    })
    -- Second button
    components.ResurrectButton2 = CreateScreenComponent({ Name = "BoonSlot1", Group = "Combat_Menu", X = buttonX, Y = buttonY2 })
    SetAnimation({ DestinationId = components.ResurrectButton2.Id, Name = lootData.Icon .. "_Large" })
    SetScale({ Id = components.ResurrectButton2.Id, Fraction = 0.85 })
    components.ResurrectButton2.OnPressedFunctionName = "HandleResurrectionMenuSelection"
    components.ResurrectButton2.Data = lootData.UpgradeOptions[2]
    components[components.ResurrectButton2.Id] = "ResurrectButton2"
    CreateTextBox({ Id = components.ResurrectButton2.Id, Text = "Resurrect (-30 HP)",
        FontSize = 27,
        OffsetX = 0, OffsetY = -55,
        Color = Color.White,
        Font = "AlegreyaSansSCLight",
        ShadowBlur = 0, ShadowColor = {0,0,0,1}, ShadowOffset = {0, 2},
        Justification = "Center"
    })
    CreateTextBox({ Id = components.ResurrectButton2.Id, Text = "Lose 30 HP to bring your fallen ally back to life!",
        OffsetX = 0, OffsetY = -30,
        Width = 675,
        Justification = "Center",
        VerticalJustification = "Top",
        LineSpacingBottom = 8,
        UseDescription = true,
        Format = "BaseFormat",
        TextSymbolScale = 0.8,
    })
    -- Third button
    components.ResurrectButton3 = CreateScreenComponent({ Name = "BoonSlot1", Group = "Combat_Menu", X = buttonX, Y = buttonY3 })
    SetAnimation({ DestinationId = components.ResurrectButton3.Id, Name = lootData.Icon .. "_Large" })
    SetScale({ Id = components.ResurrectButton3.Id, Fraction = 0.85 })
    components.ResurrectButton3.OnPressedFunctionName = "HandleResurrectionMenuSelection"
    components.ResurrectButton3.Data = lootData.UpgradeOptions[3]
    components[components.ResurrectButton3.Id] = "ResurrectButton3"
    CreateTextBox({ Id = components.ResurrectButton3.Id, Text = "Resurrect (-20% Max HP for both)",
        FontSize = 27,
        OffsetX = 0, OffsetY = -55,
        Color = Color.White,
        Font = "AlegreyaSansSCLight",
        ShadowBlur = 0, ShadowColor = {0,0,0,1}, ShadowOffset = {0, 2},
        Justification = "Center"
    })
    CreateTextBox({ Id = components.ResurrectButton3.Id, Text = "Both players lose 20% of their max health to bring your fallen ally back to life!",
        OffsetX = 0, OffsetY = -30,
        Width = 675,
        Justification = "Center",
        VerticalJustification = "Top",
        LineSpacingBottom = 8,
        UseDescription = true,
        Format = "BaseFormat",
        TextSymbolScale = 0.8,
    })
    -- Add graphical return button (bottom center)
    components.CloseButton = CreateScreenComponent({ Name = "ButtonClose", Group = "Combat_Menu", Scale = 0.7, X = ScreenCenterX, Y = 950 })
    components.CloseButton.OnPressedFunctionName = "HandleResurrectionMenuReturn"
    components.CloseButton.Data = { User = user }
    components.CloseButton.ControlHotkey = "Cancel"
    TeleportCursor({ OffsetX = buttonX, OffsetY = buttonY1, ForceUseCheck = true })
    screen.KeepOpen = true
    screen.User = user
    thread( HandleWASDInput, screen )
    HandleScreenInput( screen )
end

function HandleResurrectionMenuSelection(screen, button)
    local data = button.Data
    -- If first button, require 100 gold
    if data.ItemName == "ResurrectButton" then
        if not CurrentRun.Money or CurrentRun.Money < 100 then
            -- Not enough gold, play error sound and do nothing
            PlaySound({ Name = "/Leftovers/SFX/OutOfAmmo" })
            return
        else
            -- Deduct gold
            CurrentRun.Money = CurrentRun.Money - 100
        end
    end
    -- If second button, require -30 HP from the resurrecting player
    if data.ItemName == "ResurrectButton2" then
        local playerIndex = (data.User and data.User.PlayerIndex) or 1
        local resurrector = CoopPlayers.GetHero(playerIndex)
        if not resurrector or not resurrector.Health or resurrector.Health <= 30 then
            -- Not enough HP, play error sound and do nothing
            PlaySound({ Name = "/Leftovers/SFX/OutOfAmmo" })
            return
        else
            resurrector.Health = resurrector.Health - 30
            -- Optionally, play a hurt animation or effect here
            if SecondPlayerUi and SecondPlayerUi.UpdateHealthUI then
                SecondPlayerUi.UpdateHealthUI()
            end
            if UIData and UIData.UpdateHealthUI then
                UIData.UpdateHealthUI()
            end
        end
    end
    -- If third button, -20% max health for both players
    if data.ItemName == "ResurrectButton3" then
        local hero1 = CoopPlayers.GetHero(1)
        local hero2 = CoopPlayers.GetHero(2)
        local function canLose20Percent(hero)
            if not hero or not hero.MaxHealth then return false end
            local loss = math.floor(hero.MaxHealth * 0.2)
            return (hero.MaxHealth - loss) >= 1
        end
        if not canLose20Percent(hero1) or not canLose20Percent(hero2) then
            PlaySound({ Name = "/Leftovers/SFX/OutOfAmmo" })
            return
        else
            local function applyLoss(hero)
                local loss = math.floor(hero.MaxHealth * 0.2)
                hero.MaxHealth = hero.MaxHealth - loss
                if hero.Health > hero.MaxHealth then
                    hero.Health = hero.MaxHealth
                end
            end
            applyLoss(hero1)
            applyLoss(hero2)
            if SecondPlayerUi and SecondPlayerUi.UpdateHealthUI then
                SecondPlayerUi.UpdateHealthUI()
            end
            if UIData and UIData.UpdateHealthUI then
                UIData.UpdateHealthUI()
            end
        end
    end
    -- Pass resurrection data to close
    CloseResurrectionMenu(screen, button, data.User, data)
end

function CloseResurrectionMenu(screen, button, user, resurrectionData)
    if not user then
        user = screen.User -- fallback if not passed
    end
    DisableShopGamepadCursor( screen.Name, { PlayerIndex = user and user.PlayerIndex or 1 })
    SetConfigOption({ Name = "FreeFormSelectWrapY", Value = false })
    SetAnimation({ DestinationId = screen.Components.ShopBackground.Id, Name = "BoonSelectOut" })
    UseableOff({ Id = screen.Components.ResurrectButton.Id, ForceHighlightOff = true })
    CloseScreen( GetAllIds( screen.Components ), 0.25 )
    PlaySound({ Name = "/SFX/Menu Sounds/GeneralWhooshMENU" })
    UnfreezePlayerUnit("ResurrectionMenuOpen", { PlayerIndex = user and user.PlayerIndex or 1 })
    SetPlayerVulnerable("ResurrectionMenuOpen", { PlayerIndex = user and user.PlayerIndex or 1 })
    SetConfigOption({ Name = "UseOcclusion", Value = true })
    screen.KeepOpen = false
    OnScreenClosed({Flag = "ResurrectionMenu"})
    ScreenAnchors.ResurrectionMenu = nil
    -- Reset all players' controls after closing the menu
    CoopControl.ResetAllPlayers()
    -- Trigger resurrection after menu is fully closed
    if resurrectionData and resurrectionData.DeadHero and resurrectionData.PlayerKilled then
        ResurrectionSystem.ReviveHero(resurrectionData.DeadHero, resurrectionData.PlayerKilled)
        if resurrectionData.Marker and resurrectionData.Marker.ObjectId then
            UseableOff({ Id = resurrectionData.Marker.ObjectId })
        end
    end
end

function HandleResurrectionMenuReturn(screen, button)
    CloseResurrectionMenu(screen, button, button.Data.User)
end

function CoopResurrectionMarkerUsed(marker, args, user)
    -- Only allow living players to use the marker
    if not user or user.IsDead then return end
    if not marker or not marker.IsResurrectionMarker then return end
    local deadHero = marker.DeadHero
    local playerKilled = marker.PlayerKilled
    if not deadHero or not playerKilled then return end
    -- Switch menu control to the interacting player
    local playerId = CoopPlayers.GetPlayerByHero(user)
    CoopControl.SwitchControlForMenu(playerId)
    -- Open the resurrection menu instead of reviving immediately
    OpenResurrectionMenu(deadHero, playerKilled, marker, user)
end

return RunHooks
