-- ==========================================
-- RUNE DATA (Shared between Client & Server)
-- Path: ReplicatedStorage.Modules.RuneData
-- ==========================================
-- Stone runes are items that socket into a skill (SkillData Sockets) and change how it works.
-- Each rune is also an item base in ItemData ("Rune" .. id, Slot = "Rune"), so it drops, stacks in the
-- inventory and saves like any item. Effects run in CombatServer, the matching look in CombatClient
export type Rune = {
	Name: string,
	Description: string, -- Shown in the inventory
	Shapes: { [string]: boolean }?, -- Skill shapes it fits (SkillData Shape); nil = every skill
	Convert: string?, -- Element that CONVERT_PERCENT of the skill's physical damage turns into
}

local RuneData = {}

RuneData.Runes = {
	Reach = {
		Name = "Rune of Reach",
		Description = "+40% skill area",
	},
	Split = {
		Name = "Rune of Splitting",
		Description = "Also slashes 35° to each side (each enemy is still hit once)",
		Shapes = { Box = true },
	},
	Ember = {
		Name = "Ember Rune",
		Description = "50% of Physical damage becomes Fire (burns)",
		Convert = "Fire",
	},
	Frost = {
		Name = "Frost Rune",
		Description = "50% of Physical damage becomes Cold (chills, big hits freeze)",
		Convert = "Cold",
	},
	Storm = {
		Name = "Storm Rune",
		Description = "50% of Physical damage becomes Lightning (shocks)",
		Convert = "Lightning",
	},
	Detonation = {
		Name = "Rune of Detonation",
		Description = "Enemies this skill kills explode for 15% of their max health as Fire damage",
	},
} :: { [string]: Rune }

RuneData.AREA_MULTIPLIER = 1.4 -- Reach: hit box width / length / reach and spin radius
RuneData.SPLIT_ANGLE = 35 -- Split: degrees between the main slash and each side slash
RuneData.CONVERT_PERCENT = 0.5 -- Ember / Frost / Storm (several in one skill are scaled down to 100% total)
RuneData.EXPLODE_PERCENT = 0.15 -- Detonation: of the dead enemy's max health
RuneData.EXPLODE_RADIUS = 8 -- Detonation: studs around the corpse (explosion kills don't explode again)

-- Item base id of a rune (ItemData.Bases key)
function RuneData.getBaseId(runeId: string): string
	return "Rune" .. runeId
end

function RuneData.fits(runeId: string, skillShape: string): boolean
	local rune = RuneData.Runes[runeId]
	return rune ~= nil and (rune.Shapes == nil or rune.Shapes[skillShape] == true)
end

-- The server publishes each skill's runes as a player attribute "SkillRunes_<skillId>" = "Reach,Ember".
-- Returns them as a set: { Reach = true, Ember = true }
function RuneData.parse(text: any): { [string]: boolean }
	local runes = {}
	if type(text) == "string" then
		for runeId in string.gmatch(text, "[^,]+") do
			if RuneData.Runes[runeId] then
				runes[runeId] = true
			end
		end
	end
	return runes
end

return RuneData
