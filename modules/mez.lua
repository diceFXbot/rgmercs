-- Sample Basic Class Module
local mq        = require('mq')
local Base      = require("modules.base")
local Casting   = require("utils.casting")
local Combat    = require("utils.combat")
local Comms     = require("utils.comms")
local Config    = require('utils.config')
local Core      = require("utils.core")
local Events    = require("utils.events")
local Globals   = require('utils.globals')
local Logger    = require("utils.logger")
local Modules   = require("utils.modules")
local Strings   = require("utils.strings")
local Targeting = require("utils.targeting")
require('utils.datatypes')

local Module   = { _version = '0.1a', _name = "Mez", _author = 'Derple', }
Module.__index = Module
setmetatable(Module, { __index = Base, })
Module.FAQ                     = {}
Module.CommandHandlers         = {}

Module.CombatState             = "None"

Module.TempSettings            = {}
Module.TempSettings.MezImmune  = {}
--- Slim CC list: mezzed mob IDs we cast on (or synced from XT), with countdown. Off-XT mobs stay monitored (HateClear).
Module.TempSettings.MezTracker = {}

Module.DefaultConfig           = {
    --General
    ['MezOn']                                  = {
        DisplayName = "Enable Mezzing",
        Group = "Abilities",
        Header = "Mez",
        Category = "Mez General",
        Index = 1,
        Default = true,
        Tooltip = "Enables mezzing all forms of mezzing as a quick toggle, select particular actions to use below.",
    },
    ['DoSTMez']                                = {
        DisplayName = "ST Mez Song/Spells",
        Group = "Abilities",
        Header = "Mez",
        Category = "Mez General",
        Index = 2,
        Default = true,
        Tooltip = "Enable the memorization and use of ST mez spells/songs.",
        RequiresLoadoutChange = true,
    },
    ['DoAEMez']                                = {
        DisplayName = "AE Mez Song/Spells",
        Group = "Abilities",
        Header = "Mez",
        Category = "Mez General",
        Index = 3,
        Default = true,
        Tooltip = "Enable the memorization and use of AE mez spells/songs.",
        RequiresLoadoutChange = true,
    },
    ['DoAAMez']                                = {
        DisplayName = "Use Mez AA",
        Group = "Abilities",
        Header = "Mez",
        Category = "Mez General",
        Index = 4,
        Default = true,
        Tooltip = "Use Beam of Slumber(ENC, Directional Beam) or Dirge of the Sleepwalker(BRD, Single-Target) when able.",
    },
    ['MezStartCount']                          = {
        DisplayName = "Mez Start Count",
        Group = "Abilities",
        Header = "Mez",
        Category = "Mez General",
        Index = 5,
        Default = 2,
        Min = 1,
        Max = 20,
        Tooltip = "The minimum number of xtargets before we will attempt to use a ST mez.",
    },
    ['MezAECount']                             = {
        DisplayName = "Mez AE Count",
        Group = "Abilities",
        Header = "Mez",
        Category = "Mez General",
        Index = 6,
        Tooltip = "The minimum number of xtargets before we will attempt to use an AE mez.",
        Default = 3,
        Min = 1,
        Max = 20,
    },
    ['MaxMezCount']                            = {
        DisplayName = "Max Mez Count",
        Group = "Abilities",
        Header = "Mez",
        Category = "Mez General",
        Index = 7,
        Default = 13,
        Min = 1,
        Max = 20,
        Tooltip = "The maximum number of xtargets before we will cease attempts to mez.",
        ConfigType = "Advanced",
    },
    ['MezRadius']                              = {
        DisplayName = "Mez Radius",
        Group = "Abilities",
        Header = "Mez",
        Category = "Mez General",
        Index = 8,
        Default = 100,
        Min = 1,
        Max = 200,
        Tooltip = "The maximum distance away a potential mez target can be from the PC.",
        ConfigType = "Advanced",
    },
    ['SafeAEMez']                              = {
        DisplayName = "AE Mez Safety Check",
        Group = "Abilities",
        Header = "Mez",
        Category = "Mez General",
        Index = 9,
        Tooltip =
        "Check to ensure there aren't neutral mobs in range we could aggro if AE mez is used. May result in non-use due to false positives.",
        Default = false,
        ConfigType = "Advanced",
        FAQ = "Can you better explain the AE Mez Safety Check?",
        Answer = "If the option is enabled, the script will use various checks to determine if a non-hostile or not-aggroed NPC is present and avoid use of the mez.\n" ..
            "Unfortunately, the script currently cannot always discern whether an NPC is (un)attackable, so at times this may lead to the mez not being used when it is safe to do so.",
    },
    -- Targets
    ['MezStopHPs']                             = {
        DisplayName = "Mez Stop HPs",
        Group = "Abilities",
        Header = "Mez",
        Category = "Mez Targets",
        Index = 1,
        Default = 80,
        Min = 1,
        Max = 100,
        Tooltip = "Don't try to mez a mob that is below this HP%.",
        ConfigType = "Advanced",
    },
    ['AutoLevelRange']                         = {
        DisplayName = "Auto Level Range",
        Group = "Abilities",
        Header = "Mez",
        Category = "Mez Targets",
        Index = 2,
        Default = true,
        Tooltip = "Use automatic mez max-level detection based on the current mez spell.",
        ConfigType = "Advanced",
    },
    ['MezMinLevel']                            = {
        DisplayName = "Mez Min Level",
        Group = "Abilities",
        Header = "Mez",
        Category = "Mez Targets",
        Index = 3,
        Default = 1,
        Min = 1,
        Max = 200,
        Tooltip = "If Auto Level Range is disabled, the minimum level of a potential mez target for mez spells.",
        ConfigType = "Advanced",
    },
    ['MezMaxLevel']                            = {
        DisplayName = "Mez Max Level",
        Group = "Abilities",
        Header = "Mez",
        Category = "Mez Targets",
        Index = 4,
        Default = 200,
        Min = 1,
        Max = 200,
        Tooltip = "If Auto Level Range is disabled, the maximum level of a potential mez target for mez spells.",
        ConfigType = "Advanced",
    },

    [string.format("%s_Popped", Module._name)] = {
        DisplayName = Module._name .. " Popped",
        Type = "Custom",
        Default = false,
    },
}

