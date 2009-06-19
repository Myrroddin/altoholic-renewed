local L = LibStub("AceLocale-3.0"):GetLocale("Altoholic")

local WHITE		= "|cFFFFFFFF"
local TEAL		= "|cFF00FF9A"
local GREEN		= "|cFF00FF00"

-- Weekday constants
local CALENDAR_WEEKDAY_NORMALIZED_TEX_LEFT	= 0.0;
local CALENDAR_WEEKDAY_NORMALIZED_TEX_TOP		= 180 / 256;
local CALENDAR_WEEKDAY_NORMALIZED_TEX_WIDTH	= 90 / 256 - 0.001; -- fudge factor to prevent texture seams
local CALENDAR_WEEKDAY_NORMALIZED_TEX_HEIGHT	= 28 / 256 - 0.001; -- fudge factor to prevent texture seams


local CALENDAR_MAX_DAYS_PER_MONTH			= 42;		-- 6 weeks
local CALENDAR_DAYBUTTON_NORMALIZED_TEX_WIDTH	= 90 / 256 - 0.001; -- fudge factor to prevent texture seams
local CALENDAR_DAYBUTTON_NORMALIZED_TEX_HEIGHT	= 90 / 256 - 0.001; -- fudge factor to prevent texture seams
local CALENDAR_DAYBUTTON_HIGHLIGHT_ALPHA		= 0.5;
local DAY_BUTTON = "AltoCalendarDayButton"
local MINIMUM_YEAR = 2009

local CALENDAR_FIRST_WEEKDAY = 1
-- 1 = Sunday, recreated locally to avoid the problem caused by the calendar addon not being loaded at startup.
-- On an EU client, CALENDAR_FIRST_WEEKDAY = 1 when the game is loaded, but becomes 2 as soon as the calendar is launched.
-- So default it to 1, and add an option to select Monday as 1st day of the week instead. If need be, use a slider.
-- Although the calendar is LoD, avoid it.

local CALENDAR_MONTH_NAMES = { CalendarGetMonthNames() };
local CALENDAR_WEEKDAY_NAMES = { CalendarGetWeekdayNames() };

local CALENDAR_FULLDATE_MONTH_NAMES = {
	-- month names show up differently for full date displays in some languages
	FULLDATE_MONTH_JANUARY,
	FULLDATE_MONTH_FEBRUARY,
	FULLDATE_MONTH_MARCH,
	FULLDATE_MONTH_APRIL,
	FULLDATE_MONTH_MAY,
	FULLDATE_MONTH_JUNE,
	FULLDATE_MONTH_JULY,
	FULLDATE_MONTH_AUGUST,
	FULLDATE_MONTH_SEPTEMBER,
	FULLDATE_MONTH_OCTOBER,
	FULLDATE_MONTH_NOVEMBER,
	FULLDATE_MONTH_DECEMBER,
};

local COOLDOWN_LINE = 1
local INSTANCE_LINE = 2
local CALENDAR_LINE = 3
local CONNECTMMO_LINE = 4
local TIMER_LINE = 5

Altoholic.Calendar = {}
Altoholic.Calendar.Days = {}
Altoholic.Calendar.Events = {}

function Altoholic.Calendar:Init()
	-- by default, the week starts on Sunday, adjust CALENDAR_FIRST_WEEKDAY if necessary
	if Altoholic.Options:Get("WeekStartsMonday") == 1 then
		CALENDAR_FIRST_WEEKDAY = 2
	end
	
	local _, thisMonth, _, thisYear = CalendarGetDate();
	CalendarSetAbsMonth(thisMonth, thisYear);
	
	-- only register after setting the current month
	Altoholic:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST", Altoholic.Calendar.OnUpdate)
	
	local band = bit.band;
	
	-- initialize weekdays
	for i = 1, 7 do
		local bg = _G["AltoholicFrameCalendarWeekday"..i.."Background"]
		local left = (band(i, 1) * CALENDAR_WEEKDAY_NORMALIZED_TEX_WIDTH) + CALENDAR_WEEKDAY_NORMALIZED_TEX_LEFT;		-- mod(index, 2) * width
		local right = left + CALENDAR_WEEKDAY_NORMALIZED_TEX_WIDTH;
		local top = CALENDAR_WEEKDAY_NORMALIZED_TEX_TOP;
		local bottom = top + CALENDAR_WEEKDAY_NORMALIZED_TEX_HEIGHT;
		bg:SetTexCoord(left, right, top, bottom);
	end
	
	-- initialize day buttons
	for i = 1, CALENDAR_MAX_DAYS_PER_MONTH do
		CreateFrame("Button", DAY_BUTTON..i, AltoholicFrameCalendar, "AltoCalendarDayButtonTemplate");
		self.Days:Init(i)
	end
	
	self.Events:BuildList()
	
	-- determine the difference between local time and server time
	Altoholic.Tasks:Add("SetClockDiff", 0, Altoholic.Calendar.SetClockDiff, Altoholic.Calendar)
