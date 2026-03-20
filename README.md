# DXFs 3D Viewer com Layout por Chapas

Visualizador 3D para DXF e STEP/STP com fluxo de nesting manual em chapas, com DXF em modo browser/WebGL (GPU) e sem seletor CPU no frontend.

## Objetivo do projeto

Permitir importacao e visualizacao 3D de pecas DXF/STEP com um layout de producao orientado a chapas CNC:

- criar multiplas chapas
- selecionar chapa ativa
- posicionar pecas automaticamente dentro da area util da chapa
- mover pecas para outra chapa sem sair dos limites configurados

## Arquitetura do sistema

### Frontend (browser)

- `index.html`: estrutura da tela (toolbar, dock de chapas, viewport 3D, modal de edicao de chapa)
- `styles.css`: tema e layout responsivo
- `app.js`: renderizacao Three.js, importacao DXF browser-only, importacao STEP, selecao/transform, estado de chapas
- `app.js`: inclui ajuste dinamico de `near/far` da camera para reduzir artefatos de profundidade em zoom distante
- `app.js`: sincroniza espessura das pecas DXF com a espessura da chapa (STEP permanece com logica propria)
- `sheet-layout.js`: funcoes puras de layout (origem de chapas, area util, encaixe sem colisao)
- `dxf-worker.js`: parse DXF em paralelo no browser

### Backend local (Python)

- `server.py`: servidor HTTP para arquivos estaticos e APIs de parse
- `run_server.py`: ponto de entrada simples para subir o servidor

### Testes

- `tests/sheet-layout.test.mjs`: testes automatizados das regras de layout de chapas

## Dependencias necessarias

### Python

- Python 3.12 (recomendado)
- `ezdxf==1.4.2` (obrigatorio para DXF)
- `cadquery` (opcional, necessario para STEP/STP)
- `cupy-cuda12x` (opcional, apenas para uso direto no backend Python)

### Node.js (somente para testes)

- Node.js 18+ (usado para `node --test`)

## Instalacao

No PowerShell, dentro da pasta do projeto:

```powershell
cd C:\Users\USER\Downloads\Ver_DXF\dxf-3d-viewer-main
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m pip install cadquery
```

## Execucao

### Servidor completo (DXF + STEP + APIs)

```powershell
cd C:\Users\USER\Downloads\Ver_DXF\dxf-3d-viewer-main
.\.venv\Scripts\python.exe .\run_server.py
```

Abra no navegador:

- `http://127.0.0.1:5173`

### Execucao direta do servidor

```powershell
.\.venv\Scripts\python.exe .\server.py --host 127.0.0.1 --port 5173 --dir .
```

## Como usar (exemplo rapido)

1. Clique em `Importar DXF(s)` ou `Importar STEP(s)`.
2. Use `Nova chapa` para criar outra chapa.
3. Clique em uma chapa no painel lateral para ativar.
4. As chapas ficam em layout circular no viewport; ao selecionar outra chapa, ocorre transicao para trazer a selecionada ao centro (sem giro continuo).
5. Use `Mover para chapa` para enviar a peca selecionada para a chapa ativa.
6. Use `Editar chapa` para ajustar largura, altura, margens e espacamento.
7. No modal:
   - `Aplicar`: altera somente a chapa ativa.
   - `Aplicar em todas`: altera todas as chapas atuais e vira padrao para novas chapas.
8. Clique em `Enquadrar (Fit)` para centralizar a visualizacao.

## Principais modulos/funcoes

- `assignPartToSheet` (`app.js`): aloca peca em chapa com fallback para nova chapa
- `relayoutSheetPieces` (`app.js`): reorganiza pecas apos alterar parametros da chapa
- `findPlacementOnSheet` (`sheet-layout.js`): calcula primeira posicao valida sem colisao
- `getSheetUsableBounds` (`sheet-layout.js`): calcula area util com margens

## Testes automatizados

Executar:

```powershell
npm test
```

Cobertura atual dos testes:

- normalizacao de configuracao da chapa
- calculo de origem entre chapas
- calculo de area util
- deteccao de colisao com espacamento
- busca de posicao valida para encaixe
- falha esperada quando a peca nao cabe

## Endpoints locais

- `POST /api/parse-dxf`
- `POST /api/parse-step`

## Licenca

Este projeto esta sob a licenca MIT. Veja o arquivo `LICENSE` para os detalhes completos.
