//================================================================================
// CoopManager - heart of the co-op mod.
// One instance per level (spawned by CoopHarry.TravelPostAccept).
// Sends the local harry state over UDP at 20 Hz and drives the CoopPuppet
// that represents the remote player.
//
// Text protocol over UDP ("|" delimited):
//   HPCOOP|1|HELLO|name
//   HPCOOP|1|HELLOACK|name
//   HPCOOP|1|PING|seq                      latency probe
//   HPCOOP|1|PONG|seq                      latency reply
//   HPCOOP|1|S|map|x|y|z|yaw|pitch|vx|vy|vz|anim|rate|hp
//   HPCOOP|1|MAP|mapfile.unr               peer changed map; follow via LoadLevel
//   HPCOOP|1|SP|class|x|y|z|pitch|yaw|charge|target|ox|oy|oz   spell projectile
//   HPCOOP|1|PICK|name|class|x|y|z         prop picked up (beans/cards/frogs)
//   HPCOOP|1|LTRIG|triggerName             lumos trigger fired
//   HPCOOP|1|BYE
//================================================================================

class CoopManager extends Actor
  config(HP2Coop);

const PROTO = "HPCOOP|1";
const SEND_RATE = 0.05;
const HELLO_RATE = 1.0;
const PING_RATE = 2.0;
const HIDE_TIMEOUT = 3.0;
const DROP_TIMEOUT = 10.0;
const TRAVEL_GUARD = 5.0;

var config string LastHost;
var config int LastPort;
var config string PlayerName;
var config bool bSessionActive;
var config bool bWasHost;
var config bool bShowDebug;

var harry Player;
var CoopLink Link;
var CoopPuppet Puppet;

var bool bConnected;
var bool bIsHost;
var float LastRecvTime;
var float SendAccum;
var float HelloAccum;
var float PingAccum;
var float StatsAccum;
var int RecvCount;
var int SentCount;
var int PingSeq;
var float PingSentAt;
var int EstPingMs;
var int EstLossPct;
var int ExpectedRecv;
var int DroppedEst;

var string LastAnnouncedMap;
var float JustTraveledUntil;
var bool bApplyingRemote;

var string RemoteName;
var string RemoteMap;
var vector RLoc;
var rotator RRot;
var vector RVel;
var name RAnim;
var float RAnimRate;
var int RHealth;
var name RChanAnim;
var float RChanRate;
var bool bRChanLoop;

// ---------------------------------------------------------------------------

function InitCoop(harry p)
{
    Player = p;
    if (PlayerName == "")
        PlayerName = "Harry";
}

function LogMsg(coerce string msg)
{
    log("[HP2Coop] "$msg);
    if (Player != None)
        Player.ClientMessage("[HP2Coop] "$msg);
}

function DebugLog(coerce string msg)
{
    log("[HP2Coop] "$msg);
}

static function string StrReplace(coerce string hay, coerce string needle, coerce string with)
{
    local int i;
    i = InStr(Caps(hay), Caps(needle));
    if (i == -1)
        return hay;
    return Left(hay, i) $ with $ Mid(hay, i + Len(needle));
}

static function int StrSplit(coerce string Text, string delim, out string parts[24])
{
    local int n, i;
    local string rest;

    rest = Text;
    n = 0;
    while (rest != "" && n < 24)
    {
        i = InStr(rest, delim);
        if (i == -1)
        {
            parts[n++] = rest;
            rest = "";
        }
        else
        {
            parts[n++] = Left(rest, i);
            rest = Mid(rest, i + Len(delim));
        }
    }
    return n;
}

function string MapName()
{
    local string s;
    s = Caps(Level.LevelEnterText);
    if (s == "")
        s = Caps(Level.GetURLMap());
    return StrReplace(s, ".UNR", "");
}

// Canonical map file base name (caps, no ".unr") for travel sync.
// Prefers the URL map name because it is what LoadLevel/ServerTravel expects.
function string CurrentMapFile()
{
    local string s;
    s = Caps(Level.GetURLMap());
    if (s == "")
        s = MapName();
    return StrReplace(s, ".UNR", "");
}

// ---------------------------------------------------------------------------
// Session control
// ---------------------------------------------------------------------------