function Module:New()
    return Base.New(self)
end

function Module:ShouldRender()
    return Modules:ExecModule("Class", "CanMez")
end

function Module:Render()
    Base.Render(self)

    ImGui.NewLine()

    if self.ModuleLoaded then
        -- CCEd targets
        if ImGui.CollapsingHeader("CC Target List") then
            ImGui.Indent()
            if ImGui.BeginTable("MezzedList", 4, bit32.bor(ImGuiTableFlags.Resizable, ImGuiTableFlags.Borders)) then
                ImGui.TableSetupColumn('Id', (ImGuiTableColumnFlags.WidthFixed), 70.0)
                ImGui.TableSetupColumn('Duration', (ImGuiTableColumnFlags.WidthFixed), 150.0)
                ImGui.TableSetupColumn('Name', (ImGuiTableColumnFlags.WidthFixed), 250.0)
                ImGui.TableSetupColumn('Spell', (ImGuiTableColumnFlags.WidthStretch), 150.0)
                ImGui.TableHeadersRow()
                for _, data in ipairs(self:GetTrackerDisplayRows()) do
                    ImGui.TableNextColumn()
                    ImGui.Text(tostring(data.id))
                    ImGui.TableNextColumn()
                    if data.duration > 30000 then
                        ImGui.PushStyleColor(ImGuiCol.Text, Globals.Constants.Colors.ConditionPassColor)
                    elseif data.duration > 15000 then
                        ImGui.PushStyleColor(ImGuiCol.Text, Globals.Constants.Colors.ConditionMidColor)
                    else
                        ImGui.PushStyleColor(ImGuiCol.Text, Globals.Constants.Colors.ConditionFailColor)
                    end
                    ImGui.Text(tostring(Strings.FormatTime(math.max(0, data.duration / 1000))))
                    ImGui.PopStyleColor()
                    ImGui.TableNextColumn()
                    ImGui.Text(data.name)
                    ImGui.TableNextColumn()
                    ImGui.Text(data.mez_spell)
                end
                ImGui.EndTable()
            end
            ImGui.Unindent()
        end

        ImGui.Separator()
        -- Immune targets
        if ImGui.CollapsingHeader("Immune Target List") then
            ImGui.Indent()
            if ImGui.BeginTable("Immune", 2, bit32.bor(ImGuiTableFlags.None, ImGuiTableFlags.Borders)) then
                ImGui.TableSetupColumn('Id', (ImGuiTableColumnFlags.WidthFixed), 70.0)
                ImGui.TableSetupColumn('Name', (ImGuiTableColumnFlags.WidthStretch), 250.0)
                ImGui.TableHeadersRow()
                for id, data in pairs(self.TempSettings.MezImmune) do
                    ImGui.TableNextColumn()
                    ImGui.Text(tostring(id))
                    ImGui.TableNextColumn()
                    ImGui.Text(data.name)
                end
                ImGui.EndTable()
            end
            ImGui.Unindent()
        end
    end
end

function Module:HandleMezBroke(mobName, breakerName)
    Logger.log_debug("%s broke mez on ==> %s", breakerName, mobName)
    for id, data in pairs(self.TempSettings.MezTracker) do
        local spawn = mq.TLO.Spawn(id)
        if (spawn() and (spawn.CleanName() or "") == mobName) or (data.name or "") == mobName then
            self.TempSettings.MezTracker[id] = nil
        end
    end
    Comms.HandleAnnounce(
        Comms.FormatChatEvent("Mez Broken", mobName, breakerName), Config:GetSetting('MezAnnounceGroup'),
        Config:GetSetting('MezAnnounce'), Config:GetSetting('AnnounceToRaidIfInRaid'))
end

function Module:AddImmuneTarget(mobId, mobData)
    if self.TempSettings.MezImmune[mobId] ~= nil then return end

    self.TempSettings.MezImmune[mobId] = mobData
end

function Module:IsMezImmune(mobId)
    return self.TempSettings.MezImmune[mobId] ~= nil
end

function Module:ResetMezStates()
    self.TempSettings.MezImmune = {}
    self.TempSettings.MezTracker = {}
end

function Module:GetMezSpell()
    if Core.MyClassIs("BRD") then
        return Modules:ExecModule("Class", "GetResolvedActionMapItem", "MezSong")
    end
    if Core.MyClassIs("ENC") and (Config:GetSetting('TwincastMez', true) or 0) > 1 then
        local twincastMez = Modules:ExecModule("Class", "GetResolvedActionMapItem", "TwinCastMez")
        if twincastMez and twincastMez() then return twincastMez end
    end
    return Modules:ExecModule("Class", "GetResolvedActionMapItem", "MezSpell")
end

function Module:GetAEMezSpell()
    if Core.MyClassIs("BRD") then
        return Modules:ExecModule("Class", "GetResolvedActionMapItem", "MezAESong")
    end

    return Modules:ExecModule("Class", "GetResolvedActionMapItem", "MezAESpell")
end

--- True when any XT hater still needs mez (or refresh). Class skips DPS rotations while true.
---@return boolean
function Module:HasPendingXtCcWork()
    if not Config:GetSetting('MezOn') then return false end
    local mezSpell = self:GetMezSpell()
    if not mezSpell or not mezSpell() then return false end
    local castWindow = self:GetMezCastWindow(mezSpell)
    local haterCount = Targeting.GetXTHaterCount()
    local needsWork = self:ScanXtMezNeeds(Globals.AutoTargetID, castWindow, haterCount, mezSpell)
    return needsWork
end

