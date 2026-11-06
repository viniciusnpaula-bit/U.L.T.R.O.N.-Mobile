#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="$ROOT/android"
ASSETS_DIR="$ANDROID_DIR/app/src/main/assets"
MODEL_NAME="sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01-mobile"
MODEL_DIR="$ASSETS_DIR/$MODEL_NAME"
ARCHIVE_NAME="$MODEL_NAME.tar.bz2"
MODEL_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/$ARCHIVE_NAME"

# The Flutter-generated settings file is not committed by this project. Add
# JitPack there (not in app/build.gradle, because Flutter may enforce settings repos).
SETTINGS_FILE="$ANDROID_DIR/settings.gradle"
if [[ ! -f "$SETTINGS_FILE" ]]; then
  SETTINGS_FILE="$ANDROID_DIR/settings.gradle.kts"
fi
if [[ ! -f "$SETTINGS_FILE" ]]; then
  echo "ERRO: android/settings.gradle não existe. Execute flutter create --platforms=android antes deste script." >&2
  exit 1
fi
if ! grep -q "jitpack.io" "$SETTINGS_FILE"; then
  python3 - "$SETTINGS_FILE" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
marker = "dependencyResolutionManagement"
pos = text.find(marker)
if pos < 0:
    raise SystemExit("Não foi encontrado dependencyResolutionManagement em android/settings.gradle")
repo = text.find("repositories", pos)
brace = text.find("{", repo)
if repo < 0 or brace < 0:
    raise SystemExit("Bloco repositories do dependencyResolutionManagement não encontrado")
text = text[:brace + 1] + '\n        maven { url "https://jitpack.io" }' + text[brace + 1:]
path.write_text(text)
PY
fi

required_files=(
  "encoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx"
  "decoder-epoch-12-avg-2-chunk-16-left-64.onnx"
  "joiner-epoch-12-avg-2-chunk-16-left-64.int8.onnx"
  "tokens.txt"
  "bpe.model"
  "keywords.txt"
)
if [[ -d "$MODEL_DIR" ]] && [[ "${#required_files[@]}" -gt 0 ]]; then
  complete=true
  for file in "${required_files[@]}"; do
    [[ -s "$MODEL_DIR/$file" ]] || complete=false
  done
  if [[ "$complete" == true ]]; then
    echo "Modelo KWS sherpa-onnx já preparado em $MODEL_DIR"
    exit 0
  fi
fi

command -v curl >/dev/null
command -v tar >/dev/null
python3 -m pip install --quiet --disable-pip-version-check sentencepiece==0.2.0

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
curl --fail --location --retry 3 --retry-delay 2 "$MODEL_URL" --output "$TMP_DIR/$ARCHIVE_NAME"
tar -xjf "$TMP_DIR/$ARCHIVE_NAME" -C "$TMP_DIR"
SOURCE_DIR="$TMP_DIR/$MODEL_NAME"
if [[ ! -d "$SOURCE_DIR" ]]; then
  SOURCE_DIR="$(find "$TMP_DIR" -type f -name "tokens.txt" -printf '%h\\n' | head -1)"
fi
if [[ -z "$SOURCE_DIR" || ! -d "$SOURCE_DIR" ]]; then
  echo "ERRO: diretório do modelo não encontrado no pacote KWS." >&2
  tar -tjf "$TMP_DIR/$ARCHIVE_NAME" | head -30 >&2
  exit 1
fi

mkdir -p "$MODEL_DIR"
for file in "${required_files[@]:0:5}"; do
  if [[ ! -s "$SOURCE_DIR/$file" ]]; then
    echo "ERRO: arquivo do modelo ausente: $file" >&2
    exit 1
  fi
  cp "$SOURCE_DIR/$file" "$MODEL_DIR/$file"
done

# sherpa-onnx uses SentencePiece BPE tokens for this English Zipformer KWS model.
# The acoustic model is local; tokenization is performed only at build time.
python3 - "$MODEL_DIR" <<'PY'
from pathlib import Path
import sentencepiece as spm
import sys
model_dir = Path(sys.argv[1])
processor = spm.SentencePieceProcessor(model_file=str(model_dir / "bpe.model"))
pieces = processor.encode("ULTRON", out_type=str)
if not pieces:
    raise SystemExit("Não foi possível tokenizar a palavra de ativação ULTRON")
(model_dir / "keywords.txt").write_text(" ".join(pieces) + "\n", encoding="utf-8")
print("Palavra de ativação tokenizada:", " ".join(pieces))
PY

test -s "$MODEL_DIR/keywords.txt"
echo "Modelo sherpa-onnx KWS preparado para uso offline em: $MODEL_DIR"
