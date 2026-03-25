import "package:app_flutter/main.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("parseDxfGeometry le LINE e LWPOLYLINE", () {
    const dxf = '''
0
SECTION
2
ENTITIES
0
LINE
8
0
10
0
20
0
11
100
21
0
0
LWPOLYLINE
8
0
90
4
70
1
10
0
20
0
10
100
20
0
10
100
20
50
10
0
20
50
0
ENDSEC
0
EOF
''';

    final geometry = parseDxfGeometry(dxf);
    expect(geometry, isNotNull);
    expect(geometry!.widthMm, closeTo(100, 0.0001));
    expect(geometry.heightMm, closeTo(50, 0.0001));
    expect(geometry.polylines.length, greaterThanOrEqualTo(2));
  });

  test("parseDxfGeometry le CIRCLE", () {
    const dxf = '''
0
SECTION
2
ENTITIES
0
CIRCLE
8
0
10
300
20
200
40
75
0
ENDSEC
0
EOF
''';

    final geometry = parseDxfGeometry(dxf);
    expect(geometry, isNotNull);
    expect(geometry!.widthMm, closeTo(150, 1));
    expect(geometry.heightMm, closeTo(150, 1));
    expect(geometry.polylines.single.closed, isTrue);
  });
}
