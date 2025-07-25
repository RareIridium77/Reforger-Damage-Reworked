# Reforger Damage Reworked

**LVS vehicle now spawns with 3 new functions:**

---

### `lvs_vehicle:ReforgerCleanDecals()`

- Clears decals from all parts and wheels, not just the main body.

---

### `lvs_vehicle:StartInnerFire(repeatCount: number)`

- Starts inner fire event.  
- Calls hook: `Reforger.InnerFireStarted(lvs_entity: Entity, repeatCount: number)`

---

### `lvs_vehicle:StopInnerFire()`

- Stops inner fire event.  
- Calls hook: `Reforger.InnerFireStopped(lvs_entity: Entity)`

---

## 🔁 Pre-hooks

### `Reforger.CanStartInnerFire(lvs_entity: Entity, repeatCount: number)`

- Called before starting inner fire.  
- Return `false` to prevent it.

---

### `Reforger.CanStopInnerFire(lvs_entity: Entity)`

- Called before stopping inner fire.  
- Return `false` to prevent it.

---

> ⚠️ **NOTE:** `repeatCount` is how many times the timer will update and ignite the transport.
