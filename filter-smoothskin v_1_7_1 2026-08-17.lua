-- SmoothSkin: automatic skin smoothing filter for OBS Studio
--
-- VERSION HISTORY
-- v1.7.1 (2026-08-17)
--   Performance only. Output is bit-identical to v1.7.0; no control,
--   default or tuning constant changed.
--   * Early rejection before the sample box estimator. The saturation
--     gate and luma limits never reference the sampled skin-tone
--     center, so a pixel failing them is non-skin whatever the box
--     reports. They are now evaluated first, and the live path returns
--     immediately on failure, skipping the estimator entirely (25
--     texture samples and 100 exponentials per pixel). Most of a
--     typical frame is background, hair or clothing, so most pixels no
--     longer pay for the estimator at all. Setup mode deliberately
--     keeps going so crop guides and the box outline still draw over
--     rejected areas.
--   * Removed duplicated color conversions: the mask source is
--     converted to YCbCr once and reused by the mask, the early
--     rejection and the redness preview tint, and the center-
--     independent mask term is computed once instead of twice.
--   * Considered and rejected: dropping the per-tap spatial weight
--     array to cut register pressure. It would trade 25 registers for
--     75 added exponentials in the rejection loop, which is a trade
--     rather than a win, so it was left alone pending measurement.
--
-- v1.7.0 (2026-08-17)
--   Redness targets visible in the mask preview (debugging aid).
--   * While "Show detection mask" is on, pixels the redness pass is
--     targeting are tinted cyan over the mask. Cyan because green is
--     already the sample box and red the crop guides.
--   * The tint appears only when Redness reduction is above zero, so
--     the preview stays plain black and white when the feature is off.
--   * The tint tracks the gate, not the strength slider, so the
--     targeted footprint stays fully visible while tuning the redness
--     threshold even at low strength.
--   * The gate is now a single shared function used by both the
--     preview and the correction, so what the preview shows and what
--     the filter actually corrects cannot drift apart. No change to
--     correction behavior; this is a refactor plus the tint.
--   * The mask preview help label gained a short clause naming cyan.
--   * The filter type id is deliberately unchanged from v1.6.0, so
--     settings and existing filter instances carry over.
--
-- v1.6.0 (2026-08-17)
--   Redness correction (foundation effect), chroma only.
--   * New "Redness reduction" and "Redness threshold" controls in a
--     Redness group. Red areas on skin (blemish inflammation, rosacea)
--     are pulled back toward the skin tone the sample box already
--     estimates each frame, so no color picker is needed. Defaults to
--     0 strength, so upgrading changes nothing until you raise it.
--   * Why this is not more smoothing: the bilateral kernel spans a few
--     pixels, so it can average away a 1 to 3px blemish but never a
--     patch larger than the kernel, since every sample inside a red
--     patch is also red. Worse, the bilateral treats the color step at
--     a red patch edge as an edge worth preserving, so higher Detail
--     protection actively protects redness. Redness is therefore
--     corrected in chroma space instead of by spatial averaging.
--   * Chroma only: the pixel's own luma is preserved exactly and only
--     Cb/Cr are moved, so shading, contour and facial form survive.
--     This is the difference from DeBlemish's color replace, which
--     lerps full RGB toward a picked color and flattens the face.
--   * Correction is applied along a fitted red axis in CbCr, so only
--     excess red is pulled back; sallow or shadowed areas are never
--     pushed redder. Lips are protected by a luma guard (lips are much
--     darker than sampled skin) plus an upper excess ceiling, both
--     inline TUNING constants in the redness block.
--   * Runs after smoothing and is independent of Smoothing strength,
--     so it works with smoothing at zero.
--
-- v1.5.1 (2026-07-17)
--   Steadier detection center under movement (spatial robustness, no
--   new controls). The sample box estimate is now harder to disturb
--   when the box briefly slips onto hair, a shadow edge or background
--   as you move:
--     * Taps are weighted by distance from the box center, so the
--       middle of the box (most reliably skin) dominates and edge taps
--       (first to catch contamination) count for less.
--     * The tap grid is spread a little wider so more skin feeds the
--       estimate.
--     * A third outlier-rejection pass and a slightly tighter rejection
--       width make contrasting taps fall away faster.
--   This targets brief, partial box slips, the common cause of mask
--   "breathing" during head movement. It cannot rescue a box parked
--   fully off skin; that remains a placement matter. Tuning constants
--   are noted inline in the sampling block if you want it stiffer or
--   looser after field testing.
--
-- v1.5.0 (2026-07-17)
--   Unified detection and a single tightness knob.
--   * The Auto/Manual dropdown is retired. The sample box now always
--     sets the skin-tone center automatically (robust B4 sampling),
--     and all detection controls live in one Detection group. Warmth
--     returns to its v1.2 role as a fine trim on the sampled center.
--   * New "Mask tightness" slider: the primary closed-loop knob for
--     how much variation around the sampled center counts as skin. It
--     scales the whole acceptance envelope (edge distance and feather
--     band together) symmetrically about a neutral midpoint at 0.5.
--     Below 0.5 the mask tightens (whiter on skin only); above 0.5 it
--     loosens. Sensitivity and Feather remain available to reshape the
--     ellipse and its falloff within that envelope.
--   * Migration note: scenes saved before v1.5.0 have no tightness
--     value, so they pick up the 0.5 default. Because tightness now
--     scales Sensitivity and Feather, such scenes may look slightly
--     different and can be nudged back with the tightness slider. The
--     old detection-mode setting is ignored; the box is always active.
--
-- v1.4.1 (2026-07-17)
--   Fix: the Detection mode groups (Auto sample box, Manual skin tone)
--   now show the correct one the moment the properties panel opens.
--   Previously the show/hide callback only ran on a mode change, so a
--   user whose saved mode was Manual would still see the Auto group
--   (and vice versa) until they touched the dropdown. The initial sync
--   reads the mode from the filter data table that OBS passes to
--   get_properties, not from a settings object (OBS does not pass one
--   here), which also avoids a get_properties call failure.
--
-- v1.4.0 (2026-07-17)
--   Contrast-robust sampling and auto/manual detection modes.
--   * Robust sample box (backlog B4): the box now gathers a 5x5 grid
--     of 25 taps and runs two outlier-rejection refinement passes on
--     them. Taps that contrast strongly with the dominant skin cluster
--     in luma or chroma (eyebrows, eyes, hair edges, a headset or
--     microphone passing through, colored light leak) receive
--     near-zero weight and no longer drag the sampled skin tone. This
--     targets the mask fluctuation seen with small boxes and head
--     movement in v1.2/v1.3 field testing.
--   * Detection mode selector (backlog B6): a "Detection mode"
--     dropdown now switches between "Auto (sample box)" and "Manual
--     (skin tone slider)". Only the controls for the chosen mode are
--     shown, so auto and manual are a conscious choice instead of
--     mixed sliders. Shared tuning (background rejection, range,
--     feather, shadows) lives in its own Detection tuning group.
--   * In manual mode the warmth slider defines the skin tone as in
--     v1.1. In auto mode warmth is hidden and unused; the robust
--     sampling replaces the need for a trim.
--   * Migration note: the old "Auto skin tone (sample box)" checkbox
--     setting is replaced by the dropdown, which defaults to Auto.
--     Users who had the checkbox off must pick Manual once.
--
-- v1.3.0 (2026-07-17)
--   Region limit crop guides and preview label text.
--   * Crop guides (backlog B3): while "Show detection mask" is on,
--     each active region limit boundary is drawn as a solid thin red
--     line, and the cropped side is tinted transparent red so it is
--     unambiguous which side of the line is excluded. Setup mode only,
--     never on live output.
--   * Mask preview description and tooltip updated to user-supplied
--     text: "Areas shown in white are where the filter applies the
--     smoothing effect. Black = ignored areas."
--
-- v1.2.0 (2026-07-17)
--   Sample box auto-calibration.
--   * New "Auto skin tone (sample box)" mode, enabled by default. A
--     small box is positioned over the face with sliders, and every
--     frame the shader averages the chroma inside the box and uses it
--     as the live detection center. This replaces manual color tuning
--     and adapts automatically when lighting or white balance changes
--     mid-stream. Disable it to fall back to the fixed v1.1 detection.
--   * The sample box is drawn as a green outline in the preview, but
--     only while "Show detection mask" is on, so it can never appear
--     on the live output. Setup mode and live mode are cleanly split.
--   * "Skin tone warmth" is now a trim on top of the sampled center
--     when the sample box is active, for fine adjustment only.
--   * Mask preview moved into its own group with a help label:
--     white = skin, will be smoothed; black = ignored. (Backlog B1)
--
-- v1.1.0 (2026-07-17)
--   Detection fix and slider overhaul.
--   * Added "Background rejection" saturation gate. Skin is never gray,
--     so pixels below a minimum chroma saturation can no longer be
--     detected as skin. This stops neutral walls, desks and other
--     low-saturation background from lighting up the mask at defaults.
--   * Replaced the two abstract fine tune sliders (blue-yellow and
--     green-red) with a single "Skin tone warmth" slider. Real-world
--     variation from lighting, white balance and camera saturation
--     moves skin along one warm-cool diagonal, so one slider covers it.
--     Negative = cooler skin rendering, positive = warmer.
--   * Settings are now organized into grouped panels: Smoothing,
--     Detection, and Region limit, with the mask preview toggle at the
--     top for quick access.
--
-- v1.0.0 (2026-07-17)
--   Initial release. Automatic YCbCr chroma skin detection (no color
--   picker), edge-preserving bilateral smoothing, mask preview,
--   shadow/highlight exclusion, skin tone fine tune, region limits.
--
-- Skin is detected in the YCbCr color space, where human skin of all
-- tones clusters in a narrow chroma range that is largely independent
-- of lighting level and color temperature. Smoothing uses an
-- edge-preserving bilateral filter, so eyes, eyebrows, lips, hairline
-- and clothing edges are protected even where the mask spills onto them.
--
-- Install: OBS Studio > Tools > Scripts > + > select this file.
-- Then add the "SmoothSkin v1.7.1" filter to any video source.
--
-- SIDE BY SIDE WITH v1.5.1
-- This build registers under the id 'filter-smoothskin-v160' instead
-- of the plain 'filter-smoothskin' used by v1.5.1 and earlier, so both
-- scripts can be loaded at once and both appear in the Add Filter
-- list. Load both files under Tools > Scripts and stack them on the
-- same source, then toggle each to compare.
--
-- When done comparing, settle on one build:
--   * To keep v1.6.0 as the permanent filter, either leave the id as
--     is (existing v1.6.0 filter instances keep working, but any old
--     v1.5.1 instances in saved scenes will show as missing once the
--     v1.5.1 script is unloaded), or change the id back to
--     'filter-smoothskin' and unload v1.5.1 first, which lets old
--     scene entries bind to this build instead.
--   * Filter settings do not transfer between the two ids. Each id has
--     its own saved settings per source, so tune whichever you keep.

