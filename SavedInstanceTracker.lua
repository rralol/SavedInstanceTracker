--Variables for communication
iComm = LibStub("AceAddon-3.0"):NewAddon("SavedIn", "AceComm-3.0")

local LibAceSerializer = LibStub:GetLibrary("AceSerializer-3.0")
local LibCompress = LibStub:GetLibrary("LibCompress")
local LibCompressAddonEncodeTable = LibCompress:GetAddonEncodeTable()

local version = "1.2.2"


function iComm:OnEnable()
	iComm:RegisterComm("SavedIn", iComm:OnCommReceived())
end

--Local session variables
local currentLocation = {};
local wasInGroup = false;
local delayedReset = false;
local readyTicker;

--Custom print function for addon messages.
function SavedInPrint(...)
	local savedIn = "|cFFFF6464SavedIn|r:";
	DEFAULT_CHAT_FRAME:AddMessage(string.join(" ", savedIn, ...));
end

--Handles recieved addon messages.
function iComm:OnCommReceived(prefix, message, distribution, sender)
	if prefix == "SavedIn" then
		if message == "ResetBroadcast" then
			if not UnitIsGroupLeader("player") and UnitIsGroupLeader(sender) then
				SavedInPrint("Recieved reset message from party leader.");
				allowMultipleOfInstance = true;
			end
		elseif message  == "ResetRequest" then
			if UnitIsGroupLeader("player") and allowResetRequest then
				SavedInPrint("Recieved reset reqeust from party member sending confirmation.");
				iComm:sendMessage("RequestConfirm");
				--Start the timer for checking if all player are ready for reset run for 120 seconds
				readyTicker = C_Timer.NewTicker(1, function () CheckPlayersResetReady(); end, 120)
			end
		elseif message == "RequestConfirm" then
			local inInstance,_ = IsInInstance();
			--allowMultipleOfInstance = true
			if inInstance and not UnitIsGroupLeader("player") then
				SavedInPrint("Recieved reset confirmation from party leader you have 2 minutes to leave the instance or logout.");
			elseif not UnitIsGroupLeader("player") then
				SavedInPrint("Recieved reset confirmation from party leader please stay out of the instance.");
			end
		end
	end
end

function CheckPlayersResetReady()
	--Check if all players in party is offline or outside instance
	local partyMembers = GetHomePartyInfo();
	local inInstance,_ = IsInInstance();
	local allReady = true
	if not inInstance then
		for i=1, #partyMembers do
			local playerInInstance,_,_,_ = UnitPosition(partyMembers[i])
			--If someone is online and in instance set flag to false 
			if UnitIsConnected(partyMembers[i]) and playerInInstance == nil then
				allReady = false
			end
		end
		if allReady then
			readyTicker:Cancel();
			SavedInPrint("All players are ready for reset.");
			ResetInstances();
		end
	end
end


function iComm:sendMessage(message)
	iComm:SendCommMessage("SavedIn",message,"PARTY");
end

