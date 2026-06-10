--[[
    mez_xt_verify.lua — XTarget / Spawn Mezzed TLO をターゲットなしで読めるか検証

    使い方:
        1. mob をメズする
        2. カーソルを別ターゲット（MA 等）に移す（メズした mob を直接ターゲットしない）
        3. /lua run rgmercs/extras/mez_xt_verify
        4. コンソール出力を確認（約 2 秒ごと）
        5. 終了: /mezxt stop

    読み取る項目（いずれも SetTarget しない）:
        - Me.XTarget(i).Mezzed（名 / ID / Duration）
        - Spawn(id).Mezzed（名 / ID / Duration）
        - Spawn(id).FindBuff("detspa 31")（SPA 31 = Mesmerize）
        - XT Animation（rgmercs と同じメズアニメ集合）
        - 参考: カーソルが一致しているときだけ Target.Mezzed（比較用）

    出力の見方:
        - duration_src=XT|Spawn|FindBuff|CACHE_NONE → ターゲットなしで残り秒数が取れた経路
        - duration_src=NONE → メズ済み扱いでも秒数は取れていない
        - mezzed_yes_no=NO だが Target 行だけ YES → カーソル依存（XT/Spawn 弱い）
]]

local mq = require('mq')

local MEZ_ANIMS = { [26] = true, [32] = true, [71] = true, [72] = true, [110] = true, [111] = true, }

local running = true
local scanIntervalMs = 2000
local lastScanMs = 0

local function ts()
    return os.date('%H:%M:%S')
end

local function safeStr(v)
    if v == nil then return 'nil' end
    local s = tostring(v)
    if s == '' then return '""' end
    return s
end

---@param buff any?
---@return string spellName
---@return number? id
---@return number? remainMs
---@return string srcLabel
local function readMezzedBuff(buff, srcLabel)
    if not buff then return 'nil', nil, nil, srcLabel end
    local spellName = buff() or ''
    local id = nil
    if buff.ID then id = buff.ID() end
    local remainMs = nil
    if buff.Duration then
        if buff.Duration.TotalMilliseconds then
            local ms = buff.Duration.TotalMilliseconds()
            if ms and ms > 0 then remainMs = ms end
        end
        if not remainMs and buff.Duration.TotalSeconds then
            local sec = buff.Duration.TotalSeconds()
            if sec and sec > 0 then remainMs = sec * 1000 end
        end
    end
    local active = (id and id > 0) or (spellName ~= '') or (remainMs and remainMs > 0)
    if not active then return spellName, id, nil, srcLabel end
    return spellName, id, remainMs, srcLabel
end

local function tryFindBuff(spawn, search)
    if not spawn or not spawn() or not spawn.FindBuff then return nil end
    local buff = spawn.FindBuff(search)
    if buff and buff() then return buff end
    return nil
end

local function formatRemain(ms)
    if not ms or ms <= 0 then return 'unreadable' end
    local sec = math.floor(ms / 1000)
    return string.format('%d:%02d', math.floor(sec / 60), sec % 60)
end

