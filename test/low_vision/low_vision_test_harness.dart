import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/low_vision/cubit/low_vision_cubit.dart';
import 'package:otzaria/low_vision/input/lv_key_scope.dart';
import 'package:otzaria/low_vision/view/lv_navigation.dart';
import 'package:otzaria/low_vision/view/lv_shell_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LvHarness {
  LvHarness(this.cubit, this.router, this.shell);

  final LowVisionCubit cubit;
  final LvKeyRouter router;
  final LvShellController shell;

  void dispose() {
    router.dispose();
    shell.dispose();
    cubit.close();
  }
}

/// מציג [home] בתוך אותם ספקים שמספק [LowVisionRoot], על מסך רחב כמו Reveal.
Future<LvHarness> pumpLowVision(
  WidgetTester tester,
  Widget home, {
  void Function(LowVisionCubit cubit)? setup,
  ThemeData? theme,
  Key? boundaryKey,
  Size size = const Size(1920, 1080),
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final cubit = LowVisionCubit();
  await cubit.load();
  setup?.call(cubit);
  final router = LvKeyRouter(cubit);
  final shell = LvShellController();
  final harness = LvHarness(cubit, router, shell);
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    MultiRepositoryProvider(
      key: UniqueKey(),
      providers: [
        RepositoryProvider<LvShellController>.value(value: shell),
        RepositoryProvider<LvKeyRouter>.value(value: router),
      ],
      child: BlocProvider<LowVisionCubit>.value(
        value: cubit,
        child: MaterialApp(
          theme: theme,
          debugShowCheckedModeBanner: false,
          builder: boundaryKey == null
              ? null
              : (context, child) =>
                    RepaintBoundary(key: boundaryKey, child: child),
          locale: const Locale('he', 'IL'),
          supportedLocales: const [Locale('he', 'IL')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          onGenerateRoute: (_) => lvRoute<void>(home),
        ),
      ),
    ),
  );
  await tester.pump();
  return harness;
}
