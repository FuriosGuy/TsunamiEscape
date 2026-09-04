--!strict

-- Paste this script into the Roblox Studio Command Bar after selecting one or
-- more kart models. It repairs known cross-kart SeatBase references, creates
-- missing rigid-body welds, welds wheel components to their wheel roots,
-- creates missing wheel Motor6Ds, then audits again.

local FIX_AND_AUDIT = true
local CREATE_MISSING_INTERNAL_WELDS = true
local CREATE_MISSING_WHEEL_COMPONENT_WELDS = true
local CREATE_MISSING_WHEEL_MOTORS = true

local Selection = game:GetService("Selection")

type Joint = WeldConstraint | Motor6D

type KartScan = {
	anchor: BasePart,
	parts: { BasePart },
	partSet: { [BasePart]: boolean },
	wheelParts: { BasePart },
	wheelComponentRoots: { [BasePart]: BasePart },
	joints: { Joint },
}

type KartAudit = {
	fixedCount: number,
	createdWeldCount: number,
	createdMotorCount: number,
	brokenCount: number,
	selfWeldCount: number,
	externalCount: number,
	orphanCount: number,
	ignoredWheelOrphans: number,
	missingWheelMotorCount: number,
	duplicateWheelMotorCount: number,
	invalidWheelMotorCount: number,
	missingWheelComponentWeldCount: number,
	internalWeldCount: number,
	wheelMotorCount: number,
	issueCount: number,
}

local function describe(instance: Instance?): string
	return if instance then instance:GetFullName() else "nil"
end

local function getKartRoot(instance: Instance): Model?
	if instance == workspace then
		return nil
	end

	local current: Instance? = if instance:IsA("Model")
		then instance
		else instance:FindFirstAncestorOfClass("Model")

	while current and current ~= workspace do
		local seatBase = current:FindFirstChild("SeatBase", true)
		if seatBase and seatBase:IsA("BasePart") then
			local kartRoot = seatBase:FindFirstAncestorOfClass("Model")
			if kartRoot then
				return kartRoot
			end
		end

		local parent = current.Parent
		if not parent or parent == workspace or not parent:IsA("Model") then
			break
		end
		current = parent
	end

	return nil
end

local function isWheelPart(part: BasePart, root: Model): boolean
	local current = part.Parent
	while current and current ~= root do
		if current.Name == "Wheels" or string.match(current.Name, "^Wheel") then
			return true
		end
		current = current.Parent
	end

	return string.find(string.lower(part.Name), "wheel", 1, true) ~= nil
end

local function collectWheelParts(root: Model): { BasePart }
	local wheelParts: { BasePart } = {}
	local wheelSet: { [BasePart]: boolean } = {}
	local wheelsFolder = root:FindFirstChild("Wheels")

	if wheelsFolder then
		for _, child in ipairs(wheelsFolder:GetChildren()) do
			if child:IsA("BasePart") and not wheelSet[child] then
				wheelSet[child] = true
				table.insert(wheelParts, child)
			end
		end
	end

	if #wheelParts == 0 then
		for _, descendant in ipairs(root:GetDescendants()) do
			if
				descendant:IsA("BasePart")
				and string.find(string.lower(descendant.Name), "wheel", 1, true) ~= nil
				and not wheelSet[descendant]
			then
				wheelSet[descendant] = true
				table.insert(wheelParts, descendant)
			end
		end
	end

	return wheelParts
end