---@param skipInitialAttackOff boolean? When true, caller already stopped attack (DoMez path).
function Module:MezNow(mezId, useAE, useAA, skipInitialAttackOff)
    if mezId == 0 or not self:IsValidMezTarget(mezId) then
        Logger.log_debug("\ayMezGate:\ax MezNow skipped for %d — not a valid mez target (charmed/immune/etc).", mezId)
        return
    end

    if not skipInitialAttackOff then
        Core.DoCmd("/attack off")
    end
    local currentTargetID = mq.TLO.Target.ID()
    local retryCount = Config:GetSetting('CastRetryCountBeta')

    Targeting.SetTarget(mezId, true)

    local mezSpell = self:GetMezSpell()
    local aeMezSpell = self:GetAEMezSpell()

    if useAE then
        if not aeMezSpell or not aeMezSpell() then return end
        Logger.log_debug("Performing AE MEZ --> %d", mezId)

        if not Casting.SpellReady(aeMezSpell) then
            -- previous code checked for the enchanter class, but AAready will simply return false on any other class
            -- lets only try to use beam of slumber if we are in global, since a beam may not catch everything.
            if useAA and Config:GetSetting('DoAAMez') and Casting.AAReady("Beam of Slumber") then
                -- This is a beam AE so I need ot face the target and cast.
                Core.DoCmd("/face fast")
                -- Delay to wait till face finishes
                mq.delay(5)
                Comms.HandleAnnounce(Comms.FormatChatEvent("Mez", "AoE Around " .. (mq.TLO.Spawn(mezId).CleanName() or "Unknown"), "AA: Beam of Slumber"),
                    Config:GetSetting('MezAnnounceGroup'),
                    Config:GetSetting('MezAnnounce'), Config:GetSetting('AnnounceToRaidIfInRaid'))
                Casting.UseAA("Beam of Slumber", mezId, false, retryCount)
                mq.doevents('ImmuneMez')
                return
            elseif (mq.TLO.Me.GemTimer(aeMezSpell.RankName())() or -1) == 0 then
                local maxWaitToMez = 1500 + (mq.TLO.Window("CastingWindow").Open() and (mq.TLO.Me.Casting.MyCastTime() or 3000) or 0)
                while maxWaitToMez > 0 do
                    Logger.log_verbose("MEZ: Waiting for cast or movement to finish to use AE Mez.")
                    if Casting.SpellReady(aeMezSpell) then
                        break
                    end
                    mq.delay(50)
                    mq.doevents()
                    Events.DoEvents()
                    maxWaitToMez = maxWaitToMez - 50
                end
                if maxWaitToMez <= 0 and not Casting.SpellReady(aeMezSpell) then
                    Logger.log_verbose("Mez: Timeout while waiting to use AE Mez (%s).", aeMezSpell)
                    return
                end
            else
                Logger.log_verbose("Mez: Our AEMez Spell (%s) or AA does not appear to be ready.", aeMezSpell)
            end
        end

        -- we might have waited.
        if Casting.SpellReady(aeMezSpell) then
            Comms.HandleAnnounce(
                Comms.FormatChatEvent("Mez", "AoE Around " .. (mq.TLO.Spawn(mezId).CleanName() or "Unknown"), aeMezSpell.RankName()), Config:GetSetting('MezAnnounceGroup'),
                Config:GetSetting('MezAnnounce'), Config:GetSetting('AnnounceToRaidIfInRaid'))

            if Core.MyClassIs("brd") then
                Casting.UseSong(aeMezSpell.RankName(), mezId, false, retryCount)
            else
                Casting.UseSpell(aeMezSpell.RankName(), mezId, false, true, retryCount)
            end
        end

        -- In case they're mez immune
        mq.doevents('ImmuneMez')
    else
        Logger.log_debug("Performing Single Target MEZ --> %d", mezId)
        if not Casting.BeginMezMAWatch(mezId) then
            Targeting.SetTarget(currentTargetID, true)
            return
        end

        if useAA and Core.MyClassIs("brd") and Casting.AAReady("Dirge of the Sleepwalker") and Config:GetSetting('DoAAMez') then
            -- Bard AA Mez is Dirge of the Sleepwalker
            -- Only bards have single target AA Mez
            -- Cast and Return
            Comms.HandleAnnounce(
                Comms.FormatChatEvent("Mez", mq.TLO.Spawn(mezId).CleanName(), "AA: Dirge of the Sleepwalker"),
                Config:GetSetting('MezAnnounceGroup'),
                Config:GetSetting('MezAnnounce'), Config:GetSetting('AnnounceToRaidIfInRaid'))
            Casting.UseAA("Dirge of the Sleepwalker", mezId, false, retryCount)

            mq.doevents('ImmuneMez')
            if Casting.GetLastCastResultId() == Globals.Constants.CastResults.CAST_SUCCESS then
                self:RecordMezSuccess(mezId, "Dirge of the Sleepwalker")
                Comms.HandleAnnounce(Comms.FormatChatEvent("Mez Success", mq.TLO.Spawn(mezId).CleanName(), "AA:Dirge of the Sleepwalker"), Config:GetSetting('MezAnnounceGroup'),
                    Config:GetSetting('MezAnnounce'),
                    Config:GetSetting('AnnounceToRaidIfInRaid'))
            else
                Comms.HandleAnnounce(Comms.FormatChatEvent("Mez Failed", mq.TLO.Spawn(mezId).CleanName(), "AA:Dirge of the Sleepwalker"), Config:GetSetting('MezAnnounceGroup'),
                    Config:GetSetting('MezAnnounce'), Config:GetSetting('AnnounceToRaidIfInRaid'))
            end

            mq.doevents('ImmuneMez')
            Casting.ClearMezMAWatch()
            Targeting.SetTarget(currentTargetID, true)
            return
        end

        if not mezSpell or not mezSpell() then
            Casting.ClearMezMAWatch()
            Targeting.SetTarget(currentTargetID, true)
            return
        end

        if not Casting.SpellReady(mezSpell) then
            if (mq.TLO.Me.GemTimer(mezSpell.RankName())() or -1) == 0 then
                local maxWaitToMez = 1500 + (mq.TLO.Window("CastingWindow").Open() and (mq.TLO.Me.Casting.MyCastTime() or 3000) or 0)
                while maxWaitToMez > 0 do
                    Logger.log_verbose("MEZ: Waiting for cast or movement to finish to use ST Mez.")
                    if Casting.MezTargetIsMA(mezId) then
                        Logger.log_debug("\ayMezGate:\ax Abort ST mez wait — mob %d became MA AutoTarget.", mezId)
                        Casting.ClearMezMAWatch()
                        Targeting.SetTarget(currentTargetID, true)
                        return
                    end
                    if aeMezSpell and aeMezSpell() and Targeting.GetXTHaterCount() >= Config:GetSetting('MezAECount') and ((mq.TLO.Me.GemTimer(aeMezSpell.RankName())() or -1) == 0 or (Config:GetSetting('DoAAMez') and mq.TLO.Me.AltAbilityReady("Beam of Slumber"))) then
                        Logger.log_debug("Mez: Waiting for single mez to be ready, but high number of targets, let's check if AE Mez is needed again before we start singles.")
                        self:AEMezCheck()
                        Casting.ClearMezMAWatch()
                        Targeting.SetTarget(currentTargetID, true)
                        return
                    end
                    if Casting.SpellReady(mezSpell) then
                        break
                    end
                    mq.delay(50)
                    mq.doevents()
                    Events.DoEvents()
                    maxWaitToMez = maxWaitToMez - 50
                end
                if maxWaitToMez <= 0 and not Casting.SpellReady(mezSpell) then
                    Logger.log_verbose("Mez: Timeout while waiting to use ST Mez (%s).", mezSpell)
                end
            else
                Logger.log_verbose("Mez: Our ST Mez Spell (%s) does not appear to be ready.", mezSpell)
            end
        end

        -- we might have waited.
        if Casting.SpellReady(mezSpell) and not Casting.MezTargetIsMA(mezId) then
            if Core.MyClassIs("brd") then
                Casting.UseSong(mezSpell.RankName(), mezId, false, retryCount)
            else
                -- This may not work for Bards but will work for NEC/ENCs
                Casting.UseSpell(mezSpell.RankName(), mezId, false, false, retryCount)
            end

            -- In case they're mez immune
            mq.doevents('ImmuneMez')

            local castResult = Casting.GetLastCastResultId()
            if castResult == Globals.Constants.CastResults.CAST_SUCCESS or castResult == Globals.Constants.CastResults.CAST_TAKEHOLD then
                self:RecordMezSuccess(mezId, mezSpell.RankName.Name())
                Comms.HandleAnnounce(Comms.FormatChatEvent("Mez Success", mq.TLO.Spawn(mezId).CleanName(), mezSpell.RankName()), Config:GetSetting('MezAnnounceGroup'),
                    Config:GetSetting('MezAnnounce'), Config:GetSetting('AnnounceToRaidIfInRaid'))
            else
                Comms.HandleAnnounce(Comms.FormatChatEvent("Mez Failed", mq.TLO.Spawn(mezId).CleanName(), mezSpell.RankName()), Config:GetSetting('MezAnnounceGroup'),
                    Config:GetSetting('MezAnnounce'), Config:GetSetting('AnnounceToRaidIfInRaid'))
            end
        end

        mq.doevents('ImmuneMez')
        Casting.ClearMezMAWatch()
        Targeting.SetTarget(currentTargetID, true)
        return
    end

    Targeting.SetTarget(currentTargetID, true)
