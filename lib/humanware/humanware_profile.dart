/// Constants for the dedicated close-range HumanWare edition.
///
/// This is intentionally not a normal phone accessibility profile.  The
/// device is used from very close range, so ordinary Material touch targets
/// and text scaling remain too small on a 16-inch display.
const double kHumanWareMinimumTextScale = 3.0;

/// Kept as a getter so the compiler does not treat the desktop-oriented tour
/// branch as dead code; the same source can still be reviewed and tested.
bool get isHumanWareEdition => true;
