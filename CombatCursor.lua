-- CombatCursor
-- Highlights the mouse cursor while in combat, with a full config GUI
-- (Game Menu -> Interface -> AddOns -> CombatCursor) and /ccursor commands.

local ADDON_NAME = "CombatCursor"

----------------------------------------------------------------------
-- Saved variables / defaults
----------------------------------------------------------------------

local defaults = {
    enabled = true,       -- master on/off
    combatOnly = true,    -- true = only show while in combat
    size = 48,             -- overall diameter
    opacity = 1.0,          -- overall alpha multiplier
    r = 1, g = 0.15, b = 0.85,
    outlineThickness = 3,  -- 1 (thin) .. 5 (thick), maps to bundled ring_N texture
    outlineOpacity = 1.0,
    centerDot = false,
    clickEffect = false,
    pulse = true,
    pulseAmount = 1.35, -- how big the pulse grows, 1.0 = no growth
    trail = false,
    debug = false,
}

CombatCursorDB = CombatCursorDB or {}
for k, v in pairs(defaults) do
    if CombatCursorDB[k] == nil then
        CombatCursorDB[k] = v
    end
end
local db = CombatCursorDB

local function dprint(msg)
    if db.debug then
        print("|cff888888CombatCursor debug:|r " .. msg)
    end
end

----------------------------------------------------------------------
-- Visual layer
----------------------------------------------------------------------

local TEX_PATH = "Interface\\AddOns\\CombatCursor\\Textures\\"

local ring = CreateFrame("Frame", "CombatCursorRing", UIParent)
do
    local ok, err = pcall(function() ring:SetFrameStrata("TOOLTIP") end)
    if not ok then
        dprint("SetFrameStrata(TOOLTIP) failed, falling back to DIALOG: " .. tostring(err))
        ring:SetFrameStrata("DIALOG")
    end
end
ring:SetSize(db.size, db.size)
ring:Hide()

local outerTex = ring:CreateTexture(nil, "OVERLAY")
outerTex:SetAllPoints(ring)
ring.outerTex = outerTex

local dotTex = ring:CreateTexture(nil, "OVERLAY")
dotTex:SetPoint("CENTER", ring, "CENTER", 0, 0)
dotTex:SetTexture(TEX_PATH .. "dot")
ring.dotTex = dotTex

-- Pulse (breathing scale) animation, toggleable
local pulseAG = ring:CreateAnimationGroup()
pulseAG:SetLooping("BOUNCE")
local pulseScale = pulseAG:CreateAnimation("Scale")
pulseScale:SetOrder(1)
pulseScale:SetScale(1.35, 1.35)
pulseScale:SetDuration(0.45)
pulseScale:SetSmoothing("IN_OUT")
pulseAG.playing = false

local function applyVisualSettings()
    ring:SetSize(db.size, db.size)
    outerTex:SetTexture(TEX_PATH .. "ring_" .. tostring(db.outlineThickness))
    outerTex:SetVertexColor(db.r, db.g, db.b, db.outlineOpacity * db.opacity)
    dotTex:SetVertexColor(db.r, db.g, db.b, db.opacity)
    dotTex:SetShown(db.centerDot)
    ring:SetAlpha(1) -- alpha handled per-texture above so opacity slider affects both consistently
    pulseScale:SetScale(db.pulseAmount, db.pulseAmount)

    if db.pulse then
        if ring:IsShown() and not pulseAG.playing then
            pulseAG:Play()
            pulseAG.playing = true
        end
    else
        pulseAG:Stop()
        pulseAG.playing = false
    end
end

local wasMouseDown = false
ring:SetScript("OnShow", function(self)
    dprint("ring shown")
    wasMouseDown = IsMouseButtonDown("LeftButton")
    if db.pulse and not pulseAG.playing then
        pulseAG:Play()
        pulseAG.playing = true
    end
end)
ring:SetScript("OnHide", function(self)
    dprint("ring hidden")
    pulseAG:Stop()
    pulseAG.playing = false
end)

----------------------------------------------------------------------
-- Trail effect: a small pool of fading ghost textures sampling recent
-- cursor positions.
----------------------------------------------------------------------

local TRAIL_LENGTH = 8
local trailFrames = {}
-- Plain ordered array of recent {x,y} positions, oldest first. Simpler and
-- less error-prone than a circular-buffer index (the previous circular
-- buffer had an off-by-one that put the freshest sample in the
-- always-zero-alpha slot, which is why the trail looked broken).
local trailPositions = {}
local TRAIL_HISTORY_CAP = TRAIL_LENGTH + 1 -- +1 so we can skip the very latest point (the main ring already covers it)

