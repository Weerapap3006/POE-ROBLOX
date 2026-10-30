-- ==========================================
-- ELEMENTS (Shared between Client & Server)
-- Path: ReplicatedStorage.Modules.Elements
-- ==========================================
-- Elemental damage types and the ailments their hits inflict. The rules run on the server in
-- ServerStorage.Modules.Ailments; clients only read the ailment attributes on each Model
local Elements = {}

Elements.Types = { "Fire", "Cold", "Lightning" } -- Elemental damage types (everything else is "Physical")

-- Damage numbers and ailment labels
Elements.Colors = {
	Fire = Color3.fromRGB(255, 140, 50),
	Cold = Color3.fromRGB(120, 210, 255),
	Lightning = Color3.fromRGB(255, 230, 80),
} :: { [string]: Color3 }

-- Ailment attributes on a Model (set by the server while active) in display order
Elements.AilmentLabels = {
	{ Attribute = "Ignited", Text = "BURN", Element = "Fire" },
	{ Attribute = "Chilled", Text = "CHILL", Element = "Cold" },
	{ Attribute = "Frozen", Text = "FROZEN", Element = "Cold" },
	{ Attribute = "Shocked", Text = "SHOCK", Element = "Lightning" },
}

Elements.MAX_RESISTANCE = 75 -- Player resistance % above this doesn't count

-- Ignite (Fire): burns for IGNITE_DAMAGE_PERCENT of the hit's fire damage, spread over IGNITE_DURATION.
-- Only the strongest burn counts
Elements.IGNITE_DAMAGE_PERCENT = 1
Elements.IGNITE_DURATION = 2

-- Chill (Cold): moves CHILL_SLOW slower
Elements.CHILL_SLOW = 0.3
Elements.CHILL_DURATION = 2

-- Freeze (Cold hit worth at least FREEZE_THRESHOLD of max health): can't move, attack or dodge,
-- and an enemy attack in its windup is cancelled
Elements.FREEZE_THRESHOLD = 0.1
Elements.FREEZE_DURATION = 1

-- Shock (Lightning): takes more damage from everything.
-- Effect = lightning damage / max health × SHOCK_SCALE, kept between SHOCK_MIN and SHOCK_MAX
Elements.SHOCK_DURATION = 3
Elements.SHOCK_SCALE = 2
Elements.SHOCK_MIN = 0.05
Elements.SHOCK_MAX = 0.3

-- Rich text of the ailments active on a model, e.g. BURN SHOCK in their colors ("" when none)
function Elements.formatAilments(model: Instance): string
	local parts = {}
	for _, label in ipairs(Elements.AilmentLabels) do
		if model:GetAttribute(label.Attribute) then
			local color = Elements.Colors[label.Element]:ToHex()
			table.insert(parts, string.format('<font color="#%s">%s</font>', color, label.Text))
		end
	end
	return table.concat(parts, " ")
end

return Elements
