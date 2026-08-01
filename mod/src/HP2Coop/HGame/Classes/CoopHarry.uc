//================================================================================
// CoopHarry - injected replacement of the vanilla harry class.
// Entry point of the co-op mod: spawns/owns the CoopManager on every level
// and exposes console commands (CoopHost / CoopConnect / CoopDisconnect).
// Compile-time mechanism: "injects harry" renames vanilla harry to
// harryInjBase and this class takes the name "harry" (unrealscript-injector).
//================================================================================

class CoopHarry injects harry
  Config(User);

var CoopManager coop;

function CoopManager GetCoop()
{
    if (coop != None)
        return coop;

    foreach AllActors(class'CoopManager', coop)
    {
        log("GetCoop(): found existing "$coop);
        // The game may swap the pawn (cutscenes, double TravelPostAccept) -
        // make sure the manager drives the current harry, not a dead one.
        coop.InitCoop(Self);
        return coop;
    }

    coop = Spawn(class'CoopManager');
    coop.InitCoop(Self);
    log("GetCoop(): spawned "$coop);
    return coop;
}

event TravelPostAccept()
{
    Super.TravelPostAccept();
    log("TravelPostAccept CoopHarry");
    GetCoop().OnPlayerReady();
}

event PreClientTravel()
{
    if (coop != None)
        coop.OnPreTravel();
    Super.PreClientTravel();
}

exec function CoopHost(optional int port)
{
    GetCoop().Host(port);
}

exec function CoopConnect(string ip, optional int port)
{
    GetCoop().ConnectTo(ip, port);
}

exec function CoopDisconnect()
{
    if (coop != None)
        coop.DisconnectNow();
}

exec function CoopStatus()
{
    GetCoop().PrintStatus();
}

exec function CoopDebug()
{
    GetCoop().ToggleDebug();
}