for i = 1, TRAIL_LENGTH do
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("TOOLTIP")
    f:SetSize(24, 24)
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints(f)
    t:SetTexture(TEX_PATH .. "trail")
    f.tex = t
    f:Hide()
    trailFrames[i] = f
end

local function updateTrail()
    if not db.trail or not ring:IsShown() then
        for i = 1, TRAIL_LENGTH do trailFrames[i]:Hide() end
        wipe(trailPositions)
        return
    end
    local scale = UIParent:GetEffectiveScale()
    local x, y = GetCursorPosition()
    x, y = x / scale, y / scale

    table.insert(trailPositions, { x = x, y = y })
    while #trailPositions > TRAIL_HISTORY_CAP do
        table.remove(trailPositions, 1)
    end

    local count = #trailPositions
    for i = 1, TRAIL_LENGTH do
        -- i = 1 is the most recent ghost (just behind the live cursor position)
        local posIndex = count - i
        local pos = trailPositions[posIndex]
        local f = trailFrames[i]
        if pos then
            local fade = 1 - (i / TRAIL_LENGTH)
            f:ClearAllPoints()
            f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos.x, pos.y)
            f.tex:SetVertexColor(db.r, db.g, db.b, fade * 0.6 * db.opacity)
            f:Show()
        else
            f:Hide()
        end
    end
end

----------------------------------------------------------------------
-- Click effect: brief expanding/fading burst, detected by polling
-- IsMouseButtonDown so we never have to intercept real clicks.
----------------------------------------------------------------------

local clickBurst = CreateFrame("Frame", nil, UIParent)
clickBurst:SetFrameStrata("TOOLTIP")
clickBurst:SetSize(48, 48)
local clickTex = clickBurst:CreateTexture(nil, "OVERLAY")
clickTex:SetAllPoints(clickBurst)
clickTex:SetTexture(TEX_PATH .. "ring_1")
clickBurst:Hide()

-- Manual grow+fade over time instead of AnimationGroup/Alpha animations:
-- this client's Animation API doesn't support SetFromAlpha/SetToAlpha, so
-- we drive the effect by hand with OnUpdate + elapsed time, which only
-- relies on basic frame methods that are known to work here.
--
-- Starts at the SAME size/position as the base ring and grows further out
-- (to 3x) over a longer window (0.35s) than the original 0.25s/2.2x -- the
-- smaller/faster version was easy to miss since it barely poked past the
-- base ring before it was gone.
local CLICK_DURATION = 0.35
local CLICK_MAX_GROWTH = 3.0
local clickElapsed = nil
local clickBaseSize = 48

clickBurst:SetScript("OnUpdate", function(self, elapsed)
    if not clickElapsed then return end
    clickElapsed = clickElapsed + elapsed
    local t = clickElapsed / CLICK_DURATION
    if t >= 1 then
        self:Hide()
        clickElapsed = nil
        return
    end
    local growth = 1 + t * (CLICK_MAX_GROWTH - 1)
    self:SetSize(clickBaseSize * growth, clickBaseSize * growth)
    clickTex:SetAlpha((1 - t) * db.opacity)
end)

local function checkClickEffect()
    if not db.clickEffect or not ring:IsShown() then
        wasMouseDown = false
        return
    end
    local down = IsMouseButtonDown("LeftButton")
    if down and not wasMouseDown then
        local scale = UIParent:GetEffectiveScale()
        local x, y = GetCursorPosition()
        clickBaseSize = db.size
        clickBurst:ClearAllPoints()
        clickBurst:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
        clickBurst:SetSize(clickBaseSize, clickBaseSize)
        clickTex:SetVertexColor(db.r, db.g, db.b, db.opacity)
        clickTex:SetAlpha(1)
        clickBurst:Show()
        clickElapsed = 0
    end
    wasMouseDown = down
end

----------------------------------------------------------------------
-- Cursor-follow driver
----------------------------------------------------------------------

ring:SetScript("OnUpdate", function(self)
    local scale = UIParent:GetEffectiveScale()
    local x, y = GetCursorPosition()
    self:ClearAllPoints()
    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    updateTrail()
    checkClickEffect()
end)

----------------------------------------------------------------------
-- Visibility logic (combat state + preview mode from the GUI)
----------------------------------------------------------------------

local previewActive = false

