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

model_files=(
  "encoder-epoch-12-avg-2-chunk-16-left-64.onnx"
  "decoder-epoch-12-avg-2-chunk-16-left-64.onnx"
  "joiner-epoch-12-avg-2-chunk-16-left-64.onnx"
  "tokens.txt"
  "bpe.model"
)

# Palavras de ativação em pt-BR. Formato oficial: tokens BPE + ":boosting" + "#threshold".
# "ULTRON" é a forma escrita; "UTRON" cobre a pronúncia brasileira /uˈtɾõ/, em que o L
# antes de consoante é vocalizado. O boosting menor da variante reflete que ela ainda é
# uma hipótese a validar em aparelho, não um resultado medido.
# shortcut: tokens fixos para o modelo Gigaspeech fixado; ao trocar MODEL_NAME, regenere
# com sentencepiece a partir de bpe.model e confirme que nenhum token vira <unk>.
keywords=(
  "▁ UL T RO N :1.5 #0.25"
  "▁ U T RO N :1.0 #0.25"
)

write_keywords() {
  printf '%s\n' "${keywords[@]}" > "$MODEL_DIR/keywords.txt"
  python3 - "$MODEL_DIR" "${keywords[@]}" <<'PY'
from pathlib import Path
import sys

model_dir = Path(sys.argv[1])
vocab = {
    line.split(maxsplit=1)[0]
    for line in (model_dir / "tokens.txt").read_text(encoding="utf-8").splitlines()
    if line
}
for line in sys.argv[2:]:
    tokens = [item for item in line.split() if not item.startswith((":", "#"))]
    invalid = [token for token in tokens if token not in vocab or token == "<unk>"]
    if not tokens or invalid:
        raise SystemExit(f"keywords.txt inválido ({line!r}): {invalid or 'vazio'}")
print("Palavras de ativação:", " | ".join(" ".join(
    item for item in line.split() if not item.startswith((":", "#")))
    for line in sys.argv[2:]))
PY
}

if [[ -s "$AAR_PATH" && -d "$MODEL_DIR" ]]; then
  complete=true
  for file in "${model_files[@]}"; do
    [[ -s "$MODEL_DIR/$file" ]] || complete=false
  done
  if [[ "$complete" == true ]]; then
    write_keywords
    echo "Modelo KWS sherpa-onnx já preparado em $MODEL_DIR"
    exit 0
  fi
fi

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
for file in "${model_files[@]}"; do
  if [[ ! -s "$SOURCE_DIR/$file" ]]; then
    echo "ERRO: arquivo do modelo ausente: $file" >&2
    exit 1
  fi
  cp "$SOURCE_DIR/$file" "$MODEL_DIR/$file"
done

write_keywords

test -s "$MODEL_DIR/keywords.txt"
echo "Modelo sherpa-onnx KWS preparado para uso offline em: $MODEL_DIR"