end

local function GetWeekdayIndex(index)
	-- GetWeekdayIndex takes an index in the range [1, n] and maps it to a weekday starting
	-- at CALENDAR_FIRST_WEEKDAY. For example,
	-- CALENDAR_FIRST_WEEKDAY = 1 => [SUNDAY, MONDAY, TUESDAY, WEDNESDAY, THURSDAY, FRIDAY, SATURDAY]
	-- CALENDAR_FIRST_WEEKDAY = 2 => [MONDAY, TUESDAY, WEDNESDAY, THURSDAY, FRIDAY, SATURDAY, SUNDAY]
	-- CALENDAR_FIRST_WEEKDAY = 6 => [FRIDAY, SATURDAY, SUNDAY, MONDAY, TUESDAY, WEDNESDAY, THURSDAY]
	
	-- the expanded form for the left input to mod() is:
	-- (index - 1) + (CALENDAR_FIRST_WEEKDAY - 1)
	-- why the - 1 and then + 1 before return? because lua has 1-based indexes! awesome!
	return mod(index - 2 + CALENDAR_FIRST_WEEKDAY, 7) + 1;
end

local function GetFullDate(weekday, month, day, year)
	local weekdayName = CALENDAR_WEEKDAY_NAMES[weekday];
	local monthName = CALENDAR_FULLDATE_MONTH_NAMES[month];
	return weekdayName, monthName, day, year, month;
end

local function GetDay(fullday)
	-- full day = a date as YYYY-MM-DD
	-- this function is actually different than the one in Blizzard_Calendar.lua, since weekday can't necessarily be determined from a UI button
	local refDate = {}		-- let's use the 1st of current month as reference date
	local refMonthFirstDay
	refDate.month, refDate.year, _, refMonthFirstDay = CalendarGetMonth()
	refDate.day = 1

	local t = {}
	local year, month, day = strsplit("-", fullday)
	t.year = tonumber(year)
	t.month = tonumber(month)
	t.day = tonumber(day)

	local numDays = floor(difftime(time(t), time(refDate)) / 86400)
	local weekday = mod(refMonthFirstDay + numDays, 7)
	
	-- at this point, weekday might be negative or 0, simply add 7 to keep it in the proper range
	weekday = (weekday <= 0) and (weekday+7) or weekday
	
	return t.year, t.month, t.day, weekday
end

local TimeTable = {}	-- to pass as an argument to time()	see http://lua-users.org/wiki/OsLibraryTutorial for details

function Altoholic.Calendar:SetClockDiff(elapsed)
	-- this function is called every second until the server time changes (track minutes only)
	local ServerHour, ServerMinute = GetGameTime()
	local continue = true		-- keeps the task running
	
	if not self.ServerMinute then		-- ServerMinute not set ? this is the first pass, save it
		self.ServerMinute = ServerMinute
	else
		if self.ServerMinute ~= ServerMinute then		-- next minute ? do our stuff and stop
			local _, ServerMonth, ServerDay, ServerYear = CalendarGetDate()
			TimeTable.year = ServerYear
			TimeTable.month = ServerMonth
			TimeTable.day = ServerDay
			TimeTable.hour = ServerHour
			TimeTable.min = ServerMinute
			TimeTable.sec = 0					-- minute just changed, so second is 0

			-- our goal is achieved, we can calculate the difference between server time and local time, in seconds.
			-- a positive value means that the server time is ahead of local time.
			-- ex: server: 21:05, local 21.02 could lead to something like 180 (or close to it, depending on seconds)
			self.ClockDiff = difftime(time(TimeTable), time())
			self.Events:BuildList()		-- rebuild the event list to take the known difference into account
			
			-- now that the difference is known, we can check events for warnings, first check should occur right now (hence 0)
			Altoholic.Tasks:Add("EventWarning", 0, Altoholic.Calendar.CheckEvents, self)
		
			self.ServerMinute = nil
			continue = nil
		end
	end
	
	if continue then
		Altoholic.Tasks:Reschedule("SetClockDiff", 1)	-- 1 second later
		return true
	end