---@param spawnId number
---@param xt any?
local function probeMob(spawnId, xt)
    local spawn = mq.TLO.Spawn(spawnId)
    local name = (xt and xt() and xt.CleanName()) or (spawn() and spawn.CleanName()) or '?'
    local body = (spawn() and spawn.Body and spawn.Body.Name and spawn.Body.Name()) or '?'
    local cursorId = mq.TLO.Target.ID() or 0
    local onCursor = cursorId == spawnId

    local xtName, xtId, xtMs, xtSrc = 'nil', nil, nil, 'XT'
    if xt and xt() and xt.Mezzed then
        xtName, xtId, xtMs, xtSrc = readMezzedBuff(xt.Mezzed, 'XT')
    end

    local spName, spId, spMs, spSrc = 'nil', nil, nil, 'Spawn'
    if spawn() and spawn.Mezzed then
        spName, spId, spMs, spSrc = readMezzedBuff(spawn.Mezzed, 'Spawn')
    end

    local fbName, fbId, fbMs, fbSrc = 'nil', nil, nil, 'FindBuff'
    if spawn() then
        local fb = tryFindBuff(spawn, 'detspa 31')
        if fb then
            fbName, fbId, fbMs, fbSrc = readMezzedBuff(fb, 'FindBuff')
        end
    end

    local anim = (xt and xt() and xt.Animation and xt.Animation()) or (spawn() and spawn.Animation and spawn.Animation()) or 0
    local mezAnim = MEZ_ANIMS[anim] == true

    local tgName, tgId, tgMs = 'n/a', nil, nil
    if onCursor and mq.TLO.Target.Mezzed then
        tgName, tgId, tgMs = readMezzedBuff(mq.TLO.Target.Mezzed, 'Target')
    end

    local mezzedNoTarget = (xtMs and xtMs > 0) or (xtName ~= '' and xtName ~= 'nil')
        or (spMs and spMs > 0) or (spName ~= '' and spName ~= 'nil')
        or (fbMs and fbMs > 0) or (fbName ~= '' and fbName ~= 'nil')
        or mezAnim

    local durationMs = xtMs or spMs or fbMs
    local durationSrc = 'NONE'
    if xtMs and xtMs > 0 then durationSrc = 'XT'
    elseif spMs and spMs > 0 then durationSrc = 'Spawn'
    elseif fbMs and fbMs > 0 then durationSrc = 'FindBuff'
    end

    local cursorMezzed = onCursor and ((tgId and tgId > 0) or (tgName ~= '' and tgName ~= 'nil') or (tgMs and tgMs > 0))

    printf(
        '\ay[%s MezXT]\ax id=%d name=%s body=%s cursor=%s aggressive=%s',
        ts(), spawnId, name, body, onCursor and 'YES' or 'NO', safeStr(xt and xt() and xt.Aggressive and xt.Aggressive())
    )
    printf('  XT.Mezzed     name=%s id=%s remain=%s', safeStr(xtName), safeStr(xtId), formatRemain(xtMs))
    printf('  Spawn.Mezzed  name=%s id=%s remain=%s', safeStr(spName), safeStr(spId), formatRemain(spMs))
    printf('  FindBuff(31)  name=%s id=%s remain=%s', safeStr(fbName), safeStr(fbId), formatRemain(fbMs))
    printf('  Animation=%s mezAnim=%s', safeStr(anim), mezAnim and 'YES' or 'NO')
    if onCursor then
        printf('  Target.Mezzed name=%s id=%s remain=%s  \am(comparison only)\ax', safeStr(tgName), safeStr(tgId), formatRemain(tgMs))
    end
    printf(
        '  \agSUMMARY\ax no_target_mezed=%s duration_src=%s remain=%s cursor_mezed=%s',
        mezzedNoTarget and 'YES' or 'NO',
        durationSrc,
        formatRemain(durationMs),
        cursorMezzed and 'YES' or (onCursor and 'NO' or 'n/a')
    )
    if onCursor and cursorMezzed and not (durationMs and durationMs > 0) then
        printf('  \arNOTE\ax Cursor has mez but XT/Spawn/FindBuff duration unreadable — likely Target-only TLO.')
    elseif (not onCursor) and mezzedNoTarget and durationSrc == 'NONE' then
        printf('  \arNOTE\ax Mezzed signal without duration (animation/name only). Refresh timing unavailable without target.')
    elseif (not onCursor) and (not mezzedNoTarget) and cursorMezzed then
        printf('  \arNOTE\ax Would miss mez if only scanning XT/Spawn without target.')
    end
end

local function scanOnce()
    local xtCount = mq.TLO.Me.XTarget() or 0
    local cursorId = mq.TLO.Target.ID() or 0
    local cursorName = mq.TLO.Target.CleanName() or 'None'

    printf('\ay======== %s MezXT scan (no SetTarget) ========\ax', ts())
    printf('Cursor: id=%d name=%s | XTarget slots=%d', cursorId, cursorName, xtCount)

    if xtCount == 0 then
        printf('\aoNo XTarget entries. Add haters to XT first.\ax')
        return
    end

    for i = 1, xtCount do
        local xt = mq.TLO.Me.XTarget(i)
        if xt and xt() then
            local id = xt.ID() or 0
            if id > 0 and not xt.Dead() and (xt.Type() or ''):lower() ~= 'corpse' then
                probeMob(id, xt)
            end
        end
    end
    printf('\ay======== end scan ========\ax\n')
end

mq.bind('/mezxt', function(cmd)
    local c = (cmd or ''):lower()
    if c == 'stop' or c == 'quit' or c == 'off' then
        running = false
        printf('\ay[MezXT]\ax Stopped.')
    elseif c == 'once' or c == 'scan' then
        scanOnce()
    elseif c == 'help' or c == '?' then
        printf('\ay[MezXT]\ax Commands: /mezxt once | /mezxt stop | /lua run rgmercs/extras/mez_xt_verify')
    else
        scanOnce()
    end
end)

printf('\ag[MezXT]\ax Started. Mez a mob, move cursor away, watch console every %ds.', scanIntervalMs / 1000)
printf('[MezXT] /mezxt once = single scan | /mezxt stop = quit')

while running do
    local now = mq.gettime()
    if now - lastScanMs >= scanIntervalMs then
        lastScanMs = now
        scanOnce()
    end
    mq.delay(100)
end
