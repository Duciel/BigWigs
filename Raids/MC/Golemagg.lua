
local module, L = BigWigs:ModuleDeclaration("Golemagg the Incinerator", "Molten Core")

module.revision = 30075
module.enabletrigger = module.translatedName
module.toggleoptions = {"ragers", "enrage", "earthquake", "magma", "bosskill"}
module.wipemobs = {"Core Rager"}

L:RegisterTranslations("enUS", function() return {
	cmd = "Golemagg",

	enrage_cmd = "enrage",
	enrage_name = "Enrage Alert",
	enrage_desc = "Warn for Enrage",

	earthquake_cmd = "earthquake",
	earthquake_name = "Earthquake Alert",
	earthquake_desc = "Warn for Earthquake",
	
	ragers_cmd = "ragers",
	ragers_name = "Ragers Unchained Alert",
	ragers_desc = "Warn for Ragers Unchained (60%) and the Core Ragers' threat drops every 6 seconds",

	magma_cmd = "magma",
	magma_name = "Magma Splash Alert",
	magma_desc = "Warn for Magma Splash",
	
	
	trigger_enrage = "Golemagg the Incinerator gains Enrage.", --CHAT_MSG_SPELL_PERIODIC_CREATURE_BUFFS
	msg_enrage = "Golemagg is Enraged - Casting Earthquakes!",
	msg_enrageSoon = "Enrage Soon (at 25%) - Earthquake Soon",

	trigger_ragersUnchained = "Ragers Unchained",
	msg_ragersSoon = "Ragers Unchained Soon (at 60%)",
	msg_ragersUnchained = "Ragers Unchained - Core Ragers drop threat every 6 sec!",
	bar_threatDrop = "Core Rager threat drop",
	
	trigger_earthquake = "Golemagg the Incinerator's Earthquake", --CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE // CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE // CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE
	bar_earthquake = "Earthquake",
	
	trigger_magmaSplash = "You are afflicted by Magma Splash %((.+)%).", --CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE
	msg_magmaSplash = "Warning - High Magma Splash Stacks: ",
} end)

local timer = {
	earthquake = 3,
	threatDropFirst = 6.2, --public logs: first drop ~6s after Ragers Unchained
	threatDrop = 6, --public logs: drops every 6.0s, in step with the Unchained cast (65 kills)
}
local health = {
	ragersSoon = 65,
	ragers = 60, --Ragers Unchained at 59.2 - 60.2% Golemagg health (66 kills)
	enrageSoon = 30,
	enrage = 25, --OctoWoW: Enrage at 24.7 - 25.3% (66 kills); server script says 10%
}
local icon = {
	enrage = "spell_shadow_unholyfrenzy",
	earthquake = "spell_nature_earthquake",
	ragers = "ability_racial_bloodrage",
	threatDrop = "spell_nature_invisibilty",
	magmaSplash = "spell_fire_immolation",
}
local color = {
	earthquake = "Orange",
	threatDrop = "Red",
}
local syncName = {
	enrageSoon = "GolemaggEnrageSoon"..module.revision,
	enrage = "GolemaggEnrage"..module.revision,
	earthquake = "GolemaggEarthquake"..module.revision,
	ragersSoon = "GolemaggRagersSoon"..module.revision,
	ragers = "GolemaggRagersUnchained"..module.revision,
}

local enrageSoon = nil
local ragersSoon = nil
local ragersUnchained = nil

function module:OnEnable()
	--self:RegisterEvent("CHAT_MSG_SAY", "Event") --Debug
	
	self:RegisterEvent("UNIT_HEALTH")
	
	self:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_BUFFS", "Event") --trigger_enrage, trigger_ragersUnchained
	self:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_CREATURE_BUFF", "Event") --trigger_ragersUnchained
	
	self:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE", "Event") --trigger_earthquake
	self:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE", "Event") --trigger_earthquake
	self:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE", "Event") --trigger_earthquake
	
	self:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE", "Event") --trigger_magmaSplash
	
	
	self:ThrottleSync(10, syncName.enrageSoon)
	self:ThrottleSync(10, syncName.enrage)
	self:ThrottleSync(1, syncName.earthquake)
	self:ThrottleSync(10, syncName.ragersSoon)
	self:ThrottleSync(30, syncName.ragers)
end

function module:OnSetup()
	self.started = nil
end

