local L = LibStub("AceLocale-3.0"):GetLocale("Altoholic")

local WHITE		= "|cFFFFFFFF"
local RED		= "|cFFFF0000"
local GREEN		= "|cFF00FF00"
local TEAL		= "|cFF00FF9A"

Altoholic.Quests = {}

function Altoholic.Quests:Update()
	local character = Altoholic.Tabs.Characters:GetCurrent()

	
	local VisibleLines = 14
	local frame = "AltoholicFrameQuests"
	local entry = frame.."Entry"
	
	local self = Altoholic.Quests
	local DS = DataStore
	
	if DS:GetQuestLogSize(character) == 0 then
		AltoholicTabCharactersStatus:SetText(L["No quest found for "] .. Altoholic:GetCurrentCharacter())
		Altoholic:ClearScrollFrame( _G[ frame.."ScrollFrame" ], entry, VisibleLines, 18)
		return
	end
	AltoholicTabCharactersStatus:SetText("")
	
	local offset = FauxScrollFrame_GetOffset( _G[ frame.."ScrollFrame" ] );
	local DisplayedCount = 0
	local VisibleCount = 0
	local DrawGroup

	self.CollapsedHeaders = self.CollapsedHeaders or {}
	if self.isInvalid then
		wipe(self.CollapsedHeaders)
		self.isInvalid = nil
	end

	local i=1
	
	for line = 1, DS:GetQuestLogSize(character) do
		local isHeader, quest, questTag, groupSize, money, isComplete = DS:GetQuestLogInfo(character, line)
		
		if (offset > 0) or (DisplayedCount >= VisibleLines) then		-- if the line will not be visible
			if isHeader then													-- then keep track of counters
				
				if not self.CollapsedHeaders[line] then
					DrawGroup = true
				else
					DrawGroup = false
				end
				VisibleCount = VisibleCount + 1
				offset = offset - 1		-- no further control, nevermind if it goes negative
			elseif DrawGroup then
				VisibleCount = VisibleCount + 1
				offset = offset - 1		-- no further control, nevermind if it goes negative
			end
		else		-- line will be displayed
			if isHeader then
				if not self.CollapsedHeaders[line] then
					_G[ entry..i.."Collapse" ]:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up"); 
					DrawGroup = true
				else
					_G[ entry..i.."Collapse" ]:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up");
					DrawGroup = false
				end
				_G[entry..i.."Collapse"]:Show()
				_G[entry..i.."QuestLinkNormalText"]:SetText(TEAL .. quest)
				_G[entry..i.."QuestLink"]:SetID(0)
				_G[entry..i.."QuestLink"]:SetPoint("TOPLEFT", 25, 0)
				
				_G[entry..i.."Tag"]:Hide()
				_G[entry..i.."Status"]:Hide()
				_G[entry..i.."Money"]:Hide()
				
				_G[ entry..i ]:SetID(line)
				_G[ entry..i ]:Show()
				i = i + 1
				VisibleCount = VisibleCount + 1
				DisplayedCount = DisplayedCount + 1
				
			elseif DrawGroup then
				_G[entry..i.."Collapse"]:Hide()
				
				local _, _, level = DS:GetQuestInfo(quest)
				-- quick fix, level may be nil, I suspect that due to certain locales, the quest link may require different parsing.
				level = level or 0
				
				_G[entry..i.."QuestLinkNormalText"]:SetText(WHITE .. "[" .. level .. "] " .. quest)
				_G[entry..i.."QuestLink"]:SetID(line)
				_G[entry..i.."QuestLink"]:SetPoint("TOPLEFT", 15, 0)
				if questTag then 
					_G[entry..i.."Tag"]:SetText(self:GetTypeString(questTag, groupSize))
					_G[entry..i.."Tag"]:Show()
				else
					_G[entry..i.."Tag"]:Hide()
				end
				
				_G[entry..i.."Status"]:Hide()
				if isComplete == 1 then
					_G[entry..i.."Status"]:SetText(GREEN .. COMPLETE)
					_G[entry..i.."Status"]:Show()
				elseif isComplete == -1 then
					_G[entry..i.."Status"]:SetText(RED .. FAILED)
					_G[entry..i.."Status"]:Show()
				end
				
				if money then
					_G[entry..i.."Money"]:SetText(Altoholic:GetMoneyString(money))
					_G[entry..i.."Money"]:Show()
				else
					_G[entry..i.."Money"]:Hide()
				end
					
				_G[ entry..i ]:SetID(line)
				_G[ entry..i ]:Show()
				i = i + 1
				VisibleCount = VisibleCount + 1
				DisplayedCount = DisplayedCount + 1
			end
		end
	end 

	while i <= VisibleLines do
		_G[ entry..i ]:SetID(0)
		_G[ entry..i ]:Hide()
		i = i + 1
	end
	
	FauxScrollFrame_Update( _G[ frame.."ScrollFrame" ], VisibleCount, VisibleLines, 18);