end

function Module:AEMezCheck()
    if not Config:GetSetting('DoAEMez') then return end

    local mezNPCFilter = string.format("npc radius %d targetable los playerstate 4", Config:GetSetting('MezRadius'))
    local mezNPCPetFilter = string.format("npcpet radius %d targetable los playerstate 4", Config:GetSetting('MezRadius'))
    local aeCount = mq.TLO.SpawnCount(mezNPCFilter)() + mq.TLO.SpawnCount(mezNPCPetFilter)()

    local aeMezSpell = self:GetAEMezSpell()

    if not aeMezSpell or not aeMezSpell() then return end

    if not aeMezSpell.AERange() or aeMezSpell.AERange() == 0 then
        Logger.log_warn("\arWarning AE Mez Spell: %s has no AERange!", aeMezSpell.RankName.Name())
    end

    -- Make sure the mobs of concern are within range
    if aeCount < Config:GetSetting('MezAECount') then return end

    if Config:GetSetting('SafeAEMez') then --not Core.MyClassIs("brd") then
        -- Get the nearest spawn meeting our npc search criteria
        local angryMobCount = 0
        local mobCount = 999

        if Core.MyClassIs("brd") then
            --using MezRadius because our instrument-modified song range is not exposed and would require excessive code to determine (checking base(1) of focus2 itemspell and math, etc)
            angryMobCount = mq.TLO.SpawnCount(string.format("npc xtarhater radius %d", Config:GetSetting('MezRadius')))()
            mobCount = mq.TLO.SpawnCount(string.format("npc radius %d", Config:GetSetting('MezRadius')))()
        else --I think this can all be refactored to something simpler (we need to check from the AutoTarget, which is who we end up casting on), will look later. -- Algar 1/7/2025
            local nearestSpawn = mq.TLO.NearestSpawn(1, mezNPCFilter)
            if not nearestSpawn or not nearestSpawn() then
                nearestSpawn = mq.TLO.NearestSpawn(1, mezNPCPetFilter)
            end

            if not nearestSpawn or not nearestSpawn() then
                return
            end
            -- Next make sure casting our AE won't anger more mobs -- I'm lazy and not checking the AERange of the AA. I'm gonna assume if the
            -- AERange of the normal spell will piss them off, then the AA probably would too.
            angryMobCount = mq.TLO.SpawnCount(string.format("npc xtarhater loc %0.2f, %0.2f radius %d", nearestSpawn.X(),
                nearestSpawn.Y(), aeMezSpell.AERange() or 0))()
            mobCount = mq.TLO.SpawnCount(string.format("npc loc %0.2f, %0.2f radius %d", nearestSpawn.X(),
                nearestSpawn.Y(), aeMezSpell.AERange() or 0))()
        end
        if mobCount > angryMobCount then return end
    end

    self:StopCast()

    -- Call MezNow and pass the AE flag and allow it to use the AA if the Spell isn't ready.
    Logger.log_debug("\awNOTICE:\ax Re-targeting to our main assist's mob.")

    if not Globals.BackOffFlag then
        Combat.FindBestAutoTarget()
        if Globals.AutoTargetID > 0 then
            self:MezNow(Globals.AutoTargetID, true, true)
        end
    end

    mq.doevents('ImmuneMez')
end

