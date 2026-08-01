//================================================================================
// CoopHProp - injected replacement of HProp.
// Broadcasts every prop pickup (beans, wizard cards, chocolate frogs, potion
// ingredients...) collected by the LOCAL harry. The peer runs the same native
// DoPickupProp() on its own copy of the prop, so it disappears and is credited
// on both sides. Loop safety: bApplyingRemote is held while the peer applies
// a synced pickup, and CanPickupNow only accepts the real harry anyway.
//================================================================================

class CoopHProp injects HProp;

function DoPickupProp()
{
    local CoopManager mgr;

    Super.DoPickupProp();

    foreach AllActors(class'CoopManager', mgr)
        break;
    if (mgr != None && !mgr.bApplyingRemote)
        mgr.BroadcastPickup(self);
}
