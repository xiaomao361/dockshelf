import 'package:dockshelf/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('starts with an empty session shelf', (tester) async {
    await tester.pumpWidget(const DockShelfApp());

    expect(find.text('搁这儿 · 拖放探针'), findsOneWidget);
    expect(find.textContaining('暂无文件'), findsOneWidget);
    expect(find.textContaining('0/20'), findsOneWidget);
  });
}