obs = obslua

VERSION = '1.7.1'

SETTING_AMOUNT      = 'Amount'
SETTING_SIZE        = 'Size'
SETTING_DETAIL      = 'Detail'
SETTING_SENS        = 'Sensitivity'
SETTING_FEATHER     = 'Feather'
SETTING_TIGHT       = 'Tightness'
SETTING_WARMTH      = 'Warmth'
SETTING_RED         = 'Redness'
SETTING_REDTHR      = 'RednessThr'
SETTING_SATGATE     = 'SatGate'
SETTING_LUMALIMIT   = 'LumaLimit'
SETTING_SHOWMASK    = 'ShowMask'
SETTING_BOXX        = 'BoxX'
SETTING_BOXY        = 'BoxY'
SETTING_BOXSIZE     = 'BoxSize'
SETTING_CROPL       = 'CropLeft'
SETTING_CROPT       = 'CropTop'
SETTING_CROPR       = 'CropRight'
SETTING_CROPB       = 'CropBottom'

TEXT_AMOUNT     = 'Smoothing strength'
TEXT_SIZE       = 'Smoothing radius'
TEXT_DETAIL     = 'Detail protection'
TEXT_SENS       = 'Skin detection range'
TEXT_FEATHER    = 'Mask feather'
TEXT_TIGHT      = 'Mask tightness (- tighter / + looser)'
TEXT_WARMTH     = 'Skin tone warmth trim (- cooler / + warmer)'
TEXT_RED        = 'Redness reduction'
TEXT_REDTHR     = 'Redness threshold (- catches milder red / + only strong red)'
TEXT_SATGATE    = 'Background rejection'
TEXT_LUMALIMIT  = 'Exclude shadows and highlights'
TEXT_SHOWMASK   = 'Show detection mask'
TEXT_MASKINFO   = 'Areas shown in white are where the filter applies the smoothing effect. Black = ignored areas. Cyan = areas targeted for redness correction.'
TEXT_BOXX       = 'Sample box: horizontal position'
TEXT_BOXY       = 'Sample box: vertical position'
TEXT_BOXSIZE    = 'Sample box: size'
TEXT_CROPL      = 'From left'
TEXT_CROPT      = 'From top'
TEXT_CROPR      = 'From right'
TEXT_CROPB      = 'From bottom'

