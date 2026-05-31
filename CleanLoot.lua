-- CleanLoot replaces the standard WoW 3.3.5a group-loot roll frames with a compact native-roll UI.
-- It intentionally uses only the stock WotLK loot-roll events and APIs, so it works without a custom server protocol.

local addonName, addon = ...

addon = addon or {}
CleanLoot = addon

local ADDON_NAME = addonName or "CleanLoot"
local CHAT_PREFIX = "|cff33ff99CleanLoot|r: "

local ROLL_TYPE_PASS = 0
local ROLL_TYPE_NEED = 1
local ROLL_TYPE_GREED = 2
local ROLL_TYPE_DISENCHANT = 3

local ROW_WIDTH = 396
local ROW_HEIGHT = 32
local ROW_SPACING = 3
local ICON_SIZE = 26
local BUTTON_WIDTH = 30
local BUTTON_HEIGHT = 19
local BUTTON_SPACING = 3
local BUTTON_RIGHT_PADDING = 5
local BUTTON_GROUP_WIDTH = (BUTTON_WIDTH * 4) + (BUTTON_SPACING * 3)
local TIMER_WIDTH = 28
local TEXT_RIGHT_INSET = BUTTON_RIGHT_PADDING + BUTTON_GROUP_WIDTH + TIMER_WIDTH + 16
local RESULT_SECONDS = 2
local DEFAULT_ROLL_SECONDS = 60
local CONFIRM_MONITOR_SECONDS = 2

local DEFAULT_ANCHOR_POINT = {"BOTTOM", "BOTTOM", 0, 220}

local CHOICE_TO_ROLL_TYPE = {
	PASS = ROLL_TYPE_PASS,
	NEED = ROLL_TYPE_NEED,
	GREED = ROLL_TYPE_GREED,
	DISENCHANT = ROLL_TYPE_DISENCHANT,
}

local ROLL_TYPE_TO_CHOICE = {
	[ROLL_TYPE_PASS] = "PASS",
	[ROLL_TYPE_NEED] = "NEED",
	[ROLL_TYPE_GREED] = "GREED",
	[ROLL_TYPE_DISENCHANT] = "DISENCHANT",
}

local eventFrame = CreateFrame("Frame")
local updateFrame = CreateFrame("Frame")
local confirmMonitorFrame = CreateFrame("Frame")
local anchor = CreateFrame("Frame", "CleanLootAnchor", UIParent)

local rows = {}
local rowOrder = {}
local rowPool = {}
local hiddenNativeFrames = {}
local pendingConfirmations = {}
local confirmMonitorUntil = 0

anchor:SetWidth(ROW_WIDTH)
anchor:SetHeight(16)
anchor:SetMovable(true)
anchor:EnableMouse(true)
anchor:RegisterForDrag("LeftButton")
if anchor.SetClampedToScreen then
	anchor:SetClampedToScreen(true)
end

anchor.background = anchor:CreateTexture(nil, "BACKGROUND")
anchor.background:SetAllPoints(anchor)
anchor.background:SetTexture("Interface\\Buttons\\WHITE8x8")
anchor.background:SetVertexColor(0.02, 0.02, 0.02, 0.88)

anchor.text = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
anchor.text:SetPoint("CENTER", anchor, "CENTER", 0, 0)
anchor.text:SetText("CleanLoot")

local function Print(message)
	if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
		DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. tostring(message))
	elseif print then
		print("CleanLoot: " .. tostring(message))
	end
end

local function GetDatabase()
	CleanLootDB = CleanLootDB or {}
	if type(CleanLootDB) ~= "table" then
		CleanLootDB = {}
	end
	if CleanLootDB.enabled == nil then
		CleanLootDB.enabled = true
	end
	if CleanLootDB.locked == nil then
		CleanLootDB.locked = true
	end
	if CleanLootDB.debug == nil then
		CleanLootDB.debug = false
	end
	return CleanLootDB
end

local function PrintDebug(message)
	if GetDatabase().debug then
		Print("|cff99ccffdebug|r " .. tostring(message))
	end
end

local function IsEnabled()
	return GetDatabase().enabled ~= false