function module:OnEngage()
	enrageSoon = nil
	ragersSoon = nil
	ragersUnchained = nil
end

function module:OnDisengage()
	self:CancelScheduledEvent("GolemaggThreatDropStart")
	self:CancelScheduledEvent("GolemaggThreatDrop")
end

function module:UNIT_HEALTH(msg)
	if UnitName(msg) == module.translatedName then
		local healthPct = UnitHealth(msg) * 100 / UnitHealthMax(msg)
		if healthPct > health.enrage and healthPct <= health.enrageSoon and enrageSoon == nil and self.db.profile.enrage then
			self:Sync(syncName.enrageSoon)
		elseif healthPct > health.enrageSoon + 1 and enrageSoon == true then
			enrageSoon = nil
		elseif healthPct <= health.enrage and enrageSoon == nil then
			enrageSoon = true
		end

		if healthPct <= health.ragers and not ragersUnchained then
			self:Sync(syncName.ragers)
		elseif healthPct > health.ragers and healthPct <= health.ragersSoon and not ragersSoon then
			self:Sync(syncName.ragersSoon)
		end
	end
end

function module:Event(msg)
	if msg == L["trigger_enrage"] then
		self:Sync(syncName.enrage)

	elseif string.find(msg, L["trigger_ragersUnchained"]) then
		self:Sync(syncName.ragers)
	
	elseif string.find(msg, L["trigger_earthquake"]) then
		self:Sync(syncName.earthquake)
	
	elseif string.find(msg, L["trigger_magmaSplash"]) then
		local _,_, stacks, _ = string.find(msg, L["trigger_magmaSplash"])
		local stacksNum = tonumber(stacks)
		if stacksNum >= 12 then
			self:MagmaSplash(stacksNum)
		end
	end
end


function module:BigWigs_RecvSync(sync, rest, nick)
	if sync == syncName.enrageSoon and self.db.profile.enrage then
		self:EnrageSoon()
	elseif sync == syncName.enrage and self.db.profile.enrage then
		self:Enrage()
	
	elseif sync == syncName.earthquake and self.db.profile.earthquake then
		self:Earthquake()

	elseif sync == syncName.ragersSoon then
		self:RagersSoon()
	elseif sync == syncName.ragers then
		self:RagersUnchained()
	end
end


function module:EnrageSoon()
	enrageSoon = true
	
	if UnitClass("Player") == "Warrior" or UnitClass("Player") == "Rogue" or UnitClass("Player") == "Paladin" or UnitClass("Player") == "Shaman" or UnitClass("Player") == "Druid" then
		self:Message(L["msg_enrageSoon"], "Attention", false, nil, false)
	end
end

function module:Enrage()
	enrageSoon = true
	
	self:WarningSign(icon.enrage, 1)
	self:Message(L["msg_enrage"], "Urgent", false, nil, false)
	self:Sound("Beware")
	self:Earthquake()
end

function module:Earthquake()
	self:Bar(L["bar_earthquake"], timer.earthquake, icon.earthquake, true, color.earthquake)
end

function module:RagersSoon()
	ragersSoon = true
	if self.db.profile.ragers and not ragersUnchained then
		self:Message(L["msg_ragersSoon"], "Attention", false, nil, false)
	end
end

function module:RagersUnchained()
	if ragersUnchained then return end
	ragersUnchained = true
	ragersSoon = true

	if not self.db.profile.ragers then return end
	self:Message(L["msg_ragersUnchained"], "Important", false, nil, false)
	self:WarningSign(icon.ragers, 1)
	self:Sound("Alarm")

	-- threat drops are in step with the Unchained cast: ~6s after it, then every 6s
	self:Bar(L["bar_threatDrop"], timer.threatDropFirst, icon.threatDrop, true, color.threatDrop)
	self:ScheduleEvent("GolemaggThreatDropStart", function()
		self:ThreatDrop()
		self:ScheduleRepeatingEvent("GolemaggThreatDrop", self.ThreatDrop, timer.threatDrop, self)
	end, timer.threatDropFirst)
end

function module:ThreatDrop()
	self:Bar(L["bar_threatDrop"], timer.threatDrop, icon.threatDrop, true, color.threatDrop)
end

function module:MagmaSplash(rest)
	self:Message(L["msg_magmaSplash"]..rest)
	self:WarningSign(icon.magmaSplash, 0.7)
end
