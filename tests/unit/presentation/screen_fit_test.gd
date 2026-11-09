extends GdUnitTestSuite
## ScreenFit.logical_size: device pixels / screen scale gives the "CSS"
## size; its shorter side is held between 360 and 720 logical pixels.


func test_logical_sizes_for_real_screens() -> void:
	# iPhone-class landscape: 2532x1170 device px at 3x = 844x390.
	assert_that(ScreenFit.logical_size(Vector2i(2532, 1170), 3.0)).is_equal(Vector2i(844, 390))
	# ...and portrait.
	assert_that(ScreenFit.logical_size(Vector2i(1170, 2532), 3.0)).is_equal(Vector2i(390, 844))
	# A 1280x720 window on a 2x Retina screen: today's desktop layout.
	assert_that(ScreenFit.logical_size(Vector2i(2560, 1440), 2.0)).is_equal(Vector2i(1280, 720))
	# A big 1920x1080 window: the short side caps at 720, so the layout
	# scales up (x1.5) rather than shrinking the HUD.
	assert_that(ScreenFit.logical_size(Vector2i(3840, 2160), 2.0)).is_equal(Vector2i(1280, 720))
	# A tiny 640x300 window: the short side floors at 360 (x1.2 up).
	assert_that(ScreenFit.logical_size(Vector2i(640, 300), 1.0)).is_equal(Vector2i(768, 360))


func test_degenerate_input_falls_back() -> void:
	assert_that(ScreenFit.logical_size(Vector2i(0, 0), 2.0)).is_equal(Vector2i(1280, 720))
	# A scale below 1 is treated as 1.
	assert_that(ScreenFit.logical_size(Vector2i(1280, 720), 0.5)).is_equal(Vector2i(1280, 720))