--- True when a Mezzed buff TLO is present (ID, spell name, or readable duration).
--- Magical spawns often expose Mezzed() / Duration but not Mezzed.ID.
---@param mezBuff any?
---@return boolean
function Module:MezzedBuffActive(mezBuff)
    if not mezBuff then return false end
    if mezBuff.ID and (mezBuff.ID() or 0) > 0 then return true end
    local spellName = mezBuff()
    if spellName and spellName ~= "" then return true end
    local durationMs = self:GetMezBuffDurationMs(mezBuff)
    return durationMs ~= nil and durationMs > 0
end

--- Spell name from a Mezzed buff TLO child (nil-safe; XT/Spawn may omit Mezzed entirely).
---@param mezBuff any?
---@return string?
function Module:GetMezzedSpellName(mezBuff)
    if not mezBuff then return nil end
    local name = mezBuff()
    if name and name ~= "" then return name end
    return nil
end

--- Remaining mez buff time in milliseconds (nil when unreadable).
---@param mezBuff any Mezzed buff TLO (XT / Spawn / Target)
---@return number?
function Module:GetMezBuffDurationMs(mezBuff)
    if not mezBuff then return nil end
    local dur = mezBuff.Duration
    if not dur then return nil end
    if dur.TotalMilliseconds then
        local ms = dur.TotalMilliseconds()
        if ms and ms > 0 then return ms end
    end
    if dur.TotalSeconds then
        local sec = dur.TotalSeconds()
        if sec and sec > 0 then return sec * 1000 end
    end
    return nil
end

--- Cast safety window in milliseconds (time to refresh before mez breaks).
---@param mezSpell any?
---@return number
function Module:GetMezCastWindow(mezSpell)
    mezSpell = mezSpell or self:GetMezSpell()
    if not mezSpell or not mezSpell() then return 0 end
    return mezSpell.MyCastTime() or 0
end

--- Mezzed state via Spawn TLO (no cursor change).
---@param spawnId number
---@return boolean isMezzed
---@return number? durationMs
function Module:GetSpawnMezzedState(spawnId)
    if spawnId == 0 then return false, nil end
    local spawn = mq.TLO.Spawn(spawnId)
    if not spawn or not spawn() or not spawn.Mezzed then return false, nil end
    if not self:MezzedBuffActive(spawn.Mezzed) then return false, nil end
    return true, self:GetMezBuffDurationMs(spawn.Mezzed)
end

--- Mezzed state for an XTarget entry via XT + Spawn TLO (no cursor change).
---@param spawnId number
---@param xtSpawn MQSpawn?
---@return boolean isMezzed
---@return number? durationMs nil when mezzed but remaining time is unreadable
function Module:GetXtMezzedState(spawnId, xtSpawn)
    if spawnId == 0 then return false, nil end

    local xt = xtSpawn
    if xt and xt() and xt.Mezzed and self:MezzedBuffActive(xt.Mezzed) then
        return true, self:GetMezBuffDurationMs(xt.Mezzed)
    end

    return self:GetSpawnMezzedState(spawnId)
end

--- True when XT spawn is in a known mez animation set.
---@param xtSpawn MQSpawn?
---@return boolean
function Module:XtHasMezAnimation(xtSpawn)
    if not xtSpawn or not xtSpawn() then return false end
    return Globals.Constants.RGMezzedAnims:contains(xtSpawn.Animation() or 0)
end

--- Safe Spawn.FindBuff wrapper (MQ requires id/name/detspa syntax, not bare spell names).
---@param spawn MQSpawn?
---@param search string
---@return any? buff TLO
function Module:TrySpawnFindBuff(spawn, search)
    if not spawn or not spawn() or not spawn.FindBuff or not search or search == "" then return nil end
    local buff = spawn.FindBuff(search)
    if buff and buff() then return buff end
    return nil
end

--- Find an active mez/mesmerize buff on spawn (fallback when Mezzed TLO is incomplete).
---@param spawnId number
---@param mezSpell any?
---@return any? buff TLO
function Module:FindMezBuffOnSpawn(spawnId, mezSpell)
    local spawn = mq.TLO.Spawn(spawnId)
    if not spawn or not spawn() then return nil end

    mezSpell = mezSpell or self:GetMezSpell()
    if mezSpell and mezSpell() then
        local spellId = mezSpell.ID()
        if spellId and spellId > 0 then
            local byId = self:TrySpawnFindBuff(spawn, "id " .. tostring(spellId))
            if byId then return byId end
        end
        local rankName = mezSpell.RankName.Name()
        if rankName and rankName ~= "" then
            local byName = self:TrySpawnFindBuff(spawn, 'name "' .. rankName .. '"')
            if byName then return byName end
        end
    end

    -- SPA 31 = Mesmerize
    return self:TrySpawnFindBuff(spawn, "detspa 31")
end

---@param mobId number
---@return number? remainingMs
function Module:GetTrackerRemainingMs(mobId)
    local entry = self.TempSettings.MezTracker[mobId]
    if not entry then return nil end
    local remaining = entry.remainingMs or 0
    if remaining > 0 then return remaining end
    return nil
end

---@param durationMs number raw buff duration from TLO or spell metadata
---@param castWindow number
---@return number
function Module:ComputeTrackerRemainingMs(durationMs, castWindow)
    return math.max(durationMs - castWindow, castWindow)
end

---@param durationMs number?
---@param castWindow number
---@return "stable"|"refresh"|"unreadable"
function Module:ClassifyMezDuration(durationMs, castWindow)
    if durationMs and durationMs > castWindow then return "stable" end
    if durationMs and durationMs > 0 then return "refresh" end
    return "unreadable"
end

---@param mobId number
---@param durationMs number
---@param spellName string?
---@param mobName string?
---@param castWindow number?
function Module:SetTrackerEntry(mobId, durationMs, spellName, mobName, castWindow)
    if mobId == 0 or not durationMs or durationMs <= 0 then return end

    castWindow = castWindow or self:GetMezCastWindow()
    local spawn = mq.TLO.Spawn(mobId)
    self.TempSettings.MezTracker[mobId] = {
        name = mobName or (spawn() and spawn.CleanName()) or "?",
        remainingMs = self:ComputeTrackerRemainingMs(durationMs, castWindow),
        last_check = Globals.GetTimeMS(),
        mez_spell = spellName or "Unknown",
    }
    Logger.log_debug("\ayMezGate:\ax Tracking mez on %d (%s) for ~%s (spell %s).", mobId,
        self.TempSettings.MezTracker[mobId].name,
        Strings.FormatTime(self.TempSettings.MezTracker[mobId].remainingMs / 1000),
        self.TempSettings.MezTracker[mobId].mez_spell)
