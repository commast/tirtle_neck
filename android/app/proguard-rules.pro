# TFLite / annotation 처리기 등 안드로이드 런타임에 없는 클래스에 대한 R8 경고 억제.
# (실제 런타임에서 호출되지 않음 — 컴파일 타임 어노테이션 프로세서 클래스들)
-dontwarn javax.annotation.processing.AbstractProcessor
-dontwarn javax.annotation.processing.SupportedAnnotationTypes
-dontwarn javax.lang.model.SourceVersion
-dontwarn javax.lang.model.element.Element
-dontwarn javax.lang.model.element.ElementKind
-dontwarn javax.lang.model.element.Modifier
-dontwarn javax.lang.model.type.TypeMirror
-dontwarn javax.lang.model.type.TypeVisitor
-dontwarn javax.lang.model.util.SimpleTypeVisitor8

# TFLite GPU delegate — 디바이스에 따라 클래스 존재 여부가 다름
-dontwarn org.tensorflow.lite.gpu.GpuDelegateFactory$Options

# TFLite 모델/플러그인은 리플렉션으로 호출되므로 보존
-keep class org.tensorflow.lite.** { *; }