end

local TimerThresholds = { 15, 10, 5, 4, 3, 2, 1	}

function Altoholic.Calendar:CheckEvents(elapsed)
	if Altoholic.Options:Get("DisableWarnings") == 1 then	-- warnings disabled ? do nothing
		Altoholic.Tasks:Reschedule("EventWarning", 60)
		return true
	end

	-- called every 60 seconds
	local year, month, day, hour, minute
	
	for k, v in pairs(Altoholic.Calendar.Events.List) do
		year, month, day = strsplit("-", v.eventDate)
		hour, minute = strsplit(":", v.eventTime)

		TimeTable.year = tonumber(year)
		TimeTable.month = tonumber(month)
		TimeTable.day = tonumber(day)
		TimeTable.hour = tonumber(hour)
		TimeTable.min = tonumber(minute)
		
		local numMin = floor(difftime(time(TimeTable), time() + self.ClockDiff) / 60)
		
		if numMin == 0 then
			local _, _, title = Altoholic.Calendar.Events:GetInfo(k)
			Altoholic.Calendar:WarnUser(v.eventType, title, 0, v.char, v.realm)
			Altoholic.Calendar.Events:BuildList()
			Altoholic.Tabs.Summary:Refresh()
		elseif numMin <= 15 then
			for _, threshold in pairs(TimerThresholds) do
				if threshold == numMin then
					-- if snooze is allowed for this value
					if Altoholic.Options:Get("Warning"..threshold.."Min") == 1 then
						local _, _, title = Altoholic.Calendar.Events:GetInfo(k)
						Altoholic.Calendar:WarnUser(v.eventType, title, numMin, v.char, v.realm)
					end
					break
				elseif threshold < numMin then		-- save some cpu cycles, exit if threshold too low
					break
				end
			end
		end
	end
	
	-- the task was executed right after the minute changed server side, so reschedule exactly 60 seconds later
	Altoholic.Tasks:Reschedule("EventWarning", 60)
	return true
end

function Altoholic.Calendar:WarnUser(eventType, title, minutes, char, realm)
	local warning
	
	if minutes == 0 then
		if eventType == CALENDAR_LINE or eventType == CONNECTMMO_LINE then
			warning = format(CALENDAR_EVENTNAME_FORMAT_START .. " (%s/%s)", title, char, realm)
		end
	else
		local text
		if eventType == COOLDOWN_LINE or eventType == TIMER_LINE then
			text = L["%s will be ready in %d minutes (%s on %s)"]
		else
			text = L["%s starts in %d minutes (%s on %s)"]
		end
		
		warning = format(text, title, minutes, char, realm)
	end
	
	if not warning then return end
	
	if Altoholic.Options:Get("WarningDialogBox") == 1 then
		AltoMsgBox.ButtonHandler = self.WarningButtonHandler
		AltoMsgBox_Text:SetText(format("%s\n%s", WHITE..warning, L["Do you want to open Altoholic's calendar for details ?"]))
		AltoMsgBox:Show()
	else
		Altoholic:Print(warning)
	end
end

function Altoholic.Calendar:WarningButtonHandler(button)
	AltoMsgBox.ButtonHandler = nil		-- prevent any other call to msgbox from coming back here
	if not button then return end

	Altoholic:ToggleUI()
	Altoholic.Tabs.Summary:MenuItem_OnClick(8)
end

function Altoholic.Calendar:SetFirstDayOfWeek(day)
	CALENDAR_FIRST_WEEKDAY = day
end

