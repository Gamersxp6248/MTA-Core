local NET_FAR_COMBINE_SPAWN_EFFECT = "FAR_COMBINE_SPAWN_EFFECT"

if CLIENT then
	local CANNON_AMT = 50
	local PARTICLES_AMT = 25
	local function do_spawn_effect(pos)
		local spawn_pos_ent = ents.CreateClientProp("models/props_junk/PopCan01a.mdl", RENDERGROUP_OPAQUE)
		spawn_pos_ent:Spawn()
		spawn_pos_ent:SetPos(pos)
		spawn_pos_ent:SetNoDraw(true)
		SafeRemoveEntityDelayed(spawn_pos_ent, 10)

		local beam_point_origin_1 = ClientsideModel("models/props_junk/PopCan01a.mdl", RENDERGROUP_OPAQUE)
		beam_point_origin_1:SetNoDraw(true)
		SafeRemoveEntityDelayed(beam_point_origin_1, 10)

		local beam_point_origin_2 = ClientsideModel("models/props_junk/PopCan01a.mdl", RENDERGROUP_OPAQUE)
		beam_point_origin_2:SetNoDraw(true)
		SafeRemoveEntityDelayed(beam_point_origin_2, 10)

		for i=1, CANNON_AMT do
			local ang = ((i * 36) * math.pi) / 180
			local turn = Vector(math.sin(ang), math.cos(ang), 0) * 2
			timer.Simple(i / CANNON_AMT, function()
				if not IsValid(spawn_pos_ent) or not IsValid(beam_point_origin_1) or not IsValid(beam_point_origin_2) then return end
				beam_point_origin_1:SetPos(pos + Vector(0, 0,1000) + turn)
				beam_point_origin_2:SetPos(pos + Vector(0, 0,1000 * (CANNON_AMT - i) / CANNON_AMT) + turn)
				spawn_pos_ent:CreateParticleEffect("Weapon_Combine_Ion_Cannon", {
					{ entity = beam_point_origin_1, attachtype = PATTACH_ABSORIGIN_FOLLOW },
					{ entity = beam_point_origin_2, attachtype = PATTACH_ABSORIGIN_FOLLOW },
				})
			end)
		end
	end

	net.Receive(NET_FAR_COMBINE_SPAWN_EFFECT, function()
		local pos = net.ReadVector()
		do_spawn_effect(pos)
	end)

	return function() end, function() end
end

util.AddNetworkString(NET_FAR_COMBINE_SPAWN_EFFECT)

local MAX_SPAWN_DISTANCE = 1024

local IsValid = _G.IsValid

local tag = "far_combine"
local combines = {}
local lastonesec = 0

local function think()
	local curtime = CurTime()
	local onesec

	if curtime - lastonesec > 1 then
		lastonesec = curtime
		onesec = true
	end

	for npc, v in next, combines do
		if npc:IsValid() then
			v(npc, curtime, onesec)
		else
			combines[npc] = nil
		end
	end

	if not next(combines) then
		hook.Remove("Think", tag)
	end
end

local function try_get_combine(ply)
	local min_dist, combine = math.huge
	local pos = ply:GetPos()

	for c, _ in next, combines do
		if IsValid(c) and c:GetEnemy() == ply then
			local dist = pos:DistToSqr(c:GetPos())

			if dist < min_dist then
				min_dist = dist
				combine = c
			end
		end
	end

	return combine
end

local function is_combine_soldier(ent)
	return ent:GetClass() == "npc_combine_s" or ent:GetClass() == "npc_metropolice"
end

hook.Add("DoPlayerDeath", tag, function(ply, _, _)
	local combine = try_get_combine(ply)
	if not combine then return end
	if not is_combine_soldier(combine) then return end
	combine:EmitSound("npc/metropolice/vo/chuckle.wav")
end)

hook.Add("OnNPCKilled", tag, function(npc, ply, _)
	if not combines[npc] then return end
	local combine = try_get_combine(ply)
	if not combine then return end
	if not is_combine_soldier(combine) then return end
	combine:EmitSound("npc/metropolice/vo/lookout.wav")
end)

local function keep_sane(combine, callback)
	if not next(combines) then
		hook.Add("Think", tag, think)
	end

	combines[combine] = callback or nil
