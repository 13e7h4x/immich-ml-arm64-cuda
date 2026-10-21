# Duplicate Quality Worker Specification

## Initial operating mode

The first release is read-only. It retrieves native Immich duplicate groups, evaluates eligible image candidates and emits ranked recommendations with human-readable reasons. It does not resolve groups or trash assets.

## TIFF exclusion

TIFF assets are excluded case-insensitively by both filename extension and MIME type:

- `.tif`
- `.tiff`
- `image/tiff`
- `image/x-tiff`

The exclusion is group-wide: if any member of a duplicate group is TIFF, the worker skips the entire group. This prevents it from recommending deletion of a JPEG/HEIC counterpart while silently protecting the TIFF, and ensures TIFF-containing groups remain untouched for manual handling.

For a skipped group, the report records:

```json
{
  "status": "skipped",
  "reason": "contains_tiff"
}
```

A TIFF-containing group must never be downloaded for visual scoring and must never be included in a duplicate-resolution API payload.

## Other hard safety gates

Skip automatic resolution when a group contains:

- RAW assets or RAW/JPEG pairs
- edited/original variants
- live-photo components
- video assets
- locked assets
- favourites
- external-library assets
- ambiguous scores or an insufficient score margin

## Candidate score

For eligible raster images:

- 30% sharpness/focus
- 25% pixel resolution
- 20% perceptual no-reference quality
- 10% exposure quality
- 10% compression quality
- 5% metadata completeness

Every recommendation includes the component scores and a plain-language explanation.
