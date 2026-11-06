// Hekili oracle patch (tools/wowsims/sim-pin/build.sh): adds the 28 items the checked-in requests wear that upstream's
// live-cache db regen (3e9de3f83b) dropped back to leftover_db.bin, read from M.PIN's db (d33930d040), so the old gear
// still loads. Usage: <new db.bin> <new leftover_db.bin> <old db.bin> <old leftover_db.bin> <out>. The old ScalingItemProperties.unrounded_dps (8) and
// ReducedCasterWeaponDamage.unrounded_dps (3) were doubles; the new proto reads them as floats, so they are
// recovered from the unknown fields.
package main

import (
	"fmt"
	"math"
	"os"
	"strconv"
	"strings"

	"github.com/wowsims/forever/sim/core/proto"
	googleProto "google.golang.org/protobuf/encoding/protowire"
	gp "google.golang.org/protobuf/proto"
)

func load(path string) *proto.UIDatabase {
	b, err := os.ReadFile(path)
	if err != nil {
		panic(err)
	}
	db := &proto.UIDatabase{}
	if err := gp.Unmarshal(b, db); err != nil {
		panic(err)
	}
	return db
}

// the double at field `num` in unknown bytes `u`, if any
func dbl(u []byte, num googleProto.Number) (float32, bool) {
	for len(u) > 0 {
		n, t, l := googleProto.ConsumeTag(u)
		u = u[l:]
		if t == googleProto.Fixed64Type {
			v, l2 := googleProto.ConsumeFixed64(u)
			u = u[l2:]
			if n == num {
				return float32(math.Float64frombits(v)), true
			}
			continue
		}
		l2 := googleProto.ConsumeFieldValue(n, t, u)
		u = u[l2:]
	}
	return 0, false
}

const items = "871,5267,10136,10246,10247,10251,10253,10255,10271,11904,13001,13002,13015,13022,13070,13072,13077," +
	"13096,13116,14332,14978,14979,271928,271948,272411,272414,272415,284716"

func main() {
	newDB, newLeft := load(os.Args[1]), load(os.Args[2])
	oldDB := load(os.Args[3])
	old2 := load(os.Args[4])
	gp.Merge(oldDB, old2)
	have := map[int32]bool{}
	for _, it := range newDB.Items {
		have[it.Id] = true
	}
	for _, it := range newLeft.Items {
		have[it.Id] = true
	}
	want := map[int32]bool{} // only the items the requests wear
	for _, s := range strings.Split(items, ",") {
		n, _ := strconv.Atoi(s)
		want[int32(n)] = true
	}
	added := 0
	for _, it := range oldDB.Items {
		if have[it.Id] || !want[it.Id] {
			continue
		}
		for _, so := range it.ScalingOptions {
			if v, ok := dbl(so.ProtoReflect().GetUnknown(), 8); ok {
				so.UnroundedDps = v
			}
			so.ProtoReflect().SetUnknown(nil)
			if r := so.ReducedCasterWeaponDamage; r != nil {
				if v, ok := dbl(r.ProtoReflect().GetUnknown(), 3); ok {
					r.UnroundedDps = v
				}
				r.ProtoReflect().SetUnknown(nil)
			}
		}
		it.Sources = nil // enum numbers moved; the sim does not read them
		newLeft.Items = append(newLeft.Items, it)
		added++
		have[it.Id] = true
	}
	out, err := gp.Marshal(newLeft)
	if err != nil {
		panic(err)
	}
	if err := os.WriteFile(os.Args[5], out, 0o644); err != nil {
		panic(err)
	}
	fmt.Println("added items:", added)
	if added < 28 { // docs/dev/wowsims-packs.md lists 28
		os.Exit(1)
	}
}
