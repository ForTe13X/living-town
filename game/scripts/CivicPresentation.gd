extends RefCounted
## Read-only civic display decisions. The event fold in CivicProject.gd remains authority.

const PROJECT_ID := "hydrangea_square_planters_v1"

static func phase(state: Dictionary) -> String:
	if String(state.get("id", "")) != PROJECT_ID or int(state.get("proposal_event_id", -1)) < 0:
		return ""
	match String(state.get("status", "")):
		"proposed":
			return "planned"
		"approved":
			return "planned" if int(state.get("decision_event_id", -1)) >= 0 else ""
		"underway", "complete":
			if int(state.get("decision_event_id", -1)) < 0 or int(state.get("pay_event_id", -1)) < 0 \
					or int(state.get("start_event_id", -1)) < 0 \
					or int(state.get("due_tick", -1)) != int(state.get("start_tick", -2)) + 720:
				return ""
			if String(state["status"]) == "underway":
				return "underway"
			if int(state.get("complete_event_id", -1)) >= 0 \
					and int(state.get("complete_tick", -1)) >= int(state["due_tick"]):
				return "complete"
	return ""

static func receipt(state: Dictionary) -> String:
	if String(state.get("id", "")) == PROJECT_ID and int(state.get("proposal_event_id", -1)) >= 0 \
			and int(state.get("decision_event_id", -1)) >= 0:
		match String(state.get("status", "")):
			"rejected":
				return "广场绣球花圃 · 议事未通过 · 镇库未支付"
			"unfunded":
				if int(state.get("unfunded_event_id", -1)) >= 0:
					return "广场绣球花圃 · 镇库拨款未成功 · 尚未施工"
	match phase(state):
		"planned":
			return "广场绣球花圃 · 议事中 · 尚未动用镇库"
		"underway":
			return "广场绣球花圃 · 施工中 · 镇库已支付 %d 币 · 第 %d 刻完工" % [int(state.get("cost", 0)), int(state.get("due_tick", 0))]
		"complete":
			return "广场绣球花圃 · 已完工 · 镇库支付 %d 币 · 收据 #%d" % [int(state.get("cost", 0)), int(state.get("pay_event_id", -1))]
	return ""
