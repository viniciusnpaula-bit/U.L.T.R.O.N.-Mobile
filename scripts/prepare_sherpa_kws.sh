#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="$ROOT/android"
ASSETS_DIR="$ANDROID_DIR/app/src/main/assets"
MODEL_NAME="sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01"
MODEL_DIR="$ASSETS_DIR/$MODEL_NAME"
ARCHIVE_NAME="$MODEL_NAME.tar.bz2"
MODEL_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/$ARCHIVE_NAME"
AAR_NAME="sherpa-onnx-1.13.8.aar"
AAR_PATH="$ANDROID_DIR/app/libs/$AAR_NAME"
AAR_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.8/$AAR_NAME"

command -v curl >/dev/null
command -v tar >/dev/null

# Always refresh the official AAR so Kotlin API classes and JNI binaries
# cannot come from different cached/local versions.
mkdir -p "$(dirname "$AAR_PATH")"
AAR_TMP="$(mktemp)"
trap 'rm -f "$AAR_TMP"' EXIT
curl --fail --location --retry 3 --retry-delay 2 "$AAR_URL" --output "$AAR_TMP"
python3 -m zipfile -t "$AAR_TMP" >/dev/null

# Fail early if the downloaded AAR does not contain the expected Kotlin API
# class and native JNI library for Android ARM devices.
python3 - "$AAR_TMP" <<'PY'
import sys
import zipfile
aar = zipfile.ZipFile(sys.argv[1])
names = set(aar.namelist())
required = {
    "classes.jar",
    "jni/arm64-v8a/libsherpa-onnx-jni.so",
    "jni/armeabi-v7a/libsherpa-onnx-jni.so",
}
missing = sorted(required - names)
if missing:
    raise SystemExit("AAR sherpa-onnx incompleto; faltando: " + ", ".join(missing))
classes = zipfile.ZipFile(__import__("io").BytesIO(aar.read("classes.jar")))
class_name = "com/k2fsa/sherpa/onnx/KeywordSpotterConfig.class"
if class_name not in classes.namelist():
    raise SystemExit("AAR não contém KeywordSpotterConfig.class")
PY
mv "$AAR_TMP" "$AAR_PATH"

required_files=(
  "encoder-epoch-12-avg-2-chunk-16-left-64.onnx"
  "decoder-epoch-12-avg-2-chunk-16-left-64.onnx"
  "joiner-epoch-12-avg-2-chunk-16-left-64.onnx"
  "tokens.txt"
  "bpe.model"
  "keywords.txt"
)
if [[ -s "$AAR_PATH" && -d "$MODEL_DIR" ]] && [[ "${#required_files[@]}" -gt 0 ]]; then
  complete=true
  for file in "${required_files[@]}"; do
    [[ -s "$MODEL_DIR/$file" ]] || complete=false
  done
  if [[ "$complete" == true ]]; then
    echo "Modelo KWS sherpa-onnx já preparado em $MODEL_DIR"
    exit 0
  fi
fi

python3 -m pip install --quiet --disable-pip-version-check sentencepiece==0.2.0

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
curl --fail --location --retry 3 --retry-delay 2 "$MODEL_URL" --output "$TMP_DIR/$ARCHIVE_NAME"
tar -xjf "$TMP_DIR/$ARCHIVE_NAME" -C "$TMP_DIR"
SOURCE_DIR="$TMP_DIR/$MODEL_NAME"
if [[ ! -d "$SOURCE_DIR" ]]; then
  SOURCE_DIR="$(find "$TMP_DIR" -type f -name "tokens.txt" -printf '%h\n' | head -1)"
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