end

--- Refresh tracker countdown from a live TLO duration read.
---@param mobId number
---@param durationMs number
---@param castWindow number?
function Module:RefreshTrackerDuration(mobId, durationMs, castWindow)
    local entry = self.TempSettings.MezTracker[mobId]
    if not entry or not durationMs or durationMs <= 0 then return end
    castWindow = castWindow or self:GetMezCastWindow()
    entry.remainingMs = self:ComputeTrackerRemainingMs(durationMs, castWindow)
    entry.last_check = Globals.GetTimeMS()
end

--- Decrement MezTracker remaining times (Original UpdateTimings equivalent).
function Module:UpdateMezTimings()
    local now = Globals.GetTimeMS()
    for _, data in pairs(self.TempSettings.MezTracker) do
        if data.last_check then
            local elapsed = now - data.last_check
            data.remainingMs = math.max(0, (data.remainingMs or 0) - elapsed)
        end
        data.last_check = now
    end
end

--- Spawn ID lookup only (no cursor). True when manual or auto charm applied Charmed / PC pet Master.
---@param mobId number
---@return boolean
function Module:IsCharmedSpawnId(mobId)
    if mobId == 0 then return false end
    return Combat.TargetIsCharmedSpawn(mq.TLO.Spawn(mobId))
end

--- Drop dead, corpse, charmed, out-of-range, or MA entries from the tracker.
function Module:PruneMezTracker()
    local assistId = Globals.AutoTargetID
    local mezRadius = Config:GetSetting('MezRadius')

    for id, _ in pairs(self.TempSettings.MezTracker) do
        if id == assistId then
            self.TempSettings.MezTracker[id] = nil
        else
            local spawn = mq.TLO.Spawn(id)
            if not spawn or not spawn() or spawn.Dead() or (spawn.Type() or ""):lower() == "corpse" then
                self.TempSettings.MezTracker[id] = nil
            elseif Combat.TargetIsCharmedSpawn(spawn) then
                Logger.log_debug("\ayMezGate:\ax Tracker %d (%s) charmed — removing keep entry.", id, spawn.CleanName() or "?")
                self.TempSettings.MezTracker[id] = nil
            elseif (spawn.Distance() or 999) > mezRadius then
                Logger.log_verbose("\ayMezGate:\ax Tracker %d (%s) out of mez radius — removing.", id, spawn.CleanName() or "?")
                self.TempSettings.MezTracker[id] = nil
            end
        end
    end
end

---@param mobId number
---@param castWindow number
---@param mezSpell any?
---@param xtSpawn MQSpawn?
---@return boolean
function Module:IsTrackerStable(mobId, castWindow, mezSpell, xtSpawn)
    local isMezzed, durationMs = self:GetMobMezzedState(mobId, xtSpawn, mezSpell)
    if not isMezzed then return false end
    if not durationMs then return true end
    return durationMs > castWindow
end

--- Resolve mez duration after a successful cast (TLO → FindBuff → spell metadata fallback).
---@param mobId number
---@param spellName string
---@return number durationMs
function Module:ResolveMezDurationMs(mobId, spellName)
    local targetMezzed = mq.TLO.Target() and mq.TLO.Target.Mezzed or nil
    local durationMs = self:GetMezBuffDurationMs(targetMezzed)
    if not durationMs or durationMs <= 0 then
        local buff = self:FindMezBuffOnSpawn(mobId)
        durationMs = buff and self:GetMezBuffDurationMs(buff) or nil
    end
    if not durationMs or durationMs <= 0 then
        local spell = mq.TLO.Spell(spellName)
        if spell and spell() then
            local dur = spell.MyDuration
            if dur and dur.TotalMilliseconds then
                durationMs = dur.TotalMilliseconds()
            elseif dur and dur.TotalSeconds then
                durationMs = (dur.TotalSeconds() or 0) * 1000
            end
        end
    end
    if not durationMs or durationMs <= 0 then
        durationMs = 60000
    end
    return durationMs
end

--- Register a mob on the slim tracker after ST mez success (Magical / weak Mezzed TLO).
---@param mobId number
---@param spellName string
function Module:RecordMezSuccess(mobId, spellName)
    if mobId == 0 then return end
    self:SetTrackerEntry(mobId, self:ResolveMezDurationMs(mobId, spellName), spellName)
end

--- Live mez probe without MezTracker. nil = inconclusive (Magical / unreadable TLO).
---@param spawnId number
---@param xtSpawn MQSpawn?
---@param mezSpell any?
---@return boolean? isMezzed true = mezzed, false = slot read confirms no mez, nil = inconclusive
---@return number? durationMs
function Module:ProbeLiveMezzedState(spawnId, xtSpawn, mezSpell)
    if spawnId == 0 then return false, nil end

    local spawn = mq.TLO.Spawn(spawnId)
    if not spawn or not spawn() then return false, nil end

    local mezzedSlotEmpty = false

    if xtSpawn and xtSpawn() then
        if xtSpawn.Mezzed then
            if self:MezzedBuffActive(xtSpawn.Mezzed) then
                return true, self:GetMezBuffDurationMs(xtSpawn.Mezzed)
            end
            mezzedSlotEmpty = true
        end
        if self:XtHasMezAnimation(xtSpawn) then
            return true, nil
        end
    end

    if spawn.Mezzed then
        if self:MezzedBuffActive(spawn.Mezzed) then
            return true, self:GetMezBuffDurationMs(spawn.Mezzed)
        end
        mezzedSlotEmpty = true
    end

    local buff = self:FindMezBuffOnSpawn(spawnId, mezSpell)
    if buff then
        return true, self:GetMezBuffDurationMs(buff)
    end

    if mezzedSlotEmpty then
        return false, nil
    end

    return nil, nil
end

