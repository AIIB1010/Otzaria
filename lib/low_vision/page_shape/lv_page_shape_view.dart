import 'package:flutter/material.dart';
import 'package:otzaria/low_vision/page_shape/lv_html_text.dart';
import 'package:otzaria/low_vision/page_shape/lv_page_shape_loader.dart';

/// רוחב ה"עמוד" הווירטואלי בפיקסלים לוגיים. הגופנים בו בגודל דפוס רגיל; הגדלה
/// נעשית בזום של המשתמש, והטקסט נשאר חד (וקטורי) בכל גודל.
const double kLvPageWidth = 1800;

/// שליטה בתצוגת צורת הדף מבחוץ (כפתורי הגדלה, גלילה קטנה של החוגה).
class LvPageShapeController {
  void Function(double factor)? _zoom;
  void Function(double fractionOfViewport)? _scroll;
  VoidCallback? _fit;

  void zoomIn() => _zoom?.call(1.25);
  void zoomOut() => _zoom?.call(0.8);

  /// גלילה אנכית: [direction] חיובי = למטה, כחמישית מגובה התצוגה.
  void scroll(double direction) => _scroll?.call(direction * 0.2);

  /// חזרה להתאמת רוחב העמוד למסך.
  void fitToWidth() => _fit?.call();
}

/// "צורת הדף": הטקסט הראשי במרכז והמפרשים בצדדים ובתחתית, בעמוד אחד שאפשר
/// לתפוס, לגרור לכל כיוון (גם באלכסון) ולהגדיל בלי הגבלה, כמו עמוד מצולם.
class LvPageShapeView extends StatefulWidget {
  const LvPageShapeView({
    super.key,
    required this.data,
    required this.controller,
    required this.foreground,
    required this.background,
    required this.showNikud,
    required this.glide,
  });

  final LvPageShapeData data;
  final LvPageShapeController controller;
  final Color foreground;
  final Color background;
  final bool showNikud;
  final bool glide;

  @override
  State<LvPageShapeView> createState() => _LvPageShapeViewState();
}

const double _minZoom = 0.05;
const double _maxZoom = 40;

class _LvPageShapeViewState extends State<LvPageShapeView> {
  final _transform = TransformationController();
  Size _viewport = Size.zero;
  bool _needsFit = true;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    widget.controller
      .._zoom = _zoomBy
      .._scroll = _scrollBy
      .._fit = _fit;
  }

  @override
  void didUpdateWidget(LvPageShapeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _attach();
    if (!identical(oldWidget.data, widget.data)) _needsFit = true;
  }

  @override
  void dispose() {
    widget.controller
      .._zoom = null
      .._scroll = null
      .._fit = null;
    _transform.dispose();
    super.dispose();
  }

  double get _fitScale =>
      _viewport.width <= 0 ? 1.0 : _viewport.width / kLvPageWidth;

  void _fit() {
    final k = _fitScale;
    _transform.value = Matrix4.diagonal3Values(k, k, 1);
  }

  void _zoomBy(double factor) {
    if (_viewport.isEmpty) return;
    final current = _transform.value.getMaxScaleOnAxis();
    final target = (current * factor).clamp(_minZoom, _maxZoom);
    final k = target / current;
    final center = Offset(_viewport.width / 2, _viewport.height / 2);
    final change =
        Matrix4.translationValues(center.dx, center.dy, 0) *
        Matrix4.diagonal3Values(k, k, 1) *
        Matrix4.translationValues(-center.dx, -center.dy, 0);
    _transform.value = change * _transform.value;
  }

  void _scrollBy(double fractionOfViewport) {
    if (_viewport.isEmpty) return;
    final dy = _viewport.height * fractionOfViewport;
    _transform.value = Matrix4.translationValues(0, -dy, 0) * _transform.value;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        _viewport = box.biggest;
        if (_needsFit) {
          _needsFit = false;
          _fit();
        }
        return ColoredBox(
          color: widget.background,
          child: ClipRect(
            child: InteractiveViewer(
              transformationController: _transform,
              constrained: false,
              minScale: _minZoom,
              maxScale: _maxZoom,
              boundaryMargin: const EdgeInsets.all(kLvPageWidth),
              // ללא תנופה: העמוד נעצר כשהאצבע נעצרת, כמו ספר מתחת למצלמה.
              interactionEndFrictionCoefficient: widget.glide
                  ? 0.0000135
                  : 1e-14,
              child: _page(),
            ),
          ),
        );
      },
    );
  }

  Widget _page() {
    final mainStyle = TextStyle(
      color: widget.foreground,
      fontSize: 38,
      height: 1.45,
      fontWeight: FontWeight.w500,
    );
    final commentaryStyle = mainStyle.copyWith(fontSize: 28, height: 1.4);

    Widget richLine(String html, TextStyle style) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text.rich(
        TextSpan(
          children: lvHtmlSpans(html, style, showNikud: widget.showNikud),
          style: style,
        ),
      ),
    );

    Widget panelBox(LvPanelData panel) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.only(bottom: 6),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: widget.foreground, width: 3),
            ),
          ),
          child: Text(
            panel.title,
            style: commentaryStyle.copyWith(
              fontWeight: FontWeight.w900,
              fontSize: 30,
            ),
          ),
        ),
        for (final entry in panel.entries) richLine(entry, commentaryStyle),
      ],
    );

    final right = widget.data.panel(LvPanelSlot.right);
    final left = widget.data.panel(LvPanelSlot.left);
    final bottom = widget.data.panel(LvPanelSlot.bottom);
    final bottomSecond = widget.data.panel(LvPanelSlot.bottomSecond);

    final sideFlex = (right != null && left != null) ? 28 : 36;
    final mainFlex = (right != null && left != null)
        ? 44
        : (right != null || left != null)
        ? 64
        : 100;

    Widget divider() => Container(
      width: 3,
      margin: const EdgeInsets.symmetric(horizontal: 18),
      color: widget.foreground.withValues(alpha: 0.6),
    );

    final mainColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in widget.data.mainLines)
          if (line.trim().isNotEmpty) richLine(line, mainStyle),
      ],
    );

    // ב-RTL הילד הראשון בשורה הוא הימני: ימין, אמצע, שמאל.
    final top = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (right != null) ...[
          Expanded(flex: sideFlex, child: panelBox(right)),
          divider(),
        ],
        Expanded(flex: mainFlex, child: mainColumn),
        if (left != null) ...[
          divider(),
          Expanded(flex: sideFlex, child: panelBox(left)),
        ],
      ],
    );

    final bottomPanels = [?bottom, ?bottomSecond];

    return SizedBox(
      width: kLvPageWidth,
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            top,
            if (bottomPanels.isNotEmpty) ...[
              Container(
                height: 3,
                margin: const EdgeInsets.symmetric(vertical: 28),
                color: widget.foreground.withValues(alpha: 0.6),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < bottomPanels.length; i++) ...[
                    if (i > 0) divider(),
                    Expanded(child: panelBox(bottomPanels[i])),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