function OnPlayerReady()
{
    LogMsg("ready on map "$MapName());
    JustTraveledUntil = Level.TimeSeconds + TRAVEL_GUARD;
    if (bSessionActive)
    {
        LogMsg("restoring co-op session...");
        if (bWasHost)
            Host(LastPort);
        else
            ConnectTo(LastHost, LastPort);
    }
    else
    {
        LogMsg("no session. CoopHost / CoopConnect <ip> [port]");
    }
}

function Host(optional int port)
{
    if (port == 0)
        port = 7777;
    DisconnectLink();

    Link = Spawn(class'CoopLink');
    Link.Init(Self);
    bIsHost = true;
    bConnected = false;
    ResetStats();

    if (Link.StartHost(port))
    {
        LastPort = port;
        bWasHost = true;
        bSessionActive = true;
        SaveConfig();
        Enable('Tick');
    }
    else
    {
        Link.Destroy();
        Link = None;
    }
}

function ConnectTo(string ip, optional int port)
{
    if (port == 0)
        port = 7777;
    DisconnectLink();

    Link = Spawn(class'CoopLink');
    Link.Init(Self);
    bIsHost = false;
    bConnected = false;
    HelloAccum = 0.0;
    ResetStats();

    if (Link.StartClient(ip, port))
    {
        LastHost = ip;
        LastPort = port;
        bWasHost = false;
        bSessionActive = true;
        SaveConfig();
        Enable('Tick');
    }
    else
    {
        Link.Destroy();
        Link = None;
    }
}

function DisconnectNow()
{
    if (Link != None)
        Link.SendTo(PROTO$"|BYE");
    bSessionActive = false;
    SaveConfig();
    DisconnectLink();
    LogMsg("disconnected");
}

function DisconnectLink()
{
    if (Link != None)
    {
        Link.Destroy();
        Link = None;
    }
    bConnected = false;
    HidePuppet();
}

function ResetStats()
{
    RecvCount = 0;
    SentCount = 0;
    EstPingMs = 0;
    EstLossPct = 0;
    ExpectedRecv = 0;
    DroppedEst = 0;
    PingSeq = 0;
}

function PrintStatus()
{
    if (Link == None)
    {
        LogMsg("no session. Use CoopHost [port] or CoopConnect <ip> [port]");
        return;
    }
    if (bIsHost)
        LogMsg("role=host, connected="$bConnected$", peer="$RemoteName$", peerMap="$RemoteMap$", sent="$SentCount$", recv="$RecvCount$", ping="$EstPingMs$"ms, loss~"$EstLossPct$"%");
    else
        LogMsg("role=client, connected="$bConnected$", peer="$RemoteName$", peerMap="$RemoteMap$", sent="$SentCount$", recv="$RecvCount$", ping="$EstPingMs$"ms, loss~"$EstLossPct$"%");
}

function ToggleDebug()
{
    bShowDebug = !bShowDebug;
    SaveConfig();
    LogMsg("debug HUD="$bShowDebug);
}

// ---------------------------------------------------------------------------
// Packet handling
// ---------------------------------------------------------------------------

function OnPeerFound(string addr)
{
    LogMsg("incoming player from "$addr);
}

