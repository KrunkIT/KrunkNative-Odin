package menu

import "core:math"

// Global first-person presentation; these values never enter gameplay packets.
Viewmodel_Control :: enum { WEAPON_FOV, BOBBING, LEANING, ROTATION, OFFSET_X, OFFSET_Y, OFFSET_Z, ADS_OFFSET_Y, SWAP_Y, RELOAD_Y, ADS_FOV_POWER }
Viewmodel_Toggle :: enum { TOGGLE_ADS, AIM_ANIMATION, HIDE_ON_ADS, SHOW_HANDS, SHOW_PRIMARY, SHOW_SECONDARY, SHOW_MELEE, LEFT_HANDED }
Viewmodel_Settings :: struct {
	values: [Viewmodel_Control]f32,
	toggles: [Viewmodel_Toggle]bool,
}

// Preserve the client's existing appearance when loading older preferences.
DEFAULT_VIEWMODEL_SETTINGS :: Viewmodel_Settings{
	values = {.WEAPON_FOV=95, .BOBBING=1, .LEANING=1, .ROTATION=0, .OFFSET_X=1, .OFFSET_Y=1, .OFFSET_Z=1, .ADS_OFFSET_Y=1, .SWAP_Y=1, .RELOAD_Y=1, .ADS_FOV_POWER=1},
	toggles = {.TOGGLE_ADS=false, .AIM_ANIMATION=true, .HIDE_ON_ADS=false, .SHOW_HANDS=true, .SHOW_PRIMARY=true, .SHOW_SECONDARY=true, .SHOW_MELEE=true, .LEFT_HANDED=false},
}
// Ranges and steps from the official 5fHFc viewmodel settings.
VIEWMODEL_LIMITS := [Viewmodel_Control][2]f32{
	.WEAPON_FOV={60,150}, .BOBBING={0,3}, .LEANING={0,6}, .ROTATION={-2,2},
	.OFFSET_X={0,4}, .OFFSET_Y={0,4}, .OFFSET_Z={0,4}, .ADS_OFFSET_Y={0,2},
	.SWAP_Y={-2,2}, .RELOAD_Y={0,1}, .ADS_FOV_POWER={0,1},
}
VIEWMODEL_LABELS := [Viewmodel_Control]string{
	.WEAPON_FOV="Weapon FOV", .BOBBING="Weapon bobbing", .LEANING="Weapon leaning", .ROTATION="Weapon rotation",
	.OFFSET_X="Weapon X offset", .OFFSET_Y="Weapon Y offset", .OFFSET_Z="Weapon Z offset", .ADS_OFFSET_Y="Weapon ADS Y offset",
	.SWAP_Y="Weapon swap Y", .RELOAD_Y="Weapon reload Y", .ADS_FOV_POWER="Weapon ADS FOV power",
}
VIEWMODEL_IDS := [Viewmodel_Control]string{
	.WEAPON_FOV="WeaponFov", .BOBBING="WeaponBobbing", .LEANING="WeaponLeaning", .ROTATION="WeaponRotation",
	.OFFSET_X="WeaponOffsetX", .OFFSET_Y="WeaponOffsetY", .OFFSET_Z="WeaponOffsetZ", .ADS_OFFSET_Y="WeaponAdsOffsetY",
	.SWAP_Y="WeaponSwapY", .RELOAD_Y="WeaponReloadY", .ADS_FOV_POWER="WeaponAdsFovPower",
}
VIEWMODEL_TOGGLE_LABELS := [Viewmodel_Toggle]string{.TOGGLE_ADS="Toggle weapon ADS", .AIM_ANIMATION="Weapon aim animation", .HIDE_ON_ADS="Hide weapon on ADS", .SHOW_HANDS="Show hands", .SHOW_PRIMARY="Show primary", .SHOW_SECONDARY="Show secondary", .SHOW_MELEE="Show melee", .LEFT_HANDED="Left handed"}
VIEWMODEL_TOGGLE_IDS := [Viewmodel_Toggle]string{.TOGGLE_ADS="ToggleWeaponAds", .AIM_ANIMATION="WeaponAimAnimation", .HIDE_ON_ADS="HideWeaponAds", .SHOW_HANDS="ShowHands", .SHOW_PRIMARY="ShowPrimary", .SHOW_SECONDARY="ShowSecondary", .SHOW_MELEE="ShowMelee", .LEFT_HANDED="LeftHanded"}

viewmodel_settings_validate :: proc(settings: Viewmodel_Settings) -> Viewmodel_Settings {
	// A zero-initialized client/view predates these settings. A valid weapon
	// FOV is always positive, even when every other control is intentionally 0.
	if settings == (Viewmodel_Settings{}) { return DEFAULT_VIEWMODEL_SETTINGS }
	result := settings
	defaults := DEFAULT_VIEWMODEL_SETTINGS
	for control in Viewmodel_Control {
		value := result.values[control]
		if math.is_nan(value) || math.is_inf(value) || control == .WEAPON_FOV && value <= 0 { value = defaults.values[control] }
		result.values[control] = clamp(value, VIEWMODEL_LIMITS[control][0], VIEWMODEL_LIMITS[control][1])
	}
	return result
}

settings_viewmodel :: proc(state: ^State) {
	settings_section("View model settings", state.scale)
	settings_slider(state, "Field of view (FOV)", "FieldOfView", state.settings_draft.fov, MIN_FOV, MAX_FOV, {kind=.FOV}, step=5)
	for control in Viewmodel_Control {
		settings_slider(state, VIEWMODEL_LABELS[control], VIEWMODEL_IDS[control], state.settings_draft.viewmodel.values[control],
			VIEWMODEL_LIMITS[control][0], VIEWMODEL_LIMITS[control][1], {kind=.VIEWMODEL_VALUE, index=i32(control)}, step=control == .WEAPON_FOV ? 5 : 0.1)
	}
	for toggle in Viewmodel_Toggle {
		settings_toggle_row(state, VIEWMODEL_TOGGLE_LABELS[toggle], VIEWMODEL_TOGGLE_IDS[toggle], state.settings_draft.viewmodel.toggles[toggle], {kind=.VIEWMODEL_TOGGLE, index=i32(toggle)})
	}
	settings_note("Applies to every weapon. Save keeps your changes; Cancel restores them. World FOV preserves hipfire cm/360. ADS FOV power controls the amount of zoom when aiming.", state.scale)
}