GROUP_PREVIEW   = 'GroupPreview'
GROUP_SMOOTH    = 'GroupSmoothing'
GROUP_DETECT    = 'GroupDetection'
GROUP_RED       = 'GroupRedness'
GROUP_REGION    = 'GroupRegion'

TEXT_GROUP_PREVIEW = 'Mask preview (setup mode)'
TEXT_GROUP_SMOOTH  = 'Smoothing'
TEXT_GROUP_DETECT  = 'Detection'
TEXT_GROUP_RED     = 'Redness (evens red areas toward your skin tone)'
TEXT_GROUP_REGION  = 'Region limit (crop inward from each edge)'

source_info = {}
-- Internal filter type id. OBS registers filter types by this id, not
-- by display name, so two scripts sharing an id cannot both load: the
-- second registration is rejected and only the first appears in the
-- Add Filter list. This build uses a version-suffixed id so it can run
-- side by side with v1.5.1 for comparison.
--
-- IMPORTANT: filter instances are saved in scene data under this id.
-- A filter added as 'filter-smoothskin-v160' will not be found by a
-- build using the plain 'filter-smoothskin' id, and vice versa. Once
-- done comparing, see the note in the header about settling on one id.
source_info.id = 'filter-smoothskin-v160'
source_info.type = obs.OBS_SOURCE_TYPE_FILTER
source_info.output_flags = obs.OBS_SOURCE_VIDEO

function script_description()
  return [[<center><h2>SmoothSkin</h2><p>v]] .. VERSION .. [[</p></center>
  <p>Automatic skin smoothing with no color picking. Skin is detected in
  YCbCr chroma space (works across skin tones and lighting) and smoothed
  with an edge-preserving bilateral filter that keeps eyes, brows and
  edges sharp.</p>
  <p>Quick start: add the filter and turn on <b>Show detection mask</b>.
  A green box appears in the preview. Place it on your cheek or forehead
  with the sample box sliders. The filter reads your skin tone from
  inside the box every frame, ignoring contrasting features like brows
  or a passing headset, so the mask calibrates itself and follows
  lighting changes. Adjust <b>Mask tightness</b> while watching the
  preview until white covers your face and nothing else. Then turn the
  mask off and set <b>Smoothing strength</b> to taste.</p>]]
end

function script_load(settings)
  obs.obs_register_source(source_info)
end

function script_properties(settings)
  local p = obs.obs_properties_create()
  local pe = obs.obs_properties_add_text(p, 'text', '', obs.OBS_TEXT_DEFAULT)
  obs.obs_property_set_visible(pe, false)
  return p
end

function set_render_size(filter)
  local target = obs.obs_filter_get_target(filter.source)

  local width, height
  if target == nil then
    width = 0
    height = 0
  else
    width = obs.obs_source_get_base_width(target)
    height = obs.obs_source_get_base_height(target)
  end

  filter.width = width
  filter.height = height
end

source_info.get_name = function()
  return 'SmoothSkin v' .. VERSION
end

source_info.create = function(settings, source)
  local filter = {}
  filter.source = source

  set_render_size(filter)

  obs.obs_enter_graphics()
  filter.effect = obs.gs_effect_create(shader, nil, nil)

  if filter.effect ~= nil then
    filter.params = {}
    filter.params.Amount      = obs.gs_effect_get_param_by_name(filter.effect, 'Amount')
    filter.params.Size        = obs.gs_effect_get_param_by_name(filter.effect, 'Size')
    filter.params.Detail      = obs.gs_effect_get_param_by_name(filter.effect, 'Detail')
    filter.params.Sensitivity = obs.gs_effect_get_param_by_name(filter.effect, 'Sensitivity')
    filter.params.Feather     = obs.gs_effect_get_param_by_name(filter.effect, 'Feather')
    filter.params.Tightness   = obs.gs_effect_get_param_by_name(filter.effect, 'Tightness')
    filter.params.Warmth      = obs.gs_effect_get_param_by_name(filter.effect, 'Warmth')
    filter.params.Redness     = obs.gs_effect_get_param_by_name(filter.effect, 'Redness')
    filter.params.RednessThr  = obs.gs_effect_get_param_by_name(filter.effect, 'RednessThr')
    filter.params.SatGate     = obs.gs_effect_get_param_by_name(filter.effect, 'SatGate')
    filter.params.LumaLimit   = obs.gs_effect_get_param_by_name(filter.effect, 'LumaLimit')
    filter.params.ShowMask    = obs.gs_effect_get_param_by_name(filter.effect, 'ShowMask')
    filter.params.BoxX        = obs.gs_effect_get_param_by_name(filter.effect, 'BoxX')
    filter.params.BoxY        = obs.gs_effect_get_param_by_name(filter.effect, 'BoxY')
    filter.params.BoxSize     = obs.gs_effect_get_param_by_name(filter.effect, 'BoxSize')
    filter.params.CropLeft    = obs.gs_effect_get_param_by_name(filter.effect, 'CropLeft')
    filter.params.CropTop     = obs.gs_effect_get_param_by_name(filter.effect, 'CropTop')
    filter.params.CropRight   = obs.gs_effect_get_param_by_name(filter.effect, 'CropRight')
    filter.params.CropBottom  = obs.gs_effect_get_param_by_name(filter.effect, 'CropBottom')
    filter.params.width       = obs.gs_effect_get_param_by_name(filter.effect, 'width')
    filter.params.height      = obs.gs_effect_get_param_by_name(filter.effect, 'height')
  end

  obs.obs_leave_graphics()
  if filter.effect == nil then
    source_info.destroy(filter)
    return nil
  end

  source_info.update(filter, settings)
  return filter
