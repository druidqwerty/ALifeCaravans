package com.druid.alifecaravans;

import java.util.Map;
import java.util.WeakHashMap;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.characters.IsoZombie;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.vehicles.BaseVehicle;

/** Small engine adapters for our own caravans; no game patches or driving AI. */
public final class NativeBridge {
    private NativeBridge() {}
    private record SPLease(BaseVehicle.Authorization authorization, short playerId, int timeout,
                           short assignedId) {}
    private static final Map<BaseVehicle, SPLease> spLeases = new WeakHashMap<>();

    private static boolean hasPlayer(BaseVehicle v) {
        for (int seat=0; seat<v.getMaxPassengers(); seat++) {
            if (v.getCharacter(seat) instanceof IsoPlayer) return true;
        }
        return false;
    }

    /** Reloaded parked bodies can stay asleep after A-Life finishes boarding.
     * Authorization alone does not wake SP physics. Use the vanilla setter so
     * its missing-surrounding-chunks safety remains authoritative. */
    private static void wakeSP(BaseVehicle v, IsoZombie npc, boolean driving) {
        if (!driving || v.getDriver() != npc || npc.getVehicle() != v
                || !v.isEngineRunning() || Math.abs(v.getCurrentSpeedKmHour()) > 0.5f
                || (v.isPhysicsActive() && v.isActive && !v.isStatic)) return;
        v.checkSurroundingChunks();
        // The normal setter short-circuits on controller.isEnable, even when
        // a restored native body disagrees. Resync only a stationary body.
        if (v.isPhysicsActive() && (v.isStatic || !v.isActive)) v.setPhysicsActive(false);
        v.setPhysicsActive(true);
    }

    /** B42's local-simulation query is network-state based even in offline SP.
     * A-Life uses it before boarding. Lease that state only for a proven ALC car.
     * Lua checks the entire current session; Java repeats hard offline/identity guards. */
    @LuaMethod(name="ALCNativeAcquireSP", global=true)
    public static boolean acquireSP(BaseVehicle v, IsoZombie npc, String caravanId,
                                    String uid, double generation, boolean ridersAllowed, boolean driving) {
        if (GameClient.client || GameServer.server || v == null || npc == null
                || npc.isDead() || v.getController() == null || v.getSquare() == null
                || caravanId == null || !caravanId.equals(v.getModData().rawget("ALifeCaravanId"))
                || uid == null || !uid.equals(npc.getModData().rawget("ProjectALifeUID"))
                || !(npc.getModData().rawget("ProjectALifeGeneration") instanceof Number actual)
                || actual.doubleValue() != generation || (hasPlayer(v) && !ridersAllowed)
                || (v.getDriver() != null && v.getDriver() != npc)
                || (npc.getVehicle() != null && npc.getVehicle() != v)
                || v.getVehicleTowedBy() != null || v.getVehicleTowing() != null) return false;
        if (v.isLocalPhysicSim()) {
            wakeSP(v, npc, driving);
            return true;
        }
        if (!v.isNetPlayerAuthorization(BaseVehicle.Authorization.Server) || v.getNetPlayerId() != -1
                || Math.abs(v.getCurrentSpeedKmHour()) > 0.5f
                || Math.abs(npc.getZ() - v.getZ()) > 0.5f
                || Math.hypot(npc.getX() - v.getX(), npc.getY() - v.getY()) > 40) return false;
        // Do not manufacture a player or any network owner. In SP the NPC's
        // vanilla authorizationChanged API supplies Local, normally with ID -1.
        SPLease saved = new SPLease(v.netPlayerAuthorization, v.netPlayerId, v.netPlayerTimeout,
                                    npc.getOnlineID());
        v.authorizationChanged(npc);
        if (!v.isLocalPhysicSim()) return false;
        spLeases.put(v, saved);
        wakeSP(v, npc, driving);
        return true;
    }

    @LuaMethod(name="ALCNativeReleaseSP", global=true)
    public static boolean releaseSP(BaseVehicle v) {
        if (GameClient.client || GameServer.server || v == null) return false;
        SPLease saved = spLeases.remove(v);
        if (saved == null) return false;
        // A player/another controller that has taken over wins; never revert it.
        if (!(v.getDriver() instanceof IsoPlayer) && v.isNetPlayerAuthorization(BaseVehicle.Authorization.Local)
                && v.getNetPlayerId() == saved.assignedId()) {
            v.setNetPlayerAuthorization(saved.authorization(), saved.playerId());
            v.netPlayerTimeout = saved.timeout();
        }
        return true;
    }

    @LuaMethod(name="ALCNativeReleaseBrake", global=true)
    public static boolean release(BaseVehicle v, boolean ridersAllowed) {
        if (v == null || GameServer.server || !v.isLocalPhysicSim()
                || (GameClient.client && !v.hasAuthorization(GameClient.connection))
                || !v.isEngineRunning() || Math.abs(v.getCurrentSpeedKmHour()) > 0.5f) return false;
        // Caravan membership is checked against the current client session in
        // Lua. Vehicle ModData is server-authoritative, not a client registry.
        IsoGameCharacter driver = v.getDriver();
        if (!(driver instanceof IsoZombie) || driver.isDead() || driver.getVehicle() != v
                || driver.getModData().rawget("ProjectALifeUID") == null) return false;
        if (hasPlayer(v) && !ridersAllowed) return false;
        if (v.getController() == null) return false;
        float original = v.getBrakingForce();
        try {
            v.setBrakingForce(0);
            v.getController().park();
        } finally {
            v.setBrakingForce(original);
        }
        return true;
    }
}
