# Face Capture Lab

Aplicação **experimental** em Flutter para testar captura facial orientada,
posicionamento em tempo real, movimentos da cabeça e (futuramente) comparação
com fotos de documentos. Prova de conceito — **não** é um sistema de
autenticação biométrica certificado nem pronto para produção.

Todo o processamento é local. Nenhuma imagem ou embedding é enviado a
servidores, e dados faciais não são gravados em logs.

## Estado das fases

| Fase | Conteúdo | Situação |
|------|----------|----------|
| A | Câmera frontal, ML Kit, moldura oval, diagnóstico de ângulos | Implementada; executada em Moto G53 5G (Android) |
| B | Mensagens de posicionamento e captura frontal automática | Implementada; testes unitários ok; **aguardando teste no aparelho** |
| C | Sequência de múltiplos ângulos | Pendente |
| D | Foto do documento e comparação por embeddings | Pendente |
| E | Refinamento visual, desempenho e testes | Pendente |

iOS: configuração (permissões no `Info.plist`) incluída, mas **não compilado
nem testado** (ambiente de desenvolvimento é Windows).

## Como executar

```bash
flutter pub get
flutter run          # com um Android conectado (depuração USB ativa)
flutter test         # testes unitários (sem câmera)
flutter analyze
```

Requisitos: Flutter 3.41.x (Dart 3.11), Android 7.0+ (minSdk 24).

## Versões das dependências

As versões mais recentes no pub.dev (`camera` 0.12.2,
`google_mlkit_face_detection` 1.0.2, `face_detection_tflite` 6.10.1) exigem
Flutter ≥ 3.44. Com o Flutter 3.41.9 instalado, foram usadas as versões
**mais recentes compatíveis**:

| Pacote | Versão | Uso |
|--------|--------|-----|
| camera | 0.12.0+2 (CameraX no Android) | preview, stream NV21/BGRA, captura |
| google_mlkit_face_detection | 0.14.0 | rosto, caixa, ângulos de Euler, pontos, contornos |
| path_provider | 2.1.6 | armazenamento privado (Fase B) |
| face_detection_tflite | 6.8.0 (Fase D) | MobileFaceNet embutido, embeddings de 192 dimensões |

Para atualizar, primeiro rode `flutter upgrade` e depois ajuste o `pubspec.yaml`.

### NDK Android

O Flutter 3.41 pede o NDK 28.2 por padrão, e o plugin `jni` (dependência de
`path_provider_android`) o fixa explicitamente. Para evitar um download de
cerca de 700 MB, o projeto força o NDK **29.0.14206865**, já instalado, em
`android/app/build.gradle.kts` e `android/build.gradle.kts`. Em outra
máquina, ajuste a versão ou remova esses blocos para usar o padrão.

## Arquitetura

```
lib/
  core/face_observation.dart        modelo de rosto/quadro (independente do ML Kit)
  diagnostics/detection_thresholds  limites ajustáveis em tempo de execução
  diagnostics/frame_metrics         FPS e tempo de processamento
  services/camera_service           inicialização, stream, captura, descarte
  services/face_detection_service   ML Kit: conversão de quadros e coordenadas
  services/face_position_validator  centralização, tamanho, ângulos, luz (puro)
  services/stability_tracker        estabilidade entre quadros (puro)
  services/live_face_analyzer       pipeline câmera → detector, sem fila
  services/image_rotation           rotação do quadro por plataforma
  ui/                               telas e overlay
```

Concorrência: apenas um quadro é analisado por vez. Quadros que chegam com o
detector ocupado são **descartados** (nunca enfileirados), e resultados de
sessões anteriores são ignorados por um contador de geração.

Coordenadas: o ML Kit devolve coordenadas da imagem já rotacionada para
retrato. Para a câmera frontal o eixo X é espelhado, de modo que validador e
overlay trabalham no mesmo espaço que o usuário vê no preview (efeito espelho).

## Parâmetros de posicionamento

Todos são ajustáveis em **Diagnóstico → Ajustar limites e calibrar**, sem
recompilar. Os valores ficam só em memória e voltam ao padrão ao reabrir o app.

| Parâmetro | Padrão | Significado |
|-----------|--------|-------------|
| Tolerância X/Y do centro | 0,10 | desvio máximo do centro do rosto em relação ao centro da moldura (fração do quadro) |
| Proporção do rosto | 0,38 – 0,70 | largura do rosto ÷ largura do quadro (abaixo: "Aproxime"; acima: "Afaste") |
| Frontal | \|X\|, \|Y\|, \|Z\| ≤ 10° | pose frontal |
| Laterais | 15° ≤ \|Y\| ≤ 30° | pose virada |
| Cima/baixo | 10° ≤ \|X\| ≤ 25° | modo avançado |
| Tempo de espera | 700 ms | condições atendidas continuamente antes da captura |
| Estabilidade | 0,03 do quadro / 4° | movimento máximo entre quadros |
| Luminância | 50 – 220 | média amostrada do quadro (0–255) |

**Calibração de sentido:** o sinal de Euler Y (direita/esquerda) e X
(cima/baixo) pode variar entre plataformas. Na tela de diagnóstico, vire a
cabeça para a sua direita (ou olhe para cima) e toque no botão de calibração.
O sinal medido passa a ser usado pelo validador.

Medições feitas:

| Aparelho | Virar à direita do usuário | Olhar para cima |
|----------|----------------------------|-----------------|
| Moto G53 5G (Android, câmera frontal) | Y **negativo** (confere com o padrão) | não medido |

## Limitações conhecidas

- Com **contornos** ativos, o ML Kit analisa só o rosto mais proeminente,
  então múltiplos rostos deixam de ser detectados. Por isso os contornos ficam
  desligados por padrão.
- O plugin `camera` usa o mesmo `ResolutionPreset` para preview, análise e
  captura. A taxa de análise é controlada pelo descarte de quadros.
- Detecção de rosto e ângulos **não** é prova de vida: uma foto ou vídeo de
  outra pessoa pode satisfazer as regras de posicionamento.
