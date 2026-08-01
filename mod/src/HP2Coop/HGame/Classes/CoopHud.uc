//================================================================================
// CoopHud - injected into HPHud to draw co-op status / nametag strip.
//================================================================================

class CoopHud injects HPHud;

simulated function PostRender(Canvas Canvas)
{
    local CoopManager mgr;
    local string line;

    Super.PostRender(Canvas);

    foreach AllActors(class'CoopManager', mgr)
        break;
    if (mgr == None || !mgr.bShowDebug)
        return;

    Canvas.Font = Font'SmallFont';
    Canvas.DrawColor.R = 180;
    Canvas.DrawColor.G = 255;
    Canvas.DrawColor.B = 180;
    Canvas.SetPos(8, 8);

    if (mgr.bIsHost)
        line = "HP2Coop HOST";
    else
        line = "HP2Coop CLIENT";

    if (mgr.bConnected)
        line = line$" CONNECTED";
    else
        line = line$" WAITING";

    line = line$" peer="$mgr.RemoteName;
    if (mgr.RemoteMap != "")
        line = line$" @"$mgr.RemoteMap;
    if (mgr.Puppet != None && !mgr.Puppet.bHidden)
        line = line$" [VISIBLE]";
    line = line$" sent="$mgr.SentCount$" recv="$mgr.RecvCount;
    line = line$" ping~"$mgr.EstPingMs$"ms loss~"$mgr.EstLossPct$"%";
    Canvas.DrawText(line, false);
}