function OnPacket(string Text)
{
    local string parts[24];
    local int n;
    local int seq;
    local float ms;
    local vector sloc, soff;
    local rotator srot;

    n = StrSplit(Text, "|", parts);
    if (n < 3)
        return;
    if ((parts[0] $ "|" $ parts[1]) != PROTO)
        return;

    LastRecvTime = Level.TimeSeconds;
    RecvCount++;

    if (parts[2] == "HELLO")
    {
        if (n >= 4)
            RemoteName = parts[3];
        if (!bConnected)
        {
            bConnected = true;
            LogMsg(RemoteName$" joined the game");
        }
        Link.SendTo(PROTO$"|HELLOACK|"$PlayerName);
    }
    else if (parts[2] == "HELLOACK")
    {
        if (n >= 4)
            RemoteName = parts[3];
        if (!bConnected)
        {
            bConnected = true;
            LogMsg("connected to "$RemoteName$"'s game");
        }
    }
    else if (parts[2] == "PING")
    {
        if (n >= 4)
            Link.SendTo(PROTO$"|PONG|"$parts[3]);
    }
    else if (parts[2] == "PONG")
    {
        if (n >= 4)
        {
            seq = int(parts[3]);
            if (seq == PingSeq && PingSentAt > 0.0)
            {
                ms = (Level.TimeSeconds - PingSentAt) * 1000.0;
                if (EstPingMs == 0)
                    EstPingMs = int(ms);
                else
                    EstPingMs = (EstPingMs * 3 + int(ms)) / 4;
            }
        }
    }
    else if (parts[2] == "S")
    {
        if (n < 15)
            return;
        if (!bConnected)
        {
            bConnected = true;
            LogMsg("player state stream started");
        }
        RemoteMap = parts[3];
        RLoc.X = float(parts[4]);
        RLoc.Y = float(parts[5]);
        RLoc.Z = float(parts[6]);
        RRot.Yaw = int(parts[7]);
        RRot.Pitch = int(parts[8]);
        RRot.Roll = 0;
        RVel.X = float(parts[9]);
        RVel.Y = float(parts[10]);
        RVel.Z = float(parts[11]);
        RAnim = name(parts[12]);
        RAnimRate = float(parts[13]);
        RHealth = int(parts[14]);
        RChanAnim = '';
        RChanRate = 1.0;
        bRChanLoop = false;
        if (n >= 18)
        {
            RChanAnim = name(parts[15]);
            RChanRate = float(parts[16]);
            bRChanLoop = (int(parts[17]) != 0);
        }
        UpdatePuppet();
    }
    else if (parts[2] == "MAP")
    {
        if (n >= 4)
            FollowPeerMap(parts[3]);
    }
    else if (parts[2] == "SP")
    {
        if (n < 14)
            return;
        sloc.X = float(parts[4]);
        sloc.Y = float(parts[5]);
        sloc.Z = float(parts[6]);
        srot.Pitch = int(parts[7]);
        srot.Yaw = int(parts[8]);
        srot.Roll = 0;
        soff.X = float(parts[11]);
        soff.Y = float(parts[12]);
        soff.Z = float(parts[13]);
        ApplyRemoteSpell(parts[3], sloc, srot, float(parts[9]), parts[10], soff);
    }
    else if (parts[2] == "PICK")
    {
        if (n < 8)
            return;
        sloc.X = float(parts[5]);
        sloc.Y = float(parts[6]);
        sloc.Z = float(parts[7]);
        ApplyRemotePickup(parts[3], parts[4], sloc);
    }
    else if (parts[2] == "LTRIG")
    {
        if (n >= 4)
            ApplyRemoteLumosTrig(parts[3]);
    }
    else if (parts[2] == "BYE")
    {
        LogMsg(RemoteName$" left the game");
        bConnected = false;
        HidePuppet();
        if (!bIsHost)
            HelloAccum = 0.0;
    }
}

// ---------------------------------------------------------------------------
// Map travel sync
// ---------------------------------------------------------------------------

function FollowPeerMap(string peerMap)
{
    if (peerMap == "")
        return;
    if (Caps(peerMap) == Caps(CurrentMapFile()))
        return;
    // Anti ping-pong: right after our own travel the host keeps his map.
    if (bIsHost && Level.TimeSeconds < JustTraveledUntil)
    {
        DebugLog("ignoring MAP "$peerMap$" (just traveled, host priority)");
        return;
    }
    LogMsg("following "$RemoteName$" to map "$peerMap);
    if (Player != None)
        Player.LoadLevel(peerMap$".unr");
}

// ---------------------------------------------------------------------------
// World state sync (spells / pickups / lumos triggers)
// ---------------------------------------------------------------------------

function Actor FindActorByName(string aname)
{
    local Actor a;

    if (aname == "")
        return None;
    foreach AllActors(class'Actor', a)
        if (string(a.Name) == aname)
            return a;
    return None;
}

function BroadcastSpell(baseSpell s)
{
    local string tname;

    if (Link == None || !Link.bRemoteKnown)
        return;
    tname = "";
    if (s.TargetActor != None)
        tname = string(s.TargetActor.Name);
    Link.SendTo(PROTO$"|SP|"$string(s.Class)
        $"|"$s.Location.X$"|"$s.Location.Y$"|"$s.Location.Z
        $"|"$s.Rotation.Pitch$"|"$s.Rotation.Yaw
        $"|"$s.SpellCharge
        $"|"$tname
        $"|"$s.TargetOffset.X$"|"$s.TargetOffset.Y$"|"$s.TargetOffset.Z);
    SentCount++;
}

