import "package:app_flutter/main.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  testWidgets("layout principal renderiza componentes-chave", (tester) async {
    await tester.pumpWidget(const RouterCncApp());
    await tester.pumpAndSettle();

    expect(find.text("Importar DXF(s)"), findsOneWidget);
    expect(find.text("Importar STEP(s)"), findsOneWidget);
    expect(find.text("Nova chapa"), findsOneWidget);
    expect(find.text("Chapas"), findsOneWidget);
    expect(find.text("Pecas importadas"), findsOneWidget);
  });

  testWidgets("botao Nova chapa cria e ativa nova chapa", (tester) async {
    await tester.pumpWidget(const RouterCncApp());
    await tester.pumpAndSettle();

    expect(find.text("Chapa 1"), findsOneWidget);
    expect(find.text("Chapa 2"), findsNothing);

    final novaChapa = find.text("Nova chapa");
    await tester.ensureVisible(novaChapa);
    await tester.pumpAndSettle();
    await tester.tap(novaChapa);
    await tester.pumpAndSettle();

    expect(find.text("Chapa 2"), findsOneWidget);
  });

  testWidgets("botao Chapa monta estoque na chapa ativa", (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RouterCncHomePage(
          initialStock: [
            StockPiece(
              id: 1,
              code: "2F-TESTE",
              widthMm: 600,
              heightMm: 120,
              type: PieceType.dxf,
              quantity: 2,
              colorSeed: 42,
              sourcePath: "C:/fake/2F-TESTE.dxf",
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining("1 codigo(s) | 2 peca(s)"), findsOneWidget);

    final chapaButton = find.text("Chapa");
    await tester.ensureVisible(chapaButton);
    await tester.pumpAndSettle();
    await tester.tap(chapaButton);
    await tester.pumpAndSettle();

    expect(find.textContaining("0 codigo(s) | 0 peca(s)"), findsOneWidget);
    expect(find.textContaining("Pecas: 2 |"), findsOneWidget);
  });

  testWidgets("toggle 2D responde clique", (tester) async {
    await tester.pumpWidget(const RouterCncApp());
    await tester.pumpAndSettle();

    final checkbox = find.byType(Checkbox).first;
    await tester.ensureVisible(checkbox);
    await tester.pumpAndSettle();

    expect(tester.widget<Checkbox>(checkbox).value, isTrue);

    await tester.tap(checkbox);
    await tester.pumpAndSettle();

    expect(tester.widget<Checkbox>(checkbox).value, isFalse);
  });

  testWidgets("tecla Delete remove chapa ativa", (tester) async {
    await tester.pumpWidget(const RouterCncApp());
    await tester.pumpAndSettle();

    final novaChapa = find.text("Nova chapa");
    await tester.ensureVisible(novaChapa);
    await tester.pumpAndSettle();
    await tester.tap(novaChapa);
    await tester.pumpAndSettle();
    expect(find.text("Chapa 2"), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();

    expect(find.text("Chapa 2"), findsNothing);
    expect(find.text("Chapa 1"), findsOneWidget);
  });
}
