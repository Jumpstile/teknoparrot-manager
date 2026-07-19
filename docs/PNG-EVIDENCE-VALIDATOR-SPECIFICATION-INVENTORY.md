# PNG Evidence Validator Specification Inventory

Governing source: W3C Portable Network Graphics (PNG) Specification, Third Edition, sections 5.2-5.6, 11.2-11.3, and 15.3. This inventory defines the complete intended scope of `Test-TPMPngStructure`.

## In scope

- Exact 8-byte signature; chunk framing; big-endian lengths; 2^31-1 length ceiling; bounds and overflow-safe offsets; CRC-32 over type plus data; no trailing bytes.
- Four ASCII-letter chunk types, raw-bit property interpretation, uppercase reserved third letter, case-sensitive type identity, unknown critical rejection, and unknown ancillary acceptance.
- Static critical structure: one first IHDR, optional PLTE, one or more consecutive IDAT chunks, one terminal zero-length IEND.
- IHDR length, nonzero 1..2^31-1 dimensions, color-type/bit-depth table, compression, filter, and interlace methods.
- PLTE ordering, uniqueness, color-type rules, entry size/count, and indexed bit-depth capacity.
- Registered static ancillary ordering and multiplicity from specification Table 7: cHRM, cICP, gAMA, iCCP, mDCV, cLLI, sBIT, sRGB before PLTE/IDAT; bKGD, hIST, tRNS after required PLTE and before IDAT; eXIf, pHYs, sPLT before IDAT; tIME singleton; text chunks repeatable anywhere.
- APNG chunks acTL/fcTL/fdAT are rejected explicitly because certification screenshots are static evidence.

## Deliberately out of scope

- Deflate/filter/scanline/sample validation and palette-index use. The subsequent GDI+ RawFormat and forced LockBits full-frame decode layer owns pixel decoding.
- Internal semantic interpretation of variable ancillary payloads (ICC/Exif/text/profile decompression, colorimetric meaning, timestamps, suggested palettes). They do not establish screenshot pixel completeness; bounds and CRC still protect their bytes.
- Encoder/editor recommendations, safe-to-copy behavior, and SHOULD-level iCCP/sRGB preference. This component neither writes nor edits an input PNG.
- APNG frame sequencing and animation decoding. Animated files are rejected rather than partially validated.

## Layering invariant

Structural success never alone produces Captured status. RawFormat must be PNG, dimensions must be positive, LockBits must decode the full frame, resources must be disposed, and the file must be unlocked. Any failure remains Failed and does not affect certification scoring.
