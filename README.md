# Router CNC Flutter (C++ Core)

Aplicativo desktop em Flutter/Dart com layout inspirado no Router CNC original, preparado para usar núcleo nativo em C++ via FFI para rotinas de alto desempenho.

## Objetivo

- manter o layout e fluxo visual próximos do projeto original
- migrar base da interface para Flutter desktop
- preparar arquitetura para processamento pesado em C++ (sem Electron)

## Arquitetura

- **UI/Estado**: Flutter (`lib/main.dart`)
- **Ponte nativa**: Dart FFI (`lib/src/native/router_core.dart`)
- **Núcleo C++**: DLL `router_core` (`windows/router_core/*`)
- **Build Windows**: CMake com cópia automática da DLL para o runner

## Estrutura

```text
lib/
  main.dart
  src/native/router_core.dart
windows/
  CMakeLists.txt
  runner/CMakeLists.txt
  router_core/
    CMakeLists.txt
    router_core.h
    router_core.cpp
test/
  widget_test.dart
  router_core_test.dart
```

## Dependências

- Flutter SDK `3.41.5` (stable) ou compatível
- Dart SDK `3.11.3` (via Flutter)
- CMake e Visual Studio Build Tools para build Windows
- pacote Dart: `ffi`

## Instalação

### 1) Com Puro (recomendado)

```powershell
winget install --id pingbird.Puro -e --accept-package-agreements --accept-source-agreements
```

Depois:

```powershell
# caminho padrão do puro.exe instalado por winget
$puro = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\pingbird.Puro_Microsoft.Winget.Source_8wekyb3d8bbwe\puro.exe"
& $puro create stable stable
```

### 2) Dependências do projeto

```powershell
cd C:\Users\USER\Downloads\App_Flutter
& $puro -e stable flutter pub get
```

## Execução (Windows)

```powershell
cd C:\Users\USER\Downloads\App_Flutter
& $puro -e stable flutter run -d windows
```

## Testes e validações

```powershell
cd C:\Users\USER\Downloads\App_Flutter
& $puro -e stable flutter analyze
& $puro -e stable flutter test
& $puro -e stable flutter build windows --debug
```

## Funcionalidades já entregues

- topbar com ações principais (`Importar`, `Enquadrar`, `Editar corte`, `Simular corte`)
- painel lateral esquerdo de chapas
- viewport central com visual 2D/3D simplificado
- painel direito de peças importadas com busca e grid de cards
- integração nativa C++ funcionando por FFI (com fallback em Dart)

## Próximos passos para paridade total

- portar importação DXF/STEP para núcleo C++
- portar nesting/montagem de chapas para C++
- portar pipeline de toolpath/simulação CNC completa
- renderer 3D final com interação de câmera equivalente ao projeto original

## Licença

MIT License

Copyright (c) 2026 Paulo Augusto

## Atualizacao (23/03/2026)

- layout original mantido, sem alteracao estrutural de UI
- ajuste no teste de widget para garantir interacao com o checkbox `2D` mesmo em viewport pequena (800x600)
- validacao final executada com `analyze`, `test` e `build windows --debug`

## Atualizacao (24/03/2026)

- botoes da topbar agora executam acoes reais (`Importar`, `Enquadrar`, `Limpar`, `Nova chapa`, `Editar chapa`, `Editar corte`, `Simular corte`)
- importacao DXF/STEP funcional em Windows com seletor nativo (PowerShell + OpenFileDialog), sem depender de plugin que exige symlink
- painel de chapas destravado: selecao da chapa ativa e criacao dinamica de novas chapas
- painel de pecas destravado: filtro por tipo, busca por codigo, ajuste de quantidade e montagem por `Chapa` ou `Montar chapas`
- viewport 2D/3D interativo: zoom por scroll, pan por arraste, rotacao 3D por arraste e selecao de peca em 2D
- montagem de pecas consome estoque do card direito e atualiza contadores/tempo de operacao
- validado com `flutter analyze`, `flutter test` e `flutter build windows --debug`

## Atualizacao (23/03/2026 - Correcoes de importacao/viewport)

- corrigida a importacao multipla de DXF/STEP no seletor nativo (agora usa JSON do `OpenFileDialog` e parse robusto no Dart)
- implementada exclusao por teclado (`Delete`):
  - remove peca selecionada da chapa ativa
  - sem peca selecionada, remove a chapa ativa (ou limpa a unica chapa restante)
- viewport 3D melhorado com grade major/minor e eixos, com visual mais limpo e leitura melhor
- render 3D agora mostra todas as chapas (ativa destacada) para facilitar orientacao
- adicionado parser DXF leve no Flutter para `LINE`, `LWPOLYLINE`, `POLYLINE/VERTEX`, `CIRCLE` e `ARC`
- desenho das pecas DXF no card e na chapa agora usa geometria real parseada do arquivo (fallback para retangulo quando necessario)
- novos testes automatizados:
  - parser de geometria DXF
  - exclusao de chapa via tecla `Delete`
- validacao executada novamente:
  - `flutter analyze`
  - `flutter test`
  - `flutter build windows --debug`

## Atualizacao (23/03/2026 - Ajuste visual 3D estilo projeto original)

- corrigido conflito visual de profundidade no 3D (grade e chapa em planos distintos)
- viewport 3D refeito para o estilo do projeto de referencia:
  - grade de chao em plano horizontal
  - eixo vertical separado
  - chapa em pe acima da grade
  - pecas desenhadas na face frontal da chapa
- melhorado enquadramento de camera 3D com angulo inicial mais proximo do visual original
- mantida renderizacao leve para preservar fluidez
- validado com:
  - `flutter analyze`
  - `flutter test`
  - `flutter build windows --debug`

## Atualizacao (24/03/2026 - Refino de viewport 3D e UI)

- fechado o volume da espessura da chapa no 3D (frente, traseira e conexoes), eliminando aspecto de vetor aberto
- removidas as linhas de eixos RGB (X/Y/Z) da viewport 3D
- adicionada linha interna de borda/espacamento da chapa (valor de `Espacamento (mm)` do `Editar chapa`)
- corrigida projecao 3D para evitar artefatos/linhas quebradas em orbitacao:
  - descarte de pontos fora de faixa de projecao
  - desenho seguro de linhas/poligonos com clipping
- viewport central agora fica estritamente dentro do card (clip ativo), sem desenhar por cima da barra superior/laterais
- `Editar chapa` recebeu opcao `Todas` para aplicar configuracao em todas as chapas de uma vez
- miniaturas do card de pecas sem moldura quadrada da peca (mantido apenas o desenho da geometria)
- validado com:
  - `flutter analyze`
  - `flutter test`
  - `flutter build windows --debug`

## Atualizacao (24/03/2026 - Geometria sem caixas e espessura para tras)

- pecas DXF na chapa agora exibem apenas a geometria (sem retangulo/base quadrada de fundo)
- espessura da chapa passou a fechar para tras da face frontal
- vetores/arestas da chapa unificados em azul forte na frente, lados e traseira
- validado com:
  - `flutter analyze`
  - `flutter test`
  - `flutter build windows --debug`

## Atualizacao (24/03/2026 - Orientacao frontal + espessura das pecas)

- orientacao 3D da chapa ajustada para considerar a face frontal como referencia do enquadramento
- vetores frente/traseira/laterais da chapa padronizados com o mesmo azul forte
- pecas sem geometria DXF agora tambem sao extrudadas (frente + traseira + arestas), mantendo preenchimento transparente
- espessura visual das pecas alinhada com a espessura da chapa
- validado com:
  - `flutter analyze`
  - `flutter test`
  - `flutter build windows --debug`
