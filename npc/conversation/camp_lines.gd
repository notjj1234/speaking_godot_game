class_name CampLines
extends RefCounted
## Conversation copy and phrase lists for the camp NPCs and the fire.
## ASCII only: the pixel font has no glyphs for curly quotes or dashes.
## Upgrades read like an RPG menu: "label" is the chip (+2 HP, +1 DMG, with the
## game's real numbers per rank) and "say" the plain phrase the player speaks.
## No stat names in the talk ("vitality", "haste"). Offer lines are formatted
## with the price, so a literal percent sign is written %%.
## Offers with "action": true skip the offer and practice steps.

const YES := ["yes", "yeah", "yep", "sure", "deal", "okay", "ok", "of course"]
const NO := ["no", "nope", "not now", "nah", "never mind"]
const BYE := ["bye", "goodbye", "nothing", "no thanks", "see you", "im done", "leave"]

const NPCS := {
	"smith": {
		"name": "Smith",
		"greet": ["Back from the dead? What'll it be?", "Still breathing. Need steel?"],
		"anything_else": "Anything else?",
		"clarify": [
			"Hit harder, or land more big hits?",
			"Speak up. Hit harder, big hits, or your sword?",
		],
		"farewell": "Now get out there.",
		"practice_intro": "Swear the smith's oath: '%s'",
		"praise_first": "Clean as steel! One gem off.",
		"praise": "Good enough. Done.",
		"retry": "Again. Like you mean it.",
		"refuse": {
			"broke": "Come back with more gems.",
			"maxed": "Can't sharpen that any further.",
			"full": "",
			"no_sword": "You don't even have a sword.",
		},
		"offers": {
			"might": {
				"label": "+1 DMG",
				"say": "Hit harder",
				"offer": "A sharper blade. +1 DMG. %d gems. Deal?",
				"done": "There. Swing it.",
				"phrases": ["hit harder", "stronger", "more damage", "damage", "attack", "might",
					"sharper blade", "strength"],
			},
			"crit": {
				"label": "+10% CRIT",
				"say": "Big hits",
				"offer": "I'll show you the weak spots. +10%% CRIT. %d gems. Deal?",
				"done": "You'll see the weak spots now.",
				"phrases": ["big hits", "big hit", "crit", "crits", "critical", "critical hits", "sharper eye", "lucky hits",
					"weak spots", "precision"],
			},
			"sword": {
				"label": "Sword",
				"done": "Sword's on your belt.",
				"done_off": "Sword's put away. Fists it is.",
				"phrases": ["sword", "equip", "unequip", "equip my sword", "put it away"],
			},
		},
		"small_talk": [
			{"expect": ["good morning", "morning", "hello", "hi", "hey"], "reply": "Morning. Fire's warm."},
			{"expect": ["how are you", "how is it going"], "reply": "Busy. Blades don't sharpen themselves."},
		],
	},
	"trainer": {
		"name": "Trainer",
		"greet": ["Up and at 'em, champ! What are we training?", "Great to see you! Ready to get stronger?"],
		"anything_else": "What else can we work on?",
		"clarify": [
			"Want to last longer, or move faster?",
			"Tell me: health or speed?",
		],
		"farewell": "Go get 'em, champ!",
		"practice_intro": "Say the trainer's chant: '%s'",
		"praise_first": "Perfect form! One gem off.",
		"praise": "There you go! Done.",
		"retry": "Shake it off and try again!",
		"refuse": {
			"broke": "Bring a few more gems and we'll train.",
			"maxed": "You're already as quick as they come!",
			"full": "",
			"no_sword": "",
		},
		"offers": {
			"vitality": {
				"label": "+2 HP",
				"say": "More health",
				"offer": "Toughen up. +2 HP. %d gems. Deal?",
				"done": "Feel that? One more heart.",
				"phrases": ["tougher", "more health", "health", "hp", "vitality", "more hearts", "hearts",
					"last longer", "survive", "endurance"],
			},
			"haste": {
				"label": "+8% SPEED",
				"say": "Run faster",
				"offer": "Running drills. +8%% SPEED. %d gems. Deal?",
				"done": "Look at those feet go!",
				"phrases": ["run faster", "faster", "speed", "haste", "quicker", "move faster", "quick",
					"sprint"],
			},
		},
		"small_talk": [
			{"expect": ["good morning", "morning", "hello", "hi", "hey"], "reply": "Good morning! Big day ahead!"},
			{"expect": ["i am tired", "im tired", "tired"], "reply": "Rest by the fire. Then we go again!"},
		],
	},
	"cook": {
		"name": "Cook",
		"greet": ["Hungry? You look hungry. What can I get you?", "Pull up a log! Something to eat?"],
		"anything_else": "Anything else for the road?",
		"clarify": [
			"Something small, or something strong? An apple, or a potion?",
			"I've got apples and potions, dear. Which one?",
		],
		"farewell": "Eat well out there!",
		"practice_intro": "Name the dish for me: '%s'",
		"praise_first": "Delicious! One gem off.",
		"praise": "Lovely. Here you go.",
		"retry": "Hm? Say it again, dear.",
		"refuse": {
			"broke": "No gems, no grub, I'm afraid.",
			"maxed": "",
			"full": "Your pack's full of my stew already!",
			"no_sword": "",
		},
		"offers": {
			"apple": {
				"label": "Apple",
				"offer": "A crisp apple. Heals 4 HP. %d gems. Deal?",
				"done": "Fresh from the tree.",
				"phrases": ["apple", "apples", "fruit", "snack", "something small"],
			},
			"potion": {
				"label": "Potion",
				"offer": "A strong potion. Heals 10 HP. %d gems. Deal?",
				"done": "Drink it when it hurts.",
				"phrases": ["potion", "potions", "drink", "bottle", "something strong", "medicine", "heal"],
			},
		},
		"small_talk": [
			{"expect": ["good morning", "morning", "hello", "hi", "hey"], "reply": "Morning, dear! Stew's almost ready."},
			{"expect": ["smells good", "that smells good", "what are you cooking"], "reply": "Secret recipe. Mostly mushrooms."},
		],
	},
	"fire": {
		"name": "Campfire",
		"greet": ["Rest and fight on? Say fight on, journal, or main menu."],
		"anything_else": "The fire crackles.",
		"clarify": ["The fire crackles. Say fight on, journal, or main menu."],
		"farewell": "You stay by the fire a while.",
		"bye_label": "Stay",
		"practice_intro": "'%s'",
		"praise_first": "",
		"praise": "",
		"retry": "",
		"refuse": {"broke": "", "maxed": "", "full": "", "no_sword": ""},
		"offers": {
			"fight": {
				"label": "Fight on",
				"action": true,
				"phrases": ["fight on", "fight", "continue", "keep going", "go back", "resume", "battle"],
			},
			"journal": {
				"label": "Journal",
				"action": true,
				"phrases": ["journal", "progress", "notes", "book"],
			},
			"title": {
				"label": "Main menu",
				"action": true,
				"phrases": ["title", "title screen", "main menu", "menu", "quit"],
			},
		},
		"small_talk": [
			{"expect": ["warm", "so warm", "nice fire"], "reply": "The fire is warm. Rest a moment."},
		],
	},
}


static func npc(id: String) -> Dictionary:
	return NPCS.get(id, {})
