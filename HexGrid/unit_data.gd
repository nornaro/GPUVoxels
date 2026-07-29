class_name UnitData
extends RefCounted

enum UnitType {
	WALKER,
	RUNNER,
	TANK,
	FLYER,
	BOSS,
	HEALER,
}

enum ArmorType {
	LIGHT,
	MEDIUM,
	HEAVY,
	BOSS_ARMOR,
}

var unit_name: String
var unit_type: UnitType
var armor_type: ArmorType
var max_health: float
var speed: float
var damage: float
var attack_range: float
var attack_cooldown: float
var model_path: String
var scale: float
var xp_reward: int
var gold_reward: int
var color: Color
var special_ability: String
var spawn_weight: float
var min_wave: int


func _init(
	p_name: String,
	p_type: UnitType,
	p_armor: ArmorType,
	p_health: float,
	p_speed: float,
	p_damage: float,
	p_range: float,
	p_cooldown: float,
	p_model: String = "",
	p_scale: float = 1.0,
	p_xp: int = 10,
	p_gold: int = 5,
	p_color: Color = Color(0.85, 0.25, 0.20),
	p_ability: String = "",
	p_weight: float = 1.0,
	p_wave: int = 1
) -> void:
	unit_name = p_name
	unit_type = p_type
	armor_type = p_armor
	max_health = p_health
	speed = p_speed
	damage = p_damage
	attack_range = p_range
	attack_cooldown = p_cooldown
	model_path = p_model
	scale = p_scale
	xp_reward = p_xp
	gold_reward = p_gold
	color = p_color
	special_ability = p_ability
	spawn_weight = p_weight
	min_wave = p_wave


static func get_default_units() -> Array[UnitData]:
	return [
		UnitData.new("Scout", UnitType.WALKER, ArmorType.LIGHT, 30.0, 1.5, 5.0, 1.0, 1.0,
			"", 0.8, 10, 5, Color(0.85, 0.25, 0.20), "", 3.0, 1),
		UnitData.new("Runner", UnitType.RUNNER, ArmorType.LIGHT, 20.0, 3.0, 3.0, 1.0, 0.5,
			"", 0.7, 15, 8, Color(0.90, 0.60, 0.15), "fast", 2.0, 2),
		UnitData.new("Soldier", UnitType.WALKER, ArmorType.MEDIUM, 60.0, 1.0, 10.0, 1.5, 1.5,
			"", 1.0, 25, 12, Color(0.50, 0.50, 0.80), "", 2.0, 3),
		UnitData.new("Tank", UnitType.TANK, ArmorType.HEAVY, 200.0, 0.5, 15.0, 1.0, 2.5,
			"", 1.2, 50, 25, Color(0.30, 0.70, 0.25), "armored", 1.0, 5),
		UnitData.new("Flyer", UnitType.FLYER, ArmorType.LIGHT, 40.0, 2.5, 8.0, 2.0, 1.0,
			"", 0.9, 30, 15, Color(0.25, 0.45, 0.80), "flies", 1.5, 4),
		UnitData.new("Healer", UnitType.HEALER, ArmorType.LIGHT, 35.0, 1.2, 2.0, 3.0, 3.0,
			"", 0.9, 40, 20, Color(0.30, 0.90, 0.40), "heal_ally", 0.5, 6),
		UnitData.new("Boss", UnitType.BOSS, ArmorType.BOSS_ARMOR, 500.0, 0.4, 30.0, 2.0, 3.0,
			"", 1.5, 200, 100, Color(0.60, 0.20, 0.80), "aoe_damage", 0.1, 10),
	]


func get_team_color(team_id: int) -> Color:
	var team_colors := [
		Color(0.85, 0.25, 0.20),
		Color(0.90, 0.60, 0.15),
		Color(0.30, 0.70, 0.25),
		Color(0.25, 0.45, 0.80),
	]
	return team_colors[team_id % team_colors.size()]