--- Hybrid mezzed detection: live TLO first; tracker fallback only when live is inconclusive.
---@param spawnId number
---@param xtSpawn MQSpawn?
---@param mezSpell any?
---@return boolean isMezzed
---@return number? durationMs
function Module:GetMobMezzedState(spawnId, xtSpawn, mezSpell)
    if self:IsCharmedSpawnId(spawnId) then
        self.TempSettings.MezTracker[spawnId] = nil
        return false, nil
    end

    local castWindow = self:GetMezCastWindow(mezSpell)
    local liveMezzed, liveDuration = self:ProbeLiveMezzedState(spawnId, xtSpawn, mezSpell)

    if liveMezzed == true then
        if liveDuration and liveDuration > 0 then
            if self.TempSettings.MezTracker[spawnId] then
                self:RefreshTrackerDuration(spawnId, liveDuration, castWindow)
            end
        end
        return true, liveDuration or self:GetTrackerRemainingMs(spawnId)
    end

    if liveMezzed == false then
        if self.TempSettings.MezTracker[spawnId] then
            Logger.log_debug("\ayMezGate:\ax Spawn %d live mez clear — dropping tracker entry.", spawnId)
            self.TempSettings.MezTracker[spawnId] = nil
        end
        return false, nil
    end

    local trackerRemaining = self:GetTrackerRemainingMs(spawnId)
    if trackerRemaining then
        return true, trackerRemaining
    end

    return false, nil
end

--- Rows for the CC target UI table (slim MezTracker list).
---@return table[]
function Module:GetTrackerDisplayRows()
    local rows = {}
    for id, data in pairs(self.TempSettings.MezTracker) do
        table.insert(rows, {
            id = id,
            name = data.name or "?",
            duration = data.remainingMs or 0,
            mez_spell = data.mez_spell or "Unknown",
        })
    end
    table.sort(rows, function(a, b) return a.id < b.id end)
    return rows
end

--- Phase 1: tracked mobs (Spawn-based; survives HateClear / off-XT). PruneMezTracker runs before this.
---@param assistId number
---@param castWindow number
---@param haterCount number
---@return boolean needsWork
---@return number? mobId
---@return boolean needsRefresh
function Module:ScanTrackerMezNeeds(assistId, castWindow, haterCount, mezSpell)
    for id, data in pairs(self.TempSettings.MezTracker) do
        if id > 0 and id ~= assistId then
            if self:IsCharmedSpawnId(id) then
                self.TempSettings.MezTracker[id] = nil
            else
                local isMezzed, durationMs = self:GetMobMezzedState(id, nil, mezSpell)
                if isMezzed then
                    local timing = self:ClassifyMezDuration(durationMs, castWindow)
                    if timing == "refresh" then
                        Logger.log_debug("\ayMezGate:\ax Tracker %d (%s) mez expiring (%s).", id, data.name or "?",
                            durationMs and Strings.FormatTime(durationMs / 1000) or "?")
                        return true, id, true
                    end
                else
                    local spawn = mq.TLO.Spawn(id)
                    if haterCount >= Config:GetSetting('MezStartCount') and spawn() and self:IsValidMezTarget(id) and spawn.Aggressive() then
                        Logger.log_debug("\ayMezGate:\ax Tracker %d (%s) mez broken — needs mez.", id, data.name or "?")
                        self.TempSettings.MezTracker[id] = nil
                        return true, id, false
                    end
                    self.TempSettings.MezTracker[id] = nil
                end
            end
        end
    end

    return false, nil, false
end

--- Phase 2: XT haters for first-time mezzes (and sync newly mezzed mobs into tracker).
---@param assistId number
---@param castWindow number
---@param haterCount number
---@param mezSpell any
---@return boolean needsWork
---@return number? mobId
---@return boolean needsRefresh
function Module:ScanXtMezNeeds(assistId, castWindow, haterCount, mezSpell)
    if haterCount < Config:GetSetting('MezStartCount') then
        return false, nil, false
    end
    if haterCount > Config:GetSetting('MaxMezCount') then
        return false, nil, false
    end

    local xtCount = mq.TLO.Me.XTarget() or 0
    for i = 1, xtCount do
        local xt = mq.TLO.Me.XTarget(i)
        if xt() and not xt.Dead() and (xt.Type() or ""):lower() ~= "corpse" then
            local id = xt.ID() or 0
            if id > 0 and id ~= assistId and not self:IsTrackerStable(id, castWindow, mezSpell, xt) then
                local isMezzed, durationMs = self:GetMobMezzedState(id, xt, mezSpell)
                if isMezzed then
                    local timing = self:ClassifyMezDuration(durationMs, castWindow)
                    if timing == "stable" then
                        if not self.TempSettings.MezTracker[id] and durationMs then
                            local spellLabel = self:GetMezzedSpellName(xt.Mezzed)
                                or (mezSpell and mezSpell() and mezSpell.RankName())
                                or "Unknown"
                            self:SetTrackerEntry(id, durationMs, spellLabel, xt.CleanName(), castWindow)
                        end
                    elseif timing == "refresh" then
                        if self:IsCharmedSpawnId(id) then
                            self.TempSettings.MezTracker[id] = nil
                        else
                            Logger.log_debug("\ayMezGate:\ax XT %d (%s) mez expiring (%s).", id, xt.CleanName() or "?",
                                durationMs and Strings.FormatTime(durationMs / 1000) or "?")
                            return true, id, true
                        end
                    end
                elseif not self:IsValidMezTarget(id) then
                    -- skip invalid targets silently
                elseif not xt.Aggressive() then
                    -- non-aggressive = CC stable
                else
                    Logger.log_debug("\ayMezGate:\ax XT %d (%s) needs mez", id, xt.CleanName() or "?")
                    return true, id, false
                end
            end
        end
    end

    return false, nil, false
end

--- Hybrid scan: tracker keep (off-XT) then XT for new mezzes.
---@param mezSpell any
---@param castWindow number
---@param haterCount number
---@return boolean needsWork
---@return number? mobId
---@return boolean needsRefresh true when mez is still active but within cast window (re-mez before break)
function Module:ScanMezNeeds(mezSpell, castWindow, haterCount)
    if not mezSpell or not mezSpell() then return false, nil, false end

    local assistId = Globals.AutoTargetID

    local needsWork, mobId, needsRefresh = self:ScanTrackerMezNeeds(assistId, castWindow, haterCount, mezSpell)
    if needsWork then return needsWork, mobId, needsRefresh end

    return self:ScanXtMezNeeds(assistId, castWindow, haterCount, mezSpell)