local function refreshVisibility()
    if not db.enabled then
        ring:Hide()
        return
    end
    if previewActive then
        ring:Show()
        return
    end
    if db.combatOnly then
        if UnitAffectingCombat("player") then
            ring:Show()
        else
            ring:Hide()
        end
    else
        ring:Show()
    end
end

local panel, guiAvailable, guiError, buildOptionsPanel
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")

events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        for k, v in pairs(defaults) do
            if CombatCursorDB[k] == nil then
                CombatCursorDB[k] = v
            end
        end
        db = CombatCursorDB
        applyVisualSettings()
        local ok, result = pcall(buildOptionsPanel)
        if ok then
            panel = result
            guiAvailable = true
        else
            guiError = tostring(result)
            print("|cffff4444CombatCursor:|r the settings GUI failed to load on this client (falling back to /ccursor commands only).")
            print("|cffff4444CombatCursor error:|r " .. guiError)
        end
    elseif event == "PLAYER_LOGIN" then
        applyVisualSettings()
        refreshVisibility()
    elseif event == "PLAYER_REGEN_DISABLED" then
        dprint("entered combat")
        refreshVisibility()
    elseif event == "PLAYER_REGEN_ENABLED" then
        dprint("left combat")
        refreshVisibility()
    end
end)

----------------------------------------------------------------------
-- GUI: Interface Options panel
-- (Game Menu -> Interface -> AddOns -> CombatCursor)
----------------------------------------------------------------------

local widgetCounter = 0
local function nextWidgetName(prefix)
    widgetCounter = widgetCounter + 1
    return "CombatCursor" .. prefix .. widgetCounter
end

----------------------------------------------------------------------
-- Grid-positioned widget helpers: placed at an explicit (x, y) offset
-- from the parent's TOPLEFT. Needed for a two-column layout, where the
-- left and right columns advance independently rather than stacking on
-- top of each other.
----------------------------------------------------------------------

local function addCheckboxAt(parent, label, x, y, get, set, tooltipText)
    local cb = CreateFrame("CheckButton", nextWidgetName("Check"), parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    cb.text = _G[cb:GetName() .. "Text"]
    if cb.text then cb.text:SetText(label) end
    cb:SetChecked(get())
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        applyVisualSettings()
        refreshVisibility()
    end)
    if tooltipText then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tooltipText, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return cb
end

local function addSliderAt(parent, label, x, y, minVal, maxVal, step, get, set)
    local slider = CreateFrame("Slider", nextWidgetName("Slider"), parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 8, y - 28)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetWidth(220)
    _G[slider:GetName() .. "Low"]:SetText(tostring(minVal))
    _G[slider:GetName() .. "High"]:SetText(tostring(maxVal))
    _G[slider:GetName() .. "Text"]:SetText(label)
    slider:SetValue(get())
    slider:SetScript("OnValueChanged", function(self, value)
        if step >= 1 then value = math.floor(value + 0.5) end
        set(value)
        applyVisualSettings()
        refreshVisibility()
    end)
    return slider
end

-- Just the swatch button, no attached label -- the mockup places the
-- "Cursor Color" text as its own independent label in the left column,
-- with the swatch sitting alone in the right column on the same row.
local function addColorSwatchAt(parent, x, y, getRGB, setRGB)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    btn:SetSize(28, 28)

    local border = btn:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints(btn)
    border:SetTexture(0, 0, 0, 1)

    local swatch = btn:CreateTexture(nil, "ARTWORK")
    swatch:SetPoint("TOPLEFT", 2, -2)
    swatch:SetPoint("BOTTOMRIGHT", -2, 2)
    local r, g, b = getRGB()
    swatch:SetTexture(r, g, b)

    btn:SetScript("OnClick", function()
        local function apply()
            local nr, ng, nb = ColorPickerFrame:GetColorRGB()
            setRGB(nr, ng, nb)
            swatch:SetTexture(nr, ng, nb)
        end
        local cr, cg, cb2 = getRGB()
        ColorPickerFrame:SetColorRGB(cr, cg, cb2)
        ColorPickerFrame.func = apply
        ColorPickerFrame.opacityFunc = apply
        ColorPickerFrame.cancelFunc = function()
            setRGB(cr, cg, cb2)
            swatch:SetTexture(cr, cg, cb2)
        end
        ColorPickerFrame.previousValues = { r = cr, g = cg, b = cb2 }
        ShowUIPanel(ColorPickerFrame)
    end)
    return btn
end