end

source_info.destroy = function(filter)
  if filter.effect ~= nil then
    obs.obs_enter_graphics()
    obs.gs_effect_destroy(filter.effect)
    obs.obs_leave_graphics()
  end
  filter = nil
end

source_info.get_width = function(filter)
  return filter.width
end

source_info.get_height = function(filter)
  return filter.height
end

source_info.get_properties = function(data)
  local props = obs.obs_properties_create()

  -- Mask preview group: setup mode toggle plus help label
  local grp_preview = obs.obs_properties_create()
  local p_show = obs.obs_properties_add_bool(grp_preview, SETTING_SHOWMASK, TEXT_SHOWMASK)
  obs.obs_property_set_long_description(p_show, TEXT_MASKINFO)
  obs.obs_properties_add_text(grp_preview, 'MaskInfo', TEXT_MASKINFO, obs.OBS_TEXT_INFO)
  obs.obs_properties_add_group(props, GROUP_PREVIEW, TEXT_GROUP_PREVIEW, obs.OBS_GROUP_NORMAL, grp_preview)

  -- Smoothing group: the day-to-day controls
  local grp_smooth = obs.obs_properties_create()
  obs.obs_properties_add_float_slider(grp_smooth, SETTING_AMOUNT, TEXT_AMOUNT, 0.0, 1.0, 0.001)
  obs.obs_properties_add_float_slider(grp_smooth, SETTING_SIZE, TEXT_SIZE, 0.0, 1.0, 0.001)
  obs.obs_properties_add_float_slider(grp_smooth, SETTING_DETAIL, TEXT_DETAIL, 0.0, 1.0, 0.001)
  obs.obs_properties_add_group(props, GROUP_SMOOTH, TEXT_GROUP_SMOOTH, obs.OBS_GROUP_NORMAL, grp_smooth)

  -- Redness group: pulls red areas on skin back toward the skin tone
  -- the sample box already estimates. Strength defaults to 0, so this
  -- does nothing until deliberately turned up. Threshold sets how much
  -- excess red is needed before correction engages, which is what keeps
  -- natural color variation from being flattened.
  local grp_red = obs.obs_properties_create()
  obs.obs_properties_add_float_slider(grp_red, SETTING_RED, TEXT_RED, 0.0, 1.0, 0.001)
  obs.obs_properties_add_float_slider(grp_red, SETTING_REDTHR, TEXT_REDTHR, 0.0, 1.0, 0.001)
  obs.obs_properties_add_group(props, GROUP_RED, TEXT_GROUP_RED, obs.OBS_GROUP_NORMAL, grp_red)

  -- Detection group: the sample box always sets the skin-tone center
  -- automatically (robust B4 sampling). Mask tightness is the primary
  -- closed-loop knob for how much variation around that center counts
  -- as skin; sensitivity and feather shape the acceptance ellipse and
  -- its falloff within that; warmth trims the sampled center.
  local grp_detect = obs.obs_properties_create()
  obs.obs_properties_add_float_slider(grp_detect, SETTING_BOXX, TEXT_BOXX, 0.0, 1.0, 0.001)
  obs.obs_properties_add_float_slider(grp_detect, SETTING_BOXY, TEXT_BOXY, 0.0, 1.0, 0.001)
  obs.obs_properties_add_float_slider(grp_detect, SETTING_BOXSIZE, TEXT_BOXSIZE, 0.02, 0.30, 0.001)
  obs.obs_properties_add_float_slider(grp_detect, SETTING_TIGHT, TEXT_TIGHT, 0.0, 1.0, 0.001)
  obs.obs_properties_add_float_slider(grp_detect, SETTING_SENS, TEXT_SENS, 0.0, 1.0, 0.001)
  obs.obs_properties_add_float_slider(grp_detect, SETTING_FEATHER, TEXT_FEATHER, 0.0, 1.0, 0.001)
  obs.obs_properties_add_float_slider(grp_detect, SETTING_WARMTH, TEXT_WARMTH, -1.0, 1.0, 0.001)
  obs.obs_properties_add_float_slider(grp_detect, SETTING_SATGATE, TEXT_SATGATE, 0.0, 1.0, 0.001)
  obs.obs_properties_add_bool(grp_detect, SETTING_LUMALIMIT, TEXT_LUMALIMIT)
  obs.obs_properties_add_group(props, GROUP_DETECT, TEXT_GROUP_DETECT, obs.OBS_GROUP_NORMAL, grp_detect)

  -- Region limit group: for excluding skin-toned background areas
  local grp_region = obs.obs_properties_create()
  obs.obs_properties_add_float_slider(grp_region, SETTING_CROPL, TEXT_CROPL, 0.0, 1.0, 0.001)
  obs.obs_properties_add_float_slider(grp_region, SETTING_CROPT, TEXT_CROPT, 0.0, 1.0, 0.001)
  obs.obs_properties_add_float_slider(grp_region, SETTING_CROPR, TEXT_CROPR, 0.0, 1.0, 0.001)
  obs.obs_properties_add_float_slider(grp_region, SETTING_CROPB, TEXT_CROPB, 0.0, 1.0, 0.001)
  obs.obs_properties_add_group(props, GROUP_REGION, TEXT_GROUP_REGION, obs.OBS_GROUP_NORMAL, grp_region)

  return props
