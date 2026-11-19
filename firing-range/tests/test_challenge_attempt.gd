extends GutTest

const STEEL: ChallengeRule = preload("res://range/challenges/data/steel.tres")
const ACCURACY: ChallengeRule = preload("res://range/challenges/data/accuracy.tres")

func test_eligible_target_and_live_shot_are_required_and_timeout_is_final() -> void:
	var run := ChallengeAttempt.new(STEEL)
	run.contact(1, ChallengeRule.Target.STEEL)
	run.launch(2)
	run.contact(2, ChallengeRule.Target.MOVING)
	assert_eq(run.score(), 0)
	run.contact(2, ChallengeRule.Target.STEEL)
	run.contact(2, ChallengeRule.Target.STEEL)
	run.launch(3)
	run.advance(STEEL.seconds)
	run.contact(3, ChallengeRule.Target.STEEL)
	assert_true(run.done)
	assert_eq(run.score(), 1)

func test_accuracy_waits_for_last_impacts_and_ignores_extra_shots() -> void:
	var run := ChallengeAttempt.new(ACCURACY)
	for i: int in 11:
		run.launch(i)
		if i < 8:
			run.contact(i, ChallengeRule.Target.STATIONARY)
			run.finish_shot(i)
	run.contact(10, ChallengeRule.Target.STEEL)
	run.finish_shot(9)
	assert_false(run.done)
	run.contact(8, ChallengeRule.Target.MOVING)
	run.finish_shot(8)
	assert_true(run.done)
	assert_eq(run.score(), 90)
	for pair: Array in [[49,"No medal"],[50,"Bronze"],[69,"Bronze"],[70,"Silver"],[89,"Silver"],[90,"Gold"]]:
		assert_eq(ACCURACY.medal(pair[0]), pair[1])

func test_personal_bests_survive_restart_independently() -> void:
	var path := "/tmp/gut_m16_scores_%d.cfg" % get_instance_id()
	var scores := ChallengeScores.new(path)
	assert_eq(scores.best(&"steel"), -1)
	assert_eq(scores.record(&"steel", 7), OK)
	assert_eq(scores.record(&"moving", 0), OK)
	assert_eq(scores.record(&"steel", 5), OK)
	scores = ChallengeScores.new(path)
	assert_eq(scores.best(&"steel"), 7)
	assert_eq(scores.best(&"moving"), 0)
	DirAccess.remove_absolute(path)
