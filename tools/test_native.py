"""Boundary tests of our bridge using original tiny engine stubs (not a live test)."""
from pathlib import Path
import os
import subprocess
import tempfile

REPO = Path(__file__).resolve().parent.parent
JDK = Path(os.environ.get("PZ_JDK_DIR", "C:/Users/druid/.openclaw/workspace/_ext/jdk/jdk-25.0.4.1+1/bin"))
SOURCES = {
    "se/krka/kahlua/integration/annotations/LuaMethod.java": """package se.krka.kahlua.integration.annotations;
public @interface LuaMethod { String name(); boolean global(); }
""",
    "zombie/network/GameServer.java": """package zombie.network; public class GameServer { public static boolean server; }
""",
    "zombie/network/GameClient.java": """package zombie.network; public class GameClient { public static boolean client; public static Object connection; }
""",
    "zombie/characters/IsoGameCharacter.java": """package zombie.characters;
import zombie.vehicles.BaseVehicle;
public class IsoGameCharacter {
  public static class Data extends java.util.HashMap<String,Object> { public Object rawget(String k) { return get(k); } }
  public Data data=new Data(); public BaseVehicle vehicle; public boolean dead;
  public float x,y,z; public short id=-1;
  public Data getModData() { return data; } public boolean isDead() { return dead; }
  public BaseVehicle getVehicle() { return vehicle; } public short getOnlineID() { return id; }
  public float getX() { return x; } public float getY() { return y; } public float getZ() { return z; }
}
""",
    "zombie/characters/IsoZombie.java": "package zombie.characters; public class IsoZombie extends IsoGameCharacter {}",
    "zombie/characters/IsoPlayer.java": "package zombie.characters; public class IsoPlayer extends IsoGameCharacter {}",
    "zombie/vehicles/BaseVehicle.java": """package zombie.vehicles;
import zombie.characters.*;
public class BaseVehicle {
  public enum Authorization { Server,Local,LocalCollide,Remote }
  public Authorization netPlayerAuthorization=Authorization.Server; public short netPlayerId=-1;
  public int netPlayerTimeout=17, changed, wakeCalls, chunkChecks;
  public boolean engine=true,authorized=true,isActive,isStatic=true,chunks=true;
  public float speed,force=80,x,y,z; public Object square=new Object();
  public IsoGameCharacter.Data data=new IsoGameCharacter.Data(); public IsoGameCharacter[] seats=new IsoGameCharacter[3];
  public BaseVehicle towing,towed; public Controller controller=new Controller();
  public class Controller { public int calls; public float observed; public boolean fail,isEnable;
    public void park() { calls++; observed=force; if(fail) throw new IllegalStateException("park failed"); } }
  public int getMaxPassengers() { return seats.length; } public IsoGameCharacter getCharacter(int i) { return seats[i]; }
  public IsoGameCharacter getDriver() { return seats[0]; } public Controller getController() { return controller; }
  public IsoGameCharacter.Data getModData() { return data; } public Object getSquare() { return square; }
  public BaseVehicle getVehicleTowing() { return towing; } public BaseVehicle getVehicleTowedBy() { return towed; }
  public float getCurrentSpeedKmHour() { return speed; } public boolean isEngineRunning() { return engine; }
  public boolean hasAuthorization(Object c) { return authorized; }
  public boolean isLocalPhysicSim() { return netPlayerAuthorization==Authorization.Local || netPlayerAuthorization==Authorization.LocalCollide; }
  public boolean isNetPlayerAuthorization(Authorization a) { return netPlayerAuthorization==a; }
  public short getNetPlayerId() { return netPlayerId; }
  public void setNetPlayerAuthorization(Authorization a,int id) { netPlayerAuthorization=a;netPlayerId=(short)id;netPlayerTimeout=30;changed++; }
  public void authorizationChanged(IsoGameCharacter c) { setNetPlayerAuthorization(Authorization.Local,c.getOnlineID()); }
  public float getX() { return x; } public float getY() { return y; } public float getZ() { return z; }
  public float getBrakingForce() { return force; } public void setBrakingForce(float f) { force=f; }
  public boolean isPhysicsActive() { return controller.isEnable; }
  public void checkSurroundingChunks() { chunkChecks++; if(!chunks)setPhysicsActive(false); }
  public void setPhysicsActive(boolean wanted) {
    wakeCalls++; boolean active=wanted && chunks;
    if(controller.isEnable==active)return;
    controller.isEnable=active;isActive=active;isStatic=!active;
  }
}
""",
    "BridgeTest.java": """import com.druid.alifecaravans.NativeBridge;
import zombie.characters.*; import zombie.vehicles.*; import zombie.network.*;
public class BridgeTest {
  static int passed;
  static void check(boolean value,String name) { if(!value)throw new AssertionError(name); passed++; }
  static boolean acquire(BaseVehicle v,IsoZombie n,boolean riders) { return NativeBridge.acquireSP(v,n,"test-caravan","driver",1,riders,false); }
  static boolean drive(BaseVehicle v,IsoZombie n) { return NativeBridge.acquireSP(v,n,"test-caravan","driver",1,false,true); }
  public static void main(String[] args) {
    BaseVehicle v=new BaseVehicle(); IsoZombie n=new IsoZombie();
    n.data.put("ProjectALifeUID","driver"); n.data.put("ProjectALifeGeneration",1.0);
    v.data.put("ALifeCaravanId","test-caravan");
    GameClient.client=true;
    check(!acquire(v,n,false) && v.changed==0,"MP acquisition forbidden");
    GameClient.client=false; GameServer.server=true;
    check(!acquire(v,n,false) && v.changed==0,"server acquisition forbidden"); GameServer.server=false;
    v.data.put("ALifeCaravanId","foreign"); check(!acquire(v,n,false),"foreign tag"); v.data.put("ALifeCaravanId","test-caravan");
    n.data.put("ProjectALifeUID","wrong"); check(!acquire(v,n,false),"stale UID"); n.data.put("ProjectALifeUID","driver");
    n.data.put("ProjectALifeGeneration",2.0); check(!acquire(v,n,false),"stale generation"); n.data.put("ProjectALifeGeneration",1.0);
    n.dead=true; check(!acquire(v,n,false),"dead NPC"); n.dead=false;
    v.square=null; check(!acquire(v,n,false),"unloaded car"); v.square=new Object();
    v.towing=new BaseVehicle(); check(!acquire(v,n,false),"trailer constraint"); v.towing=null;
    n.x=41; check(!acquire(v,n,false),"remote NPC"); n.x=0;
    n.z=2; check(!acquire(v,n,false),"different floor"); n.z=0;
    v.speed=2; check(!acquire(v,n,false),"moving unowned car"); v.speed=0;
    v.netPlayerId=27; check(!acquire(v,n,false),"existing owner"); v.netPlayerId=-1;
    v.seats[0]=new IsoPlayer(); check(!acquire(v,n,true),"player driver even with riders enabled"); v.seats[0]=null;
    v.seats[2]=new IsoPlayer(); check(!acquire(v,n,false),"unapproved rider");
    check(acquire(v,n,true) && v.isLocalPhysicSim() && v.netPlayerId==-1,"approved SP rider");
    check(acquire(v,n,true) && v.changed==1,"repeat acquisition retains first snapshot");
    check(NativeBridge.releaseSP(v) && !v.isLocalPhysicSim() && v.netPlayerTimeout==17,"snapshot restored with passenger");
    check(!NativeBridge.releaseSP(v),"release is idempotent"); v.seats[2]=null;
    acquire(v,n,false); v.seats[0]=new IsoPlayer();
    check(NativeBridge.releaseSP(v) && v.isLocalPhysicSim(),"player takeover is preserved"); v.seats[0]=null;
    v.netPlayerAuthorization=BaseVehicle.Authorization.Server; acquire(v,n,false);
    v.netPlayerAuthorization=BaseVehicle.Authorization.Remote; v.netPlayerId=55;
    check(NativeBridge.releaseSP(v) && v.netPlayerId==55,"changed authority is preserved");
    v.netPlayerAuthorization=BaseVehicle.Authorization.Local; v.netPlayerId=-1; v.seats[0]=n;n.vehicle=v;
    check(acquire(v,n,false) && v.wakeCalls==0,"parked/approaching lease does not wake a body");
    check(drive(v,n) && v.isActive && !v.isStatic && v.chunkChecks==1,"restored seated SP driver wakes vanilla physics");
    int wakes=v.wakeCalls;
    check(drive(v,n) && v.wakeCalls==wakes,"active driving body is not repeatedly reset");
    v.isActive=false;v.isStatic=true;
    check(drive(v,n) && v.isActive && !v.isStatic && v.wakeCalls==wakes+2,"stationary controller/native mismatch resynchronizes");
    v.setPhysicsActive(false);v.chunks=false;
    check(drive(v,n) && !v.isActive && v.isStatic,"unloaded surrounding chunks still suppress physics");
    v.chunks=true;
    check(drive(v,n) && v.isActive,"chunk-ready driving retry wakes without another seat handoff");
    v.setPhysicsActive(false);v.engine=false;wakes=v.wakeCalls;
    check(drive(v,n) && v.wakeCalls==wakes,"stopped engine does not wake");v.engine=true;
    n.vehicle=null;
    check(drive(v,n) && v.wakeCalls==wakes,"approaching driver does not wake");n.vehicle=v;
    v.speed=2;
    check(drive(v,n) && v.wakeCalls==wakes,"moving body is never reset");v.speed=0;
    GameClient.client=true;
    check(!drive(v,n) && v.wakeCalls==wakes,"SP wake cannot run in multiplayer");GameClient.client=false;
    check(NativeBridge.release(v,false) && v.controller.calls==1 && v.controller.observed==0 && v.force==80,"brake release restores specification");
    v.controller.fail=true;
    try { NativeBridge.release(v,false); throw new AssertionError("expected error"); }
    catch(IllegalStateException expected) { check(v.force==80,"restore on controller exception"); } v.controller.fail=false;
    GameClient.client=true; v.authorized=false;
    check(!NativeBridge.release(v,true),"MP nonowner cannot clear brakes"); v.authorized=true; GameClient.client=false;
    v.seats[2]=new IsoPlayer(); check(!NativeBridge.release(v,false),"unapproved rider brake protection");
    check(NativeBridge.release(v,true),"approved passenger brake release");
    v.seats[0]=new IsoPlayer(); check(!NativeBridge.release(v,true),"player driver brake protection");
    System.out.println("Native boundary checks passed="+passed);
  }
}
""",
}

with tempfile.TemporaryDirectory(prefix="alc-native-tests-") as folder:
    root = Path(folder)
    sources = []
    for relative, body in SOURCES.items():
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(body, encoding="utf-8")
        sources.append(str(path))
    sources.append(str(REPO / "src/main/java/com/druid/alifecaravans/NativeBridge.java"))
    subprocess.run([str(JDK / "javac.exe"), "--release", "25", "-d", str(root), *sources], check=True)
    subprocess.run([str(JDK / "java.exe"), "-cp", str(root), "BridgeTest"], check=True)