end

local function HasActiveRows()
	return next(rows) ~= nil
end

local function GetCurrentTime()
	if type(GetTime) == "function" then
		return GetTime()
	end
	if type(time) == "function" then
		return time()
	end
	return 0
end

local function SetDefaultAnchorPoint()
	anchor:ClearAllPoints()
	anchor:SetPoint(DEFAULT_ANCHOR_POINT[1], UIParent, DEFAULT_ANCHOR_POINT[2], DEFAULT_ANCHOR_POINT[3], DEFAULT_ANCHOR_POINT[4])
end

local function ApplyAnchorPoint()
	local db = GetDatabase()
	local point = db.point
	if type(point) ~= "table" then
		SetDefaultAnchorPoint()
		return
	end

	local anchorPoint = point[1] or DEFAULT_ANCHOR_POINT[1]
	local relativePoint = point[2] or DEFAULT_ANCHOR_POINT[2]
	local x = tonumber(point[3]) or DEFAULT_ANCHOR_POINT[3]
	local y = tonumber(point[4]) or DEFAULT_ANCHOR_POINT[4]

	anchor:ClearAllPoints()
	anchor:SetPoint(anchorPoint, UIParent, relativePoint, x, y)
end

local function SaveAnchorPoint()
	local db = GetDatabase()
	local point, _, relativePoint, x, y = anchor:GetPoint(1)
	db.point = {
		point or DEFAULT_ANCHOR_POINT[1],
		relativePoint or DEFAULT_ANCHOR_POINT[2],
		tonumber(x) or DEFAULT_ANCHOR_POINT[3],
		tonumber(y) or DEFAULT_ANCHOR_POINT[4],
	}
end

local function UpdateAnchorVisibility()
	local db = GetDatabase()
	if db.enabled ~= false and db.locked == false then
		anchor:Show()
	else
		anchor:Hide()
	end
end

anchor:SetScript("OnDragStart", function(self)
	if GetDatabase().locked == false then
		self:StartMoving()
	end
end)

anchor:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	SaveAnchorPoint()
end)

local function ExtractItemID(itemLink)
	if type(itemLink) ~= "string" then
		return nil
	end
	return tonumber(string.match(itemLink, "item:(%d+)"))
end

local function JoinParts(parts)
	local text = ""
	for index, part in ipairs(parts) do
		if index == 1 then
			text = part
		else
			text = text .. " | " .. part
		end
	end
	return text
end

local function GetChoiceLabel(choice)
	if choice == "NEED" then
		return "N"
	elseif choice == "GREED" then
		return "G"
	elseif choice == "DISENCHANT" then
		return "DE"
	end

	return "P"
end

local function GetChoiceTooltip(choice)
	if choice == "NEED" then
		return "Need"
	elseif choice == "GREED" then
		return "Greed"
	elseif choice == "DISENCHANT" then
		return "Disenchant"
	end

	return "Pass"
end

local function GetChoiceColor(choice)
	if choice == "NEED" then
		return 0.30, 0.78, 0.40
	elseif choice == "GREED" then
		return 0.90, 0.70, 0.26
	elseif choice == "DISENCHANT" then
		return 0.62, 0.48, 0.88
	end

	return 0.78, 0.28, 0.22
end

local function HideCompareTooltips()
	if ShoppingTooltip1 then
		ShoppingTooltip1:Hide()
	end
	if ShoppingTooltip2 then
		ShoppingTooltip2:Hide()
	end
end

local function HideNativeLootRollFrames()
	if not IsEnabled() then
		return
	end

	local count = NUM_GROUP_LOOT_FRAMES or 4
	for index = 1, count do
		local frame = _G["GroupLootFrame" .. index]
		if frame and frame.Hide then
			if frame.IsShown and frame:IsShown() then
				hiddenNativeFrames[frame] = true
			end
			frame:Hide()
		end
	end
end

local function RestoreNativeLootRollFrames()
	for frame in pairs(hiddenNativeFrames) do
		if frame and frame.Show and frame.rollID then
			frame:Show()
		end
		hiddenNativeFrames[frame] = nil
	end