end

source_info.get_defaults = function(settings)
  obs.obs_data_set_default_double(settings, SETTING_AMOUNT, 0.7)
  obs.obs_data_set_default_double(settings, SETTING_SIZE, 0.5)
  obs.obs_data_set_default_double(settings, SETTING_DETAIL, 0.65)
  obs.obs_data_set_default_double(settings, SETTING_SENS, 0.5)
  obs.obs_data_set_default_double(settings, SETTING_FEATHER, 0.4)
  obs.obs_data_set_default_double(settings, SETTING_TIGHT, 0.5)
  obs.obs_data_set_default_double(settings, SETTING_WARMTH, 0.0)
  obs.obs_data_set_default_double(settings, SETTING_RED, 0.0)
  obs.obs_data_set_default_double(settings, SETTING_REDTHR, 0.5)
  obs.obs_data_set_default_double(settings, SETTING_SATGATE, 0.4)
  obs.obs_data_set_default_bool(settings, SETTING_LUMALIMIT, true)
  obs.obs_data_set_default_bool(settings, SETTING_SHOWMASK, false)
  obs.obs_data_set_default_double(settings, SETTING_BOXX, 0.5)
  obs.obs_data_set_default_double(settings, SETTING_BOXY, 0.35)
  obs.obs_data_set_default_double(settings, SETTING_BOXSIZE, 0.08)
  obs.obs_data_set_default_double(settings, SETTING_CROPL, 0.0)
  obs.obs_data_set_default_double(settings, SETTING_CROPT, 0.0)
  obs.obs_data_set_default_double(settings, SETTING_CROPR, 0.0)
  obs.obs_data_set_default_double(settings, SETTING_CROPB, 0.0)
end

source_info.update = function(filter, settings)
  filter.Amount      = obs.obs_data_get_double(settings, SETTING_AMOUNT)
  filter.Size        = obs.obs_data_get_double(settings, SETTING_SIZE)
  filter.Detail      = obs.obs_data_get_double(settings, SETTING_DETAIL)
  filter.Sensitivity = obs.obs_data_get_double(settings, SETTING_SENS)
  filter.Feather     = obs.obs_data_get_double(settings, SETTING_FEATHER)
  filter.Tightness   = obs.obs_data_get_double(settings, SETTING_TIGHT)
  filter.Warmth      = obs.obs_data_get_double(settings, SETTING_WARMTH)
  filter.Redness     = obs.obs_data_get_double(settings, SETTING_RED)
  filter.RednessThr  = obs.obs_data_get_double(settings, SETTING_REDTHR)
  filter.SatGate     = obs.obs_data_get_double(settings, SETTING_SATGATE)
  filter.LumaLimit   = obs.obs_data_get_bool(settings, SETTING_LUMALIMIT)
  filter.ShowMask    = obs.obs_data_get_bool(settings, SETTING_SHOWMASK)
  filter.BoxX        = obs.obs_data_get_double(settings, SETTING_BOXX)
  filter.BoxY        = obs.obs_data_get_double(settings, SETTING_BOXY)
  filter.BoxSize     = obs.obs_data_get_double(settings, SETTING_BOXSIZE)
  filter.CropLeft    = obs.obs_data_get_double(settings, SETTING_CROPL)
  filter.CropTop     = obs.obs_data_get_double(settings, SETTING_CROPT)
  filter.CropRight   = obs.obs_data_get_double(settings, SETTING_CROPR)
  filter.CropBottom  = obs.obs_data_get_double(settings, SETTING_CROPB)

  set_render_size(filter)
end

source_info.video_render = function(filter)
  if not obs.obs_source_process_filter_begin(filter.source, obs.GS_RGBA, obs.OBS_ALLOW_DIRECT_RENDERING) then return end

  obs.gs_effect_set_float(filter.params.Amount, filter.Amount)
  obs.gs_effect_set_float(filter.params.Size, filter.Size)
  obs.gs_effect_set_float(filter.params.Detail, filter.Detail)
  obs.gs_effect_set_float(filter.params.Sensitivity, filter.Sensitivity)
  obs.gs_effect_set_float(filter.params.Feather, filter.Feather)
  obs.gs_effect_set_float(filter.params.Tightness, filter.Tightness)
  obs.gs_effect_set_float(filter.params.Warmth, filter.Warmth)
  obs.gs_effect_set_float(filter.params.Redness, filter.Redness)
  obs.gs_effect_set_float(filter.params.RednessThr, filter.RednessThr)
  obs.gs_effect_set_float(filter.params.SatGate, filter.SatGate)
  obs.gs_effect_set_bool(filter.params.LumaLimit, filter.LumaLimit)
  obs.gs_effect_set_bool(filter.params.ShowMask, filter.ShowMask)
  obs.gs_effect_set_float(filter.params.BoxX, filter.BoxX)
  obs.gs_effect_set_float(filter.params.BoxY, filter.BoxY)
  obs.gs_effect_set_float(filter.params.BoxSize, filter.BoxSize)
  obs.gs_effect_set_float(filter.params.CropLeft, filter.CropLeft)
  obs.gs_effect_set_float(filter.params.CropTop, filter.CropTop)
  obs.gs_effect_set_float(filter.params.CropRight, filter.CropRight)
  obs.gs_effect_set_float(filter.params.CropBottom, filter.CropBottom)
  obs.gs_effect_set_int(filter.params.width, filter.width)
  obs.gs_effect_set_int(filter.params.height, filter.height)

  obs.obs_source_process_filter_end(filter.source, filter.effect, filter.width, filter.height)
