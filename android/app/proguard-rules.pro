# sherpa-onnx JNI accesses Kotlin data-class backing fields by their exact names.
# Keep the API package intact so native GetFieldID lookups remain stable.
-keep class com.k2fsa.sherpa.onnx.** { *; }
-keepclasseswithmembernames,includedescriptorclasses class com.k2fsa.sherpa.onnx.** {
    native <methods>;
}

# Preserve SQLCipher and sqflite_sqlcipher native JNI bindings in R8 release builds.
-keep class net.sqlcipher.** { *; }
-keep class net.zetetic.** { *; }
-keep class com.davidmartos96.sqflite_sqlcipher.** { *; }
-keep class io.flutter.plugins.pathprovider.** { *; }
-keepclasseswithmembernames,includedescriptorclasses class net.zetetic.** {
    native <methods>;
}

# Preserve PDFBox-Android text extraction in R8 release builds (optional image/encryption/desktop classes).
-dontwarn org.bouncycastle.**
-dontwarn org.apache.commons.logging.**
-dontwarn com.gemalto.jp2.**
-dontwarn java.awt.**
-dontwarn javax.imageio.**
-keep class com.tom_roush.pdfbox.** { *; }
-keep class com.tom_roush.fontbox.** { *; }