function ApplyRemoteSpell(string clsPath, vector loc, rotator rrot, float charge, string targetName, vector off)
{
    local class<baseSpell> c;
    local baseSpell s;
    local Actor t;
    local Actor own;

    if (Player == None)
        return;
    c = class<baseSpell>(DynamicLoadObject(clsPath, class'Class'));
    if (c == None)
    {
        DebugLog("ApplyRemoteSpell: cannot load "$clsPath);
        return;
    }
    t = FindActorByName(targetName);
    own = Player;
    if (Puppet != None && !Puppet.bHidden)
        own = Puppet;
    bApplyingRemote = true;
    s = Spawn(c, own, , loc, rrot);
    if (s != None)
    {
        s.Instigator = Pawn(own);
        s.InitSpell(own, t, off, charge);
    }
    bApplyingRemote = false;
}

function BroadcastPickup(HProp p)
{
    if (Link == None || !Link.bRemoteKnown)
        return;
    Link.SendTo(PROTO$"|PICK|"$string(p.Name)$"|"$string(p.Class)
        $"|"$p.Location.X$"|"$p.Location.Y$"|"$p.Location.Z);
    SentCount++;
}

function ApplyRemotePickup(string aname, string clsPath, vector loc)
{
    local HProp p;
    local HProp best;
    local class<Actor> c;
    local float d;
    local float bestd;

    if (Player == None)
        return;
    p = HProp(FindActorByName(aname));
    if (p != None)
    {
        // already collected here (own pickup or an earlier sync)
        if (p.IsInState('PickupProp') || p.bHidden)
            return;
    }
    else
    {
        // fallback: nearest pickup-able prop of the same class at that spot
        c = class<Actor>(DynamicLoadObject(clsPath, class'Class'));
        best = None;
        bestd = 300.0;
        foreach RadiusActors(class'HProp', p, 300.0, loc)
        {
            if (!p.bPickupOnTouch || p.IsInState('PickupProp') || p.bHidden)
                continue;
            if (c != None && !p.IsA(c.Name))
                continue;
            d = VSize(p.Location - loc);
            if (d < bestd)
            {
                bestd = d;
                best = p;
            }
        }
        p = best;
        if (p == None)
            return;
    }
    DebugLog("remote pickup: "$p.Name);
    bApplyingRemote = true;
    p.DoPickupProp();
    bApplyingRemote = false;
}

function BroadcastLumosTrig(string trigName)
{
    if (Link == None || !Link.bRemoteKnown)
        return;
    Link.SendTo(PROTO$"|LTRIG|"$trigName);
    SentCount++;
}

function ApplyRemoteLumosTrig(string trigName)
{
    local LumosTrigger t;

    t = LumosTrigger(FindActorByName(trigName));
    if (t == None || t.bFirstEventSent)
        return;
    LogMsg("lumos secret "$trigName$" activated by peer");
    bApplyingRemote = true;
    t.bFirstEventSent = true;
    t.TriggerEvent(t.Event, t, None);
    bApplyingRemote = false;
}

// ---------------------------------------------------------------------------
// Puppet
// ---------------------------------------------------------------------------

function UpdatePuppet()
{
    if (RemoteMap != MapName())
    {
        HidePuppet();
        return;
    }
    if (Puppet == None)
    {
        Puppet = Spawn(class'CoopPuppet', , , RLoc, RRot);
        if (Puppet == None)
        {
            LogMsg("failed to spawn puppet!");
            return;
        }
        if (Player != None)
        {
            Puppet.SetOwner(Player);
            Puppet.PlaceFirstTime(RLoc, RRot, Player.Location, Player.Rotation);
        }
        else
            Puppet.PlaceFirstTime(RLoc, RRot, RLoc, RRot);
        LogMsg("remote player is on your map (side of local player)");
    }
    Puppet.bHidden = false;
    Puppet.SetTarget(RLoc, RVel, RRot, RAnim, RAnimRate,
                     RChanAnim, RChanRate, bRChanLoop, RemoteName);
}

function HidePuppet()
{
    if (Puppet != None)
        Puppet.bHidden = true;
}

// ---------------------------------------------------------------------------
// Tick
// ---------------------------------------------------------------------------

