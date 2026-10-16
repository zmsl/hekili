# Task 1: Intercept gap closer; Protection precombat Charge

RED (impl stashed): make test -> 2 failures: intercept usable nil (warrior_spec:210); Arms rotation[2] heroic_strike not intercept (:493).
GREEN: make test 387 successes / 0 failures (base 386 + 1 new). make check exit 0 (luacheck, LuaLS no problems, api reads ok, api_inventory unchanged).

## SimC diff
```diff
diff --git a/tools/packs/warrior.lua b/tools/packs/warrior.lua
index 4122b65b..e605afb4 100644
--- a/tools/packs/warrior.lua
+++ b/tools/packs/warrior.lua
@@ -29,6 +29,7 @@ actions.execute=heroic_strike,use_off_gcd=1,if=active_enemies=1&((!settings.adap
 actions.execute+=/cleave,use_off_gcd=1,if=active_enemies>1&((!settings.adaptive_queueing_enabled&cooldown.mortal_strike.remains>=rage.time_to_50|settings.adaptive_queueing_enabled&should_cleave)|(execute_phase&settings.execute_queueing_enabled))
 actions.execute+=/execute
 actions.rotation=victory_rush
+actions.rotation+=/intercept,if=buff.berserker_stance.up&action.intercept.in_range&!action.heroic_strike.in_range
 actions.rotation+=/heroic_strike,use_off_gcd=1,if=active_enemies=1&((!settings.adaptive_queueing_enabled&cooldown.mortal_strike.remains>=rage.time_to_42|settings.adaptive_queueing_enabled&should_hs)|(execute_phase&settings.execute_queueing_enabled))
 actions.rotation+=/cleave,use_off_gcd=1,if=active_enemies>1&((!settings.adaptive_queueing_enabled&cooldown.mortal_strike.remains>=rage.time_to_50|settings.adaptive_queueing_enabled&should_cleave)|(execute_phase&settings.execute_queueing_enabled))
 actions.rotation+=/overpower
@@ -54,6 +55,7 @@ actions.execute=heroic_strike,use_off_gcd=1,if=active_enemies=1&((!settings.adap
 actions.execute+=/cleave,use_off_gcd=1,if=active_enemies>1&((!settings.adaptive_queueing_enabled&cooldown.bloodthirst.remains>=rage.time_to_50|settings.adaptive_queueing_enabled&should_cleave)|(execute_phase&settings.execute_queueing_enabled))
 actions.execute+=/execute
 actions.rotation=victory_rush
+actions.rotation+=/intercept,if=buff.berserker_stance.up&action.intercept.in_range&!action.heroic_strike.in_range
 actions.rotation+=/heroic_strike,use_off_gcd=1,if=active_enemies=1&((!settings.adaptive_queueing_enabled&cooldown.bloodthirst.remains>=rage.time_to_42|settings.adaptive_queueing_enabled&should_hs)|(execute_phase&settings.execute_queueing_enabled))
 actions.rotation+=/cleave,use_off_gcd=1,if=active_enemies>1&((!settings.adaptive_queueing_enabled&cooldown.bloodthirst.remains>=rage.time_to_50|settings.adaptive_queueing_enabled&should_cleave)|(execute_phase&settings.execute_queueing_enabled))
 actions.rotation+=/overpower
@@ -75,6 +77,7 @@ actions.rotation+=/berserker_stance,use_off_gcd=1,if=!up
             .. "Sunder Armor stacked to 5, Heroic Strike or Cleave with spare rage.",
         simc = [[
 actions.precombat=battle_shout,if=!buff.battle_shout.up
+actions.precombat+=/charge
 actions.precombat+=/defensive_stance,if=!buff.defensive_stance.up
 actions=shield_bash
 actions+=/defensive_stance,use_off_gcd=1,if=!buff.defensive_stance.up
```

## Warrior.lua diff (pack strings truncated)
```diff
diff --git a/src/Hekili/Forever/Classes/Warrior.lua b/src/Hekili/Forever/Classes/Warrior.lua
index f1e8b8d9..ee5ed19f 100644
--- a/src/Hekili/Forever/Classes/Warrior.lua
+++ b/src/Hekili/Forever/Classes/Warrior.lua
@@ -1075,6 +1075,16 @@ spec:RegisterAbilities({
         known = knows(INTERCEPT),
         buff = "berserker_stance",
 
+        -- LibRangeCheck resolves nothing on Forever (target.minR/maxR stay at their defaults), so no gate may read them.
+        usable = function()
+            return action.intercept.in_range, "target must be within Intercept's range"
+        end,
+
+        -- what the cast did to the now-state, in VirtualState's context (spec §12a)
+        now = function()
+            applyDebuff("target", "intercept_stun")
+        end,
+
         handler = function()
             setDistance(7)
             applyDebuff("target", "intercept_stun")
@@ -1725,15 +1735,15 @@ spec:RegisterOptions({ package = "Arms" })
 spec:RegisterPack(
     "Arms",
     20261016,
-    [[Hekili:LJvtVnUnq0Fl5IBcsGQv2K0gGid0UafT9qU4cS3KmT0ylctjQssfNue4F7Di1xuYuADa2w0MCWj2IZ7XzEKCMrm0p8pcxMquq4Jxp)678N7Fx4s1lfq4Ycs8oYw8l5
+    [[Hekili:LJvuVnUnm4Fl9LSw0cV4ETDRa1by7ag22d9LmG7n7OyZelezlpj5M2HI8BFuY2YYo2(sb6g2U(qUZ1I8tKFKMKGH(H)r4YeIccF865xFN)C)7cxQEPacxwqI3r2IpK
 )
 spec:RegisterPack(
     "Fury",
     20261016,
-    [[Hekili:LJ1tVTUnm8pl9swlEfEj912TcuNdBadB7qVKbSB2rXIjwiYwEsYnndf5Z(Js(FYo2Uj4Tn866H06yr(tK)efjddMf8hblOene80ntV5(ztNDFWc9(miyrgjAlzd(qk
+    [[Hekili:LJvtVnUnq0Fl5IBc2av7SjPnar5qlqrBpKlUa9MKPLgBrekrvsQ4nfb(3(od1xuYsk2y3wST5GsKfN5XzE8J3GjyrWFeSmMzGGhVA(v3Uy(IBdwAEjhcwMZIEITfFj
 )
 spec:RegisterPack(
     "Protection",
     20261016,
-    [[Hekili:LA12UTnpm4NLD3kwr(ZXUTFuxG1nm01lkgMhWUt2kY0XcrrYqsodDyWp7JY2jr(uA72fTjHh(i5NiPezg57KWeQfipmF68RMnD2vKq7J5ajmNY2s3GFrs3H))RALfy
+    [[Hekili:LA1BVnTpq4pl8oMyQ)A7whWpTmjgi0yVycrqI35exNlnw11oY2POHq5ZoNtsBD(72GxS1wF39C394hF2KfKVtctOwG8WY5lVAX8fxrcTpMdKWCkBlDd(fjDh()VQvw
 )
```

## Counts
 src/Hekili/Forever/Classes/Warrior.lua | 16 +++++++++++++---
 tests/Forever/warrior_spec.lua         | 32 ++++++++++++++++++++++++++------
 tools/packs/warrior.lua                |  3 +++
 3 files changed, 42 insertions(+), 9 deletions(-)