end

local function CleanupPendingConfirmations()
	local now = GetCurrentTime()
	for rollID, pending in pairs(pendingConfirmations) do
		if not pending.expiresAt or pending.expiresAt <= now then
			pendingConfirmations[rollID] = nil
		end
	end
end

local function HasPendingConfirmation()
	CleanupPendingConfirmations()
	return next(pendingConfirmations) ~= nil
end

local function HasConfirmedPendingConfirmation()
	CleanupPendingConfirmations()
	for _, pending in pairs(pendingConfirmations) do
		if pending.confirmed then
			return true
		end
	end
	return false
end

local function GetPendingConfirmation(rollID, rollType)
	rollID = tonumber(rollID)
	rollType = tonumber(rollType)
	if not rollID then
		return nil
	end

	local pending = pendingConfirmations[rollID]
	if not pending then
		return nil
	end
	if rollType and pending.rollType and rollType ~= pending.rollType then
		return nil
	end
	return pending
end

local function TrackPendingConfirmation(row, choice, rollType)
	if choice == "PASS" or not row or not row.rollID or not rollType then
		return
	end

	pendingConfirmations[row.rollID] = {
		rollType = rollType,
		choice = choice,
		expiresAt = GetCurrentTime() + CONFIRM_MONITOR_SECONDS,
	}
	confirmMonitorUntil = GetCurrentTime() + CONFIRM_MONITOR_SECONDS
end

local function StopConfirmMonitor()
	confirmMonitorFrame:SetScript("OnUpdate", nil)
end

local function TryClickConfirmPopup()
	if not IsEnabled() or not HasPendingConfirmation() then
		return true
	end

	local popupCount = STATICPOPUP_NUMDIALOGS or 4
	for index = 1, popupCount do
		local frame = _G["StaticPopup" .. index]
		if frame and frame.IsShown and frame:IsShown() and frame.which == "CONFIRM_LOOT_ROLL" then
			if HasConfirmedPendingConfirmation() and frame.Hide then
				frame:Hide()
				return true
			end
			local button = _G["StaticPopup" .. index .. "Button1"]
			if button and button.IsEnabled and button:IsEnabled() and button.Click then
				button:Click()
				return true
			end
		end
	end

	return false
end

local function OnConfirmMonitorUpdate()
	if TryClickConfirmPopup() or GetCurrentTime() >= confirmMonitorUntil then
		StopConfirmMonitor()
	end
end

local function StartConfirmMonitor()
	confirmMonitorUntil = GetCurrentTime() + CONFIRM_MONITOR_SECONDS
	confirmMonitorFrame:SetScript("OnUpdate", OnConfirmMonitorUpdate)
end

local function AutoConfirmLootRoll(rollID, rollType)
	local pending = GetPendingConfirmation(rollID, rollType)
	if not pending then
		return false
	end

	local confirmed = false
	if type(ConfirmLootRoll) == "function" then
		local confirmedRollType = tonumber(rollType) or pending.rollType
		local ok, errorMessage = pcall(ConfirmLootRoll, tonumber(rollID), confirmedRollType)
		if ok then
			confirmed = true
			pending.confirmed = true
		else
			PrintDebug(errorMessage)
		end
	end

	StartConfirmMonitor()
	return confirmed
end

