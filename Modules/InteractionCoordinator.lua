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
        Safety:DebugRevalidationFailed(
            "The gossip interaction changed before it could finish."
        )
        return nil
    end

    return RunGossipShow()
end

RunGossipShow = function(debugInteraction)
    local context = Context:Build("GOSSIP_SHOW")
    if debugInteraction and Context.DebugInteraction then
        Context:DebugInteraction("GOSSIP_SHOW", context)
    end

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
    return RunGossipShow(true)
end

AQG:RegisterEvent("GOSSIP_SHOW", function()
    Coordinator:HandleGossipShow()
end)