end

function Module:IsValidMezTarget(mobId)
    local spawn = mq.TLO.Spawn(mobId)

    if Combat.TargetIsCharmedSpawn(spawn) then return false end

    local pet = mq.TLO.Me.Pet
    if pet() and pet.ID() > 0 and (spawn.ID() or 0) == pet.ID() then return false end

    if Targeting.IsTempPet(spawn) then
        Logger.log_debug("\ayMezGate:\ax Skipping Mob ID: %d Name: %s Level: %d as it is a temp PC pet.",
            spawn.ID(), spawn.CleanName(), spawn.Level() or 0)
        return false
    end

    -- Is the mob ID in our mez immune list? If so, skip.
    if self:IsMezImmune(mobId) then
        Logger.log_debug("\ayMezGate:\ax Skipping Mob ID: %d Name: %s Level: %d as it is in our immune list.",
            spawn.ID(), spawn.CleanName(), spawn.Level() or 0)
        return false
    end
    -- Here's where we can add a necro check to see if the spawn is undead or not. If it's not
    -- undead it gets added to the mez immune list.
    if Targeting.TargetBodyIs(spawn, "giant") then
        Logger.log_debug(
            "\ayMezGate:\ax Adding ID: %d Name: %s Level: %d to our immune list as it is a giant.", spawn.ID(),
            spawn.CleanName(),
            spawn.Level())
        self:AddImmuneTarget(spawn.ID(), { id = spawn.ID(), name = spawn.CleanName(), })
        return false
    end

    if spawn and not spawn.LineOfSight() then
        Logger.log_debug("\ayMezGate:\ax Skipping Mob ID: %d Name: %s Level: %d - No LOS.", spawn.ID(),
            spawn.CleanName(), spawn.Level() or 0)
        return false
    end

    if (spawn.PctHPs() or 0) < Config:GetSetting('MezStopHPs') then
        Logger.log_debug("\ayMezGate:\ax Skipping Mob ID: %d Name: %s Level: %d - HPs too low.", spawn.ID(),
            spawn.CleanName(), spawn.Level() or 0)
        return false
    end

    if (spawn.Distance() or 999) > Config:GetSetting('MezRadius') then
        Logger.log_debug("\ayMezGate:\ax Skipping Mob ID: %d Name: %s Level: %d - Out of Mez Radius",
            spawn.ID(), spawn.CleanName(), spawn.Level() or 0)
        return false
    end

    return true
end

function Module:RestoreAssistTarget()
    if Globals.AutoTargetID > 0 and Core.ValidCombatTarget(Globals.AutoTargetID) and mq.TLO.Target.ID() ~= Globals.AutoTargetID then
        Targeting.SetTarget(Globals.AutoTargetID, true)
    end
end

--- Hybrid gate: tracker + XT. CC stable → pass through; otherwise mez one mob and block this frame.
function Module:DoMez()
    local mezSpell = self:GetMezSpell()
    if not mezSpell or not mezSpell() then
        self:RestoreAssistTarget()
        return
    end

    local aeMezSpell = self:GetAEMezSpell()
    local castWindow = self:GetMezCastWindow(mezSpell)
    local haterCount = Targeting.GetXTHaterCount()

    self:UpdateMezTimings()
    self:PruneMezTracker()

    -- メズが終わったのに MA 監視フラグだけ残っている場合の掃除（詠唱中は WaitCastFinish が中断を担当）。
    if Globals.MezInterruptOnMATarget and not mq.TLO.Me.Casting() then
        Casting.ClearMezMAWatch()
    end

    local needsWork, mobId, needsRefresh = self:ScanMezNeeds(mezSpell, castWindow, haterCount)
    if not needsWork then
        self:RestoreAssistTarget()
        return
    end

    if not Config:GetSetting('DoSTMez') then
        Logger.log_debug("\ayMezGate:\ax ST mez disabled; mob %d still needs attention.", mobId or 0)
        return
    end

    self:StopAttack()
    self:StopCast()

    if Config:GetSetting('DoAEMez') and haterCount >= Config:GetSetting('MezAECount') then
        local aeReady = aeMezSpell and aeMezSpell() and ((mq.TLO.Me.GemTimer(aeMezSpell.RankName())() or -1) == 0 or (Config:GetSetting('DoAAMez') and mq.TLO.Me.AltAbilityReady("Beam of Slumber")))
        if aeReady then
            self:AEMezCheck()
            self:RestoreAssistTarget()
            mq.doevents()
            return
        end
    end

    if mobId and mobId > 0 then
        Logger.log_debug("\ayMezGate:\ax MezNow on %d (%s)%s.", mobId, mq.TLO.Spawn(mobId).CleanName() or "?",
            needsRefresh and " — refresh" or "")
        self:MezNow(mobId, false, true, true)
    end

    self:RestoreAssistTarget()
    mq.doevents()
end

function Module:GiveTime()
    local combat_state = Combat.GetCachedCombatState()

    if not Core.IsMezzing() then return end

    if mq.TLO.Navigation.Active() or mq.TLO.MoveTo.Moving() then return end
    -- dead... whoops
    if mq.TLO.Me.Hovering() then return end

    if self.CombatState ~= combat_state and combat_state == "Downtime" then
        self:ResetMezStates()
    end

    self.CombatState = combat_state

    self:DoMez()
end

function Module:StopAttack()
    if mq.TLO.Me.Combat() then
        Logger.log_debug("\awMEZ:\ax Stopping attack to avoid breaking mez.")
        Core.DoCmd("/attack off")
        mq.delay(500, function() return mq.TLO.Me.Combat() == false end)
    end
end

function Module:StopCast()
    if mq.TLO.Me.Casting() or Casting.ActiveCastContext then
        Logger.log_debug("\awMEZ:\ax Stopping cast or song so I can mez.")
        Casting.StopCast(true)
    end
end

return Module
