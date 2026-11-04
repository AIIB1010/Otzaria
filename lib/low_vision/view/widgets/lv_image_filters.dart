import 'package:flutter/widgets.dart';

/// מתאם צבע שמחדד עמוד מצולם: הופך לגווני אפור ומגביר ניגודיות סביב האמצע,
/// כך שאותיות דהויות כהות יותר והרקע בהיר יותר. [contrast] = 1 אינו משנה כלום.
ColorFilter lvSharpenFilter(double contrast) {
  const r = 0.2126;
  const g = 0.7152;
  const b = 0.0722;
  final c = contrast;
  final t = 128 * (1 - c);
  return ColorFilter.matrix([
    c * r, c * g, c * b, 0, t, //
    c * r, c * g, c * b, 0, t,
    c * r, c * g, c * b, 0, t,
    0, 0, 0, 1, 0,
  ]);
}