local function scanKart(root: Model): KartScan?
	local anchorInstance = root:FindFirstChild("SeatBase", true)
	if not anchorInstance or not anchorInstance:IsA("BasePart") then
		warn("[KartRigAudit][MISSING_SEAT_BASE] " .. root:GetFullName())
		return nil
	end

	local parts: { BasePart } = {}
	local partSet: { [BasePart]: boolean } = {}
	local joints: { Joint } = {}
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			partSet[descendant] = true
			table.insert(parts, descendant)
		elseif descendant:IsA("WeldConstraint") or descendant:IsA("Motor6D") then
			table.insert(joints, descendant)
		end
	end

	local wheelParts = collectWheelParts(root)
	local wheelComponentRoots: { [BasePart]: BasePart } = {}
	for _, wheelPart in ipairs(wheelParts) do
		for _, descendant in ipairs(wheelPart:GetDescendants()) do
			if descendant:IsA("BasePart") then
				wheelComponentRoots[descendant] = wheelPart
			end
		end
	end

	table.sort(parts, function(left: BasePart, right: BasePart): boolean
		return left:GetFullName() < right:GetFullName()
	end)

	return {
		anchor = anchorInstance,
		parts = parts,
		partSet = partSet,
		wheelParts = wheelParts,
		wheelComponentRoots = wheelComponentRoots,
		joints = joints,
	}
end

local function repairKnownExternalReferences(root: Model, scan: KartScan, audit: KartAudit)
	for _, joint in ipairs(scan.joints) do
		if not joint:IsA("WeldConstraint") or joint.Name ~= "InternalKartWeld" then
			continue
		end

		local part0 = joint.Part0
		local part1 = joint.Part1
		if not part0 or not part1 then
			continue
		end

		local part0Inside = part0:IsDescendantOf(root)
		local part1Inside = part1:IsDescendantOf(root)
		if part0Inside == part1Inside then
			continue
		end

		local insidePart = if part0Inside then part0 else part1
		local outsidePart = if part0Inside then part1 else part0
		if outsidePart.Name ~= "SeatBase" or insidePart == scan.anchor then
			continue
		end

		if part0Inside then
			joint.Part1 = scan.anchor
		else
			joint.Part0 = scan.anchor
		end

		audit.fixedCount += 1
		print(string.format(
			"[KartRigAudit][FIXED] %s now connects to %s",
			joint:GetFullName(),
			scan.anchor:GetFullName()
		))
	end
end

local function createMissingWheelMotors(scan: KartScan, audit: KartAudit)
	if not CREATE_MISSING_WHEEL_MOTORS then
		return
	end

	for _, wheelPart in ipairs(scan.wheelParts) do
		local existingMotors: { Motor6D } = {}
		for _, joint in ipairs(scan.joints) do
			if
				joint:IsA("Motor6D")
				and (joint.Part0 == wheelPart or joint.Part1 == wheelPart)
			then
				table.insert(existingMotors, joint)
			end
		end

		local validMotorCount = 0
		for _, motor in ipairs(existingMotors) do
			if motor.Part0 == scan.anchor then
				validMotorCount += 1
			end
		end

		if validMotorCount > 1 then
			audit.duplicateWheelMotorCount += validMotorCount - 1
			continue
		end

		-- Do not create a duplicate when an incorrectly connected motor exists.
		if #existingMotors > 0 or validMotorCount > 0 then
			continue
		end

		local wheelMotor = Instance.new("Motor6D")
		wheelMotor.Name = wheelPart.Name .. "_Motor"
		wheelMotor.Part0 = scan.anchor
		wheelMotor.Part1 = wheelPart
		wheelMotor.C0 = scan.anchor.CFrame:ToObjectSpace(wheelPart.CFrame)
		wheelMotor.C1 = CFrame.identity
		wheelMotor.Parent = scan.anchor
		audit.createdMotorCount += 1
		print(string.format(
			"[KartRigAudit][CREATED_MOTOR] %s connects to %s",
			wheelMotor:GetFullName(),
			wheelPart:GetFullName()
		))
	end
end

local function buildConnectedParts(root: Model, scan: KartScan): { [BasePart]: boolean }
	local connections: { [BasePart]: { BasePart } } = {}
	for _, part in ipairs(scan.parts) do
		connections[part] = {}
	end

	for _, joint in ipairs(scan.joints) do
		local part0 = joint.Part0
		local part1 = joint.Part1
		if
			part0
			and part1
			and scan.partSet[part0]
			and scan.partSet[part1]
			and part0:IsDescendantOf(root)
			and part1:IsDescendantOf(root)
		then
			table.insert(connections[part0], part1)
			table.insert(connections[part1], part0)
		end
	end

	local visited: { [BasePart]: boolean } = { [scan.anchor] = true }
	local queue: { BasePart } = { scan.anchor }
	local queueIndex = 1
	while queueIndex <= #queue do
		local current = queue[queueIndex]
		queueIndex += 1
		for _, connectedPart in ipairs(connections[current]) do
			if not visited[connectedPart] then
				visited[connectedPart] = true
				table.insert(queue, connectedPart)
			end
		end
	end

	return visited