event Tick(float dt)
{
    if (Link == None || Player == None)
        return;

    if (!bIsHost && !bConnected)
    {
        HelloAccum += dt;
        if (HelloAccum >= HELLO_RATE)
        {
            HelloAccum = 0.0;
            Link.SendTo(PROTO$"|HELLO|"$PlayerName);
            DebugLog("sent HELLO");
        }
    }

    if (Link.bRemoteKnown)
    {
        SendAccum += dt;
        if (SendAccum >= SEND_RATE)
        {
            SendAccum = 0.0;
            SendState();
        }

        PingAccum += dt;
        if (PingAccum >= PING_RATE)
        {
            PingAccum = 0.0;
            PingSeq++;
            PingSentAt = Level.TimeSeconds;
            Link.SendTo(PROTO$"|PING|"$PingSeq);
        }
    }

    // Announce our map once per change: covers fresh connects (peer pulls the
    // late joiner onto his map) and arrivals after our own travel.
    if (bConnected && Caps(LastAnnouncedMap) != Caps(CurrentMapFile()))
    {
        LastAnnouncedMap = CurrentMapFile();
        Link.SendTo(PROTO$"|MAP|"$LastAnnouncedMap);
        DebugLog("announced map "$LastAnnouncedMap);
    }

    // rough packet-loss estimate vs expected 20 Hz peer stream
    StatsAccum += dt;
    if (StatsAccum >= 5.0)
    {
        ExpectedRecv += int(StatsAccum / SEND_RATE);
        if (ExpectedRecv > 0)
        {
            DroppedEst = ExpectedRecv - RecvCount;
            if (DroppedEst < 0)
                DroppedEst = 0;
            EstLossPct = (DroppedEst * 100) / ExpectedRecv;
            if (EstLossPct > 100)
                EstLossPct = 100;
        }
        StatsAccum = 0.0;
        DebugLog("tick host="$bIsHost$" conn="$bConnected$" sent="$SentCount$" recv="$RecvCount$" ping="$EstPingMs$" loss~"$EstLossPct$"%");
    }

    if (bConnected)
    {
        if (Level.TimeSeconds - LastRecvTime > DROP_TIMEOUT)
        {
            LogMsg("connection to "$RemoteName$" timed out");
            bConnected = false;
            HidePuppet();
            if (!bIsHost)
                HelloAccum = 0.0;
        }
        else if (Level.TimeSeconds - LastRecvTime > HIDE_TIMEOUT)
        {
            HidePuppet();
        }
    }
}

function SendState()
{
    local string s;
    local string chanAnim;
    local float chanRate;
    local int chanLoop;

    chanAnim = "None";
    chanRate = 1.0;
    chanLoop = 0;
    // After StopAiming the channel goes to stateIdle but AnimSequence may
    // still be CastAim - only sync while the channel is doing something.
    if (Player.HarryAnimChannel != None
        && !Player.HarryAnimChannel.IsInState('stateIdle')
        && Player.HarryAnimChannel.AnimSequence != '')
    {
        chanAnim = string(Player.HarryAnimChannel.AnimSequence);
        chanRate = Player.HarryAnimChannel.AnimRate;
        if (Player.HarryAnimChannel.bAnimLoop)
            chanLoop = 1;
    }

    s = PROTO$"|S|"$MapName()
        $"|"$Player.Location.X
        $"|"$Player.Location.Y
        $"|"$Player.Location.Z
        $"|"$Player.Rotation.Yaw
        $"|"$Player.Rotation.Pitch
        $"|"$Player.Velocity.X
        $"|"$Player.Velocity.Y
        $"|"$Player.Velocity.Z
        $"|"$Player.AnimSequence
        $"|"$Player.AnimRate
        $"|"$Player.Health
        $"|"$chanAnim
        $"|"$chanRate
        $"|"$chanLoop;

    Link.SendTo(s);
    SentCount++;
}

function OnPreTravel()
{
    DisconnectLink();
    if (Puppet != None)
    {
        Puppet.Destroy();
        Puppet = None;
    }
}

event Destroyed()
{
    DisconnectLink();
    Super.Destroyed();
}

defaultproperties
{
    bHidden=True
    bStasis=False
    bTickIgnoredWhenPaused=False
    bShowDebug=True
    RemoteRole=ROLE_None
}
