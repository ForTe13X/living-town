extends "res://bench/ScaleCarpenterStockFitSim.gd"

## LT-14 bench-only macro-pool trial. A single credited fisher shift stands
## for a larger crew above 24 core residents; increase its declared batch by
## 10% with integer rounding. No new job choice, shift, or out-of-shift credit.
func _pool_rescale(raw: Dictionary, pop: int) -> Dictionary:
	var out: Dictionary = super._pool_rescale(raw, pop)
	if pop <= 24 or out.is_empty():
		return out
	var produce: Dictionary = out.get("produce", {})
	var fisher: Dictionary = produce.get("渔夫", {})
	if fisher.is_empty() or not fisher.has("amount"):
		return out
	var amount := int(fisher["amount"])
	fisher["amount"] = (amount * 11 + 9) / 10
	return out
