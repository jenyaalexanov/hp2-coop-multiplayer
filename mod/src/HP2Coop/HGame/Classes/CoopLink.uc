//================================================================================
// CoopLink - UDP socket wrapper for the co-op mod.
// P2P model: the host binds a fixed port and learns the peer address from the
// first incoming packet; the client binds an ephemeral port and sends to the
// configured host address. Text protocol (see CoopManager).
//================================================================================

class CoopLink extends UdpLink;

var CoopManager mgr;
var IpAddr RemoteAddr;
var bool bRemoteKnown;

function Init(CoopManager m)
{
    mgr = m;
}

function bool StartHost(int port)
{
    local int bound;

    bRemoteKnown = false;
    bound = BindPort(port, false);
    if (bound == 0)
    {
        mgr.LogMsg("failed to bind UDP port "$port);
        return false;
    }
    mgr.LogMsg("hosting on UDP port "$bound$", waiting for a player...");
    return true;
}

function bool StartClient(string ip, int port)
{
    local int bound;

    if (!StringToIpAddr(ip, RemoteAddr))
    {
        mgr.LogMsg("bad IP address: "$ip$" (use numeric form, e.g. 192.168.1.5)");
        return false;
    }
    RemoteAddr.Port = port;
    bRemoteKnown = true;

    bound = BindPort(0, true);
    if (bound == 0)
    {
        mgr.LogMsg("failed to bind a local UDP port");
        return false;
    }
    mgr.LogMsg("connecting to "$ip$":"$port$" (local port "$bound$")...");
    return true;
}

function SendTo(coerce string s)
{
    if (bRemoteKnown)
        SendText(RemoteAddr, s);
}

event ReceivedText(IpAddr Addr, string Text)
{
    // Ignore foreign packets before adopting the sender as our peer.
    if (Left(Text, 7) != "HPCOOP|")
        return;

    // Always track the latest source address: the peer re-binds its UDP
    // socket on every map travel, so the port from the last session is dead.
    RemoteAddr = Addr;

    if (!bRemoteKnown)
    {
        bRemoteKnown = true;
        mgr.OnPeerFound(IpAddrToString(Addr));
    }
    mgr.OnPacket(Text);
}

event Destroyed()
{
    mgr = None;
    Super.Destroyed();
}