end

local function buildWheelConnectedParts(scan: KartScan, wheelRoot: BasePart): { [BasePart]: boolean }
	local connections: { [BasePart]: { BasePart } } = {
		[wheelRoot] = {},
	}

	for component, owner in pairs(scan.wheelComponentRoots) do
		if owner == wheelRoot then
			connections[component] = {}
		end
	end

	local function belongsToWheelAssembly(part: BasePart): boolean
		return part == wheelRoot or scan.wheelComponentRoots[part] == wheelRoot
	end

	for _, joint in ipairs(scan.joints) do
		local part0 = joint.Part0
		local part1 = joint.Part1
		if
			part0
			and part1
			and belongsToWheelAssembly(part0)
			and belongsToWheelAssembly(part1)
		then
			table.insert(connections[part0], part1)
			table.insert(connections[part1], part0)
		end
	end

	local visited: { [BasePart]: boolean } = { [wheelRoot] = true }
	local queue: { BasePart } = { wheelRoot }
	local queueIndex = 1
	while queueIndex <= #queue do
		local current = queue[queueIndex]
		queueIndex += 1
		for _, connectedPart in ipairs(connections[current]) do
			if not visited[connectedPart] then
				visited[connectedPart] = true
				table.insert(queue, connectedPart)
			end
		end
	end

	return visited
end

local function hasBlockingExternalReference(root: Model, scan: KartScan, part: BasePart): boolean
	for _, joint in ipairs(scan.joints) do
		if joint.Part0 ~= part and joint.Part1 ~= part then
			continue
		end

		local part0 = joint.Part0
		local part1 = joint.Part1
		if not part0 or not part1 then
			continue
		end

		local part0Inside = part0:IsDescendantOf(root)
		local part1Inside = part1:IsDescendantOf(root)
		if part0Inside == part1Inside then
			continue
		end

		local externalPart = if part0Inside then part1 else part0
		local insidePart = if part0Inside then part0 else part1
		local expectedMainAttachment = joint.Name == "KartMainWeld"
			and insidePart == scan.anchor
			and externalPart.Name == "HumanoidRootPart"
		if not expectedMainAttachment then
			return true
		end
	end

	return false
end

local function createMissingWheelComponentWelds(root: Model, scan: KartScan, audit: KartAudit)
	if not CREATE_MISSING_WHEEL_COMPONENT_WELDS then
		return
	end

	for _, wheelRoot in ipairs(scan.wheelParts) do
		local connectedParts = buildWheelConnectedParts(scan, wheelRoot)
		for _, component in ipairs(scan.parts) do
			if scan.wheelComponentRoots[component] ~= wheelRoot or connectedParts[component] then
				continue
			end
			if hasBlockingExternalReference(root, scan, component) then
				continue
			end

			local internalWeld = Instance.new("WeldConstraint")
			internalWeld.Name = "InternalKartWeld"
			internalWeld.Part0 = wheelRoot
			internalWeld.Part1 = component
			internalWeld.Parent = wheelRoot
			audit.createdWeldCount += 1
			connectedParts[component] = true
			print(string.format(
				"[KartRigAudit][CREATED_WHEEL_WELD] %s now connects to %s",
				component:GetFullName(),
				wheelRoot:GetFullName()
			))
		end
	end
end

