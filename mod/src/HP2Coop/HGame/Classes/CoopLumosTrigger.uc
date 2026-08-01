//================================================================================
// CoopLumosTrigger - injected replacement of LumosTrigger.
// When a lumos secret trigger fires its Event on one instance, broadcast it so
// the peer fires the same-named trigger's Event too - even if the peer's harry
// is standing outside lumos range (proximity check is bypassed deliberately).
// bFirstEventSent on the peer side prevents double-firing.
//================================================================================

class CoopLumosTrigger injects LumosTrigger;

function TriggerEvent(name EventName, Actor Other, Pawn EventInstigator)
{
    local CoopManager mgr;

    Super.TriggerEvent(EventName, Other, EventInstigator);

    foreach AllActors(class'CoopManager', mgr)
        break;
    if (mgr != None && !mgr.bApplyingRemote)
        mgr.BroadcastLumosTrig(string(Name));
}
