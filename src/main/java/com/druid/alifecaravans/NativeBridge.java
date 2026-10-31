package com.druid.alifecaravans;

import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.characters.IsoZombie;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.vehicles.BaseVehicle;

/** Only exposes parked-brake release; no game patches or replacement driving. */
public final class NativeBridge {
    private NativeBridge() {}

    @LuaMethod(name="ALCNativeReleaseBrake", global=true)
    public static boolean release(BaseVehicle v) {
        if (v == null || GameServer.server || !v.isLocalPhysicSim()
                || (GameClient.client && !v.hasAuthorization(GameClient.connection))
                || !v.isEngineRunning() || Math.abs(v.getCurrentSpeedKmHour()) > 0.5f) return false;
        // Caravan membership is checked against the current client session in
        // Lua. Vehicle ModData is server-authoritative, not a client registry.
        IsoGameCharacter driver = v.getDriver();
        if (!(driver instanceof IsoZombie) || driver.isDead() || driver.getVehicle() != v
                || driver.getModData().rawget("ProjectALifeUID") == null) return false;
        for (int seat=0; seat<v.getMaxPassengers(); seat++) {
            if (v.getCharacter(seat) instanceof IsoPlayer) return false;
        }
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
