--Variables for communication
iComm = LibStub("AceAddon-3.0"):NewAddon("SavIT", "AceComm-3.0")

local LibAceSerializer = LibStub:GetLibrary("AceSerializer-3.0")
local LibCompress = LibStub:GetLibrary("LibCompress")
local LibCompressAddonEncodeTable = LibCompress:GetAddonEncodeTable()

local version = "1.1"


function iComm:OnEnable()
	iComm:RegisterComm("iCommReset", iComm:OnCommReceived())
end

local playerInInstance = false;

--Custom print function adds "SavedIn: " prefix
function savedInPrint(...)
	local savedIn = "|cFFFF6464SavedIn|r:";
	DEFAULT_CHAT_FRAME:AddMessage(string.join(" ", savedIn, ...));
end

--Check if sender is party leader
local function validateSender(sender)
	if UnitIsGroupLeader(sender) then
		return true;
	else
		return false;
	end
end

function iComm:OnCommReceived(prefix, message, distribution, sender)
	if (prefix) and validateSender(sender) then
		if prefix == "iCommReset" then
			if not UnitIsGroupLeader("player") then
				savedInPrint("Recieved reset message from party leader!");
				allowMultipleOfInstance = true;
			end
		end
	end
end

function iComm:sendResetMessage()
	iComm:SendCommMessage("iCommReset","0","PARTY");
end



--Broadcast reset to other pary members
local function BroadcastResetDungeon()	
	if IsInGroup() and UnitIsGroupLeader("player") then
		savedInPrint("Resetting dungeons. Sending reset command to other party memebers.")
		iComm:sendResetMessage();
	else
		savedInPrint("Resetting dungeons.")
	end
end

--Removes expired entries from saved db
local function PurgeExpiredEntries()
	if #SavedInstances_DB > 0 then
		local i = 1
		while i <= #SavedInstances_DB do
			if time() > SavedInstances_DB[i].timeEnd and time() > SavedInstances_DB[i].backupEndTime then
				if SavedInstances_DB[i].timeEnd == 0 and playerInInstance then
					i = i + 1;
				else 
					tremove(SavedInstances_DB, i);
				end
			else
				i = i + 1;
			end
		end
	end
end
--Checks the differens in time between timestamp and current time and returns result minutes
local function getTimeToReset(index)
	if SavedInstances_DB[index].timeEnd > 0 then
		local timeToReset = SavedInstances_DB[index].timeEnd - time()
		return math.ceil(timeToReset/60)
	else
		return 0
	end
end

--Handels all of the user commands
local function HandleSlashCommands(str)
	PurgeExpiredEntries();
	if #str == 0 then 
		-- Print the DBTable
		if #SavedInstances_DB == 0 then
			savedInPrint("No active lockouts.");
		else 
			for i=1, #SavedInstances_DB do
				if getTimeToReset(i) > 0 then
					savedInPrint(i..": "..SavedInstances_DB[i].instanceName.." |cFFFF6464Releases in|r : "..getTimeToReset(i).." minutes");
				else
					savedInPrint(i..": "..SavedInstances_DB[i].instanceName.." |cFFFF6464Dungeon in progress|r!");
				end
			
			end
		end
	--Run reset command
	elseif str == "soft" then 
		allowMultipleOfInstance = true;
		savedInPrint("Next instance will count as a new instance.")
	--Print list of commands
	elseif str == "?" or "help" then
		savedInPrint("List of commands:")
		savedInPrint("/saved soft - Tells the addon to expect a fresh instance next time one of the same name is entered.")
		savedInPrint("/saved help - Display a list and description of available commands.") 
	end
end


local function addInstanceLockout(name, id)
	allowMultipleOfInstance = false;
	tinsert(SavedInstances_DB,{instanceName = name, mapid = id, timeEnd = 0, backupEndTime = time() + 3600 , player = select(1 ,UnitName("player"))})
end

--Check if an instance of the same name already exists in the DB
local function checkMultipleEntries(id)
	for i=1, #SavedInstances_DB do
		if SavedInstances_DB[i].mapid == id and SavedInstances_DB[i].player == select(1 ,UnitName("player")) then
			return true
		end
	end
	return false
end

--Run this function when addon is loaded
local function OnInitialize(event, name)
	if (name ~= "SavedInstanceTracker") then return end
	--Initiate user commands
	SLASH_SavedInstanceTracker1 = "/saved";
	SlashCmdList["SavedInstanceTracker"] = HandleSlashCommands;
	--Create empty database if not found and purge old entries
	if not SavedInstances_DB then SavedInstances_DB = {} end;
	if allowMultipleOfInstance == nil then 	allowMultipleOfInstance = true end;
	
	
	
end

local function eventHandler(self, event, arg1, ...)
	if event == "ADDON_LOADED" then
		OnInitialize(event, arg1);
		self:UnregisterEvent("ADDON_LOADED")
	elseif event == "PLAYER_ENTERING_WORLD" then
		--Check if in raid or dungeon
		local inInstance,instanceType = IsInInstance();
		if inInstance then
			playerInInstance = true;
			local instanceName,_,_,_,instanceMaxPlayers,_,_,instanceId,_ = GetInstanceInfo();
			--Check if an active instance of the same name exists 
			if checkMultipleEntries(instanceId) and allowMultipleOfInstance == false then
				-- Set endTime to 0 since the instance is still active
				savedInPrint("Player reentered active lockout reseting countdown.");
				SavedInstances_DB[#SavedInstances_DB].timeEnd = 0
				--Check if the last entry was from another character					
				if tostring(SavedInstances_DB[#SavedInstances_DB].player) ~= tostring(select(1 ,UnitName("player"))) then
					savedInPrint("New instance detected, adding to table.");
					addInstanceLockout(instanceName, instanceId);
				end
			else
				savedInPrint("New instance detected, adding to table.");
				addInstanceLockout(instanceName, instanceId);
			end
		-- Run once everytime a player leaves instance
		elseif playerInInstance == true and allowMultipleOfInstance == false then
			savedInPrint("Player has left the dungeon starting lockout countdown.");
			playerInInstance = false
			--Set endtime for last instance
			SavedInstances_DB[#SavedInstances_DB].timeEnd = time() + 3600
		end
	elseif event == "PLAYER_LOGIN" then
		PurgeExpiredEntries();
		savedInPrint("Addon version "..version.." loaded. You currently have "..#SavedInstances_DB.."/5 lockouts active!");
		savedInPrint("Use /saved help - for more information!");
		--Update end time of last active entry if reset have been pressed and endtime = 0
		if #SavedInstances_DB > 0 then
			if allowMultipleOfInstance and SavedInstances_DB[#SavedInstances_DB].timeEnd == 0 then 
				SavedInstances_DB[#SavedInstances_DB].timeEnd = time() + 3600
			end
		end
	-- Detect Dungeon Reset through chat message
	elseif event == "CHAT_MSG_SYSTEM" then
		local resetMessagePattern = "^" .. gsub(INSTANCE_RESET_SUCCESS, "%%s", ".+") .. "$"
		--Check for reset message and broadcast if found
		if arg1:match(resetMessagePattern) then
			allowMultipleOfInstance = true;
			BroadcastResetDungeon();
		end
	end
end

--Event Registration setup
local events = CreateFrame("Frame", "EventsFrame");
events:RegisterEvent("ADDON_LOADED");
events:RegisterEvent("PLAYER_LOGIN");
events:RegisterEvent("PLAYER_ENTERING_WORLD");
events:RegisterEvent("CHAT_MSG_SYSTEM");
events:SetScript("OnEvent", eventHandler);