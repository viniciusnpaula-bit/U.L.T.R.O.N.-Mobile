# sherpa-onnx JNI accesses Kotlin data-class backing fields by their exact names.
# Keep the API package intact so native GetFieldID lookups remain stable.
-keep class com.k2fsa.sherpa.onnx.** { *; }
-keepclasseswithmembernames,includedescriptorclasses class com.k2fsa.sherpa.onnx.** {
    native <methods>;
}