function Altoholic.Calendar:Update()
	-- taken from CalendarFrame_Update() in Blizzard_Calendar.lua, adjusted for my needs.

	local self = Altoholic.Calendar
	local presentWeekday, presentMonth, presentDay, presentYear = CalendarGetDate();
	local prevMonth, prevYear, prevNumDays = CalendarGetMonth(-1);
	local nextMonth, nextYear, nextNumDays = CalendarGetMonth(1);
	local month, year, numDays, firstWeekday = CalendarGetMonth();

	-- set title
	AltoholicFrameCalendar_MonthYear:SetText(CALENDAR_MONTH_NAMES[month] .. " ".. year)
	
	-- initialize weekdays
	for i = 1, 7 do
		_G["AltoholicFrameCalendarWeekday"..i.."Name"]:SetText(string.sub(CALENDAR_WEEKDAY_NAMES[GetWeekdayIndex(i)], 1, 3));
	end

	local buttonIndex = 1;
	local isDarkened = true
	local day;

	-- set the previous month's days before the first day of the week
	local viewablePrevMonthDays = mod((firstWeekday - CALENDAR_FIRST_WEEKDAY - 1) + 7, 7);
	day = prevNumDays - viewablePrevMonthDays;

	while ( GetWeekdayIndex(buttonIndex) ~= firstWeekday ) do
		self.Days:Update(buttonIndex, day, prevMonth, prevYear, isDarkened)
		day = day + 1;
		buttonIndex = buttonIndex + 1;
	end

	-- set the days of this month
	day = 1;
	isDarkened = false
	while ( day <= numDays ) do
		self.Days:Update(buttonIndex, day, month, year, isDarkened)
		day = day + 1;
		buttonIndex = buttonIndex + 1;
	end
	
	-- set the first days of the next month
	day = 1;
	isDarkened = true
	while ( buttonIndex <= CALENDAR_MAX_DAYS_PER_MONTH ) do
		self.Days:Update(buttonIndex, day, nextMonth, nextYear, isDarkened)

		day = day + 1;
		buttonIndex = buttonIndex + 1;
	end
	
	self.Events:Update()
end

function Altoholic.Calendar.Days:Init(index)
	local button = _G[DAY_BUTTON..index]
	button:SetID(index)
	
	-- set anchors
	button:ClearAllPoints();
	if ( index == 1 ) then
		button:SetPoint("TOPLEFT", AltoholicFrameCalendar, "TOPLEFT", 285, -1);
	elseif ( mod(index, 7) == 1 ) then
		button:SetPoint("TOPLEFT", _G[DAY_BUTTON..(index - 7)], "BOTTOMLEFT", 0, 0);
	else
		button:SetPoint("TOPLEFT", _G[DAY_BUTTON..(index - 1)], "TOPRIGHT", 0, 0);
	end

	-- set the normal texture to be the background
	local tex = button:GetNormalTexture();
	tex:SetDrawLayer("BACKGROUND");
	local texLeft = random(0,1) * CALENDAR_DAYBUTTON_NORMALIZED_TEX_WIDTH;
	local texRight = texLeft + CALENDAR_DAYBUTTON_NORMALIZED_TEX_WIDTH;
	local texTop = random(0,1) * CALENDAR_DAYBUTTON_NORMALIZED_TEX_HEIGHT;
	local texBottom = texTop + CALENDAR_DAYBUTTON_NORMALIZED_TEX_HEIGHT;
	tex:SetTexCoord(texLeft, texRight, texTop, texBottom);
	
	-- adjust the highlight texture layer
	tex = button:GetHighlightTexture();
	tex:SetAlpha(CALENDAR_DAYBUTTON_HIGHLIGHT_ALPHA);
end

function Altoholic.Calendar.Days:Update(index, day, month, year, isDarkened)
	local button = _G[DAY_BUTTON..index]
	local buttonName = button:GetName();
	
	button.day = day
	button.month = month
	button.year = year
	
	-- set date
	local dateLabel = _G[buttonName.."Date"];
	local tex = button:GetNormalTexture();

	dateLabel:SetText(day);
	if isDarkened then
		tex:SetVertexColor(0.4, 0.4, 0.4)
	else
		tex:SetVertexColor(1.0, 1.0, 1.0)
	end
	
	-- set count
	local countLabel = _G[buttonName.."Count"];
	local count = Altoholic.Calendar.Events:GetNum(year, month, day)
	
	if count == 0 then
		countLabel:Hide()
	else
		countLabel:SetText(count)
		countLabel:Show()
	end
end

