class_name NPCResource extends Resource

@export var npc_name: String = ""
@export var sprite: Texture
@export var portrait: Texture
@export var portrait_hframes: int = 4
@export var dialog_audio_pitch: String
@export var dialog_lines: PackedStringArray = PackedStringArray()
## Non-empty: talking starts a camp voice conversation (CampLines id) instead
## of the linear dialog_lines.
@export var conversation_id: String = ""
## MusicManager track played while you talk to this NPC (empty: keep the level's).
@export var music_track: StringName = &""
