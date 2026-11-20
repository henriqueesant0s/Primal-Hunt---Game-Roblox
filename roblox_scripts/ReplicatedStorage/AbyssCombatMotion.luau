--!strict
-- Curvas de pose do arquivo editável AbyssArtKit.blend.
local Motion = {}

type Curve = {{number}}
local faunaCurves: {[string]: Curve} = {
	Pounce = {{0, 0, 0, 0}, {0.65, -25, -12, 15}, {1, 27, 14, -21}, {1.36, -9, 4, 12}, {1.92, 0, 0, 0}},
	Spit = {{0, 0, 0, 0}, {0.68, -38, 7, 12}, {1, 31, -10, -17}, {1.36, 1, 6, 7}, {1.78, 0, 0, 0}},
	Stomp = {{0, 0, 0, 0}, {0.64, -20, -20, 20}, {1, 26, 23, -20}, {1.32, -11, 9, 8}, {1.88, 0, 0, 0}},
	Scythe = {{0, 0, 0, 0}, {0.74, -25, 18, 24}, {1, 30, -22, -15}, {1.34, 5, -7, 12}, {1.82, 0, 0, 0}},
}
local monsterCurves: {[string]: Curve} = {
	ClawSlash = {{0, 0, 0, 0}, {0.6, -15, -22, 12}, {1, 21, 27, -7}, {2.4, 0, 0, 0}},
	LeapSmash = {{0, 0, 0, 0}, {0.72, -22, -31, 15}, {1, 11, 14, 11}, {1.85, 0, 0, 0}},
	FeralCharge = {{0, 0, 0, 0}, {0.65, 18, -21, 9}, {1, -17, 22, -14}, {2.2, 0, 0, 0}},
	AcidBreath = {{0, 0, 0, 0}, {0.69, -33, -19, 22}, {1, 21, 18, -9}, {2.3, 0, 0, 0}},
}

local attackProfiles: {[string]: {string | number}} = {
	RedGoliath={"Pounce",0.48},
	ObsidianCragback={"Stomp",0.67},
	HornedCeratopsBull={"Stomp",0.54},
	BiolumMantisStalker={"Scythe",0.4},
	AcidSpitterDrake={"Spit",0.46},
	SporeCrawler={"Stomp",0.57},
	SwampStalkerRaptor={"Pounce",0.36},
}
Motion.monsterLead = {ClawSlash=.13, LeapSmash=.17, FeralCharge=.19, AcidBreath=.25} :: {[string]: number}

function Motion.windup(species: string): number
	local profile = attackProfiles[species]
	return if profile then profile[2] :: number else .45
end

local function sample(curve: Curve, phase: number): (number,number,number)
	for i=2,#curve do
		local a,b=curve[i-1],curve[i]
		if phase<=b[1] then
			local t=math.clamp((phase-a[1])/(b[1]-a[1]),0,1)
			t=t*t*(3-2*t)
			return a[2]+(b[2]-a[2])*t,a[3]+(b[3]-a[3])*t,a[4]+(b[4]-a[4])*t
		end
	end
	return 0,0,0
end

function Motion.fauna(species:string,phase:number): (number,number,number)
	local profile=attackProfiles[species]
	local key=if profile then profile[1] :: string else "Pounce"
	return sample(faunaCurves[key],phase)
end

function Motion.monster(action:string,phase:number): (number,number,number)
	local curve=monsterCurves[action]
	if curve then return sample(curve,phase) end
	return 0,0,0
end

return table.freeze(Motion)