local function createMissingInternalWelds(root: Model, scan: KartScan, audit: KartAudit)
	if not CREATE_MISSING_INTERNAL_WELDS then
		return
	end

	local connectedParts = buildConnectedParts(root, scan)
	for _, part in ipairs(scan.parts) do
		if connectedParts[part] or part == scan.anchor or isWheelPart(part, root) then
			continue
		end
		if hasBlockingExternalReference(root, scan, part) then
			continue
		end

		local internalWeld = Instance.new("WeldConstraint")
		internalWeld.Name = "InternalKartWeld"
		internalWeld.Part0 = scan.anchor
		internalWeld.Part1 = part
		internalWeld.Parent = scan.anchor
		audit.createdWeldCount += 1
		connectedParts[part] = true
		print(string.format(
			"[KartRigAudit][CREATED_WELD] %s now connects to %s",
			part:GetFullName(),
			scan.anchor:GetFullName()
		))
	end
end

local function isExpectedExternalReference(root: Model, scan: KartScan, joint: Joint): boolean
	local part0 = joint.Part0
	local part1 = joint.Part1
	if not part0 or not part1 then
		return false
	end

	local part0Inside = part0:IsDescendantOf(root)
	local part1Inside = part1:IsDescendantOf(root)
	if part0Inside == part1Inside then
		return false
	end

	local externalPart = if part0Inside then part1 else part0
	local insidePart = if part0Inside then part0 else part1
	return joint.Name == "KartMainWeld"
		and insidePart == scan.anchor
		and externalPart.Name == "HumanoidRootPart"
end

local function auditKart(root: Model, scan: KartScan, audit: KartAudit)
	local function report(kind: string, message: string)
		audit.issueCount += 1
		warn(string.format("[KartRigAudit][%s] %s", kind, message))
	end

	for _, joint in ipairs(scan.joints) do
		local part0 = joint.Part0
		local part1 = joint.Part1
		if not part0 or not part1 then
			audit.brokenCount += 1
			report(
				"BROKEN",
				string.format(
					"%s missing Part0 or Part1 | Part0=%s | Part1=%s",
					joint:GetFullName(),
					describe(part0),
					describe(part1)
				)
			)
			continue
		end

		if part0 == part1 then
			audit.selfWeldCount += 1
			report("SELF_WELD", joint:GetFullName() .. " connects a part to itself")
			continue
		end

		local part0Inside = part0:IsDescendantOf(root)
		local part1Inside = part1:IsDescendantOf(root)
		if not part0Inside or not part1Inside then
			if not isExpectedExternalReference(root, scan, joint) then
				audit.externalCount += 1
				local externalPart = if not part0Inside then part0 else part1
				report(
					"EXTERNAL_REFERENCE",
					string.format(
						"%s references outside kart: %s",
						joint:GetFullName(),
						describe(externalPart)
					)
				)
			end
			continue
		end

		if joint:IsA("WeldConstraint") and joint.Name == "InternalKartWeld" then
			audit.internalWeldCount += 1
		elseif joint:IsA("Motor6D") and string.match(joint.Name, "_Motor$") then
			audit.wheelMotorCount += 1
		end
	end

	local connectedParts = buildConnectedParts(root, scan)
	for _, part in ipairs(scan.parts) do
		if connectedParts[part] then
			continue
		end

		if isWheelPart(part, root) then
			audit.ignoredWheelOrphans += 1
			continue
		end

		audit.orphanCount += 1
		report(
			"ORPHAN_PART",
			string.format("%s is not connected to %s", part:GetFullName(), scan.anchor:GetFullName())
		)
	end

	for _, wheelRoot in ipairs(scan.wheelParts) do
		local connectedWheelParts = buildWheelConnectedParts(scan, wheelRoot)
		for _, component in ipairs(scan.parts) do
			if
				scan.wheelComponentRoots[component] == wheelRoot
				and not connectedWheelParts[component]
			then
				audit.missingWheelComponentWeldCount += 1
				report(
					"MISSING_WHEEL_COMPONENT_WELD",
					string.format(
						"%s is not connected to wheel root %s",
						component:GetFullName(),
						wheelRoot:GetFullName()
					)
				)
			end
		end
	end

	for _, wheelPart in ipairs(scan.wheelParts) do
		local validMotorCount = 0
		local anyMotorCount = 0
		for _, joint in ipairs(scan.joints) do
			if
				joint:IsA("Motor6D")
				and (joint.Part0 == wheelPart or joint.Part1 == wheelPart)
			then
				anyMotorCount += 1
				if joint.Part0 == scan.anchor and joint.Part1 == wheelPart then
					validMotorCount += 1
				end
			end
		end

		if validMotorCount == 0 then
			audit.missingWheelMotorCount += 1
			report("MISSING_WHEEL_MOTOR", wheelPart:GetFullName())
		elseif validMotorCount > 1 then
			audit.duplicateWheelMotorCount += validMotorCount - 1
			report(
				"DUPLICATE_WHEEL_MOTORS",
				string.format("%s has %d valid wheel motors", wheelPart:GetFullName(), validMotorCount)
			)
		end

		if anyMotorCount > validMotorCount then
			audit.invalidWheelMotorCount += anyMotorCount - validMotorCount
			report(
				"INVALID_WHEEL_MOTOR",
				string.format("%s has a Motor6D not connected from SeatBase", wheelPart:GetFullName())
			)
		end
	end