local function BuildItemDetailText(row)
	local parts = {}

	if row.itemCount and row.itemCount > 1 then
		parts[#parts + 1] = "x" .. tostring(row.itemCount)
	end
	if row.itemLevel and row.itemLevel > 0 then
		parts[#parts + 1] = "ilvl " .. tostring(row.itemLevel)
	end
	if row.bindOnPickUp then
		parts[#parts + 1] = "BoP"
	end

	local equipText = nil
	if row.equipLoc and row.equipLoc ~= "" then
		equipText = _G[row.equipLoc] or row.equipLoc
	end
	if not equipText or equipText == "" then
		equipText = row.itemSubType or row.itemType
	end
	if equipText and equipText ~= "" then
		parts[#parts + 1] = equipText
	end

	if #parts == 0 then
		return "Waiting for item info"
	end
	return JoinParts(parts)
end

local function SetDetailStatus(row)
	row.statusMode = "details"
	row.detailText = BuildItemDetailText(row)
	row.status:SetTextColor(0.72, 0.69, 0.62)
	row.status:SetText(row.detailText)
end

local function SetButtonEnabled(button, enabled)
	if not button then
		return
	end

	local r, g, b = GetChoiceColor(button.choice)
	if enabled then
		button:Enable()
		button:SetAlpha(1)
		button.background:SetVertexColor(0.09 + r * 0.08, 0.08 + g * 0.06, 0.06 + b * 0.04, 0.92)
		button.accent:SetVertexColor(r, g, b, 0.90)
		button.label:SetTextColor(0.96, 0.86, 0.58)
	else
		button:Disable()
		button:SetAlpha(0.42)
		button.background:SetVertexColor(0.08, 0.08, 0.08, 0.82)
		button.accent:SetVertexColor(r, g, b, 0.22)
		button.label:SetTextColor(0.58, 0.58, 0.58)
	end
end

local function RefreshButtons(row)
	SetButtonEnabled(row.buttons.NEED, row.canNeed and not row.selected)
	SetButtonEnabled(row.buttons.GREED, row.canGreed and not row.selected)
	SetButtonEnabled(row.buttons.DISENCHANT, row.canDisenchant and not row.selected)
	SetButtonEnabled(row.buttons.PASS, not row.selected)
end

local function ShowItemTooltip(row)
	if not row or not GameTooltip then
		return
	end

	if row.itemLink then
		GameTooltip:SetOwner(row.frame, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink(row.itemLink)
	elseif row.itemID then
		GameTooltip:SetOwner(row.frame, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink("item:" .. tostring(row.itemID))
	else
		return
	end

	local compareEnabled = IsShiftKeyDown and IsShiftKeyDown()
	if compareEnabled and GameTooltip_ShowCompareItem then
		GameTooltip_ShowCompareItem(GameTooltip)
	else
		HideCompareTooltips()
	end
	row.compareShown = compareEnabled
end

local function RefreshLayout()
	for index, rollID in ipairs(rowOrder) do
		local row = rows[rollID]
		if row and row.frame then
			row.frame:ClearAllPoints()
			row.frame:SetPoint("TOP", anchor, "TOP", 0, -((index - 1) * (ROW_HEIGHT + ROW_SPACING)))
		end
	end
end

local function ReleaseRow(row)
	row.frame:Hide()
	row.frame:ClearAllPoints()
	row.rollID = nil
	row.selected = nil
	row.removeAt = nil
	row.expiresAt = nil
	row.hovered = nil
	row.compareShown = nil
	table.insert(rowPool, row)
end

local function RemoveRow(rollID)
	local row = rows[rollID]
	if not row then
		return
	end

	pendingConfirmations[rollID] = nil
	rows[rollID] = nil
	for index, existingRollID in ipairs(rowOrder) do
		if existingRollID == rollID then
			table.remove(rowOrder, index)
			break
		end
	end

	ReleaseRow(row)
	RefreshLayout()
end

local function ScheduleRowRemoval(row, seconds)
	row.removeAt = (GetTime and GetTime() or 0) + (seconds or RESULT_SECONDS)
end

local function GetRollTimeLeftSeconds(row)
	if type(GetLootRollTimeLeft) == "function" and row.rollID then
		local milliseconds = tonumber(GetLootRollTimeLeft(row.rollID))
		if milliseconds and milliseconds >= 0 then
			return milliseconds / 1000
		end
	end

	if row.expiresAt then
		return math.max(0, row.expiresAt - (GetTime and GetTime() or 0))
	end
	return DEFAULT_ROLL_SECONDS
end

local function RefreshRollInfo(row)
	local texture, name, count, quality, bindOnPickUp, canNeed, canGreed, canDisenchant
	if type(GetLootRollItemInfo) == "function" and row.rollID then
		texture, name, count, quality, bindOnPickUp, canNeed, canGreed, canDisenchant = GetLootRollItemInfo(row.rollID)
	end

	local itemLink = row.itemLink
	if type(GetLootRollItemLink) == "function" and row.rollID then
		itemLink = GetLootRollItemLink(row.rollID) or itemLink
	end

	local itemID = ExtractItemID(itemLink) or row.itemID
	local itemName, cachedLink, cachedQuality, itemLevel, reqLevel, itemType, itemSubType, maxStack, equipLoc, itemTexture
	local itemQuery = itemLink or (itemID and ("item:" .. tostring(itemID)))
	if itemQuery and type(GetItemInfo) == "function" then
		itemName, cachedLink, cachedQuality, itemLevel, reqLevel, itemType, itemSubType, maxStack, equipLoc, itemTexture = GetItemInfo(itemQuery)
	end
	if not itemTexture and itemID and type(GetItemIcon) == "function" then
		itemTexture = GetItemIcon(itemID)
	end

	row.itemLink = cachedLink or itemLink
	row.itemID = itemID
	row.itemName = itemName or name or (itemID and ("Item " .. tostring(itemID))) or "Loot Roll"
	row.itemCount = tonumber(count) or row.itemCount or 1
	row.quality = cachedQuality or quality or row.quality or 1
	row.itemLevel = tonumber(itemLevel) or row.itemLevel or 0
	row.itemType = itemType or row.itemType
	row.itemSubType = itemSubType or row.itemSubType
	row.equipLoc = equipLoc or row.equipLoc
	row.itemInfoReady = itemName ~= nil
	row.bindOnPickUp = bindOnPickUp or false
	row.canNeed = canNeed and true or false
	row.canGreed = canGreed and true or false
	row.canDisenchant = canDisenchant and true or false

	local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[row.quality]
	if color then
		row.name:SetTextColor(color.r, color.g, color.b)
		row.qualityBar:SetVertexColor(color.r, color.g, color.b, 1)
	else
		row.name:SetTextColor(1, 1, 1)
		row.qualityBar:SetVertexColor(1, 1, 1, 1)
	end

	local displayName = row.itemName or ""
	if row.itemCount and row.itemCount > 1 then
		displayName = displayName .. " x" .. tostring(row.itemCount)
	end
	row.name:SetText(displayName)
	row.icon:SetTexture(itemTexture or texture or "Interface\\Icons\\INV_Misc_QuestionMark")

	if row.statusMode == "details" then
		SetDetailStatus(row)
	end
	RefreshButtons(row)
end

local function SelectRoll(row, choice)
	if row.selected then
		return
	end

	local rollType = CHOICE_TO_ROLL_TYPE[choice]
	if not rollType or type(RollOnLoot) ~= "function" then
		row.statusMode = "error"
		row.status:SetTextColor(0.90, 0.25, 0.20)
		row.status:SetText("Roll API unavailable")
		return
	end

	TrackPendingConfirmation(row, choice, rollType)
	local ok, errorMessage = pcall(RollOnLoot, row.rollID, rollType)
	if not ok then
		pendingConfirmations[row.rollID] = nil
		row.statusMode = "error"
		row.status:SetTextColor(0.90, 0.25, 0.20)
		row.status:SetText("Roll failed")
		PrintDebug(errorMessage)
		return
	end

	row.selected = choice
	row.statusMode = "selected"
	local r, g, b = GetChoiceColor(choice)
	row.status:SetTextColor(r, g, b)
	row.status:SetText("Selected " .. GetChoiceTooltip(choice))
	RefreshButtons(row)
end

local function CreateRollButton(row, choice, index)
	local button = CreateFrame("Button", nil, row.frame)
	button:SetWidth(BUTTON_WIDTH)
	button:SetHeight(BUTTON_HEIGHT)
	button:SetPoint("RIGHT", row.frame, "RIGHT", -(BUTTON_RIGHT_PADDING + (index - 1) * (BUTTON_WIDTH + BUTTON_SPACING)), 0)
	button:RegisterForClicks("LeftButtonUp")
	button.choice = choice

	button.background = button:CreateTexture(nil, "BACKGROUND")
	button.background:SetAllPoints(button)
	button.background:SetTexture("Interface\\Buttons\\WHITE8x8")

	button.accent = button:CreateTexture(nil, "BORDER")
	button.accent:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 1, 1)
	button.accent:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
	button.accent:SetHeight(2)
	button.accent:SetTexture("Interface\\Buttons\\WHITE8x8")

	button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
	button.highlight:SetAllPoints(button)
	button.highlight:SetTexture("Interface\\Buttons\\WHITE8x8")
	button.highlight:SetVertexColor(1, 1, 1, 0.10)

	button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	button.label:SetPoint("CENTER", button, "CENTER", 0, 0)
	button.label:SetText(GetChoiceLabel(choice))
	SetButtonEnabled(button, true)

	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(GetChoiceTooltip(choice), 1, 1, 1)
	end)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	button:SetScript("OnClick", function()
		SelectRoll(row, choice)
	end)

	row.buttons[choice] = button
	return button
end

local function CreateRowFrame()
	local frame = CreateFrame("Frame", nil, UIParent)
	frame:SetWidth(ROW_WIDTH)
	frame:SetHeight(ROW_HEIGHT)
	frame:SetFrameStrata("DIALOG")
	frame:EnableMouse(true)
	frame:Hide()

	local background = frame:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints(frame)
	background:SetTexture("Interface\\Buttons\\WHITE8x8")
	background:SetVertexColor(0.025, 0.022, 0.018, 0.86)

	local topLine = frame:CreateTexture(nil, "BORDER")
	topLine:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
	topLine:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
	topLine:SetHeight(1)
	topLine:SetTexture("Interface\\Buttons\\WHITE8x8")
	topLine:SetVertexColor(0.58, 0.48, 0.28, 0.34)

	local bottomLine = frame:CreateTexture(nil, "BORDER")
	bottomLine:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
	bottomLine:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
	bottomLine:SetHeight(1)
	bottomLine:SetTexture("Interface\\Buttons\\WHITE8x8")
	bottomLine:SetVertexColor(0.58, 0.48, 0.28, 0.24)

	local timerBar = frame:CreateTexture(nil, "BORDER")
	timerBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
	timerBar:SetHeight(2)
	timerBar:SetTexture("Interface\\Buttons\\WHITE8x8")
	timerBar:SetVertexColor(0.82, 0.68, 0.30, 0.78)

	local qualityBar = frame:CreateTexture(nil, "ARTWORK")
	qualityBar:SetPoint("LEFT", frame, "LEFT", 0, 0)
	qualityBar:SetWidth(2)
	qualityBar:SetHeight(ROW_HEIGHT)
	qualityBar:SetTexture("Interface\\Buttons\\WHITE8x8")
	qualityBar:SetVertexColor(1, 1, 1, 1)

	local icon = frame:CreateTexture(nil, "ARTWORK")
	icon:SetWidth(ICON_SIZE)
	icon:SetHeight(ICON_SIZE)
	icon:SetPoint("LEFT", frame, "LEFT", 6, 0)

	local name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 6, -1)
	name:SetPoint("RIGHT", frame, "RIGHT", -TEXT_RIGHT_INSET, 0)
	name:SetJustifyH("LEFT")
	name:SetText("")

	local status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	status:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 6, 2)
	status:SetPoint("RIGHT", frame, "RIGHT", -TEXT_RIGHT_INSET, 0)
	status:SetJustifyH("LEFT")
	status:SetTextColor(0.72, 0.69, 0.62)
	status:SetText("")

	local timer = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	timer:SetPoint("RIGHT", frame, "RIGHT", -(BUTTON_RIGHT_PADDING + BUTTON_GROUP_WIDTH + 8), 0)
	timer:SetWidth(TIMER_WIDTH)
	timer:SetJustifyH("RIGHT")
	timer:SetText("")

	local row = {
		frame = frame,
		icon = icon,
		name = name,
		status = status,
		timer = timer,
		timerBar = timerBar,
		qualityBar = qualityBar,
		buttons = {},
	}

	frame:SetScript("OnEnter", function()
		row.hovered = true
		ShowItemTooltip(row)
	end)
	frame:SetScript("OnLeave", function()
		row.hovered = nil
		if GameTooltip then
			GameTooltip:Hide()
		end
		HideCompareTooltips()
	end)
	frame:SetScript("OnUpdate", function()
		if row.hovered and IsShiftKeyDown and row.compareShown ~= IsShiftKeyDown() then
			ShowItemTooltip(row)
		end
	end)

	CreateRollButton(row, "PASS", 1)
	CreateRollButton(row, "DISENCHANT", 2)
	CreateRollButton(row, "GREED", 3)
	CreateRollButton(row, "NEED", 4)

	return row
end

local function AcquireRow(rollID)
	local row = table.remove(rowPool)
	if not row then
		row = CreateRowFrame()
	end

	row.rollID = rollID
	row.itemLink = nil
	row.itemID = nil
	row.itemName = nil
	row.itemCount = 1
	row.quality = 1
	row.itemLevel = 0
	row.itemType = nil
	row.itemSubType = nil
	row.equipLoc = nil
	row.itemInfoReady = false
	row.bindOnPickUp = false
	row.canNeed = false
	row.canGreed = false
	row.canDisenchant = false
	row.selected = nil
	row.startedAt = GetTime and GetTime() or 0
	row.expiresAt = row.startedAt + DEFAULT_ROLL_SECONDS
	row.removeAt = nil
	row.hovered = nil
	row.compareShown = nil
	row.statusMode = "details"
	row.detailText = ""
	row.timer:SetText("")
	row.timerBar:SetWidth(ROW_WIDTH - 2)
	row.status:SetTextColor(0.72, 0.69, 0.62)
	row.status:SetText("")

	rows[rollID] = row
	table.insert(rowOrder, rollID)
	RefreshLayout()
	return row
end

local function StartRoll(rollID, rollTime)
	if not IsEnabled() then
		return
	end

	rollID = tonumber(rollID)
	if not rollID then
		PrintDebug("Ignoring START_LOOT_ROLL without roll ID.")
		return
	end

	local row = rows[rollID] or AcquireRow(rollID)
	row.rollID = rollID
	row.startedAt = GetTime and GetTime() or 0
	row.selected = nil
	row.removeAt = nil
	row.statusMode = "details"

	local seconds = (tonumber(rollTime) or 0) / 1000
	if seconds <= 0 then
		seconds = GetRollTimeLeftSeconds(row)
	end
	if seconds <= 0 then
		seconds = DEFAULT_ROLL_SECONDS
	end
	row.countdown = seconds
	row.expiresAt = row.startedAt + seconds
	row.timerBar:SetWidth(ROW_WIDTH - 2)

	RefreshRollInfo(row)
	SetDetailStatus(row)
	row.frame:Show()
	HideNativeLootRollFrames()
end

local function ClearRows()
	local rollIDs = {}
	for rollID in pairs(rows) do
		rollIDs[#rollIDs + 1] = rollID
	end
	for _, rollID in ipairs(rollIDs) do
		RemoveRow(rollID)
	end
end

local function SetEnabled(enabled)
	local db = GetDatabase()
	db.enabled = enabled and true or false
	if db.enabled then
		Print("enabled.")
	else
		ClearRows()
		RestoreNativeLootRollFrames()
		Print("disabled.")
	end
	UpdateAnchorVisibility()
end

local function HandleSlashCommand(message)
	local command = string.lower(string.match(message or "", "^%s*(%S*)") or "")
	if command == "" or command == "status" then
		Print("Status: " .. (IsEnabled() and "enabled" or "disabled") .. ".")
		Print("Commands: /cleanloot on, off, unlock, lock, reset, debug.")
	elseif command == "on" or command == "enable" then
		SetEnabled(true)
	elseif command == "off" or command == "disable" then
		SetEnabled(false)
	elseif command == "unlock" then
		GetDatabase().locked = false
		UpdateAnchorVisibility()
		Print("anchor unlocked. Drag the CleanLoot label, then use /cleanloot lock.")
	elseif command == "lock" then
		GetDatabase().locked = true
		SaveAnchorPoint()
		UpdateAnchorVisibility()
		Print("anchor locked.")
	elseif command == "reset" then
		GetDatabase().point = nil
		ApplyAnchorPoint()
		UpdateAnchorVisibility()
		RefreshLayout()
		Print("anchor reset.")
	elseif command == "debug" then
		local db = GetDatabase()
		db.debug = not db.debug
		Print("debug " .. (db.debug and "enabled." or "disabled."))
	else
		Print("Unknown command. Use /cleanloot for help.")
	end
end

local function OnUpdate()
	local now = GetTime and GetTime() or 0
	local removeIDs = {}

	for rollID, row in pairs(rows) do
		if row.removeAt and now >= row.removeAt then
			removeIDs[#removeIDs + 1] = rollID
		else
			local remaining = GetRollTimeLeftSeconds(row)
			row.timer:SetText(tostring(math.ceil(remaining)))

			local width = ROW_WIDTH - 2
			if row.countdown and row.countdown > 0 then
				width = math.max(0, width * (remaining / row.countdown))
			end
			row.timerBar:SetWidth(width)

			if not row.itemInfoReady then
				RefreshRollInfo(row)
			end
			if remaining <= 0 and not row.removeAt then
				ScheduleRowRemoval(row, RESULT_SECONDS)
			end
		end
	end

	for _, rollID in ipairs(removeIDs) do
		RemoveRow(rollID)
	end

	if HasActiveRows() then
		HideNativeLootRollFrames()
	end
end

local function OnEvent(_, event, ...)
	if event == "ADDON_LOADED" then
		local loadedName = ...
		if loadedName == ADDON_NAME then
			GetDatabase()
			ApplyAnchorPoint()
			UpdateAnchorVisibility()
		end
	elseif event == "PLAYER_LOGIN" then
		ApplyAnchorPoint()
		UpdateAnchorVisibility()
	elseif event == "PLAYER_ENTERING_WORLD" then
		ClearRows()
		RestoreNativeLootRollFrames()
	elseif event == "START_LOOT_ROLL" then
		StartRoll(...)
	elseif event == "CANCEL_LOOT_ROLL" then
		local rollID = tonumber(...)
		if rollID then
			RemoveRow(rollID)
		end
	elseif event == "CONFIRM_LOOT_ROLL" then
		local rollID, rollType = ...
		local row = rows[tonumber(rollID)]
		if row then
			local choice = ROLL_TYPE_TO_CHOICE[tonumber(rollType)] or row.selected or "NEED"
			local r, g, b = GetChoiceColor(choice)
			if AutoConfirmLootRoll(rollID, rollType) then
				row.statusMode = "confirmed"
				row.status:SetTextColor(r, g, b)
				row.status:SetText("Confirmed " .. GetChoiceTooltip(choice))
			else
				row.statusMode = "confirm"
				row.status:SetTextColor(r, g, b)
				row.status:SetText("Confirm " .. GetChoiceTooltip(choice) .. " in popup")
			end
		end
	end
end

SetDefaultAnchorPoint()
UpdateAnchorVisibility()

if type(hooksecurefunc) == "function" and type(GroupLootFrame_OpenNewFrame) == "function" then
	hooksecurefunc("GroupLootFrame_OpenNewFrame", function()
		if IsEnabled() then
			HideNativeLootRollFrames()
		end
	end)
end

if type(hooksecurefunc) == "function" then
	hooksecurefunc("StaticPopup_Show", function(which)
		if which == "CONFIRM_LOOT_ROLL" and HasPendingConfirmation() then
			StartConfirmMonitor()
			TryClickConfirmPopup()
		end
	end)
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("START_LOOT_ROLL")
eventFrame:RegisterEvent("CANCEL_LOOT_ROLL")
eventFrame:RegisterEvent("CONFIRM_LOOT_ROLL")
eventFrame:SetScript("OnEvent", OnEvent)
updateFrame:SetScript("OnUpdate", OnUpdate)

SLASH_CLEANLOOT1 = "/cleanloot"
SLASH_CLEANLOOT2 = "/cloot"
SlashCmdList.CLEANLOOT = HandleSlashCommand