end

function Altoholic.Quests:InvalidateView()
	self.isInvalid = true
end

function Altoholic.Quests:ListCharsOnQuest(questName, player, tooltip)
	if not questName then return nil end
	
	local DS = DataStore
	local CharsOnQuest = {}
	for characterName, character in pairs(DS:GetCharacters(realm)) do
		if characterName ~= player then
			for i = 1, DS:GetQuestLogSize(character) do
				local isHeader, link = DS:GetQuestLogInfo(character, i)
				if not isHeader then
					local altQuestName = DS:GetQuestInfo(link)
					if altQuestName == questName then		-- same quest found ?
						table.insert(CharsOnQuest, DS:GetColoredCharacterName(character))	
					end
				end
			end
		end
	end
	
	if #CharsOnQuest > 0 then
		tooltip:AddLine(" ",1,1,1);
		tooltip:AddLine(GREEN .. L["Are also on this quest:"],1,1,1);
		tooltip:AddLine(table.concat(CharsOnQuest, "\n"),1,1,1);
	end
end

function Altoholic.Quests:GetTypeString(tag, size)
	local color

	if size == 2 then
		color = GREEN
	elseif size == 3 then
		color = YELLOW
	elseif size == 4 then
		color = ORANGE
	elseif size == 5 then
		color = RED
	end

	if color then
		return format("%s%s%s (%d)", WHITE, tag, color, size)
	else
		return format("%s%s", WHITE, tag)
	end
end

function Altoholic.Quests:Link_OnEnter(self)
	local id = self:GetID()
	if id == 0 then return end

	local DS = DataStore
	local character = Altoholic.Tabs.Characters:GetCurrent()
	local _, link = DS:GetQuestLogInfo(character, id)
	if not link then return end

	GameTooltip:ClearLines();
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:SetHyperlink(link);
	GameTooltip:AddLine(" ",1,1,1);
	
	local questName, questID, level = DS:GetQuestInfo(link)
	GameTooltip:AddDoubleLine(LEVEL .. ": |cFF00FF9A" .. level, L["QuestID"] .. ": |cFF00FF9A" .. questID);
	
	local player = Altoholic:GetCurrentCharacter()
	Altoholic.Quests:ListCharsOnQuest(questName, player, GameTooltip)
	GameTooltip:Show();
end

function Altoholic.Quests:Link_OnClick(self, button)
	if ( button == "LeftButton" ) and ( IsShiftKeyDown() ) then
		if ( ChatFrameEditBox:IsShown() ) then
			local id = self:GetID()
			if id == 0 then return end
			
			local character = Altoholic.Tabs.Characters:GetCurrent()
			local _, link = DataStore:GetQuestLogInfo(character, id)
	
			if not link then return end
			ChatFrameEditBox:Insert(link);
		end
	end
end