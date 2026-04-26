# protocol-fuzzing

Boofuzz-focused protocol/session fuzzing image.

Default mode runs a toy local TCP service and a deterministic campaign that
captures a known failing case. Real campaigns can mount a custom
`BOOFUZZ_SCRIPT` and target startup command.
