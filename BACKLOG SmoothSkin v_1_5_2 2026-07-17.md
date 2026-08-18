# SmoothSkin Backlog

Current release: v1.5.1

## Planned

### B5. Sample region shape (oval or rectangle)
A square region is a poor fit for oval faces. A rectangle or ellipse
would cover more skin and less non-skin at the same size. The control
scheme for size and proportions is to be discussed.

Field finding (v1.5.1): larger box outperforms a small centered box.
More sample area means the skin cluster has more votes, so a slight
move shifts a smaller fraction of taps onto non-skin and the center
holds. This is real and repeatable in testing. The guidance is to size
the box as large as possible while it still stays fully on skin
through the normal range of head movement (still on the cheek at the
ends of a side-to-side turn, not just head-on).

The limit that motivates B5: a bigger box helps only until its edges
permanently include non-skin (hairline, brows, jaw shadow, background
past the cheek). Past that the box adds standing contamination rather
than skin votes, and the estimate sits slightly off skin all the time.
The failure mode is quiet: the mask does not breathe, it just masks a
little non-skin or misses a little skin, which is easy to miss because
it does not flicker. Because the box is a square and faces are taller
than wide, the binding constraint is horizontal: cheeks run out before
forehead-to-chin does, so vertical coverage is paid for with sideways
spill onto non-skin. A tall rectangle or ellipse would lift that
constraint, giving more sample area without the edges hitting hairline
and background. This is now a concrete, tested reason to build B5
rather than a speculative one.

Status: build B5 if and when the user wants more sample area than a
square can give without spilling. The trigger to watch for is wanting
to size up further but seeing the square start to include non-skin at
its edges. Until that itch appears in practice, the larger-square
guidance above is sufficient.

Circle variant considered and set aside (v1.5.1): a circle keeps a
single size control, so it avoids the extra tuning surface an oval or
rectangle needs, which is appealing on the simplicity axis. But it is
low-value here for two reasons. First, the v1.5.1 spatial weighting
already applies a Gaussian falloff from the box center (corner taps
weigh about 0.14 vs 1.0 at center), so the effective sample region is
already a soft-edged circle. A literal circle would mostly formalize
behavior the weighting already provides, trimming corners that already
count for almost nothing. Second, and more important, a circle does
not change the region's aspect: it is the same width and height as its
bounding square, minus corners. The actual prize in B5 is aspect, a
tall shape that fits a face and covers more skin with less non-skin
spill. A circle gives up that benefit while keeping only the corner
de-emphasis that is already handled. So the aspect-changing rectangle
or ellipse remains the only shape variant worth building; the circle
is cheap but largely redundant and is not planned.

## Deferred / exploratory

### Temporal smoothing of the sampled center
Averaging the sampled center across frames would further steady the
mask. The shader has no state between frames, so true cross-frame
averaging needs either CPU-side sampling in Lua (GPU readback per
tick, heaviest) or a persistent 1-pixel render target blended each
frame (medium complexity, adds a pass). Both are more architecture
than the current all-in-shader design.

Gating (updated v1.5.1): the v1.5.1 spatial-robustness work (center-
weighted taps, wider grid, third rejection pass, tighter width) was
chosen over temporal smoothing because the user's lighting is fixed,
which removes temporal's main advantage (tracking lighting change) and
leaves box contamination as the real cause of breathing, a robustness
problem, not a memory problem. Field testing of v1.5.1 was positive.
Build temporal smoothing only if, after B5 and the larger-box
guidance, the mask still breathes more than acceptable during normal
movement. If pursued, prefer the persistent-texture blend over CPU
readback. Note: temporal smoothing cannot rescue a box parked fully
off skin either; that is a placement matter no smoothing solves.

## Scope decisions (non-goals)

- Not building for detection edge cases: heavy makeup, very dark skin
  tones in low-light environments that cannot be chroma-separated from
  the background, and skin conditions such as vitiligo. The chroma
  detection approach targets the common case; these would need
  fundamentally different (ML-based, native plugin) detection.
- All on-screen indicators (sample box, crop guides, any future
  overlays) render only while "Show detection mask" is on, never on
  live output.

## Shipped

- v1.5.1: Spatial robustness for the sample-box center. Taps weighted
  by distance from box center, wider tap grid, third outlier-rejection
  pass, tighter rejection width. Steadies the mask against brief
  partial box slips during head movement, no new controls. Field
  tested well. (Chosen over temporal smoothing given fixed lighting.)
- v1.5.0: Unified detection. Retired the Auto/Manual dropdown (B6); the
  sample box now always sets the center, all detection controls in one
  group, warmth back to a trim on the sampled center. New "Mask
  tightness" slider as the primary closed-loop knob, scaling the
  acceptance envelope symmetrically about a neutral 0.5 midpoint.
  Supersedes B6.
- v1.4.1: Fixed a get_properties failure and the Detection mode groups
  not showing the correct one on panel open (initial visibility now
  read from the filter data table OBS actually passes).
- v1.4.0: Contrast-robust sample box with 5x5 taps and two
  outlier-rejection passes (B4). Detection mode dropdown separating
  Auto (sample box) and Manual (skin tone slider) with mode-dependent
  control visibility (B6). Note: the B6 dropdown was later retired in
  v1.5.0 in favor of unified detection; the box-plus-tightness model
  replaced the two-mode split.
- v1.3.0: Region limit crop guides (B3): solid thin red boundary lines
  plus transparent red tint over the cropped side, setup mode only.
  Mask preview description updated to user-supplied text.
- v1.2.0: Sample box auto-calibration (B2) with setup-mode green box
  indicator, mask preview group with help label and tooltip (B1),
  warmth slider repurposed as a trim on the sampled center.
- v1.1.0: Background rejection saturation gate, single skin tone warmth
  slider, grouped settings panels.
- v1.0.0: Initial release. YCbCr chroma skin detection, bilateral
  edge-preserving smoothing, mask preview, region limits.