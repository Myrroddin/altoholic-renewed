local L = LibStub("AceLocale-3.0"):GetLocale("Altoholic")

local WHITE		= "|cFFFFFFFF"
local GREEN		= "|cFF00FF00"
local YELLOW	= "|cFFFFFF00"
local RED		= "|cFFFF0000"
local TEAL		= "|cFF00FF9A"

Altoholic.Mail = {}

local function SortByName(a, b, ascending)
	local DS = DataStore
	local character = Altoholic.Tabs.Characters:GetCurrent()
	
	local textA = DS:GetMailSubject(character, a) or ""
	local textB = DS:GetMailSubject(character, b) or ""

	if ascending then
		return textA < textB
	else
		return textA > textB
	end
end

local function SortBySender(a, b, ascending)
	local DS = DataStore
	local character = Altoholic.Tabs.Characters:GetCurrent()
	
	local senderA = DS:GetMailSender(character, a)
	local senderB = DS:GetMailSender(character, b)

	if ascending then
		return senderA < senderB
	else
		return senderA > senderB
	end
end

local function SortByExpiry(a, b, ascending)
	local DS = DataStore
	local character = Altoholic.Tabs.Characters:GetCurrent()
	
	local _, expiryA = DS:GetMailExpiry(character, a)
	local _, expiryB = DS:GetMailExpiry(character, b)
	
	if ascending then
		return expiryA < expiryB
	else
		return expiryA > expiryB
	end
end

local function FormatExpiry(character, index)
	local days, seconds = DataStore:GetMailExpiry(character, index)
	local colour
	
	if days > 10 then
		colour =  GREEN
	elseif days > 5 then
		colour = YELLOW
	else
		colour = RED
	end
	return colour .. SecondsToTime(seconds)
end

function Altoholic.Mail:BuildView(field, ascending)
	
	field = field or "expiry"

	self.view = self.view or {}
	wipe(self.view)
	
	local DS = DataStore
	local character = Altoholic.Tabs.Characters:GetCurrent()
	if not character then return end
	
	for i = 1, DS:GetNumMails(character) do
		table.insert(self.view, i)
	end

	if field == "name" then
		table.sort(self.view, function(a, b) return SortByName(a, b, ascending) end)
	elseif field == "from" then
		table.sort(self.view, function(a, b) return SortBySender(a, b, ascending) end)
	elseif field == "expiry" then
		table.sort(self.view, function(a, b) return SortByExpiry(a, b, ascending) end)
	end
end

function Altoholic.Mail:Update()
	local VisibleLines = 7
	local frame = "AltoholicFrameMail"
	local entry = frame.."Entry"
	
	local player = Altoholic:GetCurrentCharacter()
	local self = Altoholic.Mail
	
	local DS = DataStore
	local character = Altoholic.Tabs.Characters:GetCurrent()
	local lastVisit = DS:GetMailboxLastVisit(character)
	
	if lastVisit ~= 0 then
		local localDate = format(L["Last visit: %s by %s"], GREEN..date("%m/%d/%Y", lastVisit)..WHITE, GREEN..player)
		AltoholicFrameMailInfo1:SetText(localDate .. WHITE .. " @ " .. date("%H:%M", lastVisit))
		AltoholicFrameMailInfo1:Show()
	else
		-- never visited the AH
		AltoholicFrameMailInfo1:Hide()
	end
	
	local numMails = DS:GetNumMails(character)
	if numMails == 0 then
		AltoholicTabCharactersStatus:SetText(format(L["%s has no mail"], player))
		-- make sure the scroll frame is cleared !
		Altoholic:ClearScrollFrame( _G[ frame.."ScrollFrame" ], entry, VisibleLines, 41)
		return
	else
		AltoholicTabCharactersStatus:SetText("")
	end
	
	local offset = FauxScrollFrame_GetOffset( _G[ frame.."ScrollFrame" ] );
	
	for i=1, VisibleLines do
		local line = i + offset
		if line <= numMails then
			local index = self.view[line]
			
			local icon, count, link = DS:GetMailInfo(character, index)
			
			_G[ entry..i.."Name" ]:SetText(link or DS:GetMailSubject(character, index))
			
			_G[ entry..i.."Character" ]:SetText(DS:GetMailSender(character, index))
			_G[ entry..i.."Expiry" ]:SetText(FormatExpiry(character, index))
			_G[ entry..i.."ItemIconTexture" ]:SetTexture(icon);
			if count and count > 1 then
				_G[ entry..i.."ItemCount" ]:SetText(count)
				_G[ entry..i.."ItemCount" ]:Show()
			else
				_G[ entry..i.."ItemCount" ]:Hide()
			end
			-- trick: pass the index of the current item in the results table, required for the tooltip
			_G[ entry..i.."Item" ]:SetID(index)
			_G[ entry..i ]:Show()
		else
			_G[ entry..i ]:Hide()
		end
	end
	
	if numMails < VisibleLines then
		FauxScrollFrame_Update( _G[ frame.."ScrollFrame" ], VisibleLines, VisibleLines, 41);
	else
		FauxScrollFrame_Update( _G[ frame.."ScrollFrame" ], numMails, VisibleLines, 41);
	end
end

function Altoholic.Mail:Sort(self, field)
	Altoholic.Mail:BuildView(field, self.ascendingSort)
	Altoholic.Mail:Update()
