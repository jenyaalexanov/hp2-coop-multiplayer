//================================================================================
// CoopSpell - injected replacement of baseSpell.
// Broadcasts every spell projectile fired by the LOCAL harry so the peer can
// spawn the same projectile from its puppet. The replicated projectile then
// interacts with the peer's world on its own (opens chests, hits triggers,
// damages enemies) - spell effects sync naturally through the game code.
// Loop safety: peer-spawned projectiles have the puppet as caster (never the
// local harry), and bApplyingRemote is held while they are created.
//================================================================================

class CoopSpell injects baseSpell;

function InitSpell(Actor CastedBy, Actor CastedAt, optional Vector CastedAtOffset, optional float CastedChargeAmount, optional baseWand CastedFromWand)
{
    local CoopManager mgr;

    Super.InitSpell(CastedBy, CastedAt, CastedAtOffset, CastedChargeAmount, CastedFromWand);

    if (CastedBy != Level.PlayerHarryActor)
        return;
    foreach AllActors(class'CoopManager', mgr)
        break;
    if (mgr != None && !mgr.bApplyingRemote)
        mgr.BroadcastSpell(self);
}
