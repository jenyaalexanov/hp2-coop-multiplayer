//================================================================================
// CoopPuppet - ghost remote Harry.
// - Z_CORRECT: bare Pawn draws skharry higher than PlayerPawn at the same Loc
// - Side offset only once at first spawn (never stick/follow local player)
// - Collision forced off (Pawn.PostBeginPlay can re-enable it)
//================================================================================

class CoopPuppet extends Pawn;

const SIDE_OFFSET = 80.0;
const Z_CORRECT = 42.0;

var vector TargetLoc;
var vector TargetVel;
var rotator TargetRot;
var name TargetAnim;
var float TargetAnimRate;
var name TargetChanAnim;
var float TargetChanRate;
var bool bTargetChanLoop;
var string PlayerName;
var float LastPacketAge;
var AnimChannel SpineChan;
var bool bDidFirstPlace;

event PostBeginPlay()
{
    Super.PostBeginPlay();
    DisableCollision();
    SpineChan = AnimChannel(CreateAnimChannel(class'AnimChannel', AT_Replace, 'bip01 Spine1'));
    if (SpineChan != None)
        SpineChan.SetOwner(Self);
}

function DisableCollision()
{
    SetCollision(False, False, False);
    bProjTarget = False;
}

function vector PeerToLocal(vector peerMid)
{
    local vector v;
    v = peerMid;
    v.Z = peerMid.Z - Z_CORRECT;
    return v;
}

function SetTarget(vector L, vector V, rotator R, name Anim, float AnimRate,
                   name ChanAnim, float ChanRate, bool bChanLoop, string Name)
{
    // Always real peer pose (with height fix). No sticky side-follow.
    TargetLoc = PeerToLocal(L);
    TargetVel = V;
    TargetRot = R;
    TargetAnim = Anim;
    TargetAnimRate = AnimRate;
    TargetChanAnim = ChanAnim;
    TargetChanRate = ChanRate;
    bTargetChanLoop = bChanLoop;
    PlayerName = Name;
    LastPacketAge = 0.0;
}

// Trace world geometry under XY; returns feet-height Location (matches Z_CORRECT space).
function vector SnapFeetToFloor(vector at)
{
    local vector HitLoc, HitNorm, start, end;
    local Actor HitAct;

    start = at;
    start.Z = at.Z + 250.0;
    end = at;
    end.Z = at.Z - 1000.0;

    HitAct = Trace(HitLoc, HitNorm, end, start, false);
    if (HitAct != None)
        return HitLoc; // BSP/actor floor surface == our feet Location

    // fallback: same correction as PeerToLocal
    at.Z = at.Z - Z_CORRECT;
    return at;
}

// One-shot: beside local player, then snap to real floor under that spot.
function PlaceFirstTime(vector remoteLoc, rotator remoteRot, vector localLoc, rotator localRot)
{
    local vector flat;
    local vector dir;
    local vector p;
    local int attempt;
    local rotator tryRot;

    DisableCollision();

    flat = remoteLoc - localLoc;
    flat.Z = 0;
    if (VSize(flat) > 40.0)
        dir = Normal(flat);
    else
        dir = Normal(vect(0,1,0) << localRot);

    // Try a few side directions so we don't land past the walkable pad
    p = SnapFeetToFloor(localLoc + dir * SIDE_OFFSET);
    for (attempt = 1; attempt <= 3; attempt++)
    {
        // if we dropped more than ~a storey vs local feet, try another angle
        if (Abs(p.Z - (localLoc.Z - Z_CORRECT)) < 80.0)
            break;
        tryRot.Yaw = localRot.Yaw + attempt * 16384;
        dir = Normal(vect(0,1,0) << tryRot);
        p = SnapFeetToFloor(localLoc + dir * SIDE_OFFSET);
    }

    SetLocation(p);
    remoteRot.Pitch = 0;
    remoteRot.Roll = 0;
    SetRotation(remoteRot);
    TargetLoc = PeerToLocal(remoteLoc);
    bDidFirstPlace = true;
    bHidden = false;
}

function ClearSpineChan()
{
    if (SpineChan != None)
    {
        SpineChan.Destroy();
        SpineChan = None;
    }
    SpineChan = AnimChannel(CreateAnimChannel(class'AnimChannel', AT_Replace, 'bip01 Spine1'));
    if (SpineChan != None)
        SpineChan.SetOwner(Self);
}

simulated event Tick(float dt)
{
    local vector desired;
    local vector d;
    local int yawDiff;
    local rotator newRot;
    local float blend;
    local float chanRate;

    // Pawn base may flip collision back on
    if (bCollideActors || bBlockActors || bBlockPlayers)
        DisableCollision();

    LastPacketAge += dt;

    if (LastPacketAge < 0.25)
        desired = TargetLoc + TargetVel * LastPacketAge;
    else
        desired = TargetLoc;

    blend = FClamp(dt * 14.0, 0.0, 1.0);

    d = desired - Location;
    if (VSize(d) > 800.0)
        SetLocation(desired);
    else if (VSize(d) > 1.0)
        SetLocation(Location + d * blend);

    yawDiff = (TargetRot.Yaw - Rotation.Yaw) & 65535;
    if (yawDiff > 32768)
        yawDiff -= 65536;
    newRot = Rotation;
    newRot.Yaw = (Rotation.Yaw + int(float(yawDiff) * blend)) & 65535;
    newRot.Pitch = 0;
    newRot.Roll = 0;
    SetRotation(newRot);

    if (TargetAnim != '' && AnimSequence != TargetAnim)
        PlayAnim(TargetAnim, TargetAnimRate, 0.15);
    else if (bAnimFinished && TargetAnim != '' && TargetAnimRate > 0)
        PlayAnim(TargetAnim, TargetAnimRate, 0.0);

    if (SpineChan != None)
    {
        if (TargetChanAnim == '' || TargetChanAnim == 'None')
        {
            // Peer released cast / left channel idle - drop upper-body blend
            if (SpineChan.AnimSequence != '' && SpineChan.AnimSequence != 'None')
                ClearSpineChan();
        }
        else if (SpineChan.AnimSequence != TargetChanAnim)
        {
            chanRate = TargetChanRate;
            if (chanRate <= 0)
                chanRate = 1.0;
            if (bTargetChanLoop)
                SpineChan.LoopAnim(TargetChanAnim, chanRate, 0.2);
            else
                SpineChan.PlayAnim(TargetChanAnim, chanRate, 0.1);
        }
        else if (bTargetChanLoop && SpineChan.bAnimFinished)
        {
            SpineChan.LoopAnim(TargetChanAnim, TargetChanRate, 0.0);
        }
        else if (!bTargetChanLoop && SpineChan.bAnimFinished
                 && SpineChan.AnimSequence == TargetChanAnim)
        {
            // one-shot cast finished on peer side
            ClearSpineChan();
        }
    }
}

defaultproperties
{
    DrawType=DT_Mesh
    Mesh=SkeletalMesh'HPModels.skharryMesh'
    DrawScale=1.0
    AmbientGlow=65
    bHidden=True
    bCollideActors=False
    bCollideWorld=False
    bBlockActors=False
    bBlockPlayers=False
    bProjTarget=False
    CollisionRadius=1.0
    CollisionHeight=1.0
    Physics=PHYS_None
    bStasis=False
    Health=100
    RemoteRole=ROLE_None
}
