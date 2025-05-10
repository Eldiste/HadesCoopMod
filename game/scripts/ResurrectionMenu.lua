-- ResurrectionMenu.lua
-- Handles resurrection menu UI and selection logic

local ResurrectionCosts = ModRequire "ResurrectionCosts.lua"
local CoopControl = ModRequire "CoopControl.lua"
local CoopPlayers = ModRequire "CoopPlayers.lua"
local SecondPlayerUi = ModRequire "SecondPlayerUI.lua"
local ResurrectionSystem = ModRequire "ResurrectionSystem.lua"

local ResurrectionMenu = {}

function ResurrectionMenu.OpenResurrectionMenu(deadHero, playerKilled, marker, user)
    -- Build lootData-like table for the resurrection menu using ResurrectionCosts
    local lootData = {
        Name = "ResurrectionMenu",
        UpgradeOptions = ResurrectionCosts.GetOptions(deadHero, playerKilled, marker, user),
        MenuTitle = "Revive Fallen Ally",
        FlavorTextIds = { "Revive your teammate by channeling your will!" },
        Icon = "BoonSymbolZeus", -- Just a placeholder icon
        LightingColor = { 100, 255, 100, 255 },
        LootColor = { 100, 255, 100, 255 },
        BoonGetColor = { 100, 255, 100, 255 },
    }
    ResurrectionMenu.OpenResurrectionChoiceMenu(lootData, user)
end

function ResurrectionMenu.OpenResurrectionChoiceMenu(lootData, user)
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
    -- Dynamically create resurrection buttons
    local buttonY = 370
    local buttonSpacing = 200
    local buttonX = ScreenCenterX
    for i, option in ipairs(lootData.UpgradeOptions) do
        local btnKey = "ResurrectButton" .. tostring(i)
        components[btnKey] = CreateScreenComponent({ Name = "BoonSlot1", Group = "Combat_Menu", X = buttonX, Y = buttonY })
        SetAnimation({ DestinationId = components[btnKey].Id, Name = lootData.Icon .. "_Large" })
        SetScale({ Id = components[btnKey].Id, Fraction = 0.85 })
        components[btnKey].OnPressedFunctionName = "HandleResurrectionMenuSelection"
        components[btnKey].Data = option
        components[components[btnKey].Id] = btnKey
        CreateTextBox({ Id = components[btnKey].Id, Text = option.Label,
            FontSize = 27,
            OffsetX = 0, OffsetY = -55,
            Color = Color.White,
            Font = "AlegreyaSansSCLight",
            ShadowBlur = 0, ShadowColor = {0,0,0,1}, ShadowOffset = {0, 2},
            Justification = "Center"
        })
        CreateTextBox({ Id = components[btnKey].Id, Text = option.Description,
            OffsetX = 0, OffsetY = -30,
            Width = 675,
            Justification = "Center",
            VerticalJustification = "Top",
            LineSpacingBottom = 8,
            UseDescription = true,
            Format = "BaseFormat",
            TextSymbolScale = 0.8,
        })
        buttonY = buttonY + buttonSpacing
    end
    -- Add graphical return button (bottom center)
    components.CloseButton = CreateScreenComponent({ Name = "ButtonClose", Group = "Combat_Menu", Scale = 0.7, X = ScreenCenterX, Y = 950 })
    components.CloseButton.OnPressedFunctionName = "HandleResurrectionMenuReturn"
    components.CloseButton.Data = { User = user }
    components.CloseButton.ControlHotkey = "Cancel"
    TeleportCursor({ OffsetX = buttonX, OffsetY = 370, ForceUseCheck = true })
    screen.KeepOpen = true
    screen.User = user
    thread( HandleWASDInput, screen )
    HandleScreenInput( screen )
end

function ResurrectionMenu.HandleResurrectionMenuSelection(screen, button)
    local data = button.Data
    -- Use the cost logic from ResurrectionCosts
    if data.CanAfford and not data.CanAfford(data.User) then
        if data.OnFail then data.OnFail() end
        return
    end
    if data.Pay then data.Pay(data.User) end
    -- Pass resurrection data to close
    ResurrectionMenu.CloseResurrectionMenu(screen, button, data.User, data)
end

function ResurrectionMenu.HandleResurrectionMenuReturn(screen, button)
    ResurrectionMenu.CloseResurrectionMenu(screen, button, button.Data.User)
end

function ResurrectionMenu.CloseResurrectionMenu(screen, button, user, resurrectionData)
    if not user then
        user = screen.User -- fallback if not passed
    end
    DisableShopGamepadCursor( screen.Name, { PlayerIndex = user and user.PlayerIndex or 1 })
    SetConfigOption({ Name = "FreeFormSelectWrapY", Value = false })
    SetAnimation({ DestinationId = screen.Components.ShopBackground.Id, Name = "BoonSelectOut" })
    -- Loop over all resurrection buttons and disable them
    for i = 1, 3 do
        local btnKey = "ResurrectButton" .. tostring(i)
        if screen.Components[btnKey] and screen.Components[btnKey].Id then
            UseableOff({ Id = screen.Components[btnKey].Id, ForceHighlightOff = true })
        end
    end
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

return ResurrectionMenu 