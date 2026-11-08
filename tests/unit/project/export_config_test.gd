extends GdUnitTestSuite
## Regression checks on the export setup (milestone 8): presets parse,
## cover the intended platforms, keep dev files out of packs, and the
## bootstrap pieces exist. Actual exports run in CI, where templates
## are installed.

const PRESETS := "res://export_presets.cfg"

const EXPECTED: Dictionary[String, String] = {
	"Linux": "build/linux/preemptive_peril.x86_64",
	"Windows Desktop": "build/windows/preemptive_peril.exe",
	"Web": "build/web/index.html",
	"macOS": "build/macos/preemptive_peril.zip",
	"Android": "build/android/preemptive_peril.apk",
}


func test_presets_parse_and_cover_platforms() -> void:
	var cfg := ConfigFile.new()
	assert_int(cfg.load(PRESETS)).is_equal(OK)
	var found: Dictionary[String, String] = {}
	for section: String in cfg.get_sections():
		if section.ends_with(".options"):
			continue
		var preset_name: String = cfg.get_value(section, "name", "")
		found[preset_name] = cfg.get_value(section, "export_path", "")
		# Dev-only files stay out of every pack.
		var excludes: String = cfg.get_value(section, "exclude_filter", "")
		assert_bool(excludes.contains("tests/*")).is_true()
		assert_bool(excludes.contains("addons/gdUnit4/*")).is_true()
	for preset_name: String in EXPECTED:
		(
			assert_that(found.get(preset_name, ""))
			. append_failure_message("preset missing or mispathed: %s" % preset_name)
			. is_equal(EXPECTED[preset_name])
		)


func test_bootstrap_script_exists_and_main_scene_valid_when_set() -> void:
	assert_bool(ResourceLoader.exists("res://presentation/main.gd")).is_true()
	# The main scene is the documented one-node manual step; when someone
	# sets it, it must point at a real scene file.
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	if main_scene != "":
		assert_bool(ResourceLoader.exists(main_scene)).is_true()


func test_build_outputs_are_gitignored() -> void:
	var ignore := FileAccess.open("res://.gitignore", FileAccess.READ)
	assert_object(ignore).is_not_null()
	var text := ignore.get_as_text()
	assert_bool(text.contains("/build/")).is_true()
	assert_bool(text.contains("/reports/")).is_true()
