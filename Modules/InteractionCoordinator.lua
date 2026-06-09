local _, AQG = ...

AQG.InteractionCoordinator = AQG.InteractionCoordinator or {}
local Coordinator = AQG.InteractionCoordinator
local Context = AQG.InteractionContext
local Quest = AQG.Quest
local Gossip = AQG.Gossip
local Safety = AQG.Safety

local RunGossipShow

local function QuestStopsGossip(result)
    return result and (result.pending or result.selected or result.executed)
end

local function SameInteraction(expectedContext)
    local expectedNPC = expectedContext and expectedContext.npc
    local expectedGUID = expectedNPC and expectedNPC.guid

    if not expectedGUID then
        return false
    end

    local currentNPC = Safety:BuildNPCContext("npc")
    return currentNPC.safe and currentNPC.guid == expectedGUID
end

local function RetryGossipShow(expectedContext)
    if not SameInteraction(expectedContext) then
        Safety:DebugRevalidationFailed("gossip retry interaction changed")
        return nil
    end

    return RunGossipShow()
end

RunGossipShow = function()
    local context = Context:Build("GOSSIP_SHOW")
    local questResult = Quest:HandleGossipShow(context, function()
        RetryGossipShow(context)
    end)

    if QuestStopsGossip(questResult) then
        return {
            quest = questResult,
            gossip = nil,
        }
    end

    return {
        quest = questResult,
        gossip = Gossip:HandleGossipShow(context),
    }
end

function Coordinator:HandleGossipShow()
    return RunGossipShow()
end

AQG:RegisterEvent("GOSSIP_SHOW", function()
    Coordinator:HandleGossipShow()
end)
