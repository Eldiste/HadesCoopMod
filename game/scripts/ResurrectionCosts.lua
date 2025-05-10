-- ResurrectionCosts.lua
-- Handles resurrection button definitions and payment logic

local CoopPlayers = ModRequire "CoopPlayers.lua"
local SecondPlayerUi = ModRequire "SecondPlayerUI.lua"

local ResurrectionCosts = {}

local function updateHealthUI()
    if SecondPlayerUi and SecondPlayerUi.UpdateHealthUI then
        SecondPlayerUi.UpdateHealthUI()
    end
    if UIData and UIData.UpdateHealthUI then
        UIData.UpdateHealthUI()
    end
end

ResurrectionCosts.Options = {
    {
        ItemName = "ResurrectButton",
        Label = "Resurrect (100 Gold)",
        Description = "Pay 100 gold to bring your fallen ally back to life!",
        CanAfford = function(user)
            return CurrentRun.Money and CurrentRun.Money >= 100
        end,
        Pay = function(user)
            CurrentRun.Money = CurrentRun.Money - 100
        end,
        OnFail = function()
            PlaySound({ Name = "/Leftovers/SFX/OutOfAmmo" })
        end,
    },
    {
        ItemName = "ResurrectButton2",
        Label = "Resurrect (-30 HP)",
        Description = "Lose 30 HP to bring your fallen ally back to life!",
        CanAfford = function(user)
            local playerIndex = (user and user.PlayerIndex) or 1
            local hero = CoopPlayers.GetHero(playerIndex)
            return hero and hero.Health and hero.Health > 30
        end,
        Pay = function(user)
            local playerIndex = (user and user.PlayerIndex) or 1
            local hero = CoopPlayers.GetHero(playerIndex)
            hero.Health = hero.Health - 30
            updateHealthUI()
        end,
        OnFail = function()
            PlaySound({ Name = "/Leftovers/SFX/OutOfAmmo" })
        end,
    },
    {
        ItemName = "ResurrectButton3",
        Label = "Resurrect (-20% Max HP for both)",
        Description = "Both players lose 20% of their max health to bring your fallen ally back to life!",
        CanAfford = function(user)
            local function canLose20Percent(hero)
                if not hero or not hero.MaxHealth then return false end
                local loss = math.floor(hero.MaxHealth * 0.2)
                return (hero.MaxHealth - loss) >= 1
            end
            return canLose20Percent(CoopPlayers.GetHero(1)) and canLose20Percent(CoopPlayers.GetHero(2))
        end,
        Pay = function(user)
            local function applyLoss(hero)
                local loss = math.floor(hero.MaxHealth * 0.2)
                hero.MaxHealth = hero.MaxHealth - loss
                if hero.Health > hero.MaxHealth then
                    hero.Health = hero.MaxHealth
                end
            end
            applyLoss(CoopPlayers.GetHero(1))
            applyLoss(CoopPlayers.GetHero(2))
            updateHealthUI()
        end,
        OnFail = function()
            PlaySound({ Name = "/Leftovers/SFX/OutOfAmmo" })
        end,
    },
}

function ResurrectionCosts.GetOptions(deadHero, playerKilled, marker, user)
    local options = {}
    for _, opt in ipairs(ResurrectionCosts.Options) do
        local copy = {
            ItemName = opt.ItemName,
            Type = "Resurrect",
            Title = "Resurrect Player",
            Description = opt.Description,
            DeadHero = deadHero,
            PlayerKilled = playerKilled,
            Marker = marker,
            User = user,
            Label = opt.Label,
            CanAfford = opt.CanAfford,
            Pay = opt.Pay,
            OnFail = opt.OnFail,
        }
        table.insert(options, copy)
    end
    return options
end

return ResurrectionCosts 