end

function Altoholic.Mail:CheckExpiries(elapsed)
	-- this function checks the expiry date of each mail stored on all realms, and sets a flag if any is below threshold
	if Altoholic.Options:Get("CheckMailExpiry") == 0 then return end
	
	local threshold = Altoholic.Options:Get("MailWarningThreshold")
	local DS = DataStore
	
	for realm, _ in pairs(DS:GetRealms()) do
		for _, character in pairs(DS:GetCharacters(realm)) do
			if DS:GetNumExpiredMails(character, threshold) > 0 then
				AltoMsgBox:SetHeight(130)
				AltoMsgBox_Text:SetHeight(60)
				AltoMsgBox.ButtonHandler = AltoholicMailExpiry_ButtonHandler
				AltoMsgBox_Text:SetText(format("%sAltoholic: %s%s", TEAL, WHITE, 
					"\n" .. L["Mail is about to expire on at least one character."] .. "\n" 
					.. L["Refer to the activity pane for more details."].. "\n\n")
					.. L["Do you want to view it now ?"])
				AltoMsgBox:Show()
				return
			end
		end
	end
end

function Altoholic.Mail:OnEnter(self)
	local DS = DataStore
	local character = Altoholic.Tabs.Characters:GetCurrent()
	local index = self:GetID()
	local _, _, link, money, text = DS:GetMailInfo(character, index)
						
	if link then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetHyperlink(link);
		GameTooltip:Show();
	else
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:ClearLines();
		
		local subject = DS:GetMailSubject(character, index)
		if subject then 
			GameTooltip:AddLine("|cFFFFFFFF" .. subject,1,1,1);
		end
		if text then 
			GameTooltip:AddLine("|cFFFFD700" .. text, 1, 1, 1, 1, 1);
		end
		if money > 0 then
			GameTooltip:AddLine("|rAttached Money: " .. Altoholic:GetMoneyString(money),1,1,1);
		end
		GameTooltip:Show();
	end
end

function Altoholic.Mail:OnClick(self, button)
	local DS = DataStore
	local character = Altoholic.Tabs.Characters:GetCurrent()
	local index = self:GetID()
	local _, _, link = DS:GetMailInfo(character, index)

	if link then
		if ( button == "LeftButton" ) and ( IsShiftKeyDown() ) then
			if ( ChatFrameEditBox:IsShown() ) then
				ChatFrameEditBox:Insert(link);
			end
		end
	end
end


function AltoholicMailExpiry_ButtonHandler(self, button)
	AltoMsgBox.ButtonHandler = nil		-- prevent any other call to msgbox from coming back here
	if not button then return end
	
	Altoholic:ToggleUI()
	Altoholic.Tabs.Summary:MenuItem_OnClick(4)
end


-- *** Hooks ***

local Orig_SendMail = SendMail

-- from Comm.lua
local MSG_GUILD_SENDMAIL_INIT				= 10
local MSG_GUILD_SENDMAIL_END				= 11
local MSG_GUILD_SENDMAIL_ATTACHMENTS	= 12
local MSG_GUILD_SENDMAIL_BODY				= 13

function SendMail(recipient, subject, body, ...)
	local isRecipientAnAlt

	-- check if recipient in an alt
	for CharacterName, _ in pairs(DataStore:GetCharacters()) do
		if strlower(CharacterName) == strlower(recipient) then			-- if recipient is a known alt
			isRecipientAnAlt = true
			break
		end
	end
	
	if not isRecipientAnAlt then	-- if recipient is not an alt, maybe it's a guildmate
		local player = Altoholic.Guild.Members:GetNameOfMain(recipient)
		
		if player then 
			-- this mail is sent to "player", but is for alt  "recipient"
			local comm = Altoholic.Comm.Guild
			
			comm:Whisper(player, MSG_GUILD_SENDMAIL_INIT, recipient)
			comm:Whisper(player, MSG_GUILD_SENDMAIL_ATTACHMENTS, DataStore:GetMailAttachments())
			
			-- .. then save the mail itself + gold if any
			local moneySent = GetSendMailMoney()
			if (moneySent > 0) or (strlen(body) > 0) then
				comm:Whisper(player, MSG_GUILD_SENDMAIL_BODY, { moneySent, body, subject })
			end
			
			comm:Whisper(player, MSG_GUILD_SENDMAIL_END)
		end
	end
	
	Orig_SendMail(recipient, subject, body, ...)
end

local Orig_SendMailNameEditBox_OnChar = SendMailNameEditBox:GetScript("OnChar")

SendMailNameEditBox:SetScript("OnChar", function(...)
	local text = this:GetText(); 
	local textlen = strlen(text); 
	local DS = DataStore
	
	for characterName, character in pairs(DS:GetCharacters()) do
		if DS:GetCharacterFaction(character) == UnitFactionGroup("player") then
			if ( strfind(strupper(characterName), strupper(text), 1, 1) == 1 ) then
				SendMailNameEditBox:SetText(characterName);
				SendMailNameEditBox:HighlightText(textlen, -1);
				return;
			end
		end
	end
	
	if Orig_SendMailNameEditBox_OnChar then
		return Orig_SendMailNameEditBox_OnChar(...)
	end
end)