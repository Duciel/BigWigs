assert(BigWigs, "BigWigs not found!")

-- World Markers plugin
--
-- Lets boss modules place ground markers through worldmarkers.dll
-- (WeirdUtils, https://codeberg.org/MarcelineVQ/WeirdUtils).
-- The DLL syncs placed markers to the whole group itself, so only one
-- BigWigs user needs to place them: by default the raid/party leader.
--
-- DLL API used:
--   WorldMarker(index)              -- at cursor (not used by modules)
--   WorldMarker(index, unit)        -- at a unit's position
--   WorldMarker(index, x, y, z)     -- at world coordinates
--   ClearWorldMarker([index])       -- clear one / all
--   GetWorldMarker(index)           -- x, y, z, areaId
--   CanSetWorldMarker()             -- 1 if we are leader/assist
-- Marker indexes: 1 blue square, 2 green triangle, 3 purple diamond,
-- 4 red cross, 5 yellow star.
--
-- Module API (see Core.lua):
--   self:WorldMarker(index, unit)                 / (index, x, y, z)
--   self:TimedWorldMarker(duration, index, unit)  / (duration, index, x, y, z)
--   self:ClearWorldMarker(index)
--   self:ClearWorldMarkers()          -- every marker this module placed
--   self:CanPlaceWorldMarkers()
-- Markers placed by a module are cleared automatically when it disengages.

local L = AceLibrary("AceLocale-2.2"):new("BigWigsWorldMarkers")

L:RegisterTranslations("enUS", function()
	return {
		["World Markers"] = true,
		["worldmarkers"] = true,
		["Options for World Markers (requires worldmarkers.dll)."] = true,

		["place"] = true,
		["Place World Markers"] = true,
		["Let boss modules place World Markers for mechanics. Only works for the raid leader or assists, and needs worldmarkers.dll."] = true,

		["placer"] = true,
		["Who places markers"] = true,
		["Markers are synced to the whole raid by the DLL, so only one person needs to place them. 'leader': only the raid leader places them. 'assist': any leader or assist with this option places them."] = true,
		["leader"] = true,
		["assist"] = true,

		["clear"] = true,
		["Clear on fight end"] = true,
		["Clear markers placed by a boss module when the fight ends (kill or wipe)."] = true,

		["test"] = true,
		["Test"] = true,
		["Place the blue square on yourself for 5 seconds."] = true,

		["worldmarkers.dll is not loaded."] = true,
		["You are not allowed to place World Markers (leader/assist only)."] = true,
	}
end)

----------------------------------
--      Module Declaration      --
----------------------------------

BigWigsWorldMarkers = BigWigs:NewModule(L["World Markers"])
BigWigsWorldMarkers.revision = 1
BigWigsWorldMarkers.defaultDB = {
	place = true,
	placer = "leader",
	clear = true,
}
BigWigsWorldMarkers.consoleCmd = L["worldmarkers"]
BigWigsWorldMarkers.consoleOptions = {
	type = "group",
	name = L["World Markers"],
	desc = L["Options for World Markers (requires worldmarkers.dll)."],
	args = {
		[L["place"]] = {
			type = "toggle",
			name = L["Place World Markers"],
			desc = L["Let boss modules place World Markers for mechanics. Only works for the raid leader or assists, and needs worldmarkers.dll."],
			order = 1,
			get = function() return BigWigsWorldMarkers.db.profile.place end,
			set = function(v) BigWigsWorldMarkers.db.profile.place = v end,
		},
		[L["placer"]] = {
			type = "text",
			name = L["Who places markers"],
			desc = L["Markers are synced to the whole raid by the DLL, so only one person needs to place them. 'leader': only the raid leader places them. 'assist': any leader or assist with this option places them."],
			order = 2,
			get = function() return BigWigsWorldMarkers.db.profile.placer end,
			set = function(v) BigWigsWorldMarkers.db.profile.placer = v end,
			validate = { "leader", "assist" },
		},
		[L["clear"]] = {
			type = "toggle",
			name = L["Clear on fight end"],
			desc = L["Clear markers placed by a boss module when the fight ends (kill or wipe)."],
			order = 3,
			get = function() return BigWigsWorldMarkers.db.profile.clear end,
			set = function(v) BigWigsWorldMarkers.db.profile.clear = v end,
		},
		[L["test"]] = {
			type = "execute",
			name = L["Test"],
			desc = L["Place the blue square on yourself for 5 seconds."],
			order = 4,
			func = function() BigWigsWorldMarkers:Test() end,
		},
	}
}

-- index -> module that placed it (or true for the test marker)
local placedBy = {}

------------------------------
--      Helpers             --
------------------------------

function BigWigsWorldMarkers:IsAvailable()
	return type(WorldMarker) == "function" and type(ClearWorldMarker) == "function"
end

local function hasPermission()
	if type(CanSetWorldMarker) == "function" then
		local ok = CanSetWorldMarker()
		return ok and ok ~= 0
	end
	return IsRaidLeader() or IsRaidOfficer() or IsPartyLeader()
end

local function isLeader()
	if GetNumRaidMembers() > 0 then
		return IsRaidLeader()
	end
	return IsPartyLeader()
end

function BigWigsWorldMarkers:CanPlace()
	if not self.db.profile.place or not self:IsAvailable() then
		return false
	end
	if GetNumRaidMembers() == 0 and GetNumPartyMembers() == 0 then
		return false
	end
	if not hasPermission() then
		return false
	end
	if self.db.profile.placer ~= "assist" and not isLeader() then
		return false
	end
	return true
end

local function validIndex(index)
	return type(index) == "number" and index >= 1 and index <= 5
end

local function timerId(index)
	return "BigWigsWorldMarkerClear" .. index
end

------------------------------
--      Placement           --
------------------------------

-- Place marker `index` at a unit ("player", "raid12", "target", ...) or at x, y, z.
-- Returns x, y, z, areaId on success, nil otherwise.
function BigWigsWorldMarkers:Place(owner, index, a, b, c)
	if not validIndex(index) or not self:CanPlace() then
		return nil
	end

	local x, y, z, areaId
	if type(a) == "number" and type(b) == "number" and type(c) == "number" then
		x, y, z, areaId = WorldMarker(index, a, b, c)
	elseif type(a) == "string" then
		if not UnitExists(a) then
			return nil
		end
		x, y, z, areaId = WorldMarker(index, a)
	else
		return nil
	end

	-- the DLL returns nil (no permission) or a single negative code (failed)
	if x == nil or (y == nil and type(x) == "number" and x < 0) then
		return nil
	end

	self:CancelScheduledEvent(timerId(index))
	placedBy[index] = owner or true
	return x, y, z, areaId
end

function BigWigsWorldMarkers:PlaceTimed(owner, duration, index, a, b, c)
	local x, y, z, areaId = self:Place(owner, index, a, b, c)
	if x and type(duration) == "number" and duration > 0 then
		self:ScheduleEvent(timerId(index), self.Clear, duration, self, owner, index)
	end
	return x, y, z, areaId
end

-- Clear marker `index` if `owner` placed it (owner nil: clear regardless).
function BigWigsWorldMarkers:Clear(owner, index)
	if not validIndex(index) or not self:IsAvailable() then
		return
	end
	if owner and placedBy[index] ~= owner then
		return
	end
	self:CancelScheduledEvent(timerId(index))
	if placedBy[index] and hasPermission() then
		ClearWorldMarker(index)
	end
	placedBy[index] = nil
end

-- Clear every marker placed by `owner`.
function BigWigsWorldMarkers:ClearOwner(owner)
	for index = 1, 5 do
		if placedBy[index] == owner then
			self:Clear(owner, index)
		end
	end
end

function BigWigsWorldMarkers:OnFightEnd(owner)
	if self.db.profile.clear then
		self:ClearOwner(owner)
	end
end

function BigWigsWorldMarkers:Test()
	if not self:IsAvailable() then
		BigWigs:Print(L["worldmarkers.dll is not loaded."])
		return
	end
	if not hasPermission() then
		BigWigs:Print(L["You are not allowed to place World Markers (leader/assist only)."])
		return
	end
	local x = WorldMarker(1, "player")
	if x and not (type(x) == "number" and x < 0) then
		placedBy[1] = true
		self:ScheduleEvent(timerId(1), self.Clear, 5, self, true, 1)
	end
end
