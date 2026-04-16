-- [ README: Customization ] --
-- If you want to make customizations to this file, please put it
-- into your: MacroQuest/configs/rgmercs/class_configs/ directory
-- so it is not patched over.

-- [ NOTE ON ORDERING ] --
-- Order matters! Lua will implicitly iterate everything in an array
-- in order by default so always put the first thing you want checked
-- towards the top of the list.

local mq           = require('mq')
local Config       = require('utils.config')
local Globals      = require('utils.globals')
local Core         = require("utils.core")
local Targeting    = require("utils.targeting")
local Casting      = require("utils.casting")
local Comms        = require("utils.comms")
local Logger       = require("utils.logger")

local _ClassConfig = {
    _version            = "Alpha 1.1 - Live (Modern Era DPS Only)",
    _author             = "Algar",
    ['Modes']           = {
        'ModernEra',
    },
    ['ModeChecks']      = {
        CanMez = function() return true end,
        IsCuring = function() return Config:GetSetting('DoCureSpells') end,
        IsMezzing = function() return Config:GetSetting('MezOn') end,
        -- necro can AA Rez
        IsRezing = function() return Config:GetSetting('BattleRez') or Targeting.GetXTHaterCount() == 0 end,
    },
    ['Cures']           = {
        GetCureSpells = function(self)
            self.TempSettings.CureSpells = {}
            local diseaseSpell = Core.GetResolvedActionMapItem("CureDisease") or mq.TLO.Spell("Cure Disease")
            if diseaseSpell then
                self.TempSettings.CureSpells.Disease = diseaseSpell
            else
                Logger.log_debug("GetCureSpells: Could not resolve CureDisease/Cure Disease (not mapped or not scribed).")
            end
            local poisonSpell = Core.GetResolvedActionMapItem("CurePoison") or mq.TLO.Spell("Cure Poison")
            if poisonSpell then
                self.TempSettings.CureSpells.Poison = poisonSpell
            else
                Logger.log_debug("GetCureSpells: Could not resolve CurePoison/Cure Poison (not mapped or not scribed).")
            end
        end,
        CureNow = function(self, type, targetId)
            if (mq.TLO.Me.CombatState() or ""):lower() == "combat" then
                -- Request was to only cure out of combat.
                return false, true
            end
            if not Config:GetSetting('DoCureSpells') then return false, false end
            local cureType = (type or ""):lower()
            if cureType ~= "disease" and cureType ~= "poison" then return false, true end

            local targetSpawn = mq.TLO.Spawn(targetId)
            if not (targetSpawn and targetSpawn()) then return false, true end
            local hasCounter = false
            local counterReadable = false

            -- Prefer Actor heartbeat data for peer cures when available/recent.
            if targetId ~= mq.TLO.Me.ID() then
                local actorPeers = Comms.GetAllPeerHeartbeats(false) or {}
                for _, heartbeat in pairs(actorPeers) do
                    local data = heartbeat and heartbeat.Data
                    local recentHeartbeat = (Globals.GetTimeSeconds() - (heartbeat.LastHeartbeat or 0)) <= 3
                    if data and recentHeartbeat and tonumber(data.ID or 0) == tonumber(targetId or 0) then
                        local actorCounter = cureType == "poison" and tonumber(data.Poison or "0") or tonumber(data.Disease or "0")
                        if actorCounter ~= nil then
                            counterReadable = true
                            hasCounter = actorCounter > 0
                        end
                        break
                    end
                end
            end

            local ok, counterValue = pcall(function()
                if targetId == mq.TLO.Me.ID() then
                    if cureType == "poison" then
                        return mq.TLO.Me.Poisoned.ID() or 0
                    end
                    return mq.TLO.Me.Diseased.ID() or 0
                end
                if cureType == "poison" then
                    return targetSpawn.Poisoned.ID() or 0
                end
                return targetSpawn.Diseased.ID() or 0
            end)
            if ok then
                counterReadable = true
                if not hasCounter and (counterValue or 0) > 0 then
                    hasCounter = true
                elseif hasCounter and (counterValue or 0) <= 0 then
                    -- If either source can read "no typed counter", treat it as no-match.
                    hasCounter = false
                end
            end

            -- If available, use TotalCounters as a stronger signal to avoid curing non-counter detrimentals (e.g. some snares).
            local okTotal, totalCounters = pcall(function()
                if targetId == mq.TLO.Me.ID() then
                    return mq.TLO.Me.TotalCounters() or 0
                end
                return targetSpawn.TotalCounters() or 0
            end)
            if okTotal then
                counterReadable = true
                if (totalCounters or 0) <= 0 then
                    hasCounter = false
                elseif not hasCounter then
                    -- We have counters present but couldn't read typed counter reliably; allow by requested type.
                    hasCounter = true
                end
            end
            if not hasCounter then
                -- Some client builds do not expose disease/poison counters reliably on other PCs.
                -- For Disease specifically, fail closed to avoid curing non-counter detrimentals (ex: some snares).
                -- Poison keeps fallback behavior for compatibility with peers where counters are opaque.
                if targetId ~= mq.TLO.Me.ID() and not counterReadable and cureType == "poison" then
                    Logger.log_debug("CureNow: %s counter not readable on %s; trusting requested type for poison.", cureType, targetSpawn.CleanName() or "Unknown")
                else
                    Logger.log_debug("CureNow: Skipping cure on %s - no %s counters found.", targetSpawn.CleanName() or "Unknown", cureType)
                    return false, true
                end
            end

            local cureKey = cureType == "poison" and "Poison" or "Disease"
            local defaultSpellName = cureType == "poison" and "Cure Poison" or "Cure Disease"
            local cureSpell = self.TempSettings.CureSpells and self.TempSettings.CureSpells[cureKey]
            local spellName = defaultSpellName
            if cureSpell and cureSpell() and cureSpell.RankName then
                spellName = cureSpell.RankName() or spellName
            end

            if not mq.TLO.Me.Book(spellName)() and not mq.TLO.Me.Book(defaultSpellName)() then
                Logger.log_debug("CureNow: %s is not in spell book.", defaultSpellName)
                return false, false
            end

            Logger.log_debug("CureNow: Using %s for %s on %s.", spellName, cureType, targetSpawn.CleanName() or "Unknown")
            return Casting.UseSpell(spellName, targetId, true), true
        end,
    },
    ['Themes']          = {
        ['DPS'] = {
            { element = ImGuiCol.TitleBgActive,    color = { r = 0.5, g = 0.05, b = 1.0, a = .8, }, },
            { element = ImGuiCol.TableHeaderBg,    color = { r = 0.4, g = 0.05, b = 0.8, a = .8, }, },
            { element = ImGuiCol.Tab,              color = { r = 0.2, g = 0.05, b = 0.6, a = .8, }, },
            { element = ImGuiCol.TabSelected,      color = { r = 0.2, g = 0.05, b = 0.6, a = .8, }, },
            { element = ImGuiCol.TabHovered,       color = { r = 0.2, g = 0.05, b = 0.6, a = 1.0, }, },
            { element = ImGuiCol.Header,           color = { r = 0.1, g = 0.05, b = 0.5, a = .8, }, },
            { element = ImGuiCol.HeaderActive,     color = { r = 0.2, g = 0.05, b = 0.6, a = .8, }, },
            { element = ImGuiCol.HeaderHovered,    color = { r = 0.2, g = 0.05, b = 0.6, a = 1.0, }, },
            { element = ImGuiCol.FrameBgHovered,   color = { r = 0.2, g = 0.05, b = 0.6, a = 0.7, }, },
            { element = ImGuiCol.Button,           color = { r = 0.1, g = 0.05, b = 0.5, a = .8, }, },
            { element = ImGuiCol.ButtonActive,     color = { r = 0.2, g = 0.05, b = 0.6, a = .8, }, },
            { element = ImGuiCol.ButtonHovered,    color = { r = 0.2, g = 0.05, b = 0.6, a = 1.0, }, },
            { element = ImGuiCol.TextSelectedBg,   color = { r = 0.1, g = 0.05, b = 0.5, a = .1, }, },
            { element = ImGuiCol.FrameBg,          color = { r = 0.1, g = 0.05, b = 0.5, a = .8, }, },
            { element = ImGuiCol.SliderGrab,       color = { r = 0.5, g = 0.05, b = 1.0, a = .8, }, },
            { element = ImGuiCol.SliderGrabActive, color = { r = 0.5, g = 0.05, b = 1.0, a = .9, }, },
            { element = ImGuiCol.FrameBgActive,    color = { r = 0.2, g = 0.05, b = 0.6, a = 1.0, }, },
        },
    },
    ['CommandHandlers'] = {
        startlich = {
            usage = "/rgl startlich",
            about = "Start your Lich Spell [Note: This will enabled DoLich if it is not already].",
            handler =
                function(self)
                    Config:SetSetting('DoLich', true)
                    Core.SafeCallFunc("Start Necro Lich", self.ClassConfig.HelperFunctions.StartLich, self)

                    return true
                end,
        },
        stoplich = {
            usage = "/rgl stoplich",
            about = "Stop your Lich and Flesh Spell [Note: This will NOT disable DoLich].",
            handler =
                function(self)
                    Core.SafeCallFunc("Stop Lich Spell", self.ClassConfig.HelperFunctions.CancelLich, self)
                    Core.SafeCallFunc("Stop Flesh Buff", self.ClassConfig.HelperFunctions.CancelFlesh, self)
                    return true
                end,
        },
    },
    ['ItemSets']        = {
        ['Epic'] = {
            "Deathwhisper",
            "Soulwhisper",
        },
        ['OoW_Chest'] = {
            "Blightbringer's Tunic of the Grave",
            "Deathcaller's Robe",
        },
    },
    ['AbilitySets']     = {
        ['SelfHPBuff'] = {
            "Shielding XXIII",
            "Shield of Memories",
            "Shield of Shadow",
            "Shield of Restless Ice",
            "Shield of Scales",
            "Shield of the Pellarus",
            "Shield of the Dauntless",
            "Shield of Bronze",
            "Shield of Dreams",
            "Shield of the Void",
            "Bulwark of the Crystalwing",
            "Shield of the Crystalwing",
            "Ether Shield",
            "Shield of Maelin",
            "Shield of the Arcane",
            "Shield of the Magi",
            "Arch Shielding",
            "Greater Shielding",
            "Major Shielding",
            "Shielding",
            "Lesser Shielding",
            "Minor Shielding",
        },
        ['SelfRune1'] = {
            "Wraithskin XIII",
            "Golemskin",
            "Carrion Skin",
            "Frozen Skin",
            "Ashen Skin",
            "Deadskin",
            "Zombieskin",
            "Ghoulskin",
            "Grimskin",
            "Corpseskin",
            "Shadowskin",
            "Wraithskin",
        },
        ['SelfSpellShield1'] = {
            "Shield of Fate VII",
            "Shield of Inescapability",
            "Shield of Inevitability",
            "Shield of Destiny",
            "Shield of Order",
            "Shield of Consequence",
            "Shield of Fate",
        },
        ['FDSpell'] = {
            -- Fd Spell
            "Death Peace",
            "Feign Death",
        },
        ['HarmShieldSpell'] = {
            "Harmshield",
            "Harm Shield",
        },
        ---DPS
        ['AllianceSpell'] = {
            -- Alliance Spells
            "Malevolent Covariance",
            "Malevolent Conjunction",
            "Malevolent Coalition",
            "Malevolent Covenant",
            "Malevolent Alliance",
        },
        ['DichoSpell'] = {
            ---DichoSpell >= LVL101
            "Ecliptic Paroxysm",
            "Composite Paroxysm",
            "Dissident Paroxysm",
            "Dichotomic Paroxysm",
            "Reciprocal Paroxysm",
        },
        ['SwarmPet'] = {
            ---SwarmPet >= LVL85
            "Call Raging Skeleton X",
            "Call Ravening Skeleton",
            "Call Roiling Skeleton",
            "Call Riotous Skeleton",
            "Call Reckless Skeleton",
            "Call Remorseless Skeleton",
            "Call Relentless Skeleton",
            "Call Ruthless Skeleton",
            "Call Ruinous Skeleton",
            "Call Rumbling Skeleton",
            "Call Skeleton Thrall",
            "Call Skeleton Mass",
            "Call Skeleton Horde",
            "Call Skeleton Army",
            "Call Skeleton Mob",
            "Call Skeleton Throng",
            "Call Skeleton Host",
            "Call Skeleton Crush",
            "Call Skeleton Swarm",
        },
        ['HealthTaps'] = {
            ---HealthTaps >= LVL1
            "Drain Essence XXIII",
            "Extort Essence",
            "Maraud Essence",
            "Draw Essence",
            "Consume Essence",
            "Hemorrhage Essence",
            "Plunder Essence",
            "Bleed Essence",
            "Divert Essence",
            "Drain Essence",
            "Siphon Essence",
            "Drain Life",
            -- [] =["Ancient: Touch of Orshilak",
            "Soulspike",
            "Touch of Mujaki",
            "Touch of Night",
            "Deflux",
            "Drain Soul",
            "Drain Spirit",
            "Spirit Tap",
            "Siphon Life",
            "Lifedraw",
            "Lifespike",
            "Lifetap",
        },
        ['SoulTaps'] = {
            ---HealthTaps >= LVL1
            "Soulrip VII",
            "Soullash",
            "Soulflay",
            "Soulgouge",
            "Soulsiphon",
            "Soulrend",
        },
        ['DurationTap'] = {
            ---DurationTap >= LVL29
            "Sharosh's Grasp",
            "Helmsbane's Grasp",
            "The Protector's Grasp",
            "Tserrina's Grasp",
            "Bomoda's Grasp",
            "Plexipharia's Grasp",
            "Halstor's Grasp",
            "Ivrikdal's Grasp",
            "Arachne's Grasp",
            "Fellid's Grasp",
            "Visziaj's Grasp",
            "Dyn`leth's Grasp",
            "Fang of Death",
            "Night's Beckon",
            "Saryrn's Kiss",
            "Vexing Mordinia",
            "Bond of Death",
            "Vampiric Curse",
        },
        ['GroupLeech'] = {
            ---GroupLeech >= LVL9
            "Dark Leech VIII",
            "Ghastly Leech",
            "Twilight Leech",
            "Frozen Leech",
            "Ashen Leech",
            "Dark Leech",
            "Leech",
        },
        ['ManaDrain'] = {
            --Mana Drain with Group Mana Recourse
            "Mind Wrack XIV",
            "Mind Disintegrate",
            "Mind Atrophy",
            "Mind Erosion",
            "Mind Exorciation",
            "Mind Extraction",
            "Mind Strip",
            "Mind Abrasion",
            "Thought Flay",
            "Mind Decomposition",
            "Mental Vivisection",
            "Mind Dissection",
            "Mind Flay",
            "Mind Wrack",
        },
        ['CureDisease'] = {
            "Cure Disease",
        },
        ['CurePoison'] = {
            "Cure Poison",
        },
        ['MezSpell'] = {
            -- Screaming Terror line (single-target mez)
            "Screaming Terror XIII",
            "Horrifying Shriek",
            "Lunatic Shriek",
            "Nightmarish Shriek",
            "Hair-Raising Shriek",
            "Dreadful Shriek",
            "Foreboding",
            "Dread",
            "Dismay",
            "Bone-Rattling Shriek",
            "Spine-Chilling Shriek",
            "Bloodcurdling Shriek",
            "Screaming Terror",
        },
        ['PoisonNuke1'] = {
            ---PoisonNuke >=LVL21
            "Schisming Venin",
            "Necrotizing Venin",
            "Embalming Venin",
            "Searing Venin",
            "Effluvial Venin",
            "Liquefying Venin",
            "Dissolving Venin",
            "Blighted Venin",
            "Withering Venin",
            "Ruinous Venin",
            "Venin",
            "Acikin",
            "Neurotoxin",
            "Torbas' Venom Blast",
            "Torbas' Poison Blast",
            "Torbas' Acid Blast",
            "Shock of Poison",
        },
        ['PoisonNuke2'] = {
            ---PoisonNuke2  >=LVL 75 (DD Increase chance)
            "Call for Blood XIII",
            "Decree for Blood",
            "Proclamation for Blood",
            "Assert for Blood",
            "Refute for Blood",
            "Impose for Blood",
            "Impel for Blood",
            --"Provocation for Blood",
            "Compel for Blood",
            "Exigency for Blood",
            "Supplication of Blood",
            "Demand for Blood",
            "Call for Blood",
        },
        ['FireNuke'] = {
            ---Fire Nuke, undead conversion and short stun, 90+
            "Ignite Bones XIII", -- Level 130
            "Immolate Bones",    -- Level 125
            "Cremate Bones",     -- Level 120
            "Char Bones",        -- Level 115
            "Burn Bones",        -- Level 110
            "Combust Bones",     -- Level 105
            "Scintillate Bones", -- Level 100
            "Coruscate Bones",   -- Level 95
            "Scorch Bones",      -- Level 90
        },
        ['FireDot1'] = {
            ---FireDot1 >= LVL80
            "Searing Shadow XI",
            "Raging Shadow",
            "Scalding Shadow",
            "Broiling Shadow",
            "Burning Shadow",
            "Smouldering Shadow",
            "Coruscating Shadow",
            "Blazing Shadow",
            "Blistering Shadow",
            "Scorching Shadow",
            "Searing Shadow",
        },
        ['FireDot2'] = {
            ---FireDot2 >= LVL10
            "Dread Pyre XIII",
            "Pyre of Illandrin",
            "Pyre of Va Xakra",
            "Pyre of Klraggek",
            "Pyre of the Shadewarden",
            "Pyre of Jorobb",
            "Pyre of Marnek",
            "Pyre of Hazarak",
            "Pyre of Nos",
            "Soul Reaper's Pyre",
            "Reaver's Pyre",
            "Ashengate Pyre",
            "Dread Pyre",
            "Night Fire",
            "Funeral Pyre of Kelador",
            "Pyrocruor",
            "Ignite Blood",
            "Boil Blood",
            "Heat Blood",
        },
        ['Fear'] = {
            "Invoke Fear",
        },
        ['FireDot2_2'] = {
            ---FireDot2 >= LVL10
            "Dread Pyre XIII",
            "Pyre of Illandrin",
            "Pyre of Va Xakra",
            "Pyre of Klraggek",
            "Pyre of the Shadewarden",
            "Pyre of Jorobb",
            "Pyre of Marnek",
            "Pyre of Hazarak",
            "Pyre of Nos",
            "Soul Reaper's Pyre",
            "Reaver's Pyre",
            "Ashengate Pyre",
            "Dread Pyre",
            "Night Fire",
            "Funeral Pyre of Kelador",
            "Pyrocruor",
            "Ignite Blood",
            "Boil Blood",
            "Heat Blood",
        },
        ['FireDot3'] = {
            ---FireDot3 >= LVL88 (QuickDOT)
            "Marith's Flashblaze",
            "Arcanaforged's Flashblaze",
            "Thall Va Kelun's Flashblaze",
            "Otatomik's Flashblaze",
            "Azeron's Flashblaze",
            "Mazub's Flashblaze",
            "Osalur's Flashblaze",
            "Brimtav's Flashblaze",
            "Tenak's Flashblaze",
        },
        ['FireDot4'] = {
            ---FireDot4 >= LVL73 DOT
            "Pyre of Mori XIX",
            "Pyre of the Abandoned",
            "Pyre of the Neglected",
            "Pyre of the Wretched",
            "Pyre of the Fereth",
            "Pyre of the Lost",
            "Pyre of the Forsaken",
            "Pyre of the Piq'a",
            "Pyre of the Bereft",
            "Pyre of the Forgotten",
            "Pyre of the Lifeless",
            "Pyre of the Fallen",
        },
        ['Magic1'] = {
            ---Magic1 >= LVL51 SlowDot
            "Necrotizing Wounds VIII",
            "Putrefying Wounds",
            "Infected Wounds",
            "Septic Wounds",
            "Cytotoxic Wounds",
            "Mortiferous Wounds",
            "Pernicious Wounds",
            "Necrotizing Wounds",
            "Splirt",
            "Splart",
            "Splort",
            "Splurt",
        },
        ['Magic2'] = {
            ---Magic2 >=LVL67 DOT
            "Horror XV",
            "Extermination",
            "Extinction",
            "Oblivion",
            "Inevitable End",
            "Annihilation",
            "Termination",
            "Doom",
            "Demise",
            "Mortal Coil",
            "Anathema of Life",
            "Curse of Mortality",
            "Ancient: Curse of Mori",
            "Dark Nightmare",
            "Horror",
        },
        ['Magic2_2'] = {
            ---Magic2 >=LVL67 DOT
            "Horror XV",
            "Extermination",
            "Extinction",
            "Oblivion",
            "Inevitable End",
            "Annihilation",
            "Termination",
            "Doom",
            "Demise",
            "Mortal Coil",
            "Anathema of Life",
            "Curse of Mortality",
            "Ancient: Curse of Mori",
            "Dark Nightmare",
            "Horror",
        },
        ['Magic3'] = {
            ---Magic3 >=LVL87 QuickDot
            "Xirrim's Swift Deconstruction",
            "Blevak's Swift Deconstruction",
            "Xetheg's Swift Deconstruction",
            "Lexelan's Swift Deconstruction",
            "Adalora's Swift Deconstruction",
            "Marmat's Swift Deconstruction",
            "Itkari's Swift Deconstruction",
            "Hral's Swift Deconstruction",
            "Ninavero's Swift Deconstruction",
        },
        ['Magic4'] = {
            ---Magic4 >=LVL 97 DOT
            "Scourge of Eternity", -- Level 123 TOB
            "Scourge of Destiny",
            "Scourge of Fates",
        },
        ['Disease1'] = {
            ---Decay Line of Disease Spells >=LVL56 Slow DOT
            "Pustim's Decay",
            "Goremand's Decay",
            "Fleshrot's Decay",
            "Danvid's Decay",
            "Mourgis' Decay",
            "Livianus' Decay",
            "Wuran's Decay",
            "Ulork's Decay",
            "Folasar's Decay",
            "Megrima's Decay",
            "Eranon's Decay",
            "Severan's Rot",
            "Chaos Plague",
            "Dark Plague",
            "Cessation of Cor",
        },
        ['Disease2'] = {
            ---Grip Line of Disease Spells =LVL1 HAS DEBUFF
            "Grip of Pustim",
            "Grip of Quietus",
            "Grip of Zorglim",
            "Grip of Kraz",
            "Grip of Jabaum",
            "Grip of Zalikor",
            "Grip of Zargo",
            "Grip of Mori",
            "Plague",
            "Asystole",
            "Scourge",
            -- "Infectious Cloud", -- Target AE Spell
            "Heart Flutter",
            "Disease Cloud",
        },
        ['Combo'] = {
            ---Combines Disease1 and Disease2
            "Goremand's Grip of Decay",
            "Fleshrot's Grip of Decay",
            "Danvid's Grip of Decay",
            "Mourgis' Grip of Decay",
            "Livianus' Grip of Decay",

        },
        ['Disease3'] = {
            ---Sickness Life of Disease Spells >=LVL89 QuickDOT
            "Wremms's Swift Sickness",
            "Ogna's Swift Sickness",
            "Diabo Tatrua's Swift Sickness",
            "Lairsaf's Swift Sickness",
            "Hoshkar's Swift Sickness",
            "Ilsaria's Swift Sickness",
            "Bora's Swift Sickness",
            "Prox's Swift Sickness",
            "Rilfed's Swift Sickness",
        },
        ['Poison1'] = {
            ---Poison1 >= LVL86 (QuickDOT)
            "Lherre's Swift Venom",
            "Dotal's Swift Venom",
            "Xenacious' Swift Venom",
            "Vilefang's Swift Venom",
            "Nexona's Swift Venom",
            "Serisaria's Swift Venom",
            "Slaunk's Swift Venom",
            "Hyboram's Swift Venom",
            "Burlabis' Swift Venom",
        },
        ['Poison2'] = {
            ---Poison2 >=LVL1 (DOT)
            "Silkwhisper Venom",
            "Luggald Venom",
            "Hemorrhagic Venom",
            "Crystal Crawler Venom",
            "Polybiad Venom",
            "Glistenwing Venom",
            "Binaesa Venom",
            "Naeya Venom",
            "Argendev's Venom",
            "Slitheren Venom",
            "Venonscale Venom",
            "Vakk`dra's Sickly Mists",
            "Blood of Thule",
            "Envenomed Bolt",
            "Chilling Embrace",
            "Venom of the Snake",
            "Poison Bolt",
        },
        ['Poison2_2'] = {
            ---Poison2 >=LVL1 (DOT)
            "Silkwhisper Venom",
            "Luggald Venom",
            "Hemorrhagic Venom",
            "Crystal Crawler Venom",
            "Polybiad Venom",
            "Glistenwing Venom",
            "Binaesa Venom",
            "Naeya Venom",
            "Argendev's Venom",
            "Slitheren Venom",
            "Venonscale Venom",
            "Vakk`dra's Sickly Mists",
            "Blood of Thule",
            "Envenomed Bolt",
            "Chilling Embrace",
            "Venom of the Snake",
            "Poison Bolt",
        },
        ['Poison3'] = {
            ---Poison3 >= LVL79 DOT
            "Khrosik's Pallid Haze",
            "Uncia's Pallid Haze",
            "Zelnithak's Pallid Haze",
            "Dracnia's Pallid Haze",
            "Bomoda's Pallid Haze",
            "Plexipharia's Pallid Haze",
            "Halstor's Pallid Haze",
            "Ivrikdal's Pallid Haze",
            "Arachne's Pallid Haze",
            "Fellid's Pallid Haze",
            "Visziaj's Pallid Haze",
            "Chaos Venom",
        },
        ['Corruption1'] = {
            ---Corruption1 >= LVL77
            "Putrefaction XI",
            "Deterioration",
            "Decomposition",
            "Miasma",
            "Effluvium",
            "Liquefaction",
            "Dissolution",
            "Mortification",
            "Fetidity",
            "Putrescence",
            "Putrefaction",
        },
        ['CripplingTap'] = {
            -- >= LVL56 Crippling Claudication
            "Crippling Paraplegia",
            "Crippling Incapacity",
            "Crippling Claudication",
        },
        ['ChaoticDebuff'] = {
            -- >= LVL93
            -- Chaotic Contgion
            "Chaotic Fetor",
            "Chaotic Acridness",
            "Chaotic Miasma",
            "Chaotic Effluvium",
            "Chaotic Liquefaction",
            "Chaotic Corruption",
            "Chaotic Contagion",
        },
        ['SnareDot'] = {
            -- LVL4 -> <= LVL70
            "Clinging Darkness XIX",
            "Afflicted Darkness",
            "Harrowing Darkness",
            "Tormenting Darkness",
            "Gnawing Darkness",
            "Grasping Darkness",
            "Clutching Darkness",
            "Viscous Darkness",
            "Tenuous Darkness",
            "Clawing Darkness",
            "Auroral Darkness",
            "Coruscating Darkness",
            "Desecrating Darkness",
            "Embracing Darkness",
            "Devouring Darkness",
            "Cascading Darkness",
            "Scent of Darkness",
            "Dooming Darkness",
            "Engulfing Darkness",
            "Clinging Darkness",
        },
        ['ScentDebuff'] = {
            -- line needed till >= LVL10 <= LVL85
            "Scent of Dusk XIII",
            "Scent of The Realm",
            "Scent of The Grave",
            "Scent of Mortality",
            "Scent of Extinction",
            "Scent of Dread",
            "Scent of Nightfall",
            "Scent of Doom",
            "Scent of Gloom",
            "Scent of Afterlight",
            "Scent of Twilight",
            "Scent of Midnight",
            "Scent of Terris",
            "Scent of Darkness",
            "Scent of Shadow",
            "Scent of Dusk",
        },
        ['LichSpell'] = {
            -- LichForm Spell
            "Otherside XX",
            "Realmside",
            "Lunaside",
            "Gloomside",
            "Contraside",
            "Forgottenside",
            "Forsakenside",
            "Shadowside",
            "Darkside",
            "Netherside",
            "Spectralside",
            "Otherside",
            "Dark Possession",
            "Grave Pact",
            "Seduction of Saryrn",
            "Arch Lich",
            "Demi Lich",
            "Lich",
            "Call of Bones",
            "Allure of Death",
            "Dark Pact",
        },
        ['BestowBuff'] = {
            "Bestow Undeath X",
            "Bestow Ruin",
            "Bestow Rot",
            "Bestow Dread",
            "Bestow Relife",
            "Bestow Doom",
            "Bestow Mortality",
            "Bestow Decay",
            "Bestow Unlife",
            "Bestow Undeath",
        },
        ['PetSpellRog'] = {
            "Dark Assassin XVI",
            "Merciless Assassin",
            "Unrelenting Assassin",
            "Restless Assassin",
            "Reliving Assassin",
            "Restless Assassin",
            "Revived Assassin",
            "Unearthed Assassin",
            "Reborn Assassin",
            "Raised Assassin",
            "Unliving Murderer",
            "Noxious Servant",
            "Putrescent Servant",
            "Dark Assassin",
            "Child of Bertoxxulous",
            "Saryrn's Companion",
            "Minion of Shadows",
        },
        ['PetSpellWar'] = {
            "Rasivimun's Shade",
            "Margator's Shade",
            "Luclin's Conqueror",
            "Tserrina's Shade",
            "Adalora's Shade",
            "Miktokla's Shade",
            "Zalifur's Shade",
            "Vak`Ridel's Shade",
            "Aziad's Shade",
            "Bloodreaper's Shade",
            "Relamar's Shade",
            "Riza`farr's Shadow",
            "Lost Soul",
            "Emissary of Thule",
            "Servant of Bones",
            "Invoke Death",
            "Cackling Bones",
            "Malignant Dead",
            "Invoke Shadow",
            "Summon Dead",
            "Haunting Corpse",
            "Animate Dead",
            "Restless Bones",
            "Convoke Shadow",
            "Bone Walk",
            "Leering Corpse",
            "Cavorting Bones",
        },
        ['PetHeal'] = {
            -- Chilling Renewal line (pet heal + counter cure)
            "Chilling Renewal XVI",
            "Bracing Revival",
            "Frigid Salubrity",
            "Icy Revival",
            "Algid Renewal",
            "Icy Mending",
            "Algid Mending",
            "Chilled Mending",
            "Gelid Mending",
            "Icy Stitches",
            "Wintry Revival",
            "Chilling Renewal",
            "Dark Salve",
            "Touch of Death",
            "Renew Bones",
            "Mend Bones",
        },
        ['PetBuff'] = {
            "Necrotize Ally X",
            "Instill Ally",
            "Inspire Ally",
            "Incite Ally",
            "Infuse Ally",
            "Imbue Ally",
            --The below spells deal PBAE damage on fade and should not be casually used (later spells drop this effect)
            --"Sanction Ally",
            --"Empower Ally",
            --"Energize Ally",
            --"Necrotize Ally",
        },
        ['PetHaste'] = {
            "Sigil of Death XV",
            "Sigil of Putrefaction",
            "Sigil of Undeath",
            "Sigil of Decay",
            "Sigil of the Arcron",
            "Sigil of the Doomscale",
            "Sigil of the Sundered",
            "Sigil of the Preternatural",
            "Sigil of the Moribund",
            "Sigil of the Aberrant",
            "Sigil of the Unnatural",
            "Glyph of Darkness",
            "Rune of Death",
            "Augmentation of Death",
            "Augment Death",
            "Intensify Death",
            "Focus Death",
        },
        ['FleshBuff'] = {
            "Flesh to Toxin",  -- Level 119
            "Flesh to Venom",  -- Level 109
            "Flesh to Poison", -- Level 99
        },
    },
    ['RotationOrder']   = {
        -- Downtime doesn't have state because we run the whole rotation at once.
        {
            name = 'Downtime',
            targetId = function(self) return { mq.TLO.Me.ID(), } end,
            cond = function(self, combat_state)
                return combat_state == "Downtime" and Casting.OkayToBuff() and Casting.AmIBuffable()
            end,
        },
        {
            name = 'Lich Management',
            timer = 10,
            state = 1,
            steps = 1,
            targetId = function(self) return { mq.TLO.Me.ID(), } end,
            cond = function(self, combat_state)
                return true
            end,
        },
        { --Summon pet even when buffs are off on emu
            name = 'PetSummon',
            targetId = function(self) return { mq.TLO.Me.ID(), } end,
            cond = function(self, combat_state)
                return combat_state == "Downtime" and Casting.OkayToPetBuff() and mq.TLO.Me.Pet.ID() == 0 and not Core.IsCharming() and Casting.AmIBuffable()
            end,
        },
        { --Pet Buffs if we have one, timer because we don't need to constantly check this
            name = 'PetBuff',
            timer = 10,
            targetId = function(self) return mq.TLO.Me.Pet.ID() > 0 and { mq.TLO.Me.Pet.ID(), } or {} end,
            cond = function(self, combat_state)
                return combat_state == "Downtime" and mq.TLO.Me.Pet.ID() > 0 and Casting.OkayToPetBuff()
            end,
        },
        {
            name = 'Emergency',
            state = 1,
            steps = 1,
            doFullRotation = true,
            targetId = function(self) return Targeting.CheckForAutoTargetID() end,
            cond = function(self, combat_state)
                return Targeting.GetXTHaterCount() > 0 and not Casting.IAmFeigning() and
                    (mq.TLO.Me.PctHPs() <= Config:GetSetting('EmergencyStart') or Globals.AutoTargetIsNamed and mq.TLO.Me.PctAggro() > 99)
            end,
        },
        {
            name = 'Burn',
            state = 1,
            steps = 4,
            targetId = function(self) return Targeting.CheckForAutoTargetID() end,
            cond = function(self, combat_state)
                return combat_state == "Combat" and Casting.BurnCheck() and not Casting.IAmFeigning()
            end,
        },
        {
            name = 'DPS',
            state = 1,
            steps = 1,
            targetId = function(self) return Targeting.CheckForAutoTargetID() end,
            cond = function(self, combat_state)
                return combat_state == "Combat" and not Casting.IAmFeigning()
            end,
        },
        { -- Pet heal/counter-cleanse utility, evaluated in and out of combat
            name = 'PetHeal',
            timer = 1,
            targetId = function(self) return mq.TLO.Me.Pet.ID() > 0 and { mq.TLO.Me.Pet.ID(), } or {} end,
            cond = function(self, combat_state)
                return Config:GetSetting('DoPetHeal') and mq.TLO.Me.Pet.ID() > 0 and not Casting.IAmFeigning()
            end,
        },
    },
    ['Rotations']       = {
        ['Lich Management'] = {
            {
                name = "LichSpell",
                type = "Spell",
                active_cond = function(self, spell) return Casting.IHaveBuff(spell) end,
                cond = function(self, spell)
                    return Config:GetSetting('DoLich') and Casting.SelfBuffCheck(spell) and
                        (not Config:GetSetting('DoUnity') or not Casting.AAReady("Mortifier's Unity")) and
                        mq.TLO.Me.PctHPs() > Config:GetSetting('StopLichHP') and mq.TLO.Me.PctMana() < Config:GetSetting('StartLichMana')
                end,
            },
            {
                name = "LichControl",
                type = "CustomFunc",
                cond = function(self, _)
                    local lichSpell = self:GetResolvedActionMapItem('LichSpell')

                    return lichSpell and lichSpell() and Casting.IHaveBuff(lichSpell) and
                        (mq.TLO.Me.PctHPs() <= Config:GetSetting('StopLichHP') or mq.TLO.Me.PctMana() >= Config:GetSetting('StopLichMana'))
                end,
                custom_func = function(self)
                    Core.SafeCallFunc("Stop Lich Spell", self.ClassConfig.HelperFunctions.CancelLich, self)
                end,
            },
            {
                name = "FleshControl",
                type = "CustomFunc",
                cond = function(self, _)
                    local fleshSpell = self:GetResolvedActionMapItem('FleshBuff')

                    return fleshSpell and fleshSpell() and Casting.IHaveBuff(fleshSpell) and mq.TLO.Me.PctHPs() <= Config:GetSetting('StopLichHP')
                end,
                custom_func = function(self)
                    Core.SafeCallFunc("Stop Flesh Buff", self.ClassConfig.HelperFunctions.CancelFlesh, self)
                end,
            },
        },
        ['Emergency'] = {
            {
                name = "Death's Effigy",
                type = "AA",
                cond = function(self, aaName, target)
                    if not Config:GetSetting('AggroFeign') then return false end
                    return (mq.TLO.Me.PctHPs() <= Config:GetSetting('EmergencyStart') and Targeting.IHaveAggro(100)) or
                        (Globals.AutoTargetIsNamed and mq.TLO.Me.PctAggro() > 99)
                end,
            },
            {
                name = "FDSpell",
                type = "Spell",
                cond = function(self, spell, target)
                    if not Config:GetSetting('AggroFeign') then return false end
                    if Casting.AAReady("Death's Effigy") then return false end
                    return (mq.TLO.Me.PctHPs() <= Config:GetSetting('EmergencyStart') and Targeting.IHaveAggro(100)) or
                        (Globals.AutoTargetIsNamed and mq.TLO.Me.PctAggro() > 99)
                end,
            },
            {
                name = "Dying Grasp",
                type = "AA",
                cond = function(self, aaName)
                    return mq.TLO.Me.PctHPs() <= Config:GetSetting('EmergencyStart')
                end,
            },
            {
                name = "Embalmer's Carapace",
                type = "AA",
            },
            {
                name = "HarmShieldSpell",
                type = "Spell",
                cond = function(self, spell)
                    if Casting.AAReady("Harm Shield") then return false end
                    return (mq.TLO.Me.PctHPs() <= Config:GetSetting('EmergencyStart') and Targeting.IHaveAggro(100))
                end,
            },
            {
                name = "Harm Shield",
                type = "AA",
                cond = function(self, aaName)
                    return (mq.TLO.Me.PctHPs() <= Config:GetSetting('EmergencyStart') and Targeting.IHaveAggro(100))
                end,
            },
        },
        ['DPS'] = {
            {
                name_func = function(self)
                    return Config:GetSetting('PetType') == 1 and "PetSpellWar" or "PetSpellRog"
                end,
                type = "Spell",
                cond = function(self, spell)
                    return mq.TLO.Me.Pet.ID() == 0 and not Core.IsCharming() and Casting.ReagentCheck(spell)
                end,
                post_activate = function(self, spell, success)
                    local pet = mq.TLO.Me.Pet
                    if success and pet.ID() > 0 then
                        Comms.PrintGroupMessage("Summoned a new %d %s pet named %s using '%s'!", pet.Level(), pet.Class.Name(), pet.CleanName(), spell.RankName())
                        mq.delay(50) -- slight delay to prevent chat bug with command issue
                        self:SetPetHold()
                    end
                end,
            },
            {
                name = "HealthTaps",
                type = "Spell",
                cond = function(self, spell, target)
                    return mq.TLO.Me.PctHPs() <= Config:GetSetting('HealthTapStart')
                end,
            },
            {
                name = "SnareDot",
                type = "Spell",
                cond = function(self, spell, target)
                    return Casting.DetSpellCheck(spell) and Targeting.AggroCheckOkay() and not Casting.SnareImmuneTarget(target)
                end,
            },
            {
                name = "Summon Companion",
                type = "AA",
                cond = function(self, aaName, target)
                    if mq.TLO.Me.Pet.ID() == 0 then return false end
                    local pet = mq.TLO.Me.Pet
                    return not pet.Combat() and (pet.Distance3D() or 0) > 200
                end,
            },
            {
                name = "Wake the Dead",
                type = "AA",
                cond = function(self, aaName)
                    return mq.TLO.SpawnCount("corpse radius 100")() >= Config:GetSetting('WakeDeadCorpseCnt')
                end,
            },
            {
                name = "Disease2",
                type = "Spell",
                cond = function(self, spell, target)
                    return Targeting.GetTargetPctHPs(target) >= 55 and Casting.DotSpellCheck(spell) and Casting.HaveManaToDot() and Targeting.AggroCheckOkay()
                end,
            },
            {
                name = "FireDot2",
                type = "Spell",
                cond = function(self, spell, target)
                    return Targeting.GetTargetPctHPs(target) >= 55 and Casting.DotSpellCheck(spell) and Casting.HaveManaToDot() and Targeting.AggroCheckOkay()
                end,
            },
            {
                name = "Fear",
                type = "Spell",
                cond = function(self, spell, target)
                    local fearTarget = target or Targeting.GetAutoTarget() or mq.TLO.Target
                    if not (fearTarget and fearTarget()) then return false end
                    if (Targeting.GetTargetPctHPs(fearTarget) or 0) <= 21 then return false end

                    local snareSpell = self:GetResolvedActionMapItem('SnareDot')
                    local hasClassSnare = false
                    if snareSpell and snareSpell() then
                        local snareSpellId = Casting.GetUseableSpellId(snareSpell)
                        if snareSpellId then
                            hasClassSnare = fearTarget.FindBuff(string.format("id %d", snareSpellId))() ~= nil
                        end
                    end

                    -- Allow any detrimental movement-speed debuff (e.g. RNG snare line), not only NEC SnareDot.
                    local hasAnySnare = fearTarget.FindBuff("detspa 3")() ~= nil

                    return (hasClassSnare or hasAnySnare) and Casting.DetSpellCheck(spell) and Casting.HaveManaToDot() and Targeting.AggroCheckOkay()
                end,
            },
            {
                name = "ManaDrain",
                type = "Spell",
                cond = function(self, spell, target)
                    if not (spell and spell()) then return false end
                    return not Casting.IHaveBuff(spell.Name() .. " Recourse") and
                        (mq.TLO.Target.PctMana() or -1) > 0 and mq.TLO.Group.LowMana(40)() > 2
                end,
            },
            {
                name = "Combo",
                type = "Spell",
                cond = function(self, spell, target)
                    return Casting.DotSpellCheck(spell) and Casting.HaveManaToDot() and Targeting.AggroCheckOkay()
                end,
            },
            {
                name = "Poison2",
                type = "Spell",
                cond = function(self, spell, target)
                    return Casting.DotSpellCheck(spell) and Casting.HaveManaToDot() and Targeting.AggroCheckOkay()
                end,
            },
            {
                name = "Magic2",
                type = "Spell",
                cond = function(self, spell, target)
                    return Casting.DotSpellCheck(spell) and Casting.HaveManaToDot() and Targeting.AggroCheckOkay()
                end,
            },
            {
                name = "GroupLeech",
                type = "Spell",
                cond = function(self, spell, target)
                    return Casting.DotSpellCheck(spell) and Casting.HaveManaToDot() and Targeting.AggroCheckOkay()
                end,
            },
            {
                name = "SwarmPet",
                type = "Spell",
                cond = function(self, spell, target)
                    return (Targeting.MobHasLowHP or Globals.AutoTargetIsNamed) and Casting.OkayToNuke()
                end,
            },
            {
                name = "PoisonNuke1",
                type = "Spell",
                cond = function(self, spell, target)
                    return not Targeting.MobHasLowHP(target) and Casting.OkayToNuke() and Targeting.AggroCheckOkay()
                end,
            },
            {
                name = "PoisonNuke2",
                type = "Spell",
                cond = function(self, spell, target)
                    return not Targeting.MobHasLowHP(target) and Casting.OkayToNuke() and Targeting.AggroCheckOkay()
                end,
            },
            {
                name = "FireNuke",
                type = "Spell",
                cond = function(self, spell, target)
                    return not Targeting.MobHasLowHP(target) and Casting.OkayToNuke()
                end,
            },
            {
                name = "Death Bloom",
                type = "AA",
                cond = function(self, aaName)
                    return Casting.SelfBuffAACheck(aaName) and mq.TLO.Me.PctMana() < Config:GetSetting('DeathBloomPercent') and mq.TLO.Me.PctHPs() > 50
                end,
            },
            {
                name = "Embrace the Decay",
                type = "AA",
                cond = function(self, aaName)
                    return mq.TLO.Me.TotalCounters() > 0
                end,
            },
        },
        ['Burn'] = { -- TODO: Needs optimization. For now its all just kinda thrown in. --Algar
            {
                name = "Scent of Thule",
                type = "AA",
                cond = function(self, aaName, target)
                    return Globals.AutoTargetIsNamed
                end,
            },
            {
                name = "OoW_Chest",
                type = "Item",
            },
            {
                name = "Funeral Pyre",
                type = "AA",
            },
            {
                name = "Hand of Death",
                type = "AA",
            },
            {
                name = "Mercurial Torment",
                type = "AA",
            },
            {
                name = "Heretic's Twincast",
                type = "AA",
            },
            {
                name = "Gathering Dusk",
                type = "AA",
                cond = function(self, aaName, target) return Globals.AutoTargetIsNamed end,
            },
            {
                name = "Swarm of Decay",
                type = "AA",
            },
            {
                name = "Companion's Fury",
                type = "AA",
            },
            {
                name = "Rise of Bones",
                type = "AA",
            },
            {
                name = "Focus of Arcanum",
                type = "AA",
                cond = function(self, aaName, target) return Globals.AutoTargetIsNamed end,
            },
            {
                name = "Forceful Rejuvenation",
                type = "AA",
            },
            {
                name = "Spire of Necromancy",
                type = "AA",
            },
            { --Chest Click, name function stops errors in rotation window when slot is empty
                name_func = function() return mq.TLO.Me.Inventory("Chest").Name() or "ChestClick(Missing)" end,
                type = "Item",
                cond = function(self, itemName, target)
                    if not Config:GetSetting('DoChestClick') or not Casting.ItemHasClicky(itemName) then return false end
                    return Casting.SelfBuffItemCheck(itemName)
                end,
            },
            {
                name = "BestowBuff",
                type = "Spell",
                cond = function(self, spell) return Casting.SelfBuffCheck(spell) end,
            },
            {
                name = "Silent Casting",
                type = "AA",
                cond = function(self, aaName, target)
                    return Globals.AutoTargetIsNamed and mq.TLO.Me.PctAggro() > 60
                end,
            },
            {
                name = "Dying Grasp",
                type = "AA",
                cond = function(self, aaName, target)
                    return Globals.AutoTargetIsNamed and mq.TLO.Me.PctAggro() <= 50
                end,
            },
            {
                name = "PoisonNuke1",
                type = "Spell",
                cond = function(self, spell, target)
                    return Casting.OkayToNuke()
                end,
            },
        },
        ['Downtime'] = {
            {
                name = "SelfHPBuff",
                type = "Spell",
                active_cond = function(self, spell) return Casting.IHaveBuff(spell) end,
                cond = function(self, spell) return Casting.SelfBuffCheck(spell) end,
            },
            {
                name = "SelfRune1",
                type = "Spell",
                active_cond = function(self, spell) return Casting.IHaveBuff(spell) end,
                cond = function(self, spell) return Casting.SelfBuffCheck(spell) end,
            },
            {
                name = "SelfSpellShield1",
                type = "Spell",
                active_cond = function(self, spell) return Casting.IHaveBuff(spell) end,
                cond = function(self, spell) return Casting.SelfBuffCheck(spell) end,
            },
            {
                name = "Death Bloom",
                type = "AA",
                active_cond = function(self, aaName) return Casting.IHaveBuff(aaName) end,
                cond = function(self, aaName) return mq.TLO.Me.PctMana() < Config:GetSetting('DeathBloomPercent') end,
            },
            {
                name = "BestowBuff",
                type = "Spell",
                active_cond = function(self, spell) return Casting.IHaveBuff(spell) end,
                cond = function(self, spell) return Casting.SelfBuffCheck(spell) end,
            },
            {
                name = "FleshBuff",
                type = "Spell",
                active_cond = function(self, spell) return Casting.IHaveBuff(spell) end,
                cond = function(self, spell)
                    return mq.TLO.Me.PctHPs() > Config:GetSetting('EmergencyStart') and Casting.SelfBuffCheck(spell)
                end,
            },
        },
        ['PetSummon'] = { --TODO: Double check these lists to ensure someone leveling doesn't have to change options to keep pets current at lower levels
            {
                name_func = function(self)
                    return Config:GetSetting('PetType') == 1 and "PetSpellWar" or "PetSpellRog"
                end,
                type = "Spell",
                cond = function(self, spell)
                    return Casting.ReagentCheck(spell)
                end,
                post_activate = function(self, spell, success)
                    local pet = mq.TLO.Me.Pet
                    if success and pet.ID() > 0 then
                        Comms.PrintGroupMessage("Summoned a new %d %s pet named %s using '%s'!", pet.Level(), pet.Class.Name(), pet.CleanName(), spell.RankName())
                        mq.delay(50) -- slight delay to prevent chat bug with command issue
                        self:SetPetHold()
                    end
                end,
            },
        },
        ['PetBuff'] = {
            {
                name = "PetHaste",
                type = "Spell",
                active_cond = function(self, spell) return mq.TLO.Me.PetBuff(spell.RankName())() end,
                cond = function(self, spell) return Casting.PetBuffCheck(spell) end,
            },
            {
                name = "PetBuff",
                type = "Spell",
                active_cond = function(self, spell) return mq.TLO.Me.PetBuff(spell.RankName())() end,
                cond = function(self, spell) return Casting.PetBuffCheck(spell) end,
            },
            {
                name = "Companion's Aegis",
                type = "AA",
                cond = function(self, aaName)
                    return Casting.PetBuffAACheck(aaName)
                end,
            },
        },
        ['PetHeal'] = {
            {
                name = "PetHeal",
                type = "Spell",
                cond = function(self, spell)
                    if not Config:GetSetting('DoPetHeal') then return false end
                    local pet = mq.TLO.Me.Pet
                    if not (pet and pet() and pet.ID() > 0) then return false end

                    local petLowHP = (pet.PctHPs() or 100) <= Config:GetSetting('PetHealPct')
                    local hasCounters = false
                    local okTotal, totalCounters = pcall(function() return pet.TotalCounters() or 0 end)
                    if okTotal and totalCounters > 0 then
                        hasCounters = true
                    end

                    if not hasCounters then
                        local okPoi, poi = pcall(function() return pet.Poisoned.ID() or 0 end)
                        local okDis, dis = pcall(function() return pet.Diseased.ID() or 0 end)
                        local okCur, cur = pcall(function() return pet.Cursed.ID() or 0 end)
                        local okCor, cor = pcall(function() return pet.Corrupted.ID() or 0 end)
                        hasCounters = (okPoi and poi > 0) or (okDis and dis > 0) or (okCur and cur > 0) or (okCor and cor > 0)
                    end

                    return petLowHP or hasCounters
                end,
            },
        },
    },
    ['HelperFunctions'] = {
        CancelLich = function(self)
            -- detspa means detremental spell affect and 0 mean HPs
            -- spa is positive spell affect and 15 means mana
            local lichName = mq.TLO.Me.FindBuff("detspa 0 and spa 15")()
            Core.DoCmd("/removebuff %s", lichName)
        end,
        CancelFlesh = function(self)
            local fleshName = self:GetResolvedActionMapItem('FleshBuff')
            Core.DoCmd("/removebuff %s", fleshName)
        end,

        StartLich = function(self)
            local lichSpell = self:GetResolvedActionMapItem('LichSpell')

            if lichSpell and lichSpell() then
                Casting.UseSpell(lichSpell.RankName.Name(), mq.TLO.Me.ID(), false)
            end
        end,

        DoRez = function(self, corpseId)
            if Config:GetSetting('DoBattleRez') or mq.TLO.Me.CombatState():lower() ~= "combat" then
                if Casting.AAReady("Convergence") and Casting.ReagentCheck(mq.TLO.Me.AltAbility("Convergence").Spell) then
                    return Casting.OkayToRez(corpseId) and Casting.UseAA("Convergence", corpseId, true, 1)
                end
            end
        end,
    },
    -- New style spell list, gemless, priority-based. Will use the first set whose conditions are met.
    -- The list name ("Default" in the list below) is abitrary, it is simply what shows up in the UI when this spell list is loaded.
    -- Virtually any helper function or TLO can be used as a condition. Example: Mode or level-based lists.
    -- The first list without conditions or whose conditions returns true will be loaded, all subsequent lists will be ignored.
    -- Spells will be loaded in order (if the conditions are met), until all gem slots are full.
    -- Loadout checks (such as scribing a spell or using the "Rescan Loadout" or "Reload Spells" buttons) will re-check these lists and may load a different set if things have changed.
    ['SpellList']       = {
        {
            name = "Default",
            -- cond = function(self) return true end, --Kept here for illustration, this line could be removed in this instance since we aren't using conditions.
            spells = {
                { name = "FireNuke", },
                { name = "FDSpell", cond = function(self) return Config:GetSetting('AggroFeign') end, },
                { name = "HarmShieldSpell", cond = function(self) return Config:GetSetting('AggroFeign') end, },
                { name = "PoisonNuke1", },
                { name = "PoisonNuke2", },
                { name = "SwarmPet", },
                { name = "SnareDot", },
                { name = "Disease2", },
                { name = "FireDot2", },
                { name = "Fear", },
                { name = "Combo", },
                { name = "Poison2", },
                { name = "Magic2", },
                { name = "GroupLeech", },
                { name = "ManaDrain", },
                { name = "HealthTaps", },
                { name = "FleshBuff", },
                { name = "BestowBuff", },
                { name = "PetBuff", },
                { name = "PetHeal", cond = function(self) return Config:GetSetting('DoPetHeal') end, },
                { name = "MezSpell", cond = function(self) return Config:GetSetting('DoSTMez') end, },
                {
                    name_func = function(self)
                        if Config:GetSetting('KeepPetMemmed') then
                            return Config:GetSetting('PetType') == 1 and "PetSpellWar" or "PetSpellRog"
                        end

                        local selfHPBuff = self:GetResolvedActionMapItem('SelfHPBuff')
                        if selfHPBuff and selfHPBuff() and not Casting.IHaveBuff(selfHPBuff) then
                            return "SelfHPBuff"
                        end

                        local lichSpell = self:GetResolvedActionMapItem('LichSpell')
                        if Config:GetSetting('DoLich') and lichSpell and lichSpell() and not Casting.IHaveBuff(lichSpell) and
                            (not Config:GetSetting('DoUnity') or not Casting.AAReady("Mortifier's Unity")) and
                            mq.TLO.Me.PctHPs() > Config:GetSetting('StopLichHP') and mq.TLO.Me.PctMana() < Config:GetSetting('StartLichMana') then
                            return "LichSpell"
                        end

                        return nil
                    end,
                },
            },
        },
    },
    ['DefaultConfig']   = {
        ['Mode']              = {
            DisplayName = "Mode",
            Category = "Combat",
            Tooltip = "Select the Combat Mode for this Toon",
            Type = "Custom",
            RequiresLoadoutChange = true,
            Default = 1,
            Min = 1,
            Max = 1,
            FAQ = "What do the different Modes Do?",
            Answer = "Currently Necros only have one mode, which is DPS. This mode will focus on DPS and some utility.",
        },
        ['PetType']           = {
            DisplayName = "Pet Class",
            Group = "Abilities",
            Header = "Pet",
            Category = "Pet Summoning",
            Index = 101,
            Tooltip = "1 = War, 2 = Rog",
            Type = "Combo",
            ComboOptions = { 'War', 'Rog', },
            Default = 2,
            Min = 1,
            Max = 2,
        },
        ['KeepPetMemmed']     = {
            DisplayName = "Always Mem Pet",
            Group = "Abilities",
            Header = "Pet",
            Category = "Pet Summoning",
            Index = 102,
            Tooltip = "Keep your pet spell memorized (allows combat resummoning).",
            Default = false,
        },
        ['DoPetHeal']         = {
            DisplayName = "Use Pet Heal",
            Group = "Abilities",
            Header = "Pet",
            Category = "Pet Summoning",
            Index = 103,
            Tooltip = "Memorize and use the Pet Heal (Chilling Renewal line) when enabled.",
            Default = false,
            RequiresLoadoutChange = true,
        },
        ['PetHealPct']        = {
            DisplayName = "Pet Heal HP%",
            Group = "Abilities",
            Header = "Pet",
            Category = "Pet Summoning",
            Index = 104,
            Tooltip = "Pet HP% threshold to cast Pet Heal.",
            Default = 70,
            Min = 1,
            Max = 100,
        },
        ['BattleRez']         = {
            DisplayName = "Battle Rez",
            Group = "Abilities",
            Header = "Recovery",
            Category = "Rezzing",
            Tooltip = "Do Rezes during combat.",
            RequiresLoadoutChange = true,
            Default = true,
        },
        ['DeathBloomPercent'] = {
            DisplayName = "Death Bloom %",
            Group = "Abilities",
            Header = "Damage",
            Category = "Direct",
            Tooltip = "Mana % at which to cast Death Bloom",
            Default = 40,
            Min = 1,
            Max = 100,
        },
        ['WakeDeadCorpseCnt'] = {
            DisplayName = "WtD Corpse Count",
            Group = "Abilities",
            Header = "Pet",
            Category = "Swarm Pets",
            Tooltip = "Number of Corpses before we cast Wake the Dead",
            Default = 5,
            Min = 1,
            Max = 20,
        },
        ['DoLich']            = {
            DisplayName = "Cast Lich",
            Group = "Abilities",
            Header = "Buffs",
            Category = "Self",
            Tooltip = "Enable casting Lich spells.",
            RequiresLoadoutChange = true,
            Default = true,
        },
        ['StopLichHP']        = {
            DisplayName = "Stop Lich HP",
            Group = "Abilities",
            Header = "Buffs",
            Category = "Self",
            Tooltip = "Cancel Lich and Flesh Buff at [x] Pct HPs. Please note that Flesh Buff will recast if we are above the Emergency Start HP%",
            RequiresLoadoutChange = false,
            Default = 25,
            Min = 1,
            Max = 99,
        },
        ['StopLichMana']      = {
            DisplayName = "Stop Lich Mana",
            Group = "Abilities",
            Header = "Buffs",
            Category = "Self",
            Tooltip = "Cancel your Lich spell when your mana has increased to this percentage. (Selecting 101 will disable canceling lich based on mana percent.)",
            RequiresLoadoutChange = false,
            Default = 100,
            Min = 1,
            Max = 101,
        },
        ['StartLichMana']     = {
            DisplayName = "Start Lich Mana",
            Group = "Abilities",
            Header = "Buffs",
            Category = "Self",
            Tooltip = "Start Lich at Mana Pct [x]",
            RequiresLoadoutChange = false,
            Default = 70,
            Min = 1,
            Max = 100,
        },
        ['DoChestClick']      = {
            DisplayName = "Do Chest Click",
            Group = "Items",
            Header = "Clickies",
            Category = "Class Config Clickies",
            Tooltip = "Click your chest item",
            Default = mq.TLO.MacroQuest.BuildName() ~= "Emu",
        },
        ['EmergencyStart']    = {
            DisplayName = "Emergency HP%",
            Group = "Abilities",
            Header = "Utility",
            Category = "Emergency",
            Index = 101,
            Tooltip = "Your HP % before we begin to use emergency mitigation abilities. Also, the minimum HP we need to use the Flesh Buff.",
            Default = 50,
            Min = 1,
            Max = 100,
            ConfigType = "Advanced",
        },
        ['HealthTapStart']    = {
            DisplayName = "Health Tap HP%",
            Group = "Abilities",
            Header = "Damage",
            Category = "Direct",
            Index = 102,
            Tooltip = "Your HP % threshold to begin casting HealthTaps/Lifetap line.",
            Default = 50,
            Min = 1,
            Max = 100,
            ConfigType = "Advanced",
        },
        ['AggroFeign']        = {
            DisplayName = "Emergency Feign",
            Group = "Abilities",
            Header = "Utility",
            Category = "Emergency",
            Index = 103,
            Tooltip = "Use your Feign AA when you have aggro at low health or aggro on mobs detected as 'named' by RGMercs (see Named tab).",
            Default = true,
        },
        ['DoLifeBurn']        = {
            DisplayName = "Orphaned",
            Type = "Custom",
            Category = "Orphaned",
            Tooltip = "Orphaned setting from live, no longer used in this config.",
            Default = false,
        },
        ['DoUnity']           = {
            DisplayName = "Orphaned",
            Type = "Custom",
            Category = "Orphaned",
            Tooltip = "Orphaned setting from live, no longer used in this config.",
            Default = false,
        },
        ['StopFDPct']         = {
            DisplayName = "Orphaned",
            Type = "Custom",
            Category = "Orphaned",
            Tooltip = "Orphaned setting from live, no longer used in this config.",
            Default = false,
        },
        ['StartFDPct']        = {
            DisplayName = "Orphaned",
            Type = "Custom",
            Category = "Orphaned",
            Tooltip = "Orphaned setting from live, no longer used in this config.",
            Default = false,
        },
        ['DoSnare']           = {
            DisplayName = "Orphaned",
            Type = "Custom",
            Category = "Orphaned",
            Tooltip = "Orphaned setting from live, no longer used in this config.",
            Default = false,
        },
    },
    ['ClassFAQ']        = {
        {
            Question = "What is the current status of this class config?",
            Answer = "This class config is an Alpha config aimed at late game live.\n\n" ..
                "  It should perform well in a group, but may be lacking typical options or configuration.\n\n" ..
                "  Community effort and feedback are required for robust, resilient class configs, and PRs are highly encouraged!",
            Settings_Used = "",
        },
    },
}

return _ClassConfig