end

local function is_far_behind(ply, pos, fard)
	fard = (fard or 888) ^ 2
	local pl_pos = ply:EyePos()
	if pl_pos:DistToSqr(pos) < fard then
		return false
	end
	local aim = ply:GetAimVector()
	pl_pos:Sub(pos)
	local aim2 = pl_pos
	aim2:Normalize()
	local dot = aim:Dot(aim2)

	return dot > 0
end

local soldier_weapons = { "weapon_smg1", "weapon_ar2", "weapon_shotgun" }
local combine_types = {
	function()
		local npc = ents.Create("npc_metropolice")
		npc:SetKeyValue("additionalequipment", math.random() > 0.5 and "weapon_pistol" or "weapon_stunstick")
		npc:SetKeyValue("manhacks", tostring(math.random(0, 2)))
		return npc
	end,
	function()
		local npc = ents.Create("npc_combine_s")
		npc:SetKeyValue("additionalequipment", soldier_weapons[math.random(#soldier_weapons)])
		return npc
	end,
	function()
		local npc = ents.Create("npc_combine_s")
		npc:SetKeyValue("additionalequipment", "weapon_ar2")
		npc:SetModel("models/combine_super_soldier.mdl")
		return npc
	end
}

local function create_combine(pos)
	local spawn_function = combine_types[math.random(#combine_types)]
	local npc = spawn_function()
	npc.ms_notouch = true

	npc:SetPos(pos)
	npc:SetKeyValue("NumGrenades", "10")
	npc:SetKeyValue("tacticalvariant", "pressure")
	npc:SetKeyValue("spawnflags", tostring(bit.bor(SF_NPC_LONG_RANGE, SF_NPC_NO_WEAPON_DROP, SF_NPC_NO_PLAYER_PUSHAWAY)))
	npc:SetKeyValue("squadname", "combine")

	npc:AddRelationship("player D_LI 99")

	npc:Spawn()
	npc:Activate()
	npc:SetCurrentWeaponProficiency(WEAPON_PROFICIENCY_PERFECT)
	npc:Input("StartPatrolling")
	npc:SetHealth(100)

	if not npc:IsFlagSet(FL_FLY) then
		npc:DropToFloor()
	end

	return npc
end

local function ID(a)
	return ("%x"):format(util.CRC(tostring(a)))
end

local NODE_TYPE_GROUND = NODE_TYPE_GROUND

local function get_nearest_node(ply, maxd)
	if not IsValid(ply) then return end

	local pos = ply:GetPos()
	maxd = maxd or 2 ^ 17
	local pvsonly = false
	local nodes = game.GetMapNodegraph():GetNodes()
	local d, node = maxd ^ 2

	for k, candidate in next, nodes do
		if candidate.type == NODE_TYPE_GROUND then
			local curd = candidate.pos:DistToSqr(pos)
			if curd < d and ply:VisibleVec(candidate.pos) then
				d = curd
				node = candidate
			end
		end
	end

	if not node then
		pvsonly = true

		for k, candidate in next, nodes do
			if candidate.type == NODE_TYPE_GROUND then
				local curd = candidate.pos:DistToSqr(pos)

				if curd < d and ply:TestPVS(candidate.pos) then
					d = curd
					node = candidate
				end
			end
		end
	end

	if not node then return end
	return node, pvsonly
end

local function find_invisible_near(ply, node, collected)
	collected = collected or {}
	if collected[node] then
		return
	end
	local nopvs = not ply:TestPVS(node.pos + Vector(0, 0, 4))
	local far = is_far_behind(ply, node.pos)

	if nopvs or far then
		return node
	end

	collected[node] = true

	for k, node_candidate in next, node.neighbor or {} do
		local ret = find_invisible_near(ply, node_candidate, collected)
		if ret then
			return ret
		end
	end
end

local function invisible_near(ply, node, collected)
	collected = collected or {}
	local stack = { node }

	if not node.pos then
		stack = node
		assert(table.IsSequential(stack))
	end
	-- end of iterations
	-- could probably just not push these altogether

	return function()
		for i = 1, 1500 * 10 do
			local node = stack[1]
			table.remove(stack, 1)
			if not node then
				return
			end
			if not collected[node] then
				collected[node] = true
				local nopvs = not ply:TestPVS(node.pos + Vector(0, 0, 4))
				local far = is_far_behind(ply, node.pos)
				if nopvs or far then
					return node
				end

				for k, node_candidate in next, node.neighbor do
					if not collected[node_candidate] then
						stack[#stack + 1] = node_candidate
					end
				end
			end
		end

		error("expensive")
	end
end

local output = {}

local t = {
	output = output,
	mask = MASK_NPCSOLID,
	mins = Vector(-17, -17, 0),
	maxs = Vector(17, 17, 72)
}

local function would_combine_stuck(pos)
	if not util.IsInWorld(pos) then return true end

	t.start = pos
	t.endpos = pos

	return util.TraceHull(t).StartSolid
end

local vecup_offset = Vector(0, 0, 33)

local function find_cadidate_node(ply, n, t)
	local node, pos

	for node_candidate in invisible_near(ply, n, t) do
		if not would_combine_stuck(node_candidate.pos) then
			-- find from between nodes
			node = node_candidate
			pos = node_candidate.pos
			break
		else
			local half = node_candidate.pos * 0.5

			for k, v in next, node_candidate.neighbor do
				local a = v.pos
				local b = v.pos * 0.5 + half

				if not would_combine_stuck(b) then
					node = node_candidate
					pos = b
					break
				end

				b:Add(vecup_offset)

				if not would_combine_stuck(b) then
					node = node_candidate
					pos = b
					break
				end
			end

			if node then
				break
			end
		end
	end

	return node, pos
end

local function get_closest_player(combine, players)
	local min_dist, ret = math.huge
	for _,ply in ipairs(players) do
		if IsValid(ply) then
			local dist = ply:GetPos():Distance(combine:GetPos())
			if dist < min_dist then
				min_dist = dist
				ret = ply
			end
		end
	end

	return ret
end

local blocking_classes = {
	prop_door_rotating = true,
	func_breakable = true,
	func_movelinear = true,
}
local function is_blocking_entity(ent)
	if not IsValid(ent) then return false end

	local class = ent:GetClass()
	if class:match("func_door.*") then return true end
	if blocking_classes[class] then return true end

	-- blow up player stuff
	if ent.CPPIGetOwner and IsValid(ent:CPPIGetOwner()) then
		return true
	end

	return false
end

local function handle_entity_block(combine)
	-- dont bother if that function doesnt exist
	if not FindMetaTable("Entity").PropDoorRotatingExplode then return end

	local aim_vector = combine:GetAimVector()
	local pos = combine:GetPos()

	local time = 0
	local last_stuck_state = combine.LastStuckState
	if last_stuck_state and last_stuck_state.NPCPos:Distance(pos) <= 100 then
		if last_stuck_state.Time > 6 then
			for _, ent in pairs(ents.FindInSphere(pos, 150)) do
				if is_blocking_entity(ent) then
					ent:PropDoorRotatingExplode(aim_vector * 1000, 30, false, false)
				end
			end
		else
			time = last_stuck_state.Time + 1
		end
	end

	combine.LastStuckState = {
		NPCPos = pos,
		Time = time
	}
end

local function setup_combine(combine, target, players)
	if not IsValid(target) then return end

	SafeRemoveEntityDelayed(combine, 120)

	combine:SetLagCompensated(true)
	combine:AddFlags(FL_NPC + FL_OBJECT)
	combine:SetCollisionGroup(COLLISION_GROUP_PASSABLE_DOOR)
	combine:SetEnemy(target, true)
	combine:AddEntityRelationship(target, D_FR, 0)
	combine:AddEntityRelationship(target, D_HT, 99)
	combine:UpdateEnemyMemory(target, target:GetPos())
	combine.Enemy = target

	timer.Simple(math.random() * 1.5, function()
		if not combine:IsValid() then return end
		if not is_combine_soldier(combine) then return end
		combine:EmitSound("npc/metropolice/vo/sweepingforsuspect.wav")
	end)

	-- teleport NPC if too far
	local teleports = 0
	local last_teleport = 0
	local function check_teleport(combine, target, onesec, curtime)
		if curtime - last_teleport < 5 then return end
		local try_teleport = (curtime % 3 < 1) -- once every N seconds when N>1

		if try_teleport and target:Alive() and teleports < 3 and not target:TestPVS(combine:GetPos()) and not combine:IsUnreachable(target) then
			last_teleport = curtime
			teleports = teleports + 1
			local oldpos = combine:GetPos()
			local n_new = get_nearest_node(target, MAX_SPAWN_DISTANCE)

			if n_new then
				n = n_new
				local nnode, newpos = find_cadidate_node(target, n)
				if newpos then
					node, pos = nnode, newpos
					combine:SetPos(pos)
					combine:SetEnemy(target, true)
					combine:UpdateEnemyMemory(target, target:GetPos())
				end
			end
		end
	end

	local creation_time = combine:GetCreationTime()
	local first = true
	-- for sound emissions
	local converged, sighted

	-- "Think" hook
	local next_update = CurTime() + 1
	keep_sane(combine, function(_, curtime, onesec)
		if not IsValid(combine) then return end

		local old_target = target
		if CurTime() > next_update then
			local new_ply = get_closest_player(combine, players)

			-- if the target is in a vehicle, try to target the vehicle
			combine.TargetIsVehicle = false
			if IsValid(new_ply) and new_ply:InVehicle() then
				new_ply = new_ply:GetVehicle()
				combine.TargetIsVehicle = true
			end

			if IsValid(target) and target ~= new_ply and not table.HasValue(players, target) then
				combine:AddEntityRelationship(target, D_LI, 99)
			end

			handle_entity_block(combine)
			target = new_ply
			next_update = CurTime() + 1
		end

		if not IsValid(target) then
			if not combine.TargetIsVehicle then combine:Remove() end
			return
		end

		combine:AddEntityRelationship(target, D_HT, 99)
		combine:SetEnemy(target, old_target ~= target)

		local age = curtime - creation_time
		local enemy = combine:GetEnemy()
		if enemy ~= target then
			if not IsValid(enemy) then enemy = nil end

			-- teleportation possibility in case of no enemy
			-- fix hating other things
			if enemy then
				combine:AddEntityRelationship(enemy, D_LI, 99)
				combine:MarkEnemyAsEluded()
			end

			-- let's make you the enemy of the player again
			--if target:Alive() then
			--	combine:SetEnemy(target)
			--end
		end

		if not onesec then return end

		-- first contact
		if is_combine_soldier(combine) and not sighted and combine:VisibleVec(target:EyePos()) then
			sighted = true

			if math.random() < 1 then
				combine:EmitSound("npc/metropolice/vo/hesupthere.wav")
			end
		end

		-- getting closer
		if is_combine_soldier(combine) and not converged and target:TestPVS(combine:GetPos()) then
			converged = true

			if math.random() > 0.7 then
				timer.Simple(2, function()
					if not IsValid(combine) then return end
					combine:EmitSound("npc/metropolice/vo/converging.wav")
				end)
			end
		end

		-- tell enemy where you exist
		if target:Alive() then
			combine:UpdateEnemyMemory(target, target:GetPos())
		end

		if age > 10 then
			check_teleport(combine, target, onesec, curtime)
		end

		-- purge ancient NPCs
		if age > 60 and not target:TestPVS(combine:GetPos()) then
			combine:Remove()
		end
	end)
end

local function find_node(target)
	local nearest_node = get_nearest_node(target, MAX_SPAWN_DISTANCE)
	if not nearest_node then return false, "could not get nearest node" end

	local node, pos = find_cadidate_node(target, nearest_node)
	if not node then return false, "could not find suitable node" end

	return true, node.pos
end

local function far_combine(target, players, callback, pos)
	if not IsValid(target) then return false, "invalid target" end
	if #players == 0 then return false, "no players to use" end

	if not isvector(pos) then
		local succ, ret = find_node(target)
		if not succ then return false, ret end
		pos = ret
	end

	net.Start(NET_FAR_COMBINE_SPAWN_EFFECT, true)
	net.WriteVector(pos)
	net.Broadcast()

	timer.Simple(1, function()
		local combine = create_combine(pos)
		setup_combine(combine, target, players)
		combine:EmitSound("ambient/machines/teleport1.wav", 40)
		callback(combine)
	end)

	return true
end

return far_combine, setup_combine