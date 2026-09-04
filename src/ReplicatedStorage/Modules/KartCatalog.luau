--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KartCatalog = {}

local function getKartModelsFolder(): Instance?
	return ReplicatedStorage:FindFirstChild("KartModels")
end

local function findModelInFolder(folder: Instance?, kartName: string): Model?
	if not folder then
		return nil
	end

	local directMatch = folder:FindFirstChild(kartName)
	if directMatch and directMatch:IsA("Model") then
		return directMatch
	end

	return nil
end

function KartCatalog.FindModel(kartName: string, sourceFolderName: string?, sourceSubfolderName: string?): Model?
	local kartModelsFolder = getKartModelsFolder()
	if not kartModelsFolder then
		return nil
	end

	local sourceFolder = kartModelsFolder:FindFirstChild(sourceFolderName or "Gamepasses")
	if sourceSubfolderName and sourceFolder then
		sourceFolder = sourceFolder:FindFirstChild(sourceSubfolderName)
	end

	return findModelInFolder(sourceFolder, kartName)
end

function KartCatalog.FindSpecialsFolder(): Instance?
	local kartModelsFolder = getKartModelsFolder()
	return kartModelsFolder and kartModelsFolder:FindFirstChild("Specials")
end

function KartCatalog.FindEventModel(eventName: string, kartName: string): Model?
	local specialsFolder = KartCatalog.FindSpecialsFolder()
	local eventFolder = specialsFolder and specialsFolder:FindFirstChild(eventName)
	return findModelInFolder(eventFolder, kartName)
end

function KartCatalog.FindSpecialModel(kartName: string): Model?
	local specialsFolder = KartCatalog.FindSpecialsFolder()
	local directMatch = findModelInFolder(specialsFolder, kartName)
	if directMatch then
		return directMatch
	end

	if specialsFolder then
		for _, child in ipairs(specialsFolder:GetChildren()) do
			local nestedMatch = findModelInFolder(child, kartName)
			if nestedMatch then
				return nestedMatch
			end
		end
	end

	return nil
end

return KartCatalog