end

source_info.video_tick = function(filter, seconds)
  set_render_size(filter)
end

shader = [[
// SmoothSkin pixel shader v1.7.1
// Stage 1: skin mask from CbCr chroma distance. The sample box always
//          sets the detection center automatically with outlier
//          rejection; warmth trims that center. Mask tightness scales
//          the acceptance envelope (edge distance and feather band)
//          symmetrically about a neutral midpoint. A saturation gate
//          rejects neutral background.
// Stage 2: edge-preserving bilateral smoothing inside the mask.

#define LOOP    12
#define ANGLE   0.26179938779   // pi / 12, two rings, 48 samples total
#define RADIUS  0.0022

// TUNING: red axis in (Cb, Cr), fitted from skin reddening. Skin
// redness raises Cr and slightly lowers Cb.
#define RED_AXIS float2(-0.124, 0.992)

uniform float4x4 ViewProj;
uniform texture2d image;

uniform float Amount;
uniform float Size;
uniform float Detail;
uniform float Sensitivity;
uniform float Feather;
uniform float Tightness;
uniform float Warmth;
uniform float Redness;
uniform float RednessThr;
uniform float SatGate;
uniform bool  LumaLimit;
uniform bool  ShowMask;
uniform float BoxX;
uniform float BoxY;
uniform float BoxSize;
uniform float CropLeft;
uniform float CropTop;
uniform float CropRight;
uniform float CropBottom;
uniform int   width;
uniform int   height;

sampler_state textureSampler {
    Filter    = Linear;
    AddressU  = Clamp;
    AddressV  = Clamp;
};

struct VertData {
    float4 pos : POSITION;
    float2 uv  : TEXCOORD0;
};

VertData VSDefault(VertData v_in)
{
    VertData vert_out;
    vert_out.pos = mul(float4(v_in.pos.xyz, 1.0), ViewProj);
    vert_out.uv  = v_in.uv;
    return vert_out;
}

// BT.601 RGB to YCbCr, all components in 0..1
float3 rgb2ycbcr(float3 c)
{
    float y  = dot(c, float3(0.299, 0.587, 0.114));
    float cb = (c.b - y) * 0.564 + 0.5;
    float cr = (c.r - y) * 0.713 + 0.5;
    return float3(y, cb, cr);
}

// Inverse of rgb2ycbcr. The multipliers are exact reciprocals of the
// forward coefficients (1 / 0.713 and 1 / 0.564) rather than the
// rounded 1.402 / 1.772 constants, so an untouched pixel round-trips
// to itself. Used by the redness pass to rebuild a pixel after moving
// only its chroma, leaving luma intact.
float3 ycbcr2rgb(float3 ycc)
{
    float r = ycc.x + (ycc.z - 0.5) * 1.4025245;
    float b = ycc.x + (ycc.y - 0.5) * 1.7730496;
    float g = (ycc.x - 0.299 * r - 0.114 * b) / 0.587;
    return saturate(float3(r, g, b));
}

// Redness gate. Returns (gate, excess) where gate is 0..1 for how
// strongly this pixel qualifies as excess redness on skin, and excess
// is its signed projection onto the red axis.
//
// Shared by the correction pass and the setup-mode cyan tint, so what
// the preview shows and what the filter corrects can never drift apart.
// Takes an already-converted YCbCr value so callers that already hold
// one do not pay for the conversion twice.
float2 redness_gate(float3 ycc, float2 center, float skinY)
{
    // TUNING: lips guard. Ratio of pixel luma to sampled skin luma;
    // below LUMA0 no correction, above LUMA1 full. Lips sit near
    // 0.5 to 0.65 of skin luma, blemishes and rosacea near 0.85+.
    // Lower LUMA0 if redness on shadowed skin is being missed.
    const float LUMA0 = 0.68;
    const float LUMA1 = 0.82;
    // TUNING: upper ceiling on excess red, a second line of defence
    // for very saturated red such as bright lips. Raise both if
    // severe rosacea is being left uncorrected.
    const float CEIL0 = 0.115;
    const float CEIL1 = 0.165;

    float excess = dot(ycc.yz - center, RED_AXIS);

    // Threshold slider maps to a deadzone in chroma units, so mild
    // natural variation stays untouched.
    float thr = 0.010 + RednessThr * 0.045;

    float t = smoothstep(thr, thr + 0.015, excess);
    t *= 1.0 - smoothstep(CEIL0, CEIL1, excess);
    t *= smoothstep(LUMA0, LUMA1, ycc.x / max(skinY, 0.0001));

    return float2(t, excess);
}

// Soft skin probability, 0..1, against a given chroma center.
// Center-independent part of the skin mask: the saturation gate and
// the optional luma limits. Neither term references the sampled
// skin-tone center, so a pixel scoring zero here cannot be skin no
// matter what the sample box reports. Evaluating this first lets the
// main shader reject most of the frame before paying for the sample
// box estimator, which is the single most expensive block per pixel.
float skin_mask_pre(float3 ycc)
{
    // Saturation gate: skin is never gray. Pixels whose chroma sits
    // too close to neutral (white, gray, black, unsaturated walls and
    // furniture) cannot be skin, regardless of the ellipse test.
    float chroma = length(ycc.yz - float2(0.5, 0.5));
    float gate = SatGate * 0.12;
    float p = smoothstep(gate, gate + 0.03, chroma);

    if (LumaLimit) {
        p *= smoothstep(0.06, 0.18, ycc.x);          // drop deep shadows and hair
        p *= 1.0 - smoothstep(0.93, 0.995, ycc.x);   // drop blown highlights
    }

    return p;
}

// Soft skin probability, 0..1. Takes the already-converted YCbCr value
// and the pre-test result from skin_mask_pre so neither is recomputed.
float skin_mask(float3 ycc, float2 center, float pre)
{
    float2 axes = float2(0.115, 0.095);   // ellipse radii in Cb, Cr

    float dist = length((ycc.yz - center) / axes);

    // Mask tightness scales the whole acceptance envelope about a
    // neutral midpoint: Tightness 0.5 leaves Sensitivity and Feather
    // exactly as tuned (scale 1.0), lower values shrink both the edge
    // distance and the feather band together (tighter, whiter on skin
    // only), higher values grow them together (looser, more inclusive).
    // This is the primary closed-loop knob; Sensitivity and Feather
    // still reshape the ellipse and its falloff within that envelope.
    float ts = 0.5 + Tightness;                  // 0.5 .. 1.5, neutral at 1.0
    float edge0 = Sensitivity * 2.0 * ts;
    float edge1 = edge0 + (0.05 + Feather * 1.2) * ts;
    float m = 1.0 - smoothstep(edge0, edge1, dist);

    return m * pre;
}

float4 PassThrough(VertData v_in) : TARGET
{
    float2 uv = v_in.uv;
    float aspect = float(width) / float(height);
    float2 px = float2(1.0 / float(width), 1.0 / float(height));

    float4 orig = image.Sample(textureSampler, uv);
    float3 base = orig.rgb;

    // Build the mask source from a lightly averaged sample so
    // single-pixel noise does not make the mask flicker frame to frame.
    float3 msrc = base;
    msrc += image.Sample(textureSampler, uv + float2( px.x * 2.0, 0.0)).rgb;
    msrc += image.Sample(textureSampler, uv + float2(-px.x * 2.0, 0.0)).rgb;
    msrc += image.Sample(textureSampler, uv + float2(0.0,  px.y * 2.0)).rgb;
    msrc += image.Sample(textureSampler, uv + float2(0.0, -px.y * 2.0)).rgb;
    msrc /= 5.0;

    float3 mycc = rgb2ycbcr(msrc);

    // Center-independent rejection, evaluated before the sample box
    // estimator. The saturation gate and luma limits do not depend on
    // the sampled center, so a pixel scoring zero here is guaranteed
    // non-skin and would have been returned untouched anyway. Bailing
    // now skips the estimator (25 texture samples and 100 exponentials
    // per pixel), which most of a typical frame does not need. The
    // result is bit-identical to evaluating it in the old order.
    //
    // The live path only. In setup mode the shader must keep going so
    // the crop guides and sample box outline still draw over rejected
    // areas.
    float pre = skin_mask_pre(mycc);

    if (!ShowMask && (pre <= 0.0005)) return orig;

    // Sample box geometry. BoxSize is a fraction of frame height, and
    // the horizontal extent is aspect corrected so the box is square
    // on screen.
    float2 bcenter = float2(BoxX, BoxY);
    float2 bext = float2(BoxSize * 0.5 / aspect, BoxSize * 0.5);

    // Detection center. The sample box always estimates it: gather a
    // 5x5 grid of taps inside the box as (Y, Cb, Cr) values, spread a
    // little wider than before so more skin feeds the estimate.
    float2 center;

    float3 taps[25];
    float  sw[25];      // spatial weight per tap, center of box weighted
                        // most heavily so edge taps that slip onto hair
                        // or a shadow edge when you move contribute less
    for (int j = 0; j < 5; j++) {
        for (int k = 0; k < 5; k++) {
            float2 grid = float2(float(j) - 2.0, float(k) - 2.0);
            float2 off = grid * bext * 0.46;   // wider spread (was 0.38)
            int idx = j * 5 + k;
            taps[idx] = rgb2ycbcr(image.Sample(textureSampler, bcenter + off).rgb);
            // Gaussian falloff from box center over the 5x5 grid. Center
            // tap weight 1.0, corners about 0.2, so the middle of the
            // box (most reliably skin) dominates the estimate.
            sw[idx] = exp(-dot(grid, grid) / 4.0);
        }
    }

    // Spatially weighted initial mean: center taps count for more than
    // edge taps from the outset.
    float3 est = float3(0.0, 0.0, 0.0);
    float  swsum = 0.0;
    for (int t0 = 0; t0 < 25; t0++) { est += taps[t0] * sw[t0]; swsum += sw[t0]; }
    est /= max(swsum, 0.0001);

    // Three soft outlier-rejection refinements (mean-shift style; was
    // two). Since skin dominates the box, the mean starts near the skin
    // cluster; taps that contrast with it in luma or chroma, such as
    // eyebrows, eyes, hair edges, a passing headset or colored light
    // leak, receive near-zero weight and stop dragging the estimate.
    // Each tap's contrast weight is multiplied by its spatial weight,
    // so a slip at the box edge is doubly discounted. Luma differences
    // are weighted at half strength so natural shading across the skin
    // patch is tolerated. The rejection width is a little tighter than
    // before (0.052 vs 0.06) so contaminated taps fall away faster and
    // the estimate holds skin more stubbornly as the box moves.
    // TUNING: raise 0.0054 toward 0.0072 if the mask feels too twitchy
    // or rejects real skin shading; lower it for an even stiffer lock.
    for (int r = 0; r < 3; r++) {
        float3 racc = float3(0.0, 0.0, 0.0);
        float rwsum = 0.0;
        for (int t = 0; t < 25; t++) {
            float3 dd = (taps[t] - est) * float3(0.5, 1.0, 1.0);
            float rw = exp(-dot(dd, dd) / 0.0054) * sw[t];   // 2 * 0.052^2
            racc += taps[t] * rw;
            rwsum += rw;
        }
        est = racc / max(rwsum, 0.0001);
    }

    center = est.yz;

    // The same robust estimate also gives the average skin luma, which
    // the redness pass uses to tell lips (much darker than skin) from
    // blemishes and rosacea (close to skin luma).
    float skinY = est.x;

    // Warmth trims the sampled center along the warm-cool diagonal for
    // fine adjustment when the auto estimate lands close but not exact.
    center += float2(-Warmth * 0.07, Warmth * 0.07);

    // Build the mask from a lightly averaged sample so single-pixel
    // noise does not make the mask flicker frame to frame.
    // (msrc and its YCbCr conversion were computed above, before the
    // early-out, and the center-independent term is reused as well.)
    float m = skin_mask(mycc, center, pre);

    // Optional region limit, each slider crops inward from its edge
    if ((uv.x < CropLeft) || (uv.x > 1.0 - CropRight) ||
        (uv.y < CropTop)  || (uv.y > 1.0 - CropBottom))
        m = 0.0;

    // Setup mode: grayscale mask with visual guides. All indicators
    // exist only in this mode and can never reach the live output.
    if (ShowMask) {
        float3 outm = float3(m, m, m);

        // Redness targets tinted cyan. Shown only when Redness
        // reduction is above zero, so the preview stays plain black and
        // white when the feature is off. The tint tracks the gate only,
        // not the strength slider, so the targeted footprint stays
        // fully visible while tuning the threshold even at low strength.
        // Cyan is used because green is the sample box and red is the
        // crop guides.
        if (Redness > 0.0) {
            float2 rg = redness_gate(mycc, center, skinY);
            outm = lerp(outm, float3(0.10, 0.85, 0.95), saturate(rg.x * m));
        }

        // Region limit visualization: the cropped side is tinted
        // transparent red so it is unambiguous which side of each
        // guide line is excluded.
        if ((uv.x < CropLeft) || (uv.x > 1.0 - CropRight) ||
            (uv.y < CropTop)  || (uv.y > 1.0 - CropBottom))
            outm = lerp(outm, float3(0.85, 0.10, 0.10), 0.35);

        // Solid thin red guide line at each active crop boundary
        float2 gl = float2(px.x * 1.5, px.y * 1.5);
        if ((CropLeft   > 0.0005) && (abs(uv.x - CropLeft) <= gl.x))
            outm = float3(0.95, 0.15, 0.15);
        if ((CropRight  > 0.0005) && (abs(uv.x - (1.0 - CropRight)) <= gl.x))
            outm = float3(0.95, 0.15, 0.15);
        if ((CropTop    > 0.0005) && (abs(uv.y - CropTop) <= gl.y))
            outm = float3(0.95, 0.15, 0.15);
        if ((CropBottom > 0.0005) && (abs(uv.y - (1.0 - CropBottom)) <= gl.y))
            outm = float3(0.95, 0.15, 0.15);

        // Sample box outline drawn last so it stays visible on top.
        // The box is always the detection source now, so it always
        // draws in setup mode.
        float2 dpos = abs(uv - bcenter);
        float2 border = float2(px.x * 2.0, px.y * 2.0);
        if ((dpos.x <= bext.x) && (dpos.y <= bext.y) &&
            ((dpos.x > bext.x - border.x) || (dpos.y > bext.y - border.y)))
            outm = float3(0.15, 0.9, 0.25);
        return float4(outm, 1.0);
    }

    if (m <= 0.001) return orig;

    float3 outc = base;

    if ((Amount > 0.0) && (Size > 0.0)) {

    // Edge-preserving bilateral smoothing. Each neighbor is weighted by
    // color similarity to the center pixel, so blemishes and pores are
    // averaged away while strong edges such as eyes, brows, nostrils and
    // the face outline contribute almost nothing and stay sharp.
    float sigma  = lerp(0.32, 0.045, Detail);
    float sigma2 = 2.0 * sigma * sigma;

    float3 acc  = base;
    float  wsum = 1.0;

    float2 radi = float2(1.0, aspect) * Size * RADIUS * m;
    float  ang  = 0.0;
    float2 xy;
    float3 samp;
    float3 d;
    float  w;

    for (int i = 0; i < LOOP; i++) {
        sincos(ang, xy.x, xy.y);
        xy *= radi;

        samp = image.Sample(textureSampler, uv + xy).rgb;
        d = samp - base;
        w = exp(-dot(d, d) / sigma2);
        acc += samp * w; wsum += w;

        samp = image.Sample(textureSampler, uv - xy).rgb;
        d = samp - base;
        w = exp(-dot(d, d) / sigma2);
        acc += samp * w; wsum += w;

        xy *= 2.5;

        samp = image.Sample(textureSampler, uv + xy).rgb;
        d = samp - base;
        w = exp(-dot(d, d) / sigma2);
        acc += samp * w; wsum += w;

        samp = image.Sample(textureSampler, uv - xy).rgb;
        d = samp - base;
        w = exp(-dot(d, d) / sigma2);
        acc += samp * w; wsum += w;

        ang += ANGLE;
    }

    float3 smoothed = acc / wsum;
    outc = lerp(base, smoothed, saturate(Amount * m));

    }

    // Redness correction, chroma only. Runs on the smoothed result and
    // is independent of Smoothing strength, so it still works with
    // smoothing at zero.
    //
    // Excess red is measured as a signed projection onto a red axis
    // fitted in CbCr space: skin redness raises Cr and slightly lowers
    // Cb. Because the projection is signed, only pixels redder than the
    // sampled skin tone are pulled back; sallow or shadowed skin has a
    // negative projection and is never pushed redder.
    //
    // Only Cb and Cr move. The pixel keeps its own luma exactly, so
    // shading, contour and facial form survive and the result reads as
    // foundation rather than paint.
    if (Redness > 0.0) {
        float3 ycc = rgb2ycbcr(outc);
        float2 rg = redness_gate(ycc, center, skinY);

        float pull = saturate(Redness * rg.x * m);

        // Remove the excess along the red axis only. Chroma variation
        // perpendicular to that axis is left alone, so the skin keeps
        // its natural color life instead of going uniform.
        ycc.yz -= RED_AXIS * rg.y * pull;

        outc = ycbcr2rgb(ycc);
    }

    return float4(outc, orig.a);
}

technique Draw
{
    pass
    {
        vertex_shader = VSDefault(v_in);
        pixel_shader  = PassThrough(v_in);
    }
}
]]