function Altoholic.Calendar.Days:OnClick(self, button)
	local Events = Altoholic.Calendar.Events
	local count = Events:GetNum(self.year, self.month, self.day)
	if count == 0 then	-- no events on that day ? exit
		return
	end	
	
	local index = Events:GetIndex(self.year, self.month, self.day)
	if index then
		Events:SetOffset(index - 1)	-- if the date is the 4th line, offset is 3
		Events:Update()
	end
end

function Altoholic.Calendar.Days:OnEnter(self)

	local Events = Altoholic.Calendar.Events
	local count = Events:GetNum(self.year, self.month, self.day)
	if count == 0 then	-- no events on that day ? exit
		return
	end
	
	AltoTooltip:SetOwner(self, "ANCHOR_LEFT");
	AltoTooltip:ClearLines();
	local eventDate = format("%04d-%02d-%02d", self.year, self.month, self.day)
	local weekday = GetWeekdayIndex(mod(self:GetID(), 7)) 
	weekday = (weekday == 0) and 7 or weekday
	
	AltoTooltip:AddLine(TEAL..format(FULLDATE, GetFullDate(weekday, self.month, self.day, self.year)));

	for k, v in pairs(Events.List) do
		if v.eventDate == eventDate then
			local char, eventTime, title = Events:GetInfo(k)
			AltoTooltip:AddDoubleLine(format("%s %s", WHITE..eventTime, char), title);
		end
	end
	AltoTooltip:Show();
end

local EVENT_DATE = 1
local EVENT_INFO = 2

function Altoholic.Calendar.Events:BuildView()
	self.view = self.view or {}
	wipe(self.view)
	
	-- the following list of events : 10/05, 10/05, 12/05, 14/05, 14/05
	-- turns into this view : 
	-- 	"10/05"
	--	event 1
	--	event 2
	--	"12/05"
	--	event 1
	-- 	"14/05"
	--	event 1
	--	event 2
	
	
	local eventDate = ""
	for k, v in pairs(self.List) do
		if eventDate ~= v.eventDate then
			table.insert(self.view, { linetype = EVENT_DATE, eventDate = v.eventDate })
			eventDate = v.eventDate
		end
		table.insert(self.view, { linetype = EVENT_INFO, parentID = k })
	end
end

function Altoholic.Calendar.Events:BuildList()
	self.List = self.List or {}
	wipe(self.List)

	local ClockDiff = Altoholic.Calendar.ClockDiff or 0
	
	for RealmName, r in pairs(Altoholic.ThisAccount) do
		for CharacterName, c in pairs(r.char) do
			-- Profession Cooldowns
			local isCDWarningDone
			for k, v in pairs(c.ProfessionCooldowns) do
				local reset, lastcheck = strsplit("|", v)
				reset = tonumber(reset)
				lastcheck = tonumber(lastcheck)
				
				if reset - (time() - lastcheck) > 0 then	-- expires later
					local expires = reset + lastcheck + ClockDiff
					self:Add(COOLDOWN_LINE, date("%Y-%m-%d",expires), date("%H:%M",expires), CharacterName, RealmName, k)
				else	-- has expired
					local _, item = strsplit("|", k)
					if not isCDWarningDone then
						-- prevents a wall of text for the professions that share like 20 CD's (alchemy,...)
						Altoholic:Print(format(L["%s is now ready (%s on %s)"], item, CharacterName, RealmName ))
						isCDWarningDone = true
					end
					c.ProfessionCooldowns[k] = nil
				end
			end
			
			-- Saved Instances
			for k, v in pairs(c.SavedInstance) do
				local reset, lastcheck = strsplit("|", v)
				reset = tonumber(reset)
				lastcheck = tonumber(lastcheck)
				
				if reset - (time() - lastcheck) > 0 then	-- expires later
					local expires = reset + lastcheck + ClockDiff
					self:Add(INSTANCE_LINE, date("%Y-%m-%d",expires), date("%H:%M",expires), CharacterName, RealmName, k)
				else	-- has expired
					local instance = strsplit("|", k)
					Altoholic:Print(format(L["%s is now unlocked (%s on %s)"], instance, CharacterName, RealmName ))
					c.SavedInstance[k] = nil
				end
				
			end
			
			-- Calendar Events
			for k, v in pairs(c.Calendar) do
				local eventDate, eventTime = strsplit("|", v)
				self:Add(CALENDAR_LINE, eventDate, eventTime, CharacterName, RealmName, k)
			end
			
			-- ConnectMMO events
			for k, v in pairs(c.ConnectMMO) do
				local eventDate, eventTime = strsplit("|", v)
				self:Add(CONNECTMMO_LINE, eventDate, eventTime, CharacterName, RealmName, k)
			end
			
			-- Other timers (like mysterious egg, etc..)
			for k, v in pairs(c.Timers) do
				local item, lastcheck, duration = strsplit("|", v)
				lastcheck = tonumber(lastcheck)
				duration = tonumber(duration)
				local expires = duration + lastcheck + ClockDiff
				if (expires - time()) > 0 then
					self:Add(TIMER_LINE, date("%Y-%m-%d",expires), date("%H:%M",expires), CharacterName, RealmName, k)
				else
					Altoholic:Print(format(L["%s is now ready (%s on %s)"], item, CharacterName, RealmName ))
					c.Timers[k] = nil
				end
			end
		end
	end
	
	-- sort by time
	self:Sort()
	self:BuildView()
