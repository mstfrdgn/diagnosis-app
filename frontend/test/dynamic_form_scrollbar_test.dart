import 'package:diagnostic_app/models/orange_variable.dart';
import 'package:diagnostic_app/widgets/dynamic_form.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Companion to `scrollbar_controller_test.dart`, which covers the screens.
/// [DynamicForm] was missed by that pass because it is a widget rather than a
/// screen, and it is the one the user actually scrolls — the input screen
/// builds one per group.
void main() {
  List<OrangeVariable> fields(int count) => [
        for (var i = 0; i < count; i++)
          OrangeVariable(
            name: 'field_$i',
            type: VariableType.continuous,
            role: VariableRole.feature,
          ),
      ];

  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: Form(child: child)),
      );

  testWidgets('scrolling a DynamicForm does not assert', (tester) async {
    // The PrimaryScrollController is inherited on mobile, so the missing
    // controller is invisible under flutter_test's default platform. This app
    // ships on desktop, where it is not. The override must be undone inside
    // the body: the framework checks for leaked debug vars before tearDown.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      tester.view.physicalSize = const Size(700, 500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        wrap(
          DynamicForm(
            variables: fields(30),
            values: ValueNotifier<Map<String, dynamic>>({}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('sibling DynamicForms in an IndexedStack each scroll cleanly',
      (tester) async {
    // How the input screen actually builds them: IndexedStack builds every
    // child, so all the lists are attached at once. A controller shared across
    // them would assert here even though the single-form case passes.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      tester.view.physicalSize = const Size(700, 500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final values = ValueNotifier<Map<String, dynamic>>({});
      var index = 0;

      await tester.pumpWidget(
        wrap(
          StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                TextButton(
                  onPressed: () => setState(() => index = 1),
                  child: const Text('next group'),
                ),
                Expanded(
                  child: IndexedStack(
                    index: index,
                    children: [
                      DynamicForm(variables: fields(30), values: values),
                      DynamicForm(variables: fields(30), values: values),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('next group'));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView).last, const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
