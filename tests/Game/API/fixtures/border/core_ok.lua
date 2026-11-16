-- tools/check_border.sh must pass this core stand-in: the four approved calls (windows design v6 §5.6: WindowOp)
local _, ns = ...
ns.VirtualState.WindowOp("pack:x#Primary", 3, 2)
ns.VirtualState.Drain(0)
ns.VirtualState.Build({})
ns.VirtualState.SetLog({})