end

local NUM_EVENTLINES = 14

function Altoholic.Calendar.Events:Update()
	local self = Altoholic.Calendar.Events
	
	local VisibleLines = NUM_EVENTLINES
	local frame = "AltoholicFrameCalendar"
	local entry = frame.."Entry"

	local offset = FauxScrollFrame_GetOffset( _G[ frame.."ScrollFrame" ] );

	for i=1, VisibleLines do
		local line = i + offset
		if line <= #self.view then
			local s = self.view[line]
			
			if s.linetype == EVENT_DATE then
				local year, month, day, weekday = GetDay(s.eventDate)
				_G[ entry..i.."Date" ]:SetText(format(FULLDATE, GetFullDate(weekday, month, day, year)))
				_G[ entry..i.."Date" ]:Show()
				
				_G[ entry..i.."Hour" ]:Hide()
				_G[ entry..i.."Character" ]:Hide()
				_G[ entry..i.."Title" ]:Hide()
				_G[ entry..i.."_Background"]:Show()
				
			elseif s.linetype == EVENT_INFO then
				local char, eventTime, title = self:GetInfo(s.parentID)

				_G[ entry..i.."Hour" ]:SetText(eventTime)
				_G[ entry..i.."Character" ]:SetText(char)
				_G[ entry..i.."Title" ]:SetText(title)
				
				_G[ entry..i.."Hour" ]:Show()
				_G[ entry..i.."Character" ]:Show()
				_G[ entry..i.."Title" ]:Show()

				_G[ entry..i.."Date" ]:Hide()
				_G[ entry..i.."_Background"]:Hide()
			end

			_G[ entry..i ]:SetID(line)
			_G[ entry..i ]:Show()
		else
			_G[ entry..i ]:Hide()
		end
	end
	
	local last = (#self.view < VisibleLines) and VisibleLines or #self.view
	FauxScrollFrame_Update( _G[ frame.."ScrollFrame" ], last, VisibleLines, 18);
end

function Altoholic.Calendar.Events:GetInfo(index)
	local e = self.List[index]		-- dereference event
	if not e then return end
				
	local c = Altoholic:GetCharacterTable(e.char, e.realm)
	local char = Altoholic:GetClassColor(c.englishClass) .. e.char
	if e.realm ~= GetRealmName() then	-- different realm ?
		char = format("%s %s(%s)", char, GREEN, e.realm)
	end
				
	local title, desc
	if e.eventType == COOLDOWN_LINE then
		_, title = strsplit("|", e.parentID)

		local reset, lastcheck = strsplit("|", c.ProfessionCooldowns[e.parentID])
		reset = tonumber(reset)
		lastcheck = tonumber(lastcheck)
		local expiresIn = reset - (time() - lastcheck)
		
		desc = format("%s %s", COOLDOWN_REMAINING, Altoholic:GetTimeString(expiresIn))
		
	elseif e.eventType == INSTANCE_LINE then
		-- title gets the instance name, desc gets the raid id
		title, desc = strsplit("|", e.parentID)
		
		--	CALENDAR_EVENTNAME_FORMAT_RAID_LOCKOUT = "%s Unlocks"; -- %s = Raid Name
		desc = format("%s%s\nID: %s%s", WHITE,
			format(CALENDAR_EVENTNAME_FORMAT_RAID_LOCKOUT, title), GREEN, desc)
	elseif e.eventType == CALENDAR_LINE then
		local eventType, inviteStatus
		_, _, title, eventType, inviteStatus = strsplit("|", c.Calendar[e.parentID])
		
		local StatusText = {
			CALENDAR_STATUS_INVITED,		-- CALENDAR_INVITESTATUS_INVITED   = 1
			CALENDAR_STATUS_ACCEPTED,		-- CALENDAR_INVITESTATUS_ACCEPTED  = 2
			CALENDAR_STATUS_DECLINED,		-- CALENDAR_INVITESTATUS_DECLINED  = 3
			CALENDAR_STATUS_CONFIRMED,		-- CALENDAR_INVITESTATUS_CONFIRMED = 4
			CALENDAR_STATUS_OUT,				-- CALENDAR_INVITESTATUS_OUT       = 5
			CALENDAR_STATUS_STANDBY,		-- CALENDAR_INVITESTATUS_STANDBY   = 6
		}
		
		desc = format("%s: %s", STATUS, WHITE..StatusText[tonumber(inviteStatus)])
		
	elseif e.eventType == CONNECTMMO_LINE then
		local eventType, eventDesc, attendees
		_, _, title, eventType, eventDesc, attendees = strsplit("|", c.ConnectMMO[e.parentID])
		
		local numPlayers, minLvl, maxLvl, privateToFriends, privateToGuild = strsplit(",", eventDesc)
		local eventTable = {}
	
		table.insert(eventTable, WHITE .. format(L["Number of players: %s"], GREEN .. numPlayers))
		table.insert(eventTable, WHITE .. format(L["Minimum Level: %s"], GREEN .. minLvl))
		table.insert(eventTable, WHITE .. format(L["Maximum Level: %s"], GREEN .. maxLvl))
		table.insert(eventTable, WHITE .. format(L["Private to friends: %s"], GREEN .. (tonumber(privateToFriends) == 1 and YES or NO)))
		table.insert(eventTable, WHITE .. format(L["Private to guild: %s"], GREEN .. (tonumber(privateToGuild) == 1 and YES or NO)))

		local attendeesTable = { strsplit(",", attendees) }
		
		if #attendeesTable > 0 then
			table.insert(eventTable, "")
			table.insert(eventTable, WHITE..L["Attendees: "].."|r")
			for _, name in pairs(attendeesTable) do
				table.insert(eventTable, " " .. name )
			end
			table.insert(eventTable, "")
			table.insert(eventTable, GREEN .. L["Left-click to invite attendees"])
		end
		
		desc = table.concat(eventTable, "\n")
	elseif e.eventType == TIMER_LINE then
		title = strsplit("|", c.Timers[e.parentID])
	end
				
	return char, e.eventTime, title, desc
end

function Altoholic.Calendar.Events:Sort()
	table.sort(self.List, function(a, b)
		if (a.eventDate ~= b.eventDate) then			-- sort by date first ..
			return a.eventDate < b.eventDate
		elseif (a.eventTime ~= b.eventTime) then		-- .. then by hour
			return a.eventTime < b.eventTime
		elseif (a.char ~= b.char) then					-- .. then by alt
			return a.char < b.char
		end
	end)
end

function Altoholic.Calendar.Events:Add(eventType, eventDate, eventTime, char, realm, index)
	table.insert(self.List, {
		eventType = eventType, 
		eventDate = eventDate, 
		eventTime = eventTime, 
		char = char,
		realm = realm,
		parentID = index })
end

function Altoholic.Calendar.Events:GetNum(year, month, day)
	local eventDate = format("%04d-%02d-%02d", year, month, day)
	local count = 0
	for k, v in pairs(self.List) do
		if v.eventDate == eventDate then
			count = count + 1
		end
	end
	return count
end

function Altoholic.Calendar.Events:OnEnter(frame)
	local self = Altoholic.Calendar.Events
	local s = self.view[frame:GetID()]
	if not s or s.linetype == EVENT_DATE then return end
	
	
	AltoTooltip:SetOwner(frame, "ANCHOR_RIGHT");
	AltoTooltip:ClearLines();
	-- local eventDate = format("%04d-%02d-%02d", self.year, self.month, self.day)
	-- local weekday = GetWeekdayIndex(mod(self:GetID(), 7))
	-- AltoTooltip:AddLine(TEAL..format(FULLDATE, GetFullDate(weekday, self.month, self.day, self.year)));
	
	local char, eventTime, title, desc = self:GetInfo(s.parentID)
	AltoTooltip:AddDoubleLine(format("%s %s", WHITE..eventTime, char), title);
	if desc then
		AltoTooltip:AddLine(" ")
		AltoTooltip:AddLine(desc)
	end
	AltoTooltip:Show();
end

function Altoholic.Calendar.Events:OnClick(frame, button)
	-- if an event is left-clicked, try to invite attendees. ConnectMMO events only
	
	local self = Altoholic.Calendar.Events
	local s = self.view[frame:GetID()]
	if not s or s.linetype == EVENT_DATE then return end		-- date line ? exit
	
	local e = self.List[s.parentID]		-- dereference event
	-- not a connectmmo event ? or wrong realm ? exit
	if not e or e.eventType ~= CONNECTMMO_LINE or e.realm ~= GetRealmName() then return end	
	
	local c = Altoholic:GetCharacterTable(e.char, e.realm)
	if not c then return end	-- invalid char table ? exit
	
	local _, _, _, _, _, attendees = strsplit("|", c.ConnectMMO[e.parentID])

	-- TODO, add support for raid groups
	for _, name in pairs({ strsplit(",", attendees) }) do
		if name ~= UnitName("player") then
			InviteUnit(name) 
		end
	end
end

function Altoholic.Calendar.Events:GetIndex(year, month, day)
	local eventDate = format("%04d-%02d-%02d", year, month, day)
	for k, v in pairs(self.view) do
		if v.linetype == EVENT_DATE and v.eventDate == eventDate then
			-- if the date line is found, return its index
			return k
		end
	end
end

function Altoholic.Calendar.Events:SetOffset(offset)
	if offset < 0 then
		offset = 0
	elseif offset > (#self.view - NUM_EVENTLINES) then
		offset = (#self.view - NUM_EVENTLINES)
	end
	FauxScrollFrame_SetOffset( AltoholicFrameCalendarScrollFrame, offset )
	AltoholicFrameCalendarScrollFrameScrollBar:SetValue(offset * 18)
end

function Altoholic.Calendar:Scan()
	if not CalendarFrame then
		-- The Calendar addon is LoD, and most functions return nil if the calendar is not loaded, so unless the CalendarFrame is valid, exit right away
		return
	end
	Altoholic:UnregisterEvent("CALENDAR_UPDATE_EVENT_LIST")	-- prevent CalendarSetAbsMonth from triggering a scan (= avoid infinite loop)
	
	local currentMonth, currentYear = CalendarGetMonth()		-- save the current month
	local _, thisMonth, _, thisYear = CalendarGetDate();
	CalendarSetAbsMonth(thisMonth, thisYear);
	
	local c = Altoholic.ThisCharacter
	wipe(c.Calendar)
	
	-- save last month, this month + 6 following months
	for monthOffset = -1, 6 do
		local month, year, numDays = CalendarGetMonth(monthOffset)
		
		for day = 1, numDays do
			for i = 1, CalendarGetNumDayEvents(monthOffset, day) do		-- number of events that day ..
				-- http://www.wowwiki.com/API_CalendarGetDayEvent
				local title, hour, minute, calendarType, _, eventType, _, _, inviteStatus = CalendarGetDayEvent(monthOffset, day, i)
				if calendarType ~= "HOLIDAY" and calendarType ~= "RAID_LOCKOUT" then
					-- don't save holiday events, they're the same for all chars, and would be redundant..who wants to see 10 fishing contests every sundays ? =)

					table.insert(c.Calendar, format("%s|%s|%s|%d|%d",
						format("%04d-%02d-%02d", year, month, day), format("%02d:%02d", hour, minute),
						title, eventType, inviteStatus ))
				end
			end
		end
	end
	
	CalendarSetAbsMonth(currentMonth, currentYear);		-- restore current month
	Altoholic:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST", Altoholic.Calendar.OnUpdate)
end

function Altoholic.Calendar:OnUpdate()
	local self = Altoholic.Calendar
	self:Scan()
	self.Events:BuildList()
	Altoholic.Tabs.Summary:Refresh()
end
