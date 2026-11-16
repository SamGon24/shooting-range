extends GutTest


func test_confirmation_sounds_are_cached_non_silent_and_distinct() -> void:
	var hit: AudioStreamWAV = SfxFactory.confirmation(1400.0, 1000.0, 0.045)
	var armor: AudioStreamWAV = SfxFactory.confirmation(2300.0, 400.0, 0.16)
	var kill: AudioStreamWAV = SfxFactory.confirmation(1000.0, 1800.0, 0.22)
	assert_eq(hit, SfxFactory.confirmation(1400.0, 1000.0, 0.045))
	assert_almost_eq(hit.get_length(), 0.045, 0.0001)
	assert_almost_eq(armor.get_length(), 0.16, 0.0001)
	assert_almost_eq(kill.get_length(), 0.22, 0.0001)
	assert_ne(hit.data, armor.data)
	assert_ne(armor.data, kill.data)
	var loudest: int = 0
	for index: int in hit.data.size() / 2:
		loudest = maxi(loudest, absi(hit.data.decode_s16(index * 2)))
	assert_gt(loudest, 1000)


func test_feedback_plays_the_matching_prebuilt_player_without_new_nodes() -> void:
	var feedback := RangeFeedback.new()
	add_child_autofree(feedback)
	var audio := FeedbackAudio.new()
	audio.feedback = feedback
	add_child_autofree(audio)
	var count: int = get_tree().get_node_count()
	for kind: HitFeedback.Kind in [HitFeedback.Kind.HIT, HitFeedback.Kind.ARMOR_BREAK, HitFeedback.Kind.KILL]:
		feedback.feedback.emit(kind, Vector3.ZERO, 50.0, false)
		var player := audio.get_child(kind) as AudioStreamPlayer
		assert_true(player.playing)
	assert_eq(get_tree().get_node_count(), count)
	assert_eq(audio.get_child_count(), 3)
	await wait_physics_frames(20)
