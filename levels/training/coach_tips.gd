class_name CoachTips
extends RefCounted
## One-time reminder tips after Guided Training, in the Trainer's bubble.
## Each id shows once ever (SettingsManager tutorial_tips_seen) and never while
## the player is still in Training or its camp tour.

const TIP_SECONDS := 6.0

const CAMP_AFTER_DEATH := "You fell, but your gems became points. Spend them here, then head back to the fire."
const SHOP_READY := "You can afford an upgrade! Talk to the Smith or the Trainer."
const FIRST_BOSS := "A boss! Three health bars, and each one ends with a word challenge."
const NEW_ARENA := "New area! Enemies here are tougher."
const PRACTICE_PAD := "Practise on the slime, then walk onto the glowing START square when you're ready."


static func show_once(host: Node, id: String, text: String) -> bool:
	if host == null or not host.is_inside_tree():
		return false
	if TrainingState.tip_seen(id) or TrainingState.in_tutorial(host.get_tree()):
		return false
	TrainingState.mark_tip_seen(id)
	var banner := CoachBanner.new()
	banner.name = "CoachTip"
	host.add_child(banner)
	banner.flash(text, TIP_SECONDS)
	print("✅ Coach tip shown: ", id)
	return true