end

local function run()
	local roots: { [Model]: boolean } = {}
	for _, selectedInstance in ipairs(Selection:Get()) do
		local kartRoot = getKartRoot(selectedInstance)
		if kartRoot then
			roots[kartRoot] = true
		end
	end

	if next(roots) == nil then
		warn("[KartRigAudit] Select one or more kart models containing SeatBase.")
		return
	end

	local rootList: { Model } = {}
	for root in pairs(roots) do
		table.insert(rootList, root)
	end
	table.sort(rootList, function(left: Model, right: Model): boolean
		return left:GetFullName() < right:GetFullName()
	end)

	for _, root in ipairs(rootList) do
		local scan = scanKart(root)
		if not scan then
			continue
		end

		local audit: KartAudit = {
			fixedCount = 0,
			createdWeldCount = 0,
			createdMotorCount = 0,
			brokenCount = 0,
			selfWeldCount = 0,
			externalCount = 0,
			orphanCount = 0,
			ignoredWheelOrphans = 0,
			missingWheelMotorCount = 0,
			duplicateWheelMotorCount = 0,
			invalidWheelMotorCount = 0,
			missingWheelComponentWeldCount = 0,
			internalWeldCount = 0,
			wheelMotorCount = 0,
			issueCount = 0,
		}

		if FIX_AND_AUDIT then
			repairKnownExternalReferences(root, scan, audit)
			createMissingWheelMotors(scan, audit)
			local refreshedScan = scanKart(root)
			if refreshedScan then
				scan = refreshedScan
			end
			createMissingWheelComponentWelds(root, scan, audit)
			refreshedScan = scanKart(root)
			if refreshedScan then
				scan = refreshedScan
			end
			createMissingInternalWelds(root, scan, audit)
		end

		local finalScan = scanKart(root)
		if not finalScan then
			continue
		end
		auditKart(root, finalScan, audit)

		local partCount = #finalScan.parts
		print(string.format(
			"[KartRigAudit][SUMMARY] %s | parts=%d | constraints=%d | internalWelds=%d | wheelMotors=%d | fixed=%d | createdWelds=%d | createdMotors=%d | external=%d | orphans=%d | ignoredWheelOrphans=%d | missingWheelComponentWelds=%d | missingWheelMotors=%d | duplicateWheelMotors=%d | invalidWheelMotors=%d | issues=%d",
			root:GetFullName(),
			partCount,
			#finalScan.joints,
			audit.internalWeldCount,
			audit.wheelMotorCount,
			audit.fixedCount,
			audit.createdWeldCount,
			audit.createdMotorCount,
			audit.externalCount,
			audit.orphanCount,
			audit.ignoredWheelOrphans,
			audit.missingWheelComponentWeldCount,
			audit.missingWheelMotorCount,
			audit.duplicateWheelMotorCount,
			audit.invalidWheelMotorCount,
			audit.issueCount
		))

		if audit.issueCount == 0 then
			print("[KartRigAudit][OK] No remaining issues.")
		else
			warn(string.format("[KartRigAudit] Remaining issues: %d", audit.issueCount))
		end
	end
end

run()