--Broadcast reset to other pary members
local function BroadcastResetDungeonSuccess()	
	if IsInGroup() and UnitIsGroupLeader("player") then
		SavedInPrint("Sending reset successful to other party memebers.")
		iComm:sendMessage("ResetBroadcast");
	else
		SavedInPrint("Resetting dungeons.")
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
local function GetTimeToReset(index)
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
			SavedInPrint("No active lockouts.");
		else 
			for i=1, #SavedInstances_DB do
				if GetTimeToReset(i) > 0 then
					SavedInPrint(i..": "..SavedInstances_DB[i].instanceName.." |cFFFF6464Releases in|r : "..GetTimeToReset(i).." minutes");
				else
					SavedInPrint(i..": "..SavedInstances_DB[i].instanceName.." |cFFFF6464Dungeon in progress|r!");
				end
			
			end
		end
	--Request reset from leader
	elseif str == "request" then
		if IsInGroup() then
			SavedInPrint("Sending reset request to leader.")
			iComm:sendMessage("ResetRequest");
		else 
			SavedInPrint("Reseting dungeon when player exits dungeon.")
			local inInstance,_ = IsInInstance();
			if inInstance then
				delayedReset = true;
			else
				SavedInPrint("Player outside of instance reseting dungeon!");
				C_Timer.After(1, ResetInstances);
			end
		end
	--Forcing new instance
	elseif str == "reset" then
		local inInstance,_ = IsInInstance();
		if inInstance then
			SavedInPrint("Forcing new instance lockout to be added.")
			local instanceName,_,_,_,_,_,_,instanceId,_ = GetInstanceInfo();
			SavedInstances_DB[#SavedInstances_DB].timeEnd = time() + 3600;
			SavedInstances_DB[#SavedInstances_DB].active = false;
			AddInstanceLockout(instanceName, instanceId);
		else
			SavedInPrint("Next instance will count as a new instance.")
			allowMultipleOfInstance = true;
		end
	--Run soft reset command
	elseif str == "softreset" then 
		allowMultipleOfInstance = true;
		SavedInPrint("Next instance will count as a new instance.")
	elseif str == "allowRequest" then
		if allowResetRequest then
			SavedInPrint("Disallowing party reset requests.")
		else
			SavedInPrint("Allowing party reset requests.")
		end
	--Print list of commands
	elseif str == "?" or "help" then
		SavedInPrint("List of commands:")
		SavedInPrint("/sav reset - Forces a new entry of the current instance.")
		SavedInPrint("/sav softreset - Tells the addon to expect a fresh instance next time one of the same name is entered.")
		SavedInPrint("/sav request - Request an automatic reset from party leader(requires leader to SavedInstanceTracker addon).")
		SavedInPrint("/sav allowRequest - Toggles between allowing and disallowing party members to send request resets when party leader.")
		SavedInPrint("/sav help - Display a list and description of available commands.") 
	end
end


local function AddInstanceLockout(name, id)
	SavedInPrint("New instance detected, adding to table.");
	allowMultipleOfInstance = false;
	tinsert(SavedInstances_DB,{instanceName = name, countdownActive = false, mapid = id, timeEnd = 0, backupEndTime = time() + 3600 , player = select(1 ,UnitName("player"))})
end

--Check if an instance of the same name tied to the same character already exists in the DB
local function CheckMultipleEntries(id)
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
	SLASH_SavedInstanceTracker1 = "/sav";
	SlashCmdList["SavedInstanceTracker"] = HandleSlashCommands;
	--Create empty database if not found and purge old entries
	if not SavedInstances_DB then SavedInstances_DB = {} end;
	if not lastLocation then lastLocation = {instanceId = -1, subZone = "nil"} end;
	if allowMultipleOfInstance == nil then 	allowMultipleOfInstance = true end;
	if allowResetRequest == nil then allowResetRequest = true end;
end

local function GetCurrentLocation()
	local name, instanceType, difficultyID, difficultyName, maxPlayers, dynamicDifficulty, isDynamic, instanceID, instanceGroupSize, LfgDungeonID = GetInstanceInfo();
	local location = {};
	if instanceType == "party" or instanceType == "raid" then
		location.instanceId = instanceID; 
		location.subZone = GetSubZoneText();
	else
		location.instanceId = -1;
		location.subZone = "nil";
	end
	return location;
end

local function UpdateCurrentLocation()
	currentLocation = GetCurrentLocation();
end

--Checking for offline reset
local function checkForOfflineReset()
	--Debug
	--SavedInPrint("Curzone: "..currentLocation.subZone.. " Lastzone: "..lastLocation.subZone);
	if currentLocation.instanceId == lastLocation.instanceId and currentLocation.subZone ~= lastLocation.subZone then
		--Debug
		--SavedInPrint("true");
		return true;
	else
		return false;
	end
end

local function UpdateGroupStatus()
	if IsInGroup() then
		wasInGroup = true;
	else
		wasInGroup = false;
	end
end

local function isInPvEInstance(instanceType)
	if instanceType == "raid" or instanceType == "party" then
		return true
	else 
		return false
	end
end

local function EventHandler(self, event, arg1, ...)
	if event == "ADDON_LOADED" then
		OnInitialize(event, arg1);
		self:UnregisterEvent("ADDON_LOADED")
		
	elseif event == "PLAYER_ENTERING_WORLD" then
		--Update session variables
		UpdateCurrentLocation();
		UpdateGroupStatus();
		--Check if in raid or dungeon
		local inInstance,instanceType = IsInInstance();
		if inInstance and isInPvEInstance(instanceType) then
		
			local instanceName,_,_,_,instanceMaxPlayers,_,_,instanceId,_ = GetInstanceInfo();
			--Check if an active instance of the same name exists 
			if CheckMultipleEntries(instanceId) and allowMultipleOfInstance == false then
				--Check for offline reset
				if checkForOfflineReset() then
					--Set endtime for last instance
					SavedInPrint("Offline reset detected.");
					SavedInstances_DB[#SavedInstances_DB].timeEnd = time() + 3600;
					AddInstanceLockout(instanceName, instanceId);
				else
					-- Set endTime to 0 since the instance is still active
					SavedInPrint("Player reentered active lockout reseting countdown.");
					SavedInstances_DB[#SavedInstances_DB].countdownActive = false
					SavedInstances_DB[#SavedInstances_DB].timeEnd = 0
				end
			else
				AddInstanceLockout(instanceName, instanceId);
			end
		-- Run once everytime a player leaves instance
		elseif not inInstance and #SavedInstances_DB > 0 then
			if SavedInstances_DB[#SavedInstances_DB].countdownActive == false then
				SavedInPrint("Player has left the dungeon starting lockout countdown.");
				--Set endtime for last instance and set to inactive
				SavedInstances_DB[#SavedInstances_DB].timeEnd = time() + 3600;
				SavedInstances_DB[#SavedInstances_DB].countdownActive = true
			end
		end
		
		--Check for delayedReset if true resetdungeon(Used for Solo reset request)
		if delayedReset and not inInstance and not IsInGroup() then
			SavedInPrint("Player outside of instance reseting dungeon.");
			C_Timer.After(1, ResetInstances);
			delayedReset = false;
		end
		
	elseif event == "PLAYER_LOGIN" then
		PurgeExpiredEntries();
		SavedInPrint("Addon version "..version.." loaded. You currently have "..#SavedInstances_DB.."/5 lockouts active!");
		SavedInPrint("Use /sav help - for more information!");
		
	elseif event == "ZONE_CHANGED_NEW_AREA" then
		local inInstance,_ = IsInInstance();
		if inInstance then
			--Debug
			--SavedInPrint(GetSubZoneText());
			--Update location
			UpdateCurrentLocation();
		end
	elseif event == "PLAYER_CAMPING" then
		--Set logout location
		lastLocation = GetCurrentLocation();
	elseif event == "GROUP_ROSTER_UPDATE" then
		--Reset if leaving group outside of instance.
		local inInstance,_ = IsInInstance();
		if not inInstance and not IsInGroup() and wasInGroup then
			--debug
			--SavedInPrint("Player leaving party outside of instance.");
			allowMultipleOfInstance = true
		end
	elseif event == "INSTANCE_BOOT_START" then
		--Reset instance
		allowMultipleOfInstance = true
		UpdateGroupStatus();
		
	elseif event == "INSTANCE_BOOT_STOP" then
		if IsInGroup() then 
			allowMultipleOfInstance = false
			UpdateGroupStatus();
		end
	-- Detect Dungeon Reset through chat message
	elseif event == "CHAT_MSG_SYSTEM" then
		local resetMessagePattern = "^" .. gsub(INSTANCE_RESET_SUCCESS, "%%s", ".+") .. "$"
		--Check for reset message and broadcast if found
		if arg1:match(resetMessagePattern) then
			allowMultipleOfInstance = true;
			BroadcastResetDungeonSuccess();
		end
	end
end

--Event Registration setup
local events = CreateFrame("Frame", "EventsFrame");
events:RegisterEvent("ADDON_LOADED");
events:RegisterEvent("INSTANCE_BOOT_START");
events:RegisterEvent("INSTANCE_BOOT_STOP");
events:RegisterEvent("PLAYER_LOGIN");
events:RegisterEvent("PLAYER_CAMPING");
events:RegisterEvent("PLAYER_ENTERING_WORLD");
events:RegisterEvent("GROUP_ROSTER_UPDATE");
events:RegisterEvent("ZONE_CHANGED_NEW_AREA");
events:RegisterEvent("CHAT_MSG_SYSTEM");
events:SetScript("OnEvent", EventHandler);