local function addLabelAt(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

buildOptionsPanel = function()
local panel = CreateFrame("Frame", "CombatCursorOptionsPanel", UIParent)
panel.name = "CombatCursor"

-- Content overflowed the fixed-size options panel with this many widgets,
-- so everything below lives inside a scroll frame instead of being
-- parented directly to the panel. -28 on the right leaves room for the
-- scrollbar; the scroll child's width stays synced to the visible area
-- via OnSizeChanged since the panel's actual pixel width isn't known yet
-- at creation time.
local scrollFrame = CreateFrame("ScrollFrame", "CombatCursorOptionsScroll", panel, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 8)

local content = CreateFrame("Frame", "CombatCursorOptionsContent", scrollFrame)
content:SetSize(1, 760) -- width kept in sync below; height is a generous fixed value covering all content
scrollFrame:SetScrollChild(content)
scrollFrame:SetScript("OnSizeChanged", function(self, w, h)
    content:SetWidth(w)
end)

-- Two-column grid layout. Rows advance independently per column via
-- explicit y offsets rather than chaining widgets to one another.
-- Right column pulled in from 420 -> 340: at 420 it was crowding the
-- actual in-game panel edge (sliders/swatch sat right up against it).
local colLeftX, colRightX = 16, 340

-- Row 1: master toggle + preview, side by side
local enabledCB = addCheckboxAt(content, "Enable cursor enhancement", colLeftX, -16,
    function() return db.enabled end,
    function(v) db.enabled = v end,
    "Master on/off switch for the whole addon.")

local previewCB = addCheckboxAt(content, "Preview cursor enhancement", colRightX, -16,
    function() return previewActive end,
    function(v) previewActive = v end,
    "While checked, the cursor highlight previews live so you can dial in your settings without needing to be in combat. Automatically unchecks when you close this panel.")

-- Row 2: combat-only toggle
local combatOnlyCB = addCheckboxAt(content, "Show only in combat", colLeftX, -56,
    function() return db.combatOnly end,
    function(v) db.combatOnly = v end,
    "When checked, the cursor highlight only appears while you're in combat. When unchecked, it stays visible all the time.")

-- Row 3: color label (left) + swatch (right)
addLabelAt(content, "Cursor Color", colLeftX, -104)
local colorSwatch = addColorSwatchAt(content, colRightX, -108,
    function() return db.r, db.g, db.b end,
    function(r, g, b) db.r, db.g, db.b = r, g, b; applyVisualSettings() end)

-- Row 4: size + opacity sliders
local sizeSlider = addSliderAt(content, "Cursor Size", colLeftX, -150, 16, 128, 1,
    function() return db.size end,
    function(v) db.size = v end)

local opacitySlider = addSliderAt(content, "Cursor Opacity", colRightX, -150, 0.1, 1.0, 0.05,
    function() return db.opacity end,
    function(v) db.opacity = v end)

-- Row 5: outline size + opacity sliders
local outlineSizeSlider = addSliderAt(content, "Outline Size", colLeftX, -222, 1, 5, 1,
    function() return db.outlineThickness end,
    function(v) db.outlineThickness = v end)

local outlineOpacitySlider = addSliderAt(content, "Outline Opacity", colRightX, -222, 0.1, 1.0, 0.05,
    function() return db.outlineOpacity end,
    function(v) db.outlineOpacity = v end)

-- Row 6: pulse amount, its own full row in the left column (moved out of
-- the Effects area to sit with the other sliders, per updated mockup)
local pulseAmountSlider = addSliderAt(content, "Pulse Amount", colLeftX, -294, 1.05, 2.0, 0.05,
    function() return db.pulseAmount end,
    function(v) db.pulseAmount = v end)

-- ===== Effects =====
addLabelAt(content, "Effects:", colLeftX, -390)

local clickEffectCB = addCheckboxAt(content, "Enable click effect", colLeftX, -426,
    function() return db.clickEffect end,
    function(v) db.clickEffect = v end,
    "Shows a ring that briefly expands outward from your cursor and fades out whenever you left-click, while the cursor highlight is visible.")

local pulseCB = addCheckboxAt(content, "Enable cursor pulse", colLeftX, -462,
    function() return db.pulse end,
    function(v) db.pulse = v end,
    "Makes the cursor highlight gently grow and shrink on a loop, to help catch your eye. See Pulse Amount above to control how big the pulse grows.")

local trailCB = addCheckboxAt(content, "Enable cursor trail", colLeftX, -498,
    function() return db.trail end,
    function(v) db.trail = v end,
    "Leaves a short fading trail of ghost copies behind your cursor as it moves.")

local centerDotCB = addCheckboxAt(content, "Enable center dot", colLeftX, -534,
    function() return db.centerDot end,
    function(v) db.centerDot = v end,
    "Adds a solid dot in the middle of the cursor highlight, using the same color and opacity as the cursor above. Combined with a thick outline, this can make the whole highlight look like one solid filled circle instead of a hollow ring -- that's expected, not a bug.")

panel:SetScript("OnShow", function()
    previewActive = false
    previewCB:SetChecked(false)
    applyVisualSettings()
    refreshVisibility()
end)
panel:SetScript("OnHide", function()
    previewActive = false
    previewCB:SetChecked(false)
    refreshVisibility()
end)

InterfaceOptions_AddCategory(panel)

return panel
end -- buildOptionsPanel

----------------------------------------------------------------------
-- /ccursor command line (kept working alongside the GUI regardless of
-- whether the panel above loaded successfully)
----------------------------------------------------------------------

local function openConfig()
    if not guiAvailable then
        print("|cffff4444CombatCursor:|r the settings GUI isn't available on this client. Use /ccursor size|color|always|enable|disable|test|status instead.")
        if guiError then
            print("|cffff4444CombatCursor error:|r " .. guiError)
        end
        return
    end
    InterfaceOptionsFrame_OpenToCategory(panel)
    InterfaceOptionsFrame_OpenToCategory(panel) -- Blizzard quirk: first call sometimes doesn't focus the panel
end

SLASH_COMBATCURSOR1 = "/ccursor"
SlashCmdList["COMBATCURSOR"] = function(msg)
    local args = {}
    for word in msg:gmatch("%S+") do table.insert(args, word) end
    local cmd = args[1] and args[1]:lower() or ""

    if cmd == "config" or cmd == "options" or cmd == "gui" then
        openConfig()

    elseif cmd == "size" and tonumber(args[2]) then
        db.size = tonumber(args[2])
        applyVisualSettings()
        print("|cff66ccffCombatCursor:|r size set to " .. db.size)

    elseif cmd == "color" and tonumber(args[2]) and tonumber(args[3]) and tonumber(args[4]) then
        db.r, db.g, db.b = tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
        applyVisualSettings()
        print("|cff66ccffCombatCursor:|r color updated")

    elseif cmd == "always" then
        db.combatOnly = not db.combatOnly
        print("|cff66ccffCombatCursor:|r combat-only is now " .. (db.combatOnly and "ON" or "OFF"))
        refreshVisibility()

    elseif cmd == "enable" then
        db.enabled = true
        refreshVisibility()
        print("|cff66ccffCombatCursor:|r enabled")

    elseif cmd == "disable" then
        db.enabled = false
        refreshVisibility()
        print("|cff66ccffCombatCursor:|r disabled")

    elseif cmd == "test" then
        previewActive = not previewActive
        refreshVisibility()
        print("|cff66ccffCombatCursor:|r test toggle -> " .. tostring(ring:IsShown()))

    elseif cmd == "debug" then
        db.debug = not db.debug
        print("|cff66ccffCombatCursor:|r debug is now " .. (db.debug and "ON" or "OFF"))

    elseif cmd == "status" then
        print("|cff66ccffCombatCursor status:|r")
        print("  enabled=" .. tostring(db.enabled) .. " combatOnly=" .. tostring(db.combatOnly))
        print("  size=" .. db.size .. " opacity=" .. db.opacity .. " color=(" .. db.r .. "," .. db.g .. "," .. db.b .. ")")
        print("  outlineThickness=" .. db.outlineThickness .. " outlineOpacity=" .. db.outlineOpacity)
        print("  centerDot=" .. tostring(db.centerDot) .. " clickEffect=" .. tostring(db.clickEffect) ..
              " pulse=" .. tostring(db.pulse) .. " trail=" .. tostring(db.trail))
        print("  shown=" .. tostring(ring:IsShown()) .. " inCombat=" .. tostring(UnitAffectingCombat("player")))

    else
        print("|cff66ccffCombatCursor commands:|r")
        print("  /ccursor config              -- open the settings GUI")
        print("  /ccursor size <number>       -- set ring size")
        print("  /ccursor color <r> <g> <b>   -- set color, values 0-1")
        print("  /ccursor always              -- toggle combat-only vs always-on")
        print("  /ccursor enable | disable    -- master on/off")
        print("  /ccursor test                -- toggle a live preview on/off")
        print("  /ccursor status              -- print current settings and state")
        print("  /ccursor debug               -- toggle debug event logging")
    end
end
